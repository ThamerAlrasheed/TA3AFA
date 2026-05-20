import SwiftUI
import Supabase

struct FamilySettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @AppStorage("appearance.language") private var languageCode: String =
        Locale.current.language.languageCode?.identifier ?? "en"
    @State private var showingAddMember = false
    @State private var isLoading = false
    @State private var patients: [PatientProfile] = []
    @State private var selectedPatient: PatientProfile?

    private var isArabic: Bool { languageCode == "ar" }
    
    struct PatientProfile: Identifiable, Codable, Hashable {
        let id: String
        let firstName: String
        let lastName: String
        let status: String
        var canPatientAddMeds: Bool = true
        var canPatientManageCalendar: Bool = true
        var notifyPatientMeds: Bool = true
        var notifyPatientAppointments: Bool = true
    }

    private var supabase: SupabaseManager { .shared }

    var body: some View {
        List {
            Section {
                if patients.isEmpty && !isLoading {
                    Text(SettingsL10n.text("No family members connected yet.", "لا يوجد أفراد عائلة مرتبطون حتى الآن."))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(isArabic ? .trailing : .leading)
                        .padding(.vertical, 8)
                } else {
                    ForEach(patients) { patient in
                        Button {
                            selectedPatient = patient
                        } label: {
                            patientNavigationRow(patient)
                        }
                        .buttonStyle(.plain)
                        .listRowSeparator(.hidden)
                        .padding(.vertical, 6)
                    }
                }
            } header: {
                Text(SettingsL10n.text("Family Members", "أفراد العائلة"))
            }
            
            Section {
                SettingsActionRow(
                    icon: "person.badge.plus",
                    text: SettingsL10n.text("Add Family Member", "إضافة فرد من العائلة")
                ) {
                    showingAddMember = true
                }
            } footer: {
                Text(SettingsL10n.text(
                    "Adding a family member allows you to manage their medications and schedule.",
                    "إضافة فرد من العائلة تتيح لك إدارة أدويته وجدوله."
                ))
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
            }
            .listRowSeparator(.hidden)
        }
        .navigationTitle(SettingsL10n.text("Family Members", "أفراد العائلة"))
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
        .navigationDestination(item: $selectedPatient) { patient in
            ManagedPatientSettingsView(patient: patient) {
                Task { await loadPatients() }
            }
        }
        .sheet(isPresented: $showingAddMember) {
            AddFamilyMemberView { _ in
                Task { await loadPatients() }
            }
        }
        .task { await loadPatients() }
    }

    private func displayName(for patient: PatientProfile) -> String {
        "\(patient.firstName) \(patient.lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var patientIcon: some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.title2)
            .foregroundStyle(Color.istsehGreen)
            .frame(width: 32)
    }

    private func patientNavigationRow(_ patient: PatientProfile) -> some View {
        HStack(spacing: 12) {
            if isArabic {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.75))
                    .frame(width: 18)
                patientText(patient)
                patientIcon
            } else {
                patientIcon
                patientText(patient)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.75))
                    .frame(width: 18)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func patientText(_ patient: PatientProfile) -> some View {
        VStack(alignment: isArabic ? .trailing : .leading, spacing: 4) {
            Text(displayName(for: patient))
                .font(.headline)
                .multilineTextAlignment(isArabic ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: isArabic ? .trailing : .leading)

            Text(localizedStatus(patient.status))
                .font(.caption2)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(patient.status == "active" ? Color.istsehGreenSoft : .orange.opacity(0.12))
                .clipShape(Capsule())
                .foregroundStyle(patient.status == "active" ? Color.istsehGreen : .orange)
                .frame(maxWidth: .infinity, alignment: isArabic ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: isArabic ? .trailing : .leading)
    }

    private func localizedStatus(_ status: String) -> String {
        guard isArabic else { return status.capitalized }
        switch status.lowercased() {
        case "active": return "نشط"
        case "pending": return "بانتظار القبول"
        default: return status
        }
    }

    private func loadPatients() async {
        guard let uid = supabase.authenticatedUserID else { return }
        let uidString = uid.uuidString.lowercased()
        isLoading = true
        defer { isLoading = false }

        struct RelationRow: Decodable {
            let patient_id: String
            let status: String
            let can_patient_add_meds: Bool
            let can_patient_manage_calendar: Bool
            let notify_patient_meds: Bool
            let notify_patient_appointments: Bool
            struct UserRef: Decodable {
                let first_name: String?
                let last_name: String?
            }
            let users: UserRef?
        }

        do {
            let rows: [RelationRow] = try await supabase.client
                .from("caregiver_relations")
                .select("patient_id, status, can_patient_add_meds, can_patient_manage_calendar, notify_patient_meds, notify_patient_appointments, users!caregiver_relations_patient_id_fkey(first_name, last_name)")
                .eq("caregiver_id", value: uidString)
                .execute()
                .value

            patients = rows.map {
                PatientProfile(
                    id: $0.patient_id,
                    firstName: $0.users?.first_name ?? "",
                    lastName: $0.users?.last_name ?? "",
                    status: $0.status,
                    canPatientAddMeds: $0.can_patient_add_meds,
                    canPatientManageCalendar: $0.can_patient_manage_calendar,
                    notifyPatientMeds: $0.notify_patient_meds,
                    notifyPatientAppointments: $0.notify_patient_appointments
                )
            }
            settings.familyMembers = patients.map(\.id)
        } catch is CancellationError {
            return
        } catch {
            print("⚠️ loadPatients failed for \(uidString):", error)
        }
    }
}

