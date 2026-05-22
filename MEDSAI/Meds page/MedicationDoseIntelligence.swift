import Foundation

struct DoseFieldVisibility: Hashable {
    var strengthVisible: Bool = true
    var concentrationVisible: Bool = false
    var quantityPerDoseVisible: Bool = true
    var doseFreeTextVisible: Bool = false
    var routeVisible: Bool = false
    var applicationAreaVisible: Bool = false
    var targetAreaVisible: Bool = false
    var wearDurationVisible: Bool = false
}

struct MedicationFormRule: Hashable {
    let formID: String
    let defaultDoseUnitOptions: [String]
    let foodTimingVisibleByDefault: Bool
    let visibility: DoseFieldVisibility
    let helperEnglish: String
    let helperArabic: String

    func helper(isArabic: Bool) -> String { isArabic ? helperArabic : helperEnglish }
}

enum MedicationFormRules {
    static func rule(for formID: String?) -> MedicationFormRule {
        switch normalizedForm(formID) {
        case "tablet":
            return MedicationFormRule(
                formID: "tablet",
                defaultDoseUnitOptions: ["tablets", "mg", "mcg", "g", "other"],
                foodTimingVisibleByDefault: true,
                visibility: DoseFieldVisibility(strengthVisible: true, quantityPerDoseVisible: true),
                helperEnglish: "Confirm the tablet strength and how many tablets are taken each time.",
                helperArabic: "أكد تركيز القرص وعدد الأقراص في كل مرة."
            )
        case "capsule":
            return MedicationFormRule(
                formID: "capsule",
                defaultDoseUnitOptions: ["capsules", "mg", "mcg", "g", "other"],
                foodTimingVisibleByDefault: true,
                visibility: DoseFieldVisibility(strengthVisible: true, quantityPerDoseVisible: true),
                helperEnglish: "Confirm capsule strength and capsules per intake.",
                helperArabic: "أكد تركيز الكبسولة وعدد الكبسولات في كل مرة."
            )
        case "liquid", "syrup", "suspension":
            return MedicationFormRule(
                formID: "liquid",
                defaultDoseUnitOptions: ["mL", "mg", "mcg", "drops", "other"],
                foodTimingVisibleByDefault: true,
                visibility: DoseFieldVisibility(strengthVisible: true, concentrationVisible: true, quantityPerDoseVisible: true),
                helperEnglish: "Use mL per dose. Add concentration if the bottle lists mg per mL.",
                helperArabic: "استخدم مل لكل جرعة. أضف التركيز إذا كان مكتوبًا على العبوة."
            )
        case "drops":
            return MedicationFormRule(
                formID: "drops",
                defaultDoseUnitOptions: ["drops", "mL", "other"],
                foodTimingVisibleByDefault: false,
                visibility: DoseFieldVisibility(strengthVisible: false, quantityPerDoseVisible: true, targetAreaVisible: true),
                helperEnglish: "Confirm drops per dose and target area.",
                helperArabic: "أكد عدد القطرات ومكان الاستخدام."
            )
        case "inhaler":
            return MedicationFormRule(
                formID: "inhaler",
                defaultDoseUnitOptions: ["puffs", "doses", "other"],
                foodTimingVisibleByDefault: false,
                visibility: DoseFieldVisibility(strengthVisible: false, quantityPerDoseVisible: true),
                helperEnglish: "Confirm puffs per use.",
                helperArabic: "أكد عدد البخات في كل مرة."
            )
        case "injection":
            return MedicationFormRule(
                formID: "injection",
                defaultDoseUnitOptions: ["units", "mL", "mg", "mcg", "IU", "other"],
                foodTimingVisibleByDefault: false,
                visibility: DoseFieldVisibility(strengthVisible: true, concentrationVisible: true, quantityPerDoseVisible: true, routeVisible: true),
                helperEnglish: "Confirm injection dose. Route is optional but useful.",
                helperArabic: "أكد جرعة الحقن. طريقة الحقن اختيارية لكنها مفيدة."
            )
        case "cream", "ointment", "gel":
            return MedicationFormRule(
                formID: "cream",
                defaultDoseUnitOptions: ["small amount", "medium amount", "large amount", "other"],
                foodTimingVisibleByDefault: false,
                visibility: DoseFieldVisibility(strengthVisible: false, quantityPerDoseVisible: false, doseFreeTextVisible: true, applicationAreaVisible: true),
                helperEnglish: "Describe how much to apply and where.",
                helperArabic: "اكتب كمية الاستخدام ومكان وضع الدواء."
            )
        case "patch":
            return MedicationFormRule(
                formID: "patch",
                defaultDoseUnitOptions: ["patches", "mg", "mcg/hour", "other"],
                foodTimingVisibleByDefault: false,
                visibility: DoseFieldVisibility(strengthVisible: true, quantityPerDoseVisible: true, applicationAreaVisible: true, wearDurationVisible: true),
                helperEnglish: "Confirm patch strength and replacement timing.",
                helperArabic: "أكد تركيز اللصقة ووقت استبدالها."
            )
        case "spray":
            return MedicationFormRule(
                formID: "spray",
                defaultDoseUnitOptions: ["sprays", "puffs", "doses", "other"],
                foodTimingVisibleByDefault: false,
                visibility: DoseFieldVisibility(strengthVisible: false, quantityPerDoseVisible: true, targetAreaVisible: true),
                helperEnglish: "Confirm sprays per dose and target area.",
                helperArabic: "أكد عدد الرشات ومكان الاستخدام."
            )
        case "suppository":
            return MedicationFormRule(
                formID: "suppository",
                defaultDoseUnitOptions: ["suppositories", "mg", "other"],
                foodTimingVisibleByDefault: false,
                visibility: DoseFieldVisibility(strengthVisible: true, quantityPerDoseVisible: true),
                helperEnglish: "Confirm suppository strength and count per use.",
                helperArabic: "أكد تركيز التحميلة والعدد في كل مرة."
            )
        default:
            return MedicationFormRule(
                formID: normalizedForm(formID),
                defaultDoseUnitOptions: ["mg", "mL", "doses", "units", "other"],
                foodTimingVisibleByDefault: true,
                visibility: DoseFieldVisibility(strengthVisible: true, concentrationVisible: true, quantityPerDoseVisible: true, doseFreeTextVisible: true),
                helperEnglish: "Confirm the dose details before continuing.",
                helperArabic: "أكد تفاصيل الجرعة قبل المتابعة."
            )
        }
    }

