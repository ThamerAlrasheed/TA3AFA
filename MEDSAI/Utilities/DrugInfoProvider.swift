import Foundation
import Supabase
import UIKit

// MARK: - UIImage Helpers
extension UIImage {
    func toBase64(maxSizeInBytes: Int = 1_000_000) -> String? {
        var compression: CGFloat = 0.9
        var data = self.jpegData(compressionQuality: compression)
        
        while (data?.count ?? 0) > maxSizeInBytes && compression > 0.1 {
            compression -= 0.1
            data = self.jpegData(compressionQuality: compression)
        }
        
        return data?.base64EncodedString()
    }
}

// MARK: - Your existing, app-facing model (kept the same)
struct DrugPayload: Codable {
    let title: String
    let strengths: [String]
    let dosageForms: [String]
    let foodRule: String?            // "afterFood" | "beforeFood" | "withFood" | "none"
    let minIntervalHours: Int?
    let ingredients: [String]
    let indications: [String]
    let howToTake: [String]
    let commonSideEffects: [String]
    let importantWarnings: [String]
    let interactionsToAvoid: [String]
    let references: [String]?
    let kbKey: String?
    let rxcui: String?               // Canonical NIH ID
    let id: UUID?                    // Database UUID for tracking
}

struct InteractionAlert: Codable, Identifiable {
    var id: String { description }
    let severity: String             // "HIGH" | "MEDIUM" | "LOW"
    let description: String
}

// MARK: - Scan flow models
struct DrugCandidate: Codable, Identifiable {
    var id: String { name + (strength ?? "") }
    let name: String
    let strength: String?
    let dosage_form: String?
    let confidence: Double
    let detected_text: String?
}

struct ScanResult: Codable {
    let candidates: [DrugCandidate]
    let is_high_confidence: Bool
    let requires_confirmation: Bool
    let analysis_id: String
}

// MARK: - Safety Engine Models
enum SafetySeverity: String, Codable {
    case contraindicated, major, moderate, minor, unknown
}

enum SafetyWarningType: String, Codable {
    case duplicateIngredient = "DUPLICATE_INGREDIENT"
    case drugInteraction = "DRUG_INTERACTION"
    case allergyConflict = "ALLERGY_CONFLICT"
    case conditionConflict = "CONDITION_CONFLICT"
}

struct SafetyWarning: Codable, Identifiable {
    var id: String { type.rawValue + meds.joined() + (severity.rawValue) }
    let type: SafetyWarningType
    let severity: SafetySeverity
    let affected_medication_ids: [String]?
    let meds: [String]
    let ingredients: [String]
    let description: String
    let management: String?
    let source: String
    let is_deterministic: Bool
    let requires_acknowledgement: Bool
    let can_continue: Bool

    init(
        type: SafetyWarningType,
        severity: SafetySeverity,
        meds: [String],
        ingredients: [String],
        description: String,
        management: String?,
        source: String,
        is_deterministic: Bool,
        requires_acknowledgement: Bool,
        can_continue: Bool,
        affectedMedicationIDs: [String]? = nil
    ) {
        self.type = type
        self.severity = severity
        self.affected_medication_ids = affectedMedicationIDs
        self.meds = meds
        self.ingredients = ingredients
        self.description = description
        self.management = management
        self.source = source
        self.is_deterministic = is_deterministic
        self.requires_acknowledgement = requires_acknowledgement
        self.can_continue = can_continue
    }
}

struct SafetyCheckResponse: Codable {
    let warnings: [SafetyWarning]
    let source_trace: [String]
}

struct SafetyMedicationInput: Encodable {
    let id: String?
    let name: String
    let rxcui: String?
    let ingredients: [String]

    init(id: String? = nil, name: String, rxcui: String?, ingredients: [String]) {
        self.id = id
        self.name = name
        self.rxcui = rxcui
        self.ingredients = ingredients
    }
}

private struct PatientRequestContext {
    let patientId: String?
    let deviceToken: String?
}

#if DEBUG
private struct RedactedSafetyMedication: Encodable {
    let id: String?
    let name: String
    let rxcui: String?
    let ingredients: [String]
}

private struct RedactedSafetyRequest: Encodable {
    let patient_id: String?
    let device_token_present: Bool
    let medications: [RedactedSafetyMedication]
    let lang: String
}
#endif

