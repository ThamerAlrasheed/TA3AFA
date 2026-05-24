import SwiftUI
import Foundation
import UserNotifications

extension Notification.Name {
    static let medicationsDidChange = Notification.Name("medicationsDidChange")
}

// MARK: - Completion Store (Local persistence for Today's progress)

enum CompletionStore {
    private static let dosesKey = "completedDoseKeys"
    private static let apptsKey = "completedAppointments"

    static func completedDoses() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: dosesKey) ?? [])
    }

    static func setCompletedDoses(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: dosesKey)
    }

    static func markDoseDone(_ key: String) {
        var set = completedDoses()
        set.insert(key)
        setCompletedDoses(set)
    }

    static func completedAppointments() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: apptsKey) ?? [])
    }

    static func setCompletedAppointments(_ set: Set<String>) {
        UserDefaults.standard.set(Array(set), forKey: apptsKey)
    }
}

// MARK: - Small utilities

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
}

enum DosageUnit: String, CaseIterable, Identifiable {
    case mg = "mg", g = "g", mL = "mL"
    var id: String { rawValue }
    var label: String { rawValue }
}

extension NumberFormatter {
    static let dosage: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = 2
        return f
    }()
}

func parseDosageToDouble(_ s: String) -> (Double?, DosageUnit) {
    let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    let amtStr = parts.first.map(String.init) ?? ""
    let unitStr = parts.count > 1 ? String(parts[1]).lowercased() : "mg"
    let unit = DosageUnit.allCases.first { $0.rawValue.lowercased() == unitStr } ?? .mg
    let num = NumberFormatter.dosage.number(from: amtStr)?.doubleValue
    return (num, unit)
}

func formatDosage(amount: Double, unit: DosageUnit) -> String {
    let s = NumberFormatter.dosage.string(from: NSNumber(value: amount)) ?? "\(amount)"
    return "\(s) \(unit.rawValue)"
}

enum MedicationStrengthFormatter {
    static func displayableStrengths(from rawValues: [String]) -> [String] {
        var seen = Set<String>()
        var cleaned: [String] = []

        for raw in rawValues {
            for fragment in strengthFragments(from: raw) {
                guard let value = displayableStrength(from: fragment) else { continue }
                let key = value.lowercased()
                guard seen.insert(key).inserted else { continue }
                cleaned.append(value)
            }
        }

        return cleaned
    }