enum CareProfileMenuPresentation {
    case compact
    case pill
}

struct CareProfileMenu: View {
    @EnvironmentObject var settings: AppSettings
    var presentation: CareProfileMenuPresentation = .compact
    var onSelectionChanged: () -> Void

    @State private var patients: [FamilySettingsView.PatientProfile] = []
    @State private var isLoading = false

    private var supabase: SupabaseManager { .shared }

    var body: some View {
        Menu {
            Button {
                selectSelf()
            } label: {
                Label(
                    SettingsL10n.text("My Profile", "ملفي الشخصي"),
                    systemImage: settings.activePatientID == nil ? "checkmark.circle.fill" : "person.circle"
                )
            }

            if isLoading {
                Label(SettingsL10n.text("Loading family…", "جاري تحميل العائلة…"), systemImage: "hourglass")
            } else if patients.isEmpty {
                Label(SettingsL10n.text("No family members", "لا يوجد أفراد عائلة"), systemImage: "person.2.slash")
            } else {
                Divider()
                ForEach(patients) { patient in
                    Button {
                        select(patient)
                    } label: {
                        Label(displayName(for: patient), systemImage: isSelected(patient) ? "checkmark.circle.fill" : "person.crop.circle")
                    }
                }
            }
        } label: {
            menuLabel
        }
        .task { await loadPatients() }
    }

    @ViewBuilder
    private var menuLabel: some View {
        switch presentation {
        case .compact:
            HStack(spacing: 5) {
                Image(systemName: settings.activePatientID == nil ? "person.circle.fill" : "person.crop.circle.badge.checkmark")
                Text(settings.activePatientID == nil ? SettingsL10n.text("My Profile", "ملفي الشخصي") : settings.activeCareDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.istsehGreen)
        case .pill:
            HStack(spacing: 7) {
                Image(systemName: settings.activePatientID == nil ? "person.circle.fill" : "person.crop.circle.badge.checkmark")
                Text(settings.activePatientID == nil ? SettingsL10n.text("My Profile", "ملفي الشخصي") : SettingsL10n.managing(settings.activeCareDisplayName))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.istsehGreen)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.istsehGreenSoft, in: Capsule())
        }
    }

    private func selectSelf() {
        settings.stopActingAsPatient()
        Task { await settings.loadRoutineFromSupabase() }
        onSelectionChanged()
    }

    private func select(_ patient: FamilySettingsView.PatientProfile) {
        guard let pid = UUID(uuidString: patient.id) else { return }
        settings.actAsPatient(id: pid, displayName: displayName(for: patient))
        Task { await settings.loadRoutineFromSupabase() }
        onSelectionChanged()
    }

    private func isSelected(_ patient: FamilySettingsView.PatientProfile) -> Bool {
        settings.activePatientID == patient.id.lowercased()
    }

