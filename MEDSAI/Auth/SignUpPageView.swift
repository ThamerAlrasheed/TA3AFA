import SwiftUI
import Supabase
import UserNotifications

struct SignUpPageView: View {
    private struct UserProfileUpsertPayload: Encodable {
        let id: String
        let email: String
        let first_name: String
        let last_name: String
        let date_of_birth: String
        let role: String
    }

    private enum Step: Int, CaseIterable {
        case welcome
        case account
        case profile
        case routine
        case medical
        case notifications
        case preview
    }

    @EnvironmentObject var settings: AppSettings
    @State private var step: Step = .welcome

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @FocusState private var accountFocus: AccountField?
    private enum AccountField { case email, password, confirm }

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @FocusState private var profileFocus: ProfileField?
    private enum ProfileField { case first, last }

    @State private var breakfast = Self.date(hour: 8)
    @State private var lunch = Self.date(hour: 13)
    @State private var dinner = Self.date(hour: 19)
    @State private var bedtime = Self.date(hour: 23)
    @State private var wakeup = Self.date(hour: 7)

    @State private var allergyList: [String] = []
    @State private var conditionList: [String] = []
    @State private var pendingCustomAllergy = ""
    @State private var pendingCustomCondition = ""

    @State private var wantsNotifications = true
    @State private var notificationPermissionMessage: String?
    @State private var busy = false
    @State private var errorText: String?
    @State private var stepValidationMessage: String?
    #if DEBUG
    @State private var signupTrace: [String] = []
    #endif

    private var supabase: SupabaseManager { .shared }

    private var emailValid: Bool {
        let pattern = #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#
        return email.trimmingCharacters(in: .whitespacesAndNewlines).range(of: pattern, options: .regularExpression) != nil
    }

    private var strongPassword: Bool {
        password.count >= 6
    }

    private var canContinue: Bool {
        !busy
    }

    private var validationHint: String? {
        stepValidationMessage
    }