    static func shouldShowFoodTiming(formID: String?, foodRule: FoodRule, sourceBacked: Bool) -> Bool {
        if sourceBacked && foodRule != .none && foodRule != .notSure { return true }
        return rule(for: formID).foodTimingVisibleByDefault
    }

    static func normalizedForm(_ formID: String?) -> String {
        let value = (formID ?? "other")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
        switch value {
        case "syrup", "oral_liquid", "suspension": return "liquid"
        case "ointment", "gel": return value
        default: return value.isEmpty ? "other" : value
        }
    }
}

struct ParsedMedicationDoseDetails: Hashable {
    var originalText: String
    var doseAmount: Double?
    var doseUnit: String?
    var doseForm: String?
    var strengthAmount: Double?
    var strengthUnit: String?
    var concentrationAmount: Double?
    var concentrationUnit: String?
    var quantityPerDose: Double?
    var quantityUnit: String?
    var route: String?
    var applicationArea: String?
    var displayLabel: String
    var isConfident: Bool
}

enum MedicationDoseParser {
    static func parse(_ input: String, preferredForm: String?) -> ParsedMedicationDoseDetails {
        let cleaned = normalize(input)
        let detectedForm = detectForm(in: cleaned) ?? MedicationFormRules.normalizedForm(preferredForm)
        let concentration = parseConcentration(in: cleaned)
        let firstMeasurement = parseFirstMeasurement(in: cleaned)
        let countMeasurement = parseCountMeasurement(in: cleaned, form: detectedForm)
        let quantityUnit = countMeasurement?.unit ?? defaultQuantityUnit(for: detectedForm)
        let quantity = countMeasurement?.amount ?? defaultQuantity(for: detectedForm, text: cleaned)
        let strengthAmount = concentration?.amount ?? firstMeasurement?.amount
        let strengthUnit = concentration?.unit ?? firstMeasurement?.unit
        let doseAmount = countMeasurement?.amount ?? (detectedForm == "liquid" && firstMeasurement?.unit == "mL" ? firstMeasurement?.amount : nil)
        let doseUnit = countMeasurement?.unit ?? (detectedForm == "liquid" && firstMeasurement?.unit == "mL" ? "mL" : nil)
        let display = displayLabel(quantity: quantity, quantityUnit: quantityUnit, strengthAmount: strengthAmount, strengthUnit: strengthUnit, concentrationUnit: concentration?.unit, fallback: input)
        let confident = detectedForm != "other" && (quantity != nil || strengthAmount != nil || concentration != nil)

        return ParsedMedicationDoseDetails(
            originalText: input,
            doseAmount: doseAmount,
            doseUnit: doseUnit,
            doseForm: detectedForm,
            strengthAmount: strengthAmount,
            strengthUnit: strengthUnit,
            concentrationAmount: concentration?.amount,
            concentrationUnit: concentration?.unit,
            quantityPerDose: quantity,
            quantityUnit: quantityUnit,
            route: detectRoute(in: cleaned),
            applicationArea: detectApplicationArea(in: cleaned),
            displayLabel: display,
            isConfident: confident
        )
    }

