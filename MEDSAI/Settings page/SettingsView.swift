import SwiftUI
import UserNotifications

// MARK: - Settings Hub

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var medsRepo: UserMedsRepo

    @AppStorage("appearance.language") private var languageCode: String =
        Locale.current.language.languageCode?.identifier ?? "en"

    #if DEBUG
    @State private var debugSnapshot: DebugContextSnapshot?
    @AppStorage("debug.showContextPanel") private var showDebugContextPanel = false
    #endif

    private var supabase: SupabaseManager { .shared }

    private var accountUserID: UUID? {
        supabase.authenticatedUserID ?? (settings.role == .patient ? supabase.patientUserID : nil)
    }

    private var isCaregiver: Bool {
        settings.role == .caregiver || settings.activePatientID != nil
    }

    private var hasSelectedPatient: Bool {
        isCaregiver && settings.activePatientID != nil
    }

    private var medicalProfilePatientId: String? {
        if isCaregiver {
            return settings.activePatientID
        }
        if settings.role == .patient {
            return nil
        }
        return supabase.authenticatedUserID?.uuidString.lowercased()
    }

    private var medicalProfileDisplayName: String {
        if isCaregiver, let name = settings.activePatientName {
            return name
        }
        if settings.role == .patient {
            return "Your"
        }
        let trimmed = "\(settings.firstName) \(settings.lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Your" : trimmed
    }

    private var accountOwnerName: String? {
        let trimmed = "\(settings.firstName) \(settings.lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var headerTitle: String {
        if isCaregiver {
            if let name = settings.activePatientName {
                return "Managing \(name)"
            }
            return "My Profile"
        }
        return "My Profile"
    }

    private var headerSubtitle: String? {
        if isCaregiver {
            let owner = accountOwnerName ?? currentEmailIfAvailable()
            if hasSelectedPatient, let owner {
                return "Caregiver account: \(owner)"
            }
            return owner
        }
        return accountOwnerName ?? currentEmailIfAvailable()
    }

    private var selectedPatientId: String? {
        if isCaregiver, let pid = settings.activePatientID {
            return pid
        }
        return nil
    }

    var body: some View {
        NavigationStack {
            List {
                profileHeaderSection

                if isCaregiver {
                    if hasSelectedPatient {
                        selectedPatientCareSections
                    } else {
                        ownPatientCareSections
                        familySection(title: "Family Members", subtitle: "Manage family and care access")
                        preferencesSection
                    }
                } else {
                    ownPatientCareSections
                    if settings.role == .regular {
                        familySection(title: "Family Members", subtitle: "Manage family and care access")
                    }
                    preferencesSection
                    if settings.role == .regular {
                        accountProfileSection
                    }
                }

                helpLegalSection
                #if DEBUG
                if showDebugContextPanel {
                    debugContextSection
                }
                #endif
                sessionActionsSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.istsehPageBackground.ignoresSafeArea())
            .avoidsTabBar()
            .navigationTitle("Settings")
            .tint(Color.istsehGreen)
            .onAppear {
                Task {
                    await settings.loadCurrentUserProfile()
                    #if DEBUG
                    await refreshDebugSnapshot()
                    #endif
                }
                Task { await ensureNotificationAuthIfEnabled() }
            }
            .onChange(of: settings.firstName) { _, _ in Task { await persistNames() } }
            .onChange(of: settings.lastName)  { _, _ in Task { await persistNames() } }
            .onChange(of: settings.dateOfBirth) { _, _ in Task { await persistProfileDate() } }
            .onChange(of: settings.activePatientID) { _, _ in
                #if DEBUG
                Task { await refreshDebugSnapshot() }
                #endif
            }
            .onChange(of: languageCode) { _, _ in
                NotificationCenter.default.post(name: NSNotification.Name("UserRoutineChanged"), object: nil)
            }
        }
        .environment(\.layoutDirection, languageCode == "ar" ? .rightToLeft : .leftToRight)
    }

    // MARK: - Profile Header Card

    private var profileHeaderSection: some View {
        Section {
            VStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(Color.istsehGreenSoft)
                        .frame(width: 64, height: 64)
                    Image(systemName: headerIconName)
                        .font(.system(size: 28))
                        .foregroundStyle(Color.istsehGreen)
                }
                .padding(.top, 16)

                if settings.isProfileLoading && !hasSelectedPatient {
                    BrandedLoadingView(message: LoadingMessage.profile.text, style: .inline)
                } else {
                    Text(headerTitle)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)

                    if let headerSubtitle {
                        Text(headerSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    #if DEBUG
                    if let error = settings.profileLoadError {
                        Text("DEBUG profile load failed: \(error)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    #endif
                }

                if settings.role != .patient {
                    CareProfileMenu(presentation: .pill) {
                        Task { await settings.loadRoutineFromSupabase() }
                    }
                    .environmentObject(settings)
                } else {
                    Label(settings.role == .patient ? "Patient profile" : "Personal care", systemImage: "staroflife.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.istsehGreen)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.istsehGreenSoft, in: Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var headerIconName: String {
        if isCaregiver {
            return hasSelectedPatient ? "person.crop.circle.badge.checkmark" : "person.circle.fill"
        }
        return "person.crop.circle.fill"
    }

    // MARK: - Contextual Sections

    @ViewBuilder
    private var ownPatientCareSections: some View {
        Section("Care") {
            SettingsNavRow(
                icon: "cross.case.fill", iconColor: Color.istsehGreen,
                title: "Medical Profile",
                subtitle: "Allergies and chronic conditions"
            ) {
                MedicalProfileView(
                    patientId: medicalProfilePatientId,
                    patientName: medicalProfileDisplayName
                )
                .environmentObject(settings)
            }

            SettingsNavRow(
                icon: "clock.fill", iconColor: Color.istsehGreen,
                title: "Daily Routine",
                subtitle: "Wake time, meals, and bedtime"
            ) {
                RoutineSettingsView().environmentObject(settings)
            }

            SettingsNavRow(
                icon: "bell.badge.fill", iconColor: Color.istsehGreen,
                title: "Reminders",
                subtitle: "Medication and appointment alerts"
            ) {
                ReminderSettingsView()
            }
        }
        .listRowBackground(Color.istsehCard)
    }

    @ViewBuilder
    private var selectedPatientCareSections: some View {
        Section(settings.activePatientName.map { "Managing \($0)" } ?? "Patient Care") {
            SettingsNavRow(
                icon: "cross.case.fill", iconColor: Color.istsehGreen,
                title: "Medical Profile",
                subtitle: settings.activePatientName.map { "\($0)'s allergies and conditions" }
                    ?? "Allergies and chronic conditions"
            ) {
                MedicalProfileView(
                    patientId: selectedPatientId,
                    patientName: settings.activePatientName ?? "Patient"
                )
                .environmentObject(settings)
            }

            SettingsNavRow(
                icon: "clock.fill", iconColor: Color.istsehGreen,
                title: "Daily Routine",
                subtitle: settings.activePatientName.map { "\($0)'s wake time, meals, and bedtime" }
                    ?? "Wake time, meals, and bedtime"
            ) {
                RoutineSettingsView().environmentObject(settings)
            }

            SettingsNavRow(
                icon: "bell.badge.fill", iconColor: Color.istsehGreen,
                title: "Reminders",
                subtitle: "Medication and appointment alerts for this patient"
            ) {
                ReminderSettingsView()
            }
        }
        .listRowBackground(Color.istsehCard)

        familySection(title: "Change Patient", subtitle: "Switch or manage family members")
    }

    private func familySection(title: String, subtitle: String) -> some View {
        Section("Family") {
            SettingsNavRow(
                icon: "person.2.fill", iconColor: Color.istsehGreen,
                title: title,
                subtitle: subtitle
            ) {
                FamilySettingsView().environmentObject(settings)
            }
        }
        .listRowBackground(Color.istsehCard)
    }

    private var preferencesSection: some View {
        Section("App Preferences") {
            VStack(alignment: languageCode == "ar" ? .trailing : .leading, spacing: 8) {
                HStack(spacing: 10) {
                    SettingsIconBadge(systemName: "paintbrush.fill", color: Color.istsehGreen)
                    Text("Appearance")
                        .font(.body)
                        .foregroundStyle(.primary)
                }
                Picker("Appearance", selection: $settings.appearanceMode) {
                    ForEach(AppSettings.AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(languageCode == "ar" ? .trailing : .leading, 40)
            }
            .padding(.vertical, 4)

            HStack(spacing: 10) {
                SettingsIconBadge(systemName: "globe", color: Color.istsehGreen)
                Text("Language")
                    .foregroundStyle(.primary)
                Spacer()
                Menu {
                    Button("English") { languageCode = "en" }
                    Button("العربية") { languageCode = "ar" }
                } label: {
                    HStack(spacing: 4) {
                        Text(languageDisplayName)
                            .foregroundStyle(Color.istsehGreen)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.istsehGreen)
                    }
                }
            }
        }
        .listRowBackground(Color.istsehCard)
    }

    private var accountProfileSection: some View {
        Section("Account Profile") {
            HStack {
                Text("First name")
                Spacer()
                TextField("First", text: $settings.firstName)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
            }
            HStack {
                Text("Last name")
                Spacer()
                TextField("Last", text: $settings.lastName)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
            }
            HStack {
                Text("Email")
                Spacer()
                Text(currentEmail()).foregroundStyle(.secondary)
            }
            DatePicker(
                "Date of birth",
                selection: Binding(
                    get: { settings.dateOfBirth ?? Date(timeIntervalSince1970: 0) },
                    set: { settings.dateOfBirth = $0 }
                ),
                displayedComponents: .date
            )
        }
        .listRowBackground(Color.istsehCard)
    }

    private var helpLegalSection: some View {
        Section("Help & Legal") {
            Button {
                settings.onboardingCompleted = false
            } label: {
                HStack(spacing: 10) {
                    SettingsIconBadge(systemName: "sparkles", color: Color.istsehGreen)
                    Text("Show tutorial again").foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)

            NavigationLink {
                FAQView()
            } label: {
                HStack(spacing: 10) {
                    SettingsIconBadge(systemName: "questionmark.circle.fill", color: Color.istsehGreen)
                    Text("FAQ").foregroundStyle(.primary)
                }
            }

            Button {
                openURLString("https://example.com/privacy")
            } label: {
                HStack(spacing: 10) {
                    SettingsIconBadge(systemName: "hand.raised.fill", color: Color.istsehGreen)
                    Text("Privacy Policy").foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)

            Button {
                openURLString("https://example.com/terms")
            } label: {
                HStack(spacing: 10) {
                    SettingsIconBadge(systemName: "doc.text.fill", color: Color.istsehGreen)
                    Text("Terms of Service").foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)

            Button {
                openMail(
                    to: "support@yourapp.example",
                    subject: "ISTSEH Support",
                    body: defaultSupportBody()
                )
            } label: {
                HStack(spacing: 10) {
                    SettingsIconBadge(systemName: "envelope.fill", color: Color.istsehGreen)
                    Text("Contact Support").foregroundStyle(.primary)
                }
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(Color.istsehCard)
    }

    private var sessionActionsSection: some View {
        Section {
            Button(role: .destructive) { signOut() } label: {
                HStack {
                    Spacer()
                    Label(settings.role == .patient ? "Disconnect from Caregiver" : "Sign out",
                          systemImage: "rectangle.portrait.and.arrow.right")
                    Spacer()
                }
            }
        }
        .listRowBackground(Color.istsehCard)
    }

    // MARK: - Supabase helpers

    private func persistNames() async {
        guard settings.role == .regular,
              let uid = supabase.authenticatedUserID,
              settings.loadedProfileUserID == uid else { return }
        let trimmedFirst = settings.firstName.trimmingCharacters(in: .whitespaces)
        let trimmedLast  = settings.lastName.trimmingCharacters(in: .whitespaces)
        do {
            try await supabase.client
                .from("users")
                .update(["first_name": trimmedFirst, "last_name": trimmedLast])
                .eq("id", value: uid.uuidString.lowercased())
                .execute()
        } catch {
            #if DEBUG
            print("DEBUG_SESSION persistNames failed for \(uid.uuidString.lowercased()): \(error.localizedDescription)")
            #endif
        }
    }

    private func persistProfileDate() async {
        guard settings.role == .regular,
              let uid = supabase.authenticatedUserID,
              settings.loadedProfileUserID == uid,
              let date = settings.dateOfBirth else { return }
        do {
            try await supabase.client
                .from("users")
                .update(["date_of_birth": isoString(from: date)])
                .eq("id", value: uid.uuidString.lowercased())
                .execute()
        } catch {
            #if DEBUG
            print("DEBUG_SESSION persistProfileDate failed for \(uid.uuidString.lowercased()): \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Helpers

    private func currentEmail() -> String {
        supabase.client.auth.currentSession?.user.email ?? "Not available"
    }

    private func currentEmailIfAvailable() -> String? {
        supabase.client.auth.currentSession?.user.email
    }

    private var languageDisplayName: String {
        languageCode == "ar" ? "Arabic" : "English"
    }

    private func signOut() {
        Task {
            await settings.signOutCompletely()
            #if DEBUG
            await MainActor.run { debugSnapshot = nil }
            #endif
        }
    }

    private func ensureNotificationAuthIfEnabled() async {
        guard NotificationsManager.reminderSetting("enabled") else { return }
        _ = await NotificationsManager.shared.requestAuthorization()
    }

    private func isoString(from date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.string(from: date)
    }

    private func dobFromISO(_ iso: String) -> Date? {
        guard !iso.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.date(from: iso)
    }

    private func openMail(to: String, subject: String, body: String) {
        let subjectEncoded = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let bodyEncoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:\(to)?subject=\(subjectEncoded)&body=\(bodyEncoded)") {
            UIApplication.shared.open(url)
        }
    }

    private func openURLString(_ value: String) {
        if let url = URL(string: value) {
            UIApplication.shared.open(url)
        }
    }

    private func defaultSupportBody() -> String {
        let email = currentEmail()
        return """
        Hello Support,

        I need help with the ISTSEH app.

        Email: \(email)
        App Version: 1.0
        iOS: \(UIDevice.current.systemVersion)
        Device: \(UIDevice.current.model)

        Describe your issue here:
        """
    }

    #if DEBUG
    private var debugContextSection: some View {
        Section("DEBUG Context") {
            Button("Refresh Context Snapshot") {
                Task { await refreshDebugSnapshot() }
            }

            if let snapshot = debugSnapshot {
                DebugRow(label: "auth.uid", value: snapshot.authID)
                DebugRow(label: "auth.email", value: snapshot.email)
                DebugRow(label: "display profile id", value: snapshot.profileID)
                DebugRow(label: "display name", value: snapshot.displayName)
                DebugRow(label: "activePatientID", value: snapshot.activePatientID)
                DebugRow(label: "activePatientName", value: snapshot.activePatientName)
                DebugRow(label: "care-code active", value: snapshot.careCodeActive)
                DebugRow(label: "allergies", value: "\(snapshot.allergyCount)")
                DebugRow(label: "conditions", value: "\(snapshot.conditionCount)")
                DebugRow(label: "medications", value: "\(snapshot.medCount)")
                DebugRow(label: "pending med notifications", value: "\(snapshot.pendingMedicationNotifications)")
            } else {
                Text("No snapshot loaded")
                    .foregroundStyle(.secondary)
            }
        }
        .listRowBackground(Color.istsehCard)
    }

    private func refreshDebugSnapshot() async {
        let authID = supabase.authenticatedUserID?.uuidString.lowercased() ?? "nil"
        let email = supabase.client.auth.currentSession?.user.email ?? "nil"
        let profileID = settings.loadedProfileUserID?.uuidString.lowercased() ?? "nil"
        let displayName = accountOwnerName ?? "nil"
        let activePatientID = settings.activePatientID ?? "nil"
        let activePatientName = settings.activePatientName ?? "nil"
        let careCodeActive = "\(supabase.isPatientMode)"
        let patientID = medicalProfilePatientId

        async let allergies = (try? DrugInfo.listAllergies(patientId: patientID)) ?? []
        async let conditions = (try? DrugInfo.listConditions(patientId: patientID)) ?? []
        let pendingMedicationCount = await pendingMedicationNotificationCount()
        let loadedAllergies = await allergies
        let loadedConditions = await conditions

        await MainActor.run {
            debugSnapshot = DebugContextSnapshot(
                authID: authID,
                email: email,
                profileID: profileID,
                displayName: displayName,
                activePatientID: activePatientID,
                activePatientName: activePatientName,
                careCodeActive: careCodeActive,
                allergyCount: loadedAllergies.count,
                conditionCount: loadedConditions.count,
                medCount: medsRepo.meds.count,
                pendingMedicationNotifications: pendingMedicationCount
            )
        }
    }

    private func pendingMedicationNotificationCount() async -> Int {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.filter { $0.identifier.hasPrefix("MED.") || $0.identifier.hasPrefix("MED_") }.count)
            }
        }
    }
    #endif
}

#if DEBUG
private struct DebugContextSnapshot {
    let authID: String
    let email: String
    let profileID: String
    let displayName: String
    let activePatientID: String
    let activePatientName: String
    let careCodeActive: String
    let allergyCount: Int
    let conditionCount: Int
    let medCount: Int
    let pendingMedicationNotifications: Int
}

private struct DebugRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .multilineTextAlignment(.trailing)
        }
    }
}
#endif

// MARK: - Reminder Settings Screen

private struct ReminderSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    @State private var notificationsEnabled: Bool = true
    @State private var notifyDoses: Bool = true
    @State private var notifyAppointments: Bool = true
    @State private var notifyCaregiverDoses: Bool = false
    @AppStorage("appearance.language") private var languageCode: String =
        Locale.current.language.languageCode?.identifier ?? "en"
    #if DEBUG
    @AppStorage("debug.showContextPanel") private var showDebugContextPanel = false
    #endif

    private var isArabic: Bool { languageCode == "ar" }

    private var reminderContextKey: String {
        NotificationsManager.reminderContextKey()
    }

    var body: some View {
        Form {
            Section(
                footer: Text(footerText)
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
            ) {
                Toggle(isOn: $notificationsEnabled) {
                    Label("Enable reminders", systemImage: "bell.fill")
                }
                .onChange(of: notificationsEnabled) { _, newVal in
                    Task {
                        if newVal {
                            _ = await NotificationsManager.shared.requestAuthorization()
                        } else {
                            notifyDoses = false
                            notifyAppointments = false
                            notifyCaregiverDoses = false
                            NotificationsManager.shared.cancelMedicationReminders()
                        }
                        persistReminderSettings()
                        NotificationCenter.default.post(name: NSNotification.Name("UserRoutineChanged"), object: nil)
                    }
                }

                Toggle("Medication reminders", isOn: $notifyDoses)
                    .disabled(!notificationsEnabled)
                    .onChange(of: notifyDoses) { _, _ in
                        persistReminderSettings()
                        NotificationCenter.default.post(name: NSNotification.Name("UserRoutineChanged"), object: nil)
                    }

                Toggle("Appointment reminders", isOn: $notifyAppointments)
                    .disabled(!notificationsEnabled)
                    .onChange(of: notifyAppointments) { _, _ in
                        persistReminderSettings()
                    }

                if settings.activePatientID != nil {
                    Toggle("Caregiver medication reminders", isOn: $notifyCaregiverDoses)
                        .disabled(!notificationsEnabled || !notifyDoses)
                        .onChange(of: notifyCaregiverDoses) { _, _ in
                            persistReminderSettings()
                            NotificationCenter.default.post(name: NSNotification.Name("UserRoutineChanged"), object: nil)
                        }
                }
            }
            .listRowBackground(Color.istsehCard)

            #if DEBUG
            if showDebugContextPanel {
                Section {
                    Button("Test self reminder in 15 seconds") {
                        NotificationsManager.shared.scheduleDebugMedicationReminder(type: .selfUser)
                    }

                    Button("Test family member reminder in 15 seconds") {
                        NotificationsManager.shared.scheduleDebugMedicationReminder(type: .patient)
                    }

                    Button("Test caregiver reminder in 15 seconds") {
                        NotificationsManager.shared.scheduleDebugMedicationReminder(type: .caregiver)
                    }
                } header: {
                    Text("Developer Tests")
                } footer: {
                    Text("DEBUG only. These buttons are not compiled into production builds.")
                        .multilineTextAlignment(isArabic ? .trailing : .leading)
                }
                .listRowBackground(Color.istsehCard)
            }
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(Color.istsehPageBackground.ignoresSafeArea())
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.istsehGreen)
        .task(id: reminderContextKey) {
            loadReminderSettings()
        }
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
    }

    private var footerText: String {
        if let name = settings.activePatientName {
            return "Reminders are scheduled using \(name)'s medication plan and daily routine."
        }
        return "Reminders are scheduled using your medication plan and daily routine."
    }

    private func loadReminderSettings() {
        notificationsEnabled = NotificationsManager.reminderSetting("enabled", contextKey: reminderContextKey)
        notifyDoses = NotificationsManager.reminderSetting("doses", contextKey: reminderContextKey)
        notifyAppointments = NotificationsManager.reminderSetting("appts", contextKey: reminderContextKey)
        notifyCaregiverDoses = NotificationsManager.reminderSetting("caregiverDoses", contextKey: reminderContextKey)
    }

    private func persistReminderSettings() {
        NotificationsManager.setReminderSetting(notificationsEnabled, setting: "enabled", contextKey: reminderContextKey)
        NotificationsManager.setReminderSetting(notifyDoses, setting: "doses", contextKey: reminderContextKey)
        NotificationsManager.setReminderSetting(notifyAppointments, setting: "appts", contextKey: reminderContextKey)
        NotificationsManager.setReminderSetting(notifyCaregiverDoses, setting: "caregiverDoses", contextKey: reminderContextKey)
    }
}

// MARK: - FAQ Screen

private struct FAQView: View {
    @AppStorage("appearance.language") private var languageCode: String =
        Locale.current.language.languageCode?.identifier ?? "en"

    private var isArabic: Bool { languageCode == "ar" }

    var body: some View {
        List {
            Section(header: Text("General")) {
                Text("How do I add a medication?")
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
                Text("How do I edit or delete a medication?")
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
            }
            Section(header: Text("Scheduling")) {
                Text("How are dose times calculated?")
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
                Text("How do food rules affect my schedule?")
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
            }
            Section(header: Text("Notifications")) {
                Text("How can I change reminders?")
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
                Text("Why didn't I receive a notification?")
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
            }
        }
        .navigationTitle("FAQ")
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
    }
}

// MARK: - Shared Settings Components

struct SettingsNavRow<D: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @ViewBuilder var destination: () -> D

    var body: some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 14) {
                SettingsIconBadge(systemName: icon, color: iconColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
        }
    }
}

struct SettingsEmptyStateRow: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.istsehGreen)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }
}

struct SettingsIconBadge: View {
    let systemName: String
    let color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color.gradient)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
