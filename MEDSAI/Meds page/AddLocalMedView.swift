import SwiftUI
import PhotosUI

struct AddLocalMedView: View {
    var initialPayload: DrugPayload? = nil
    var onSave: (LocalMed) -> Void
    @Environment(\.dismiss) private var dismiss

    // Form
    @State private var name: String
    @State private var dosageAmount: Double?
    @State private var dosageUnit: DosageUnit
    @State private var freq: Int
    @State private var start = Date()
    @State private var end: Date
    @State private var notes: String

    // GPT
    @State private var isLoadingInfo = false
    @State private var infoChips: [String]
    @State private var parsedFoodRule: FoodRule
    @State private var parsedMinInterval: Int?
    @State private var catalogId: String? // Captured UUID

    // Strengths from GPT
    @State private var dosageOptions: [String]
    
    init(initialPayload: DrugPayload? = nil, onSave: @escaping (LocalMed) -> Void) {
        self.initialPayload = initialPayload
        self.onSave = onSave
        
        let p = initialPayload
        _name = State(initialValue: p?.title ?? "")
        _dosageAmount = State(initialValue: nil) // will be picked from options
        _dosageUnit = State(initialValue: .mg)
        _freq = State(initialValue: 2)
        _end = State(initialValue: Calendar.current.date(byAdding: .day, value: 14, to: Date())!)
        _notes = State(initialValue: "")
        
        // GPT results pre-fill
        _infoChips = State(initialValue: p?.indications ?? [])
        _dosageOptions = State(initialValue: p?.strengths ?? [])
        
        let food: FoodRule = {
            switch p?.foodRule {
            case "afterFood": return .afterFood
            case "beforeFood": return .beforeFood
            default: return .none
            }
        }()
        _parsedFoodRule = State(initialValue: food)
        _parsedMinInterval = State(initialValue: p?.minIntervalHours)
        _catalogId = State(initialValue: p?.id?.uuidString)
    }
    @State private var selectedDosageOption: String? = nil

    // debounce
    @State private var fetchTask: Task<Void, Never>? = nil
    @State private var lastFetchedName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)

                        TextField("Name", text: $name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .onChange(of: name) { _, new in scheduleLookup(for: new) }

                        if !name.isEmpty {
                            Button {
                                name = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )

                    if !dosageOptions.isEmpty {
                        DosePicker(options: dosageOptions, selection: $selectedDosageOption)
                    } else {
                        DoseManual(amount: $dosageAmount, unit: $dosageUnit)
                    }

                    Stepper("\(freq)x per day", value: $freq, in: 1...6)

                    if isLoadingInfo {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Getting drug info…").foregroundStyle(.secondary)
                        }
                    } else if !infoChips.isEmpty {
                        WrapChips(items: infoChips)
                    }
                }

                Section("Dates") {
                    DatePicker("Start", selection: $start, displayedComponents: .date)
                    DatePicker("End", selection: $end, displayedComponents: .date)
                }

                Section("Notes") { TextField("Optional notes", text: $notes, axis: .vertical) }
            }
            .navigationTitle("Add medication")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let strengthOK = (!dosageOptions.isEmpty && (selectedDosageOption ?? dosageOptions.first) != nil)
            || (dosageOptions.isEmpty && dosageAmount != nil)
        return hasName && strengthOK && start <= end
    }

    private func save() {
        let dosageString: String = {
            if !dosageOptions.isEmpty {
                return (selectedDosageOption ?? dosageOptions.first!) // safe by canSave
            } else {
                let amount = dosageAmount ?? 0
                return formatDosage(amount: amount, unit: dosageUnit)
            }
        }()

        let med = LocalMed(
            name: name.trimmingCharacters(in: .whitespaces),
            dosage: dosageString,
            frequencyPerDay: freq,
            startDate: start,
            endDate: end,
            foodRule: parsedFoodRule,
            notes: notes.isEmpty ? nil : notes,
            ingredients: nil,
            minIntervalHours: parsedMinInterval,
            catalogId: catalogId
        )

        onSave(med)
        dismiss()
    }

    // MARK: - GPT lookup helpers
    private func scheduleLookup(for input: String) {
        fetchTask?.cancel()
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else {
            infoChips = []; parsedFoodRule = .none; parsedMinInterval = nil
            dosageOptions = []; selectedDosageOption = nil
            return
        }
        if trimmed.caseInsensitiveCompare(lastFetchedName) == .orderedSame { return }
        fetchTask = Task { [trimmed] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            await loadInfo(for: trimmed)
        }
    }

    @MainActor
    private func loadInfo(for medName: String) async {
        isLoadingInfo = true
        defer { isLoadingInfo = false }
        lastFetchedName = medName
        dosageOptions = []; selectedDosageOption = nil

        do {
            let payload = try await DrugInfo.fetchDetails(name: medName)
            
            // Ensure it's in the global catalog (so we have a UUID to link to)
            let entry = try? await MedCatalogRepo.shared.upsert(from: payload, searchedName: medName)
            let finalPayload = entry?.payload ?? payload

            // Strengths
            dosageOptions = finalPayload.strengths
            selectedDosageOption = finalPayload.strengths.first

            // Food rule + min interval
            switch (finalPayload.foodRule ?? "none").lowercased() {
            case "afterfood", "after_food": parsedFoodRule = .afterFood
            case "beforefood", "before_food": parsedFoodRule = .beforeFood
            default: parsedFoodRule = .none
            }
            parsedMinInterval = finalPayload.minIntervalHours
            catalogId = finalPayload.id?.uuidString

            // Chips
            var chips: [String] = []
            if parsedFoodRule == .afterFood { chips.append("Take after food") }
            if parsedFoodRule == .beforeFood { chips.append("Take before food") }
            if let ih = parsedMinInterval { chips.append("~every \(ih)h") }
            infoChips = chips

        } catch {
            infoChips = ["Couldn’t fetch info"]
        }
    }
}

// Subviews used by AddLocalMedView — keeps type-checking simple
private struct DosePicker: View {
    let options: [String]
    @Binding var selection: String?

    var body: some View {
        let sel = Binding<String>(
            get: { selection ?? options.first ?? "" },
            set: { selection = $0 }
        )
        return Picker("Dose", selection: sel) {
            ForEach(options, id: \.self) { opt in
                Text(opt).tag(opt)
            }
        }
    }
}

private struct DoseManual: View {
    @Binding var amount: Double?
    @Binding var unit: DosageUnit
    var body: some View {
        HStack {
            NumericTextField(value: $amount, placeholder: "Amount", allowsDecimal: true, maxFractionDigits: 2)
                .frame(minWidth: 90)
            Picker("Unit", selection: $unit) {
                ForEach(DosageUnit.allCases) { u in Text(u.label).tag(u) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }
}
