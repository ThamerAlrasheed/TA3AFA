import Foundation

// MARK: - Canonical model we store per medication (global, not per-user)
struct MedCatalogEntry: Codable, Identifiable {
    var id: String { key }
    let key: String
    var name: String
    var aliases: [String]
    var imageURLs: [String]
    var payload: DrugPayload

    var createdAt: Date
    var updatedAt: Date

    init(key: String, name: String, aliases: [String] = [], imageURLs: [String] = [], payload: DrugPayload) {
        self.key = key
        self.name = name
        self.aliases = aliases
        self.imageURLs = imageURLs
        self.payload = payload
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Repo for global medications catalog (Supabase-backed)
final class MedCatalogRepo {
    private struct MedicationInsertPayload: Encodable {
        let name: String
        let how_to_take: [String]?
        let food_rule: String
        let min_interval_hours: Int?
        let strengths: [String]?
        let common_side_effects: [String]?
        let interactions_to_avoid: [String]?
    }

    static let shared = MedCatalogRepo()
    private init() {}

    private var supabase: SupabaseManager { .shared }

    /// Normalize user input to a stable key
    func normalizeKey(_ raw: String) -> String {
        let lower = raw.lowercased()
        let replaced = lower.replacingOccurrences(of: #"[^a-z0-9]+"#, with: "_", options: .regularExpression)
        return replaced.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    /// Read by name if present
    func fetch(name: String) async throws -> MedCatalogEntry? {
        struct Row: Decodable {
            let id: String
            let name: String
            let how_to_take: [String]?
            let common_side_effects: [String]?
            let interactions_to_avoid: [String]?
            let food_rule: String?
            let min_interval_hours: Int?
            let strengths: [String]?
        }

        let rows: [Row] = try await supabase.client
            .from("medications")
            .select()
            .eq("name", value: name)
            .limit(1)
            .execute()
            .value

        guard let row = rows.first else { return nil }

        let payload = DrugPayload(
            title: row.name,
            strengths: row.strengths ?? [],
            dosageForms: [],
            foodRule: row.food_rule,
            minIntervalHours: row.min_interval_hours,
            ingredients: [],
            indications: [],
            howToTake: row.how_to_take ?? [],
            commonSideEffects: row.common_side_effects ?? [],
            importantWarnings: [],
            interactionsToAvoid: row.interactions_to_avoid ?? [],
            references: nil,
            kbKey: nil
        )

        return MedCatalogEntry(
            key: normalizeKey(row.name),
            name: row.name,
            payload: payload
        )
    }

    /// Upsert from payload + original name
    func upsert(from payload: DrugPayload, searchedName: String, imageURL: URL? = nil) async throws -> MedCatalogEntry {
        let display = payload.title.isEmpty ? searchedName : payload.title

        // Try to find existing
        struct ExistingRow: Decodable { let id: String; let name: String }
        let existing: [ExistingRow] = try await supabase.client
            .from("medications")
            .select("id, name")
            .eq("name", value: display)
            .limit(1)
            .execute()
            .value

        if existing.isEmpty {
            _ = try? await supabase.client
                .from("medications")
                .insert(
                    MedicationInsertPayload(
                        name: display,
                        how_to_take: payload.howToTake,
                        food_rule: payload.foodRule ?? "none",
                        min_interval_hours: payload.minIntervalHours,
                        strengths: payload.strengths,
                        common_side_effects: payload.commonSideEffects,
                        interactions_to_avoid: payload.interactionsToAvoid
                    )
                )
                .execute()
        }

        return MedCatalogEntry(
            key: normalizeKey(display),
            name: display,
            payload: payload
        )
    }
}
