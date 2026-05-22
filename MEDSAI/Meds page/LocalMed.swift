import Foundation

enum MedicationSourceType: String, Codable, CaseIterable, Hashable {
    case identified
    case manual

    static func fromStorage(_ value: String?, medicationId: String?) -> MedicationSourceType {
        if let value, value.lowercased() == "manual" { return .manual }
        return medicationId == nil ? .manual : .identified
    }
}

enum MedicationScheduleMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case daily
    case weekly
    case specificDays
    case everyXDays
    case asNeeded
    case emergencyOnly

    var id: String { rawValue }

    static func fromStorage(_ value: String?, isPrn: Bool?) -> MedicationScheduleMode {
        switch value {
        case "weekly": return .weekly
        case "specific_days": return .specificDays
        case "every_x_days": return .everyXDays
        case "as_needed": return .asNeeded
        case "emergency_only": return .emergencyOnly
        default: return isPrn == true ? .asNeeded : .daily
        }
    }

    var storageValue: String {
        switch self {
        case .daily: return "daily"
        case .weekly: return "weekly"
        case .specificDays: return "specific_days"
        case .everyXDays: return "every_x_days"
        case .asNeeded: return "as_needed"
        case .emergencyOnly: return "emergency_only"
        }
    }

    var isPRN: Bool { self == .asNeeded || self == .emergencyOnly }
}

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
    var sourceType: MedicationSourceType
    var medicationForm: String?
    var customFormText: String?
    var strengthValue: Double?
    var strengthUnit: String?
    var customUnitText: String?
    var doseAmount: Double?
    var doseAmountUnit: String?
    var doseQuantity: Double?
    var doseUnit: String?
    var doseQuantityUnit: String?
    var strengthAmount: Double?
    var parsedStrengthUnit: String?
    var concentrationAmount: Double?
    var concentrationUnit: String?
    var route: String?
    var applicationArea: String?
    var doseDisplay: String?
    var foodRuleSource: String?
    var doseDetailsSource: String?
    var isDoseAutoFilled: Bool
    var doseDetailsConfirmedByUser: Bool
    var scheduleMode: MedicationScheduleMode
    var timesPerDay: Int?
    var timesPerWeek: Int?
    var selectedWeekdays: [Int]
    var intervalDays: Int?
    var remindersEnabled: Bool
    var caregiverRemindersEnabled: Bool?
    var visualShape: String?
    var visualColor: String?
    var visualBackgroundColor: String?
    var refillReminderEnabled: Bool
    var refillCurrentSupply: Double?
    var refillSupplyUnit: String?
    var refillThresholdQuantity: Double?
    var refillEstimatedRunoutDate: Date?
    var refillReminderDate: Date?
    var refillReminderMode: String?
    var refillNotes: String?
    var sourceMetadata: String?
    var scanSource: String?
    var scanConfidence: Double?
    var scanConfirmedByUser: Bool?
    var scanExtractedFields: MedicationExtractedFields?
    var scanCandidateSnapshot: [MedicationScanCandidate]?

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
        catalogId: String? = nil,
        sourceType: MedicationSourceType? = nil,
        medicationForm: String? = nil,
        customFormText: String? = nil,
        strengthValue: Double? = nil,
        strengthUnit: String? = nil,
        customUnitText: String? = nil,
        doseAmount: Double? = nil,
        doseAmountUnit: String? = nil,
        doseQuantity: Double? = nil,
        doseUnit: String? = nil,
        doseQuantityUnit: String? = nil,
        strengthAmount: Double? = nil,
        parsedStrengthUnit: String? = nil,
        concentrationAmount: Double? = nil,
        concentrationUnit: String? = nil,
        route: String? = nil,
        applicationArea: String? = nil,
        doseDisplay: String? = nil,
        foodRuleSource: String? = nil,
        doseDetailsSource: String? = nil,
        isDoseAutoFilled: Bool = false,
        doseDetailsConfirmedByUser: Bool = false,
        scheduleMode: MedicationScheduleMode? = nil,
        timesPerDay: Int? = nil,
        timesPerWeek: Int? = nil,
        selectedWeekdays: [Int] = [],
        intervalDays: Int? = nil,
        remindersEnabled: Bool = true,
        caregiverRemindersEnabled: Bool? = nil,
        visualShape: String? = nil,
        visualColor: String? = nil,
        visualBackgroundColor: String? = nil,
        refillReminderEnabled: Bool = false,
        refillCurrentSupply: Double? = nil,
        refillSupplyUnit: String? = nil,
        refillThresholdQuantity: Double? = nil,
        refillEstimatedRunoutDate: Date? = nil,
        refillReminderDate: Date? = nil,
        refillReminderMode: String? = nil,
        refillNotes: String? = nil,
        sourceMetadata: String? = nil,
        scanSource: String? = nil,
        scanConfidence: Double? = nil,
        scanConfirmedByUser: Bool? = nil,
        scanExtractedFields: MedicationExtractedFields? = nil,
        scanCandidateSnapshot: [MedicationScanCandidate]? = nil
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
        self.sourceType = sourceType ?? MedicationSourceType.fromStorage(nil, medicationId: catalogId)
        self.medicationForm = medicationForm
        self.customFormText = customFormText
        self.strengthValue = strengthValue
        self.strengthUnit = strengthUnit
        self.customUnitText = customUnitText
        self.doseAmount = doseAmount
        self.doseAmountUnit = doseAmountUnit
        self.doseQuantity = doseQuantity
        self.doseUnit = doseUnit
        self.doseQuantityUnit = doseQuantityUnit
        self.strengthAmount = strengthAmount
        self.parsedStrengthUnit = parsedStrengthUnit
        self.concentrationAmount = concentrationAmount
        self.concentrationUnit = concentrationUnit
        self.route = route
        self.applicationArea = applicationArea
        self.doseDisplay = doseDisplay
        self.foodRuleSource = foodRuleSource
        self.doseDetailsSource = doseDetailsSource
        self.isDoseAutoFilled = isDoseAutoFilled
        self.doseDetailsConfirmedByUser = doseDetailsConfirmedByUser
        self.scheduleMode = scheduleMode ?? (asNeeded ? .asNeeded : .daily)
        self.timesPerDay = timesPerDay
        self.timesPerWeek = timesPerWeek
        self.selectedWeekdays = selectedWeekdays
        self.intervalDays = intervalDays
        self.remindersEnabled = remindersEnabled
        self.caregiverRemindersEnabled = caregiverRemindersEnabled
        self.visualShape = visualShape
        self.visualColor = visualColor
        self.visualBackgroundColor = visualBackgroundColor
        self.refillReminderEnabled = refillReminderEnabled
        self.refillCurrentSupply = refillCurrentSupply
        self.refillSupplyUnit = refillSupplyUnit
        self.refillThresholdQuantity = refillThresholdQuantity
        self.refillEstimatedRunoutDate = refillEstimatedRunoutDate
        self.refillReminderDate = refillReminderDate
        self.refillReminderMode = refillReminderMode
        self.refillNotes = refillNotes
        self.sourceMetadata = sourceMetadata
        self.scanSource = scanSource
        self.scanConfidence = scanConfidence
        self.scanConfirmedByUser = scanConfirmedByUser
        self.scanExtractedFields = scanExtractedFields
        self.scanCandidateSnapshot = scanCandidateSnapshot
    }

    /// Decode from Supabase row
    struct DBRow: Decodable {
        let id: String
        let name: String?
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
        let medication_name: String?
        let source_type: String?
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
        let is_dose_auto_filled: Bool?
        let dose_details_confirmed_by_user: Bool?
        let schedule_mode: String?
        let times_per_day: Int?
        let times_per_week: Int?
        let selected_weekdays: [Int]?
        let interval_days: Int?
        let reminders_enabled: Bool?
        let caregiver_reminders_enabled: Bool?
        let visual_shape: String?
        let visual_color: String?
        let visual_background_color: String?
        let refill_reminder_enabled: Bool?
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
        self.name = row.medications?.name ?? row.medication_name ?? row.name ?? "Unknown"
        self.catalogId = row.medication_id
        self.rxcui = row.medications?.rxcui
        self.ingredients = row.medications?.active_ingredients
        self.dosageTimes = row.dosage_times ?? []
        self.asNeeded = row.is_prn ?? false
        self.isManualSchedule = row.is_manual_schedule ?? false
        self.sourceType = MedicationSourceType.fromStorage(row.source_type, medicationId: row.medication_id)
        self.medicationForm = row.medication_form
        self.customFormText = row.custom_form_text
        self.strengthValue = row.strength_value
        self.strengthUnit = row.strength_unit
        self.customUnitText = row.custom_unit_text
        self.doseAmount = row.dose_amount
        self.doseAmountUnit = row.dose_amount_unit
        self.doseQuantity = row.dose_quantity
        self.doseUnit = row.dose_unit
        self.doseQuantityUnit = row.dose_quantity_unit
        self.strengthAmount = row.strength_amount ?? row.strength_value
        self.parsedStrengthUnit = row.parsed_strength_unit ?? row.strength_unit
        self.concentrationAmount = row.concentration_amount
        self.concentrationUnit = row.concentration_unit
        self.route = row.route
        self.applicationArea = row.application_area
        self.doseDisplay = row.dose_display
        self.foodRuleSource = row.food_rule_source
        self.doseDetailsSource = row.dose_details_source
        self.isDoseAutoFilled = row.is_dose_auto_filled ?? false
        self.doseDetailsConfirmedByUser = row.dose_details_confirmed_by_user ?? false
        self.scheduleMode = MedicationScheduleMode.fromStorage(row.schedule_mode, isPrn: row.is_prn)
        self.timesPerDay = row.times_per_day ?? row.frequency_per_day
        self.timesPerWeek = row.times_per_week
        self.selectedWeekdays = row.selected_weekdays ?? []
        self.intervalDays = row.interval_days
        self.remindersEnabled = row.reminders_enabled ?? true
        self.caregiverRemindersEnabled = row.caregiver_reminders_enabled
        self.visualShape = row.visual_shape
        self.visualColor = row.visual_color
        self.visualBackgroundColor = row.visual_background_color
        self.refillReminderEnabled = row.refill_reminder_enabled ?? false
        self.refillCurrentSupply = row.refill_current_supply
        self.refillSupplyUnit = row.refill_supply_unit
        self.refillThresholdQuantity = row.refill_threshold_quantity
        self.refillEstimatedRunoutDate = Self.parseOptionalDate(row.refill_estimated_runout_date)
        self.refillReminderDate = Self.parseOptionalDate(row.refill_reminder_date)
        self.refillReminderMode = row.refill_reminder_mode
        self.refillNotes = row.refill_notes
        self.scanSource = row.scan_source
        self.scanConfidence = row.scan_confidence
        self.scanConfirmedByUser = row.scan_confirmed_by_user
        self.scanExtractedFields = row.scan_extracted_fields
        self.scanCandidateSnapshot = row.scan_candidate_snapshot
        self.sourceMetadata = nil

        let df = ISO8601DateFormatter()
        df.formatOptions = [.withFullDate]
        self.startDate = df.date(from: row.start_date ?? "") ?? Date()
        self.endDate = df.date(from: row.end_date ?? "") ?? Calendar.current.date(byAdding: .day, value: 14, to: Date())!

        self.foodRule = FoodRule.fromStorage(row.food_rule ?? row.medications?.food_rule)
    }

    private static func parseOptionalDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let internet = ISO8601DateFormatter()
        if let date = internet.date(from: value) { return date }
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        return day.date(from: value)
    }

    func isScheduled(on date: Date, calendar: Calendar = .current) -> Bool {
        if isArchived || scheduleMode.isPRN || asNeeded { return false }
        let day = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard day >= start && day <= end else { return false }

        switch scheduleMode {
        case .daily:
            return true
        case .weekly, .specificDays:
            let weekday = calendar.component(.weekday, from: day)
            return !selectedWeekdays.isEmpty && selectedWeekdays.contains(weekday)
        case .everyXDays:
            let interval = max(intervalDays ?? 1, 1)
            let days = calendar.dateComponents([.day], from: start, to: day).day ?? 0
            return days >= 0 && days % interval == 0
        case .asNeeded, .emergencyOnly:
            return false
        }
    }

    func shouldShowOnDate(_ date: Date, calendar: Calendar = .current) -> Bool {
        if isArchived { return false }
        let day = calendar.startOfDay(for: date)
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard day >= start && day <= end else { return false }

        if scheduleMode.isPRN || asNeeded {
            return true
        }

        switch scheduleMode {
        case .daily:
            return true
        case .weekly, .specificDays:
            if selectedWeekdays.isEmpty {
                return true
            }
            let weekday = calendar.component(.weekday, from: day)
            return selectedWeekdays.contains(weekday)
        case .everyXDays:
            let interval = max(intervalDays ?? 1, 1)
            let days = calendar.dateComponents([.day], from: start, to: day).day ?? 0
            return days >= 0 && days % interval == 0
        case .asNeeded, .emergencyOnly:
            return true
        }
    }
}

