import SwiftUI

struct MedicalProfileView: View {
    let patientId: String?
    let patientName: String
    
    @State private var allergies: [Allergy] = []
    @State private var conditions: [Condition] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    @State private var showAddAllergy = false
    @State private var showAddCondition = false
    
    var body: some View {
        List {
            Section(header: Text("Allergies")) {
                if allergies.isEmpty && !isLoading {
                    Text("No known allergies reported.")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                        .padding(.vertical, 4)
                } else {
                    ForEach(allergies) { allergy in
                        NavigationLink(destination: AllergyDetailView(allergy: allergy, patientId: patientId, onSave: { Task { await loadProfile() } })) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(allergy.name).bold()
                                    Spacer()
                                    SeverityBadge(severity: allergy.severity)
                                }
                                if let reaction = allergy.reaction, !reaction.isEmpty {
                                    Text("Reaction: \(reaction)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Button(action: { showAddAllergy = true }) {
                    Label("Add Allergy", systemImage: "plus.circle")
                }
            }
            
            Section(header: Text("Medical Conditions")) {
                if conditions.isEmpty && !isLoading {
                    Text("No chronic conditions reported.")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                        .padding(.vertical, 4)
                } else {
                    ForEach(conditions) { condition in
                        NavigationLink(destination: ConditionDetailView(condition: condition, patientId: patientId, onSave: { Task { await loadProfile() } })) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(condition.name).bold()
                                    Spacer()
                                    StatusBadge(status: condition.status)
                                }
                                if let date = condition.diagnosed_at {
                                    Text("Diagnosed: \(formatDate(date))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Button(action: { showAddCondition = true }) {
                    Label("Add Condition", systemImage: "plus.circle")
                }
            }
        }
        .navigationTitle("\(patientName)'s Profile")
        .task {
            await loadProfile()
        }
        .refreshable {
            await loadProfile()
        }
        .sheet(isPresented: $showAddAllergy) {
            NavigationStack {
                AllergyDetailView(allergy: Allergy(name: ""), patientId: patientId, onSave: {
                    showAddAllergy = false
                    Task { await loadProfile() }
                })
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAddAllergy = false }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddCondition) {
            NavigationStack {
                ConditionDetailView(condition: Condition(name: ""), patientId: patientId, onSave: {
                    showAddCondition = false
                    Task { await loadProfile() }
                })
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showAddCondition = false }
                    }
                }
            }
        }
        .overlay {
            if isLoading && allergies.isEmpty && conditions.isEmpty {
                ProgressView("Loading profile...")
            }
        }
    }
    
    private func loadProfile() async {
        isLoading = true
        errorMessage = nil
        do {
            let (a, c) = try await (
                DrugInfo.listAllergies(patientId: patientId),
                DrugInfo.listConditions(patientId: patientId)
            )
            await MainActor.run {
                self.allergies = a
                self.conditions = c
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    private func formatDate(_ dateStr: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        let display = DateFormatter()
        display.dateStyle = .medium
        return display.string(from: date)
    }
}

struct SeverityBadge: View {
    let severity: String
    var body: some View {
        Text(severity.uppercased())
            .font(.caption2)
            .bold()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
    var color: Color {
        switch severity.lowercased() {
        case "severe": return .red
        case "moderate": return .orange
        case "mild": return .blue
        default: return .gray
        }
    }
}

struct StatusBadge: View {
    let status: String
    var body: some View {
        Text(status.uppercased())
            .font(.caption2)
            .bold()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundColor(color)
            .cornerRadius(4)
    }
    var color: Color {
        switch status.lowercased() {
        case "active": return .green
        case "inactive": return .gray
        case "resolved": return .blue
        default: return .gray
        }
    }
}

// MARK: - Detail Views

struct AllergyDetailView: View {
    @State var allergy: Allergy
    let patientId: String?
    let onSave: () -> Void
    
    @State private var isSaving = false
    @Environment(\.dismiss) var dismiss
    
    let severities = ["mild", "moderate", "severe", "unknown"]
    
    var body: some View {
        Form {
            Section("Basic Info") {
                TextField("Allergy Name (e.g. Penicillin)", text: Binding(
                    get: { allergy.name },
                    set: { allergy = Allergy(id: allergy.id, name: $0, severity: allergy.severity, reaction: allergy.reaction, notes: allergy.notes, is_active: allergy.is_active) }
                ))
                
                Picker("Severity", selection: Binding(
                    get: { allergy.severity },
                    set: { allergy = Allergy(id: allergy.id, name: allergy.name, severity: $0, reaction: allergy.reaction, notes: allergy.notes, is_active: allergy.is_active) }
                )) {
                    ForEach(severities, id: \.self) { s in Text(s.capitalized).tag(s) }
                }
            }
            
            Section("Details") {
                TextField("Reaction (e.g. Rash)", text: Binding(
                    get: { allergy.reaction ?? "" },
                    set: { allergy = Allergy(id: allergy.id, name: allergy.name, severity: allergy.severity, reaction: $0.isEmpty ? nil : $0, notes: allergy.notes, is_active: allergy.is_active) }
                ))
                TextEditor(text: Binding(
                    get: { allergy.notes ?? "" },
                    set: { allergy = Allergy(id: allergy.id, name: allergy.name, severity: allergy.severity, reaction: allergy.reaction, notes: $0.isEmpty ? nil : $0, is_active: allergy.is_active) }
                ))
                .frame(minHeight: 60)
                .overlay(alignment: .topLeading) {
                    if (allergy.notes ?? "").isEmpty {
                        Text("Additional notes").foregroundColor(.secondary).padding(.top, 8).padding(.leading, 4).allowsHitTesting(false)
                    }
                }
            }
            
            if !isNew {
                Section {
                    Button("Remove Allergy", role: .destructive) {
                        Task { await deactivate() }
                    }
                }
            }
        }
        .navigationTitle(isNew ? "Add Allergy" : "Edit Allergy")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(allergy.name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
    }
    
    private var isNew: Bool { allergy.id.count < 10 }
    
    private func save() async {
        isSaving = true
        do {
            try await DrugInfo.saveAllergy(patientId: patientId, allergy: allergy)
            onSave()
            dismiss()
        } catch {
            print("Save failed")
        }
        isSaving = false
    }
    
    private func deactivate() async {
        do {
            try await DrugInfo.deactivateAllergy(patientId: patientId, id: allergy.id)
            onSave()
            dismiss()
        } catch {
            print("Deactivate failed")
        }
    }
}

struct ConditionDetailView: View {
    @State var condition: Condition
    let patientId: String?
    let onSave: () -> Void
    
    @State private var isSaving = false
    @Environment(\.dismiss) var dismiss
    
    let statuses = ["active", "inactive", "resolved", "unknown"]
    
    var body: some View {
        Form {
            Section("Basic Info") {
                TextField("Condition Name (e.g. Diabetes)", text: Binding(
                    get: { condition.name },
                    set: { condition = Condition(id: condition.id, name: $0, status: condition.status, diagnosed_at: condition.diagnosed_at, notes: condition.notes, is_active: condition.is_active) }
                ))
                
                Picker("Status", selection: Binding(
                    get: { condition.status },
                    set: { condition = Condition(id: condition.id, name: condition.name, status: $0, diagnosed_at: condition.diagnosed_at, notes: condition.notes, is_active: condition.is_active) }
                )) {
                    ForEach(statuses, id: \.self) { s in Text(s.capitalized).tag(s) }
                }
            }
            
            Section("Details") {
                TextEditor(text: Binding(
                    get: { condition.notes ?? "" },
                    set: { condition = Condition(id: condition.id, name: condition.name, status: condition.status, diagnosed_at: condition.diagnosed_at, notes: $0.isEmpty ? nil : $0, is_active: condition.is_active) }
                ))
                .frame(minHeight: 60)
                .overlay(alignment: .topLeading) {
                    if (condition.notes ?? "").isEmpty {
                        Text("Additional notes").foregroundColor(.secondary).padding(.top, 8).padding(.leading, 4).allowsHitTesting(false)
                    }
                }
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
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(condition.name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
            }
        }
    }
    
    private var isNew: Bool { condition.id.count < 10 }
    
    private func save() async {
        isSaving = true
        do {
            try await DrugInfo.saveCondition(patientId: patientId, condition: condition)
            onSave()
            dismiss()
        } catch {
            print("Save failed")
        }
        isSaving = false
    }
    
    private func deactivate() async {
        do {
            try await DrugInfo.deactivateCondition(patientId: patientId, id: condition.id)
            onSave()
            dismiss()
        } catch {
            print("Deactivate failed")
        }
    }
}