    private func displayName(for patient: FamilySettingsView.PatientProfile) -> String {
        "\(patient.firstName) \(patient.lastName)".trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadPatients() async {
        guard let uid = supabase.authenticatedUserID else { return }
        let uidString = uid.uuidString.lowercased()
        isLoading = true
        defer { isLoading = false }

        struct RelationRow: Decodable {
            let patient_id: String
            let status: String
            let can_patient_add_meds: Bool
            let can_patient_manage_calendar: Bool
            let notify_patient_meds: Bool
            let notify_patient_appointments: Bool
            struct UserRef: Decodable {
                let first_name: String?
                let last_name: String?
            }
            let users: UserRef?
        }

        do {
            let rows: [RelationRow] = try await supabase.client
                .from("caregiver_relations")
                .select("patient_id, status, can_patient_add_meds, can_patient_manage_calendar, notify_patient_meds, notify_patient_appointments, users!caregiver_relations_patient_id_fkey(first_name, last_name)")
                .eq("caregiver_id", value: uidString)
                .execute()
                .value

            patients = rows.map {
                FamilySettingsView.PatientProfile(
                    id: $0.patient_id,
                    firstName: $0.users?.first_name ?? "",
                    lastName: $0.users?.last_name ?? "",
                    status: $0.status,
                    canPatientAddMeds: $0.can_patient_add_meds,
                    canPatientManageCalendar: $0.can_patient_manage_calendar,
                    notifyPatientMeds: $0.notify_patient_meds,
                    notifyPatientAppointments: $0.notify_patient_appointments
                )
            }
            settings.familyMembers = patients.map(\.id)
        } catch is CancellationError {
            return
        } catch {
            print("⚠️ CareProfileMenu loadPatients failed for \(uidString):", error)
        }
    }
}

struct ManagedPatientSettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @AppStorage("appearance.language") private var languageCode: String =
        Locale.current.language.languageCode?.identifier ?? "en"
    @State var patient: FamilySettingsView.PatientProfile
    var onUpdate: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var isTransferring = false
    @State private var newCaregiverEmail = ""
    @State private var statusMessage: String?
    @State private var isSaving = false
    @State private var showRemoveConfirmation = false

    private var isArabic: Bool { languageCode == "ar" }
    private var supabase: SupabaseManager { .shared }

