import Foundation
import Supabase

/// Central manager for all PostgreSQL interactions via Supabase.
/// Replace the placeholder URL and key with your actual Supabase credentials.
final class SupabaseManager {
    struct CreateFamilyMemberRequest: Encodable {
        let firstName: String
        let lastName: String
        let dateOfBirth: String
        let allergies: [String]
        let conditions: [String]
        let canPatientAddMeds: Bool
        let canPatientManageCalendar: Bool
        let notifyPatientMeds: Bool
        let notifyPatientAppointments: Bool

        enum CodingKeys: String, CodingKey {
            case firstName = "first_name"
            case lastName = "last_name"
            case dateOfBirth = "date_of_birth"
            case allergies
            case conditions
            case canPatientAddMeds = "can_patient_add_meds"
            case canPatientManageCalendar = "can_patient_manage_calendar"
            case notifyPatientMeds = "notify_patient_meds"
            case notifyPatientAppointments = "notify_patient_appointments"
        }
    }

    struct CreateFamilyMemberResponse: Decodable {
        let patientID: String
        let code: String
        let expiresAt: String

        enum CodingKeys: String, CodingKey {
            case patientID = "patient_id"
            case code
            case expiresAt = "expires_at"
        }
    }

    struct RedeemCareCodeRequest: Encodable {
        let code: String
    }

    struct RedeemCareCodeResponse: Decodable {
        let patientID: String
        let deviceToken: String

        enum CodingKeys: String, CodingKey {
            case patientID = "patient_id"
            case deviceToken = "device_token"
        }
    }

    struct PatientMedicationContext {
        let medications: [LocalMed.DBRow]
        let canAddMeds: Bool
        let canManageCalendar: Bool
        let notifyMeds: Bool
        let notifyAppointments: Bool
    }

    private struct PatientMedicationRequest: Encodable {
        let action: String
        let deviceToken: String?
        let targetPatientID: String?
        let medication: PatientMedicationPayload?
        let appointment: PatientAppointmentPayload?
        let id: String?

        enum CodingKeys: String, CodingKey {
            case action
            case deviceToken = "device_token"
            case targetPatientID = "target_patient_id"
            case medication
            case appointment
            case id
        }
    }

