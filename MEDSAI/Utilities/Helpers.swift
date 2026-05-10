import SwiftUI
import Foundation
import UserNotifications

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
            return explicit.compactMap { t -> Date? in
                let parts = t.split(separator: ":")
                guard parts.count >= 2 else { return nil }
                let h = Int(parts[0]) ?? 0
                let m = Int(parts[1]) ?? 0
                return cal.date(bySettingHour: h, minute: m, second: 0, of: startOfDay)
            }
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
            return raw.map(clampInsideAwake)
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
            return Array(anchors.prefix(med.frequencyPerDay))
                .map { shift($0, minutes: mealOffsetMinutes) }
                .map(clampInsideAwake)

        case .beforeFood:
            let anchors: [Date]
            switch med.frequencyPerDay {
            case 1:  anchors = [breakfast]
            case 2:  anchors = [breakfast, dinner]
            case 3:  anchors = [breakfast, lunch, dinner]
            default: anchors = [breakfast, lunch, dinner, bed]
            }
            return Array(anchors.prefix(med.frequencyPerDay))
                .map { shift($0, minutes: -mealOffsetMinutes) }
                .map(clampInsideAwake)

        case .withFood:
            let anchors: [Date]
            switch med.frequencyPerDay {
            case 1:  anchors = [breakfast]
            case 2:  anchors = [breakfast, dinner]
            case 3:  anchors = [breakfast, lunch, dinner]
            default: anchors = [breakfast, lunch, dinner, bed]
            }
            return Array(anchors.prefix(med.frequencyPerDay))
                .map(clampInsideAwake)

        case .none:
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
            return anchors.map(clampInsideAwake)
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

// MARK: - Keep scrolling content above the tab bar

private struct TabBarAvoider: ViewModifier {
    private let pad: CGFloat = 64

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