extension LocalMed {
    func scheduleSummary(isArabic: Bool = false) -> String {
        if asNeeded || scheduleMode.isPRN {
            return scheduleMode == .emergencyOnly
                ? (isArabic ? "للطوارئ فقط" : "Emergency only")
                : (isArabic ? "عند الحاجة" : "As needed")
        }
        switch scheduleMode {
        case .daily:
            return DoseTextFormatter.formatFrequency(for: self, isArabic: isArabic)
        case .weekly:
            let days = weekdaySummary(isArabic: isArabic)
            return days.isEmpty ? (isArabic ? "أسبوعيًا" : "Weekly") : days
        case .specificDays:
            let days = weekdaySummary(isArabic: isArabic)
            return days.isEmpty ? (isArabic ? "أيام محددة" : "Selected days") : days
        case .everyXDays:
            return isArabic ? "كل \(intervalDays ?? 1) أيام" : "Every \(intervalDays ?? 1) days"
        case .asNeeded:
            return isArabic ? "عند الحاجة" : "As needed"
        case .emergencyOnly:
            return isArabic ? "للطوارئ فقط" : "Emergency only"
        }
    }

    var strengthSummary: String? {
        guard let strengthValue, let strengthUnit, strengthValue > 0 else { return nil }
        return "\(strengthValue.formatted()) \(strengthUnit)"
    }

    func weekdaySummary(isArabic: Bool = false) -> String {
        let labels: [Int: String] = isArabic
            ? [1: "الأحد", 2: "الاثنين", 3: "الثلاثاء", 4: "الأربعاء", 5: "الخميس", 6: "الجمعة", 7: "السبت"]
            : [1: "Sun", 2: "Mon", 3: "Tue", 4: "Wed", 5: "Thu", 6: "Fri", 7: "Sat"]
        return selectedWeekdays.sorted().compactMap { labels[$0] }.joined(separator: isArabic ? "، " : ", ")
    }

    func foodRuleLabel(isArabic: Bool = false) -> String {
        DoseTextFormatter.formatFoodInstruction(foodRule, isArabic: isArabic) ?? ""
    }
}
