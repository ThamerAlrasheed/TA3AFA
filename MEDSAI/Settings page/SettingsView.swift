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

    private var medicalProfilePatientId: String? {
        if settings.role == .caregiver, let pid = settings.activePatientID {
            return pid
        }
        return supabase.currentUserID?.uuidString.lowercased()
    }

    var body: some View {
        NavigationStack {
            List {
                profileHeaderSection

                Section("Care") {
                    SettingsNavRow(
                        icon: "person.2.fill", iconColor: .green,
                        title: "Family Members",
                        subtitle: "Manage patients and care access"
                    ) {
                        FamilySettingsView().environmentObject(settings)
                    }

                    SettingsNavRow(
                        icon: "cross.case.fill", iconColor: .red,
                        title: "Medical Profile",
                        subtitle: settings.activePatientName.map { "Managing \($0)'s profile" }
                            ?? "Allergies and chronic conditions"
                    ) {
                        MedicalProfileView(
                            patientId: medicalProfilePatientId,
                            patientName: settings.activePatientName
                                ?? (firstName.isEmpty ? "My" : firstName)
                        )
                    }

                    SettingsNavRow(
                        icon: "clock.fill", iconColor: .orange,
                        title: "Daily Routine",
                        subtitle: settings.activePatientName.map { "Managing \($0)'s routine" }
                            ?? "Wake time, meals, and bedtime"
                    ) {
                        RoutineSettingsView().environmentObject(settings)
                    }

                    SettingsNavRow(
                        icon: "bell.badge.fill", iconColor: .purple,
                        title: "Reminders",
                        subtitle: "Medication and appointment alerts"
                    ) {
                        ReminderSettingsView()
                    }
                }

                Section("Preferences") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            SettingsIconBadge(systemName: "paintbrush.fill", color: .indigo)
                            Text("Appearance").font(.body)
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
                        SettingsIconBadge(systemName: "globe", color: .blue)
                        Picker("Language", selection: $languageCode) {
                            Text("English").tag("en")
                            Text("العربية").tag("ar")
                        }
                    }
                }

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

                Section("Help & Legal") {
                    Button {
                        settings.onboardingCompleted = false
                    } label: {
                        HStack(spacing: 10) {
                            SettingsIconBadge(systemName: "sparkles", color: .yellow)
                            Text("Show tutorial again").foregroundStyle(.primary)
                        }
                    }

                    NavigationLink {
                        FAQView().tint(.green)
                    } label: {
                        HStack(spacing: 10) {
                            SettingsIconBadge(systemName: "questionmark.circle.fill", color: .blue)
                            Text("FAQ")
                        }
                    }

                    Link(destination: URL(string: "https://example.com/privacy")!) {
                        HStack(spacing: 10) {
                            SettingsIconBadge(systemName: "hand.raised.fill", color: Color(.systemGray))
                            Text("Privacy Policy").foregroundStyle(.primary)
                        }
                    }

                    Link(destination: URL(string: "https://example.com/terms")!) {
                        HStack(spacing: 10) {
                            SettingsIconBadge(systemName: "doc.text.fill", color: Color(.systemGray))
                            Text("Terms of Service").foregroundStyle(.primary)
                        }
                    }

                    Button {
                        openMail(
                            to: "support@yourapp.example",
                            subject: "ISTSEH Support",
                            body: defaultSupportBody()
                        )
                    } label: {
                        HStack(spacing: 10) {
                            SettingsIconBadge(systemName: "envelope.fill", color: .green)
                            Text("Contact Support").foregroundStyle(.primary)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) { signOut() } label: {
                        HStack {
                            Spacer()
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            Spacer()
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .tint(.green)
            .toolbar {
                if settings.role == .caregiver {
                    ToolbarItem(placement: .topBarLeading) {
                        CareProfileMenu {
                            Task { await settings.loadRoutineFromSupabase() }
                        }
                        .environmentObject(settings)
                    }
                }
            }
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
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(settings.role == .caregiver
                              ? Color.green.opacity(0.12)
                              : Color.blue.opacity(0.10))
                        .frame(width: 64, height: 64)
                    Image(systemName: settings.role == .caregiver
                          ? "person.2.fill"
                          : "person.crop.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(settings.role == .caregiver ? .green : .blue)
                }
                .padding(.top, 16)

                if !firstName.isEmpty || !lastName.isEmpty {
                    Text("\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces))
                        .font(.title3.weight(.semibold))
                }

                Group {
                    if settings.role == .caregiver {
                        if let name = settings.activePatientName {
                            Label("Managing \(name)", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("No patient selected", systemImage: "person.crop.circle.badge.questionmark")
                                .foregroundStyle(.secondary)
                        }
                    } else if settings.role == .patient {
                        Label("Patient profile", systemImage: "staroflife.fill")
                            .foregroundStyle(.blue)
                    } else {
                        Label("Personal care", systemImage: "heart.fill")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Capsule())
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color(.systemGroupedBackground))
    }

    // MARK: - Supabase helpers

    private func hydrateNamesFromSupabase() async {
        guard firstName.isEmpty || lastName.isEmpty,
              let uid = supabase.currentUserID else { return }
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
        guard let uid = supabase.currentUserID else { return }
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
        guard UserDefaults.standard.bool(forKey: "notify.enabled") else { return }
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
    @AppStorage("notify.enabled") private var notificationsEnabled: Bool = true
    @AppStorage("notify.doses")   private var notifyDoses: Bool = true
    @AppStorage("notify.appts")   private var notifyAppointments: Bool = true

    var body: some View {
        Form {
            Section(
                footer: Text("Reminders are scheduled using this patient's medication plan and daily routine.")
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
                    }
                }

                Toggle("Medication reminders", isOn: $notifyDoses)
                    .disabled(!notificationsEnabled)

                Toggle("Appointment reminders", isOn: $notifyAppointments)
                    .disabled(!notificationsEnabled)
            }
        }
        .navigationTitle("Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .tint(.green)
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
        .tint(.green)
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
                    Text(title).font(.body)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
        }
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
