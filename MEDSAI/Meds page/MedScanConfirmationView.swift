import SwiftUI

struct MedScanConfirmationView: View {
    let previewImage: UIImage
    let fallbackImageDataProvider: () -> Data?
    var onConfirmed: (DrugPayload, MedicationScanSaveMetadata?) -> Void
    var onCancel: () -> Void

    @State private var decision: MedicationScanDecision
    @State private var selectedCandidateIndex: Int?
    @State private var manualBrandName: String
    @State private var manualGenericName: String
    @State private var manualStrength: String
    @State private var manualDosageForm: String
    @State private var manualManufacturer: String
    @State private var isEditing = false
    @State private var isFetchingIntel = false
    @State private var isRunningFallback = false
    @State private var isRematching = false
    @State private var hasUnmatchedEdits = false
    @State private var fallbackAttempted = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(
        previewImage: UIImage,
        fallbackImageDataProvider: @escaping () -> Data?,
        decision: MedicationScanDecision,
        onConfirmed: @escaping (DrugPayload, MedicationScanSaveMetadata?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.previewImage = previewImage
        self.fallbackImageDataProvider = fallbackImageDataProvider
        self.onConfirmed = onConfirmed
        self.onCancel = onCancel
        _decision = State(initialValue: decision)
        let initialIndex = Self.initialSelectedCandidateIndex(decision.candidates)
        let initialCandidate = initialIndex.flatMap { decision.candidates.indices.contains($0) ? decision.candidates[$0] : nil }
        _selectedCandidateIndex = State(initialValue: initialIndex)
        _manualBrandName = State(initialValue: initialCandidate?.brandName ?? decision.extractedFields.possibleBrandName ?? "")
        _manualGenericName = State(initialValue: initialCandidate?.genericName ?? decision.extractedFields.possibleGenericName ?? "")
        _manualStrength = State(initialValue: initialCandidate?.strength ?? Self.displayStrength(decision.extractedFields))
        _manualDosageForm = State(initialValue: initialCandidate?.dosageForm ?? decision.extractedFields.dosageForm ?? "")
        _manualManufacturer = State(initialValue: initialCandidate?.manufacturer ?? decision.extractedFields.manufacturer ?? "")
    }

    init(
        image: UIImage,
        scanResult: ScanResult,
        onConfirmed: @escaping (DrugPayload) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let decision = Self.legacyDecision(from: scanResult)
        self.init(
            previewImage: image,
            fallbackImageDataProvider: { nil },
            decision: decision,
            onConfirmed: { payload, _ in onConfirmed(payload) },
            onCancel: onCancel
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(uiImage: previewImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 190)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal)

                    warningBanner
                    possibleMedicationCard
                    candidateSection

                    if isEditing {
                        manualEditCard
                    }

                    if shouldShowFallbackButton {
                        fallbackCard
                    }

                    #if DEBUG
                    debugInfoSection
                    #endif

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.istsehDanger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .background(Color.istsehPageBackground.ignoresSafeArea())
            .navigationTitle("Confirm Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                    .disabled(isFetchingIntel || isRunningFallback)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let reason = confirmDisabledReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button(action: confirmMedication) {
                        HStack {
                            if isFetchingIntel {
                                ISTSEHLoadingView(message: "", style: .compact)
                                    .frame(width: 24, height: 24)
                            }
                            Text("Confirm Medication")
                                .bold()
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(canConfirm ? Color.istsehGreen : Color.secondary.opacity(0.45))
                    .disabled(!canConfirm || isFetchingIntel || isRunningFallback || isRematching)

                    Button(action: continueManually) {
                        Label("Continue Manually", systemImage: "square.and.pencil")
                            .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isFetchingIntel || isRunningFallback || isRematching)
                }
                .padding()
                .background(.bar)
            }
        }
    }