    var body: some View {
        List {
            Section {
                Toggle(SettingsL10n.text("Can add medications", "يمكنه إضافة الأدوية"), isOn: $patient.canPatientAddMeds)
                    .onChange(of: patient.canPatientAddMeds) { _, _ in Task { await savePermissions() } }
                
                Toggle(SettingsL10n.text("Can manage calendar", "يمكنه إدارة التقويم"), isOn: $patient.canPatientManageCalendar)
                    .onChange(of: patient.canPatientManageCalendar) { _, _ in Task { await savePermissions() } }
            } header: {
                Text(SettingsL10n.text("Patient Permissions", "صلاحيات المريض"))
            }

            Section {
                Toggle(SettingsL10n.text("Medication Reminders", "تذكيرات الأدوية"), isOn: $patient.notifyPatientMeds)
                    .onChange(of: patient.notifyPatientMeds) { _, _ in Task { await savePermissions() } }
                
                Toggle(SettingsL10n.text("Appointment Reminders", "تذكيرات المواعيد"), isOn: $patient.notifyPatientAppointments)
                    .onChange(of: patient.notifyPatientAppointments) { _, _ in Task { await savePermissions() } }
            } header: {
                Text(SettingsL10n.text("Patient Notifications", "تنبيهات المريض"))
            }

            Section {
                if isTransferring {
                    SettingsEditableTextRow(
                        title: SettingsL10n.text("New Caregiver Email", "بريد مقدم الرعاية الجديد"),
                        placeholder: "caregiver@example.com",
                        text: $newCaregiverEmail
                    )
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.none)
                    
                    Button(SettingsL10n.text("Confirm Transfer", "تأكيد النقل")) {
                        Task { await performTransfer() }
                    }
                    .bold()
                    .foregroundStyle(.red)
                    .disabled(newCaregiverEmail.isEmpty || isSaving)
                    
                    Button(SettingsL10n.text("Cancel", "إلغاء")) {
                        isTransferring = false
                        newCaregiverEmail = ""
                    }
                    .foregroundStyle(.secondary)
                } else {
                    SettingsActionRow(
                        icon: "arrowshape.turn.up.right.fill",
                        text: SettingsL10n.text("Transfer Patient to Another User", "نقل المريض إلى مستخدم آخر"),
                        iconColor: .orange
                    ) {
                        isTransferring = true
                    }
                    .foregroundStyle(.orange)
                }
            } header: {
                Text(SettingsL10n.text("Transfer Care", "نقل الرعاية"))
            } footer: {
                Text(SettingsL10n.text(
                    "Transferring will move \(patient.firstName) to a new caregiver. You will lose access immediately.",
                    "سيتم نقل \(patient.firstName) إلى مقدم رعاية جديد، وستفقد الوصول مباشرة."
                ))
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
            }

            Section {
                SettingsActionRow(
                    icon: "person.fill.xmark",
                    text: SettingsL10n.text("Remove Family Member", "إزالة فرد العائلة"),
                    iconColor: .red
                ) {
                    showRemoveConfirmation = true
                }
                .foregroundStyle(.red)
                .disabled(isSaving)
            } header: {
                Text(SettingsL10n.text("Remove Access", "إزالة الوصول"))
            } footer: {
                Text(SettingsL10n.text(
                    "Removing \(patient.firstName) will stop showing their medications, appointments, and settings in your family list.",
                    "إزالة \(patient.firstName) ستوقف ظهور أدويته ومواعيده وإعداداته في قائمة العائلة."
                ))
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
            }
            
            if let msg = statusMessage {
                Section {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle((msg.contains("Success") || msg.contains("نجاح") || msg.contains("تم ")) ? Color.istsehGreen : .red)
                        .multilineTextAlignment(isArabic ? .trailing : .leading)
                }
            }
        }
        .navigationTitle(SettingsL10n.text("\(patient.firstName)'s Settings", "إعدادات \(patient.firstName)"))
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
        .disabled(isSaving)
        .alert(SettingsL10n.text("Remove \(patient.firstName)?", "إزالة \(patient.firstName)؟"), isPresented: $showRemoveConfirmation) {
            Button(SettingsL10n.text("Remove", "إزالة"), role: .destructive) {
                Task { await removeFamilyMember() }
            }
            Button(SettingsL10n.text("Cancel", "إلغاء"), role: .cancel) { }
        } message: {
            Text(SettingsL10n.text(
                "You will no longer be able to manage this family member from your caregiver account.",
                "لن تتمكن من إدارة هذا الفرد من حساب مقدم الرعاية."
            ))
        }
        .overlay {
            if isSaving {
                BrandedLoadingView(
                    message: LoadingMessage.custom("Saving…", "جاري الحفظ…").text,
                    style: .card
                )
                .padding(.horizontal, 28)
            }
        }
    }

    private func savePermissions() async {
        guard let pid = UUID(uuidString: patient.id) else { return }
        let pidString = pid.uuidString.lowercased()
        isSaving = true
        defer { isSaving = false }
        do {
            try await supabase.updatePatientPermissions(
                patientId: pid,
                canAddMeds: patient.canPatientAddMeds,
                canManageCalendar: patient.canPatientManageCalendar,
                notifyMeds: patient.notifyPatientMeds,
                notifyApps: patient.notifyPatientAppointments
            )
            onUpdate()
        } catch {
            print("⚠️ savePermissions failed for \(pidString):", error)
            statusMessage = SettingsL10n.text("Failed to update: \(error.localizedDescription)", "تعذر التحديث: \(error.localizedDescription)")
        }
    }

    private func performTransfer() async {
        guard let pid = UUID(uuidString: patient.id) else { return }
        let pidString = pid.uuidString.lowercased()
        isSaving = true
        statusMessage = nil
        defer { isSaving = false }
        
        do {
            try await supabase.transferPatient(id: pid, toEmail: newCaregiverEmail)
            statusMessage = SettingsL10n.text("Success! Patient transferred.", "تم نقل المريض بنجاح.")
            // Context cleanup if needed
            if SupabaseManager.shared.activePatientID == pid {
                settings.stopActingAsPatient()
            }
            onUpdate()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            dismiss()
        } catch {
            print("⚠️ transferPatient failed for \(pidString):", error)
            statusMessage = SettingsL10n.text("Transfer failed: \(error.localizedDescription)", "تعذر النقل: \(error.localizedDescription)")
        }
    }

    private func removeFamilyMember() async {
        guard let pid = UUID(uuidString: patient.id) else { return }
        let pidString = pid.uuidString.lowercased()
        isSaving = true
        statusMessage = nil
        defer { isSaving = false }

        do {
            try await supabase.removeFamilyMember(patientId: pid)
            if SupabaseManager.shared.activePatientID == pid {
                settings.stopActingAsPatient()
            }
            settings.familyMembers.removeAll { $0.lowercased() == pidString }
            onUpdate()
            dismiss()
        } catch {
            print("⚠️ removeFamilyMember failed for \(pidString):", error)
            statusMessage = SettingsL10n.text("Remove failed: \(error.localizedDescription)", "تعذرت الإزالة: \(error.localizedDescription)")
        }
    }

}

