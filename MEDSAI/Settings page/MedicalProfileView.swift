import SwiftUI

struct MedicalProfileView: View {
    let patientId: String?
    let patientName: String

    @EnvironmentObject var settings: AppSettings

    @State private var selectedAllergies: [String] = []
    @State private var selectedConditions: [String] = []
    @State private var originalAllergies: [Allergy] = []
    @State private var originalConditions: [Condition] = []
    @State private var pendingCustomAllergy = ""
    @State private var pendingCustomCondition = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedMessage: String?
    #if DEBUG
    @State private var debugSaveTrace: [String] = []
    #endif

    private var requestPatientId: String? {
        if settings.role == .caregiver {
            return settings.activePatientID
        }
        if settings.role == .patient {
            return nil
        }
        return patientId
    }

    private var profileContextKey: String {
        "\(settings.role.rawValue):\(requestPatientId ?? "self")"
    }

    private var hasChanges: Bool {
        Set(selectedAllergies.map(normalize)) != Set(originalAllergies.map { normalize($0.name) })
        || Set(selectedConditions.map(normalize)) != Set(originalConditions.map { normalize($0.name) })
    }

    var body: some View {
        ZStack {
            Color.istsehPageBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    header

                    AllergySelectionSection(selectedItems: $selectedAllergies, pendingCustomText: $pendingCustomAllergy)

                    ConditionSelectionSection(selectedItems: $selectedConditions, pendingCustomText: $pendingCustomCondition)

                    if let savedMessage {
                        Text(savedMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.istsehGreen)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 18)
            }
            .refreshable { await loadProfile() }
            .avoidsTabBar()

            if isLoading && selectedAllergies.isEmpty && selectedConditions.isEmpty {
                ISTSEHLoadingView(message: LoadingMessage.profile.text, style: .fullScreen)
            }
        }
        .safeAreaInset(edge: .bottom) {
            saveBar
        }
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
        .navigationTitle(MedicalProfileText.medicalProfile)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: profileContextKey) { await loadProfile() }
        .alert(MedicalProfileText.medicalProfile, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(SettingsL10n.text("OK", "حسنًا"), role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var saveBar: some View {
        if hasChanges || hasPendingCustomText {
            VStack(spacing: 8) {
                if hasPendingCustomText {
                    Text(MedicalProfileText.pendingCustomSaveWarning)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                ISTSEHPrimaryButton(
                    title: isSaving ? MedicalProfileText.customSaving : MedicalProfileText.saveChanges,
                    systemImage: "checkmark.circle.fill",
                    isDisabled: isSaving
                ) {
                    Task { await saveChanges() }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 92)
            .background(.ultraThinMaterial)
        }
    }

    private var isArabic: Bool {
        UserDefaults.standard.string(forKey: "appearance.language") == "ar"
    }

    private var header: some View {
        ISTSEHCard {
            HStack(alignment: .top, spacing: 14) {
                if isArabic {
                    headerText
                    ISTSEHIconBadge(systemName: "heart.text.clipboard.fill")
                } else {
                    ISTSEHIconBadge(systemName: "heart.text.clipboard.fill")
                    headerText
                }
            }
        }
    }

    private var headerText: some View {
        VStack(alignment: isArabic ? .trailing : .leading, spacing: 6) {
            Text(MedicalProfileText.medicalProfile)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(isArabic ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: isArabic ? .trailing : .leading)
            Text(patientName.isEmpty ? MedicalProfileText.selectAllThatApply : patientName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(isArabic ? .trailing : .leading)
                .frame(maxWidth: .infinity, alignment: isArabic ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: isArabic ? .trailing : .leading)
    }

    private func loadProfile() async {
        isLoading = true
        do {
            async let allergies = DrugInfo.listAllergies(patientId: requestPatientId)
            async let conditions = DrugInfo.listConditions(patientId: requestPatientId)
            let loaded = try await (allergies, conditions)
            await MainActor.run {
                originalAllergies = loaded.0
                originalConditions = loaded.1
                selectedAllergies = loaded.0.map(\.name)
                selectedConditions = loaded.1.map(\.name)
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func saveChanges() async {
        applyPendingCustomItems()
        guard hasChanges else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            resetDebugSaveTrace()
            appendDebugSaveTrace("save started context=\(String(describing: SupabaseManager.shared.resolveActiveCareContext())) requestPatientId=\(requestPatientId ?? "nil") activePatientID=\(settings.activePatientID ?? "nil") careCodeActive=\(SupabaseManager.shared.isPatientMode) allergiesSelected=\(selectedAllergies.count) conditionsSelected=\(selectedConditions.count)")
            try await reconcileAllergies()
            try await reconcileConditions()
            await loadProfile()
            await MainActor.run {
                savedMessage = MedicalProfileText.saved
            }
        } catch {
            appendDebugSaveTrace("save failed error=\(sanitize(error))")
            await MainActor.run {
                errorMessage = MedicalProfileText.saveFailed
            }
        }
    }

    private var hasPendingCustomText: Bool {
        !pendingCustomAllergy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !pendingCustomCondition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private func applyPendingCustomItems() {
        addPending(&pendingCustomAllergy, to: &selectedAllergies)
        addPending(&pendingCustomCondition, to: &selectedConditions)
        savedMessage = nil
    }

    private func addPending(_ pending: inout String, to selected: inout [String]) {
        let trimmed = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !selected.contains(where: { normalize($0) == normalize(trimmed) }) {
            selected.append(trimmed)
        }
        pending = ""
    }

    private func reconcileAllergies() async throws {
        let selected = keyedSelected(selectedAllergies)
        let original = keyedOriginal(originalAllergies)

        for key in Set(original.keys).subtracting(selected.keys) {
            if let item = original[key] {
                appendDebugSaveTrace("deactivate_allergy started id=\(item.id) payloadKeys=[action,patient_id,id]")
                try await DrugInfo.deactivateAllergy(patientId: requestPatientId, id: item.id)
                appendDebugSaveTrace("deactivate_allergy success id=\(item.id)")
            }
        }

        for key in Set(selected.keys).subtracting(original.keys) {
            if let name = selected[key] {
                appendDebugSaveTrace("save_allergy started payloadKeys=[action,patient_id,allergy(name,severity,reaction,notes,is_active)] severity=unknown")
                try await DrugInfo.saveAllergy(patientId: requestPatientId, allergy: Allergy(name: name))
                appendDebugSaveTrace("save_allergy success")
            }
        }
    }

    private func reconcileConditions() async throws {
        let selected = keyedSelected(selectedConditions)
        let original = keyedOriginal(originalConditions)

        for key in Set(original.keys).subtracting(selected.keys) {
            if let item = original[key] {
                appendDebugSaveTrace("deactivate_condition started id=\(item.id) payloadKeys=[action,patient_id,id]")
                try await DrugInfo.deactivateCondition(patientId: requestPatientId, id: item.id)
                appendDebugSaveTrace("deactivate_condition success id=\(item.id)")
            }
        }

        for key in Set(selected.keys).subtracting(original.keys) {
            if let name = selected[key] {
                appendDebugSaveTrace("save_condition started payloadKeys=[action,patient_id,condition(name,status,diagnosed_at,notes,is_active)] status=active")
                try await DrugInfo.saveCondition(patientId: requestPatientId, condition: Condition(name: name))
                appendDebugSaveTrace("save_condition success")
            }
        }
    }

    private func keyedSelected(_ values: [String]) -> [String: String] {
        values.reduce(into: [:]) { result, value in
            let key = normalize(value)
            guard !key.isEmpty else { return }
            result[key] = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func keyedOriginal<T: Identifiable>(_ values: [T]) -> [String: T] where T.ID == String {
        values.reduce(into: [:]) { result, value in
            if let allergy = value as? Allergy {
                result[normalize(allergy.name)] = value
            } else if let condition = value as? Condition {
                result[normalize(condition.name)] = value
            }
        }
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func sanitize(_ error: Error) -> String {
        String(describing: error)
            .replacingOccurrences(of: SupabaseManager.shared.supabaseKey, with: "[redacted-key]")
    }

    private func resetDebugSaveTrace() {
        #if DEBUG
        debugSaveTrace = []
        #endif
    }

    private func appendDebugSaveTrace(_ message: String) {
        #if DEBUG
        let line = "DEBUG_MEDICAL_PROFILE \(message)"
        debugSaveTrace.append(line)
        print(line)
        #endif
    }
}

private extension MedicalProfileText {
    static var saveChanges: String { isArabic ? "حفظ التغييرات" : "Save changes" }
    static var customSaving: String { isArabic ? "جاري الحفظ…" : "Saving…" }
    static var saved: String { isArabic ? "تم حفظ التغييرات." : "Changes saved." }
    static var saveFailed: String {
        isArabic
            ? "تعذر حفظ الملف الطبي. يرجى المحاولة مرة أخرى."
            : "Couldn’t save your medical profile. Please try again."
    }
    static var pendingCustomSaveWarning: String {
        isArabic
            ? "سيتم إضافة النص المخصص عند حفظ التغييرات."
            : "Custom text will be added when you save changes."
    }
}