// MARK: - Protocol: updated
protocol DrugInfoProvider {
    static func fetchDetails(name: String, lang: String) async throws -> DrugPayload
    static func fetchDosageOptions(name: String) async throws -> [String]
    static func analyzeImage(base64: String) async throws -> ScanResult
    static func checkInteractions(rxcuis: [String], lang: String) async throws -> [InteractionAlert]
    static func checkSafety(patientId: String?, deviceToken: String?, medications: [SafetyMedicationInput], lang: String) async throws -> SafetyCheckResponse
    static func parseSchedule(text: String, lang: String) async throws -> ParsedSchedule
    static func listDevices(patientId: String) async throws -> [PatientDevice]
    static func revokeDevice(patientId: String, deviceId: String) async throws
    
    // Medical Profile
    static func listAllergies(patientId: String?) async throws -> [Allergy]
    static func saveAllergy(patientId: String?, allergy: Allergy) async throws
    static func deactivateAllergy(patientId: String?, id: String) async throws
    
    static func listConditions(patientId: String?) async throws -> [Condition]
    static func saveCondition(patientId: String?, condition: Condition) async throws
    static func deactivateCondition(patientId: String?, id: String) async throws
}

struct Allergy: Codable, Identifiable {
    var id: String
    let name: String
    let severity: String // mild, moderate, severe, unknown
    let reaction: String?
    let notes: String?
    let is_active: Bool
    
    init(id: String = UUID().uuidString, name: String, severity: String = "unknown", reaction: String? = nil, notes: String? = nil, is_active: Bool = true) {
        self.id = id
        self.name = name
        self.severity = severity
        self.reaction = reaction
        self.notes = notes
        self.is_active = is_active
    }
}

struct Condition: Codable, Identifiable {
    var id: String
    let name: String
    let status: String // active, inactive, resolved, unknown
    let diagnosed_at: String? // ISO date
    let notes: String?
    let is_active: Bool
    
    init(id: String = UUID().uuidString, name: String, status: String = "active", diagnosed_at: String? = nil, notes: String? = nil, is_active: Bool = true) {
        self.id = id
        self.name = name
        self.status = status
        self.diagnosed_at = diagnosed_at
        self.notes = notes
        self.is_active = is_active
    }
}

struct PatientDevice: Codable, Identifiable {
    let id: String
    let patient_id: String
    let platform: String
    let device_name: String?
    let app_version: String?
    let os_version: String?
    let last_seen_at: String?
    let created_at: String
}

struct ListDevicesResponse: Codable {
    let devices: [PatientDevice]
}

struct ParsedSchedule: Codable {
    let dose_amount: Double?
    let dose_unit: String?
    let frequency_per_day: Int?
    let interval_hours: Int?
    let times_of_day: [String]
    let food_rule: String
    let as_needed: Bool
    let raw_text: String
    let language: String
    let confidence: Double
    let needs_confirmation: Bool
}

// MARK: - Backend wire model (matches your Cloud Function JSON) — lenient decoding
private struct BackendPayload: Codable {
    let title: String?
    let strengths: [String]?
    let food_rule: String?
    let active_ingredients: [String]?
    let min_interval_hours: Int?
    let interactions_to_avoid: [String]?
    let common_side_effects: [String]?
    let how_to_take: [String]?
    let what_for: [String]?
    let rxcui: String?
    let id: String?
}

// MARK: - HTTP client
enum DrugInfo: DrugInfoProvider {

