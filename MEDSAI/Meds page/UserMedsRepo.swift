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
    @Published private(set) var notifyMeds = true
    @Published private(set) var notifyAppointments = true

    private var supabase: SupabaseManager { .shared }
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: NSNotification.Name("SupabaseContextChanged"))
            .sink { [weak self] _ in Task { await self?.fetchMeds() } }
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
            // 1. Fetch Permission if needed (Only for patients or impersonated contexts)
            if uid != supabase.authenticatedUserID || supabase.isPatientMode {
                struct PermissionRow: Decodable {
                    let can_patient_add_meds: Bool
                    let notify_patient_meds: Bool
                    let notify_patient_appointments: Bool
                }
                let perms: [PermissionRow] = try await self.supabase.retry {
                    try await self.supabase.client
                        .from("caregiver_relations")
                        .select("can_patient_add_meds, notify_patient_meds, notify_patient_appointments")
                        .eq("patient_id", value: uidString)
                        .execute()
                        .value
                }
                
                if let first = perms.first {
                    self.canAddMeds = first.can_patient_add_meds
                    self.notifyMeds = first.notify_patient_meds
                    self.notifyAppointments = first.notify_patient_appointments
                } else {
                    self.canAddMeds = true
                    self.notifyMeds = true
                    self.notifyAppointments = true
                }
            } else {
                self.canAddMeds = true
                self.notifyMeds = true
                self.notifyAppointments = true
            }

            // 2. Fetch Meds
            let rows: [LocalMed.DBRow] = try await self.supabase.retry {
                try await self.supabase.client
                    .from("user_medications")
                    .select("*, medications(name, food_rule)")
                    .eq("user_id", value: uidString)
                    .eq("is_active", value: true)
                    .execute()
                    .value
            }
            self.meds = rows.compactMap { LocalMed(row: $0) }
        } catch {
            print("⚠️ fetchMeds failed for \(uidString):", error)
            errorMessage = "Unable to fetch medications (\(error.localizedDescription))."
        }
        isLoading = false
    }

    // MARK: - CRUD

    func add(_ med: LocalMed) async {
        guard let uid = supabase.currentUserID else { return }
        let uidString = uid.uuidString.lowercased()
        
        // 1. Ensure we have a medication_id to link to
        var finalMedId = med.catalogId
        
        // 1.1 Fallback: if somehow search didn't provide an ID, do a quick lookup by name
        if finalMedId == nil {
            struct MedIdRow: Decodable { let id: String }
            let lookup: [MedIdRow] = (try? await supabase.client
                .from("medications")
                .select("id")
                .ilike("name", pattern: med.name)
                .limit(1)
                .execute()
                .value) ?? []
            finalMedId = lookup.first?.id
        }
        
        guard let medIdToLink = finalMedId else {
            errorMessage = "Medication '\(med.name)' not found in the global catalog. Please search for it first."
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
                start_date: isoFmt.string(from: med.startDate),
                end_date: isoFmt.string(from: med.endDate),
                notes: normalizedNotes(med.notes),
                is_active: true
            )

            try await supabase.client
                .from("user_medications")
                .upsert(row)
                .execute()

            await fetchMeds()
        } catch {
            print("⚠️ add med failed:", error)
            errorMessage = error.localizedDescription
        }
    }

    func update(_ med: LocalMed) async { await add(med) }

    func delete(_ med: LocalMed) async {
        do {
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

    private func normalizedNotes(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
