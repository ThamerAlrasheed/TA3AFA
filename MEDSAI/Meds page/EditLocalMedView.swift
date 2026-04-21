import SwiftUI

struct EditLocalMedView: View {
    var med: LocalMed
    var onSave: (LocalMed) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var working: LocalMed
    @State private var doseAmount: Double? = nil
    @State private var doseUnit: DosageUnit = .mg

    @State private var infoChips: [String] = []

    init(med: LocalMed, onSave: @escaping (LocalMed) -> Void) {
        self.med = med
        self.onSave = onSave
        _working = State(initialValue: med)
    }

    var body: some View {
        Form {
            Section("Basics") {
                TextField("Name", text: $working.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()

                DoseManual(amount: $doseAmount, unit: $doseUnit)

                Stepper("\(working.frequencyPerDay)x per day", value: $working.frequencyPerDay, in: 1...6)

                if !infoChips.isEmpty { WrapChips(items: infoChips) }
            }

            Section("Dates") {
                DatePicker("Start", selection: $working.startDate, displayedComponents: .date)
                DatePicker("End", selection: $working.endDate, displayedComponents: .date)
            }

            Section("Notes") {
                TextField("Notes",
                          text: Binding(
                            get: { working.notes ?? "" },
                            set: { working.notes = $0.isEmpty ? nil : $0 }),
                          axis: .vertical)
            }
        }
        .onAppear {
            let (amt, unit) = parseDosageToDouble(working.dosage)
            doseAmount = amt; doseUnit = unit
            var chips: [String] = []
            if working.foodRule == .afterFood { chips.append("Take after food") }
            if working.foodRule == .beforeFood { chips.append("Take before food") }
            if let ih = working.minIntervalHours { chips.append("~every \(ih)h") }
            infoChips = chips
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    let amt = doseAmount ?? 0
                    working.dosage = formatDosage(amount: amt, unit: doseUnit)
                    onSave(working)
                    dismiss()
                }
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