    // Map backend → app-facing model (with defaults for missing fields)
    private static func mapToAppModel(_ b: BackendPayload, fallbackTitle: String) -> DrugPayload {
        let mappedFood: String? = {
            switch b.food_rule ?? "none" {
            case "after_food": return "afterFood"
            case "before_food": return "beforeFood"
            case "with_food": return "withFood"
            case "none": return "none"
            default: return nil
            }
        }()

        // Helper to ensure lists are summarized and concise
        func summarize(_ list: [String]?) -> [String] {
            guard let list = list, !list.isEmpty else { return [] }
            let combined = list.joined(separator: "\n")
            return MedSummarizer.bullets(from: combined, max: 4)
        }

        return DrugPayload(
            title: (b.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle,
            strengths: b.strengths ?? [],
            dosageForms: [],
            foodRule: mappedFood,
            minIntervalHours: b.min_interval_hours,
            ingredients: b.active_ingredients ?? [],
            indications: summarize(b.what_for),
            howToTake: summarize(b.how_to_take),
            commonSideEffects: summarize(b.common_side_effects),
            importantWarnings: [],
            interactionsToAvoid: summarize(b.interactions_to_avoid),
            references: nil,
            kbKey: nil,
            rxcui: b.rxcui,
            id: b.id.flatMap { UUID(uuidString: $0) }
        )
    }

    /// Build DrugPayload from openFDA MedDetails + strengths (fallback when backend fails)
    private static func payloadFromOpenFDA(medName: String, details: MedDetails, strengths: [String]) -> DrugPayload {
        func summarize(_ s: String) -> [String] {
            MedSummarizer.bullets(from: s, max: 4)
        }

        return DrugPayload(
            title: details.title.isEmpty ? medName : details.title,
            strengths: strengths.isEmpty ? (details.dosage.isEmpty ? [] : [details.dosage]) : strengths,
            dosageForms: [],
            foodRule: nil,
            minIntervalHours: nil,
            ingredients: details.ingredients,
            indications: summarize(details.uses),
            howToTake: summarize(details.dosage),
            commonSideEffects: summarize(details.sideEffects),
            importantWarnings: summarize(details.warnings),
            interactionsToAvoid: summarize(details.interactions),
            references: nil,
            kbKey: nil,
            rxcui: nil,
            id: nil
        )
    }

    // MARK: - Public API

    // NAME → details (Supabase Edge Function first, then openFDA fallback)
    static func fetchDetails(name: String, lang: String = "English") async throws -> DrugPayload {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(domain: "DrugInfo", code: -1, userInfo: [NSLocalizedDescriptionKey: "Empty medication name"])
        }

        // 1) Try Supabase Edge Function (GPT + RAG) first
        do {
            let backend: BackendPayload = try await SupabaseManager.shared.client.functions.invoke(
                "drug-intel",
                options: .init(
                    headers: ["apikey": SupabaseManager.shared.supabaseKey],
                    body: ["name": trimmed, "lang": lang]
                )
            )
            return mapToAppModel(backend, fallbackTitle: trimmed)
        } catch {
            print("Supabase drug-intel error: \(error)")
            // 2) Fallback: openFDA label + NDC strengths (No translation here)
            if let details = try? await OpenFDAService.fetchDetails(forName: trimmed) {
                let strengths = (try? await OpenFDAService.fetchDosageOptions(forName: trimmed)) ?? []
                return payloadFromOpenFDA(medName: trimmed, details: details, strengths: strengths)
            }
            throw error
        }
    }

    // List of RXCUIs → Interaction alerts
    static func checkInteractions(rxcuis: [String], lang: String = "English") async throws -> [InteractionAlert] {
        guard rxcuis.count >= 2 else { return [] }
        
        struct InteractionRequest: Encodable {
            let rxcuis: [String]
            let lang: String
        }
        
        struct InteractionResponse: Codable {
            let interactions: [InteractionAlert]
        }
        
        do {
            let response: InteractionResponse = try await SupabaseManager.shared.client.functions.invoke(
                "check-interactions",
                options: .init(
                    headers: ["apikey": SupabaseManager.shared.supabaseKey],
                    body: InteractionRequest(rxcuis: rxcuis, lang: lang)
                )
            )
            return response.interactions
        } catch {
            print("Supabase check-interactions error: \(error)")
            return []
        }
    }

    // NAME → strength options (reuse the same call)
    static func fetchDosageOptions(name: String) async throws -> [String] {
        let payload = try await fetchDetails(name: name)
        return payload.strengths
    }

    // IMAGE → candidates (send base64 to your Supabase Edge Function)
    static func analyzeImage(base64: String) async throws -> ScanResult {
        do {
            let result: ScanResult = try await SupabaseManager.shared.client.functions.invoke(
                "image-to-drug",
                options: .init(
                    headers: ["apikey": SupabaseManager.shared.supabaseKey],
                    body: ["image": base64]
                )
            )
            return result
        } catch {
            print("Supabase image-to-drug error: \(error)")
            throw error
        }
    }

