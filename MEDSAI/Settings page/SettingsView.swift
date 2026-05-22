import SwiftUI
import UserNotifications

enum SettingsL10n {
    static var isArabic: Bool {
        UserDefaults.standard.string(forKey: "appearance.language") == "ar"
    }

    static var layoutDirection: LayoutDirection { isArabic ? .rightToLeft : .leftToRight }
    static var textAlignment: TextAlignment { isArabic ? .trailing : .leading }
    static var horizontalAlignment: HorizontalAlignment { isArabic ? .trailing : .leading }
    static var frameAlignment: Alignment { isArabic ? .trailing : .leading }

    static func text(_ english: String, _ arabic: String) -> String {
        isArabic ? arabic : english
    }

    static func managing(_ name: String) -> String {
        isArabic ? "إدارة ملف \(name)" : "Managing \(name)"
    }

    static func patientPossessive(_ name: String, _ englishSuffix: String, _ arabicPrefix: String) -> String {
        isArabic ? "\(arabicPrefix) \(name)" : "\(name)'s \(englishSuffix)"
    }
}

// MARK: - Settings Hub

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var medsRepo: UserMedsRepo

    @AppStorage("appearance.language") private var languageCode: String =
        Locale.current.language.languageCode?.identifier ?? "en"
    @State private var showingFAQ = false

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
            return SettingsL10n.text("Your", "ملفك")
        }
        let trimmed = "\(settings.firstName) \(settings.lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? SettingsL10n.text("Your", "ملفك") : trimmed
    }

    private var accountOwnerName: String? {
        let trimmed = "\(settings.firstName) \(settings.lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var headerTitle: String {
        if isCaregiver {
            if let name = settings.activePatientName {
                return SettingsL10n.managing(name)
            }
            return SettingsL10n.text("My Profile", "ملفي الشخصي")
        }
        return SettingsL10n.text("My Profile", "ملفي الشخصي")
    }

    private var headerSubtitle: String? {
        if isCaregiver {
            let owner = accountOwnerName ?? currentEmailIfAvailable()
            if hasSelectedPatient, let owner {
                return SettingsL10n.text("Caregiver account: \(owner)", "حساب مقدم الرعاية: \(owner)")
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
                        familySection(
                            title: SettingsL10n.text("Family Members", "أفراد العائلة"),
                            subtitle: SettingsL10n.text("Manage family and care access", "إدارة أفراد العائلة وصلاحيات الرعاية")
                        )
                        preferencesSection
                    }
                } else {
                    ownPatientCareSections
                    if settings.role == .regular {
                        familySection(
                            title: SettingsL10n.text("Family Members", "أفراد العائلة"),
                            subtitle: SettingsL10n.text("Manage family and care access", "إدارة أفراد العائلة وصلاحيات الرعاية")
                        )
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
            .navigationTitle(SettingsL10n.text("Settings", "الإعدادات"))
            .navigationBarTitleDisplayMode(.inline)
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
            .id(languageCode)
            .navigationDestination(isPresented: $showingFAQ) {
                FAQView()
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
                        Text(SettingsL10n.text("DEBUG profile load failed: \(error)", "فشل تحميل الملف في وضع التطوير: \(error)"))
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
                    Label(
                        settings.role == .patient
                            ? SettingsL10n.text("Patient profile", "ملف المريض")
                            : SettingsL10n.text("Personal care", "الرعاية الشخصية"),
                        systemImage: "staroflife.fill"
                    )
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
        Section(SettingsL10n.text("Care", "الرعاية")) {
            SettingsNavRow(
                icon: "cross.case.fill", iconColor: Color.istsehGreen,
                title: SettingsL10n.text("Medical Profile", "الملف الطبي"),
                subtitle: SettingsL10n.text("Allergies and chronic conditions", "الحساسية والحالات المزمنة"),
                showsDivider: true
            ) {
                MedicalProfileView(
                    patientId: medicalProfilePatientId,
                    patientName: medicalProfileDisplayName
                )
                .environmentObject(settings)
            }

            SettingsNavRow(
                icon: "clock.fill", iconColor: Color.istsehGreen,
                title: SettingsL10n.text("Daily Routine", "الروتين اليومي"),
                subtitle: SettingsL10n.text("Wake time, meals, and bedtime", "وقت الاستيقاظ والوجبات والنوم"),
                showsDivider: true
            ) {
                RoutineSettingsView().environmentObject(settings)
            }

            SettingsNavRow(
                icon: "bell.badge.fill", iconColor: Color.istsehGreen,
                title: SettingsL10n.text("Reminders", "التذكيرات"),
                subtitle: SettingsL10n.text("Medication and appointment alerts", "تنبيهات الأدوية والمواعيد")
            ) {
                ReminderSettingsView()
            }
        }
        .listRowBackground(Color.istsehCard)
    }

    @ViewBuilder
    private var selectedPatientCareSections: some View {
        Section(settings.activePatientName.map { SettingsL10n.managing($0) } ?? SettingsL10n.text("Patient Care", "رعاية المريض")) {
            SettingsNavRow(
                icon: "cross.case.fill", iconColor: Color.istsehGreen,
                title: SettingsL10n.text("Medical Profile", "الملف الطبي"),
                subtitle: settings.activePatientName.map {
                    SettingsL10n.patientPossessive($0, "allergies and conditions", "الحساسية والحالات الخاصة بـ")
                } ?? SettingsL10n.text("Allergies and chronic conditions", "الحساسية والحالات المزمنة"),
                showsDivider: true
            ) {
                MedicalProfileView(
                    patientId: selectedPatientId,
                    patientName: settings.activePatientName ?? "Patient"
                )
                .environmentObject(settings)
            }

            SettingsNavRow(
                icon: "clock.fill", iconColor: Color.istsehGreen,
                title: SettingsL10n.text("Daily Routine", "الروتين اليومي"),
                subtitle: settings.activePatientName.map {
                    SettingsL10n.patientPossessive($0, "wake time, meals, and bedtime", "روتين الاستيقاظ والوجبات والنوم الخاص بـ")
                } ?? SettingsL10n.text("Wake time, meals, and bedtime", "وقت الاستيقاظ والوجبات والنوم"),
                showsDivider: true
            ) {
                RoutineSettingsView().environmentObject(settings)
            }

            SettingsNavRow(
                icon: "bell.badge.fill", iconColor: Color.istsehGreen,
                title: SettingsL10n.text("Reminders", "التذكيرات"),
                subtitle: SettingsL10n.text("Medication and appointment alerts for this patient", "تنبيهات الأدوية والمواعيد لهذا المريض")
            ) {
                ReminderSettingsView()
            }
        }
        .listRowBackground(Color.istsehCard)

        familySection(
            title: SettingsL10n.text("Change Patient", "تغيير المريض"),
            subtitle: SettingsL10n.text("Switch or manage family members", "التبديل أو إدارة أفراد العائلة")
        )
    }

    private func familySection(title: String, subtitle: String) -> some View {
        Section(SettingsL10n.text("Family", "العائلة")) {
            SettingsNavRow(
                icon: "person.2.fill", iconColor: Color.istsehGreen,
                title: title,
                subtitle: subtitle
            ) {
                FamilySettingsView().environmentObject(settings)
            }
        }
        .listRowBackground(Color.istsehCard)
        .listRowSeparator(.hidden)
    }

    private var preferencesSection: some View {
        Section(SettingsL10n.text("App Preferences", "تفضيلات التطبيق")) {
            VStack(alignment: SettingsL10n.horizontalAlignment, spacing: 8) {
                SettingsPlainRow(icon: "paintbrush.fill", text: SettingsL10n.text("Appearance", "المظهر"))
                Picker(SettingsL10n.text("Appearance", "المظهر"), selection: $settings.appearanceMode) {
                    ForEach(AppSettings.AppearanceMode.allCases) { mode in
                        Text(mode.localizedLabel).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(languageCode == "ar" ? .trailing : .leading, 40)
            }
            .padding(.vertical, 4)
            .listRowSeparator(.hidden)

            SettingsMenuRow(
                icon: "globe",
                title: SettingsL10n.text("Language", "اللغة"),
                value: languageDisplayName
            ) {
                languageMenu
            }
            .listRowSeparator(.hidden)
        }
        .listRowBackground(Color.istsehCard)
        .listRowSeparator(.hidden)
    }

    private var languageMenu: some View {
        Menu {
            Button(SettingsL10n.text("English", "الإنجليزية")) { languageCode = "en" }
            Button(SettingsL10n.text("Arabic", "العربية")) { languageCode = "ar" }
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

    private var accountProfileSection: some View {
        Section(SettingsL10n.text("Account Profile", "ملف الحساب")) {
            SettingsEditableTextRow(
                title: SettingsL10n.text("First name", "الاسم الأول"),
                placeholder: SettingsL10n.text("First", "الاسم الأول"),
                text: $settings.firstName
            )
            SettingsEditableTextRow(
                title: SettingsL10n.text("Last name", "اسم العائلة"),
                placeholder: SettingsL10n.text("Last", "اسم العائلة"),
                text: $settings.lastName
            )
            SettingsValueRow(title: SettingsL10n.text("Email", "البريد الإلكتروني"), value: currentEmail())
            SettingsDateRow(
                title: SettingsL10n.text("Date of birth", "تاريخ الميلاد"),
                selection: Binding(
                    get: { settings.dateOfBirth ?? Date(timeIntervalSince1970: 0) },
                    set: { settings.dateOfBirth = $0 }
                ),
            )
        }
        .listRowBackground(Color.istsehCard)
        .listRowSeparator(.hidden)
    }

    private var helpLegalSection: some View {
        Section(SettingsL10n.text("Help & Legal", "المساعدة والخصوصية")) {
            SettingsActionRow(
                icon: "sparkles",
                text: SettingsL10n.text("Show tutorial again", "عرض الشرح مرة أخرى"),
                showsDivider: true
            ) {
                settings.onboardingCompleted = false
            }

            SettingsActionRow(
                icon: "questionmark.circle.fill",
                text: SettingsL10n.text("FAQ", "الأسئلة الشائعة"),
                showsChevron: true,
                showsDivider: true
            ) {
                showingFAQ = true
            }

            SettingsActionRow(
                icon: "hand.raised.fill",
                text: SettingsL10n.text("Privacy Policy", "سياسة الخصوصية"),
                showsDivider: true
            ) {
                openURLString("https://example.com/privacy")
            }

            SettingsActionRow(
                icon: "doc.text.fill",
                text: SettingsL10n.text("Terms of Service", "شروط الاستخدام"),
                showsDivider: true
            ) {
                openURLString("https://example.com/terms")
            }

            SettingsActionRow(
                icon: "envelope.fill",
                text: SettingsL10n.text("Contact Support", "التواصل مع الدعم")
            ) {
                openMail(
                    to: "support@yourapp.example",
                    subject: "ISTSEH Support",
                    body: defaultSupportBody()
                )
            }
        }
        .listRowBackground(Color.istsehCard)
        .listRowSeparator(.hidden)
    }

    private var sessionActionsSection: some View {
        Section {
            Button(role: .destructive) { signOut() } label: {
                HStack {
                    Spacer()
                    Label(settings.role == .patient
                          ? SettingsL10n.text("Disconnect from Caregiver", "قطع الاتصال بمقدم الرعاية")
                          : SettingsL10n.text("Sign out", "تسجيل الخروج"),
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
        supabase.client.auth.currentSession?.user.email ?? SettingsL10n.text("Not available", "غير متوفر")
    }

    private func currentEmailIfAvailable() -> String? {
        supabase.client.auth.currentSession?.user.email
    }

    private var languageDisplayName: String {
        languageCode == "ar" ? SettingsL10n.text("Arabic", "العربية") : SettingsL10n.text("English", "الإنجليزية")
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
        if SettingsL10n.isArabic {
            return """
            مرحبًا فريق الدعم،

            أحتاج مساعدة في تطبيق استصح.

            البريد الإلكتروني: \(email)
            إصدار التطبيق: 1.0
            iOS: \(UIDevice.current.systemVersion)
            الجهاز: \(UIDevice.current.model)

            اكتب المشكلة هنا:
            """
        } else {
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

    #if DEBUG
    private var debugContextSection: some View {
        Section(SettingsL10n.text("DEBUG Context", "سياق التطوير")) {
            Button(SettingsL10n.text("Refresh Context Snapshot", "تحديث لقطة السياق")) {
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
                Text(SettingsL10n.text("No snapshot loaded", "لم يتم تحميل لقطة"))
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
                    Label(SettingsL10n.text("Enable reminders", "تفعيل التذكيرات"), systemImage: "bell.fill")
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

                Toggle(SettingsL10n.text("Medication reminders", "تذكيرات الأدوية"), isOn: $notifyDoses)
                    .disabled(!notificationsEnabled)
                    .onChange(of: notifyDoses) { _, _ in
                        persistReminderSettings()
                        NotificationCenter.default.post(name: NSNotification.Name("UserRoutineChanged"), object: nil)
                    }

                Toggle(SettingsL10n.text("Appointment reminders", "تذكيرات المواعيد"), isOn: $notifyAppointments)
                    .disabled(!notificationsEnabled)
                    .onChange(of: notifyAppointments) { _, _ in
                        persistReminderSettings()
                    }

                if settings.activePatientID != nil {
                    Toggle(SettingsL10n.text("Caregiver medication reminders", "تذكيرات أدوية لمقدم الرعاية"), isOn: $notifyCaregiverDoses)
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
                    Button(SettingsL10n.text("Test self reminder in 15 seconds", "اختبار تذكير شخصي بعد 15 ثانية")) {
                        NotificationsManager.shared.scheduleDebugMedicationReminder(type: .selfUser)
                    }

                    Button(SettingsL10n.text("Test family member reminder in 15 seconds", "اختبار تذكير لفرد عائلة بعد 15 ثانية")) {
                        NotificationsManager.shared.scheduleDebugMedicationReminder(type: .patient)
                    }

                    Button(SettingsL10n.text("Test caregiver reminder in 15 seconds", "اختبار تذكير لمقدم الرعاية بعد 15 ثانية")) {
                        NotificationsManager.shared.scheduleDebugMedicationReminder(type: .caregiver)
                    }
                } header: {
                    Text(SettingsL10n.text("Developer Tests", "اختبارات المطور"))
                } footer: {
                    Text(SettingsL10n.text(
                        "DEBUG only. These buttons are not compiled into production builds.",
                        "تظهر في وضع التطوير فقط، ولا يتم تضمينها في نسخة الإنتاج."
                    ))
                        .multilineTextAlignment(isArabic ? .trailing : .leading)
                }
                .listRowBackground(Color.istsehCard)
            }
            #endif
        }
        .scrollContentBackground(.hidden)
        .background(Color.istsehPageBackground.ignoresSafeArea())
        .navigationTitle(SettingsL10n.text("Reminders", "التذكيرات"))
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.istsehGreen)
        .task(id: reminderContextKey) {
            loadReminderSettings()
        }
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
    }

    private var footerText: String {
        if let name = settings.activePatientName {
            return SettingsL10n.text(
                "Reminders are scheduled using \(name)'s medication plan and daily routine.",
                "تتم جدولة التذكيرات حسب خطة أدوية \(name) وروتينه اليومي."
            )
        }
        return SettingsL10n.text(
            "Reminders are scheduled using your medication plan and daily routine.",
            "تتم جدولة التذكيرات حسب خطة أدويتك وروتينك اليومي."
        )
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
            Section(header: Text(SettingsL10n.text("General", "عام"))) {
                Text(SettingsL10n.text("How do I add a medication?", "كيف أضيف دواء؟"))
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
                Text(SettingsL10n.text("How do I edit or delete a medication?", "كيف أعدل أو أحذف دواء؟"))
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
            }
            Section(header: Text(SettingsL10n.text("Scheduling", "الجدولة"))) {
                Text(SettingsL10n.text("How are dose times calculated?", "كيف يتم حساب أوقات الجرعات؟"))
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
                Text(SettingsL10n.text("How do food rules affect my schedule?", "كيف تؤثر تعليمات الطعام على الجدول؟"))
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
            }
            Section(header: Text(SettingsL10n.text("Notifications", "التنبيهات"))) {
                Text(SettingsL10n.text("How can I change reminders?", "كيف أغير التذكيرات؟"))
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
                Text(SettingsL10n.text("Why didn't I receive a notification?", "لماذا لم يصلني تنبيه؟"))
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
            }
        }
        .navigationTitle(SettingsL10n.text("FAQ", "الأسئلة الشائعة"))
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
    }
}

// MARK: - Shared Settings Components

struct SettingsNavRow<D: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var showsDivider: Bool = false
    @ViewBuilder var destination: () -> D
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var isActive = false

    private var isRTL: Bool { layoutDirection == .rightToLeft }
    private var rowTextAlignment: TextAlignment { isRTL ? .trailing : .leading }
    private var rowHorizontalAlignment: HorizontalAlignment { isRTL ? .trailing : .leading }
    private var rowFrameAlignment: Alignment { isRTL ? .trailing : .leading }

    var body: some View {
        Button {
            isActive = true
        } label: {
            VStack(spacing: 0) {
                rowContent
                if showsDivider {
                    SettingsRowDivider()
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .navigationDestination(isPresented: $isActive) {
            destination()
        }
    }

    private var rowContent: some View {
        HStack(spacing: 14) {
            if isRTL {
                chevronView
                titleStack
                SettingsIconBadge(systemName: icon, color: iconColor)
            } else {
                SettingsIconBadge(systemName: icon, color: iconColor)
                titleStack
                chevronView
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var titleStack: some View {
        VStack(alignment: rowHorizontalAlignment, spacing: 2) {
            Text(title)
                .font(.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(rowTextAlignment)
                .frame(maxWidth: .infinity, alignment: rowFrameAlignment)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(rowTextAlignment)
                .frame(maxWidth: .infinity, alignment: rowFrameAlignment)
        }
        .frame(maxWidth: .infinity, alignment: rowFrameAlignment)
    }

    private var chevronView: some View {
        Image(systemName: isRTL ? "chevron.left" : "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary.opacity(0.75))
            .frame(width: 18)
    }
}

struct SettingsLinkRow<D: View>: View {
    let icon: String
    let text: String
    var iconColor: Color = Color.istsehGreen
    var showsDivider: Bool = false
    @ViewBuilder var destination: () -> D
    @State private var isActive = false

    var body: some View {
        SettingsActionRow(
            icon: icon,
            text: text,
            iconColor: iconColor,
            showsChevron: true,
            showsDivider: showsDivider
        ) {
            isActive = true
        }
        .navigationDestination(isPresented: $isActive) {
            destination()
        }
    }
}

struct SettingsActionRow: View {
    let icon: String
    let text: String
    var iconColor: Color = Color.istsehGreen
    var showsChevron: Bool = false
    var showsDivider: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 0) {
                SettingsPlainRow(
                    icon: icon,
                    text: text,
                    iconColor: iconColor,
                    showsChevron: showsChevron
                )
                .padding(.vertical, 10)

                if showsDivider {
                    SettingsRowDivider()
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
    }
}

struct SettingsPlainRow: View {
    let icon: String
    let text: String
    var iconColor: Color = Color.istsehGreen
    var showsChevron: Bool = false
    @Environment(\.layoutDirection) private var layoutDirection

    private var isRTL: Bool { layoutDirection == .rightToLeft }

    var body: some View {
        HStack(spacing: 10) {
            if isRTL {
                if showsChevron {
                    SettingsDisclosureChevron()
                }
                Text(text)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                SettingsIconBadge(systemName: icon, color: iconColor)
            } else {
                SettingsIconBadge(systemName: icon, color: iconColor)
                Text(text)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if showsChevron {
                    SettingsDisclosureChevron()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct SettingsMenuRow<MenuContent: View>: View {
    let icon: String
    let title: String
    let value: String
    @ViewBuilder var menu: () -> MenuContent
    @Environment(\.layoutDirection) private var layoutDirection

    private var isRTL: Bool { layoutDirection == .rightToLeft }

    var body: some View {
        HStack(spacing: 10) {
            if isRTL {
                menu()
                Text(title)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                SettingsIconBadge(systemName: icon, color: Color.istsehGreen)
            } else {
                SettingsIconBadge(systemName: icon, color: Color.istsehGreen)
                Text(title)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                menu()
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

private struct SettingsDisclosureChevron: View {
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        Image(systemName: layoutDirection == .rightToLeft ? "chevron.left" : "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary.opacity(0.75))
            .frame(width: 18)
    }
}

private struct SettingsRowDivider: View {
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        Rectangle()
            .fill(Color.istsehCardStroke.opacity(0.75))
            .frame(maxWidth: .infinity)
            .frame(height: 1 / UIScreen.main.scale)
            .padding(layoutDirection == .rightToLeft ? .trailing : .leading, 44)
            .padding(layoutDirection == .rightToLeft ? .leading : .trailing, 32)
    }
}

private struct SettingsMixedDirectionText: View {
    let text: String
    var style: Font? = nil
    @Environment(\.layoutDirection) private var layoutDirection

    private var isLTRValue: Bool {
        text.range(of: #"[A-Za-z0-9@._+\-/]"#, options: .regularExpression) != nil
    }

    var body: some View {
        Text(text)
            .font(style)
            .environment(\.layoutDirection, isLTRValue ? .leftToRight : layoutDirection)
            .multilineTextAlignment(isLTRValue ? .leading : (layoutDirection == .rightToLeft ? .trailing : .leading))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
    }
}

struct SettingsValueRow: View {
    let title: String
    let value: String
    @Environment(\.layoutDirection) private var layoutDirection

    private var isRTL: Bool { layoutDirection == .rightToLeft }

    var body: some View {
        HStack(spacing: 12) {
            if isRTL {
                SettingsMixedDirectionText(text: value)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(title)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                SettingsMixedDirectionText(text: value)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct SettingsEditableTextRow: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    @Environment(\.layoutDirection) private var layoutDirection

    private var isRTL: Bool { layoutDirection == .rightToLeft }
    private var isLTRInput: Bool {
        text.range(of: #"[A-Za-z0-9@._+\-/]"#, options: .regularExpression) != nil
            || placeholder.range(of: #"[A-Za-z0-9@._+\-/]"#, options: .regularExpression) != nil
    }
    private var inputDirection: LayoutDirection {
        isLTRInput ? .leftToRight : (isRTL ? .rightToLeft : .leftToRight)
    }
    private var inputAlignment: TextAlignment {
        isLTRInput ? .leading : (isRTL ? .trailing : .trailing)
    }

    var body: some View {
        Group {
            if isRTL {
                VStack(alignment: .trailing, spacing: 8) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    TextField(placeholder, text: $text)
                        .multilineTextAlignment(inputAlignment)
                        .textInputAutocapitalization(isLTRInput ? .never : .words)
                        .environment(\.layoutDirection, inputDirection)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.istsehPageBackground.opacity(0.45))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.istsehCardStroke, lineWidth: 1)
                        )
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.vertical, 4)
            } else {
                HStack {
                    Text(title)
                    Spacer(minLength: 16)
                    TextField(placeholder, text: $text)
                        .multilineTextAlignment(inputAlignment)
                        .textInputAutocapitalization(isLTRInput ? .never : .words)
                        .environment(\.layoutDirection, inputDirection)
                }
            }
        }
    }
}

struct SettingsDateRow: View {
    let title: String
    @Binding var selection: Date
    @Environment(\.layoutDirection) private var layoutDirection

    private var isRTL: Bool { layoutDirection == .rightToLeft }

    var body: some View {
        DatePicker(
            title,
            selection: $selection,
            displayedComponents: .date
        )
        .multilineTextAlignment(isRTL ? .trailing : .leading)
        .environment(\.layoutDirection, layoutDirection)
    }
}

extension AppSettings.AppearanceMode {
    var localizedLabel: String {
        switch self {
        case .light:
            return SettingsL10n.text("Light", "فاتح")
        case .dark:
            return SettingsL10n.text("Dark", "داكن")
        case .system:
            return SettingsL10n.text("System", "تلقائي")
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
