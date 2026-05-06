import SwiftUI
import Supabase

struct FamilySettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var showingAddMember = false
    @State private var isLoading = false
    @State private var patients: [PatientProfile] = []
    
    struct PatientProfile: Identifiable, Codable {
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
                    Text("No family members connected yet.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(patients) { patient in
                        NavigationLink {
                            ManagedPatientSettingsView(patient: patient) {
                                Task { await loadPatients() }
                            }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.green)
                                    .frame(width: 32)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(displayName(for: patient))
                                        .font(.headline)

                                    HStack(spacing: 6) {
                                        Text(patient.status.capitalized)
                                            .font(.caption2)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 3)
                                            .background(patient.status == "active" ? .green.opacity(0.12) : .orange.opacity(0.12))
                                            .clipShape(Capsule())
                                            .foregroundStyle(patient.status == "active" ? .green : .orange)
                                    }
                                }

                                Spacer()
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            } header: {
                Text("Family Members")
            }
            
            Section {
                Button {
                    showingAddMember = true
                } label: {
                    HStack {
                        Image(systemName: "person.badge.plus")
                        Text("Add Family Member")
                    }
                    .foregroundStyle(.green)
                }
            } footer: {
                Text("Adding a family member allows you to manage their medications and schedule.")
            }
        }
        .navigationTitle("Family Members")
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

struct CareProfileMenu: View {
    @EnvironmentObject var settings: AppSettings
    var onSelectionChanged: () -> Void

    @State private var patients: [FamilySettingsView.PatientProfile] = []
    @State private var isLoading = false

    private var supabase: SupabaseManager { .shared }