    var body: some View {
        ZStack {
            Color.istsehPageBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    header
                    progressBar
                    currentStepView

                    if let errorText {
                        Text(errorText)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        #if DEBUG
                        signupTraceView
                        #endif
                    }

                    OnboardingFooter(
                        backTitle: MedicalProfileText.back,
                        primaryTitle: step == .preview ? MedicalProfileText.finishSetup : MedicalProfileText.continueText,
                        skipTitle: step == .medical || step == .notifications ? MedicalProfileText.skipForNow : nil,
                        validationHint: validationHint,
                        canContinue: canContinue && !busy,
                        showsBack: step != .welcome,
                        isBusy: busy,
                        onBack: goBack,
                        onPrimary: { Task { await advance() } },
                        onSkip: { Task { await skipOptionalStep() } }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 34)
            }

            if busy {
                Color.black.opacity(0.18).ignoresSafeArea()
                BrandedLoadingView(
                    message: MedicalProfileText.isArabic ? "جاري إنشاء الحساب…" : "Creating account…",
                    style: .card
                )
                .padding(.horizontal, 28)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("ISTSEH")
                    .font(.headline.bold())
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.layoutDirection, MedicalProfileText.isArabic ? .rightToLeft : .leftToRight)
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.istsehGreenSoft)
                    .frame(width: 76, height: 76)
                Image(systemName: stepIcon)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.istsehGreen)
            }

            Text(stepTitle)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)

            Text(stepSubtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }

    private var progressBar: some View {
        VStack(spacing: 8) {
            ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                .tint(Color.istsehGreen)
            Text("\(step.rawValue + 1) / \(Step.allCases.count)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var currentStepView: some View {
        switch step {
        case .welcome:
            welcomeCard
        case .account:
            accountCard
        case .profile:
            profileCard
        case .routine:
            routineCard
        case .medical:
            VStack(spacing: 16) {
                AllergySelectionSection(selectedItems: $allergyList, pendingCustomText: $pendingCustomAllergy)
                ConditionSelectionSection(selectedItems: $conditionList, pendingCustomText: $pendingCustomCondition)
            }
        case .notifications:
            notificationsCard
        case .preview:
            PremiumTeaserView()
        }
    }

    private var welcomeCard: some View {
        ISTSEHCard {
            VStack(alignment: MedicalProfileText.isArabic ? .trailing : .leading, spacing: 14) {
                Label(MedicalProfileText.careTitle, systemImage: "sparkles")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.istsehGreen)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(MedicalProfileText.careSubtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var accountCard: some View {
        ISTSEHCard {
            VStack(spacing: 12) {
                OnboardingField(systemImage: "envelope", placeholder: copy("Email", "البريد الإلكتروني"), text: $email, isSecure: false)
                    .focused($accountFocus, equals: .email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                OnboardingField(systemImage: "lock", placeholder: copy("Password", "كلمة المرور"), text: $password, isSecure: true)
                    .focused($accountFocus, equals: .password)
                    .textContentType(.newPassword)
                OnboardingField(systemImage: "lock.rotation", placeholder: copy("Confirm password", "تأكيد كلمة المرور"), text: $confirmPassword, isSecure: true)
                    .focused($accountFocus, equals: .confirm)
            }
        }
    }

    private var profileCard: some View {
        ISTSEHCard {
            VStack(spacing: 12) {
                OnboardingField(systemImage: "person", placeholder: copy("First name", "الاسم الأول"), text: $firstName, isSecure: false)
                    .focused($profileFocus, equals: .first)
                OnboardingField(systemImage: "person.fill", placeholder: copy("Last name", "اسم العائلة"), text: $lastName, isSecure: false)
                    .focused($profileFocus, equals: .last)

                DatePicker(copy("Date of birth", "تاريخ الميلاد"), selection: $dateOfBirth, in: ...Date(), displayedComponents: .date)
                    .tint(Color.istsehGreen)
                    .padding(.top, 4)
            }
        }
    }

    private var routineCard: some View {
        ISTSEHCard {
            VStack(spacing: 12) {
                Text(MedicalProfileText.dailyRoutine)
                    .font(.headline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                RoutineTimeRow(title: copy("Wake up", "الاستيقاظ"), date: $wakeup, image: "sunrise.fill")
                RoutineTimeRow(title: copy("Breakfast", "الفطور"), date: $breakfast, image: "cup.and.saucer.fill")
                RoutineTimeRow(title: copy("Lunch", "الغداء"), date: $lunch, image: "fork.knife")
                RoutineTimeRow(title: copy("Dinner", "العشاء"), date: $dinner, image: "fork.knife.circle.fill")
                RoutineTimeRow(title: copy("Bedtime", "وقت النوم"), date: $bedtime, image: "moon.fill")
            }
        }
    }

    private var notificationsCard: some View {
        ISTSEHCard {
            VStack(alignment: .center, spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.istsehGreenSoft)
                        .frame(width: 64, height: 64)
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Color.istsehGreen)
                }

                Text(copy(
                    "Medication reminders work best when notifications are enabled. You can change this later in Settings.",
                    "تعمل تذكيرات الأدوية بشكل أفضل عند تفعيل الإشعارات. يمكنك تغيير ذلك لاحقًا من الإعدادات."
                ))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

                Button {
                    Task { await requestNotificationPermission() }
                } label: {
                    Label(copy("Enable Notifications", "تفعيل الإشعارات"), systemImage: "bell.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.istsehGreen)

                if let notificationPermissionMessage {
                    Text(notificationPermissionMessage)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    private func goBack() {
        withAnimation(.easeInOut) {
            step = Step(rawValue: step.rawValue - 1) ?? .welcome
        }
    }

    private func advance() async {
        errorText = nil
        stepValidationMessage = nil
        guard validateCurrentStep() else { return }
        if step == .preview {
            await finish()
            return
        }
        withAnimation(.easeInOut) {
            step = Step(rawValue: step.rawValue + 1) ?? .preview
        }
    }

    private func requestNotificationPermission() async {
        let granted = await NotificationsManager.shared.requestAuthorization()
        wantsNotifications = granted
        notificationPermissionMessage = granted
            ? copy("Notifications are enabled.", "تم تفعيل الإشعارات.")
            : copy("Notifications are off. You can continue and enable them later in Settings.", "الإشعارات غير مفعلة. يمكنك المتابعة وتفعيلها لاحقًا من الإعدادات.")
    }

    private func skipOptionalStep() async {
        guard step == .medical || step == .notifications else { return }
        if step == .notifications {
            wantsNotifications = false
        }
        await advance()
    }

    private func finish() async {
        guard validateAllSteps() else { return }
        busy = true
        defer { busy = false }

        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        resetSignupTrace()
        appendSignupTrace("final_setup started step=\(step.rawValue + 1)/\(Step.allCases.count)")
        appendSignupTrace("validation passed authUidPresent=\(supabase.client.auth.currentSession?.user.id != nil)")
        appendSignupTrace("payload summary: emailPresent=\(!trimmedEmail.isEmpty), firstNamePresent=\(!firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), lastNamePresent=\(!lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty), dobFormat=yyyy-MM-dd, language=\(UserDefaults.standard.string(forKey: "appearance.language") ?? "nil"), appearance=\(UserDefaults.standard.string(forKey: "appearanceMode") ?? "nil"), activePatientID=\(settings.activePatientID ?? "nil"), careCodeActive=\(supabase.isPatientMode), allergiesCount=\(allergyList.count), conditionsCount=\(conditionList.count), routineFields=5")

        do {
            let userId: UUID
            if let existingUserID = supabase.client.auth.currentSession?.user.id {
                userId = existingUserID
                appendSignupTrace("auth retry using existing session uid=\(existingUserID.uuidString.lowercased())")
            } else {
                appendSignupTrace("auth signup started payloadKeys=[email,password]")
                let authResponse = try await runBackendStep("auth.signUp") {
                    try await supabase.client.auth.signUp(email: trimmedEmail, password: password)
                }
                guard let createdUserID = authResponse.session?.user.id else {
                    appendSignupTrace("auth signup returned no session; email confirmation may be required")
                    errorText = copy("Account created. Please log in to continue.", "تم إنشاء الحساب. الرجاء تسجيل الدخول للمتابعة.")
                    return
                }
                userId = createdUserID
                appendSignupTrace("auth signup success uid=\(createdUserID.uuidString.lowercased())")
            }
            guard supabase.client.auth.currentSession?.user.id != nil else {
                appendSignupTrace("auth uid missing after signup/retry")
                errorText = copy("Account created. Please log in to continue.", "تم إنشاء الحساب. الرجاء تسجيل الدخول للمتابعة.")
                return
            }
            await MainActor.run {
                settings.prepareForAuthenticatedSession()
            }
            appendSignupTrace("local session context cleared activePatientID=\(settings.activePatientID ?? "nil"), careCodeActive=\(supabase.isPatientMode)")

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withFullDate]

            let profile = UserProfileUpsertPayload(
                id: userId.uuidString,
                email: trimmedEmail,
                first_name: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                last_name: lastName.trimmingCharacters(in: .whitespacesAndNewlines),
                date_of_birth: isoFormatter.string(from: dateOfBirth),
                role: UserRole.regular.rawValue
            )

            appendSignupTrace("users.upsert started uid=\(userId.uuidString.lowercased()) payloadKeys=[id,email,first_name,last_name,date_of_birth,role]")
            _ = try await runBackendStep("users.upsert") {
                try await supabase.client.from("users").upsert(profile).execute()
            }

            let patientId = userId.uuidString.lowercased()
            try await syncOnboardingMedicalDetails(patientId: patientId)

            appendSignupTrace("navigation/bootstrap started")
            await settings.bootstrapAuthenticatedSession()
            appendSignupTrace("navigation/bootstrap success")
        } catch {
            appendSignupTrace("final_setup failed error=\(sanitize(error))")
            if isDuplicateEmailError(error) {
                errorText = copy("This email is already in use.", "هذا البريد الإلكتروني مستخدم بالفعل.")
                return
            }
            errorText = copy(
                "We couldn’t finish setting up your account. Please try again.",
                "تعذر إكمال إعداد حسابك. يرجى المحاولة مرة أخرى."
            )
        }
    }

    private func validateCurrentStep() -> Bool {
        if let message = validationMessage(for: step) {
            stepValidationMessage = message
            focusFirstInvalidField(for: step)
            return false
        }
        return true
    }

    private func validateAllSteps() -> Bool {
        for candidate in Step.allCases {
            if let message = validationMessage(for: candidate) {
                step = candidate
                stepValidationMessage = message
                focusFirstInvalidField(for: candidate)
                return false
            }
        }
        return true
    }

    private func validationMessage(for candidate: Step) -> String? {
        switch candidate {
        case .welcome, .notifications, .preview:
            return nil
        case .account:
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedEmail.isEmpty {
                return copy("Please enter your email.", "يرجى إدخال البريد الإلكتروني.")
            }
            if !emailValid {
                return copy("Please enter a valid email address.", "يرجى إدخال بريد إلكتروني صحيح.")
            }
            if password.isEmpty {
                return copy("Please enter your password.", "يرجى إدخال كلمة المرور.")
            }
            if password.count < 6 {
                return copy("Password must be at least 6 characters.", "يجب أن تكون كلمة المرور ٦ أحرف على الأقل.")
            }
            if confirmPassword.isEmpty {
                return copy("Please confirm your password.", "يرجى تأكيد كلمة المرور.")
            }
            if password != confirmPassword {
                return copy("Passwords do not match.", "كلمتا المرور غير متطابقتين.")
            }
            return nil
        case .profile:
            if firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return copy("Please enter your first name.", "يرجى إدخال الاسم الأول.")
            }
            if lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return copy("Please enter your last name.", "يرجى إدخال اسم العائلة.")
            }
            if dateOfBirth > Date() {
                return copy("Please enter a valid date of birth.", "يرجى إدخال تاريخ ميلاد صحيح.")
            }
            return nil
        case .routine:
            let times = [wakeup, breakfast, lunch, dinner, bedtime]
            let allTimesValid = times.allSatisfy { date in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
                return comps.hour != nil && comps.minute != nil
            }
            if !allTimesValid || timeString(from: wakeup) == timeString(from: bedtime) {
                return copy("Please complete your daily routine times.", "يرجى إكمال أوقات الروتين اليومي.")
            }
            return nil
        case .medical:
            if !pendingCustomAllergy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return copy("Tap Add to save the custom allergy or clear the field.", "اضغط إضافة لحفظ الحساسية المخصصة أو امسح الحقل.")
            }
            if !pendingCustomCondition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return copy("Tap Add to save the custom condition or clear the field.", "اضغط إضافة لحفظ المرض المزمن المخصص أو امسح الحقل.")
            }
            return nil
        }
    }

    private func focusFirstInvalidField(for candidate: Step) {
        switch candidate {
        case .account:
            if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !emailValid {
                accountFocus = .email
            } else if password.isEmpty || password.count < 6 {
                accountFocus = .password
            } else if confirmPassword.isEmpty || password != confirmPassword {
                accountFocus = .confirm
            }
        case .profile:
            if firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                profileFocus = .first
            } else if lastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                profileFocus = .last
            }
        default:
            break
        }
    }

    private func runBackendStep<T>(_ name: String, operation: () async throws -> T) async throws -> T {
        do {
            let result = try await operation()
            appendSignupTrace("\(name) success")
            return result
        } catch {
            appendSignupTrace("\(name) failed \(sanitize(error))")
            throw error
        }
    }

    private func syncOnboardingMedicalDetails(patientId: String) async throws {
        let routinePayload: [String: String] = [
            "breakfast_time": timeString(from: breakfast),
            "lunch_time": timeString(from: lunch),
            "dinner_time": timeString(from: dinner),
            "bedtime": timeString(from: bedtime),
            "wakeup_time": timeString(from: wakeup)
        ]
        appendSignupTrace("users.update_routine started patientId=\(patientId), payloadKeys=[breakfast_time,lunch_time,dinner_time,bedtime,wakeup_time], valueTypes=String(HH:mm:ss)")
        _ = try await runBackendStep("users.update_routine") {
            try await supabase.client
                .from("users")
                .update(routinePayload)
                .eq("id", value: patientId)
                .execute()
        }

        appendSignupTrace("patient-profile allergies started count=\(allergyList.count), payloadKeys=[action,patient_id,allergy(name,severity,reaction,notes,is_active)]")
        for name in allergyList.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !name.isEmpty {
            try await runBackendStep("patient-profile.save_allergy") {
                try await DrugInfo.saveAllergy(patientId: patientId, allergy: Allergy(name: name))
            }
        }
        appendSignupTrace("patient-profile allergies complete")

        appendSignupTrace("patient-profile conditions started count=\(conditionList.count), payloadKeys=[action,patient_id,condition(name,status,diagnosed_at,notes,is_active)]")
        for name in conditionList.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !name.isEmpty {
            try await runBackendStep("patient-profile.save_condition") {
                try await DrugInfo.saveCondition(patientId: patientId, condition: Condition(name: name))
            }
        }
        appendSignupTrace("patient-profile conditions complete")
    }

    private func sanitize(_ error: Error) -> String {
        if let functionsError = error as? FunctionsError {
            switch functionsError {
            case let .httpError(code, data):
                let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
                return "httpError(status=\(code), body=\(body))"
            case .relayError:
                return "relayError"
            }
        }
        return String(describing: error)
            .replacingOccurrences(of: SupabaseManager.shared.supabaseKey, with: "[redacted-key]")
    }

    private func resetSignupTrace() {
        #if DEBUG
        signupTrace = []
        #endif
    }

    private func appendSignupTrace(_ message: String) {
        #if DEBUG
        let line = "DEBUG_SIGNUP \(message)"
        signupTrace.append(line)
        print(line)
        #endif
    }

    private func isDuplicateEmailError(_ error: Error) -> Bool {
        let message = String(describing: error).lowercased()
        return message.contains("already") || message.contains("registered") || message.contains("duplicate")
    }

    private var stepTitle: String {
        switch step {
        case .welcome: return MedicalProfileText.careTitle
        case .account: return copy("Create your account", "إنشاء حسابك")
        case .profile: return copy("Tell us about you", "أخبرنا عنك")
        case .routine: return MedicalProfileText.dailyRoutine
        case .medical: return MedicalProfileText.medicalProfile
        case .notifications: return MedicalProfileText.notifications
        case .preview: return MedicalProfileText.premiumTitle
        }
    }

    private var stepSubtitle: String {
        switch step {
        case .welcome: return MedicalProfileText.careSubtitle
        case .account: return copy("Use an email and password to keep your care plan synced.", "استخدم البريد الإلكتروني وكلمة المرور لمزامنة خطة رعايتك.")
        case .profile: return copy("Basic details help personalize your medication schedule.", "تساعد البيانات الأساسية في تخصيص جدول أدويتك.")
        case .routine: return copy("ISTSEH uses your day to place reminders at better times.", "يستخدم استصح روتينك لاختيار أوقات تذكير أنسب.")
        case .medical: return copy("Keep this simple. Select what applies or add your own.", "اجعلها بسيطة. اختر ما ينطبق أو أضف عنصرًا مخصصًا.")
        case .notifications: return copy("We will only use reminders for care-related alerts.", "سنستخدم الإشعارات للتذكيرات المتعلقة بالرعاية فقط.")
        case .preview: return MedicalProfileText.premiumSubtitle
        }
    }

    private var stepIcon: String {
        switch step {
        case .welcome: return "cross.case.fill"
        case .account: return "person.badge.plus.fill"
        case .profile: return "person.text.rectangle.fill"
        case .routine: return "clock.fill"
        case .medical: return "heart.text.clipboard.fill"
        case .notifications: return "bell.badge.fill"
        case .preview: return "sparkles"
        }
    }

    private func copy(_ english: String, _ arabic: String) -> String {
        MedicalProfileText.isArabic ? arabic : english
    }

    private func timeString(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d:00", components.hour ?? 0, components.minute ?? 0)
    }

    private static func date(hour: Int, minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    #if DEBUG
    private var signupTraceView: some View {
        DisclosureGroup("DEBUG Signup Trace") {
            VStack(alignment: .leading, spacing: 6) {
                if signupTrace.isEmpty {
                    Text("No trace yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(signupTrace.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(.top, 6)
        }
        .font(.caption.weight(.semibold))
        .padding(12)
        .background(Color.istsehCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.istsehCardStroke, lineWidth: 1)
        )
        .padding(.horizontal, 4)
    }
    #endif
}

private struct OnboardingField: View {
    let systemImage: String
    let placeholder: String
    @Binding var text: String
    let isSecure: Bool

    var body: some View {
        HStack(spacing: 12) {
            if !MedicalProfileText.isArabic {
                icon
            }
            if isSecure {
                SecureField(placeholder, text: $text)
                    .multilineTextAlignment(MedicalProfileText.isArabic ? .trailing : .leading)
            } else {
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(MedicalProfileText.isArabic ? .trailing : .leading)
            }
            if MedicalProfileText.isArabic {
                icon
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.istsehPageBackground.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.istsehCardStroke, lineWidth: 1)
        )
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .foregroundStyle(Color.istsehGreen)
            .frame(width: 22)
    }
}

private struct OnboardingFooter: View {
    let backTitle: String
    let primaryTitle: String
    let skipTitle: String?
    let validationHint: String?
    let canContinue: Bool
    let showsBack: Bool
    let isBusy: Bool
    let onBack: () -> Void
    let onPrimary: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let validationHint, !isBusy {
                Text(validationHint)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            HStack(spacing: 12) {
                if showsBack {
                    Button(backTitle, action: onBack)
                        .font(.headline)
                        .frame(width: 104, height: 52)
                        .background(Color.istsehGreenSoft)
                        .foregroundStyle(Color.istsehGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                Button(action: onPrimary) {
                    Text(primaryTitle)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .background(canContinue ? Color.istsehGreen : Color.istsehGreen.opacity(0.35))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .disabled(!canContinue || isBusy)
            }

            if let skipTitle {
                Button(skipTitle, action: onSkip)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.istsehGreen)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(isBusy)
            }
        }
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, .leftToRight)
    }
}

private struct RoutineTimeRow: View {
    let title: String
    @Binding var date: Date
    let image: String

    var body: some View {
        HStack(spacing: 12) {
            if MedicalProfileText.isArabic {
                timePicker
                Spacer(minLength: 12)
                label
                icon
            } else {
                icon
                label
                Spacer(minLength: 12)
                timePicker
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.istsehPageBackground.opacity(0.46))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.istsehCardStroke, lineWidth: 1)
        )
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.istsehGreenSoft)
                .frame(width: 38, height: 38)
            Image(systemName: image)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.istsehGreen)
        }
    }

    private var label: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .frame(minWidth: 88, alignment: MedicalProfileText.isArabic ? .trailing : .leading)
    }

    private var timePicker: some View {
        DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
            .labelsHidden()
            .tint(Color.istsehGreen)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.istsehCard)
            .clipShape(Capsule())
    }
}

struct PremiumTeaserView: View {
    var body: some View {
        ISTSEHCard {
            VStack(alignment: .center, spacing: 14) {
                Label(MedicalProfileText.comingLater, systemImage: "sparkles")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.istsehGreen)
                Text(MedicalProfileText.premiumTitle)
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(MedicalProfileText.premiumSubtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                VStack(alignment: .center, spacing: 10) {
                    PremiumBenefit(title: MedicalProfileText.isArabic ? "تنبيهات عائلية متقدمة" : "Advanced family alerts")
                    PremiumBenefit(title: MedicalProfileText.isArabic ? "دعم إعادة صرف الدواء" : "Refill support")
                    PremiumBenefit(title: MedicalProfileText.isArabic ? "تقارير سلامة أعمق" : "Deeper safety reports")
                    PremiumBenefit(title: MedicalProfileText.isArabic ? "إدارة أكثر من عائلة" : "Manage more than one family")
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct PremiumBenefit: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.istsehGreen)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .center)
        .environment(\.layoutDirection, MedicalProfileText.isArabic ? .rightToLeft : .leftToRight)
    }
}
