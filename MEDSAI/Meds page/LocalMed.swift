import Foundation

// MARK: - Local model (Postgres-backed via Supabase)
struct LocalMed: Identifiable, Hashable, Equatable {
    let id: String
    var name: String
    var dosage: String
    var frequencyPerDay: Int
    var startDate: Date
    var endDate: Date
    var foodRule: FoodRule
    var notes: String?
    var ingredients: [String]?
    var minIntervalHours: Int?
    var isArchived: Bool
    var catalogId: String? // The UUID from the global medications catalog

    init(
        id: String = UUID().uuidString,
        name: String,
        dosage: String,
        frequencyPerDay: Int,
        startDate: Date,
        endDate: Date,
        foodRule: FoodRule = .none,
        notes: String? = nil,
        ingredients: [String]? = nil,
        minIntervalHours: Int? = nil,
        isArchived: Bool = false,
        catalogId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.frequencyPerDay = frequencyPerDay
        self.startDate = startDate
        self.endDate = endDate
        self.foodRule = foodRule
        self.notes = notes
        self.ingredients = ingredients
        self.minIntervalHours = minIntervalHours
        self.isArchived = isArchived
        self.catalogId = catalogId
    }

    /// Decode from Supabase row
    struct DBRow: Decodable {
        let id: String
        let dosage: String
        let frequency_per_day: Int
        let frequency_hours: Int?
        let start_date: String?
        let end_date: String?
        let notes: String?
        let is_active: Bool
        let medication_id: String?
        // Joined medication name
        struct MedRef: Decodable { let name: String; let food_rule: String? }
        let medications: MedRef?
    }

    init?(row: DBRow) {
        self.id = row.id
        self.dosage = row.dosage
        self.frequencyPerDay = row.frequency_per_day
        self.minIntervalHours = row.frequency_hours
        self.notes = row.notes
        self.isArchived = !row.is_active
        self.name = row.medications?.name ?? "Unknown"
        self.catalogId = row.medication_id

        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate]
        self.startDate = df.date(from: row.start_date ?? "") ?? Date()
        self.endDate = df.date(from: row.end_date ?? "") ?? Calendar.current.date(byAdding: .day, value: 14, to: Date())!

        let frRaw = row.medications?.food_rule ?? FoodRule.none.rawValue
        self.foodRule = FoodRule(rawValue: frRaw) ?? .none
        self.ingredients = nil
    }
}