    // Server-Side Safety Engine
    static func checkSafety(patientId: String?, deviceToken: String?, medications: [SafetyMedicationInput], lang: String = "English") async throws -> SafetyCheckResponse {
        struct SafetyRequest: Encodable {
            let patient_id: String?
            let device_token: String?
            let medications: [SafetyMedicationInput]
            let lang: String
        }

        do {
            let requestContext = resolvedPatientRequestContext(patientId: patientId, deviceToken: deviceToken)
            let requestBody = SafetyRequest(
                patient_id: requestContext.patientId,
                device_token: requestContext.deviceToken,
                medications: medications,
                lang: lang
            )
            var headers = ["apikey": SupabaseManager.shared.supabaseKey]
            if let accessToken = SupabaseManager.shared.client.auth.currentSession?.accessToken {
                headers["Authorization"] = "Bearer \(accessToken)"
            }

            #if DEBUG
            logSafetyRequest(
                patientId: requestContext.patientId,
                deviceToken: requestContext.deviceToken,
                medications: medications,
                lang: lang
            )
            #endif

            let result: SafetyCheckResponse = try await SupabaseManager.shared.client.functions.invoke(
                "check-interactions",
                options: .init(
                    headers: headers,
                    body: requestBody
                )
            )

            #if DEBUG
            logSafetyResponse(result)
            #endif

            return result
        } catch {
            print("Supabase check-interactions (safety) error: \(error)")
            throw error
        }
    }

    // Schedule Parsing
    static func parseSchedule(text: String, lang: String = "English") async throws -> ParsedSchedule {
        do {
            let result: ParsedSchedule = try await SupabaseManager.shared.client.functions.invoke(
                "parse-schedule",
                options: .init(
                    headers: ["apikey": SupabaseManager.shared.supabaseKey],
                    body: ["text": text, "lang": lang]
                )
            )
            return result
        } catch {
            print("Supabase parse-schedule error: \(error)")
            throw error
        }
    }

    // List Devices
    static func listDevices(patientId: String) async throws -> [PatientDevice] {
        do {
            let result: ListDevicesResponse = try await SupabaseManager.shared.client.functions.invoke(
                "list-patient-devices",
                options: .init(
                    headers: ["apikey": SupabaseManager.shared.supabaseKey],
                    body: ["patient_id": patientId]
                )
            )
            return result.devices
        } catch {
            print("Supabase list-patient-devices error: \(error)")
            throw error
        }
    }

    // Revoke Device
    static func revokeDevice(patientId: String, deviceId: String) async throws {
        do {
            let _: [String: Bool] = try await SupabaseManager.shared.client.functions.invoke(
                "revoke-patient-device",
                options: .init(
                    headers: ["apikey": SupabaseManager.shared.supabaseKey],
                    body: ["patient_id": patientId, "patient_device_id": deviceId]
                )
            )
        } catch {
            print("Supabase revoke-patient-device error: \(error)")
            throw error
        }
    }
    
    // MARK: - Medical Profile
    
    private struct ProfileRequest: Encodable {
        let action: String
        let patient_id: String?
        let device_token: String?
        let allergy: Allergy?
        let condition: Condition?
        let id: String?
    }
    
    private static func invokeProfileFunction<T: Decodable>(_ request: ProfileRequest) async throws -> T {
        do {
            var headers = ["apikey": SupabaseManager.shared.supabaseKey]
            if let accessToken = SupabaseManager.shared.client.auth.currentSession?.accessToken {
                headers["Authorization"] = "Bearer \(accessToken)"
            }

            return try await SupabaseManager.shared.client.functions.invoke(
                "patient-profile",
                options: .init(method: .post, headers: headers, body: request)
            )
        } catch {
            print("Supabase patient-profile error: \(error)")
            throw error
        }
    }
    
    static func listAllergies(patientId: String?) async throws -> [Allergy] {
        struct Res: Decodable { let allergies: [Allergy] }
        let context = resolvedPatientRequestContext(patientId: patientId, deviceToken: SupabaseManager.shared.patientDeviceToken)
        let res: Res = try await invokeProfileFunction(ProfileRequest(
            action: "list_allergies",
            patient_id: context.patientId,
            device_token: context.deviceToken,
            allergy: nil,
            condition: nil,
            id: nil
        ))
        return res.allergies
    }
    
