import Foundation
import SwiftUI
import Combine

enum UserRole: String, Codable {
    case regular, caregiver, patient
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // User profile (expand as needed)
    @Published var firstName: String
    @Published var lastName: String
    @Published var dateOfBirth: Date?
    
    // Caregiver role and patient session context are persisted in Keychain.
    @Published var role: UserRole {
        didSet {
            do {
                try PatientSessionStore.shared.setUserRole(role.rawValue)
            } catch {
                print("Patient session storage failed while saving role: \(error.localizedDescription)")
            }
        }
    }
    @Published var activePatientID: String? {
        didSet {
            let patientID = activePatientID.flatMap { UUID(uuidString: $0) }
            if SupabaseManager.shared.activePatientID != patientID {
                SupabaseManager.shared.activePatientID = patientID
            }
            if activePatientID == nil {
                activePatientName = nil
            }
        }
    } // If caregiver, who are we viewing?
    @Published var activePatientName: String? {
        didSet {
            do {
                try PatientSessionStore.shared.setActivePatientName(activePatientName)
            } catch {
                print("Patient session storage failed while saving active patient name: \(error.localizedDescription)")
            }
        }
    }
    @Published var familyMembers: [String] = []  // Names/IDs of linked patients

    // Routine (meals & sleep) – single source of truth for scheduling
    @Published var breakfast: DateComponents
    @Published var lunch: DateComponents
    @Published var dinner: DateComponents
    @Published var bedtime: DateComponents
    @Published var wakeup: DateComponents

    // App flow flags
    @Published var onboardingCompleted: Bool
    @Published var didChooseEntry: Bool

    // Appearance
    enum AppearanceMode: String, CaseIterable, Identifiable {
        case light, dark, system
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }
    @Published var appearanceMode: AppearanceMode
    @Published var sessionRevokedMessage: String? = nil

    /// Returns the ColorScheme to pass to `.preferredColorScheme()`.
    /// `nil` means follow the system setting.
    var colorScheme: ColorScheme? {
        switch appearanceMode {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return nil
        }
    }

    // Internal
    private var cancellables = Set<AnyCancellable>()
    private var isApplyingRemote = false
    private let saveDebounce = PassthroughSubject<Void, Never>()

    private var supabase: SupabaseManager { .shared }

