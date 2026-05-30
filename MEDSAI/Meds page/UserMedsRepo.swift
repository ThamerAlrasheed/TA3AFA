import Foundation
import Combine
import Supabase

// MARK: - Repo (per-user, Supabase-backed)
@MainActor
final class UserMedsRepo: ObservableObject {
    private struct UserMedicationUpsertPayload: Encodable {
        let id: String
        let user_id: String
        let medication_id: String?
        let dosage: String
        let frequency_per_day: Int
        let frequency_hours: Int?
        let food_rule: String
        let dosage_times: [String]?
        let is_prn: Bool
        let is_manual: Bool
        let is_manual_schedule: Bool
        let medication_name: String
        let source_type: String
        let medication_form: String?
        let strength_value: Double?
        let strength_unit: String?
        let dose_amount: Double?
        let dose_amount_unit: String?
        let dose_quantity: Double?
        let dose_unit: String?
        let dose_quantity_unit: String?
        let strength_amount: Double?
        let parsed_strength_unit: String?
        let concentration_amount: Double?
        let concentration_unit: String?
        let route: String?
        let application_area: String?
        let dose_display: String?
        let food_rule_source: String?
        let dose_details_source: String?
        let is_dose_auto_filled: Bool
        let dose_details_confirmed_by_user: Bool
        let schedule_mode: String
        let times_per_day: Int?
        let times_per_week: Int?
        let selected_weekdays: [Int]?
        let interval_days: Int?
        let reminders_enabled: Bool
        let caregiver_reminders_enabled: Bool?
        let visual_shape: String?
        let visual_color: String?
        let visual_background_color: String?
        let refill_reminder_enabled: Bool
        let refill_current_supply: Double?
        let refill_supply_unit: String?
        let refill_threshold_quantity: Double?
        let refill_estimated_runout_date: String?
        let refill_reminder_date: String?
        let refill_reminder_mode: String?
        let refill_notes: String?
        let scan_source: String?
        let scan_confidence: Double?
        let scan_confirmed_by_user: Bool?
        let scan_extracted_fields: MedicationExtractedFields?
        let scan_candidate_snapshot: [MedicationScanCandidate]?
        let custom_form_text: String?
        let custom_unit_text: String?
        let source_metadata: String?
        let start_date: String
        let end_date: String
        let notes: String?
        let is_active: Bool
    }

    private struct LegacyUserMedicationUpsertPayload: Encodable {
        let id: String
        let user_id: String
        let medication_id: String?
        let name: String
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
        let visual_shape: String?
        let visual_color: String?
        let visual_background_color: String?
        let medication_form: String?
    }

    private struct ArchivePayload: Encodable {
        let is_active: Bool
    }

    @Published private(set) var meds: [LocalMed] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedOnce = false
    @Published private(set) var errorMessage: String?
    @Published var saveErrorMessage: String?
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
    private var lastSafetyWarningMedicationIDs: Set<String> = []

    init() {
        NotificationCenter.default.publisher(for: NSNotification.Name("SupabaseContextChanged"))
            .sink { [weak self] _ in
                Task {
                    await self?.fetchMeds()
                }
            }
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
        guard isSignedIn else {
            meds = []
            errorMessage = nil
            isLoading = false
            return
        }
        Task { await fetchMeds() }
    }

