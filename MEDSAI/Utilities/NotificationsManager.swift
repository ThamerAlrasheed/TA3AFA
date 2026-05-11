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
        static let doseCategory = "DOSE_CATEGORY"
        static let apptCategory = "APPT_CATEGORY"
        static let takeAction   = "TAKE_ACTION"
        static let skipAction   = "SKIP_ACTION"
    }

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func configure() {
        let takeAction = UNNotificationAction(identifier: IDs.takeAction, title: "Mark as Taken", options: [.foreground])
        let skipAction = UNNotificationAction(identifier: IDs.skipAction, title: "Skip", options: [.destructive])
        
        let doseCategory = UNNotificationCategory(
            identifier: IDs.doseCategory,
            actions: [takeAction, skipAction],
            intentIdentifiers: [],
            options: .customDismissAction
        )
        
        let apptCategory = UNNotificationCategory(
            identifier: IDs.apptCategory,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([doseCategory, apptCategory])
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            print("⚠️ Auth request failed:", error)
            return false
        }
    }

    func schedule(id: String, title: String, body: String, at date: Date, categoryId: String? = nil, userInfo: [String: Any] = [:]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        if let cat = categoryId { content.categoryIdentifier = cat }

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error { print("❌ Notification failed:", error) }
        }
    }

    func cancel(ids: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Reminders Lifecycle

    // MARK: - UserDefaults toggle helpers (default true if key never set)
    static func reminderContextKey() -> String {
        let supabase = SupabaseManager.shared
        if let activePatientID = supabase.activePatientID {
            return "managed.\(activePatientID.uuidString.lowercased())"
        }
        if supabase.isPatientMode, let patientID = supabase.patientUserID {
            return "patient.\(patientID.uuidString.lowercased())"
        }
        if let authenticatedID = supabase.authenticatedUserID {
            return "self.\(authenticatedID.uuidString.lowercased())"
        }
        return "self.local"
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
        return true
    }

    static func setReminderSetting(_ value: Bool, setting: String, contextKey: String? = nil) {
        UserDefaults.standard.set(value, forKey: reminderDefaultsKey(setting, contextKey: contextKey))
    }

    private func boolSetting(_ key: String) -> Bool {
        let setting = key.replacingOccurrences(of: "notify.", with: "")
        return Self.reminderSetting(setting)
    }

    func updateReminders(for med: LocalMed) {
        cancelReminders(for: med.id)
        guard !med.isArchived else { return }
        guard boolSetting("notify.enabled"), boolSetting("notify.doses") else { return }

        let times = med.dosageTimes.compactMap { t -> DateComponents? in
            let parts = t.split(separator: ":")
            guard parts.count >= 2 else { return nil }
            return DateComponents(hour: Int(parts[0]), minute: Int(parts[1]))
        }
        
        guard !times.isEmpty else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        
        for dayOffset in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            if date < cal.startOfDay(for: med.startDate) || date > cal.startOfDay(for: med.endDate) { continue }

            for (index, timeComps) in times.enumerated() {
                guard let triggerDate = cal.date(bySettingHour: timeComps.hour ?? 0, 
                                               minute: timeComps.minute ?? 0, 
                                               second: 0, of: date) else { continue }
                if triggerDate <= Date() { continue }

                let notifyId = "MED_\(med.id)_\(dayOffset)_\(index)"
                let doseKey = "\(med.id)_\(cal.startOfDay(for: triggerDate).timeIntervalSince1970)_\(index)"

                schedule(
                    id: notifyId,
                    title: "Medication Reminder",
                    body: "It's time to take \(med.name) (\(med.dosage))",
                    at: triggerDate,
                    categoryId: IDs.doseCategory,
                    userInfo: ["medId": med.id, "doseKey": doseKey]
                )
            }
        }
    }

    func updateAppointmentReminders(for appt: Appointment, settings: AppSettings) {
        cancelAppointmentReminders(for: appt.id)
        guard boolSetting("notify.enabled"), boolSetting("notify.appts") else { return }
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

    func cancelReminders(for medId: String) {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let ids = requests.filter { $0.identifier.hasPrefix("MED_\(medId)_") }.map { $0.identifier }
            if !ids.isEmpty {
                Task { @MainActor in
                    self.cancel(ids: ids)
                }
            }
        }
    }

    func cancelAppointmentReminders(for apptId: String) {
        cancel(ids: ["APPT_1D_\(apptId)", "APPT_30_\(apptId)"])
    }

    func refreshAll(meds: [LocalMed], appts: [Appointment], settings: AppSettings) {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        for med in meds { updateReminders(for: med) }
        for appt in appts { updateAppointmentReminders(for: appt, settings: settings) }
    }

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

        if action == IDs.takeAction, let key = userInfo["doseKey"] as? String, let medId = userInfo["medId"] as? String {
            Task { @MainActor in
                CompletionStore.markDoseDone(key)
                try? await SupabaseManager.shared.recordDoseEvent(medId: medId, scheduledAt: Date(), status: .taken)
                NotificationCenter.default.post(name: .doseCompletionChanged, object: nil)
            }
        }
        completionHandler()
    }
}
