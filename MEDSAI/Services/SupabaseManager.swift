import Foundation
import Supabase

enum ActiveCareContext: Equatable {
    case selfUser(userId: UUID)
    case managedPatient(patientId: UUID, caregiverUserId: UUID)
    case linkedPatient(patientId: UUID, deviceSessionId: String)
}

enum MedicationOwnerContext: Equatable {
    case selfUser(UUID)
    case patient(UUID)
}

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
        let code: String?
        let careCode: String?
        let generatedCode: String?
        let expiresAt: String
        
        var resolvedCode: String {
            return code ?? careCode ?? generatedCode ?? ""
        }

        enum CodingKeys: String, CodingKey {
            case patientID = "patient_id"
            case code
            case careCode = "care_code"
            case generatedCode
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

    struct GenerateCareCodeRequest: Encodable {
        let patientID: String

        enum CodingKeys: String, CodingKey {
            case patientID = "patient_id"
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
        let doseEvent: PatientDoseEventPayload?
        let appointment: PatientAppointmentPayload?
        let id: String?

        init(
            action: String,
            deviceToken: String? = nil,
            targetPatientID: String? = nil,
            medication: PatientMedicationPayload? = nil,
            doseEvent: PatientDoseEventPayload? = nil,
            appointment: PatientAppointmentPayload? = nil,
            id: String? = nil
        ) {
            self.action = action
            self.deviceToken = deviceToken
            self.targetPatientID = targetPatientID
            self.medication = medication
            self.doseEvent = doseEvent
            self.appointment = appointment
            self.id = id
        }

        enum CodingKeys: String, CodingKey {
            case action
            case deviceToken = "device_token"
            case targetPatientID = "target_patient_id"
            case medication
            case doseEvent = "dose_event"
            case appointment
            case id
        }
    }

    private struct PatientDoseEventPayload: Encodable {
        let userMedicationID: String?
        let scheduledFor: String?
        let status: String?
        let source: String?
        let start: String?
        let end: String?

        enum CodingKeys: String, CodingKey {
            case userMedicationID = "user_medication_id"
            case scheduledFor = "scheduled_for"
            case status
            case source
            case start
            case end
        }
    }

    private struct PatientMedicationPayload: Encodable {
        let id: String
        let medicationID: String?
        let name: String
        let dosage: String
        let frequencyPerDay: Int
        let frequencyHours: Int?
        let dosageTimes: [String]
        let isPrn: Bool
        let isManual: Bool
        let isManualSchedule: Bool
        let medicationName: String
        let sourceType: String
        let medicationForm: String?
        let strengthValue: Double?
        let strengthUnit: String?
        let doseAmount: Double?
        let doseAmountUnit: String?
        let doseQuantity: Double?
        let doseUnit: String?
        let doseQuantityUnit: String?
        let strengthAmount: Double?
        let parsedStrengthUnit: String?
        let concentrationAmount: Double?
        let concentrationUnit: String?
        let route: String?
        let applicationArea: String?
        let doseDisplay: String?
        let foodRuleSource: String?
        let doseDetailsSource: String?
        let isDoseAutoFilled: Bool
        let doseDetailsConfirmedByUser: Bool
        let scheduleMode: String
        let timesPerDay: Int?
        let timesPerWeek: Int?
        let selectedWeekdays: [Int]?
        let intervalDays: Int?
        let remindersEnabled: Bool
        let caregiverRemindersEnabled: Bool?
        let visualShape: String?
        let visualColor: String?
        let visualBackgroundColor: String?
        let refillReminderEnabled: Bool
        let refillCurrentSupply: Double?
        let refillSupplyUnit: String?
        let refillThresholdQuantity: Double?
        let refillEstimatedRunoutDate: String?
        let refillReminderDate: String?
        let refillReminderMode: String?
        let refillNotes: String?
        let scanSource: String?
        let scanConfidence: Double?
        let scanConfirmedByUser: Bool?
        let scanExtractedFields: MedicationExtractedFields?
        let scanCandidateSnapshot: [MedicationScanCandidate]?
        let customFormText: String?
        let customUnitText: String?
        let sourceMetadata: String?
        let startDate: String
        let endDate: String
        let notes: String?
        let foodRule: String
        let rxcui: String?
        let ingredients: [String]?

        enum CodingKeys: String, CodingKey {
            case id
            case medicationID = "medication_id"
            case name
            case dosage
            case frequencyPerDay = "frequency_per_day"
            case frequencyHours = "frequency_hours"
            case dosageTimes = "dosage_times"
            case isPrn = "is_prn"
            case isManual = "is_manual"
            case isManualSchedule = "is_manual_schedule"
            case medicationName = "medication_name"
            case sourceType = "source_type"
            case medicationForm = "medication_form"
            case strengthValue = "strength_value"
            case strengthUnit = "strength_unit"
            case doseAmount = "dose_amount"
            case doseAmountUnit = "dose_amount_unit"
            case doseQuantity = "dose_quantity"
            case doseUnit = "dose_unit"
            case doseQuantityUnit = "dose_quantity_unit"
            case strengthAmount = "strength_amount"
            case parsedStrengthUnit = "parsed_strength_unit"
            case concentrationAmount = "concentration_amount"
            case concentrationUnit = "concentration_unit"
            case route
            case applicationArea = "application_area"
            case doseDisplay = "dose_display"
            case foodRuleSource = "food_rule_source"
            case doseDetailsSource = "dose_details_source"
            case isDoseAutoFilled = "is_dose_auto_filled"
            case doseDetailsConfirmedByUser = "dose_details_confirmed_by_user"
            case scheduleMode = "schedule_mode"
            case timesPerDay = "times_per_day"
            case timesPerWeek = "times_per_week"
            case selectedWeekdays = "selected_weekdays"
            case intervalDays = "interval_days"
            case remindersEnabled = "reminders_enabled"
            case caregiverRemindersEnabled = "caregiver_reminders_enabled"
            case visualShape = "visual_shape"
            case visualColor = "visual_color"
            case visualBackgroundColor = "visual_background_color"
            case refillReminderEnabled = "refill_reminder_enabled"
            case refillCurrentSupply = "refill_current_supply"
            case refillSupplyUnit = "refill_supply_unit"
            case refillThresholdQuantity = "refill_threshold_quantity"
            case refillEstimatedRunoutDate = "refill_estimated_runout_date"
            case refillReminderDate = "refill_reminder_date"
            case refillReminderMode = "refill_reminder_mode"
            case refillNotes = "refill_notes"
            case scanSource = "scan_source"
            case scanConfidence = "scan_confidence"
            case scanConfirmedByUser = "scan_confirmed_by_user"
            case scanExtractedFields = "scan_extracted_fields"
            case scanCandidateSnapshot = "scan_candidate_snapshot"
            case customFormText = "custom_form_text"
            case customUnitText = "custom_unit_text"
            case sourceMetadata = "source_metadata"
            case startDate = "start_date"
            case endDate = "end_date"
            case notes
            case foodRule = "food_rule"
            case rxcui
            case ingredients
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
        let dose_events: [MedicationDoseEventRow]?
        let dose_event: MedicationDoseEventInsertResponse?
        let permissions: Permissions?
    }

    struct MedicationDoseEventRow: Decodable {
        let id: String
        let patient_id: String
        let user_medication_id: String?
        let scheduled_for: String
        let status: String
        let taken_at: String?
        let source: String?
        let device_session_id: String?
        let created_at: String?
    }

    private struct MedicationDoseEventInsertResponse: Decodable {
        let id: String
    }

    private struct PatientAppointmentPayload: Encodable {
        let id: String?
        let title: String
        let doctorName: String
        let appointmentType: String
        let appointmentTime: String
        let location: String?
        let notes: String?
        let isCompleted: Bool?

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case doctorName = "doctor_name"
            case appointmentType = "appointment_type"
            case appointmentTime = "appointment_time"
            case location
            case notes
            case isCompleted = "is_completed"
        }
    }

    private struct PatientAppointmentRow: Decodable {
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
            let normalizedNotes = (notes?.isEmpty == true) ? nil : notes
            return Appointment(id: id, title: title, type: type, date: date, location: location, notes: normalizedNotes)
        }
    }

    private struct FunctionErrorResponse: Decodable {
        let error: String
    }

    private struct PushTokenUpsertPayload: Encodable {
        let user_id: String
        let token: String
        let platform: String
        let environment: String
        let device_id: String?
        let app_version: String?
        let language: String
        let is_active: Bool
    }

    private struct RemoveFamilyMemberPayload: Encodable {
        let status: String
    }

    private struct NotifyCaregiverDoseEventPayload: Encodable {
        let doseEventID: String
        let patientID: String
        let userMedicationID: String
        let status: String
        let occurredAt: String
        let actorUserID: String?
        let actorDeviceID: String?
        let actorPushToken: String?
        let deviceToken: String?

        enum CodingKeys: String, CodingKey {
            case doseEventID = "dose_event_id"
            case patientID = "patient_id"
            case userMedicationID = "user_medication_id"
            case status
            case occurredAt = "occurred_at"
            case actorUserID = "actor_user_id"
            case actorDeviceID = "actor_device_id"
            case actorPushToken = "actor_push_token"
            case deviceToken = "device_token"
        }
    }

    private struct NotifyCaregiverDoseEventResponse: Decodable {
        let caregivers_found: Int?
        let tokens_found: Int?
        let sent_count: Int?
        let failed_count: Int?
    }

    struct DoseEventStatusSnapshot {
        let medicationID: String
        let scheduledAt: Date
        let status: DoseStatus
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
        PatientSessionStore.shared.patientUserID
    }

    var patientDeviceToken: String? {
        PatientSessionStore.shared.deviceToken
    }

    /// The patient ID currently being managed by a caregiver.
    var activePatientID: UUID? {
        get {
            PatientSessionStore.shared.activePatientID
        }
        set {
            guard PatientSessionStore.shared.activePatientID != newValue else {
                #if DEBUG
                print("Care context unchanged; skipping SupabaseContextChanged notification.")
                #endif
                return
            }
            do {
                try PatientSessionStore.shared.setActivePatientID(newValue)
            } catch {
                print("Patient session storage failed while updating active patient: \(error.localizedDescription)")
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

    // Account-level caregiver action. Uses authenticatedUserID, NOT activePatientID.
    func upsertPushToken(token: String, environment: String, deviceID: String?, appVersion: String?) async {
        guard let userID = authenticatedUserID, !isPatientMode else {
            #if DEBUG
            print("Skipping caregiver push token registration because there is no authenticated user session.")
            #endif
            return
        }

        let payload = PushTokenUpsertPayload(
            user_id: userID.uuidString.lowercased(),
            token: token,
            platform: "ios",
            environment: environment,
            device_id: deviceID,
            app_version: appVersion,
            language: Self.currentLanguageCode(),
            is_active: true
        )

        do {
            try await client
                .from("user_push_tokens")
                .upsert(payload, onConflict: "user_id,token,environment")
                .execute()
            #if DEBUG
            print("Registered APNs token for caregiver notifications. environment=\(environment) deviceID=\(deviceID ?? "nil")")
            #endif
        } catch {
            print("⚠️ Failed to register APNs token:", error)
        }
    }

    func deactivatePushToken(token: String) async {
        guard let userID = authenticatedUserID, !isPatientMode else { return }

        struct DeactivatePayload: Encodable {
            let is_active: Bool
        }

        do {
            try await client
                .from("user_push_tokens")
                .update(DeactivatePayload(is_active: false))
                .eq("token", value: token)
                .eq("user_id", value: userID.uuidString.lowercased())
                .execute()
            #if DEBUG
            print("Deactivated APNs token on logout.")
            #endif
        } catch {
            print("⚠️ Failed to deactivate APNs token on logout:", error)
        }
    }

    private static func currentLanguageCode() -> String {
        let stored = UserDefaults.standard.string(forKey: "appearance.language")
        return stored == "ar" ? "ar" : "en"
    }

    func resolveMedicationOwnerContext() throws -> MedicationOwnerContext {
        if let activePatientID = activePatientID {
            return .patient(activePatientID)
        }
        if isPatientMode, let patientID = patientUserID {
            return .patient(patientID)
        }
        if let authID = authenticatedUserID {
            return .selfUser(authID)
        }
        throw NSError(domain: "SupabaseManager", code: 401,
                      userInfo: [NSLocalizedDescriptionKey: "No active owner context found."])
    }

    func ownerIDString(from context: MedicationOwnerContext) -> String {
        switch context {
        case .selfUser(let id), .patient(let id):
            return id.uuidString
        }
    }

    func resolveActiveCareContext() -> ActiveCareContext? {
        if let caregiverID = authenticatedUserID {
            if let patientID = activePatientID {
                return .managedPatient(patientId: patientID, caregiverUserId: caregiverID)
            }
            return .selfUser(userId: caregiverID)
        }

        if let patientID = patientUserID, let token = patientDeviceToken, !token.isEmpty {
            return .linkedPatient(patientId: patientID, deviceSessionId: token)
        }

        return nil
    }

    func clearStoredCareContext() {
        do {
            try PatientSessionStore.shared.setActivePatientID(nil)
            try PatientSessionStore.shared.setActivePatientName(nil)
        } catch {
            print("Patient context cleanup failed: \(error.localizedDescription)")
        }
    }

    func clearCareCodeSession() {
        do {
            try PatientSessionStore.shared.clearPatientSession()
        } catch {
            print("Care-code session cleanup failed: \(error.localizedDescription)")
        }
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

    // Account-level caregiver action. Uses auth session, NOT activePatientID.
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

    // Account-level caregiver action. Uses authenticatedUserID, NOT activePatientID.
    func removeFamilyMember(patientId: UUID) async throws {
        guard let caregiverId = authenticatedUserID else {
            throw NSError(
                domain: "SupabaseManager",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "You must be signed in with a caregiver account."]
            )
        }

        #if DEBUG
        print("removeFamilyMember request caregiverID=\(caregiverId.uuidString.lowercased()) patientID=\(patientId.uuidString.lowercased())")
        #endif

        // Revoke the relation instead of deleting the patient profile. This works
        // with the existing caregiver UPDATE RLS policy and keeps an audit trail.
        try await client
            .from("caregiver_relations")
            .update(RemoveFamilyMemberPayload(status: "removed"))
            .eq("caregiver_id", value: caregiverId.uuidString.lowercased())
            .eq("patient_id", value: patientId.uuidString.lowercased())
            .execute()
    }

    // Account-level caregiver action. Uses auth session, NOT activePatientID.
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

    /// Redeem a care code without requiring an active Supabase Auth session.
    /// Uses a plain URLSession POST with the anon key so unauthenticated
    /// users (patients on the landing page) can call this endpoint.
    /// The Supabase SDK's functions.invoke is intentionally NOT used here
    /// because it auto-attaches the current session JWT which is empty/invalid
    /// before login, causing UNAUTHORIZED_INVALID_JWT_FORMAT.
    func redeemCareCode(_ code: String) async throws -> RedeemCareCodeResponse {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)

        // Build the URL manually so we control every header.
        let urlString = "https://svucjnbwlcsaiaurdmab.supabase.co/functions/v1/redeem-care-code"
        guard let url = URL(string: urlString) else {
            throw NSError(
                domain: "SupabaseManager", code: 0,
                userInfo: [NSLocalizedDescriptionKey: "Could not connect right now. Please try again."]
            )
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Only the apikey header is sent. Authorization is intentionally omitted:
        // supabaseKey is a publishable key, NOT a JWT. Sending it as
        // "Bearer <publishable-key>" triggers UNAUTHORIZED_INVALID_JWT_FORMAT at
        // the Supabase gateway. With verify_jwt=false the gateway skips JWT
        // validation entirely — apikey is sufficient for routing.
        urlRequest.setValue(supabaseKey, forHTTPHeaderField: "apikey")

        let body = ["code": trimmedCode]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: urlRequest)

        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 0

        #if DEBUG
        let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
        print("DEBUG redeem-care-code: status=\(statusCode) body=\(rawBody)")
        #endif

        if statusCode == 200 {
            do {
                // Use a plain JSONDecoder — the struct already has explicit CodingKeys
                // that map snake_case JSON keys (patient_id, device_token) to Swift
                // properties. Adding keyDecodingStrategy = .convertFromSnakeCase on
                // top of explicit CodingKeys causes double-transformation and silent
                // decode failure (the pre-transformed "patientId" never matches the
                // CodingKey "patient_id"), which previously fell through to "Could not
                // connect right now."
                let decoder = JSONDecoder()
                let decoded = try decoder.decode(RedeemCareCodeResponse.self, from: data)
                #if DEBUG
                print("DEBUG redeem-care-code: decode success, patientID length=\(decoded.patientID.count), tokenLength=\(decoded.deviceToken.count)")
                #endif
                return decoded
            } catch {
                #if DEBUG
                print("DEBUG redeem-care-code: DECODE FAILED (backend replied 200 but body didn't match RedeemCareCodeResponse). Error: \(error)")
                let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
                print("DEBUG redeem-care-code: raw 200 body was: \(rawBody)")
                #endif
                throw NSError(
                    domain: "SupabaseManager", code: 200,
                    userInfo: [NSLocalizedDescriptionKey: "Code accepted, but the app could not finish setup. Please restart and try again."]
                )
            }
        }

        // Parse backend error message if available.
        if let errorBody = try? JSONDecoder().decode(FunctionErrorResponse.self, from: data) {
            let msg = errorBody.error
            // Map backend messages to user-friendly strings.
            if msg.lowercased().contains("invalid") ||
               msg.lowercased().contains("expired") ||
               msg.lowercased().contains("used") ||
               msg.lowercased().contains("6-digit") {
                throw NSError(
                    domain: "SupabaseManager", code: statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid family code. Please check the code and try again."]
                )
            }
        }

        throw NSError(
            domain: "SupabaseManager", code: statusCode,
            userInfo: [NSLocalizedDescriptionKey: "Could not connect right now. Please try again."]
        )
    }

    // Account-level caregiver action. Regenerates an invite for an existing relation.
    func generateCareCode(for patientId: UUID) async throws -> CreateFamilyMemberResponse {
        guard authenticatedUserID != nil else {
            throw NSError(
                domain: "SupabaseManager",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "You must be signed in with a caregiver account."]
            )
        }

        do {
            return try await client.functions.invoke(
                "generate-care-code",
                options: .init(
                    method: .post,
                    body: GenerateCareCodeRequest(patientID: patientId.uuidString.lowercased())
                )
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
                    userInfo: [NSLocalizedDescriptionKey: body ?? "The care-code generation request failed."]
                )
            case .relayError:
                throw NSError(
                    domain: "SupabaseManager",
                    code: 502,
                    userInfo: [NSLocalizedDescriptionKey: "Supabase could not reach the care-code generation function."]
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

    // Patient-scoped medication action. Uses selected patient context (activePatientID).
    func savePatientMedication(_ med: LocalMed) async throws {
        let requestContext = try patientFunctionRequestContext()
        let normalizedTimesPerDay = med.dosageTimes.isEmpty ? med.timesPerDay : med.dosageTimes.count

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        let payload = PatientMedicationPayload(
            id: med.id,
            medicationID: med.sourceType == .identified ? med.catalogId : nil,
            name: med.name,
            dosage: med.dosage,
            frequencyPerDay: med.frequencyPerDay,
            frequencyHours: med.minIntervalHours,
            dosageTimes: med.dosageTimes,
            isPrn: med.asNeeded,
            isManual: med.sourceType == .manual,
            isManualSchedule: med.isManualSchedule,
            medicationName: med.name,
            sourceType: med.sourceType.rawValue,
            medicationForm: med.medicationForm,
            strengthValue: med.strengthValue,
            strengthUnit: med.strengthUnit,
            doseAmount: med.doseAmount,
            doseAmountUnit: med.doseAmountUnit,
            doseQuantity: med.doseQuantity,
            doseUnit: med.doseUnit,
            doseQuantityUnit: med.doseQuantityUnit,
            strengthAmount: med.strengthAmount,
            parsedStrengthUnit: med.parsedStrengthUnit,
            concentrationAmount: med.concentrationAmount,
            concentrationUnit: med.concentrationUnit,
            route: med.route,
            applicationArea: med.applicationArea,
            doseDisplay: med.doseDisplay,
            foodRuleSource: med.foodRuleSource,
            doseDetailsSource: med.doseDetailsSource,
            isDoseAutoFilled: med.isDoseAutoFilled,
            doseDetailsConfirmedByUser: med.doseDetailsConfirmedByUser,
            scheduleMode: med.scheduleMode.storageValue,
            timesPerDay: normalizedTimesPerDay,
            timesPerWeek: med.timesPerWeek,
            selectedWeekdays: med.selectedWeekdays.isEmpty ? nil : med.selectedWeekdays,
            intervalDays: med.intervalDays,
            remindersEnabled: med.remindersEnabled,
            caregiverRemindersEnabled: med.caregiverRemindersEnabled,
            visualShape: med.visualShape,
            visualColor: med.visualColor,
            visualBackgroundColor: med.visualBackgroundColor,
            refillReminderEnabled: med.refillReminderEnabled,
            refillCurrentSupply: med.refillCurrentSupply,
            refillSupplyUnit: med.refillSupplyUnit,
            refillThresholdQuantity: med.refillThresholdQuantity,
            refillEstimatedRunoutDate: dateOnlyString(med.refillEstimatedRunoutDate),
            refillReminderDate: dateTimeString(med.refillReminderDate),
            refillReminderMode: med.refillReminderMode,
            refillNotes: normalizedNotes(med.refillNotes),
            scanSource: med.scanSource ?? "manual",
            scanConfidence: med.scanConfidence,
            scanConfirmedByUser: med.scanConfirmedByUser ?? false,
            scanExtractedFields: med.scanExtractedFields,
            scanCandidateSnapshot: med.scanCandidateSnapshot,
            customFormText: med.customFormText,
            customUnitText: med.customUnitText,
            sourceMetadata: med.sourceMetadata,
            startDate: formatter.string(from: med.startDate),
            endDate: formatter.string(from: med.endDate),
            notes: normalizedNotes(med.notes),
            foodRule: med.foodRule.rawValue,
            rxcui: med.rxcui,
            ingredients: med.ingredients
        )

        #if DEBUG
        debugPatientMedicationSaveStarted(med, requestContext: requestContext)
        #endif

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

    func savePatientAppointment(id: String?, title: String, type: AppointmentType, date: Date, location: String?, notes: String?) async throws {
        let requestContext = try patientFunctionRequestContext()

        let payload = PatientAppointmentPayload(
            id: id,
            title: title,
            doctorName: type.rawValue,
            appointmentType: type.rawValue,
            appointmentTime: ISO8601DateFormatter().string(from: date),
            location: normalizedNotes(location),
            notes: normalizedNotes(notes),
            isCompleted: id == nil ? false : nil
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

    // MARK: - App Hooks
    var onSessionExpired: (() -> Void)?

    private func invokePatientMedicationFunction<T: Decodable>(_ request: PatientMedicationRequest) async throws -> T {
        if isPatientMode {
            // Build the URL manually for raw URLSession request to bypass Supabase SDK's automatic JWT injection
            let urlString = "https://svucjnbwlcsaiaurdmab.supabase.co/functions/v1/patient-medications"
            guard let url = URL(string: urlString) else {
                throw NSError(
                    domain: "SupabaseManager", code: 0,
                    userInfo: [NSLocalizedDescriptionKey: "Could not build patient-medications URL."]
                )
            }

            var urlRequest = URLRequest(url: url)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue(supabaseKey, forHTTPHeaderField: "apikey")

            // Encode request body and explicitly inject patient_id
            let encoder = JSONEncoder()
            let requestData = try encoder.encode(request)
            var jsonDict = (try? JSONSerialization.jsonObject(with: requestData) as? [String: Any]) ?? [:]
            
            if let patientID = patientUserID {
                jsonDict["patient_id"] = patientID.uuidString.lowercased()
            }
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: jsonDict)

            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            let httpResponse = response as? HTTPURLResponse
            let statusCode = httpResponse?.statusCode ?? 0

            #if DEBUG
            let rawBody = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            print("DEBUG patient-medications raw call: status=\(statusCode) body=\(rawBody)")
            #endif

            if statusCode == 200 {
                return try JSONDecoder().decode(T.self, from: data)
            } else {
                let responseBody = String(data: data, encoding: .utf8) ?? ""
                let isGatewayJWTError = responseBody.contains("UNAUTHORIZED_INVALID_JWT_FORMAT") || responseBody.contains("Invalid JWT")

                if statusCode == 401 {
                    if isGatewayJWTError {
                        #if DEBUG
                        print("⚠️ Gateway JWT authentication error (not a revoked patient session). Please verify function configurations.")
                        #endif
                    } else if responseBody.contains("Patient session has been revoked") || responseBody.contains("Patient session is invalid or expired") {
                        print("⚠️ Patient session revoked/expired (401).")
                        Task { @MainActor in onSessionExpired?() }
                    }
                }

                if let decoded = try? JSONDecoder().decode(FunctionErrorResponse.self, from: data) {
                    throw NSError(
                        domain: "SupabaseManager",
                        code: statusCode,
                        userInfo: [NSLocalizedDescriptionKey: decoded.error]
                    )
                }

                throw NSError(
                    domain: "SupabaseManager",
                    code: statusCode,
                    userInfo: [NSLocalizedDescriptionKey: responseBody.isEmpty ? "The patient-medications function request failed." : responseBody]
                )
            }
        } else {
            do {
                return try await client.functions.invoke(
                    "patient-medications",
                    options: .init(method: .post, body: request)
                )
            } catch let error as FunctionsError {
                switch error {
                case let .httpError(code, data):
                    let responseBody = String(data: data, encoding: .utf8) ?? ""
                    let isGatewayJWTError = responseBody.contains("UNAUTHORIZED_INVALID_JWT_FORMAT") || responseBody.contains("Invalid JWT")

                    if code == 401 {
                        if isGatewayJWTError {
                            #if DEBUG
                            print("⚠️ Gateway JWT authentication error (not a revoked patient session). Please verify function configurations.")
                            #endif
                        } else if responseBody.contains("Patient session has been revoked") || responseBody.contains("Patient session is invalid or expired") {
                            print("⚠️ Patient session revoked/expired (401).")
                            Task { @MainActor in onSessionExpired?() }
                        }
                    }

                    #if DEBUG
                    print("""
                    ⚠️ patient-medications Edge Function failed
                    endpoint/table/EdgeFunction: patient-medications
                    httpStatusCode: \(code)
                    decodedResponseBody: \(responseBody)
                    """)
                    #endif

                    if let decoded = try? JSONDecoder().decode(FunctionErrorResponse.self, from: data) {
                        throw NSError(
                            domain: "SupabaseManager",
                            code: code,
                            userInfo: [NSLocalizedDescriptionKey: decoded.error]
                        )
                    }

                    throw NSError(
                        domain: "SupabaseManager",
                        code: code,
                        userInfo: [NSLocalizedDescriptionKey: responseBody.isEmpty ? "The patient-medications function request failed." : responseBody]
                    )
                case .relayError:
                    #if DEBUG
                    print("""
                    ⚠️ patient-medications Edge Function relay error
                    endpoint/table/EdgeFunction: patient-medications
                    httpStatusCode: unavailable
                    decodedResponseBody: relayError
                    """)
                    #endif
                    throw NSError(
                        domain: "SupabaseManager",
                        code: 502,
                        userInfo: [NSLocalizedDescriptionKey: "Supabase could not reach the patient-medications function."]
                    )
                }
            }
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

    #if DEBUG
    private func debugPatientMedicationSaveStarted(
        _ med: LocalMed,
        requestContext: (deviceToken: String?, targetPatientID: String?)
    ) {
        let medicationNamePresent = !med.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let strengthText = "\(med.strengthValue.map { String($0) } ?? "nil") \(med.strengthUnit ?? "nil")"
        let doseText = "\(med.doseQuantity.map { String($0) } ?? "nil") \(med.doseUnit ?? "nil")"
        var lines: [String] = []
        lines.append("patient-medications save started")
        lines.append("selectedContext: \(debugActiveCareContextLabel())")
        lines.append("auth.uid: \(authenticatedUserID?.uuidString.lowercased() ?? "nil")")
        lines.append("activePatientID: \(activePatientID?.uuidString.lowercased() ?? "nil")")
        lines.append("careCodeActive: \(isPatientMode)")
        lines.append("targetPatientIDPresent: \(requestContext.targetPatientID != nil)")
        lines.append("deviceTokenPresent: \(requestContext.deviceToken != nil)")
        lines.append("medicationNamePresent: \(medicationNamePresent)")
        lines.append("medicationIdPresent: \(med.catalogId != nil)")
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
        lines.append("payloadKeys: action,device_token,target_patient_id,medication(id,medication_id,name,dosage,frequency_per_day,frequency_hours,dosage_times,is_prn,is_manual,is_manual_schedule,medication_name,source_type,medication_form,strength_value,strength_unit,dose_amount,dose_amount_unit,dose_quantity,dose_unit,dose_quantity_unit,strength_amount,parsed_strength_unit,concentration_amount,concentration_unit,route,application_area,dose_display,food_rule_source,dose_details_source,is_dose_auto_filled,dose_details_confirmed_by_user,schedule_mode,times_per_day,times_per_week,selected_weekdays,interval_days,reminders_enabled,caregiver_reminders_enabled,visual_shape,visual_color,visual_background_color,refill_reminder_enabled,refill_current_supply,refill_supply_unit,refill_threshold_quantity,refill_estimated_runout_date,refill_reminder_date,refill_reminder_mode,refill_notes,scan_source,scan_confidence,scan_confirmed_by_user,scan_extracted_fields,scan_candidate_snapshot,custom_form_text,custom_unit_text,source_metadata,start_date,end_date,notes,food_rule,rxcui,ingredients)")
        lines.append("endpoint/table/EdgeFunction: patient-medications")
        print(lines.joined(separator: "\n"))
    }

    private func debugActiveCareContextLabel() -> String {
        switch resolveActiveCareContext() {
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

    private func debugDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
    #endif

    // MARK: - Dose Events

    func recordDoseEvent(
        medId: String,
        scheduledAt: Date,
        status: DoseStatus,
        patientID explicitPatientID: UUID? = nil,
        source explicitSource: String? = nil
    ) async throws {
        guard let uid = currentUserID else { return }
        guard let medUUID = UUID(uuidString: medId) else {
            print("⚠️ Cannot record dose event: Invalid medId UUID: \(medId)")
            return
        }

        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Notification actions may run after the user has switched context, so
        // prefer the patient ID encoded in the notification payload.
        let patientId = explicitPatientID ?? (isPatientMode ? patientUserID : activePatientID) ?? uid
        let source = normalizedDoseEventSource(explicitSource)

        if isPatientMode || activePatientID != nil {
            let requestContext = try patientFunctionRequestContext()
            let payload = PatientDoseEventPayload(
                userMedicationID: medUUID.uuidString.lowercased(),
                scheduledFor: isoFmt.string(from: scheduledAt),
                status: status.rawValue,
                source: source,
                start: nil,
                end: nil
            )
            let response: PatientMedicationFunctionResponse = try await invokePatientMedicationFunction(
                PatientMedicationRequest(
                    action: "record_dose_event",
                    deviceToken: requestContext.deviceToken,
                    targetPatientID: requestContext.targetPatientID,
                    doseEvent: payload
                )
            )

            if let id = response.dose_event?.id, let eventID = UUID(uuidString: id) {
                Task {
                    await self.notifyCaregiversDoseEvent(
                        doseEventID: eventID,
                        patientID: patientId,
                        userMedicationID: medUUID,
                        status: status,
                        occurredAt: Date(),
                        actorUserID: authenticatedUserID,
                        actorDeviceID: NotificationsManager.currentDeviceIdentifier,
                        actorPushToken: NotificationsManager.currentAPNSToken
                    )
                }
            }
            return
        }

        struct DoseEventRow: Encodable {
            let id: UUID
            let patient_id: UUID
            let user_medication_id: UUID
            let scheduled_for: String
            let status: String
            let taken_at: String?
            let recorded_by: UUID
            let source: String
        }
        
        let row = DoseEventRow(
            id: UUID(),
            patient_id: patientId,
            user_medication_id: medUUID,
            scheduled_for: isoFmt.string(from: scheduledAt),
            status: status.rawValue,
            taken_at: status == .taken ? isoFmt.string(from: Date()) : nil,
            recorded_by: uid, // The actual person logged in
            source: source
        )

        struct DoseEventInsertResponse: Decodable {
            let id: UUID
        }

        let inserted: DoseEventInsertResponse = try await client
            .from("medication_dose_events")
            .upsert(row, onConflict: "patient_id,user_medication_id,scheduled_for")
            .select("id")
            .single()
            .execute()
            .value

        Task {
            await self.notifyCaregiversDoseEvent(
                doseEventID: inserted.id,
                patientID: patientId,
                userMedicationID: medUUID,
                status: status,
                occurredAt: Date(),
                actorUserID: authenticatedUserID,
                actorDeviceID: NotificationsManager.currentDeviceIdentifier,
                actorPushToken: NotificationsManager.currentAPNSToken
            )
        }
    }

    private func normalizedDoseEventSource(_ explicitSource: String?) -> String {
        switch explicitSource {
        case "today_button", "calendar_button", "notification_action", "patient_device", "caregiver", "system":
            return explicitSource ?? "system"
        case "self":
            return "today_button"
        default:
            return isPatientMode ? "patient_device" : (activePatientID == nil ? "today_button" : "caregiver")
        }
    }

    func fetchDoseEventStatusSnapshots(start: Date, end: Date) async throws -> [DoseEventStatusSnapshot] {
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let rows: [MedicationDoseEventRow]
        if isPatientMode || activePatientID != nil {
            let requestContext = try patientFunctionRequestContext()
            let payload = PatientDoseEventPayload(
                userMedicationID: nil,
                scheduledFor: nil,
                status: nil,
                source: nil,
                start: isoFmt.string(from: start),
                end: isoFmt.string(from: end)
            )
            let response: PatientMedicationFunctionResponse = try await invokePatientMedicationFunction(
                PatientMedicationRequest(
                    action: "list_dose_events",
                    deviceToken: requestContext.deviceToken,
                    targetPatientID: requestContext.targetPatientID,
                    doseEvent: payload
                )
            )
            rows = response.dose_events ?? []
        } else {
            guard let patientId = currentUserID else { return [] }
            rows = try await client
                .from("medication_dose_events")
                .select("id,patient_id,user_medication_id,scheduled_for,status,taken_at,source,device_session_id,created_at")
                .eq("patient_id", value: patientId.uuidString.lowercased())
                .gte("scheduled_for", value: isoFmt.string(from: start))
                .lt("scheduled_for", value: isoFmt.string(from: end))
                .order("created_at", ascending: false)
                .execute()
                .value
        }

        return rows.compactMap { row in
            guard let medicationID = row.user_medication_id,
                  let scheduledAt = isoFmt.date(from: row.scheduled_for),
                  let status = DoseStatus(rawValue: row.status) else {
                return nil
            }
            return DoseEventStatusSnapshot(
                medicationID: medicationID,
                scheduledAt: scheduledAt,
                status: status
            )
        }
    }

    private func notifyCaregiversDoseEvent(
        doseEventID: UUID,
        patientID: UUID,
        userMedicationID: UUID,
        status: DoseStatus,
        occurredAt: Date,
        actorUserID: UUID?,
        actorDeviceID: String?,
        actorPushToken: String?
    ) async {
        let payload = NotifyCaregiverDoseEventPayload(
            doseEventID: doseEventID.uuidString.lowercased(),
            patientID: patientID.uuidString.lowercased(),
            userMedicationID: userMedicationID.uuidString.lowercased(),
            status: status.rawValue,
            occurredAt: ISO8601DateFormatter().string(from: occurredAt),
            actorUserID: actorUserID?.uuidString.lowercased(),
            actorDeviceID: actorDeviceID,
            actorPushToken: actorPushToken,
            deviceToken: isPatientMode ? patientDeviceToken : nil
        )

        do {
            let response: NotifyCaregiverDoseEventResponse = try await client.functions.invoke(
                "notify-caregiver-dose-event",
                options: .init(method: .post, body: payload)
            )
            #if DEBUG
            print(
                "Caregiver dose push fan-out:",
                "caregivers=\(response.caregivers_found ?? 0)",
                "tokens=\(response.tokens_found ?? 0)",
                "sent=\(response.sent_count ?? 0)",
                "failed=\(response.failed_count ?? 0)"
            )
            #endif
        } catch {
            print("⚠️ Caregiver dose push fan-out failed:", error)
        }
    }
}
