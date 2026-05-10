import Foundation

struct LocalMed: Identifiable, Hashable, Equatable {
    let id: String
    var name: String
    var dosage: String
    var frequencyPerDay: Int
    var startDate: Date
    var endDate: Date
    var foodRule: FoodRule
    var dosageTimes: [String] // e.g. ["08:15:00"]
    var notes: String?
    var ingredients: [String]?
    var rxcui: String?
    var minIntervalHours: Int?
    var isArchived: Bool
    var asNeeded: Bool
    var isManualSchedule: Bool
    var catalogId: String? // The UUID from the global medications catalog

    init(
        id: String = UUID().uuidString,
        name: String,
        dosage: String,
        frequencyPerDay: Int,
        startDate: Date,
        endDate: Date,
        foodRule: FoodRule = .none,
        dosageTimes: [String] = [],
        notes: String? = nil,
        ingredients: [String]? = nil,
        rxcui: String? = nil,
        minIntervalHours: Int? = nil,
        isArchived: Bool = false,
        asNeeded: Bool = false,
        isManualSchedule: Bool = false,
        catalogId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.dosage = dosage
        self.frequencyPerDay = frequencyPerDay
        self.startDate = startDate
        self.endDate = endDate
        self.foodRule = foodRule
        self.dosageTimes = dosageTimes
        self.notes = notes
        self.ingredients = ingredients
        self.rxcui = rxcui
        self.minIntervalHours = minIntervalHours
        self.isArchived = isArchived
        self.asNeeded = asNeeded
        self.isManualSchedule = isManualSchedule
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
        let food_rule: String?
        let is_prn: Bool?
        let is_manual_schedule: Bool?
        let medication_id: String?
        let dosage_times: [String]?
        // Joined medication name
        struct MedRef: Decodable { 
            let name: String
            let food_rule: String?
            let rxcui: String?
            let active_ingredients: [String]?
        }
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
        self.rxcui = row.medications?.rxcui
        self.ingredients = row.medications?.active_ingredients
        self.dosageTimes = row.dosage_times ?? []
        self.asNeeded = row.is_prn ?? false
        self.isManualSchedule = row.is_manual_schedule ?? false

        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate]
        self.startDate = df.date(from: row.start_date ?? "") ?? Date()
        self.endDate = df.date(from: row.end_date ?? "") ?? Calendar.current.date(byAdding: .day, value: 14, to: Date())!

        self.foodRule = FoodRule.fromStorage(row.food_rule ?? row.medications?.food_rule)
    }
}