    static func displayableStrength(from rawValue: String) -> String? {
        var value = addLeadingZeroToDecimals(rawValue)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "µg", with: "mcg")
            .replacingOccurrences(of: "μg", with: "mcg")
            .replacingOccurrences(of: #"(?i)\[iU\]"#, with: "IU", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bmicrograms?\b"#, with: "mcg", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bmilligrams?\b"#, with: "mg", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bmilliliters?\b"#, with: "mL", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bml\b"#, with: "mL", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\biu\b"#, with: "IU", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\bper\b"#, with: "/", options: .regularExpression)

        guard !value.isEmpty else { return nil }

        let lower = value.lowercased()
        let hasTechnicalBracketUnit = value.range(of: #"\[[^\]]+\]"#, options: .regularExpression) != nil
        if hasTechnicalBracketUnit || lower.contains("hp_") || lower.contains("arb'u") {
            return nil
        }

        value = value
            .replacingOccurrences(of: #"\s*/\s*1\s*(mL)\b"#, with: "/mL", options: .regularExpression)
            .replacingOccurrences(of: #"\s*/\s*1\s*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*/\s*"#, with: "/", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=\d)(mg|mcg|g|mL|IU)\b"#, with: " $1", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if value.contains("/") {
            let parts = value.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return nil }
            let denominator = parts[1]
            let denominatorHasDisplayUnit = denominator.range(
                of: #"(?i)(mL|mg|mcg|g|IU|unit|units)\b"#,
                options: .regularExpression
            ) != nil
            guard denominatorHasDisplayUnit else { return nil }
        }

        if let normalized = normalizedDoseExpression(value) {
            return normalized
        }

        let hasDoseUnit = value.range(
            of: #"(?i)\b\d+(?:\.\d+)?\s*(mg|mcg|g|mL|IU)\b"#,
            options: .regularExpression
        ) != nil
        let hasCountUnit = value.range(
            of: #"(?i)\b(tablet|tablets|capsule|capsules|gummy|gummies|drop|drops|puff|puffs|spray|sprays)\b"#,
            options: .regularExpression
        ) != nil

        guard hasDoseUnit || hasCountUnit else { return nil }
        return value
    }

    private static func strengthFragments(from rawValue: String) -> [String] {
        let normalized = rawValue
            .replacingOccurrences(of: ";", with: ",")
            .replacingOccurrences(of: " and ", with: ", ", options: .caseInsensitive)

        let pieces = normalized
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return pieces.isEmpty ? [rawValue] : pieces
    }

    private static func addLeadingZeroToDecimals(_ raw: String) -> String {
        let pattern = #"(^|[^0-9])\.(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return raw }
        let ns = raw as NSString
        let matches = regex.matches(in: raw, range: NSRange(location: 0, length: ns.length)).reversed()
        var value = raw

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let fullRange = Range(match.range(at: 0), in: value),
                  let prefixRange = Range(match.range(at: 1), in: value),
                  let digitsRange = Range(match.range(at: 2), in: value) else { continue }

            let prefix = value[prefixRange]
            let digits = value[digitsRange]
            value.replaceSubrange(fullRange, with: "\(prefix)0.\(digits)")
        }

        return value
    }

    private static func normalizedDoseExpression(_ value: String) -> String? {
        let pattern = #"(?i)^\s*([0-9]+(?:\.[0-9]+)?)\s*(mg|mcg|g|mL|IU)\s*(?:/\s*([0-9]+(?:\.[0-9]+)?)?\s*(mg|mcg|g|mL|IU|unit|units)?)?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length)) else {
            return nil
        }

        func capture(_ index: Int) -> String? {
            guard index < match.numberOfRanges, match.range(at: index).location != NSNotFound else { return nil }
            return (value as NSString).substring(with: match.range(at: index))
        }

        guard let amount = capture(1), let unit = capture(2), let numericAmount = Double(amount) else { return nil }
        let numerator = "\(formatNumber(numericAmount)) \(displayUnit(unit))"

        guard let denominatorUnit = capture(4).map(displayUnit) else {
            return numerator
        }

        if let denominatorAmount = capture(3).flatMap(Double.init), denominatorAmount != 1 {
            return "\(numerator)/\(formatNumber(denominatorAmount)) \(denominatorUnit)"
        }

        if denominatorUnit == "unit" || denominatorUnit == "units" {
            return numerator
        }

        return "\(numerator)/\(denominatorUnit)"
    }

    private static func displayUnit(_ raw: String) -> String {
        switch raw.lowercased() {
        case "ml": return "mL"
        case "iu": return "IU"
        case "unit": return "unit"
        case "units": return "units"
        default: return raw.lowercased()
        }
    }

    private static func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 4
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Scheduler v2 (awake-window aware + meal anchoring + FDA interval)

enum Scheduler {

    // Tunables
    private static let mealOffsetMinutes: Int = 15
    private static let wakeUpBufferMinutes: Int = 15
    private static let bedtimeBufferMinutes: Int = 15
    
    private static let defaultMinGapSec: TimeInterval = 15 * 60
    private static let mergeWindowSec: TimeInterval   = 10 * 60

