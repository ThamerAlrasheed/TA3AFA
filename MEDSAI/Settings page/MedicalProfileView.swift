import SwiftUI

// MARK: - Medical Profile Hub

struct MedicalProfileView: View {
    let patientId: String?
    let patientName: String

    @EnvironmentObject var settings: AppSettings

    @State private var allergies: [Allergy] = []
    @State private var conditions: [Condition] = []
    @State private var isLoading = false
    @State private var showAddAllergy = false
    @State private var showAddCondition = false

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

    private var navTitle: String {
        switch settings.role {
        case .patient:
            return "Your Medical Profile"
        case .caregiver:
            if let name = settings.activePatientName { return "\(name)'s Profile" }
            return "My Medical Profile"
        default:
            return "Medical Profile"
        }
    }

    var body: some View {
        profileList
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: profileContextKey) { await loadProfile() }
        .refreshable { await loadProfile() }
        .tint(Color.istsehGreen)
        .sheet(isPresented: $showAddAllergy) {
            NavigationStack {
                AllergyDetailView(
                    allergy: Allergy(id: "", name: ""),
                    patientId: requestPatientId,
                    onSave: { showAddAllergy = false; Task { await loadProfile() } }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAddAllergy = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddCondition) {
            NavigationStack {
                ConditionDetailView(
                    condition: Condition(id: "", name: ""),
                    patientId: requestPatientId,
                    onSave: { showAddCondition = false; Task { await loadProfile() } }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAddCondition = false }
                    }
                }
            }
        }
        .overlay {
            if isLoading && allergies.isEmpty && conditions.isEmpty {
                ProgressView("Loading…")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    // MARK: - Profile List

    private var profileList: some View {
        List {
            // ── Allergies ──────────────────────────────────────────────────
            Section {
                if allergies.isEmpty && !isLoading {
                    ProfileEmptyRow(icon: "allergens", message: "No allergies recorded")
                } else {
                    ForEach(allergies) { allergy in
                        NavigationLink {
                            AllergyDetailView(
                                allergy: allergy,
                                patientId: requestPatientId,
                                onSave: { Task { await loadProfile() } }
                            )
                        } label: {
                            AllergyRow(allergy: allergy)
                        }
                    }
                }
                Button {
                    showAddAllergy = true
                } label: {
                    Label("Add Allergy", systemImage: "plus.circle.fill")
                }
            } header: {
                Label("Allergies", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            // ── Chronic Conditions ─────────────────────────────────────────
            Section {
                if conditions.isEmpty && !isLoading {
                    ProfileEmptyRow(icon: "heart.text.clipboard", message: "No chronic conditions recorded")
                } else {
                    ForEach(conditions) { condition in
                        NavigationLink {
                            ConditionDetailView(
                                condition: condition,
                                patientId: requestPatientId,
                                onSave: { Task { await loadProfile() } }
                            )
                        } label: {
                            ConditionRow(condition: condition)
                        }
                    }
                }
                Button {
                    showAddCondition = true
                } label: {
                    Label("Add Condition", systemImage: "plus.circle.fill")
                }
            } header: {
                Label("Chronic Conditions", systemImage: "heart.text.clipboard.fill")
                    .foregroundStyle(Color.istsehGreen)
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Load

    private func loadProfile() async {
        isLoading = true
        do {
            async let a = DrugInfo.listAllergies(patientId: requestPatientId)
            async let c = DrugInfo.listConditions(patientId: requestPatientId)
            let (al, co) = try await (a, c)
            await MainActor.run {
                self.allergies = al
                self.conditions = co
                self.isLoading = false
            }
        } catch {
            await MainActor.run { self.isLoading = false }
        }
    }
}

// MARK: - Row Views

private struct AllergyRow: View {
    let allergy: Allergy
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(allergy.name).font(.body)
                Spacer()
                SeverityBadge(severity: allergy.severity)
            }
            if let reaction = allergy.reaction, !reaction.isEmpty {
                Text(reaction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ConditionRow: View {
    let condition: Condition
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(condition.name).font(.body)
                Spacer()
                StatusBadge(status: condition.status)
            }
            if let notes = condition.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ProfileEmptyRow: View {
    let icon: String
    let message: String
    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 10)
            Spacer()
        }
    }
}

// MARK: - Severity & Status Badges

struct SeverityBadge: View {
    let severity: String
    var body: some View {
        Text(displayLabel.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .foregroundStyle(badgeColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    private var displayLabel: String {
        switch severity.lowercased() {
        case "mild": return "Mild"
        case "moderate": return "Moderate"
        case "severe": return "Severe"
        default: return "Unknown"
        }
    }
    private var badgeColor: Color {
        switch severity.lowercased() {
        case "severe": return .red
        case "moderate": return .orange
        case "mild": return Color.istsehGreen
        default: return Color(.systemGray)
        }
    }
}

struct StatusBadge: View {
    let status: String
    var body: some View {
        Text(status.capitalized.uppercased())
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .foregroundStyle(badgeColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    private var badgeColor: Color {
        switch status.lowercased() {
        case "active": return Color.istsehGreen
        case "inactive": return Color(.systemGray)
        case "resolved": return Color.istsehGreen
        default: return Color(.systemGray)
        }
    }
}

// MARK: - Allergy Detail View (Picker-first)

struct AllergyDetailView: View {
    let patientId: String?
    let onSave: () -> Void

    @State private var searchText = ""
    @State private var selectedName: String
    @State private var severity: String
    @State private var reaction: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var isPicking: Bool

    private let allergyId: String
    private var isNew: Bool { allergyId.isEmpty || allergyId.count < 10 }
    private var canSave: Bool {
        !selectedName.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    @Environment(\.dismiss) private var dismiss

    init(allergy: Allergy, patientId: String?, onSave: @escaping () -> Void) {
        self.allergyId = allergy.id
        self.patientId = patientId
        self.onSave = onSave
        _selectedName = State(initialValue: allergy.name)
        _severity = State(initialValue: allergy.severity.isEmpty ? "unknown" : allergy.severity)
        _reaction = State(initialValue: allergy.reaction ?? "")
        _notes = State(initialValue: allergy.notes ?? "")
        _isPicking = State(initialValue: allergy.id.isEmpty || allergy.id.count < 10)
    }

    var body: some View {
        if isPicking {
            pickerBody
        } else {
            formBody
        }
    }

    // MARK: - Picker

    private var pickerBody: some View {
        List {
            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                Section("Custom") {
                    Button {
                        selectedName = searchText.trimmingCharacters(in: .whitespaces)
                        searchText = ""
                        isPicking = false
                    } label: {
                        Label(
                            "Use \"\(searchText.trimmingCharacters(in: .whitespaces))\"",
                            systemImage: "plus.circle"
                        )
                    }
                }
            }

            ForEach(AllergyCatalog.groupedFiltered(by: searchText), id: \.category) { group in
                Section(group.category) {
                    ForEach(group.items) { item in
                        Button {
                            selectedName = item.displayName
                            isPicking = false
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.displayName)
                                    .foregroundStyle(.primary)
                                if !item.aliases.isEmpty {
                                    Text(item.aliases.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search allergy or medicine"
        )
        .navigationTitle(isNew ? "Add Allergy" : "Change Allergy")
        .navigationBarTitleDisplayMode(.large)
        .tint(Color.istsehGreen)
    }

    // MARK: - Form

    private var formBody: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            selectedName.trimmingCharacters(in: .whitespaces).isEmpty
                                ? "No allergy selected"
                                : selectedName
                        )
                        .font(.headline)
                        if let item = AllergyCatalog.item(named: selectedName) {
                            Text(item.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Change") { isPicking = true }
                        .font(.subheadline)
                        .foregroundStyle(Color.istsehGreen)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Allergy")
            }

            Section {
                Picker("Severity", selection: $severity) {
                    Text("Unknown").tag("unknown")
                    Text("Mild").tag("mild")
                    Text("Moderate").tag("moderate")
                    Text("Severe").tag("severe")
                }
            } header: {
                Text("Severity")
            }

            Section {
                TextField("Reaction (e.g. Rash, hives)", text: $reaction)
                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Notes (optional)")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $notes).frame(minHeight: 60)
                }
            } header: {
                Text("Details")
            }

            if !isNew {
                Section {
                    Button("Archive Allergy", role: .destructive) {
                        Task { await deactivate() }
                    }
                }
            }
        }
        .navigationTitle(isNew ? "Add Allergy" : "Edit Allergy")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.istsehGreen)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Actions

    private func save() async {
        isSaving = true
        let name = selectedName.trimmingCharacters(in: .whitespaces)
        let updated = Allergy(
            id: allergyId,
            name: name,
            severity: severity,
            reaction: reaction.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : reaction.trimmingCharacters(in: .whitespaces),
            notes: notes.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : notes.trimmingCharacters(in: .whitespaces),
            is_active: true
        )
        do {
            try await DrugInfo.saveAllergy(patientId: patientId, allergy: updated)
            onSave()
            dismiss()
        } catch {
            print("❌ Save allergy:", error)
        }
        isSaving = false
    }

    private func deactivate() async {
        do {
            try await DrugInfo.deactivateAllergy(patientId: patientId, id: allergyId)
            onSave()
            dismiss()
        } catch {
            print("❌ Deactivate allergy:", error)
        }
    }
}

// MARK: - Condition Detail View (Picker-first)

struct ConditionDetailView: View {
    let patientId: String?
    let onSave: () -> Void

    @State private var searchText = ""
    @State private var selectedName: String
    @State private var status: String
    @State private var notes: String
    @State private var isSaving = false
    @State private var isPicking: Bool

    private let conditionId: String
    private var isNew: Bool { conditionId.isEmpty || conditionId.count < 10 }
    private var canSave: Bool {
        !selectedName.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    @Environment(\.dismiss) private var dismiss

    init(condition: Condition, patientId: String?, onSave: @escaping () -> Void) {
        self.conditionId = condition.id
        self.patientId = patientId
        self.onSave = onSave
        _selectedName = State(initialValue: condition.name)
        _status = State(initialValue: condition.status.isEmpty ? "active" : condition.status)
        _notes = State(initialValue: condition.notes ?? "")
        _isPicking = State(initialValue: condition.id.isEmpty || condition.id.count < 10)
    }

    var body: some View {
        if isPicking {
            pickerBody
        } else {
            formBody
        }
    }

    // MARK: - Picker

    private var pickerBody: some View {
        List {
            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                Section("Custom") {
                    Button {
                        selectedName = searchText.trimmingCharacters(in: .whitespaces)
                        searchText = ""
                        isPicking = false
                    } label: {
                        Label(
                            "Use \"\(searchText.trimmingCharacters(in: .whitespaces))\"",
                            systemImage: "plus.circle"
                        )
                    }
                }
            }

            ForEach(ConditionCatalog.groupedFiltered(by: searchText), id: \.category) { group in
                Section(group.category) {
                    ForEach(group.items) { item in
                        Button {
                            selectedName = item.displayName
                            isPicking = false
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.displayName)
                                    .foregroundStyle(.primary)
                                if !item.aliases.isEmpty {
                                    Text(item.aliases.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search condition or disease"
        )
        .navigationTitle(isNew ? "Add Condition" : "Change Condition")
        .navigationBarTitleDisplayMode(.large)
        .tint(Color.istsehGreen)
    }

    // MARK: - Form

    private var formBody: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "heart.text.clipboard.fill")
                        .foregroundStyle(Color.istsehGreen)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(
                            selectedName.trimmingCharacters(in: .whitespaces).isEmpty
                                ? "No condition selected"
                                : selectedName
                        )
                        .font(.headline)
                        if let item = ConditionCatalog.item(named: selectedName) {
                            Text(item.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Change") { isPicking = true }
                        .font(.subheadline)
                        .foregroundStyle(Color.istsehGreen)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Condition")
            }

            Section {
                Picker("Status", selection: $status) {
                    Text("Active").tag("active")
                    Text("Inactive").tag("inactive")
                    Text("Resolved").tag("resolved")
                    Text("Unknown").tag("unknown")
                }
            } header: {
                Text("Status")
            }

            Section {
                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("Notes (optional)")
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $notes).frame(minHeight: 60)
                }
            } header: {
                Text("Details")
            }

            if !isNew {
                Section {
                    Button("Archive Condition", role: .destructive) {
                        Task { await deactivate() }
                    }
                }
            }
        }
        .navigationTitle(isNew ? "Add Condition" : "Edit Condition")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color.istsehGreen)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Save") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Actions

    private func save() async {
        isSaving = true
        let name = selectedName.trimmingCharacters(in: .whitespaces)
        let updated = Condition(
            id: conditionId,
            name: name,
            status: status,
            notes: notes.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : notes.trimmingCharacters(in: .whitespaces),
            is_active: true
        )
        do {
            try await DrugInfo.saveCondition(patientId: patientId, condition: updated)
            onSave()
            dismiss()
        } catch {
            print("❌ Save condition:", error)
        }
        isSaving = false
    }

    private func deactivate() async {
        do {
            try await DrugInfo.deactivateCondition(patientId: patientId, id: conditionId)
            onSave()
            dismiss()
        } catch {
            print("❌ Deactivate condition:", error)
        }
    }
}