    private static func normalize(_ value: String) -> String {
        value
            .applyingTransform(.toLatin, reverse: false)?
            .lowercased()
            .replacingOccurrences(of: "٫", with: ".")
            .replacingOccurrences(of: "مل", with: "ml")
            .replacingOccurrences(of: "مجم", with: "mg")
            .replacingOccurrences(of: "مج", with: "mg")
            .replacingOccurrences(of: "قرص", with: "tablet")
            .replacingOccurrences(of: "أقراص", with: "tablets")
            .replacingOccurrences(of: "كبسولة", with: "capsule")
            .replacingOccurrences(of: "قطرات", with: "drops")
            .replacingOccurrences(of: "قطرة", with: "drops")
            .replacingOccurrences(of: "بخة", with: "puff")
            .replacingOccurrences(of: "بخات", with: "puffs")
            ?? value.lowercased()
    }

    private static func parseConcentration(in text: String) -> (amount: Double, unit: String)? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(mg|mcg|g|iu|units?)\s*/\s*([0-9]+(?:\.[0-9]+)?\s*)?(ml|mL|l|dose)"#
        guard let match = firstMatch(pattern: pattern, in: text),
              let amount = Double(match[1]) else { return nil }
        let numerator = normalizeUnit(match[2])
        let denominator = normalizeUnit(match[4])
        return (amount, "\(numerator)/\(denominator)")
    }

    private static func parseFirstMeasurement(in text: String) -> (amount: Double, unit: String)? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(mg|mcg|g|ml|mL|iu|units?|drops?|puffs?|sprays?)"#
        guard let match = firstMatch(pattern: pattern, in: text),
              let amount = Double(match[1]) else { return nil }
        return (amount, normalizeUnit(match[2]))
    }

    private static func parseCountMeasurement(in text: String, form: String) -> (amount: Double, unit: String)? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(tablets?|tabs?|capsules?|caps?|drops?|puffs?|sprays?|patches?|suppositories?|doses?)"#
        guard let match = firstMatch(pattern: pattern, in: text),
              let amount = Double(match[1]) else { return nil }
        return (amount, normalizeUnit(match[2]))
    }

    private static func firstMatch(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : nsText.substring(with: range)
        }
    }

    private static func detectForm(in text: String) -> String? {
        let checks: [(String, String)] = [
            ("tablet|tablets|tab|tabs|pill|pills", "tablet"),
            ("capsule|capsules|cap|caps", "capsule"),
            ("syrup|suspension|oral liquid|liquid", "liquid"),
            ("drop|drops|eye|ear", "drops"),
            ("inhaler|puff|puffs", "inhaler"),
            ("injection|inject|insulin|syringe", "injection"),
            ("cream|ointment|gel", "cream"),
            ("patch|patches", "patch"),
            ("spray|sprays", "spray"),
            ("suppository|suppositories", "suppository")
        ]
        return checks.first { text.range(of: $0.0, options: .regularExpression) != nil }?.1
    }

    private static func detectRoute(in text: String) -> String? {
        if text.contains("subcutaneous") || text.contains("sc") { return "subcutaneous" }
        if text.contains("intramuscular") || text.contains("im") { return "intramuscular" }
        if text.contains("intravenous") || text.contains("iv") { return "intravenous" }
        return nil
    }

    private static func detectApplicationArea(in text: String) -> String? {
        if text.contains("eye") { return "eye" }
        if text.contains("ear") { return "ear" }
        if text.contains("nose") { return "nose" }
        if text.contains("skin") { return "skin" }
        if text.contains("oral") || text.contains("mouth") { return "oral" }
        return nil
    }

    private static func defaultQuantity(for form: String, text: String) -> Double? {
        switch form {
        case "tablet", "capsule", "patch", "suppository": return 1
        case "inhaler": return text.contains("2 puff") ? 2 : 1
        default: return nil
        }
    }

    private static func defaultQuantityUnit(for form: String) -> String? {
        switch form {
        case "tablet": return "tablets"
        case "capsule": return "capsules"
        case "drops": return "drops"
        case "inhaler": return "puffs"
        case "spray": return "sprays"
        case "patch": return "patches"
        case "suppository": return "suppositories"
        default: return nil
        }
    }

    private static func normalizeUnit(_ value: String) -> String {
        switch value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "ml": return "mL"
        case "iu": return "IU"
        case "unit", "units": return "units"
        case "tablet", "tablets", "tab", "tabs": return "tablets"
        case "capsule", "capsules", "cap", "caps": return "capsules"
        case "drop", "drops": return "drops"
        case "puff", "puffs": return "puffs"
        case "spray", "sprays": return "sprays"
        case "patch", "patches": return "patches"
        case "suppository", "suppositories": return "suppositories"
        case "dose", "doses": return "doses"
        default: return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func displayLabel(quantity: Double?, quantityUnit: String?, strengthAmount: Double?, strengthUnit: String?, concentrationUnit: String?, fallback: String) -> String {
        let quantityText = quantity.flatMap { amount in quantityUnit.map { "\(amount.formatted()) \($0)" } }
        let strengthText = strengthAmount.flatMap { amount in strengthUnit.map { "\(amount.formatted()) \($0)" } }
        if let quantityText, let strengthText { return "\(quantityText) / \(strengthText)" }
        if let strengthText { return strengthText }
        if let quantityText { return quantityText }
        return fallback.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension LocalMed {
    func doseActionText(isArabic: Bool = false) -> String {
        DoseTextFormatter.medicationTitle(name)
    }
}

enum DoseTextFormatter {
    static func medicationTitle(_ name: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Medication" : trimmed
    }

    static func formatDoseAmount(for med: LocalMed) -> String? {
        if let text = formatAmount(med.doseQuantity, unit: med.doseQuantityUnit ?? med.doseUnit, explicit: med.doseDetailsConfirmedByUser) {
            return text
        }
        if let text = formatAmount(med.doseAmount, unit: med.doseAmountUnit, explicit: med.doseDetailsConfirmedByUser) {
            return text
        }
        if let text = parseDisplayDose(med.doseDisplay, explicit: med.doseDetailsConfirmedByUser) {
            return text
        }
        if let text = parseDisplayDose(med.dosage, explicit: med.doseDetailsConfirmedByUser) {
            return text
        }
        return formatAmount(med.strengthValue ?? med.strengthAmount, unit: med.strengthUnit ?? med.parsedStrengthUnit, explicit: med.doseDetailsConfirmedByUser)
    }

    static func formatFrequency(for med: LocalMed, isArabic: Bool = false) -> String {
        if med.asNeeded || med.scheduleMode.isPRN {
            return isArabic ? "عند الحاجة" : "As needed"
        }
        let count = max(med.timesPerDay ?? med.frequencyPerDay, 0)
        guard count > 0 else {
            return isArabic ? "غير مجدول" : "Unscheduled"
        }
        if isArabic {
            return count == 1 ? "مرة يوميًا" : "\(count) مرات يوميًا"
        }
        switch count {
        case 1: return "Once daily"
        case 2: return "Twice daily"
        default: return "\(count) times daily"
        }
    }

    static func formatFoodInstruction(_ rule: FoodRule, isArabic: Bool = false) -> String? {
        switch rule {
        case .beforeFood: return isArabic ? "قبل الأكل" : "Before food"
        case .afterFood: return isArabic ? "بعد الأكل" : "After food"
        case .withFood: return isArabic ? "مع الأكل" : "With food"
        case .avoidWithFood: return isArabic ? "تجنب تناوله مع الطعام" : "Avoid with food"
        case .notSure: return isArabic ? "تعليمات الطعام غير مؤكدة" : "Food timing not sure"
        case .none: return nil
        }
    }

    static func shouldShowFoodInstruction(for med: LocalMed) -> Bool {
        med.foodRule != .none
    }

    static func deduplicatedTimeStrings(_ times: [String]) -> [String] {
        Array(Set(times.compactMap(normalizedHHmm))).sorted().map { "\($0):00" }
    }

    static func deduplicatedDoseDates(_ dates: [Date], calendar: Calendar = .current) -> [Date] {
        var seen = Set<String>()
        return dates
            .sorted()
            .filter { date in
                let key = normalizedHHmm(date, calendar: calendar)
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
    }

    static func deduplicatedDosePairs(_ pairs: [(Date, LocalMed)], calendar: Calendar = .current) -> [(Date, LocalMed)] {
        var seen = Set<String>()
        return pairs
            .sorted { $0.0 < $1.0 }
            .filter { date, med in
                let key = "\(med.id)|\(calendar.startOfDay(for: date).timeIntervalSince1970)|\(normalizedHHmm(date, calendar: calendar))"
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
    }

    private static func parseDisplayDose(_ value: String?, explicit: Bool) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()
        guard !lower.contains("/") && !lower.contains("mg/ml") && !lower.contains("mg / ml") else { return nil }

        let pattern = #"([0-9]+(?:[.,][0-9]+)?)\s*([A-Za-z/%]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              match.numberOfRanges >= 3,
              let amountRange = Range(match.range(at: 1), in: trimmed),
              let unitRange = Range(match.range(at: 2), in: trimmed) else {
            return nil
        }
        let amountText = String(trimmed[amountRange]).replacingOccurrences(of: ",", with: ".")
        return formatAmount(Double(amountText), unit: String(trimmed[unitRange]), explicit: explicit)
    }

    private static func formatAmount(_ amount: Double?, unit rawUnit: String?, explicit: Bool) -> String? {
        guard let amount, amount > 0 else { return nil }
        let unit = normalizedUnit(rawUnit)
        guard let unit else { return nil }
        guard isValid(amount: amount, unit: unit, explicit: explicit) else {
            #if DEBUG
            print("DoseTextFormatter hiding suspicious dose amount: \(amount) \(unit)")
            #endif
            return nil
        }
        return "\(formatNumber(amount)) \(displayUnit(unit, amount: amount))"
    }

    private static func isValid(amount: Double, unit: String, explicit: Bool) -> Bool {
        switch unit {
        case "tablet", "capsule", "pill", "drop", "spray", "puff":
            return (0.25...10).contains(amount)
        case "mg":
            return (0.01...5000).contains(amount)
        case "ml":
            return (0.01...100).contains(amount)
        case "mcg", "g", "iu", "%", "unit", "dose":
            return explicit ? amount <= 5000 : amount <= 1000
        default:
            return explicit && amount <= 1000
        }
    }

    private static func normalizedUnit(_ value: String?) -> String? {
        let unit = (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !unit.isEmpty else { return nil }
        if unit.contains("/") { return nil }
        switch unit {
        case "tablet", "tablets", "tab", "tabs": return "tablet"
        case "capsule", "capsules", "cap", "caps": return "capsule"
        case "pill", "pills": return "pill"
        case "drop", "drops": return "drop"
        case "spray", "sprays": return "spray"
        case "puff", "puffs": return "puff"
        case "ml", "milliliter", "milliliters": return "ml"
        case "mg", "milligram", "milligrams": return "mg"
        case "mcg", "microgram", "micrograms": return "mcg"
        case "g", "gram", "grams": return "g"
        case "iu": return "iu"
        case "unit", "units": return "unit"
        case "dose", "doses": return "dose"
        case "%": return "%"
        default: return unit
        }
    }

    private static func displayUnit(_ unit: String, amount: Double) -> String {
        switch unit {
        case "tablet", "capsule", "pill", "drop", "spray", "puff", "unit", "dose":
            return amount == 1 ? unit : "\(unit)s"
        case "ml": return "mL"
        case "iu": return "IU"
        default: return unit
        }
    }

    private static func formatNumber(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = amount < 1 ? 2 : 1
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    private static func normalizedHHmm(_ value: String) -> String? {
        let parts = value.split(separator: ":")
        guard parts.count >= 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else { return nil }
        return String(format: "%02d:%02d", hour, minute)
    }

    private static func normalizedHHmm(_ date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }
}