    static func buildAdherenceSchedule(
        meds: [Medication],
        settings: AppSettings,
        date: Date = Date()
    ) -> [(Date, Medication)] {

        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        let endOfDay   = cal.date(byAdding: .day, value: 1, to: startOfDay)!

        let active = meds.filter { $0.startDate <= endOfDay && $0.endDate >= startOfDay }
        if active.isEmpty { return [] }

        var pendingDoses: [(Date, Medication)] = []
        for m in active {
            for t in preferredTimes(for: m, on: startOfDay, settings: settings) {
                if t >= startOfDay && t < endOfDay { pendingDoses.append((t, m)) }
            }
        }

        var slots: [(time: Date, meds: [Medication])] = []
        for (t, m) in pendingDoses.sorted(by: { $0.0 < $1.0 }) {
            if let idx = bestSlotIndex(for: (t, m), in: slots) {
                slots[idx].meds.append(m)
                slots[idx].time = averageTime(slots[idx].time, t)
            } else {
                slots.append((t, [m]))
            }
        }

        slots = enforceInterSlotSeparation(slots)

        return slots
            .sorted { $0.time < $1.time }
            .flatMap { slot in slot.meds.map { (slot.time, $0) } }
    }

    // MARK: - Preferred anchors (per med)

    static func preferredTimes(for med: Medication, on startOfDay: Date, settings: AppSettings) -> [Date] {
        let cal = Calendar.current

        // 0. Use explicit dosageTimes if provided (User override)
        if let explicit = med.dosageTimes, !explicit.isEmpty {
            let dates = explicit.compactMap { t -> Date? in
                let parts = t.split(separator: ":")
                guard parts.count >= 2 else { return nil }
                let h = Int(parts[0]) ?? 0
                let m = Int(parts[1]) ?? 0
                return cal.date(bySettingHour: h, minute: m, second: 0, of: startOfDay)
            }
            return DoseTextFormatter.deduplicatedDoseDates(dates, calendar: cal)
        }

        func time(_ comps: DateComponents) -> Date {
            cal.date(bySettingHour: comps.hour ?? 9, minute: comps.minute ?? 0, second: 0, of: startOfDay)!
        }

        let breakfast = time(settings.breakfast)
        let lunch     = time(settings.lunch)
        let dinner    = time(settings.dinner)
        let wake      = time(settings.wakeup)
        var bed       = time(settings.bedtime)

        if bed <= wake {
            bed = cal.date(byAdding: .hour, value: 16, to: wake) ?? wake.addingTimeInterval(16 * 3600)
        }

        func shift(_ base: Date, minutes: Int) -> Date { base.addingTimeInterval(TimeInterval(minutes * 60)) }

        func clampInsideAwake(_ date: Date) -> Date {
            if date < wake { return wake.addingTimeInterval(5 * 60) }
            if date > bed  { return bed.addingTimeInterval(-5 * 60) }
            return date
        }

        if let interval = med.minIntervalHours, interval > 0 && med.frequencyPerDay > 1 {
            let raw = evenlySpaced(
                count: med.frequencyPerDay,
                from: wake.addingTimeInterval(TimeInterval(wakeUpBufferMinutes * 60)),
                to: bed.addingTimeInterval(TimeInterval(-bedtimeBufferMinutes * 60)),
                minSpacingHours: interval
            )
            return DoseTextFormatter.deduplicatedDoseDates(raw.map(clampInsideAwake), calendar: cal)
        }

        switch med.foodRule {
        case .afterFood:
            let anchors: [Date]
            switch med.frequencyPerDay {
            case 1:  anchors = [breakfast]
            case 2:  anchors = [breakfast, dinner]
            case 3:  anchors = [breakfast, lunch, dinner]
            default: anchors = [breakfast, lunch, dinner, bed]
            }
            return DoseTextFormatter.deduplicatedDoseDates(Array(anchors.prefix(med.frequencyPerDay))
                .map { shift($0, minutes: mealOffsetMinutes) }
                .map(clampInsideAwake), calendar: cal)

        case .beforeFood:
            let anchors: [Date]
            switch med.frequencyPerDay {
            case 1:  anchors = [breakfast]
            case 2:  anchors = [breakfast, dinner]
            case 3:  anchors = [breakfast, lunch, dinner]
            default: anchors = [breakfast, lunch, dinner, bed]
            }
            return DoseTextFormatter.deduplicatedDoseDates(Array(anchors.prefix(med.frequencyPerDay))
                .map { shift($0, minutes: -mealOffsetMinutes) }
                .map(clampInsideAwake), calendar: cal)

        case .withFood:
            let anchors: [Date]
            switch med.frequencyPerDay {
            case 1:  anchors = [breakfast]
            case 2:  anchors = [breakfast, dinner]
            case 3:  anchors = [breakfast, lunch, dinner]
            default: anchors = [breakfast, lunch, dinner, bed]
            }
            return DoseTextFormatter.deduplicatedDoseDates(
                Array(anchors.prefix(med.frequencyPerDay)).map(clampInsideAwake),
                calendar: cal
            )

        case .avoidWithFood, .notSure, .none:
            var anchors: [Date]
            switch med.frequencyPerDay {
            case 1: anchors = [shift(wake, minutes: wakeUpBufferMinutes)]
            case 2: anchors = [shift(wake, minutes: wakeUpBufferMinutes), shift(bed, minutes: -bedtimeBufferMinutes)]
            case 3: anchors = [breakfast, lunch, dinner]
            default:
                anchors = evenlySpaced(
                    count: med.frequencyPerDay,
                    from: wake.addingTimeInterval(TimeInterval(wakeUpBufferMinutes * 60)),
                    to: bed.addingTimeInterval(TimeInterval(-bedtimeBufferMinutes * 60)),
                    minSpacingHours: nil
                )
            }
            return DoseTextFormatter.deduplicatedDoseDates(anchors.map(clampInsideAwake), calendar: cal)
        }
    }

