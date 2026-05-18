import SwiftUI

struct MedScanConfirmationView: View {
    let image: UIImage
    let scanResult: ScanResult
    var onConfirmed: (DrugPayload) -> Void
    var onCancel: () -> Void

    @State private var selectedCandidate: DrugCandidate?
    @State private var manualName: String = ""
    @State private var manualStrength: String = ""
    @State private var manualDosageForm: String = ""
    @State private var isEditing = false
    @State private var isFetchingIntel = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) var dismiss

    init(image: UIImage, scanResult: ScanResult, onConfirmed: @escaping (DrugPayload) -> Void, onCancel: @escaping () -> Void) {
        self.image = image
        self.scanResult = scanResult
        self.onConfirmed = onConfirmed
        self.onCancel = onCancel
        
        // Initialize with top candidate
        let top = scanResult.candidates.first
        _selectedCandidate = State(initialValue: top)
        _manualName = State(initialValue: top?.name ?? "")
        _manualStrength = State(initialValue: top?.strength.flatMap(MedicationStrengthFormatter.displayableStrength) ?? "")
        _manualDosageForm = State(initialValue: top?.dosage_form ?? "")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Scanned Image Preview
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 200)
                    .cornerRadius(12)
                    .padding(.horizontal)

                if isEditing {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Edit Details").font(.headline)
                        TextField("Medication Name", text: $manualName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Strength (e.g. 200mg)", text: $manualStrength)
                            .textFieldStyle(.roundedBorder)
                        TextField("Dosage Form (e.g. Tablet)", text: $manualDosageForm)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Done Editing") {
                            isEditing = false
                        }
                        .padding(.top, 4)
                    }
                    .padding()
                    .background(Color.istsehCard)
                    .cornerRadius(12)
                    .padding(.horizontal)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(scanResult.candidates.count > 1 ? "Select Medication" : "Identified Medication")
                                .font(.headline)
                            Spacer()
                            Button("Edit") {
                                isEditing = true
                            }
                        }

                        ForEach(scanResult.candidates) { candidate in
                            candidateRow(candidate)
                        }
                    }
                    .padding()
                    .background(Color.istsehCard)
                    .cornerRadius(12)
                    .padding(.horizontal)
                }

                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }

                Spacer()

                Button(action: confirmAndFetch) {
                    HStack {
                        if isFetchingIntel {
                            ProgressView().tint(.white)
                        } else {
                            Text("Confirm & Continue")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.istsehGreen)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .bold()
                }
                .disabled(isFetchingIntel || (manualName.isEmpty && selectedCandidate == nil))
                .padding()
            }
            .navigationTitle("Confirm Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
            }
        }
    }

    private func candidateRow(_ candidate: DrugCandidate) -> some View {
        Button {
            selectedCandidate = candidate
            manualName = candidate.name
            manualStrength = candidate.strength.flatMap(MedicationStrengthFormatter.displayableStrength) ?? ""
            manualDosageForm = candidate.dosage_form ?? ""
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(candidate.name).bold()
                    if let strength = candidate.strength.flatMap(MedicationStrengthFormatter.displayableStrength) {
                        Text(strength).font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                if selectedCandidate?.id == candidate.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.istsehGreen)
                }
                Text("\(Int(candidate.confidence * 100))%")
                    .font(.caption2)
                    .padding(4)
                    .background(Color.istsehGreen.opacity(0.1))
                    .cornerRadius(4)
            }
            .padding(10)
            .background(selectedCandidate?.id == candidate.id ? Color.istsehGreen.opacity(0.05) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private func confirmAndFetch() {
        isFetchingIntel = true
        errorMessage = nil
        
        let finalName = manualName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        Task {
            do {
                // Now we fetch the full clinical safety data from drug-intel
                let fetchedPayload = try await DrugInfo.fetchDetails(name: finalName, lang: "English")
                let payload = fetchedPayload.normalizedForPatientDisplay(fallbackTitle: finalName)
                
                await MainActor.run {
                    isFetchingIntel = false
                    onConfirmed(payload)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isFetchingIntel = false
                    errorMessage = "Failed to fetch medical details. Please check the name."
                }
            }
        }
    }
}
