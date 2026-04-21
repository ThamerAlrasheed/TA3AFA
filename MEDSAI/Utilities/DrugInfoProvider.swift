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
    let foodRule: String?            // "afterFood" | "beforeFood" | "none"
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

// MARK: - Protocol: updated
protocol DrugInfoProvider {
    static func fetchDetails(name: String, lang: String) async throws -> DrugPayload
    static func fetchDosageOptions(name: String) async throws -> [String]
    static func analyzeImage(base64: String) async throws -> DrugPayload
    static func checkInteractions(rxcuis: [String], lang: String) async throws -> [InteractionAlert]
}

// MARK: - Backend wire model (matches your Cloud Function JSON) — lenient decoding
private struct BackendPayload: Codable {
    let title: String?
    let strengths: [String]?
    let food_rule: String?
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
            ingredients: [],
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

    // IMAGE → details (send base64 to your Supabase Edge Function)
    static func analyzeImage(base64: String) async throws -> DrugPayload {
        do {
            let backend: BackendPayload = try await SupabaseManager.shared.client.functions.invoke(
                "image-to-drug",
                options: .init(
                    headers: ["apikey": SupabaseManager.shared.supabaseKey],
                    body: ["image": base64]
                )
            )
            return mapToAppModel(backend, fallbackTitle: "Medication")
        } catch {
            print("Supabase image-to-drug error: \(error)")
            throw error
        }
    }
}