    private init() {
        do {
            try PatientSessionStore.shared.migrateLegacyUserDefaultsIfNeeded()
        } catch {
            print("Patient session migration failed: \(error.localizedDescription)")
        }

        // Profile defaults
        firstName = ""
        lastName  = ""
        dateOfBirth = nil

        // Restore persisted role
        let savedRole = PatientSessionStore.shared.userRoleRawValue ?? UserRole.regular.rawValue
        role = UserRole(rawValue: savedRole) ?? .regular
        activePatientID = SupabaseManager.shared.activePatientID?.uuidString.lowercased()
        activePatientName = PatientSessionStore.shared.activePatientName

        // Routine defaults (these are used until we load from Supabase)
        breakfast = DateComponents(hour: 8,  minute: 0)
        lunch     = DateComponents(hour: 13, minute: 0)
        dinner    = DateComponents(hour: 19, minute: 0)
        bedtime   = DateComponents(hour: 23, minute: 0)
        wakeup    = DateComponents(hour: 7,  minute: 0)

        // Flow defaults
        onboardingCompleted = false
        didChooseEntry = false

        // Appearance default (light)
        let savedMode = UserDefaults.standard.string(forKey: "appearanceMode") ?? AppearanceMode.light.rawValue
        appearanceMode = AppearanceMode(rawValue: savedMode) ?? .light

        // Handle session expiration (revocation)
        SupabaseManager.shared.onSessionExpired = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.sessionRevokedMessage = "Your access to this patient profile has been revoked by the caregiver."
                self.forceDisconnectPatient()
            }
        }

        // Debounced auto-save when routine changes locally
        saveDebounce
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] in
                Task { [weak self] in await self?.saveRoutineToSupabase() }
            }
            .store(in: &cancellables)

        // Watch routine fields
        Publishers.MergeMany(
            $breakfast.map { _ in () },
            $lunch.map { _ in () },
            $dinner.map { _ in () },
            $bedtime.map { _ in () },
            $wakeup.map { _ in () }
        )
        .sink { [weak self] in
            guard let self, !self.isApplyingRemote else { return }
            self.saveDebounce.send(())
            // Notify repo to refresh all reminders
            NotificationCenter.default.post(name: NSNotification.Name("UserRoutineChanged"), object: nil)
        }
        .store(in: &cancellables)

        // Persist appearance mode
        $appearanceMode
            .dropFirst() // skip initial value
            .sink { UserDefaults.standard.set($0.rawValue, forKey: "appearanceMode") }
            .store(in: &cancellables)
    }

    func resetAppFlow() {
        didChooseEntry = false
        onboardingCompleted = false
    }

    @MainActor
    func forceDisconnectPatient() {
        // Clear session
        PatientSessionStore.shared.clearAllSessionValuesBestEffort()
        
        // Reset local state to landing
        role = .regular
        didChooseEntry = false
        // activePatientID and activePatientName are updated via didSet on role or manually
        activePatientID = nil
        activePatientName = nil
    }

    @MainActor
    func actAsPatient(id: UUID, displayName: String) {
        activePatientName = displayName
        activePatientID = id.uuidString.lowercased()
    }

    @MainActor
    func stopActingAsPatient() {
        activePatientID = nil
        activePatientName = nil
    }

    var activeCareDisplayName: String {
        if let activePatientName, !activePatientName.isEmpty {
            return activePatientName
        }
        if !firstName.isEmpty {
            return firstName
        }
        return "Family member"
    }

    // MARK: - Supabase sync

    /// Call after sign-in (or app start if already signed in) to pull routine from Postgres.
    @MainActor
    func loadRoutineFromSupabase() async {
        guard let uid = supabase.currentUserID else { return }
        let requestedUserID = uid
        let wasActingAtRequestStart = supabase.activePatientID != nil

        do {
            // When a caregiver has an active patient, use the Edge Function so RLS doesn't block
            if let activePatientID = supabase.activePatientID {
                let patientIdStr = activePatientID.uuidString.lowercased()
                let routine = try await DrugInfo.getPatientRoutine(patientId: patientIdStr)
                guard supabase.currentUserID == requestedUserID else { return }
                isApplyingRemote = true
                breakfast = parseTime(routine.breakfast_time, defaultHour: 8)
                lunch     = parseTime(routine.lunch_time,     defaultHour: 13)
                dinner    = parseTime(routine.dinner_time,    defaultHour: 19)
                bedtime   = parseTime(routine.bedtime,        defaultHour: 23)
                wakeup    = parseTime(routine.wakeup_time,    defaultHour: 7)
                isApplyingRemote = false
                return
            }

            // Own routine: direct DB query (auth.uid() matches own row)
            struct UserRow: Decodable {
                let breakfast_time: String?
                let lunch_time: String?
                let dinner_time: String?
                let bedtime: String?
                let wakeup_time: String?
                let first_name: String?
                let last_name: String?
                let role: String?
            }

            let rows: [UserRow] = try await self.supabase.retry {
                try await self.supabase.client
                    .from("users")
                    .select("breakfast_time, lunch_time, dinner_time, bedtime, wakeup_time, first_name, last_name, role")
                    .eq("id", value: uid.uuidString)
                    .limit(1)
                    .execute()
                    .value
            }

            guard supabase.currentUserID == requestedUserID else { return }
            guard let row = rows.first else { return }

            isApplyingRemote = true
            breakfast = parseTime(row.breakfast_time, defaultHour: 8)
            lunch     = parseTime(row.lunch_time,     defaultHour: 13)
            dinner    = parseTime(row.dinner_time,    defaultHour: 19)
            bedtime   = parseTime(row.bedtime,        defaultHour: 23)
            wakeup    = parseTime(row.wakeup_time,    defaultHour: 7)

            if let fn = row.first_name { firstName = fn }
            if let ln = row.last_name  { lastName = ln }

            // Only update role if we are NOT currently acting as a patient
            if let r = row.role, !wasActingAtRequestStart, supabase.activePatientID == nil {
                role = UserRole(rawValue: r) ?? .regular
            }

            isApplyingRemote = false
        } catch {
            print("⚠️ loadRoutineFromSupabase failed:", error.localizedDescription)
            isApplyingRemote = false
        }
    }

    /// Debounced writer used whenever the user edits routine fields locally.
    func saveRoutineToSupabase() async {
        guard let uid = supabase.currentUserID else { return }

        // When a caregiver has an active patient, save via Edge Function (bypasses RLS)
        if let activePatientID = supabase.activePatientID {
            let patientIdStr = activePatientID.uuidString.lowercased()
            let routine = DrugInfo.PatientRoutine(
                breakfast_time: formatTime(breakfast, defaultHour: 8),
                lunch_time: formatTime(lunch, defaultHour: 13),
                dinner_time: formatTime(dinner, defaultHour: 19),
                bedtime: formatTime(bedtime, defaultHour: 23),
                wakeup_time: formatTime(wakeup, defaultHour: 7)
            )
            do {
                try await DrugInfo.savePatientRoutine(patientId: patientIdStr, routine: routine)
            } catch {
                print("⚠️ saveRoutineToSupabase (patient) failed:", error.localizedDescription)
            }
            return
        }

        // Own routine: direct DB update
        let data: [String: String] = [
            "breakfast_time": formatTime(breakfast, defaultHour: 8),
            "lunch_time":     formatTime(lunch,     defaultHour: 13),
            "dinner_time":    formatTime(dinner,    defaultHour: 19),
            "bedtime":        formatTime(bedtime,   defaultHour: 23),
            "wakeup_time":    formatTime(wakeup,    defaultHour: 7)
        ]

        do {
            _ = try await self.supabase.retry {
                try await self.supabase.client
                    .from("users")
                    .update(data)
                    .eq("id", value: uid.uuidString)
                    .execute()
            }
        } catch {
            print("⚠️ saveRoutineToSupabase failed:", error.localizedDescription)
        }
    }

    // MARK: - Time helpers

    /// Converts a Postgres TIME string like "08:00:00" into DateComponents.
    private func parseTime(_ timeString: String?, defaultHour: Int) -> DateComponents {
        guard let ts = timeString, ts.count >= 5 else {
            return DateComponents(hour: defaultHour, minute: 0)
        }
        let parts = ts.prefix(5).split(separator: ":")
        let hour = Int(parts.first ?? "") ?? defaultHour
        let minute = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        return DateComponents(hour: hour, minute: minute)
    }

    /// Converts DateComponents back to a Postgres TIME string like "08:00:00".
    private func formatTime(_ comps: DateComponents, defaultHour: Int) -> String {
        let h = comps.hour ?? defaultHour
        let m = comps.minute ?? 0
        return String(format: "%02d:%02d:00", h, m)
    }
}