    private static func evenlySpaced(count: Int, from start: Date, to end: Date, minSpacingHours: Int?) -> [Date] {
        guard count > 0 else { return [] }
        if count == 1 { return [start] }
        let totalWindow = end.timeIntervalSince(start)
        let step = totalWindow / Double(count - 1)
        var out: [Date] = []
        var cursor = start
        out.append(cursor)
        for _ in 1..<count {
            cursor = cursor.addingTimeInterval(step)
            if let last = out.last, let minH = minSpacingHours {
                let needed = last.addingTimeInterval(Double(minH) * 3600)
                if cursor < needed { cursor = needed }
            }
            if cursor > end { cursor = end }
            out.append(cursor)
        }
        return out
    }

    private static func bestSlotIndex(for dose: (Date, Medication),
                                      in slots: [(time: Date, meds: [Medication])]) -> Int? {
        for i in slots.indices {
            let slot = slots[i]
            if abs(slot.time.timeIntervalSince(dose.0)) <= mergeWindowSec {
                if slot.meds.allSatisfy({ canCoSchedule($0, dose.1) }) {
                    return i
                }
            }
        }
        return nil
    }

    private static func canCoSchedule(_ a: Medication, _ b: Medication) -> Bool {
        let conflicts = InteractionEngine.checkConflictsLegacy(
            meds: [(a.name, a.ingredients ?? []), (b.name, b.ingredients ?? [])]
        )
        let hasAvoid   = conflicts.contains { if case .avoid = $0.kind { return true } else { return false } }
        let needsHours = conflicts.contains { if case .separate = $0.kind { return true } else { return false } }
        return !(hasAvoid || needsHours)
    }