    private var warningBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                confidenceBadge
                Spacer()
                Text(scoreDisplay)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Text("Please confirm the medication using the package label. ISTSEH may misread unclear images.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color.istsehCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var confidenceBadge: some View {
        Text(confidenceLabel)
            .font(.caption.weight(.bold))
            .foregroundStyle(confidenceColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(confidenceColor.opacity(0.12), in: Capsule())
    }

    private var possibleMedicationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Possible medication")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button(isEditing ? "Update Matches" : "Edit") {
                    if isEditing {
                        rerunCandidateMatching()
                    } else {
                        isEditing = true
                    }
                }
                    .font(.subheadline.weight(.semibold))
                    .disabled(isRematching)
            }
            Text("Which medication is this?")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            fieldRow("Best name", bestMedicationNameCandidate)
            fieldRow("Generic name", decision.extractedFields.possibleGenericName)
            iconSuggestionRow
            fieldRow("Manufacturer", decision.extractedFields.manufacturer)
            fieldRow("Barcode", decision.extractedFields.barcode)
        }
        .padding()
        .background(Color.istsehCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var candidateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Catalog Candidates")
                .font(.headline)
                .foregroundStyle(.primary)

            if decision.candidates.isEmpty {
                Text("No verified medication match found. Retake the photo or enter the medication name manually.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(decision.candidates.enumerated()), id: \.offset) { index, candidate in
                    candidateCard(candidate, index: index)
                }
                if !decision.candidates.contains(where: { Self.isConfirmableCandidate($0) }) {
                    Text("No verified medication match found. Retake the photo or enter the medication name manually.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    selectedCandidateIndex = nil
                    isEditing = true
                    hasUnmatchedEdits = true
                } label: {
                    Label("None are correct", systemImage: selectedCandidateIndex == nil ? "checkmark.circle.fill" : "circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color.istsehCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var manualEditCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Details").font(.headline)
            TextField("Medication name", text: $manualBrandName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: manualBrandName) { _, _ in markEditedFieldsChanged() }
            TextField("Generic or active ingredient", text: $manualGenericName)
                .textFieldStyle(.roundedBorder)
                .onChange(of: manualGenericName) { _, _ in markEditedFieldsChanged() }
            TextField("Strength (for example 500 mg)", text: $manualStrength)
                .textFieldStyle(.roundedBorder)
                .onChange(of: manualStrength) { _, _ in markEditedFieldsChanged() }
            TextField("Form (tablet, syrup, cream...)", text: $manualDosageForm)
                .textFieldStyle(.roundedBorder)
                .onChange(of: manualDosageForm) { _, _ in markEditedFieldsChanged() }
            TextField("Manufacturer", text: $manualManufacturer)
                .textFieldStyle(.roundedBorder)
                .onChange(of: manualManufacturer) { _, _ in markEditedFieldsChanged() }
            if hasUnmatchedEdits {
                Text("Update matches before confirming so the medication is verified against the catalog.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if isRematching {
                ISTSEHLoadingView(message: "Checking catalog matches", style: .inline)
                    .font(.caption)
            }
        }
        .padding()
        .background(Color.istsehCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var fallbackCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(fallbackAttempted && decision.candidates.isEmpty ? "We still could not identify this medication." : "Need extra help reading the package?")
                .font(.headline)
                .foregroundStyle(.primary)
            if let fallbackReason = decision.fallbackReason {
                Text(fallbackReason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if fallbackAttempted && decision.candidates.isEmpty {
                Text("Retake the photo or enter the medication manually.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button(action: runImageFallback) {
                HStack {
                    if isRunningFallback {
                        ISTSEHLoadingView(message: "", style: .compact)
                            .frame(width: 24, height: 24)
                    }
                    Label("Try AI Image Recognition", systemImage: "sparkles")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.istsehGreen)
            .disabled(isRunningFallback || isFetchingIntel)
        }
        .padding()
        .background(Color.istsehCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var averageOCRConfidence: Double {
        let confidences = decision.ocrResult.lines.compactMap { $0.confidence }
        guard !confidences.isEmpty else { return 0.0 }
        return confidences.reduce(0.0, +) / Double(confidences.count)
    }

    #if DEBUG
    private var debugInfoSection: some View {
        DisclosureGroup("Scan Debug Info") {
            VStack(alignment: .leading, spacing: 10) {
                debugBlock(
                    title: "Image Pipeline Metadata",
                    value: """
                    Original Dimensions: \(Int(decision.originalWidth ?? 0)) x \(Int(decision.originalHeight ?? 0))
                    Preview Dimensions: \(Int(decision.previewWidth ?? 0)) x \(Int(decision.previewHeight ?? 0))
                    OCR Dimensions: \(Int(decision.ocrWidth ?? 0)) x \(Int(decision.ocrHeight ?? 0))
                    Detailed Retry OCR Dimensions: \(decision.ocrRetryUsed ? "\(Int(decision.detailedOcrWidth ?? 0)) x \(Int(decision.detailedOcrHeight ?? 0))" : "Not Used")
                    Fallback Image Byte Size: \(decision.fallbackByteSize.map { "\($0) bytes" } ?? "Not Triggered")
                    OCR Line Count: \(decision.ocrResult.lines.count)
                    Average OCR Confidence: \(String(format: "%.2f", averageOCRConfidence))
                    """
                )
                debugBlock(
                    title: "OCR lines",
                    value: decision.ocrResult.lines.enumerated().map { index, line in
                        let confidence = line.confidence.map { String(format: "%.2f", $0) } ?? "n/a"
                        return "\(index + 1). [\(confidence)] \(line.text)"
                    }.joined(separator: "\n")
                )
                debugBlock(
                    title: "Normalized OCR lines",
                    value: decision.ocrResult.lines.enumerated().map { index, line in
                        "\(index + 1). \(MedicationOCRNormalizer.normalizeLine(line.text))"
                    }.joined(separator: "\n")
                )
                debugBlock(title: "Extracted fields", value: debugJSON(decision.extractedFields))
                debugBlock(title: "Field confidence", value: debugJSON(decision.extractedFields.confidence))
                debugBlock(
                    title: "Candidate scores",
                    value: decision.candidates.map { candidate in
                        "\(candidate.brandName): \(String(format: "%.2f", candidate.matchScore)) | \(candidate.matchReasons.joined(separator: ", "))"
                    }.joined(separator: "\n")
                )
                debugBlock(title: "Fallback reason", value: decision.fallbackReason ?? "none")
            }
            .padding(.top, 8)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .padding()
        .background(Color.istsehCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.istsehCardStroke))
        .padding(.horizontal)
    }

    private func debugBlock(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "none" : value)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func debugJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else {
            return "unavailable"
        }
        return text
    }
    #endif

    private func fieldRow(_ label: String, _ value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text((value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? value : "Not detected") ?? "Not detected")
                .font(.footnote)
                .foregroundStyle(value == nil ? .secondary : .primary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var iconSuggestionRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Suggested icon")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            if let suggestedIconLabel {
                HStack(spacing: 8) {
                    MedicationVisualView(
                        form: detectedIconForm,
                        shapeID: MedicationIconSuggestion.suggestedShapeID(for: detectedIconForm),
                        medicationColorID: "green",
                        backgroundColorID: "softGreen",
                        size: 34
                    )
                    Text(suggestedIconLabel)
                        .font(.footnote)
                        .foregroundStyle(.primary)
                }
            } else {
                Text("Icon can be customized later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private func candidateCard(_ candidate: MedicationScanCandidate, index: Int) -> some View {
        Button {
            selectedCandidateIndex = index
            hasUnmatchedEdits = false
            isEditing = false
            manualBrandName = candidate.brandName
            manualGenericName = candidate.genericName ?? ""
            manualStrength = candidate.strength ?? ""
            manualDosageForm = candidate.dosageForm ?? ""
            manualManufacturer = candidate.manufacturer ?? ""
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selectedCandidateIndex == index ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedCandidateIndex == index ? Color.istsehGreen : .secondary)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(candidate.brandName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let genericName = candidate.genericName, !genericName.isEmpty {
                        Text(genericName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if !candidate.matchReasons.isEmpty {
                Text(candidate.matchReasons.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Color.istsehGreen)
                    }
                    if !Self.isConfirmableCandidate(candidate) {
                        Text("Needs review before confirmation")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Text("\(Int(candidate.matchScore * 100))%")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
            }
            .padding(10)
            .background(selectedCandidateIndex == index ? Color.istsehGreen.opacity(0.08) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var selectedCandidate: MedicationScanCandidate? {
        guard let selectedCandidateIndex,
              decision.candidates.indices.contains(selectedCandidateIndex) else { return nil }
        return decision.candidates[selectedCandidateIndex]
    }

    private var canConfirm: Bool {
        Self.isConfirmableCandidate(selectedCandidate)
            && !hasUnmatchedEdits
            && !isEditing
            && !finalMedicationName.isEmpty
    }

    private var confirmDisabledReason: String? {
        if isEditing || hasUnmatchedEdits {
            return "Update matches before confirming the medication name."
        }
        if selectedCandidate == nil {
            return "No verified medication match found. Retake the photo or enter the medication name manually."
        }
        if !Self.isConfirmableCandidate(selectedCandidate) {
            return "This scan is not reliable enough to confirm yet."
        }
        return nil
    }

    private var finalMedicationName: String {
        (selectedCandidate?.brandName ?? manualBrandName).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var bestMedicationNameCandidate: String? {
        selectedCandidate?.brandName.nilIfEmpty
            ?? decision.topCandidate?.brandName.nilIfEmpty
            ?? decision.extractedFields.possibleBrandName?.nilIfEmpty
            ?? decision.extractedFields.possibleGenericName?.nilIfEmpty
    }

    private var detectedIconForm: String? {
        manualDosageForm.nilIfEmpty
            ?? selectedCandidate?.dosageForm?.nilIfEmpty
            ?? decision.extractedFields.dosageForm?.nilIfEmpty
    }

    private var suggestedIconLabel: String? {
        MedicationIconSuggestion.displayName(for: detectedIconForm)
    }

    private var confidenceLabel: String {
        let score = selectedCandidate?.matchScore ?? decision.topCandidate?.matchScore ?? 0
        if score >= MedicationScanPipeline.highConfidenceCandidateThreshold { return "High confidence" }
        if score >= MedicationScanPipeline.mediumConfidenceCandidateThreshold { return "Medium confidence" }
        if decision.ocrResult.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "No readable text" }
        return "Needs review"
    }

    private var scoreDisplay: String {
        let score = selectedCandidate?.matchScore ?? decision.topCandidate?.matchScore ?? decision.extractedFields.confidence.overall
        guard score > 0 else { return "Needs review" }
        if score < MedicationScanPipeline.mediumConfidenceCandidateThreshold { return "Needs review" }
        return "\(Int(score * 100))%"
    }

    private var confidenceColor: Color {
        let score = selectedCandidate?.matchScore ?? decision.topCandidate?.matchScore ?? 0
        if score >= MedicationScanPipeline.highConfidenceCandidateThreshold { return Color.istsehGreen }
        if score >= MedicationScanPipeline.mediumConfidenceCandidateThreshold { return .orange }
        return .red
    }

    private var shouldShowFallbackButton: Bool {
        decision.requiresFallback || (decision.topCandidate?.matchScore ?? 0) < MedicationScanPipeline.mediumConfidenceCandidateThreshold
    }

    static func isConfirmableCandidate(_ candidate: MedicationScanCandidate?) -> Bool {
        guard let candidate else { return false }
        guard candidate.matchScore >= MedicationScanPipeline.mediumConfidenceCandidateThreshold else { return false }
        guard !RuleBasedMedicationFieldExtractor.isSuspiciousMedicationName(candidate.brandName) else { return false }

        switch candidate.source {
        case "supabase_catalog", "local_db", "gpt_assisted":
            return candidate.medicationId != nil
        case "image_to_drug_fallback":
            return true
        default:
            return candidate.medicationId != nil
        }
    }

    private static func initialSelectedCandidateIndex(_ candidates: [MedicationScanCandidate]) -> Int? {
        candidates.firstIndex(where: isConfirmableCandidate)
    }

    private func runImageFallback() {
        isRunningFallback = true
        errorMessage = nil
        Task {
            do {
                guard let data = fallbackImageDataProvider() else {
                    throw NSError(domain: "MedScanConfirmationView", code: 404, userInfo: [NSLocalizedDescriptionKey: "No fallback image data available"])
                }
                let updated = try await MedicationScanPipeline().processImageFallback(
                    data: data,
                    appendingTo: decision
                )
                await MainActor.run {
                    var finalDecision = updated
                    finalDecision.fallbackByteSize = data.count
                    decision = finalDecision
                    selectedCandidateIndex = Self.initialSelectedCandidateIndex(finalDecision.candidates)
                    if let selectedCandidateIndex,
                       finalDecision.candidates.indices.contains(selectedCandidateIndex) {
                        let selected = finalDecision.candidates[selectedCandidateIndex]
                        manualBrandName = selected.brandName
                        manualGenericName = selected.genericName ?? ""
                        manualStrength = selected.strength ?? ""
                        manualDosageForm = selected.dosageForm ?? ""
                        manualManufacturer = selected.manufacturer ?? ""
                    }
                    fallbackAttempted = true
                    hasUnmatchedEdits = false
                    isRunningFallback = false
                    if finalDecision.candidates.isEmpty {
                        errorMessage = "We still could not identify this medication. Retake the photo or enter it manually."
                    }
                }
            } catch {
                await MainActor.run {
                    isRunningFallback = false
                    fallbackAttempted = true
                    errorMessage = "We still could not identify this medication. Retake the photo or enter it manually."
                }
            }
        }
    }

    private func rerunCandidateMatching() {
        let fields = editedExtractedFields()
        isRematching = true
        errorMessage = nil

        Task {
            do {
                let candidates = try await MedicationCandidateMatcher().findCandidates(for: fields)
                await MainActor.run {
                    decision.extractedFields = fields
                    decision.candidates = candidates
                    decision.selectedCandidate = candidates.first
                    decision.requiresFallback = MedicationScanPipeline.shouldFallback(
                        ocrResult: decision.ocrResult,
                        candidates: candidates
                    )
                    decision.fallbackReason = candidates.isEmpty
                        ? "No catalog candidate matched the edited fields."
                        : ((candidates.first?.matchScore ?? 0) < MedicationScanPipeline.mediumConfidenceCandidateThreshold ? "Top catalog match is below confirmation confidence." : nil)
                    selectedCandidateIndex = Self.initialSelectedCandidateIndex(candidates)
                    if let selectedCandidateIndex,
                       candidates.indices.contains(selectedCandidateIndex) {
                        let selected = candidates[selectedCandidateIndex]
                        manualBrandName = selected.brandName
                        manualGenericName = selected.genericName ?? manualGenericName
                        manualStrength = selected.strength ?? manualStrength
                        manualDosageForm = selected.dosageForm ?? manualDosageForm
                        manualManufacturer = selected.manufacturer ?? manualManufacturer
                    }
                    hasUnmatchedEdits = false
                    isEditing = false
                    isRematching = false
                }
            } catch {
                await MainActor.run {
                    isRematching = false
                    errorMessage = "We could not check the edited fields against the catalog. Continue manually or try again."
                }
            }
        }
    }

    private func markEditedFieldsChanged() {
        guard isEditing else { return }
        hasUnmatchedEdits = true
        selectedCandidateIndex = nil
    }

    private func confirmMedication() {
        guard canConfirm else { return }
        isFetchingIntel = true
        errorMessage = nil
        let candidate = selectedCandidate
        let name = finalMedicationName

        Task {
            do {
                let fetchedPayload = try await DrugInfo.fetchDetails(name: name, lang: "English")
                let normalized = fetchedPayload.normalizedForPatientDisplay(fallbackTitle: name)
                let finalPayload = payloadWithCandidateID(normalized, candidate: candidate)
                let metadata = MedicationScanSaveMetadata.confirmed(
                    source: scanSource(candidate: candidate),
                    confidence: candidate?.matchScore,
                    extractedFields: editedExtractedFields(),
                    candidates: decision.candidates
                )
                await MainActor.run {
                    isFetchingIntel = false
                    onConfirmed(finalPayload, metadata)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isFetchingIntel = false
                    errorMessage = "Failed to fetch verified medication details. Please check the name or edit the fields."
                }
            }
        }
    }

    private func continueManually() {
        let fields = editedExtractedFields()
        let title = manualBrandName.nilIfEmpty ?? fields.possibleBrandName ?? ""
        let payload = DrugPayload(
            title: title,
            strengths: manualStrength.nilIfEmpty.map { [$0] } ?? [],
            dosageForms: manualDosageForm.nilIfEmpty.map { [$0] } ?? [],
            foodRule: nil,
            minIntervalHours: nil,
            ingredients: manualGenericName.nilIfEmpty.map { [$0] } ?? fields.possibleActiveIngredients,
            indications: [],
            howToTake: [],
            commonSideEffects: [],
            importantWarnings: [],
            interactionsToAvoid: [],
            references: nil,
            kbKey: nil,
            rxcui: nil,
            id: nil
        )
        onConfirmed(
            payload,
            .manualFromScan(
                extractedFields: fields,
                candidates: decision.candidates
            )
        )
        dismiss()
    }

    private func payloadWithCandidateID(_ payload: DrugPayload, candidate: MedicationScanCandidate?) -> DrugPayload {
        DrugPayload(
            title: payload.title,
            strengths: payload.strengths.isEmpty && !manualStrength.isEmpty ? [manualStrength] : payload.strengths,
            dosageForms: payload.dosageForms.isEmpty && !manualDosageForm.isEmpty ? [manualDosageForm] : payload.dosageForms,
            foodRule: payload.foodRule,
            minIntervalHours: payload.minIntervalHours,
            ingredients: payload.ingredients.isEmpty && !manualGenericName.isEmpty ? [manualGenericName] : payload.ingredients,
            indications: payload.indications,
            howToTake: payload.howToTake,
            commonSideEffects: payload.commonSideEffects,
            importantWarnings: payload.importantWarnings,
            interactionsToAvoid: payload.interactionsToAvoid,
            references: payload.references,
            kbKey: payload.kbKey,
            rxcui: payload.rxcui,
            id: candidate?.medicationId ?? payload.id
        )
    }

    private func editedExtractedFields() -> MedicationExtractedFields {
        let parsedStrength = RuleBasedMedicationFieldExtractor.extractStrength(from: manualStrength)
        var fields = decision.extractedFields
        fields.possibleBrandName = manualBrandName.nilIfEmpty
        fields.possibleGenericName = manualGenericName.nilIfEmpty
        fields.possibleActiveIngredients = manualGenericName.nilIfEmpty.map { [$0] } ?? fields.possibleActiveIngredients
        fields.strengthValue = parsedStrength.value ?? fields.strengthValue
        fields.strengthUnit = parsedStrength.unit ?? fields.strengthUnit
        fields.dosageForm = manualDosageForm.nilIfEmpty ?? fields.dosageForm
        fields.manufacturer = manualManufacturer.nilIfEmpty ?? fields.manufacturer
        fields.packageQuantity = nil
        fields.rawDirectionsText = []
        fields.rawWarningsText = []
        fields.needsUserConfirmation = true
        return fields
    }

    private func scanSource(candidate: MedicationScanCandidate?) -> String {
        if candidate?.source == "image_to_drug_fallback" { return "image_to_drug_fallback" }
        if candidate?.source == "gpt_assisted" { return "apple_ocr_gpt_resolver" }
        return "apple_ocr"
    }

    private static func displayStrength(_ fields: MedicationExtractedFields) -> String {
        guard let value = fields.strengthValue, let unit = fields.strengthUnit else { return "" }
        let number = value.rounded() == value ? String(Int(value)) : String(value)
        return "\(number) \(unit)"
    }

    private static func legacyDecision(from scanResult: ScanResult) -> MedicationScanDecision {
        let candidates = scanResult.candidates.map {
            MedicationScanCandidate(
                medicationId: nil,
                brandName: $0.name,
                genericName: nil,
                activeIngredients: [],
                strength: $0.strength,
                dosageForm: $0.dosage_form,
                manufacturer: nil,
                matchScore: min(max($0.confidence, 0), 1),
                matchReasons: ["AI image recognition fallback"],
                source: "image_to_drug_fallback",
                requiresConfirmation: true
            )
        }
        let first = candidates.first
        let strength = first?.strength.map { RuleBasedMedicationFieldExtractor.extractStrength(from: $0) }
        return MedicationScanDecision(
            ocrResult: .empty,
            extractedFields: MedicationExtractedFields(
                possibleBrandName: first?.brandName,
                possibleGenericName: nil,
                possibleActiveIngredients: [],
                strengthValue: strength?.value,
                strengthUnit: strength?.unit,
                dosageForm: first?.dosageForm,
                packageQuantity: nil,
                manufacturer: nil,
                barcode: nil,
                languageHints: [],
                rawWarningsText: [],
                rawDirectionsText: [],
                confidence: .low,
                extractionMethod: "image_to_drug_fallback",
                needsUserConfirmation: true
            ),
            candidates: candidates,
            selectedCandidate: first,
            scanSessionId: UUID(),
            requiresFallback: false,
            fallbackReason: nil
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
