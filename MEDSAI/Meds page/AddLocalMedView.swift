import SwiftUI
import PhotosUI

struct AddLocalMedView: View {
    @EnvironmentObject var medsRepo: UserMedsRepo
    @EnvironmentObject var settings: AppSettings

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

    // Safety Engine
    @State private var safetyWarnings: [SafetyWarning] = []
    @State private var safetySourceTrace: [String] = []
    @State private var isCheckingSafety = false
    @State private var showSafetyWarnings = false
    @State private var offlineSafetyMessage: String? = nil
    @State private var capturedIngredients: [String] = []
    @State private var capturedRxCUI: String? = nil

    // Schedule Parsing
    @State private var instructionText: String = ""
    @State private var isParsingSchedule = false
    @State private var parsedSchedulePendingConfirmation = false
    @State private var isManualSchedule = false
    @State private var parsedScheduleConfidence: Double = 0
    @State private var parsedTimesOfDay: [String] = []
    @State private var dosageTimes: [Date] = []
    @State private var asNeeded: Bool = false
    @State private var validationError: String? = nil

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
        
        let food = FoodRule.fromStorage(p?.foodRule)
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
                            .onChange(of: name) { _, _ in updateSuggestedTimes() }

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
                            .onChange(of: selectedDosageOption) { _, _ in 
                                isManualSchedule = true
                                parsedSchedulePendingConfirmation = false
                                validationError = nil
                                updateSuggestedTimes()
                            }
                    } else {
                        DoseManual(amount: $dosageAmount, unit: $dosageUnit)
                            .onChange(of: dosageAmount) { _, _ in 
                                isManualSchedule = true
                                parsedSchedulePendingConfirmation = false
                                validationError = nil
                                updateSuggestedTimes()
                            }
                    }

                    Stepper("\(freq)x per day", value: $freq, in: 1...6)
                        .onChange(of: freq) { _, _ in 
                            isManualSchedule = true
                            parsedSchedulePendingConfirmation = false
                            validationError = nil
                            updateSuggestedTimes()
                        }
                    
                    Toggle("Take only when needed", isOn: $asNeeded)
                        .onChange(of: asNeeded) { _, _ in 
                            parsedSchedulePendingConfirmation = false
                            validationError = nil
                            updateSuggestedTimes()
                        }
                    
                    if asNeeded {
                        Text("No fixed reminders will be created unless you add them manually.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Picker("Food Timing", selection: $parsedFoodRule) {
                        Text("No food rule").tag(FoodRule.none)
                        Text("Before food").tag(FoodRule.beforeFood)
                        Text("With food").tag(FoodRule.withFood)
                        Text("After food").tag(FoodRule.afterFood)
                    }
                    .onChange(of: parsedFoodRule) { _, _ in
                        parsedSchedulePendingConfirmation = false
                        validationError = nil
                        updateSuggestedTimes()
                    }

                    if isLoadingInfo {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Getting drug info…").foregroundStyle(.secondary)
                        }
                    } else if !infoChips.isEmpty {
                        WrapChips(items: infoChips)
                    }
                }

                Section {
                    TextEditor(text: $instructionText)
                        .frame(minHeight: 80)
                        .overlay(alignment: .topLeading) {
                            if instructionText.isEmpty {
                                Text("Optional: paste instructions from label or doctor")
                                    .foregroundColor(.secondary)
                                    .padding(.top, 8)
                                    .padding(.leading, 4)
                                    .allowsHitTesting(false)
                            }
                        }
                    
                    Button(action: suggestSchedule) {
                        HStack {
                            if isParsingSchedule {
                                ProgressView().tint(Color.istsehGreen)
                            } else {
                                Image(systemName: "sparkles")
                                Text("Suggest Schedule")
                            }
                        }
                    }
                    .disabled(isParsingSchedule)
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("You can enter instructions in English or Arabic.")
                }

                if parsedSchedulePendingConfirmation {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Image(systemName: "info.circle.fill").foregroundColor(Color.istsehGreen)
                                Text("Suggested Schedule").bold()
                            }
                            
                            Text("Please confirm or edit these suggested reminder times:")
                                .font(.caption).foregroundColor(.secondary)
                            
                            ForEach(0..<dosageTimes.count, id: \.self) { index in
                                DatePicker("Dose \(index + 1)", selection: $dosageTimes[index], displayedComponents: .hourAndMinute)
                                    .onChange(of: dosageTimes[index]) { _, _ in 
                                        isManualSchedule = true
                                        parsedSchedulePendingConfirmation = false
                                        validationError = nil
                                    }
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("• \(freq)x per day")
                                if let amount = dosageAmount {
                                    Text("• \(amount.formatted()) \(dosageUnit.label)")
                                }
                                Text("• \(foodRuleSummary(parsedFoodRule))")

                                if !parsedTimesOfDay.isEmpty {
                                    Text("• Times: \(parsedTimesOfDay.joined(separator: ", "))")
                                }

                                if !instructionText.isEmpty {
                                    Text("• Confidence: \(Int(parsedScheduleConfidence * 100))%")
                                        .font(.caption)
                                        .foregroundColor(parsedScheduleConfidence < 0.85 ? .orange : .secondary)
                                } else {
                                    Text("• Suggested from your routine")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .font(.subheadline)

                            Button(action: { parsedSchedulePendingConfirmation = false; validationError = nil }) {
                                Text("Confirm Times")
                                    .bold()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(Color.istsehGreen)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                        .padding(.vertical, 8)
                    }
                }

                Section("Dates") {
                    DatePicker("Start", selection: $start, displayedComponents: .date)
                    DatePicker("End", selection: $end, displayedComponents: .date)
                }

                Section("Notes") { TextField("Optional notes", text: $notes, axis: .vertical) }
                
                if let error = validationError {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.subheadline)
                            .bold()
                    }
                }
            }
            .navigationTitle("Add medication")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { 
                        if parsedSchedulePendingConfirmation {
                            validationError = "Please confirm or edit the suggested schedule before saving."
                        } else {
                            runSafetyCheck()
                        }
                    }.disabled(!canSave || isCheckingSafety)
                }
            }
            .sheet(isPresented: $showSafetyWarnings) {
                SafetyWarningView(
                    warnings: safetyWarnings,
                    offlineMessage: offlineSafetyMessage,
                    sourceTrace: safetySourceTrace,
                    onConfirm: {
                        // TODO: Log safety_warning_ignored if backend support exists
                        save()
                    },
                    onCancel: {
                        showSafetyWarnings = false
                    }
                )
            }
            .overlay {
                if isCheckingSafety {
                    ZStack {
                        Color.black.opacity(0.2).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Checking safety...").font(.subheadline).bold()
                        }
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                    }
                }
            }
        }
    }

    private var canSave: Bool {
        let hasName = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let strengthOK = (!dosageOptions.isEmpty && (selectedDosageOption ?? dosageOptions.first) != nil)
            || (dosageOptions.isEmpty && (dosageAmount ?? 0) > 0)
        return hasName && strengthOK && start <= end
    }

    private func suggestSchedule() {
        let text = instructionText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        isParsingSchedule = true
        parsedSchedulePendingConfirmation = false
        validationError = nil
        
        if text.isEmpty {
            // Local suggestion based on current selections
            Task {
                await MainActor.run {
                    isParsingSchedule = false
                    updateSuggestedTimes()
                    parsedSchedulePendingConfirmation = true
                }
            }
            return
        }
        
        // Detect language: simple regex for Arabic characters
        let isArabic = text.range(of: "\\p{Arabic}", options: .regularExpression) != nil
        let lang = isArabic ? "Arabic" : "English"
        
        Task {
            do {
                let result = try await DrugInfo.parseSchedule(text: text, lang: lang)
                
                await MainActor.run {
                    isParsingSchedule = false
                    isManualSchedule = false
                    
                    // Pre-fill fields
                    if let f = result.frequency_per_day {
                        self.freq = f
                    }
                    
                    self.asNeeded = result.as_needed
                    
                    let parsedRule = FoodRule.fromStorage(result.food_rule)
                    if parsedRule != .none {
                        self.parsedFoodRule = parsedRule
                    }
                    
                    if let amount = result.dose_amount {
                        self.dosageAmount = amount
                    }
                    
                    if let unit = result.dose_unit {
                        // Attempt to match unit
                        if let matched = DosageUnit.allCases.first(where: { $0.label.lowercased().contains(unit.lowercased()) }) {
                            self.dosageUnit = matched
                        }
                    }
                    
                    parsedScheduleConfidence = result.confidence
                    parsedTimesOfDay = result.times_of_day
                    
                    updateSuggestedTimes()
                    parsedSchedulePendingConfirmation = true
                    // Haptic feedback
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } catch {
                await MainActor.run {
                    isParsingSchedule = false
                }
            }
        }
    }

    private func updateSuggestedTimes() {
        if asNeeded {
            self.dosageTimes = []
            return
        }
        
        let tempMed = Medication(
            id: UUID().uuidString,
            name: name,
            dosage: "",
            frequencyPerDay: freq,
            startDate: start,
            endDate: end,
            foodRule: parsedFoodRule,
            notes: nil,
            ingredients: capturedIngredients,
            minIntervalHours: parsedMinInterval,
            rxcui: capturedRxCUI,
            dosageTimes: nil,
            asNeeded: asNeeded
        )
        
        let times = Scheduler.preferredTimes(for: tempMed, on: start.startOfDay, settings: settings)
        self.dosageTimes = times
    }

    private func runSafetyCheck() {
        validationError = nil
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        isCheckingSafety = true
        offlineSafetyMessage = nil
        safetyWarnings = []
        safetySourceTrace = []

        Task {
            do {
                await medsRepo.fetchMeds()

                // 1. Prepare Inputs
                let pendingMedID = "pending-\(UUID().uuidString)"
                let currentMed = SafetyMedicationInput(
                    id: pendingMedID,
                    name: trimmedName,
                    rxcui: capturedRxCUI,
                    ingredients: capturedIngredients
                )
                
                let activeMeds = medsRepo.meds.filter { !$0.isArchived }
                let existingMeds = activeMeds.map { SafetyMedicationInput(
                    id: $0.id,
                    name: $0.name,
                    rxcui: $0.rxcui,
                    ingredients: $0.ingredients ?? []
                )}

                // 2. Call Server Safety Engine
                let text = instructionText.trimmingCharacters(in: .whitespacesAndNewlines)
                let isArabic = text.range(of: "\\p{Arabic}", options: .regularExpression) != nil
                let lang = isArabic ? "Arabic" : "English"
                
                let response = try await DrugInfo.checkSafety(
                    patientId: SupabaseManager.shared.currentUserID?.uuidString.lowercased(),
                    deviceToken: SupabaseManager.shared.patientDeviceToken,
                    medications: [currentMed] + existingMeds,
                    lang: lang
                )

                await MainActor.run {
                    isCheckingSafety = false
                    let relevantWarnings = response.warnings.filter {
                        isWarning(
                            $0,
                            involvingPendingID: pendingMedID,
                            medName: trimmedName,
                            medIngredients: capturedIngredients
                        )
                    }

                    if relevantWarnings.isEmpty {
                        save()
                    } else {
                        safetyWarnings = relevantWarnings
                        safetySourceTrace = response.source_trace
                        showSafetyWarnings = true
                    }
                }
            } catch {
                // 3. Offline Fallback: InteractionEngine
                let activeMeds = medsRepo.meds.filter { !$0.isArchived }
                let localResult = InteractionEngine.checkConflicts(
                    meds: [(trimmedName, capturedIngredients)] + activeMeds.map { ($0.name, $0.ingredients ?? []) }
                )
                
                await MainActor.run {
                    isCheckingSafety = false
                    let relevantConflicts = localResult.conflicts.filter { conflict in
                        conflict.medA.caseInsensitiveCompare(trimmedName) == .orderedSame ||
                        conflict.medB.caseInsensitiveCompare(trimmedName) == .orderedSame
                    }

                    if relevantConflicts.isEmpty {
                        save()
                    } else {
                        // Map local conflicts to SafetyWarning models for the UI
                        safetyWarnings = relevantConflicts.map { conflict in
                            SafetyWarning(
                                type: .drugInteraction,
                                severity: .major,
                                meds: [conflict.medA, conflict.medB],
                                ingredients: [],
                                description: conflict.explanation,
                                management: "Consult your doctor for advice.",
                                source: "local_engine",
                                is_deterministic: true,
                                requires_acknowledgement: true,
                                can_continue: true
                            )
                        }
                        safetySourceTrace = ["local_engine"]
                        offlineSafetyMessage = localResult.warningMessage
                        showSafetyWarnings = true
                    }
                }
            }
        }
    }

    private func isWarning(
        _ warning: SafetyWarning,
        involvingPendingID pendingID: String,
        medName: String,
        medIngredients: [String]
    ) -> Bool {
        // Most precise check: backend explicitly tagged this pending med.
        if warning.affected_medication_ids?.contains(pendingID) == true {
            return true
        }

        // For allergy conflicts and any contraindicated/blocking warning, do NOT rely
        // solely on affected_medication_ids — also check by name and canonical ingredients.
        // This handles cases where the pending ID is not in the list (e.g., empty array
        // returned by backend) or canonical alias matching is needed.
        let isBlockingOrAllergy = warning.type == .allergyConflict
            || warning.severity == .contraindicated
            || !warning.can_continue

        let newMedTerms = Set(canonicalSafetyTerms([medName] + medIngredients))
        let warningTerms = Set(canonicalSafetyTerms(warning.meds + warning.ingredients))

        if isBlockingOrAllergy {
            if !newMedTerms.isDisjoint(with: warningTerms) { return true }

            let normalizedMedName = normalizeSafetyTerm(medName)
            if warning.meds.map(normalizeSafetyTerm).contains(where: {
                !$0.isEmpty && ($0 == normalizedMedName || $0.contains(normalizedMedName) || normalizedMedName.contains($0))
            }) { return true }
        }

        // For non-blocking warnings, only show if affected_medication_ids is unset/empty
        // (so we fall back to canonical term matching) or matched above.
        if let affectedIDs = warning.affected_medication_ids, !affectedIDs.isEmpty {
            // Already checked contains(pendingID) above — if we're here it didn't match.
            return false
        }

        if !newMedTerms.isDisjoint(with: warningTerms) { return true }

        return warning.meds
            .map(normalizeSafetyTerm)
            .contains { warningMed in
                let normalizedMedName = normalizeSafetyTerm(medName)
                return warningMed == normalizedMedName ||
                    (!warningMed.isEmpty && (warningMed.contains(normalizedMedName) || normalizedMedName.contains(warningMed)))
            }
    }

    private func normalizeSafetyTerm(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func canonicalSafetyTerms(_ values: [String]) -> [String] {
        var terms = Set<String>()

        for value in values {
            let normalized = normalizeSafetyTerm(value)
            guard !normalized.isEmpty else { continue }
            terms.insert(normalized)

            if let canonical = canonicalIngredient(for: normalized) {
                terms.insert(canonical)
            }
        }

        return Array(terms)
    }

    private func canonicalIngredient(for normalized: String) -> String? {
        let aliasMap: [String: String] = [
            "ibuprofen": "ibuprofen",
            "advil": "ibuprofen",
            "motrin": "ibuprofen",
            "brufen": "ibuprofen",
            "nurofen": "ibuprofen",
            "nsaid": "ibuprofen",
            "nsaids": "ibuprofen",
            "nonsteroidal anti inflammatory": "ibuprofen",
            "nonsteroidal anti inflammatory drug": "ibuprofen",
            "non steroidal anti inflammatory": "ibuprofen",
            "acetaminophen": "acetaminophen",
            "paracetamol": "acetaminophen",
            "tylenol": "acetaminophen",
            "panadol": "acetaminophen",
            "amoxicillin": "amoxicillin",
            "amoxil": "amoxicillin",
            "augmentin": "amoxicillin"
        ]

        for (alias, canonical) in aliasMap {
            if normalized == alias || normalized.contains(alias) {
                return canonical
            }
        }

        return nil
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

        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm:ss"
        let timesStrings = dosageTimes.map { timeFmt.string(from: $0) }

        let med = LocalMed(
            id: initialPayload?.id?.uuidString ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespaces),
            dosage: dosageString,
            frequencyPerDay: freq,
            startDate: start,
            endDate: end,
            foodRule: parsedFoodRule,
            dosageTimes: timesStrings,
            notes: notes.isEmpty ? nil : notes,
            ingredients: capturedIngredients.isEmpty ? nil : capturedIngredients,
            rxcui: capturedRxCUI,
            minIntervalHours: parsedMinInterval,
            isArchived: false,
            asNeeded: asNeeded,
            isManualSchedule: isManualSchedule,
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
            parsedFoodRule = FoodRule.fromStorage(finalPayload.foodRule)
            parsedMinInterval = finalPayload.minIntervalHours
            catalogId = finalPayload.id?.uuidString
            capturedIngredients = finalPayload.ingredients
            capturedRxCUI = finalPayload.rxcui
            isManualSchedule = false

            // Chips
            var chips: [String] = []
            if parsedFoodRule == .afterFood { chips.append("Take after food") }
            if parsedFoodRule == .beforeFood { chips.append("Take before food") }
            if parsedFoodRule == .withFood { chips.append("Take with food") }
            if let ih = parsedMinInterval { chips.append("~every \(ih)h") }
            infoChips = chips

        } catch {
            infoChips = ["Couldn’t fetch info"]
        }
    }

    private func foodRuleSummary(_ rule: FoodRule) -> String {
        switch rule {
        case .none: return "No food rule"
        case .beforeFood: return "Take before food"
        case .withFood: return "Take with food"
        case .afterFood: return "Take after food"
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
