import SwiftUI
import UserNotifications

// MARK: - Settings Hub

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings

    @AppStorage("profile.firstName") private var firstName: String = ""
    @AppStorage("profile.lastName")  private var lastName: String  = ""
    @AppStorage("profile.dob")       private var dobISO: String    = ""
    @AppStorage("appearance.language") private var languageCode: String =
        Locale.current.language.languageCode?.identifier ?? "en"

    private var supabase: SupabaseManager { .shared }

    private var accountUserID: UUID? {
        supabase.authenticatedUserID ?? (settings.role == .patient ? supabase.patientUserID : nil)
    }

    private var isCaregiver: Bool {
        settings.role == .caregiver
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
        let trimmed = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Your" : trimmed
    }

    private var accountOwnerName: String? {
        let trimmed = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
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
                    preferencesSection
                    if settings.role == .regular {
                        accountProfileSection
                    }
                }

                helpLegalSection
                sessionActionsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .tint(Color.istsehGreen)
            .onAppear {
                Task { await hydrateNamesFromSupabase() }
                Task { await ensureNotificationAuthIfEnabled() }
            }
            .onChange(of: firstName) { _, _ in Task { await persistNames() } }
            .onChange(of: lastName)  { _, _ in Task { await persistNames() } }
        }
        .safeAreaPadding(.bottom)
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

                Text(headerTitle)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                if let headerSubtitle {
                    Text(headerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if isCaregiver {
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
        .listRowBackground(Color(.systemGroupedBackground))
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
    }

    private var preferencesSection: some View {
        Section("App Preferences") {
            VStack(alignment: .leading, spacing: 8) {
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
                .padding(.leading, 40)
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
    }

    private var accountProfileSection: some View {
        Section("Account Profile") {
            HStack {
                Text("First name")
                Spacer()
                TextField("First", text: $firstName)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
            }
            HStack {
                Text("Last name")
                Spacer()
                TextField("Last", text: $lastName)
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
                    get: { dobFromISO(dobISO) ?? Date(timeIntervalSince1970: 0) },
                    set: { dobISO = isoString(from: $0) }
                ),
                displayedComponents: .date
            )
        }
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
    }

    // MARK: - Supabase helpers

    private func hydrateNamesFromSupabase() async {
        guard firstName.isEmpty || lastName.isEmpty,
              let uid = accountUserID else { return }
        do {
            struct Row: Decodable { let first_name: String?; let last_name: String? }
            let rows: [Row] = try await supabase.client
                .from("users")
                .select("first_name, last_name")
                .eq("id", value: uid.uuidString)
                .limit(1)
                .execute()
                .value
            if let row = rows.first {
                if firstName.isEmpty, let fn = row.first_name, !fn.isEmpty { firstName = fn }
                if lastName.isEmpty,  let ln = row.last_name,  !ln.isEmpty { lastName  = ln }
            }
        } catch { }
    }

    private func persistNames() async {
        guard settings.role == .regular,
              let uid = supabase.authenticatedUserID else { return }
        let trimmedFirst = firstName.trimmingCharacters(in: .whitespaces)
        let trimmedLast  = lastName.trimmingCharacters(in: .whitespaces)
        do {
            try await supabase.client
                .from("users")
                .update(["first_name": trimmedFirst, "last_name": trimmedLast])
                .eq("id", value: uid.uuidString)
                .execute()
        } catch { }
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
            try? await supabase.client.auth.signOut()
            await MainActor.run {
                PatientSessionStore.shared.clearAllSessionValuesBestEffort()
                settings.stopActingAsPatient()
                settings.role = .regular
                settings.didChooseEntry = false
                settings.onboardingCompleted = false
            }
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
}

// MARK: - Reminder Settings Screen

private struct ReminderSettingsView: View {
    @EnvironmentObject var settings: AppSettings

    @State private var notificationsEnabled: Bool = true
    @State private var notifyDoses: Bool = true
    @State private var notifyAppointments: Bool = true

    private var reminderContextKey: String {
        NotificationsManager.reminderContextKey()
    }

    var body: some View {
        Form {
            Section(
                footer: Text(footerText)
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
                            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
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
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.istsehGreen)
        .task(id: reminderContextKey) {
            loadReminderSettings()
        }
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
    }

    private func persistReminderSettings() {
        NotificationsManager.setReminderSetting(notificationsEnabled, setting: "enabled", contextKey: reminderContextKey)
        NotificationsManager.setReminderSetting(notifyDoses, setting: "doses", contextKey: reminderContextKey)
        NotificationsManager.setReminderSetting(notifyAppointments, setting: "appts", contextKey: reminderContextKey)
    }
}

// MARK: - FAQ Screen

private struct FAQView: View {
    var body: some View {
        List {
            Section(header: Text("General")) {
                Text("How do I add a medication?")
                Text("How do I edit or delete a medication?")
            }
            Section(header: Text("Scheduling")) {
                Text("How are dose times calculated?")
                Text("How do food rules affect my schedule?")
            }
            Section(header: Text("Notifications")) {
                Text("How can I change reminders?")
                Text("Why didn't I receive a notification?")
            }
        }
        .navigationTitle("FAQ")
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
