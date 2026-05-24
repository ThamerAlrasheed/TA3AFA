// NotificationsManager.swift
import Foundation
import UserNotifications
import UIKit

// MARK: - Broadcasts to refresh UI live when background actions change completion state
extension Notification.Name {
    static let doseCompletionChanged = Notification.Name("doseCompletionChanged")
}

@MainActor
final class NotificationsManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationsManager()

    struct IDs {
        static let doseCategory = "MEDICATION_REMINDER"
        static let apptCategory = "APPT_CATEGORY"
        static let refillCategory = "REFILL_CATEGORY"
        static let takeAction = "LOG_TAKEN"
        static let skipAction = "LOG_SKIPPED"
        static let remindLaterAction = "REMIND_LATER_10"
    }

    enum MedicationReminderContextType: String {
        case selfUser = "self"
        case patient
        case caregiver
    }

    struct MedicationReminderContext {
        let type: MedicationReminderContextType
        let ownerID: String
        let contextKey: String
        let patientName: String?

        var supportsDoseActions: Bool {
            type != .caregiver
        }
    }

    private let medicationScheduleWindowDays = 7

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func configure() {
        let takeAction = UNNotificationAction(identifier: IDs.takeAction, title: "Log as Taken", options: [])
        let skipAction = UNNotificationAction(identifier: IDs.skipAction, title: "Log as Skipped", options: [])
        let remindLaterAction = UNNotificationAction(identifier: IDs.remindLaterAction, title: "Remind Me in 10 Minutes", options: [])

        let doseCategory = UNNotificationCategory(
            identifier: IDs.doseCategory,
            actions: [takeAction, skipAction, remindLaterAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )

        let apptCategory = UNNotificationCategory(
            identifier: IDs.apptCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        let refillCategory = UNNotificationCategory(
            identifier: IDs.refillCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([doseCategory, apptCategory, refillCategory])
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            if !granted {
                print("Notifications permission is denied. Medication reminders will not be delivered until enabled in Settings.")
            }
            return granted
        } catch {
            print("Notification authorization request failed:", error.localizedDescription)
            return false
        }
    }

    func schedule(
        id: String,
        title: String,
        subtitle: String = "",
        body: String,
        at date: Date,
        categoryId: String? = nil,
        threadIdentifier: String? = nil,
        timeSensitive: Bool = false,
        userInfo: [String: Any] = [:]
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        if let cat = categoryId { content.categoryIdentifier = cat }
        if let threadIdentifier { content.threadIdentifier = threadIdentifier }
        if timeSensitive { content.interruptionLevel = .timeSensitive }

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Notification scheduling failed:", error.localizedDescription)
            }
        }
    }

    func cancel(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - UserDefaults toggle helpers

    static func reminderContextKey() -> String {
        currentMedicationBaseContext().contextKey
    }

    static func reminderDefaultsKey(_ setting: String, contextKey: String? = nil) -> String {
        "notify.\(contextKey ?? reminderContextKey()).\(setting)"
    }

    static func reminderSetting(_ setting: String, contextKey: String? = nil) -> Bool {
        let defaults = UserDefaults.standard
        let scopedKey = reminderDefaultsKey(setting, contextKey: contextKey)
        if let value = defaults.object(forKey: scopedKey) as? Bool {
            return value
        }
        if let legacyValue = defaults.object(forKey: "notify.\(setting)") as? Bool {
            return legacyValue
        }
        return setting == "caregiverDoses" ? false : true
    }

    static func setReminderSetting(_ value: Bool, setting: String, contextKey: String? = nil) {
        UserDefaults.standard.set(value, forKey: reminderDefaultsKey(setting, contextKey: contextKey))
    }

    static func appLanguageCode() -> String {
        let stored = UserDefaults.standard.string(forKey: "appearance.language")
        if stored == "ar" || stored == "en" {
            return stored ?? "en"
        }
        return Locale.current.language.languageCode?.identifier == "ar" ? "ar" : "en"
    }

    static func medicationDoseKey(medID: String, scheduledAt date: Date, ownerID: String? = nil) -> String {
        let owner = ownerID ?? currentMedicationBaseContext().ownerID
        return "\(owner)_\(medID)_\(Int(date.timeIntervalSince1970))"
    }

    static func currentMedicationBaseContext() -> MedicationReminderContext {
        let supabase = SupabaseManager.shared
        let settings = AppSettings.shared

        if let activePatientID = supabase.activePatientID {
            let ownerID = activePatientID.uuidString.lowercased()
            return MedicationReminderContext(
                type: .patient,
                ownerID: ownerID,
                contextKey: "managed.\(ownerID)",
                patientName: settings.activePatientName
            )
        }

        if supabase.isPatientMode, let patientID = supabase.patientUserID {
            let ownerID = patientID.uuidString.lowercased()
            let name = [settings.firstName, settings.lastName]
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return MedicationReminderContext(
                type: .selfUser,
                ownerID: ownerID,
                contextKey: "patient.\(ownerID)",
                patientName: name.isEmpty ? nil : name
            )
        }

        if let authenticatedID = supabase.authenticatedUserID {
            let ownerID = authenticatedID.uuidString.lowercased()
            return MedicationReminderContext(
                type: .selfUser,
                ownerID: ownerID,
                contextKey: "self.\(ownerID)",
                patientName: nil
            )
        }

        return MedicationReminderContext(
            type: .selfUser,
            ownerID: "local",
            contextKey: "self.local",
            patientName: nil
        )
    }

    // MARK: - Medication Reminders

    func updateReminders(for med: LocalMed) {
        let baseContext = Self.currentMedicationBaseContext()
        cancelMedicationReminders(for: med.id, context: baseContext)
        cancelRefillReminder(for: med.id, context: baseContext)
        if baseContext.type == .patient {
            let caregiverContext = MedicationReminderContext(
                type: .caregiver,
                ownerID: baseContext.ownerID,
                contextKey: "\(baseContext.contextKey).caregiver",
                patientName: baseContext.patientName
            )
            cancelMedicationReminders(for: med.id, context: caregiverContext)
            cancelRefillReminder(for: med.id, context: caregiverContext)
        }
        cancelLegacyMedicationReminders(for: med.id)

        guard !med.isArchived else { return }
        if med.refillReminderEnabled {
            scheduleRefillReminder(for: med, context: baseContext)
        }

        guard med.remindersEnabled, !med.scheduleMode.isPRN, !med.asNeeded else { return }
        guard Self.reminderSetting("enabled", contextKey: baseContext.contextKey),
              Self.reminderSetting("doses", contextKey: baseContext.contextKey) else { return }

        scheduleMedicationReminders(for: med, context: baseContext)

        if baseContext.type == .patient,
           Self.reminderSetting("caregiverDoses", contextKey: baseContext.contextKey) {
            // TODO: True caregiver alerts across devices need backend/APNs fan-out:
            // store caregiver device tokens, create server-side due-dose jobs, and send push notifications per patient relation.
            let caregiverContext = MedicationReminderContext(
                type: .caregiver,
                ownerID: baseContext.ownerID,
                contextKey: "\(baseContext.contextKey).caregiver",
                patientName: baseContext.patientName
            )
            cancelMedicationReminders(for: med.id, context: caregiverContext)
            scheduleMedicationReminders(for: med, context: caregiverContext)
        }
    }

    func scheduleMedicationReminders(for med: LocalMed, context: MedicationReminderContext) {
        let times = med.dosageTimes.compactMap(parseDoseTime)
        guard !times.isEmpty else { return }
        guard !med.asNeeded || !med.dosageTimes.isEmpty else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        for dayOffset in 0..<medicationScheduleWindowDays {
            guard let date = cal.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            guard med.isScheduled(on: date, calendar: cal) else { continue }
            if date < cal.startOfDay(for: med.startDate) || date > cal.startOfDay(for: med.endDate) { continue }

            for (index, timeComps) in times.enumerated() {
                guard let triggerDate = cal.date(
                    bySettingHour: timeComps.hour ?? 0,
                    minute: timeComps.minute ?? 0,
                    second: 0,
                    of: date
                ) else { continue }
                if triggerDate <= Date() { continue }

                switch context.type {
                case .selfUser:
                    scheduleSelfMedicationReminder(med, context: context, at: triggerDate, doseIndex: index)
                case .patient:
                    schedulePatientMedicationReminder(med, context: context, at: triggerDate, doseIndex: index)
                case .caregiver:
                    scheduleCaregiverMedicationReminder(med, context: context, at: triggerDate, doseIndex: index)
                }
            }
        }
    }

    func scheduleSelfMedicationReminder(_ med: LocalMed, context: MedicationReminderContext, at date: Date, doseIndex: Int) {
        scheduleMedicationReminder(med, context: context, at: date, doseIndex: doseIndex)
    }

    func schedulePatientMedicationReminder(_ med: LocalMed, context: MedicationReminderContext, at date: Date, doseIndex: Int) {
        scheduleMedicationReminder(med, context: context, at: date, doseIndex: doseIndex)
    }

    func scheduleCaregiverMedicationReminder(_ med: LocalMed, context: MedicationReminderContext, at date: Date, doseIndex: Int) {
        scheduleMedicationReminder(med, context: context, at: date, doseIndex: doseIndex)
    }

    private func scheduleMedicationReminder(_ med: LocalMed, context: MedicationReminderContext, at date: Date, doseIndex: Int) {
        let copy = localizedMedicationCopy(med: med, context: context, scheduledAt: date)
        let notificationID = medicationNotificationID(medID: med.id, context: context, scheduledAt: date, doseIndex: doseIndex)
        let doseKey = Self.medicationDoseKey(medID: med.id, scheduledAt: date, ownerID: context.ownerID)
        let isoDate = ISO8601DateFormatter().string(from: date)
        let doseText = doseDetailText(for: med, isArabic: Self.appLanguageCode() == "ar")

        var userInfo: [String: Any] = [
            "medicationId": med.id,
            "medId": med.id,
            "medicationName": med.name,
            "doseId": doseKey,
            "doseKey": doseKey,
            "ownerPatientId": context.ownerID,
            "contextType": context.type.rawValue,
            "scheduledAt": isoDate,
            "notificationCategory": context.supportsDoseActions ? IDs.doseCategory : "MEDICATION_REMINDER",
            "doseText": doseText,
            "snoozeCount": 0
        ]
        if let patientName = context.patientName {
            userInfo["patientName"] = patientName
        }

        schedule(
            id: notificationID,
            title: copy.title,
            subtitle: copy.subtitle,
            body: copy.body,
            at: date,
            categoryId: context.supportsDoseActions ? IDs.doseCategory : nil,
            threadIdentifier: "medication-reminders",
            timeSensitive: true,
            userInfo: userInfo
        )
    }

    func cancelReminders(for medId: String) {
        let context = Self.currentMedicationBaseContext()
        cancelMedicationReminders(for: medId, context: context)
        cancelRefillReminder(for: medId, context: context)
        if context.type == .patient {
            let caregiverContext = MedicationReminderContext(
                type: .caregiver,
                ownerID: context.ownerID,
                contextKey: "\(context.contextKey).caregiver",
                patientName: context.patientName
            )
            cancelMedicationReminders(for: medId, context: caregiverContext)
            cancelRefillReminder(for: medId, context: caregiverContext)
        }
        cancelLegacyMedicationReminders(for: medId)
    }

    func cancelMedicationReminders() {
        cancelMedicationReminders(for: Self.currentMedicationBaseContext())
    }

    func cancelMedicationReminders(for context: MedicationReminderContext) {
        let prefix = medicationNotificationPrefix(context: context)
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier)
            if !ids.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    func cancelMedicationReminders(for medId: String, context: MedicationReminderContext) {
        let prefix = "\(medicationNotificationPrefix(context: context))\(stableIdentifierComponent(medId))."
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier)
            if !ids.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    private func scheduleRefillReminder(for med: LocalMed, context: MedicationReminderContext) {
        guard let reminderDate = med.refillReminderDate, reminderDate > Date() else { return }
        guard Self.reminderSetting("enabled", contextKey: context.contextKey) else { return }

        let isArabic = Self.appLanguageCode() == "ar"
        schedule(
            id: refillNotificationID(medID: med.id, context: context),
            title: isArabic ? "تذكير إعادة الصرف" : "Refill reminder",
            body: isArabic ? "قد تكون كمية \(med.name) أوشكت على النفاد." : "\(med.name) may be running low.",
            at: reminderDate,
            categoryId: IDs.refillCategory,
            userInfo: [
                "medicationId": med.id,
                "medId": med.id,
                "ownerPatientId": context.ownerID,
                "contextType": context.type.rawValue,
                "notificationType": "refill"
            ]
        )
        #if DEBUG
        print("Scheduled refill notification medId=\(med.id) patientId=\(context.ownerID) at=\(ISO8601DateFormatter().string(from: reminderDate))")
        #endif
    }

    private func cancelRefillReminder(for medId: String, context: MedicationReminderContext) {
        cancel(ids: [refillNotificationID(medID: medId, context: context)])
    }

    private func cancelLegacyMedicationReminders(for medId: String) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests
                .filter { $0.identifier.hasPrefix("MED_\(medId)_") }
                .map(\.identifier)
            if !ids.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
            }
        }
    }

    // MARK: - Appointment Reminders

    func updateAppointmentReminders(for appt: Appointment, settings: AppSettings) {
        cancelAppointmentReminders(for: appt.id)
        guard Self.reminderSetting("enabled"), Self.reminderSetting("appts") else { return }
        let cal = Calendar.current
        let t = appt.date

        if let bedDate = cal.date(bySettingHour: settings.bedtime.hour ?? 22,
                                  minute: settings.bedtime.minute ?? 0,
                                  second: 0,
                                  of: cal.date(byAdding: .day, value: -1, to: t) ?? t) {
            if bedDate > Date() {
                schedule(
                    id: "APPT_1D_\(appt.id)",
                    title: "Appointment tomorrow: \(appt.titleWithEmoji)",
                    body: t.formatted(date: .omitted, time: .shortened) + (appt.location?.isEmpty == false ? " • \(appt.location!)" : ""),
                    at: bedDate,
                    categoryId: IDs.apptCategory,
                    userInfo: ["appointmentId": appt.id]
                )
            }
        }

        let thirtyBefore = t.addingTimeInterval(-30 * 60)
        if thirtyBefore > Date() {
            schedule(
                id: "APPT_30_\(appt.id)",
                title: "Your “\(appt.titleWithEmoji)” appointment is in 30 mins",
                body: t.formatted(date: .omitted, time: .shortened) + (appt.location?.isEmpty == false ? " • \(appt.location!)" : ""),
                at: thirtyBefore,
                categoryId: IDs.apptCategory,
                userInfo: ["appointmentId": appt.id]
            )
        }
    }

    func cancelAppointmentReminders(for apptId: String) {
        cancel(ids: ["APPT_1D_\(apptId)", "APPT_30_\(apptId)"])
    }

    func refreshAll(meds: [LocalMed], appts: [Appointment], settings: AppSettings) {
        let context = Self.currentMedicationBaseContext()
        cancelMedicationReminders(for: context)
        if context.type == .patient {
            cancelMedicationReminders(
                for: MedicationReminderContext(
                    type: .caregiver,
                    ownerID: context.ownerID,
                    contextKey: "\(context.contextKey).caregiver",
                    patientName: context.patientName
                )
            )
        }
        for med in meds { updateReminders(for: med) }
        for appt in appts { updateAppointmentReminders(for: appt, settings: settings) }
    }

    // MARK: - DEBUG Real-device Test Helpers

    #if DEBUG
    func scheduleDebugMedicationReminder(type: MedicationReminderContextType) {
        let base = Self.currentMedicationBaseContext()
        let context: MedicationReminderContext
        switch type {
        case .selfUser:
            context = MedicationReminderContext(type: .selfUser, ownerID: base.ownerID, contextKey: base.contextKey, patientName: nil)
        case .patient:
            context = MedicationReminderContext(type: .patient, ownerID: base.ownerID, contextKey: base.contextKey, patientName: base.patientName ?? fallbackPatientName())
        case .caregiver:
            context = MedicationReminderContext(type: .caregiver, ownerID: base.ownerID, contextKey: "\(base.contextKey).caregiver", patientName: base.patientName ?? fallbackPatientName())
        }

        let date = Date().addingTimeInterval(15)
        let med = LocalMed(
            id: debugMedicationID(for: type),
            name: "Panadol",
            dosage: "500 mg",
            frequencyPerDay: 1,
            startDate: Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
            dosageTimes: [String(format: "%02d:%02d:00", Calendar.current.component(.hour, from: date), Calendar.current.component(.minute, from: date))],
            isManualSchedule: true
        )
        scheduleMedicationReminder(med, context: context, at: date, doseIndex: 0)
    }

    private func debugMedicationID(for type: MedicationReminderContextType) -> String {
        switch type {
        case .selfUser: return "00000000-0000-0000-0000-000000000101"
        case .patient: return "00000000-0000-0000-0000-000000000102"
        case .caregiver: return "00000000-0000-0000-0000-000000000103"
        }
    }
    #endif

    // MARK: - Delegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let action = response.actionIdentifier

        #if DEBUG
        print("NOTIFICATION ACTION:", action)
        print("Medication notification payload:", userInfo)
        #endif

        switch action {
        case IDs.takeAction:
            Task { @MainActor in
                self.handleDoseAction(userInfo: userInfo, status: .taken)
            }
        case IDs.skipAction:
            Task { @MainActor in
                self.handleDoseAction(userInfo: userInfo, status: .skipped)
            }
        case IDs.remindLaterAction:
            Task { @MainActor in
                self.scheduleSnoozedMedicationReminder(from: response.notification.request.content)
            }
        default:
            break
        }
        completionHandler()
    }

    // MARK: - Helpers

    @MainActor
    private func handleDoseAction(userInfo: [AnyHashable: Any], status: DoseStatus) {
        guard let key = userInfo["doseKey"] as? String,
              let medId = (userInfo["medicationId"] as? String) ?? (userInfo["medId"] as? String) else { return }

        let scheduledAt = (userInfo["scheduledAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        let ownerID = (userInfo["ownerPatientId"] as? String).flatMap(UUID.init(uuidString:))
        let source = (userInfo["contextType"] as? String) ?? "notification"

        Task { @MainActor in
            CompletionStore.markDoseDone(key)
            if status == .skipped {
                var skipped = DailyDoseStatusStore.skippedDoses()
                skipped.insert(key)
                DailyDoseStatusStore.setSkippedDoses(skipped)
            }

            try? await SupabaseManager.shared.recordDoseEvent(
                medId: medId,
                scheduledAt: scheduledAt,
                status: status,
                patientID: ownerID,
                source: source
            )
            NotificationCenter.default.post(name: .doseCompletionChanged, object: nil)
        }
    }

    @MainActor
    private func scheduleSnoozedMedicationReminder(from content: UNNotificationContent) {
        let userInfo = content.userInfo
        let snoozeCount = userInfo["snoozeCount"] as? Int ?? 0
        guard snoozeCount < 3 else { return }

        var nextUserInfo = userInfo.reduce(into: [String: Any]()) { partial, item in
            partial[String(describing: item.key)] = item.value
        }
        nextUserInfo["snoozeCount"] = snoozeCount + 1
        nextUserInfo["isSnoozeReminder"] = true

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 10 * 60, repeats: false)
        let nextContent = UNMutableNotificationContent()
        nextContent.title = content.title
        nextContent.subtitle = content.subtitle.isEmpty ? snoozeSubtitle() : content.subtitle
        nextContent.body = snoozeBody(originalBody: content.body)
        nextContent.sound = .default
        nextContent.categoryIdentifier = IDs.doseCategory
        nextContent.threadIdentifier = "medication-reminders"
        nextContent.interruptionLevel = .timeSensitive
        nextContent.userInfo = nextUserInfo

        let medId = (userInfo["medicationId"] as? String) ?? (userInfo["medId"] as? String) ?? UUID().uuidString
        let request = UNNotificationRequest(
            identifier: "SNOOZE_\(stableIdentifierComponent(medId))_\(Int(Date().timeIntervalSince1970))",
            content: nextContent,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Snooze notification scheduling failed:", error.localizedDescription)
            }
        }
    }

    private func snoozeSubtitle() -> String {
        Self.appLanguageCode() == "ar" ? "تذكير بعد 10 دقائق" : "Reminder in 10 minutes"
    }

    private func snoozeBody(originalBody: String) -> String {
        let isArabic = Self.appLanguageCode() == "ar"
        if isArabic { return "تذكير مرة أخرى: \(originalBody)" }
        return "Reminder again: \(originalBody)"
    }

    private func parseDoseTime(_ value: String) -> DateComponents? {
        let parts = value.split(separator: ":")
        guard parts.count >= 2 else { return nil }
        return DateComponents(hour: Int(parts[0]), minute: Int(parts[1]))
    }

    private func localizedMedicationCopy(med: LocalMed, context: MedicationReminderContext, scheduledAt date: Date) -> (title: String, subtitle: String, body: String) {
        let isArabic = Self.appLanguageCode() == "ar"
        let medName = DoseTextFormatter.medicationTitle(med.name)
        let doseText = doseDetailText(for: med, isArabic: isArabic)
        let foodText = MedicationFormRules.shouldShowFoodTiming(
            formID: med.medicationForm,
            foodRule: med.foodRule,
            sourceBacked: med.foodRuleSource == "source"
        ) ? med.foodRuleLabel(isArabic: isArabic) : ""
        let detail = [doseText, foodText]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: isArabic ? "، " : ". ")
        let subtitle = isArabic ? "مجدول في \(timeString(for: date))" : "Scheduled for \(timeString(for: date))"
        let patientName = context.patientName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let safePatientName = (patientName?.isEmpty == false) ? patientName! : fallbackPatientName()

        switch (context.type, isArabic) {
        case (.selfUser, false):
            let body = detail.isEmpty ? "\(medName) is due now. Tap to log it." : "\(medName) is due now. \(detail)."
            return ("Medication Reminder", subtitle, body)
        case (.selfUser, true):
            let body = detail.isEmpty ? "\(medName) مستحق الآن. اضغط لتسجيله." : "\(medName) مستحق الآن. \(detail)."
            return ("تذكير بالدواء", subtitle, body)
        case (.patient, false):
            let body = detail.isEmpty ? "\(safePatientName): \(medName) is due now." : "\(safePatientName): \(medName) is due now. \(detail)."
            return ("Medication Reminder", subtitle, body)
        case (.patient, true):
            let body = detail.isEmpty ? "\(safePatientName): \(medName) مستحق الآن." : "\(safePatientName): \(medName) مستحق الآن. \(detail)."
            return ("تذكير بالدواء", subtitle, body)
        case (.caregiver, false):
            let body = detail.isEmpty ? "\(safePatientName) has a medication due now: \(medName)." : "\(safePatientName) has \(medName) due now. \(detail)."
            return ("Caregiver Reminder", subtitle, body)
        case (.caregiver, true):
            let body = detail.isEmpty ? "لدى \(safePatientName) دواء مستحق الآن: \(medName)." : "لدى \(safePatientName) دواء مستحق الآن: \(medName). \(detail)."
            return ("تذكير لمقدم الرعاية", subtitle, body)
        }
    }

    private func doseDetailText(for med: LocalMed, isArabic: Bool) -> String {
        if let dose = DoseTextFormatter.formatDoseAmount(for: med), !dose.isEmpty {
            return dose
        }
        let trimmed = med.dosage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return isArabic ? "جرعة واحدة" : "1 dose"
    }

    private func timeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: Self.appLanguageCode() == "ar" ? "ar" : "en_US")
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func fallbackPatientName() -> String {
        Self.appLanguageCode() == "ar" ? "فرد العائلة" : "your family member"
    }

    private func medicationNotificationID(medID: String, context: MedicationReminderContext, scheduledAt date: Date, doseIndex: Int) -> String {
        let timestamp = Int(date.timeIntervalSince1970)
        return "\(medicationNotificationPrefix(context: context))\(stableIdentifierComponent(medID)).\(timestamp).\(doseIndex)"
    }

    private func refillNotificationID(medID: String, context: MedicationReminderContext) -> String {
        "\(medicationNotificationPrefix(context: context))\(stableIdentifierComponent(medID)).refill"
    }

    private func medicationNotificationPrefix(context: MedicationReminderContext) -> String {
        "MED.\(stableIdentifierComponent(context.contextKey))."
    }

    private func stableIdentifierComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.map { allowed.contains($0) ? Character($0).description : "_" }.joined()
    }
}