    private static func enforceInterSlotSeparation(
        _ slots: [(time: Date, meds: [Medication])]
    ) -> [(time: Date, meds: [Medication])] {

        var out = slots.sorted { $0.time < $1.time }
        guard out.count > 1 else { return out }

        for i in 0..<out.count {
            for j in (i+1)..<out.count {
                let a = out[i], b = out[j]

                var maxHours: Double = 0
                var hasAvoid = false
                for ma in a.meds {
                    for mb in b.meds {
                        let conflicts = InteractionEngine.checkConflictsLegacy(
                            meds: [(ma.name, ma.ingredients ?? []), (mb.name, mb.ingredients ?? [])]
                        )
                        if conflicts.contains(where: { if case .avoid = $0.kind { return true } else { return false } }) {
                            hasAvoid = true
                        }
                        if let h = conflicts.compactMap({ c -> Double? in
                            if case .separate(let x) = c.kind { return x } else { return nil }
                        }).max() {
                            maxHours = max(maxHours, h)
                        }
                    }
                }

                let required = max(maxHours * 3600, hasAvoid ? defaultMinGapSec : defaultMinGapSec)

                if abs(a.time.timeIntervalSince(b.time)) < required {
                    if a.time <= b.time {
                        out[j].time = a.time.addingTimeInterval(required)
                    } else {
                        out[i].time = b.time.addingTimeInterval(required)
                    }
                }
            }
        }
        return out.sorted { $0.time < $1.time }
    }

    private static func averageTime(_ a: Date, _ b: Date) -> Date {
        let mid = (a.timeIntervalSinceReferenceDate + b.timeIntervalSinceReferenceDate) / 2
        return Date(timeIntervalSinceReferenceDate: mid)
    }
}

// MARK: - Shared medication dose builder

struct MedicationDoseBuilder {
    static func dosePairs(
        for meds: [LocalMed],
        on date: Date,
        settings: AppSettings,
        calendar: Calendar = .current
    ) -> [(Date, LocalMed)] {
        let dayStart = calendar.startOfDay(for: date)

        let active = meds.filter { med in
            guard !med.isArchived else { return false }
            return med.isScheduled(on: dayStart, calendar: calendar)
        }

        return DoseTextFormatter.deduplicatedDosePairs(active.flatMap { med in
            doseDates(for: med, on: dayStart, settings: settings, calendar: calendar).map { ($0, med) }
        })
    }

    static func doseDates(
        for med: LocalMed,
        on date: Date,
        settings: AppSettings,
        calendar: Calendar = .current
    ) -> [Date] {
        let dayStart = calendar.startOfDay(for: date)
        let explicitTimes = med.dosageTimes.compactMap { timeString -> Date? in
            let parts = timeString.split(separator: ":")
            guard parts.count >= 2,
                  let hour = Int(parts[0]),
                  let minute = Int(parts[1]) else { return nil }
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart)
        }

        if !explicitTimes.isEmpty {
            return DoseTextFormatter.deduplicatedDoseDates(explicitTimes, calendar: calendar)
        }

        let adapted = Medication(
            id: med.id,
            name: med.name,
            dosage: med.dosage,
            frequencyPerDay: max(med.timesPerDay ?? med.frequencyPerDay, 1),
            startDate: med.startDate,
            endDate: med.endDate,
            foodRule: med.foodRule,
            notes: med.notes,
            ingredients: med.ingredients,
            minIntervalHours: med.minIntervalHours,
            rxcui: med.rxcui,
            dosageTimes: nil,
            asNeeded: med.asNeeded,
            isManualSchedule: med.isManualSchedule
        )

        return DoseTextFormatter.deduplicatedDoseDates(
            Scheduler.preferredTimes(for: adapted, on: dayStart, settings: settings),
            calendar: calendar
        )
    }
}

// MARK: - Local notifications

enum Notifier {
    static func requestAuth() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func schedule(local id: String, title: String, body: String, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    static func cancel(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }
}

// MARK: - Summarization & bullet extraction

struct MedEssentials {
    let title: String
    let quickTips: [String]
    let whatFor: [String]
    let howToTake: [String]
    let commonSideEffects: [String]
    let importantWarnings: [String]
    let interactionsToAvoid: [String]
    let ingredients: [String]
}

enum MedSummarizer {