    func fetchMeds() async {
        let ownerContext: MedicationOwnerContext
        do {
            ownerContext = try supabase.resolveMedicationOwnerContext()
        } catch {
            print("MED FETCH DEBUG error resolving owner:", error)
            isSignedIn = false
            meds = []
            errorMessage = nil
            isLoading = false
            return
        }

        let uidString = supabase.ownerIDString(from: ownerContext).lowercased()
        isSignedIn = true

        print("MED FETCH DEBUG")
        print("currentAuthUserID:", supabase.authenticatedUserID as Any)
        print("activePatientID:", supabase.activePatientID as Any)
        print("resolvedFetchOwnerID:", uidString)
        print("fetch mode:", debugCareContextMode())

        // Only show full-screen loading on initial load (when we have no data yet)
        let isFirstLoad = !hasLoadedOnce && meds.isEmpty
        if isFirstLoad {
            isLoading = true
        }
        errorMessage = nil
        // DO NOT clear meds here — keep last-known-good state visible
        defer {
            isLoading = false
        }

        do {
            switch ownerContext {
            case .patient:
                let context = try await self.supabase.fetchPatientMedicationContext()
                self.canAddMeds = context.canAddMeds
                self.canManageCalendar = context.canManageCalendar
                self.notifyMeds = context.notifyMeds
                self.notifyAppointments = context.notifyAppointments
                let loadedMeds = context.medications.compactMap { LocalMed(row: $0) }
                #if DEBUG
                debugMedicationLoad(rows: context.medications, loadedMeds: loadedMeds, source: "patient-medications")
                #endif
                self.meds = loadedMeds
                self.hasLoadedOnce = true
                NotificationsManager.shared.refreshMedicationNotifications(for: loadedMeds, reason: "patient_meds_loaded")
                await refreshSafetyWarnings(for: loadedMeds)
                return

            case .selfUser:
                self.canAddMeds = true
                self.canManageCalendar = true
                self.notifyMeds = true
                self.notifyAppointments = true

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
                #if DEBUG
                debugMedicationLoad(rows: rows, loadedMeds: loadedMeds, source: "user_medications")
                #endif
                self.meds = loadedMeds
                self.hasLoadedOnce = true
                NotificationsManager.shared.refreshMedicationNotifications(for: loadedMeds, reason: "self_meds_loaded")
                await refreshSafetyWarnings(for: loadedMeds)
            }
        } catch is CancellationError {
            #if DEBUG
            print("fetchMeds cancelled for \(uidString). Keeping \(meds.count) existing meds.")
            #endif
            // Keep old data — do NOT clear meds
        } catch {
            print("MED FETCH ERROR:", error)
            // Only set error if we never successfully loaded
            if !hasLoadedOnce {
                errorMessage = "Unable to fetch medications (\(error.localizedDescription))."
            }
            // Keep old meds visible
        }
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
            lastSafetyWarningMedicationIDs = []
            return
        }

        let ids = Set(meds.map(\.id))
        guard ids != lastSafetyWarningMedicationIDs else { return }
        guard !isRefreshingSafetyWarnings else { return }

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
        lastSafetyWarningMedicationIDs = ids