    var body: some View {
        Menu {
            Button {
                selectSelf()
            } label: {
                Label("My profile", systemImage: settings.activePatientID == nil ? "checkmark.circle.fill" : "person.circle")
            }

            if isLoading {
                Label("Loading family…", systemImage: "hourglass")
            } else if patients.isEmpty {
                Label("No family members", systemImage: "person.2.slash")
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
            HStack(spacing: 5) {
                Image(systemName: settings.activePatientID == nil ? "person.2.circle.fill" : "person.crop.circle.badge.checkmark")
                if settings.activePatientID != nil {
                    Text(settings.activeCareDisplayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(.green)
        }
        .task { await loadPatients() }
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
    @State var patient: FamilySettingsView.PatientProfile
    var onUpdate: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    @State private var isTransferring = false
    @State private var newCaregiverEmail = ""
    @State private var statusMessage: String?
    @State private var isSaving = false
    @State private var showRemoveConfirmation = false

    private var supabase: SupabaseManager { .shared }

    var body: some View {
        List {
            Section {
                Toggle("Can add medications", isOn: $patient.canPatientAddMeds)
                    .onChange(of: patient.canPatientAddMeds) { _, _ in Task { await savePermissions() } }
                
                Toggle("Can manage calendar", isOn: $patient.canPatientManageCalendar)
                    .onChange(of: patient.canPatientManageCalendar) { _, _ in Task { await savePermissions() } }
            } header: {
                Text("Patient Permissions")
            }

            Section {
                Toggle("Medication Reminders", isOn: $patient.notifyPatientMeds)
                    .onChange(of: patient.notifyPatientMeds) { _, _ in Task { await savePermissions() } }
                
                Toggle("Appointment Reminders", isOn: $patient.notifyPatientAppointments)
                    .onChange(of: patient.notifyPatientAppointments) { _, _ in Task { await savePermissions() } }
            } header: {
                Text("Patient Notifications")
            }

            Section {
                if isTransferring {
                    TextField("New Caregiver Email", text: $newCaregiverEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.none)
                    
                    Button("Confirm Transfer") {
                        Task { await performTransfer() }
                    }
                    .bold()
                    .foregroundStyle(.red)
                    .disabled(newCaregiverEmail.isEmpty || isSaving)
                    
                    Button("Cancel") {
                        isTransferring = false
                        newCaregiverEmail = ""
                    }
                    .foregroundStyle(.secondary)
                } else {
                    Button("Transfer Patient to Another User") {
                        isTransferring = true
                    }
                    .foregroundStyle(.orange)
                }
            } header: {
                Text("Transfer Care")
            } footer: {
                Text("Transferring will move \(patient.firstName) to a new caregiver. You will lose access immediately.")
            }

            Section {
                Button(role: .destructive) {
                    showRemoveConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "person.fill.xmark")
                        Text("Remove Family Member")
                    }
                }
                .disabled(isSaving)
            } header: {
                Text("Remove Access")
            } footer: {
                Text("Removing \(patient.firstName) will stop showing their medications, appointments, and settings in your family list.")
            }
            
            if let msg = statusMessage {
                Section {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(msg.contains("Success") ? .green : .red)
                }
            }
        }
        .navigationTitle("\(patient.firstName)'s Settings")
        .disabled(isSaving)
        .alert("Remove \(patient.firstName)?", isPresented: $showRemoveConfirmation) {
            Button("Remove", role: .destructive) {
                Task { await removeFamilyMember() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You will no longer be able to manage this family member from your caregiver account.")
        }
        .overlay {
            if isSaving {
                ProgressView().controlSize(.large)
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
            statusMessage = "Failed to update: \(error.localizedDescription)"
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
            statusMessage = "Success! Patient transferred."
            // Context cleanup if needed
            if SupabaseManager.shared.activePatientID == pid {
                settings.stopActingAsPatient()
            }
            onUpdate()
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            dismiss()
        } catch {
            print("⚠️ transferPatient failed for \(pidString):", error)
            statusMessage = "Transfer failed: \(error.localizedDescription)"
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
            statusMessage = "Remove failed: \(error.localizedDescription)"
        }
    }

}

struct AddFamilyMemberView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var settings: AppSettings
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var dob = Date()
    @State private var allergies: [String] = []
    @State private var conditions: [String] = []
    
    // Initial Settings
    @State private var canAddMeds = true
    @State private var canManageCalendar = true
    @State private var notifyMeds = true
    @State private var notifyApps = true

    @State private var generatedCode: String?
    @State private var isSaving = false
    @State private var errorText: String?
    
    var onSave: (String) -> Void

    private var supabase: SupabaseManager { .shared }
    
    var body: some View {
        NavigationStack {
            Form {
                if let code = generatedCode {
                    Section {
                        VStack(spacing: 16) {
                            Text("Profile Created!")
                                .font(.headline)
                            
                            Text("Share this code with \(firstName):")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Text(formatCode(code))
                                .font(.system(size: 42, weight: .bold, design: .monospaced))
                                .tracking(8)
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            
                            Text("This code expires in 72 hours.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Button("Copy Code") {
                                UIPasteboard.general.string = code
                            }
                            .buttonStyle(.bordered)
                            .tint(.green)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                } else {
                    Section {
                        TextField("First Name", text: $firstName)
                        TextField("Last Name", text: $lastName)
                        DatePicker("Date of Birth", selection: $dob, in: ...Date(), displayedComponents: .date)
                    } header: {
                        Text("Patient Information")
                    }
                    
                    Section {
                        MultiSelectorView(
                            title: "Allergies",
                            presets: ["Peanuts", "Milk", "Eggs", "Tree Nuts", "Soy", "Wheat", "Fish", "Shellfish", "Penicillin", "Aspirin", "Ibuprofen", "Latex"],
                            selectedItems: $allergies
                        )
                        .padding(.vertical, 4)
                        
                        MultiSelectorView(
                            title: "Chronic Conditions",
                            presets: ["Diabetes", "Hypertension", "Asthma", "Arthritis", "CKD", "COPD", "Heart Disease", "Anxiety", "Depression"],
                            selectedItems: $conditions
                        )
                        .padding(.vertical, 4)
                    } header: {
                        Text("Medical Details")
                    }
                    
                    Section {
                        Toggle("Can add medications", isOn: $canAddMeds)
                        Toggle("Can manage calendar", isOn: $canManageCalendar)
                        Toggle("Medication Reminders", isOn: $notifyMeds)
                        Toggle("Appointment Reminders", isOn: $notifyApps)
                    } header: {
                        Text("Initial Permissions")
                    } footer: {
                        Text("These settings can be changed later in the patient's settings.")
                    }
                    
                    if let err = errorText {
                        Section {
                            Text(err)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("Add Family Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                if generatedCode == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Generate Code") {
                            Task { await generateCode() }
                        }
                        .disabled(firstName.isEmpty || lastName.isEmpty || isSaving)
                    }
                }
            }
        }
    }
    
    private func generateCode() async {
        guard supabase.client.auth.currentSession?.user.id != nil else {
            await MainActor.run {
                errorText = "You must be signed in with a caregiver account to create a family member."
            }
            return
        }
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

    private func friendlyErrorMessage(for error: Error) -> String {
        let message = error.localizedDescription.lowercased()
        if message.contains("non-2xx status code: 404") || message.contains("function") && message.contains("not found") {
            return "The family-member backend function is not deployed yet."
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