    static func bullets(from raw: String, max: Int = 4) -> [String] {
        var text = raw
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "•", with: "\n• ")
            .replacingOccurrences(of: "·", with: "\n• ")
            .replacingOccurrences(of: "‣", with: "\n• ")
            .replacingOccurrences(of: "—", with: " – ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        text = text.replacingOccurrences(
            of: #"(^|\n)\s*\d+\s+[A-Z][A-Z\s/,-]{3,}(?=\n|$)"#,
            with: "",
            options: [.regularExpression]
        )

        let candidates: [String] = text
            .replacingOccurrences(of: ".", with: ".\n")
            .replacingOccurrences(of: ";", with: ";\n")
            .components(separatedBy: CharacterSet.newlines)
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var lines: [String] = []
        for var s in candidates {
            if s.hasPrefix("•") { s = s.dropFirst().trimmingCharacters(in: .whitespaces) }

            // Skip short or numerical-only lines
            if s.range(of: #"^\(?\d+(?:\s*,\s*\d+)*\)?$"#, options: .regularExpression) != nil { continue }
            if s.range(of: #"^\d+\s*[–-]\s*\d+$"#, options: .regularExpression) != nil { continue }
            if s.count < 10 { continue }

            // Aggressive truncation for conciseness
            if s.count > 110 {
                let cut = s.index(s.startIndex, offsetBy: 100)
                if let space = s[cut...].firstIndex(of: " ") {
                    s = String(s[..<space]) + "..."
                } else {
                    s = String(s.prefix(105)) + "..."
                }
            }
            lines.append(s)
        }

        var out: [String] = []
        func similar(_ a: String, _ b: String) -> Bool {
            let ax = a.lowercased(), bx = b.lowercased()
            return ax == bx || ax.contains(bx) || bx.contains(ax)
        }
        for s in lines {
            if out.contains(where: { similar($0, s) }) { continue }
            out.append(s)
            if out.count >= max { break }
        }
        return out
    }

    static func essentials(from details: MedDetails) -> MedEssentials {
        let parsed = DrugTextParser.parse(details.combinedText)

        var tips: [String] = []
        if let fr = parsed.foodRule {
            tips.append(fr == .afterFood ? "Take after food" : "Take before food")
        }
        if let ih = parsed.minIntervalHours { tips.append("About every \(ih)h") }
        if !parsed.mustAvoid.isEmpty { tips.append("Avoid: " + parsed.mustAvoid.joined(separator: ", ")) }

        return MedEssentials(
            title: details.title,
            quickTips: tips,
            whatFor: bullets(from: details.uses, max: 4),
            howToTake: bullets(from: details.dosage, max: 5),
            commonSideEffects: bullets(from: details.sideEffects, max: 5),
            importantWarnings: bullets(from: details.warnings, max: 5),
            interactionsToAvoid: bullets(from: details.interactions, max: 4),
            ingredients: details.ingredients
        )
    }
}

// MARK: - App Layout Metrics

enum AppLayoutMetrics {
    static let tabBarHeight: CGFloat = 86
    static let tabBarBottomPadding: CGFloat = 8
    static let tabBarContentClearance: CGFloat = 118
}

// MARK: - Keep scrolling content above the tab bar

private struct TabBarAvoider: ViewModifier {
    private let pad: CGFloat = AppLayoutMetrics.tabBarContentClearance

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: pad)
            }
    }
}

extension View {
    func avoidsTabBar() -> some View { modifier(TabBarAvoider()) }
}

// MARK: - Global helper for "active medication" logic used by Meds page

/// Returns true when today's date is within the medication's start & end dates (inclusive).
@inline(__always)
func isMedicationActive(_ med: Medication, on date: Date = Date()) -> Bool {
    let cal = Calendar.current
    let today = cal.startOfDay(for: date)
    let start = cal.startOfDay(for: med.startDate)
    let end   = cal.startOfDay(for: med.endDate)
    return (today >= start) && (today <= end)
}