    private struct PatientMedicationPayload: Encodable {
        let id: String
        let name: String
        let dosage: String
        let frequencyPerDay: Int
        let frequencyHours: Int?
        let startDate: String
        let endDate: String
        let notes: String?
        let foodRule: String

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case dosage
            case frequencyPerDay = "frequency_per_day"
            case frequencyHours = "frequency_hours"
            case startDate = "start_date"
            case endDate = "end_date"
            case notes
            case foodRule = "food_rule"
        }
    }

    private struct PatientMedicationFunctionResponse: Decodable {
        struct Permissions: Decodable {
            let can_patient_add_meds: Bool?
            let can_patient_manage_calendar: Bool?
            let notify_patient_meds: Bool?
            let notify_patient_appointments: Bool?
        }

        let medications: [LocalMed.DBRow]?
        let appointments: [PatientAppointmentRow]?
        let permissions: Permissions?
    }

    private struct PatientAppointmentPayload: Encodable {
        let id: String?
        let title: String
        let doctorName: String
        let appointmentTime: String
        let notes: String?

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case doctorName = "doctor_name"
            case appointmentTime = "appointment_time"
            case notes
        }
    }

    private struct PatientAppointmentRow: Decodable {
        let id: String
        let title: String
        let doctor_name: String?
        let appointment_time: String
        let notes: String?

        func toAppointment() -> Appointment {
            let type = AppointmentType.fromString(doctor_name)
            let date = ISO8601DateFormatter().date(from: appointment_time) ?? Date()
            let normalizedNotes = (notes?.isEmpty == true) ? nil : notes
            return Appointment(id: id, title: title, type: type, date: date, location: nil, notes: normalizedNotes)
        }
    }

    private struct FunctionErrorResponse: Decodable {
        let error: String
    }

    static let shared = SupabaseManager()

    private let supabaseURL = URL(string: "https://svucjnbwlcsaiaurdmab.supabase.co")!
    let supabaseKey = "sb_publishable_jEQs-Uecl0vce5rwqHq5zA_AW68TTrI"

    let client: SupabaseClient

    private init() {
        self.client = SupabaseClient(
            supabaseURL: supabaseURL, 
            supabaseKey: supabaseKey,
            options: .init(
                auth: .init(emitLocalSessionAsInitialSession: true)
            )
        )
    }

    // MARK: - Current User Helpers

    /// For patients logged in via care code (no Supabase Auth session).
    var patientUserID: UUID? {
        guard let str = UserDefaults.standard.string(forKey: "patientUserId") else { return nil }
        return UUID(uuidString: str)
    }

    var patientDeviceToken: String? {
        UserDefaults.standard.string(forKey: "deviceToken")
    }

    /// The patient ID currently being managed by a caregiver.
    var activePatientID: UUID? {
        get {
            guard let str = UserDefaults.standard.string(forKey: "activePatientId") else { return nil }
            return UUID(uuidString: str)
        }
        set {
            if let newValue = newValue {
                UserDefaults.standard.set(newValue.uuidString, forKey: "activePatientId")
            } else {
                UserDefaults.standard.removeObject(forKey: "activePatientId")
            }
            NotificationCenter.default.post(name: NSNotification.Name("SupabaseContextChanged"), object: nil)
        }
    }

    /// Returns the target user ID for data operations.
    /// If a caregiver has an active patient selected, returns the patient's ID.
    /// Otherwise returns the authenticated user's ID or the care-code patient fallback.
    var currentUserID: UUID? {
        if let activeID = activePatientID {
            return activeID
        }
        return client.auth.currentSession?.user.id ?? patientUserID
    }

    /// The actual authenticated user's ID (ignoring impersonation).
    var authenticatedUserID: UUID? {
        client.auth.currentSession?.user.id
    }

    /// True if the user logged in via a care code (not email/password).
    var isPatientMode: Bool {
        client.auth.currentSession?.user.id == nil && patientUserID != nil
    }

    /// Convenience: throws if not signed in.
    func requireUserID() throws -> UUID {
        guard let id = currentUserID else {
            throw NSError(domain: "SupabaseManager", code: 401,
                          userInfo: [NSLocalizedDescriptionKey: "User is not signed in."])
        }
        return id
    }

    // MARK: - Retry Logic

    /// Retries a given async operation if it fails with a transient error (like PGRST002).
    func retry<T>(_ operation: @escaping () async throws -> T, maxRetries: Int = 3) async throws -> T {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                let errorString = "\(error)"
                
                // PGRST002 specifically often includes "Could not query the database for the schema cache"
                let isTransient = errorString.contains("PGRST002") || 
                                 errorString.contains("schema cache") ||
                                 errorString.contains("Retrying")

                if isTransient && attempt < maxRetries - 1 {
                    let delay = UInt64(pow(2.0, Double(attempt)) * 1_000_000_000) // Exponential backoff
                    print("⚠️ Supabase transient error detected (attempt \(attempt + 1)). Retrying in \(Double(delay)/1_000_000_000)s...")
                    try? await Task.sleep(nanoseconds: delay)
                    continue
                }
                throw error
            }
        }
        throw lastError ?? NSError(domain: "SupabaseManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Retry failed"])
    }

    // MARK: - Caregiver Actions

    func transferPatient(id: UUID, toEmail: String) async throws {
        struct TransferRequest: Encodable {
            let patientId: UUID
            let newCaregiverEmail: String
        }

        try await client.functions.invoke(
            "transfer-patient",
            options: .init(method: .post, body: TransferRequest(patientId: id, newCaregiverEmail: toEmail))
        )
    }

    func updatePatientPermissions(
        patientId: UUID,
        canAddMeds: Bool,
        canManageCalendar: Bool,
        notifyMeds: Bool,
        notifyApps: Bool
    ) async throws {
        try await client
            .from("caregiver_relations")
            .update([
                "can_patient_add_meds": canAddMeds,
                "can_patient_manage_calendar": canManageCalendar,
                "notify_patient_meds": notifyMeds,
                "notify_patient_appointments": notifyApps
            ])
            .eq("patient_id", value: patientId.uuidString.lowercased())
            .execute()
    }

    func removeFamilyMember(patientId: UUID) async throws {
        guard let caregiverId = authenticatedUserID else {
            throw NSError(
                domain: "SupabaseManager",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "You must be signed in with a caregiver account."]
            )
        }

        try await client
            .from("caregiver_relations")
            .delete()
            .eq("caregiver_id", value: caregiverId.uuidString.lowercased())
            .eq("patient_id", value: patientId.uuidString.lowercased())
            .execute()
    }

    func createFamilyMember(
        firstName: String,
        lastName: String,
        dateOfBirth: Date,
        allergies: [String],
        conditions: [String],
        canAddMeds: Bool,
        canManageCalendar: Bool,
        notifyMeds: Bool,
        notifyApps: Bool
    ) async throws -> CreateFamilyMemberResponse {
        guard client.auth.currentSession?.user.id != nil else {
            throw NSError(
                domain: "SupabaseManager",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "You must be signed in with a caregiver account."]
            )
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        let request = CreateFamilyMemberRequest(
            firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
            lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
            dateOfBirth: formatter.string(from: dateOfBirth),
            allergies: allergies,
            conditions: conditions,
            canPatientAddMeds: canAddMeds,
            canPatientManageCalendar: canManageCalendar,
            notifyPatientMeds: notifyMeds,
            notifyPatientAppointments: notifyApps
        )

        do {
            return try await client.functions.invoke(
                "create-family-member",
                options: .init(method: .post, body: request)
            )
        } catch let error as FunctionsError {
            switch error {
            case let .httpError(code, data):
                if let decoded = try? JSONDecoder().decode(FunctionErrorResponse.self, from: data) {
                    throw NSError(
                        domain: "SupabaseManager",
                        code: code,
                        userInfo: [NSLocalizedDescriptionKey: decoded.error]
                    )
                }

                let body = String(data: data, encoding: .utf8)
                throw NSError(
                    domain: "SupabaseManager",
                    code: code,
                    userInfo: [NSLocalizedDescriptionKey: body ?? "The family-member function request failed."]
                )
            case .relayError:
                throw NSError(
                    domain: "SupabaseManager",
                    code: 502,
                    userInfo: [NSLocalizedDescriptionKey: "Supabase could not reach the family-member function."]
                )
            }
        }
    }

    func redeemCareCode(_ code: String) async throws -> RedeemCareCodeResponse {
        let request = RedeemCareCodeRequest(code: code.trimmingCharacters(in: .whitespacesAndNewlines))

        do {
            return try await client.functions.invoke(
                "redeem-care-code",
                options: .init(method: .post, body: request)
            )
        } catch let error as FunctionsError {
            switch error {
            case let .httpError(code, data):
                if let decoded = try? JSONDecoder().decode(FunctionErrorResponse.self, from: data) {
                    throw NSError(
                        domain: "SupabaseManager",
                        code: code,
                        userInfo: [NSLocalizedDescriptionKey: decoded.error]
                    )
                }

                let body = String(data: data, encoding: .utf8)
                throw NSError(
                    domain: "SupabaseManager",
                    code: code,
                    userInfo: [NSLocalizedDescriptionKey: body ?? "The care-code function request failed."]
                )
            case .relayError:
                throw NSError(
                    domain: "SupabaseManager",
                    code: 502,
                    userInfo: [NSLocalizedDescriptionKey: "Supabase could not reach the care-code function."]
                )
            }
        }
    }

    func fetchPatientMedicationContext() async throws -> PatientMedicationContext {
        let requestContext = try patientFunctionRequestContext()

        let response: PatientMedicationFunctionResponse = try await invokePatientMedicationFunction(
            PatientMedicationRequest(
                action: "list",
                deviceToken: requestContext.deviceToken,
                targetPatientID: requestContext.targetPatientID,
                medication: nil,
                appointment: nil,
                id: nil
            )
        )

        let permissions = response.permissions
        return PatientMedicationContext(
            medications: response.medications ?? [],
            canAddMeds: permissions?.can_patient_add_meds ?? true,
            canManageCalendar: permissions?.can_patient_manage_calendar ?? true,
            notifyMeds: permissions?.notify_patient_meds ?? true,
            notifyAppointments: permissions?.notify_patient_appointments ?? true
        )
    }

    func savePatientMedication(_ med: LocalMed) async throws {
        let requestContext = try patientFunctionRequestContext()

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        let payload = PatientMedicationPayload(
            id: med.id,
            name: med.name,
            dosage: med.dosage,
            frequencyPerDay: med.frequencyPerDay,
            frequencyHours: med.minIntervalHours,
            startDate: formatter.string(from: med.startDate),
            endDate: formatter.string(from: med.endDate),
            notes: normalizedNotes(med.notes),
            foodRule: med.foodRule.rawValue
        )

        let _: PatientMedicationFunctionResponse = try await invokePatientMedicationFunction(
            PatientMedicationRequest(
                action: "save",
                deviceToken: requestContext.deviceToken,
                targetPatientID: requestContext.targetPatientID,
                medication: payload,
                appointment: nil,
                id: nil
            )
        )
    }

    func fetchPatientAppointments() async throws -> [Appointment] {
        let requestContext = try patientFunctionRequestContext()

        let response: PatientMedicationFunctionResponse = try await invokePatientMedicationFunction(
            PatientMedicationRequest(
                action: "list_appointments",
                deviceToken: requestContext.deviceToken,
                targetPatientID: requestContext.targetPatientID,
                medication: nil,
                appointment: nil,
                id: nil
            )
        )

        return (response.appointments ?? []).map { $0.toAppointment() }
    }

    func savePatientAppointment(id: String?, title: String, type: AppointmentType, date: Date, notes: String?) async throws {
        let requestContext = try patientFunctionRequestContext()

        let payload = PatientAppointmentPayload(
            id: id,
            title: title,
            doctorName: type.rawValue,
            appointmentTime: ISO8601DateFormatter().string(from: date),
            notes: normalizedNotes(notes)
        )

        let _: PatientMedicationFunctionResponse = try await invokePatientMedicationFunction(
            PatientMedicationRequest(
                action: "save_appointment",
                deviceToken: requestContext.deviceToken,
                targetPatientID: requestContext.targetPatientID,
                medication: nil,
                appointment: payload,
                id: nil
            )
        )
    }

    func deletePatientAppointment(id: String) async throws {
        let requestContext = try patientFunctionRequestContext()

        let _: PatientMedicationFunctionResponse = try await invokePatientMedicationFunction(
            PatientMedicationRequest(
                action: "delete_appointment",
                deviceToken: requestContext.deviceToken,
                targetPatientID: requestContext.targetPatientID,
                medication: nil,
                appointment: nil,
                id: id
            )
        )
    }

    func deletePatientMedication(id: String) async throws {
        let requestContext = try patientFunctionRequestContext()

        let _: PatientMedicationFunctionResponse = try await invokePatientMedicationFunction(
            PatientMedicationRequest(
                action: "delete_medication",
                deviceToken: requestContext.deviceToken,
                targetPatientID: requestContext.targetPatientID,
                medication: nil,
                appointment: nil,
                id: id
            )
        )
    }

    func archivePatientMedication(id: String, archived: Bool) async throws {
        let requestContext = try patientFunctionRequestContext()

        let _: PatientMedicationFunctionResponse = try await invokePatientMedicationFunction(
            PatientMedicationRequest(
                action: archived ? "archive_medication" : "restore_medication",
                deviceToken: requestContext.deviceToken,
                targetPatientID: requestContext.targetPatientID,
                medication: nil,
                appointment: nil,
                id: id
            )
        )
    }

    private func patientFunctionRequestContext() throws -> (deviceToken: String?, targetPatientID: String?) {
        if let activePatientID {
            return (nil, activePatientID.uuidString.lowercased())
        }

        if let deviceToken = patientDeviceToken, !deviceToken.isEmpty {
            return (deviceToken, nil)
        }

        throw NSError(
            domain: "SupabaseManager",
            code: 401,
            userInfo: [NSLocalizedDescriptionKey: "Patient session is missing. Please reconnect with your caregiver code."]
        )
    }

    private func invokePatientMedicationFunction<T: Decodable>(_ request: PatientMedicationRequest) async throws -> T {
        do {
            return try await client.functions.invoke(
                "patient-medications",
                options: .init(method: .post, body: request)
            )
        } catch let error as FunctionsError {
            switch error {
            case let .httpError(code, data):
                if let decoded = try? JSONDecoder().decode(FunctionErrorResponse.self, from: data) {
                    throw NSError(
                        domain: "SupabaseManager",
                        code: code,
                        userInfo: [NSLocalizedDescriptionKey: decoded.error]
                    )
                }

                let body = String(data: data, encoding: .utf8)
                throw NSError(
                    domain: "SupabaseManager",
                    code: code,
                    userInfo: [NSLocalizedDescriptionKey: body ?? "The patient-medications function request failed."]
                )
            case .relayError:
                throw NSError(
                    domain: "SupabaseManager",
                    code: 502,
                    userInfo: [NSLocalizedDescriptionKey: "Supabase could not reach the patient-medications function."]
                )
            }
        }
    }

    private func normalizedNotes(_ notes: String?) -> String? {
        guard let notes else { return nil }
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
