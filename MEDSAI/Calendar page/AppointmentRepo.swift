import Foundation
import Combine

/// Supabase-backed repo for user appointments from the `appointments` table.
final class AppointmentsRepo: ObservableObject {
    private struct AppointmentInsertPayload: Encodable {
        let user_id: String
        let title: String
        let doctor_name: String
        let appointment_time: String
        let notes: String?
    }

    private struct AppointmentFullInsertPayload: Encodable {
        let user_id: String
        let title: String
        let doctor_name: String
        let appointment_type: String
        let appointment_time: String
        let location: String?
        let notes: String?
        let is_completed: Bool
    }

    private struct AppointmentUpdatePayload: Encodable {
        let title: String
        let doctor_name: String
        let appointment_time: String
        let notes: String?
    }

    private struct AppointmentFullUpdatePayload: Encodable {
        let title: String
        let doctor_name: String
        let appointment_type: String
        let appointment_time: String
        let location: String?
        let notes: String?
    }

    @Published private(set) var items: [Appointment] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var hasLoadedOnce: Bool = false
    @Published private(set) var errorMessage: String? = nil

    private var supabase: SupabaseManager { .shared }
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: NSNotification.Name("SupabaseContextChanged"))
            .sink { [weak self] _ in Task { await self?.fetchAppointments() } }
            .store(in: &cancellables)
    }

    var isSignedIn: Bool { supabase.currentUserID != nil }

    func start() {
        guard isSignedIn else {
            items = []
            errorMessage = nil
            isLoading = false
            return
        }
        Task { await fetchAppointments() }
    }

    @MainActor
    func fetchAppointments() async {
        guard let uid = supabase.currentUserID else {
            items = []
            errorMessage = nil
            isLoading = false
            return
        }
        let uidString = uid.uuidString.lowercased()

        // Only show full loading on first load
        let isFirstLoad = !hasLoadedOnce && items.isEmpty
        if isFirstLoad {
            isLoading = true
        }
        errorMessage = nil
        // DO NOT clear items — keep last-known-good state visible
        defer { isLoading = false }

        do {
            if supabase.isPatientMode || supabase.activePatientID != nil {
                self.items = try await self.supabase.fetchPatientAppointments()
                self.hasLoadedOnce = true
                return
            }

            let rows: [AppointmentRow] = try await self.supabase.retry {
                try await self.supabase.client
                    .from("appointments")
                    .select()
                    .eq("user_id", value: uidString)
                    .order("appointment_time")
                    .execute()
                    .value
            }
            self.items = rows.map { $0.toAppointment() }
            self.hasLoadedOnce = true
            
            // Sync Reminders
            for item in self.items {
                NotificationsManager.shared.updateAppointmentReminders(for: item, settings: AppSettings.shared)
            }
        } catch is CancellationError {
            #if DEBUG
            print("fetchAppointments cancelled for \(uidString). Keeping \(items.count) existing appointments.")
            #endif
            // Keep old data
        } catch {
            print("⚠️ fetchAppointments failed for \(uidString):", error)
            if !hasLoadedOnce {
                errorMessage = error.localizedDescription
            }
            // Keep old appointments visible
        }
    }

    func appointments(on date: Date) -> [Appointment] {
        let cal = Calendar.current
        return items.filter { cal.isDate($0.date, inSameDayAs: date) }
    }

    func add(title: String, type: AppointmentType, date: Date, location: String?, notes: String?, completion: ((Error?) -> Void)? = nil) {
        guard supabase.currentUserID != nil else {
            completion?(NSError(domain: "AppointmentsRepo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not signed in"]))
            return
        }
        Task {
            do {
                if supabase.isPatientMode || supabase.activePatientID != nil {
                    #if DEBUG
                    debugAppointmentWrite(route: "patient-medications", operation: "create", resolvedTargetPatientID: supabase.activePatientID ?? supabase.patientUserID)
                    #endif

                    try await supabase.savePatientAppointment(
                        id: nil,
                        title: title,
                        type: type,
                        date: date,
                        location: location,
                        notes: notes
                    )
                    await fetchAppointments()
                    completion?(nil)
                    return
                }

                guard let authUserID = supabase.authenticatedUserID else {
                    throw NSError(domain: "AppointmentsRepo", code: 401, userInfo: [NSLocalizedDescriptionKey: "User is not signed in."])
                }

                let uidString = authUserID.uuidString.lowercased()
                #if DEBUG
                debugAppointmentWrite(route: "appointments", operation: "create", resolvedTargetPatientID: authUserID)
                #endif

                try await insertSelfAppointment(
                    ownerID: uidString,
                    title: title,
                    type: type,
                    date: date,
                    location: location,
                    notes: notes
                )
                await fetchAppointments()
                completion?(nil)
            } catch {
                #if DEBUG
                if isRLSError(error), supabase.activePatientID == nil, !supabase.isPatientMode {
                    print("⚠️ Self appointment insert failed RLS. Check that payload owner column matches auth.uid() and policy WITH CHECK.")
                }
                #endif
                print("⚠️ add appointment failed:", error)
                completion?(error)
            }
        }
    }

    func update(id: String, title: String, type: AppointmentType, date: Date, location: String?, notes: String?, completion: ((Error?) -> Void)? = nil) {
        Task {
            do {
                if supabase.isPatientMode || supabase.activePatientID != nil {
                    #if DEBUG
                    debugAppointmentWrite(route: "patient-medications", operation: "update", resolvedTargetPatientID: supabase.activePatientID ?? supabase.patientUserID)
                    #endif

                    try await supabase.savePatientAppointment(
                        id: id,
                        title: title,
                        type: type,
                        date: date,
                        location: location,
                        notes: notes
                    )
                    await fetchAppointments()
                    completion?(nil)
                    return
                }

                #if DEBUG
                debugAppointmentWrite(route: "appointments", operation: "update", resolvedTargetPatientID: supabase.authenticatedUserID)
                #endif

                let data = AppointmentUpdatePayload(
                    title: title,
                    doctor_name: type.rawValue,
                    appointment_time: ISO8601DateFormatter().string(from: date),
                    notes: normalizedNotes(notes)
                )
                let fullData = AppointmentFullUpdatePayload(
                    title: title,
                    doctor_name: type.rawValue,
                    appointment_type: type.rawValue,
                    appointment_time: ISO8601DateFormatter().string(from: date),
                    location: normalizedNotes(location),
                    notes: normalizedNotes(notes)
                )
                do {
                    try await supabase.client
                        .from("appointments")
                        .update(fullData)
                        .eq("id", value: id)
                        .execute()
                } catch {
                    guard isMissingAppointmentBoardColumnError(error) else { throw error }
                    try await supabase.client
                        .from("appointments")
                        .update(data)
                        .eq("id", value: id)
                        .execute()
                }
                await fetchAppointments()
                completion?(nil)
            } catch {
                completion?(error)
            }
        }
    }

    @MainActor
    func delete(_ appointment: Appointment) async {
        do {
            if supabase.isPatientMode || supabase.activePatientID != nil {
                #if DEBUG
                debugAppointmentWrite(route: "patient-medications", operation: "delete", resolvedTargetPatientID: supabase.activePatientID ?? supabase.patientUserID)
                #endif

                try await supabase.deletePatientAppointment(id: appointment.id)
                await fetchAppointments()
                return
            }

            #if DEBUG
            debugAppointmentWrite(route: "appointments", operation: "delete", resolvedTargetPatientID: supabase.authenticatedUserID)
            #endif

            try await supabase.client
                .from("appointments")
                .delete()
                .eq("id", value: appointment.id)
                .execute()
            await fetchAppointments()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    @MainActor
    func refreshAllReminders() {
        for item in items {
            NotificationsManager.shared.updateAppointmentReminders(for: item, settings: AppSettings.shared)
        }
    }

    private func normalizedNotes(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func insertSelfAppointment(ownerID: String, title: String, type: AppointmentType, date: Date, location: String?, notes: String?) async throws {
        let isoDate = ISO8601DateFormatter().string(from: date)
        let normalized = normalizedNotes(notes)
        let row = AppointmentFullInsertPayload(
            user_id: ownerID,
            title: title,
            doctor_name: type.rawValue,
            appointment_type: type.rawValue,
            appointment_time: isoDate,
            location: normalizedNotes(location),
            notes: normalized,
            is_completed: false
        )

        do {
            try await supabase.client
                .from("appointments")
                .insert(row)
                .execute()
        } catch {
            guard isMissingAppointmentBoardColumnError(error) else {
                throw error
            }

            #if DEBUG
            print("appointments board columns are not in the schema cache; retrying self insert with legacy user_id ownership.")
            #endif

            let legacyRow = AppointmentInsertPayload(
                user_id: ownerID,
                title: title,
                doctor_name: type.rawValue,
                appointment_time: isoDate,
                notes: normalized
            )

            try await supabase.client
                .from("appointments")
                .insert(legacyRow)
                .execute()
        }
    }

    private func isMissingAppointmentBoardColumnError(_ error: Error) -> Bool {
        let text = "\(error)".lowercased()
        let missingBoardColumn = text.contains("appointment_type")
            || text.contains("location")
            || text.contains("is_completed")
        return missingBoardColumn
            && (text.contains("schema cache") || text.contains("could not find") || text.contains("pgrst204"))
    }

    private func isRLSError(_ error: Error) -> Bool {
        let text = "\(error)".lowercased()
        return text.contains("42501") || text.contains("row-level security")
    }

    #if DEBUG
    private func debugAppointmentWrite(route: String, operation: String, resolvedTargetPatientID: UUID?) {
        let mode: String
        if supabase.isPatientMode {
            mode = "care-code"
        } else if supabase.activePatientID != nil {
            mode = "caregiver"
        } else {
            mode = "self"
        }

        print("""
        appointment \(operation) started
        currentAuthUserID: \(supabase.authenticatedUserID?.uuidString.lowercased() ?? "nil")
        activePatientID: \(supabase.activePatientID?.uuidString.lowercased() ?? "nil")
        resolvedTargetPatientID: \(resolvedTargetPatientID?.uuidString.lowercased() ?? "nil")
        mode: \(mode)
        payload ownership: \(resolvedTargetPatientID?.uuidString.lowercased() ?? "nil")
        route: \(route)
        """)
    }
    #endif

}

// MARK: - DB Row Decodable

private struct AppointmentRow: Decodable {
    let id: String
    let title: String
    let doctor_name: String?
    let appointment_type: String?
    let appointment_time: String
    let location: String?
    let notes: String?
    let is_completed: Bool?

    func toAppointment() -> Appointment {
        let type = AppointmentType.fromString(appointment_type ?? doctor_name)
        let date = ISO8601DateFormatter().date(from: appointment_time) ?? Date()
        let n = (notes?.isEmpty == true) ? nil : notes
        return Appointment(id: id, title: title, type: type, date: date, location: location, notes: n)
    }
}

// MARK: - Appointment types (with emoji)

enum AppointmentType: String, Codable, CaseIterable, Identifiable, Equatable, Hashable {
    case therapy, doctor, lab, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .therapy: return "Therapy"
        case .doctor: return "Doctor"
        case .lab: return "Lab"
        case .other: return "Other"
        }
    }

    var emoji: String {
        switch self {
        case .therapy: return "💬"
        case .doctor: return "🩺"
        case .lab: return "🧪"
        case .other: return "📅"
        }
    }

    var sfSymbol: String {
        switch self {
        case .therapy: return "heart.text.square"
        case .doctor: return "stethoscope"
        case .lab: return "testtube.2"
        case .other: return "calendar.badge.clock"
        }
    }

    var label: String {
        "\(emoji) \(title)"
    }

    static func fromString(_ s: String?) -> AppointmentType {
        guard let s, let t = AppointmentType(rawValue: s) else { return .doctor }
        return t
    }
}

// MARK: - Model

struct Appointment: Identifiable, Equatable {
    let id: String
    let title: String
    let type: AppointmentType
    let date: Date
    let location: String?
    let notes: String?

    var titleWithEmoji: String { "\(type.label) • \(title)" }
}