struct AddFamilyMemberView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settings: AppSettings
    @AppStorage("appearance.language") private var languageCode: String =
        Locale.current.language.languageCode?.identifier ?? "en"
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var dob = Date()
    @State private var allergies: [String] = []
    @State private var conditions: [String] = []
    @State private var pendingCustomAllergy = ""
    @State private var pendingCustomCondition = ""
    
    // Initial Settings
    @State private var canAddMeds = true
    @State private var canManageCalendar = true
    @State private var notifyMeds = true
    @State private var notifyApps = true

    @State private var generatedCode: String?
    @State private var isSaving = false
    @State private var errorText: String?
    
    var onSave: (String) -> Void

    private var isArabic: Bool { languageCode == "ar" }
    private var supabase: SupabaseManager { .shared }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if let code = generatedCode {
                    ISTSEHCard {
                        VStack(spacing: 16) {
                        Text(SettingsL10n.text("Profile Created!", "تم إنشاء الملف!"))
                            .font(.headline)
                        
                        Text(SettingsL10n.text("Share this code with \(firstName):", "شارك هذا الرمز مع \(firstName):"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Text(formatCode(code))
                            .font(.system(size: 42, weight: .bold, design: .monospaced))
                            .tracking(8)
                            .padding()
                            .background(Color.istsehCard)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.istsehCardStroke, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        
                        Text(SettingsL10n.text("This code expires in 72 hours.", "ينتهي هذا الرمز خلال 72 ساعة."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(isArabic ? .trailing : .leading)
                        
                        Button(SettingsL10n.text("Copy Code", "نسخ الرمز")) {
                            UIPasteboard.general.string = code
                        }
                        .buttonStyle(.bordered)
                        .tint(Color.istsehGreen)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    }
                } else {
                    VStack(spacing: 16) {
                    ISTSEHCard {
                        VStack(alignment: isArabic ? .trailing : .leading, spacing: 12) {
                            Text(SettingsL10n.text("Patient Information", "معلومات المريض"))
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: isArabic ? .trailing : .leading)

                        SettingsEditableTextRow(
                            title: SettingsL10n.text("First Name", "الاسم الأول"),
                            placeholder: SettingsL10n.text("First Name", "الاسم الأول"),
                            text: $firstName
                        )
                        SettingsEditableTextRow(
                            title: SettingsL10n.text("Last Name", "اسم العائلة"),
                            placeholder: SettingsL10n.text("Last Name", "اسم العائلة"),
                            text: $lastName
                        )
                        DatePicker(SettingsL10n.text("Date of Birth", "تاريخ الميلاد"), selection: $dob, in: ...Date(), displayedComponents: .date)
                                .multilineTextAlignment(isArabic ? .trailing : .leading)
                                .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
                                .tint(Color.istsehGreen)
                    }
                    }
                    
                        AllergySelectionSection(
                            selectedItems: $allergies,
                            pendingCustomText: $pendingCustomAllergy
                        )
                        .padding(.vertical, 4)
                        
                        ConditionSelectionSection(
                            selectedItems: $conditions,
                            pendingCustomText: $pendingCustomCondition
                        )
                        .padding(.vertical, 4)
                    
                    ISTSEHCard {
                        VStack(alignment: isArabic ? .trailing : .leading, spacing: 12) {
                            Text(SettingsL10n.text("Initial Permissions", "الصلاحيات الأولية"))
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: isArabic ? .trailing : .leading)

                        Toggle(SettingsL10n.text("Can add medications", "يمكنه إضافة الأدوية"), isOn: $canAddMeds)
                        Toggle(SettingsL10n.text("Can manage calendar", "يمكنه إدارة التقويم"), isOn: $canManageCalendar)
                        Toggle(SettingsL10n.text("Medication Reminders", "تذكيرات الأدوية"), isOn: $notifyMeds)
                        Toggle(SettingsL10n.text("Appointment Reminders", "تذكيرات المواعيد"), isOn: $notifyApps)
                        Text(SettingsL10n.text("These settings can be changed later in the patient's settings.", "يمكن تغيير هذه الإعدادات لاحقًا من إعدادات المريض."))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(isArabic ? .trailing : .leading)
                                .padding(.top, 4)
                        }
                    }
                    
                    if let err = errorText {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, alignment: .center)
                    }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .avoidsTabBar()
            .background(Color.istsehPageBackground.ignoresSafeArea())
            .navigationTitle(SettingsL10n.text("Add Family Member", "إضافة فرد من العائلة"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(SettingsL10n.text("Close", "إغلاق")) { dismiss() }
                }
                if generatedCode == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(SettingsL10n.text("Generate Code", "إنشاء الرمز")) {
                            Task { await generateCode() }
                        }
                        .disabled(firstName.isEmpty || lastName.isEmpty || isSaving)
                    }
                }
            }
        }
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
    }
    
    private func generateCode() async {
        guard supabase.client.auth.currentSession?.user.id != nil else {
            await MainActor.run {
                errorText = SettingsL10n.text(
                    "You must be signed in with a caregiver account to create a family member.",
                    "يجب تسجيل الدخول بحساب مقدم رعاية لإنشاء فرد عائلة."
                )
            }
            return
        }
        guard applyPendingCustomItems() else { return }
        isSaving = true
        errorText = nil
        defer { isSaving = false }

        do {
            let response = try await supabase.createFamilyMember(
                firstName: firstName,
                lastName: lastName,
                dateOfBirth: dob,
                allergies: allergies,
                conditions: conditions,
                canAddMeds: canAddMeds,
                canManageCalendar: canManageCalendar,
                notifyMeds: notifyMeds,
                notifyApps: notifyApps
            )

            await MainActor.run {
                settings.role = .caregiver
                self.generatedCode = response.code
                onSave(firstName)
            }
        } catch {
            await MainActor.run {
                errorText = friendlyErrorMessage(for: error)
            }
        }
    }

    @discardableResult
    private func applyPendingCustomItems() -> Bool {
        let pendingAllergy = pendingCustomAllergy.trimmingCharacters(in: .whitespacesAndNewlines)
        let pendingCondition = pendingCustomCondition.trimmingCharacters(in: .whitespacesAndNewlines)

        if !pendingAllergy.isEmpty {
            errorText = MedicalProfileText.isArabic
                ? "اضغط إضافة لحفظ الحساسية المخصصة أو امسح الحقل."
                : "Tap Add to save the custom allergy or clear the field."
            return false
        }

        if !pendingCondition.isEmpty {
            errorText = MedicalProfileText.isArabic
                ? "اضغط إضافة لحفظ المرض المزمن المخصص أو امسح الحقل."
                : "Tap Add to save the custom condition or clear the field."
            return false
        }

        return true
    }

    private func friendlyErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("non-2xx status code: 404") || message.contains("function") && message.contains("not found") {
            return SettingsL10n.text(
                "The family-member backend function is not deployed yet.",
                "وظيفة إنشاء أفراد العائلة غير مفعلة في الخادم بعد."
            )
        }
        return error.localizedDescription
    }
    
    private func formatCode(_ code: String) -> String {
        var res = ""
        for (i, char) in code.enumerated() {
            res.append(char)
            if i == 2 { res.append(" ") }
        }
        return res
    }
}
