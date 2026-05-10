import Foundation
import Combine
import Supabase

// MARK: - Repo (per-user, Supabase-backed)
@MainActor
final class UserMedsRepo: ObservableObject {
    private struct UserMedicationUpsertPayload: Encodable {
        let id: String
        let user_id: String
        let medication_id: String
        let dosage: String
        let frequency_per_day: Int
        let frequency_hours: Int?
        let food_rule: String
        let dosage_times: [String]?
        let is_prn: Bool
        let is_manual_schedule: Bool
        let start_date: String
        let end_date: String
        let notes: String?
        let is_active: Bool
    }

    private struct ArchivePayload: Encodable {
        let is_active: Bool
    }

    @Published private(set) var meds: [LocalMed] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSignedIn = false
    @Published private(set) var canAddMeds = true
    @Published private(set) var canManageCalendar = true
    @Published private(set) var notifyMeds = true
    @Published private(set) var notifyAppointments = true
    @Published private(set) var safetyWarningsByMedID: [String: [SafetyWarning]] = [:]
    @Published private(set) var safetySourceTrace: [String] = []
    @Published private(set) var isRefreshingSafetyWarnings = false

    private var supabase: SupabaseManager { .shared }
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: NSNotification.Name("SupabaseContextChanged"))
            .sink { [weak self] _ in Task { await self?.fetchMeds() } }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSNotification.Name("UserRoutineChanged"))
            .sink { [weak self] _ in self?.refreshAllReminders() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .medicalProfileChanged)
            .sink { [weak self] _ in Task { await self?.refreshSafetyWarnings() } }
            .store(in: &cancellables)
    }

    func start() {
        isSignedIn = supabase.currentUserID != nil
        guard isSignedIn else { meds = []; errorMessage = nil; return }
        Task { await fetchMeds() }
    }

    func fetchMeds() async {
        guard let uid = supabase.currentUserID else { return }
        let uidString = uid.uuidString.lowercased()
        isLoading = true; errorMessage = nil
        do {
            if supabase.isPatientMode || supabase.activePatientID != nil {
                let context = try await self.supabase.fetchPatientMedicationContext()
                self.canAddMeds = context.canAddMeds
                self.canManageCalendar = context.canManageCalendar
                self.notifyMeds = context.notifyMeds
                self.notifyAppointments = context.notifyAppointments
                let loadedMeds = context.medications.compactMap { LocalMed(row: $0) }
                self.meds = loadedMeds
                isLoading = false
                await refreshSafetyWarnings(for: loadedMeds)
                return
            }

            // 1. Fetch Permission if needed (Only for patients or impersonated contexts)
            if uid != supabase.authenticatedUserID || supabase.isPatientMode {
                struct PermissionRow: Decodable {
                    let can_patient_add_meds: Bool
                    let can_patient_manage_calendar: Bool
                    let notify_patient_meds: Bool
                    let notify_patient_appointments: Bool
                }
                let perms: [PermissionRow] = try await self.supabase.retry {
                    try await self.supabase.client
                        .from("caregiver_relations")
                        .select("can_patient_add_meds, can_patient_manage_calendar, notify_patient_meds, notify_patient_appointments")
                        .eq("patient_id", value: uidString)
                        .execute()
                        .value
                }
                
                if let first = perms.first {
                    self.canAddMeds = first.can_patient_add_meds
                    self.canManageCalendar = first.can_patient_manage_calendar
                    self.notifyMeds = first.notify_patient_meds
                    self.notifyAppointments = first.notify_patient_appointments
                } else {
                    self.canAddMeds = true
                    self.canManageCalendar = true
                    self.notifyMeds = true
                    self.notifyAppointments = true
                }
            } else {
                self.canAddMeds = true
                self.canManageCalendar = true
                self.notifyMeds = true
                self.notifyAppointments = true
            }

            // 2. Fetch Meds
            let rows: [LocalMed.DBRow] = try await self.supabase.retry {
                try await self.supabase.client
                    .from("user_medications")
                    .select("*, medications(name, food_rule, rxcui, active_ingredients)")
                    .eq("user_id", value: uidString)
                    .eq("is_active", value: true)
                    .execute()
                    .value
            }
            let loadedMeds = rows.compactMap { LocalMed(row: $0) }
            self.meds = loadedMeds
            await refreshSafetyWarnings(for: loadedMeds)
        } catch {
            print("⚠️ fetchMeds failed for \(uidString):", error)
            errorMessage = "Unable to fetch medications (\(error.localizedDescription))."
        }
        isLoading = false
    }

    func safetyWarnings(for med: LocalMed) -> [SafetyWarning] {
        safetyWarningsByMedID[med.id] ?? []
    }

    func refreshSafetyWarnings() async {
        await refreshSafetyWarnings(for: meds)
    }

    private func refreshSafetyWarnings(for meds: [LocalMed]) async {
        guard !meds.isEmpty else {
            safetyWarningsByMedID = [:]
            safetySourceTrace = []
            return
        }

        let inputs = meds.map {
            SafetyMedicationInput(
                id: $0.id,
                name: $0.name,
                rxcui: $0.rxcui,
                ingredients: $0.ingredients ?? []
            )
        }

        isRefreshingSafetyWarnings = true
        defer { isRefreshingSafetyWarnings = false }

        do {
            let response = try await DrugInfo.checkSafety(
                patientId: supabase.currentUserID?.uuidString.lowercased(),
                deviceToken: supabase.patientDeviceToken,
                medications: inputs,
                lang: "English"
            )

            safetySourceTrace = response.source_trace
            safetyWarningsByMedID = Self.mapWarnings(response.warnings, to: meds)
        } catch {
            print("⚠️ refresh safety warnings failed:", error)
            safetyWarningsByMedID = [:]
            safetySourceTrace = []
        }
    }

    private static func mapWarnings(_ warnings: [SafetyWarning], to meds: [LocalMed]) -> [String: [SafetyWarning]] {
        var mapped: [String: [SafetyWarning]] = [:]

        for warning in warnings {
            for med in meds where warningApplies(warning, to: med) {
                mapped[med.id, default: []].append(warning)
            }
        }

        return mapped.mapValues { SafetyWarningPresentation.sorted($0) }
    }

    private static func warningApplies(_ warning: SafetyWarning, to med: LocalMed) -> Bool {
        if warning.affected_medication_ids?.contains(med.id) == true { return true }

        let medName = normalize(med.name)
        let warningMeds = warning.meds.map(normalize)
        if warningMeds.contains(medName) { return true }
        if warningMeds.contains(where: { !$0.isEmpty && (medName.contains($0) || $0.contains(medName)) }) { return true }

        let medIngredients = (med.ingredients ?? []).map(normalize)
        let warningIngredients = warning.ingredients.map(normalize)
        return !Set(medIngredients).isDisjoint(with: Set(warningIngredients))
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - CRUD

    func add(_ med: LocalMed) async {
        guard let uid = supabase.currentUserID else { return }
        let uidString = uid.uuidString.lowercased()

        if supabase.isPatientMode || supabase.activePatientID != nil {
            do {
                try await supabase.savePatientMedication(med)
                await fetchMeds()
            } catch {
                print("⚠️ patient add med failed:", error)
                errorMessage = error.localizedDescription
            }
            return
        }
        
        // 1. Ensure we have a medication_id to link to
        var finalMedId = med.catalogId
        
        // 1.1 Improved Link Logic: Search by name if ID is missing or if we want to be safe
        if finalMedId == nil {
            do {
                // Try to find or create in catalog
                // We'll use a placeholder DrugPayload if we don't have one, 
                // but usually the UI provides it from the search result.
                let dummyPayload = DrugPayload(
                    title: med.name,
                    strengths: [],
                    dosageForms: [],
                    foodRule: med.foodRule.rawValue,
                    minIntervalHours: nil,
                    ingredients: med.ingredients ?? [],
                    indications: [],
                    howToTake: [],
                    commonSideEffects: [],
                    importantWarnings: [],
                    interactionsToAvoid: [],
                    references: nil,
                    kbKey: nil,
                    rxcui: med.rxcui,
                    id: nil
                )
                
                let entry = try await MedCatalogRepo.shared.upsert(from: dummyPayload, searchedName: med.name)
                finalMedId = entry.payload.id?.uuidString
            } catch {
                print("⚠️ Failed to auto-catalog med: \(error)")
            }
        }
        
        guard let medIdToLink = finalMedId else {
            errorMessage = "Medication '\(med.name)' could not be found or created in the catalog."
            return
        }

        do {
            let isoFmt = ISO8601DateFormatter()
            isoFmt.formatOptions = [.withFullDate]

            let row = UserMedicationUpsertPayload(
                id: med.id,
                user_id: uidString,
                medication_id: medIdToLink,
                dosage: med.dosage,
                frequency_per_day: med.frequencyPerDay,
                frequency_hours: med.minIntervalHours,
                food_rule: med.foodRule.rawValue,
                dosage_times: med.dosageTimes.isEmpty ? nil : med.dosageTimes,
                is_prn: med.asNeeded,
                is_manual_schedule: med.isManualSchedule,
                start_date: isoFmt.string(from: med.startDate),
                end_date: isoFmt.string(from: med.endDate),
                notes: normalizedNotes(med.notes),
                is_active: true
            )

            try await supabase.client
                .from("user_medications")
                .upsert(row)
                .execute()

            NotificationsManager.shared.updateReminders(for: med)
            await fetchMeds()
        } catch {
            print("⚠️ add med failed:", error)
            errorMessage = error.localizedDescription
        }
    }

    func update(_ med: LocalMed) async { await add(med) }

    func delete(_ med: LocalMed) async {
        do {
            NotificationsManager.shared.cancelReminders(for: med.id)
            if supabase.isPatientMode || supabase.activePatientID != nil {
                try await supabase.deletePatientMedication(id: med.id)
                await fetchMeds()
                return
            }

            try await supabase.client
                .from("user_medications")
                .delete()
                .eq("id", value: med.id)
                .execute()
            await fetchMeds()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setArchived(_ med: LocalMed, archived: Bool) async {
        do {
            if archived {
                NotificationsManager.shared.cancelReminders(for: med.id)
            } else {
                NotificationsManager.shared.updateReminders(for: med)
            }

            if supabase.isPatientMode || supabase.activePatientID != nil {
                try await supabase.archivePatientMedication(id: med.id, archived: archived)
                await fetchMeds()
                return
            }

            try await supabase.client
                .from("user_medications")
                .update(ArchivePayload(is_active: !archived))
                .eq("id", value: med.id)
                .execute()
            await fetchMeds()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func refreshAllReminders() {
        let settings = AppSettings.shared
        
        Task {
            for med in meds {
                if !med.isArchived {
                    var currentMed = med
                    
                    // 1. If NOT manual, recalculate dosageTimes based on new routine
                    if !med.isManualSchedule {
                        let tempMed = Medication(
                            id: med.id,
                            name: med.name,
                            dosage: med.dosage,
                            frequencyPerDay: med.frequencyPerDay,
                            startDate: med.startDate,
                            endDate: med.endDate,
                            foodRule: med.foodRule,
                            notes: med.notes,
                            ingredients: med.ingredients,
                            minIntervalHours: med.minIntervalHours,
                            rxcui: med.rxcui,
                            dosageTimes: nil, // force recalc
                            asNeeded: med.asNeeded,
                            isManualSchedule: med.isManualSchedule
                        )
                        
                        let newTimes = Scheduler.preferredTimes(for: tempMed, on: Date().startOfDay, settings: settings)
                        let timeFmt = DateFormatter()
                        timeFmt.dateFormat = "HH:mm:ss"
                        let timesStrings = newTimes.map { timeFmt.string(from: $0) }
                        
                        currentMed.dosageTimes = timesStrings
                        
                        // Persist to Supabase
                        await add(currentMed)
                    }
                    
                    // 2. Update local notifications
                    NotificationsManager.shared.updateReminders(for: currentMed)
                }
            }
        }
    }

    private func normalizedNotes(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Notification.Name {
    static let medicalProfileChanged = Notification.Name("MedicalProfileChanged")
}