    static func saveAllergy(patientId: String?, allergy: Allergy) async throws {
        struct Res: Decodable { let success: Bool }
        let context = resolvedPatientRequestContext(patientId: patientId, deviceToken: SupabaseManager.shared.patientDeviceToken)
        let _: Res = try await invokeProfileFunction(ProfileRequest(
            action: "save_allergy",
            patient_id: context.patientId,
            device_token: context.deviceToken,
            allergy: allergy,
            condition: nil,
            id: nil
        ))
        NotificationCenter.default.post(name: .medicalProfileChanged, object: nil)
    }
    
    static func deactivateAllergy(patientId: String?, id: String) async throws {
        struct Res: Decodable { let success: Bool }
        let context = resolvedPatientRequestContext(patientId: patientId, deviceToken: SupabaseManager.shared.patientDeviceToken)
        let _: Res = try await invokeProfileFunction(ProfileRequest(
            action: "deactivate_allergy",
            patient_id: context.patientId,
            device_token: context.deviceToken,
            allergy: nil,
            condition: nil,
            id: id
        ))
        NotificationCenter.default.post(name: .medicalProfileChanged, object: nil)
    }
    
    static func listConditions(patientId: String?) async throws -> [Condition] {
        struct Res: Decodable { let conditions: [Condition] }
        let context = resolvedPatientRequestContext(patientId: patientId, deviceToken: SupabaseManager.shared.patientDeviceToken)
        let res: Res = try await invokeProfileFunction(ProfileRequest(
            action: "list_conditions",
            patient_id: context.patientId,
            device_token: context.deviceToken,
            allergy: nil,
            condition: nil,
            id: nil
        ))
        return res.conditions
    }
    
    static func saveCondition(patientId: String?, condition: Condition) async throws {
        struct Res: Decodable { let success: Bool }
        let context = resolvedPatientRequestContext(patientId: patientId, deviceToken: SupabaseManager.shared.patientDeviceToken)
        let _: Res = try await invokeProfileFunction(ProfileRequest(
            action: "save_condition",
            patient_id: context.patientId,
            device_token: context.deviceToken,
            allergy: nil,
            condition: condition,
            id: nil
        ))
        NotificationCenter.default.post(name: .medicalProfileChanged, object: nil)
    }
    
    static func deactivateCondition(patientId: String?, id: String) async throws {
        struct Res: Decodable { let success: Bool }
        let context = resolvedPatientRequestContext(patientId: patientId, deviceToken: SupabaseManager.shared.patientDeviceToken)
        let _: Res = try await invokeProfileFunction(ProfileRequest(
            action: "deactivate_condition",
            patient_id: context.patientId,
            device_token: context.deviceToken,
            allergy: nil,
            condition: nil,
            id: id
        ))
        NotificationCenter.default.post(name: .medicalProfileChanged, object: nil)
    }

    private static func resolvedPatientRequestContext(patientId: String?, deviceToken: String?) -> PatientRequestContext {
        let supabase = SupabaseManager.shared

        if supabase.isPatientMode {
            return PatientRequestContext(
                patientId: nil,
                deviceToken: (deviceToken?.isEmpty == false ? deviceToken : supabase.patientDeviceToken)
            )
        }

        let resolvedPatientId = patientId ?? supabase.currentUserID?.uuidString.lowercased()
        return PatientRequestContext(patientId: resolvedPatientId, deviceToken: nil)
    }

    #if DEBUG
    private static func logSafetyRequest(patientId: String?, deviceToken: String?, medications: [SafetyMedicationInput], lang: String) {
        let meds = medications.map {
            RedactedSafetyMedication(
                id: $0.id,
                name: $0.name,
                rxcui: $0.rxcui,
                ingredients: $0.ingredients
            )
        }

        let redacted = RedactedSafetyRequest(
            patient_id: patientId,
            device_token_present: deviceToken?.isEmpty == false,
            medications: meds,
            lang: lang
        )

        if let redactedData = try? JSONEncoder().encode(redacted),
           let json = String(data: redactedData, encoding: .utf8) {
            print("check-interactions request JSON: \(json)")
        }
    }

    private static func logSafetyResponse(_ response: SafetyCheckResponse) {
        if let data = try? JSONEncoder().encode(response),
           let json = String(data: data, encoding: .utf8) {
            print("check-interactions response JSON: \(json)")
        }
    }
    #endif
}