        do {
            let response = try await DrugInfo.checkSafety(
                patientId: supabase.currentUserID?.uuidString.lowercased(),
                deviceToken: supabase.patientDeviceToken,
                medications: inputs,
                lang: "English"
            )

            safetySourceTrace = response.source_trace
            safetyWarningsByMedID = Self.mapWarnings(response.warnings, to: meds)
        } catch is CancellationError {
            #if DEBUG
            print("refresh safety warnings cancelled")
            #endif
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
        let ownerContext: MedicationOwnerContext
        do {
            ownerContext = try supabase.resolveMedicationOwnerContext()
        } catch {
            print("MED SAVE ERROR resolving owner:", error)
            saveErrorMessage = error.localizedDescription
            return
        }
        let uidString = supabase.ownerIDString(from: ownerContext).lowercased()

        #if DEBUG
        print("FAMILY MED SAVE DEBUG")
        print("selectedContext:", debugSelectedContext())
        print("auth.uid:", supabase.authenticatedUserID as Any)
        print("activePatientID:", supabase.activePatientID as Any)
        print("activePatientName:", AppSettings.shared.activePatientName as Any)
        print("resolvedOwnerID:", uidString)
        print("isSelfMode:", supabase.activePatientID == nil && !supabase.isPatientMode)
        print("isFamilyMemberMode:", supabase.activePatientID != nil)
        print("save route:", debugSaveRoute())
        print("payload medication_name:", med.name)
        print("payload user_id:", uidString)
        debugMedicationSaveStarted(med, ownerID: uidString, endpoint: supabase.isPatientMode || supabase.activePatientID != nil ? "patient-medications" : "user_medications")
        #endif

        if case .patient = ownerContext {
            guard canAddMeds else {
                saveErrorMessage = medicationPermissionErrorMessage()
                return
            }

            do {
                try await supabase.savePatientMedication(med)
                await fetchMeds()
                NotificationCenter.default.post(name: .medicationsDidChange, object: nil)
                #if DEBUG
                debugMedicationRefreshStatus(errorMessage)
                #endif
                print("MED SAVE SUCCESS id:", med.id)
            } catch {
                #if DEBUG
                print("FAMILY MED SAVE ERROR:", error)
                if let postgrestError = error as? PostgrestError {
                    print("PostgREST code:", postgrestError.code as Any)
                    print("PostgREST message:", postgrestError.message)
                    print("PostgREST detail:", postgrestError.detail as Any)
                    print("PostgREST hint:", postgrestError.hint as Any)
                }
                debugMedicationSaveFailure(med, ownerID: uidString, table: "patient-medications", error: "\(error)")
                #else
                print("⚠️ patient add med failed:", error)
                #endif
                saveErrorMessage = medicationSaveMessage(for: error, isPatientContext: true)
            }
            return
        }
        
        // Identified meds stay linked to catalog. Manual meds intentionally save without
        // medication_id so they are not blocked by catalog lookup/upsert failures.
        var finalMedId = med.catalogId

        if med.sourceType == .identified && finalMedId == nil {
            do {
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

        if med.sourceType == .identified && finalMedId == nil {
            saveErrorMessage = localizedMedicationSaveError()
            #if DEBUG
            debugMedicationSaveFailure(med, ownerID: uidString, table: "user_medications", error: "identified medication missing catalog id")
            #endif
            return
        }

        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withFullDate]

        let payload = userMedicationPayload(for: med, ownerID: uidString, medicationID: finalMedId, formatter: isoFmt)

        print("MED SAVE DEBUG")
        print("currentAuthUserID:", supabase.authenticatedUserID as Any)
        print("activePatientID:", supabase.activePatientID as Any)
        print("resolvedOwnerID:", uidString)
        print("mode:", debugCareContextMode())
        print("payload user_id:", payload.user_id)
        print("medication_name:", payload.medication_name as Any)
        print("medication_id:", payload.medication_id as Any)
        print("is_active:", payload.is_active as Any)
        print("dosage_times:", payload.dosage_times as Any)
        print("frequency_per_day:", payload.frequency_per_day as Any)

        do {
            let savedRows: [LocalMed.DBRow] = try await supabase.client
                .from("user_medications")
                .upsert(payload)
                .select()
                .execute()
                .value

            print("MED SAVE SUCCESS rows:", savedRows.count)
            print("MED SAVE SUCCESS first:", savedRows.first as Any)

            await fetchMeds()
            NotificationCenter.default.post(name: .medicationsDidChange, object: nil)
            #if DEBUG
            debugMedicationRefreshStatus(errorMessage)
            #endif
        } catch {
            if shouldRetryLegacyMedicationSave(error) {
                do {
                    #if DEBUG
                    debugMedicationSaveFailure(med, ownerID: uidString, table: "user_medications", error: "full payload failed; retrying legacy payload: \(error)")
                    #endif
                    let legacyRow = legacyUserMedicationPayload(for: med, ownerID: uidString, medicationID: finalMedId, formatter: isoFmt)
                    let savedRows: [LocalMed.DBRow] = try await supabase.client
                        .from("user_medications")
                        .upsert(legacyRow)
                        .select()
                        .execute()
                        .value
                    print("MED SAVE SUCCESS rows:", savedRows.count)
                    print("MED SAVE SUCCESS first:", savedRows.first as Any)

                    await fetchMeds()
                    NotificationCenter.default.post(name: .medicationsDidChange, object: nil)
                    #if DEBUG
                    debugMedicationRefreshStatus(errorMessage)
                    #endif
                    return
                } catch {
                    #if DEBUG
                    debugMedicationSaveFailure(med, ownerID: uidString, table: "user_medications", error: "legacy payload failed: \(error)")
                    #else
                    print("⚠️ add med failed:", error)
                    #endif
                    saveErrorMessage = localizedMedicationSaveError()
                    return
                }
            }

            #if DEBUG
            debugMedicationSaveFailure(med, ownerID: uidString, table: "user_medications", error: "\(error)")
            #else
            print("⚠️ add med failed:", error)
            #endif
            saveErrorMessage = localizedMedicationSaveError()
        }
    }

    private func userMedicationPayload(
        for med: LocalMed,
        ownerID uidString: String,
        medicationID finalMedId: String?,
        formatter isoFmt: ISO8601DateFormatter
    ) -> UserMedicationUpsertPayload {
        let normalizedTimesPerDay = med.dosageTimes.isEmpty ? med.timesPerDay : med.dosageTimes.count

        return UserMedicationUpsertPayload(
                id: med.id,
                user_id: uidString,
                medication_id: finalMedId,
                dosage: med.dosage,
                frequency_per_day: med.frequencyPerDay,
                frequency_hours: med.minIntervalHours,
                food_rule: med.foodRule.rawValue,
                dosage_times: med.dosageTimes.isEmpty ? nil : med.dosageTimes,
                is_prn: med.asNeeded,
                is_manual: med.sourceType == .manual,
                is_manual_schedule: med.isManualSchedule,
                medication_name: med.name,
                source_type: med.sourceType.rawValue,
                medication_form: med.medicationForm,
                strength_value: med.strengthValue,
                strength_unit: med.strengthUnit,
                dose_amount: med.doseAmount,
                dose_amount_unit: med.doseAmountUnit,
                dose_quantity: med.doseQuantity,
                dose_unit: med.doseUnit,
                dose_quantity_unit: med.doseQuantityUnit,
                strength_amount: med.strengthAmount,
                parsed_strength_unit: med.parsedStrengthUnit,
                concentration_amount: med.concentrationAmount,
                concentration_unit: med.concentrationUnit,
                route: med.route,
                application_area: med.applicationArea,
                dose_display: med.doseDisplay,
                food_rule_source: med.foodRuleSource,
                dose_details_source: med.doseDetailsSource,
                is_dose_auto_filled: med.isDoseAutoFilled,
                dose_details_confirmed_by_user: med.doseDetailsConfirmedByUser,
                schedule_mode: med.scheduleMode.storageValue,
                times_per_day: normalizedTimesPerDay,
                times_per_week: med.timesPerWeek,
                selected_weekdays: med.selectedWeekdays.isEmpty ? nil : med.selectedWeekdays,
                interval_days: med.intervalDays,
                reminders_enabled: med.remindersEnabled,
                caregiver_reminders_enabled: med.caregiverRemindersEnabled,
                visual_shape: med.visualShape,
                visual_color: med.visualColor,
                visual_background_color: med.visualBackgroundColor,
                refill_reminder_enabled: med.refillReminderEnabled,
                refill_current_supply: med.refillCurrentSupply,
                refill_supply_unit: med.refillSupplyUnit,
                refill_threshold_quantity: med.refillThresholdQuantity,
                refill_estimated_runout_date: dateOnlyString(med.refillEstimatedRunoutDate),
                refill_reminder_date: dateTimeString(med.refillReminderDate),
                refill_reminder_mode: med.refillReminderMode,
                refill_notes: normalizedNotes(med.refillNotes),
                scan_source: med.scanSource ?? "manual",
                scan_confidence: med.scanConfidence,
                scan_confirmed_by_user: med.scanConfirmedByUser ?? false,
                scan_extracted_fields: med.scanExtractedFields,
                scan_candidate_snapshot: med.scanCandidateSnapshot,
                custom_form_text: med.customFormText,
                custom_unit_text: med.customUnitText,
                source_metadata: med.sourceMetadata,
                start_date: isoFmt.string(from: med.startDate),
                end_date: isoFmt.string(from: med.endDate),
                notes: normalizedNotes(med.notes),
                is_active: true
            )
    }

    private func legacyUserMedicationPayload(
        for med: LocalMed,
        ownerID uidString: String,
        medicationID finalMedId: String?,
        formatter isoFmt: ISO8601DateFormatter
    ) -> LegacyUserMedicationUpsertPayload {
        #if DEBUG
        print("Legacy medication payload visual fields")
        print("  visual_shape:", med.visualShape as Any)
        print("  visual_color:", med.visualColor as Any)
        print("  visual_background_color:", med.visualBackgroundColor as Any)
        #endif
        return LegacyUserMedicationUpsertPayload(
            id: med.id,
            user_id: uidString,
            medication_id: finalMedId,
            name: med.name,
            dosage: med.dosage,
            frequency_per_day: med.frequencyPerDay,
            frequency_hours: med.minIntervalHours,
            food_rule: legacyFoodRuleStorage(med.foodRule),
            dosage_times: med.dosageTimes.isEmpty ? nil : med.dosageTimes,
            is_prn: med.asNeeded,
            is_manual_schedule: med.isManualSchedule,
            start_date: isoFmt.string(from: med.startDate),
            end_date: isoFmt.string(from: med.endDate),
            notes: normalizedNotes(med.notes),
            is_active: true,
            visual_shape: med.visualShape,
            visual_color: med.visualColor,
            visual_background_color: med.visualBackgroundColor,
            medication_form: med.medicationForm
        )
    }

    func update(_ med: LocalMed) async { await add(med) }

    func delete(_ med: LocalMed) async {
        let ownerContext: MedicationOwnerContext
        do {
            ownerContext = try supabase.resolveMedicationOwnerContext()
        } catch {
            print("MED DELETE ERROR resolving owner:", error)
            saveErrorMessage = error.localizedDescription
            return
        }

        do {
            NotificationsManager.shared.cancelReminders(for: med.id)
            
            switch ownerContext {
            case .patient:
                try await supabase.deletePatientMedication(id: med.id)
                await fetchMeds()
                NotificationsManager.shared.cancelReminders(for: med.id)
                
            case .selfUser:
                try await supabase.client
                    .from("user_medications")
                    .delete()
                    .eq("id", value: med.id)
                    .execute()
                await fetchMeds()
            }
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    func setArchived(_ med: LocalMed, archived: Bool) async {
        let ownerContext: MedicationOwnerContext
        do {
            ownerContext = try supabase.resolveMedicationOwnerContext()
        } catch {
            print("MED ARCHIVE ERROR resolving owner:", error)
            saveErrorMessage = error.localizedDescription
            return
        }

        do {
            if archived {
                NotificationsManager.shared.cancelReminders(for: med.id)
            }

            switch ownerContext {
            case .patient:
                try await supabase.archivePatientMedication(id: med.id, archived: archived)
                await fetchMeds()
                if archived {
                    NotificationsManager.shared.cancelReminders(for: med.id)
                }
                
            case .selfUser:
                try await supabase.client
                    .from("user_medications")
                    .update(ArchivePayload(is_active: !archived))
                    .eq("id", value: med.id)
                    .execute()
                await fetchMeds()
            }
        } catch {
            saveErrorMessage = error.localizedDescription
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
                    
                    // 2. Batched local notification refresh happens once after the loop.
                }
            }
            NotificationsManager.shared.refreshMedicationNotifications(for: meds, reason: "refresh_all_reminders")
        }
    }

    private func normalizedNotes(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func dateOnlyString(_ date: Date?) -> String? {
        guard let date else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    private func dateTimeString(_ date: Date?) -> String? {
        guard let date else { return nil }
        return ISO8601DateFormatter().string(from: date)
    }

    private func shouldRetryLegacyMedicationSave(_ error: Error) -> Bool {
        let text = "\(error)".lowercased()
        return text.contains("schema cache")
            || text.contains("pgrst")
            || text.contains("column")
            || text.contains("could not find")
            || text.contains("source_metadata")
            || text.contains("refill_")
            || text.contains("dose_details")
            || text.contains("dose_amount")
            || text.contains("concentration_")
            || text.contains("medication_name")
            || text.contains("source_type")
            || text.contains("is_manual")
            || text.contains("food_rule_enum")
            || text.contains("invalid input value for enum")
            || text.contains("scan_")
    }

    private func legacyFoodRuleStorage(_ rule: FoodRule) -> String {
        switch rule {
        case .beforeFood: return "beforeFood"
        case .withFood: return "withFood"
        case .afterFood: return "afterFood"
        case .none, .avoidWithFood, .notSure: return "none"
        }
    }

    private func localizedMedicationSaveError() -> String {
        UserDefaults.standard.string(forKey: "appearance.language") == "ar"
            ? "تعذر حفظ الدواء. يرجى المحاولة مرة أخرى."
            : "Couldn’t save the medication. Please try again."
    }

    private func medicationPermissionErrorMessage() -> String {
        UserDefaults.standard.string(forKey: "appearance.language") == "ar"
            ? "ليس لديك صلاحية لإدارة أدوية فرد العائلة هذا."
            : "You do not have permission to manage medications for this family member."
    }

    private func medicationSaveMessage(for error: Error, isPatientContext: Bool) -> String {
        let message = "\(error)".lowercased()
        if isPatientContext,
           message.contains("permission")
            || message.contains("not allowed")
            || message.contains("403")
            || message.contains("access") {
            return medicationPermissionErrorMessage()
        }
        return localizedMedicationSaveError()
    }

    private func debugCareContextMode() -> String {
        switch supabase.resolveActiveCareContext() {
        case .selfUser:
            return "self"
        case .managedPatient:
            return "authenticated caregiver"
        case .linkedPatient:
            return "care-code linked patient"
        case .none:
            return "none"
        }
    }

    private func debugSaveRoute() -> String {
        switch supabase.resolveActiveCareContext() {
        case .selfUser:
            return "direct user_medications"
        case .managedPatient:
            return "patient-medications edge function (authenticated caregiver target_patient_id)"
        case .linkedPatient:
            return "patient-medications edge function (care-code device token)"
        case .none:
            return "none"
        }
    }

    #if DEBUG
    private func debugMedicationSaveStarted(_ med: LocalMed, ownerID: String, endpoint: String) {
        print(debugMedicationLines(
            title: "Medication save started",
            med: med,
            ownerID: ownerID,
            endpoint: endpoint,
            status: nil,
            responseBody: nil
        ).joined(separator: "\n"))
    }

    private func debugMedicationSaveFailure(_ med: LocalMed, ownerID: String, table: String, error: String) {
        print(debugMedicationLines(
            title: "Medication save failed",
            med: med,
            ownerID: ownerID,
            endpoint: table,
            status: "unavailable",
            responseBody: error
        ).joined(separator: "\n"))
    }

    private func debugMedicationRefreshStatus(_ error: String?) {
        let lines = [
            "Medication local refresh finished",
            "finalLocalRefreshStatus: \(error == nil ? "success" : "failed")",
            "refreshError: \(error ?? "nil")",
            "loadedMedicationCount: \(meds.count)"
        ]
        print(lines.joined(separator: "\n"))
    }

    private func debugMedicationLoad(rows: [LocalMed.DBRow], loadedMeds: [LocalMed], source: String) {
        let missingMedicationID = rows.filter { $0.medication_id == nil }.count
        let missingVisualFields = rows.filter {
            $0.visual_shape == nil || $0.visual_color == nil || $0.visual_background_color == nil
        }.count
        let missingRefillFields = rows.filter { $0.refill_reminder_enabled == nil }.count
        let missingScheduleMode = rows.filter { $0.schedule_mode == nil }.count
        let mappedModes = loadedMeds.map {
            "\($0.name)=\($0.scheduleMode.storageValue) weekdays=\($0.selectedWeekdays) visual=(\($0.visualShape ?? "nil"),\($0.visualColor ?? "nil"),\($0.visualBackgroundColor ?? "nil")) visualFallback=\($0.visualShape == nil || $0.visualColor == nil || $0.visualBackgroundColor == nil) refill=(enabled:\($0.refillReminderEnabled),mode:\($0.refillReminderMode ?? "nil"),supply:\($0.refillCurrentSupply != nil),threshold:\($0.refillThresholdQuantity != nil),date:\($0.refillReminderDate != nil))"
        }
        print("""
        Medication load/decode
        source: \(source)
        recordCount: \(rows.count)
        loadedCount: \(loadedMeds.count)
        decodeFailures: \(rows.count - loadedMeds.count)
        recordsMissingMedicationId: \(missingMedicationID)
        recordsMissingVisualFields: \(missingVisualFields)
        recordsMissingRefillFields: \(missingRefillFields)
        recordsMissingScheduleMode: \(missingScheduleMode)
        decoded visual/refill fields on Meds load: \(mappedModes)
        """)
    }

    private func debugMedicationLines(
        title: String,
        med: LocalMed,
        ownerID: String,
        endpoint: String,
        status: String?,
        responseBody: String?
    ) -> [String] {
        let medicationNamePresent = !med.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let strengthText = "\(med.strengthValue.map { String($0) } ?? "nil") \(med.strengthUnit ?? "nil")"
        let doseText = "\(med.doseQuantity.map { String($0) } ?? "nil") \(med.doseUnit ?? "nil")"
        var lines: [String] = []
        lines.append(title)
        lines.append("selectedContext: \(debugSelectedContext())")
        lines.append("auth.uid: \(supabase.authenticatedUserID?.uuidString.lowercased() ?? "nil")")
        lines.append("activePatientID: \(supabase.activePatientID?.uuidString.lowercased() ?? "nil")")
        lines.append("careCodeActive: \(supabase.isPatientMode)")
        lines.append("ownerID: \(ownerID)")
        lines.append("medicationNamePresent: \(medicationNamePresent)")
        lines.append("medicationIdPresent: \(med.catalogId != nil)")
        lines.append("medicationId: \(med.catalogId ?? "nil")")
        lines.append("isManual: \(med.sourceType == .manual)")
        lines.append("sourceType: \(med.sourceType.rawValue)")
        lines.append("medicationForm: \(med.medicationForm ?? "nil")")
        lines.append("strength: \(strengthText)")
        lines.append("dose: \(doseText)")
        lines.append("doseDisplay: \(med.doseDisplay ?? "nil")")
        lines.append("doseDetailsSource: \(med.doseDetailsSource ?? "nil") autoFilled=\(med.isDoseAutoFilled) confirmed=\(med.doseDetailsConfirmedByUser)")
        lines.append("scheduleMode: \(med.scheduleMode.storageValue)")
        lines.append("selectedWeekdays: \(med.selectedWeekdays)")
        lines.append("isPRN/asNeeded: \(med.asNeeded || med.scheduleMode.isPRN)")
        lines.append("doseTimes: \(med.dosageTimes)")
        lines.append("doseTimesCount: \(med.dosageTimes.count)")
        lines.append("foodRule: \(med.foodRule.rawValue)")
        lines.append("startDate: \(debugDate(med.startDate))")
        lines.append("endDatePresent: true")
        lines.append("remindersEnabled: \(med.remindersEnabled)")
        lines.append("visualShape: \(med.visualShape ?? "nil")")
        lines.append("visualColor: \(med.visualColor ?? "nil")")
        lines.append("visualBackgroundColor: \(med.visualBackgroundColor ?? "nil")")
        lines.append("visualFieldsPresent: \(med.visualShape != nil && med.visualColor != nil && med.visualBackgroundColor != nil)")
        lines.append("refill_enabled: \(med.refillReminderEnabled)")
        lines.append("refill_current_supply present: \(med.refillCurrentSupply != nil)")
        lines.append("refill_threshold present: \(med.refillThresholdQuantity != nil)")
        lines.append("refill_reminder_mode: \(med.refillReminderMode ?? "nil")")
        lines.append("refill_reminder_date present: \(med.refillReminderDate != nil)")
        lines.append("scanSource: \(med.scanSource ?? "nil")")
        lines.append("scanConfidence: \(med.scanConfidence.map { String($0) } ?? "nil")")
        lines.append("scanConfirmedByUser: \(med.scanConfirmedByUser.map { String($0) } ?? "nil")")
        lines.append("payloadKeys: \(debugPayloadKeys(for: endpoint))")
        lines.append("endpoint/table/EdgeFunction: \(endpoint)")
        if let status {
            lines.append("httpStatusCode: \(status)")
        }
        if let responseBody {
            lines.append("decodedResponseBody: \(responseBody)")
        }
        return lines
    }

    private func debugSelectedContext() -> String {
        switch supabase.resolveActiveCareContext() {
        case let .selfUser(userId):
            return "self user \(userId.uuidString.lowercased())"
        case let .managedPatient(patientId, caregiverUserId):
            return "managed patient \(patientId.uuidString.lowercased()) caregiver \(caregiverUserId.uuidString.lowercased())"
        case let .linkedPatient(patientId, _):
            return "linked patient \(patientId.uuidString.lowercased())"
        case .none:
            return "none"
        }
    }

    private func debugPayloadKeys(for endpoint: String) -> String {
        if endpoint == "patient-medications" {
            return "action,device_token,target_patient_id,medication(id,medication_id,name,dosage,frequency_per_day,frequency_hours,dosage_times,is_prn,is_manual,is_manual_schedule,medication_name,source_type,medication_form,strength_value,strength_unit,dose_amount,dose_amount_unit,dose_quantity,dose_unit,dose_quantity_unit,strength_amount,parsed_strength_unit,concentration_amount,concentration_unit,route,application_area,dose_display,food_rule_source,dose_details_source,is_dose_auto_filled,dose_details_confirmed_by_user,schedule_mode,times_per_day,times_per_week,selected_weekdays,interval_days,reminders_enabled,caregiver_reminders_enabled,visual_shape,visual_color,visual_background_color,refill_reminder_enabled,refill_current_supply,refill_supply_unit,refill_threshold_quantity,refill_estimated_runout_date,refill_reminder_date,refill_reminder_mode,refill_notes,scan_source,scan_confidence,scan_confirmed_by_user,scan_extracted_fields,scan_candidate_snapshot,custom_form_text,custom_unit_text,source_metadata,start_date,end_date,notes,food_rule,rxcui,ingredients)"
        }
        return "id,user_id,medication_id,dosage,frequency_per_day,frequency_hours,food_rule,dosage_times,is_prn,is_manual,is_manual_schedule,medication_name,source_type,medication_form,strength_value,strength_unit,dose_amount,dose_amount_unit,dose_quantity,dose_unit,dose_quantity_unit,strength_amount,parsed_strength_unit,concentration_amount,concentration_unit,route,application_area,dose_display,food_rule_source,dose_details_source,is_dose_auto_filled,dose_details_confirmed_by_user,schedule_mode,times_per_day,times_per_week,selected_weekdays,interval_days,reminders_enabled,caregiver_reminders_enabled,visual_shape,visual_color,visual_background_color,refill_reminder_enabled,refill_current_supply,refill_supply_unit,refill_threshold_quantity,refill_estimated_runout_date,refill_reminder_date,refill_reminder_mode,refill_notes,scan_source,scan_confidence,scan_confirmed_by_user,scan_extracted_fields,scan_candidate_snapshot,custom_form_text,custom_unit_text,source_metadata,start_date,end_date,notes,is_active"
    }

    private func debugDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
    #endif

}

extension Notification.Name {
    static let medicalProfileChanged = Notification.Name("MedicalProfileChanged")
}
