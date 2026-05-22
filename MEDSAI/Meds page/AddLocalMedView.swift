import SwiftUI
import PhotosUI

struct AddLocalMedView: View {
    @EnvironmentObject var medsRepo: UserMedsRepo
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var initialPayload: DrugPayload? = nil
    var editingMed: LocalMed? = nil
    var scanMetadata: MedicationScanSaveMetadata? = nil
    var onSave: (LocalMed) -> Void

    @State private var step: WizardStep = .confirm
    @State private var name: String
    @State private var catalogId: String?
    @State private var sourceType: MedicationSourceType
    @State private var capturedIngredients: [String]
    @State private var capturedRxCUI: String?
    @State private var medicationForm: String
    @State private var customFormText: String
    @State private var strengthValue: Double?
    @State private var strengthUnit: String
    @State private var customUnitText: String
    @State private var doseAmount: Double?
    @State private var doseAmountUnit: String
    @State private var doseQuantity: Double?
    @State private var doseUnit: String
    @State private var doseQuantityUnit: String
    @State private var concentrationAmount: Double?
    @State private var concentrationUnit: String
    @State private var route: String
    @State private var applicationArea: String
    @State private var doseDisplay: String
    @State private var foodRuleSource: String
    @State private var doseDetailsSource: String
    @State private var isDoseAutoFilled: Bool
    @State private var doseDetailsConfirmedByUser: Bool
    @State private var scheduleMode: MedicationScheduleMode
    @State private var timesPerDay: Int
    @State private var timesPerWeek: Int
    @State private var selectedWeekdays: Set<Int>
    @State private var intervalDays: Int
    @State private var dosageTimes: [Date]
    @State private var foodRule: FoodRule
    @State private var start: Date
    @State private var end: Date
    @State private var hasEndDate: Bool
    @State private var remindersEnabled: Bool
    @State private var caregiverRemindersEnabled: Bool
    @State private var visualShape: String
    @State private var visualColor: String
    @State private var visualBackgroundColor: String
    @State private var refillReminderEnabled: Bool
    @State private var refillCurrentSupply: Double?
    @State private var refillSupplyUnit: String
    @State private var refillThresholdQuantity: Double?
    @State private var refillNotes: String
    @State private var notes: String
    @State private var validationError: String?
    @State private var infoChips: [String]
    @State private var dosageOptions: [String]
    @State private var selectedDosageOption: String?
    @State private var isLoadingInfo = false
    @State private var fetchTask: Task<Void, Never>?
    @State private var lastFetchedName = ""
    @State private var isManualSchedule = false
    @State private var isCheckingSafety = false
    @State private var showSafetyWarnings = false
    @State private var safetyWarnings: [SafetyWarning] = []
    @State private var safetySourceTrace: [String] = []
    @State private var offlineSafetyMessage: String?
    @State private var parsedMinInterval: Int?
    @State private var identificationState: MedicationIdentificationState
    @State private var isManualDoseEditing: Bool
    @State private var showOptionalDoseFields: Bool

    init(
        initialPayload: DrugPayload? = nil,
        editingMed: LocalMed? = nil,
        scanMetadata: MedicationScanSaveMetadata? = nil,
        onSave: @escaping (LocalMed) -> Void
    ) {
        self.initialPayload = initialPayload
        self.editingMed = editingMed
        self.scanMetadata = scanMetadata
        self.onSave = onSave

        let payload = initialPayload
        let med = editingMed
        let identified = med?.sourceType == .identified || payload?.id != nil
        let initialName = med?.name ?? payload?.title ?? ""
        let initialForm = med?.medicationForm
            ?? MedicationIconSuggestion.normalizedForm(from: payload?.dosageForms.first)
            ?? ""
        let startDate = med?.startDate ?? Date()
        let endDate = med?.endDate ?? Calendar.current.date(byAdding: .day, value: 14, to: Date())!

        _name = State(initialValue: initialName)
        _catalogId = State(initialValue: med?.catalogId ?? payload?.id?.uuidString)
        _sourceType = State(initialValue: identified ? .identified : .manual)
        _capturedIngredients = State(initialValue: med?.ingredients ?? payload?.ingredients ?? [])
        _capturedRxCUI = State(initialValue: med?.rxcui ?? payload?.rxcui)
        _medicationForm = State(initialValue: initialForm)
        _customFormText = State(initialValue: med?.customFormText ?? "")
        _strengthValue = State(initialValue: med?.strengthValue)
        _strengthUnit = State(initialValue: med?.strengthUnit ?? "mg")
        _customUnitText = State(initialValue: med?.customUnitText ?? "")
        _doseAmount = State(initialValue: med?.doseAmount)
        _doseAmountUnit = State(initialValue: med?.doseAmountUnit ?? "mg")
        _doseQuantity = State(initialValue: med?.doseQuantity ?? parseDosageToDouble(med?.dosage ?? "").0)
        _doseUnit = State(initialValue: med?.doseUnit ?? parseDosageToDouble(med?.dosage ?? "").1.label)
        _doseQuantityUnit = State(initialValue: med?.doseQuantityUnit ?? med?.doseUnit ?? "tablets")
        _concentrationAmount = State(initialValue: med?.concentrationAmount)
        _concentrationUnit = State(initialValue: med?.concentrationUnit ?? "mg/mL")
        _route = State(initialValue: med?.route ?? "")
        _applicationArea = State(initialValue: med?.applicationArea ?? "")
        _doseDisplay = State(initialValue: med?.doseDisplay ?? med?.dosage ?? "")
        _foodRuleSource = State(initialValue: med?.foodRuleSource ?? "")
        _doseDetailsSource = State(initialValue: med?.doseDetailsSource ?? "manual")
        _isDoseAutoFilled = State(initialValue: med?.isDoseAutoFilled ?? false)
        _doseDetailsConfirmedByUser = State(initialValue: med?.doseDetailsConfirmedByUser ?? false)
        _scheduleMode = State(initialValue: med?.scheduleMode ?? (med?.asNeeded == true ? .asNeeded : .asNeeded))
        _timesPerDay = State(initialValue: med?.timesPerDay ?? med?.frequencyPerDay ?? 1)
        _timesPerWeek = State(initialValue: med?.timesPerWeek ?? max(med?.selectedWeekdays.count ?? 1, 1))
        _selectedWeekdays = State(initialValue: Set(med?.selectedWeekdays ?? []))
        _intervalDays = State(initialValue: med?.intervalDays ?? 2)
        _dosageTimes = State(initialValue: AddLocalMedView.dates(from: med?.dosageTimes ?? [], on: startDate))
        _foodRule = State(initialValue: med?.foodRule ?? FoodRule.fromStorage(payload?.foodRule))
        _start = State(initialValue: startDate)
        _end = State(initialValue: endDate)
        _hasEndDate = State(initialValue: med != nil)
        _remindersEnabled = State(initialValue: med?.remindersEnabled ?? false)
        _caregiverRemindersEnabled = State(initialValue: med?.caregiverRemindersEnabled ?? false)
        _visualShape = State(initialValue: med?.visualShape ?? MedicationIconSuggestion.suggestedShapeID(for: initialForm) ?? "")
        _visualColor = State(initialValue: med?.visualColor ?? "green")
        _visualBackgroundColor = State(initialValue: med?.visualBackgroundColor ?? "softGreen")
        _refillReminderEnabled = State(initialValue: med?.refillReminderEnabled ?? false)
        _refillCurrentSupply = State(initialValue: med?.refillCurrentSupply)
        _refillSupplyUnit = State(initialValue: med?.refillSupplyUnit ?? "tablets")
        _refillThresholdQuantity = State(initialValue: med?.refillThresholdQuantity)
        _refillNotes = State(initialValue: med?.refillNotes ?? "")
        _notes = State(initialValue: med?.notes ?? "")
        _infoChips = State(initialValue: PatientLabelSanitizer.cleanBullets(from: payload?.indications ?? [], max: 4))
        _dosageOptions = State(initialValue: MedicationStrengthFormatter.displayableStrengths(from: payload?.strengths ?? []))
        _selectedDosageOption = State(initialValue: nil)
        _parsedMinInterval = State(initialValue: med?.minIntervalHours ?? payload?.minIntervalHours)
        _isManualSchedule = State(initialValue: med?.isManualSchedule ?? false)
        _identificationState = State(initialValue: identified ? .identified : (initialName.isEmpty ? .idle : .manual))
        _isManualDoseEditing = State(initialValue: med?.doseDetailsConfirmedByUser ?? false)
        _showOptionalDoseFields = State(initialValue: false)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                wizardHeader
                ProgressView(value: Double(step.index + 1), total: Double(WizardStep.allCases.count))
                    .tint(.istsehGreen)
                    .padding(.horizontal)
                    .padding(.bottom, 8)

                if step == .visual {
                    visualCustomizationScrollView
                } else {
                    defaultStepScrollView
                }

                footer
            }
            .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
            .background(Color.istsehPageBackground.ignoresSafeArea())
            .navigationTitle(editingMed == nil ? l("Add medication", "إضافة دواء") : l("Edit medication", "تعديل الدواء"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(l("Cancel", "إلغاء")) { dismiss() }
                }
            }
            .sheet(isPresented: $showSafetyWarnings) {
                SafetyWarningView(
                    warnings: safetyWarnings,
                    offlineMessage: offlineSafetyMessage,
                    sourceTrace: safetySourceTrace,
                    onConfirm: { save() },
                    onCancel: { showSafetyWarnings = false }
                )
            }
            .overlay {
                if isCheckingSafety {
                    ZStack {
                        Color.black.opacity(0.18).ignoresSafeArea()
                        ISTSEHLoadingView(
                            message: l("Checking safety", "جاري فحص السلامة"),
                            style: .card
                        )
                        .padding(.horizontal, 28)
                    }
                }
            }
            .onAppear {
                if dosageTimes.isEmpty && !scheduleMode.isPRN { useSuggestedSchedule() }
            }
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .confirm: confirmStep
        case .form: formStep
        case .dose: doseStep
        case .visual: visualStep
        case .scheduleType: scheduleTypeStep
        case .scheduleTimes: scheduleTimesStep
        case .food: foodStep
        case .duration: durationStep
        case .review: reviewStep
        }
    }

    private var defaultStepScrollView: some View {
        ScrollView {
            VStack(alignment: languageHorizontalAlignment, spacing: 18) {
                validationBanner
                stepContent
            }
            .padding()
        }
    }

    private var visualCustomizationScrollView: some View {
        ScrollView {
            LazyVStack(alignment: languageHorizontalAlignment, spacing: 18, pinnedViews: [.sectionHeaders]) {
                Section {
                    VStack(alignment: languageHorizontalAlignment, spacing: 18) {
                        validationBanner
                        visualStep
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                } header: {
                    VisualPreviewDock(
                        form: medicationForm.nilIfEmpty,
                        shapeID: visualShape,
                        visualColor: visualColor,
                        visualBackgroundColor: visualBackgroundColor,
                        label: l("Preview", "المعاينة"),
                        size: 104
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.istsehPageBackground)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.istsehCardStroke.opacity(0.7))
                            .frame(height: 1)
                    }
                    .zIndex(1)
                }
            }
        }
    }

    @ViewBuilder
    private var validationBanner: some View {
        if let validationError {
            Label(validationError, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .padding(12)
                .multilineTextAlignment(languageTextAlignment)
                .frame(maxWidth: .infinity, alignment: languageFrameAlignment)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var wizardHeader: some View {
        VStack(spacing: 8) {
            Text(patientHeaderText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(step.title(isArabic: isArabic))
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
            Text(l("Step \(step.index + 1) of \(WizardStep.allCases.count)", "الخطوة \(step.index + 1) من \(WizardStep.allCases.count)"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .confirm {
                Button { moveBack() } label: {
                    Label(l("Back", "رجوع"), systemImage: isArabic ? "chevron.right" : "chevron.backward")
                        .frame(maxWidth: .infinity, minHeight: 46)
                }
                .buttonStyle(.bordered)
            }

            Button {
                if step == .review {
                    runSafetyCheck()
                } else {
                    moveForward()
                }
            } label: {
                Label(step == .review ? l("Save Medication", "حفظ الدواء") : l("Continue", "متابعة"), systemImage: step == .review ? "checkmark" : (isArabic ? "chevron.left" : "chevron.forward"))
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.borderedProminent)
            .tint(.istsehGreen)
            .disabled(isCheckingSafety)
        }
        .padding()
        .background(.bar)
    }

    private var confirmStep: some View {
        WizardCard {
            VStack(alignment: languageHorizontalAlignment, spacing: 16) {
                Text(l("Medication name", "اسم الدواء"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: languageFrameAlignment)
                    .multilineTextAlignment(languageTextAlignment)
                TextField(l("Enter medication name", "أدخل اسم الدواء"), text: $name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .disabled(sourceType == .identified && editingMed != nil)
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
                    .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
                    .padding(12)
                    .background(Color.istsehCard, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.istsehCardStroke))
                    .onChange(of: name) { _, new in scheduleLookup(for: new) }

                if sourceType == .identified {
                    StatusTag(
                        title: l("Medication identified", "تم التعرف على الدواء"),
                        subtitle: l("ISTSEH found information for this medication.", "وجد استصح معلومات لهذا الدواء."),
                        systemImage: "checkmark.seal.fill"
                    )
                    Button(l("Change medication", "تغيير الدواء")) {
                        sourceType = .manual
                        identificationState = .idle
                        catalogId = nil
                        capturedRxCUI = nil
                        capturedIngredients = []
                        name = ""
                    }
                    .buttonStyle(.bordered)
                } else {
                    if identificationState == .checking || isLoadingInfo {
                        Label(l("Checking medication...", "جاري التحقق من الدواء..."), systemImage: "sparkles")
                            .foregroundStyle(.secondary)
                    } else if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        StatusTag(
                            title: l("Not identified", "لم يتم التعرف على الدواء"),
                            subtitle: l("You can still add it using the details you enter.", "يمكنك إضافته باستخدام المعلومات التي تدخلها."),
                            systemImage: "questionmark.circle.fill"
                        )
                    }
                }
            }
        }
    }

    private var formStep: some View {
        WizardCard {
            SelectionGrid(options: medicationForms, selection: $medicationForm, isArabic: isArabic)
            if medicationForm == "other" {
                TextField(l("Describe form", "اكتب النوع"), text: $customFormText)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .onChange(of: medicationForm) { _, _ in
            let options = visualOptionsForSelectedForm
            if !options.contains(where: { $0.id == visualShape }) {
                visualShape = options.first?.id ?? ""
            }
            let rule = currentFormRule
            if !rule.defaultDoseUnitOptions.contains(doseQuantityUnit) {
                doseQuantityUnit = rule.defaultDoseUnitOptions.first ?? doseQuantityUnit
                doseUnit = doseQuantityUnit
            }
            if !foodTimingVisible {
                foodRule = .none
            }
            if !doseDisplay.isEmpty {
                applyParsedDoseDetails(MedicationDoseParser.parse(doseDisplay, preferredForm: medicationForm), source: doseDetailsSource)
            }
            showOptionalDoseFields = false
        }
    }

    private var doseStep: some View {
        WizardCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(currentFormRule.helper(isArabic: isArabic))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if sourceType == .identified && !dosageOptions.isEmpty {
                    Text(l("Suggested strengths", "التركيزات المقترحة")).font(.headline)
                    ChipPicker(options: dosageOptions, selection: Binding(
                        get: { selectedDosageOption ?? "" },
                        set: { value in
                            selectedDosageOption = value
                            isManualDoseEditing = false
                            applySuggestedStrength(value)
                        }
                    ))
                }

                doseDetailsSummaryCard

                if isManualDoseEditing {
                    inlineDoseFields
                }

                if !doseDetailsConfirmedByUser {
                    Label(l("Dose details were auto-filled. Please confirm or edit them.", "تم تعبئة تفاصيل الجرعة تلقائيًا. يرجى تأكيدها أو تعديلها."), systemImage: "sparkles")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    isManualDoseEditing = true
                    showOptionalDoseFields = false
                    selectedDosageOption = nil
                    doseDetailsConfirmedByUser = true
                    isDoseAutoFilled = false
                    doseDetailsSource = "user"
                } label: {
                    Label(l("Enter manually", "إدخال يدوي"), systemImage: "pencil")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(.istsehGreen)
                .disabled(isManualDoseEditing)
            }
        }
    }

    private var doseDetailsSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l("Dose details", "تفاصيل الجرعة"))
                    .font(.headline)
                Spacer()
                Text(isDoseAutoFilled ? l("Auto-filled", "تلقائي") : l("Manual", "يدوي"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.istsehGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.istsehGreen.opacity(0.12), in: Capsule())
            }

            ReviewRow(title: l("Dose size", "حجم الجرعة"), value: doseSizeSummary)
            ReviewRow(title: l("Dose form", "نوع الجرعة"), value: displayForm)
            ReviewRow(title: l("Display label", "وصف الجرعة"), value: doseDescriptionSummary)
        }
        .padding(12)
        .background(Color.istsehGreen.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.istsehGreen.opacity(0.25)))
    }

    private var inlineDoseFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l("Manual dose entry", "إدخال الجرعة يدويًا"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            manualPrimaryDoseFields

            if hasOptionalDoseFields {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        showOptionalDoseFields.toggle()
                    }
                } label: {
                    Label(
                        showOptionalDoseFields ? l("Hide extra details", "إخفاء التفاصيل الإضافية") : l("More dose details", "تفاصيل جرعة إضافية"),
                        systemImage: showOptionalDoseFields ? "chevron.up.circle" : "chevron.down.circle"
                    )
                }
                .buttonStyle(.bordered)
                .tint(.istsehGreen)
            }

            if showOptionalDoseFields {
                manualOptionalDoseFields
            }
        }
        .onChange(of: strengthValue) { _, _ in updateDoseDisplayFromFieldsIfNeeded() }
        .onChange(of: strengthUnit) { _, _ in updateDoseDisplayFromFieldsIfNeeded() }
        .onChange(of: doseQuantity) { _, _ in updateDoseDisplayFromFieldsIfNeeded() }
        .onChange(of: doseQuantityUnit) { _, _ in updateDoseDisplayFromFieldsIfNeeded() }
        .onChange(of: concentrationAmount) { _, _ in updateDoseDisplayFromFieldsIfNeeded() }
        .onChange(of: concentrationUnit) { _, _ in updateDoseDisplayFromFieldsIfNeeded() }
    }

    @ViewBuilder
    private var manualPrimaryDoseFields: some View {
        switch MedicationFormRules.normalizedForm(medicationForm) {
        case "cream", "ointment", "gel":
            TextField(l("Application amount or instructions", "كمية الاستخدام أو التعليمات"), text: $doseDisplay)
                .textFieldStyle(ISTSEHMedicationTextFieldStyle())
                .multilineTextAlignment(isArabic ? .trailing : .leading)
            areaPicker(target: false)
        case "liquid":
            DoseInputRow(value: $doseQuantity, unit: $doseQuantityUnit, placeholder: l("Amount per dose", "الكمية في كل جرعة"), unitTitle: l("Unit", "الوحدة"), units: ["mL", "doses", "other"], isArabic: isArabic)
        case "drops":
            DoseInputRow(value: $doseQuantity, unit: $doseQuantityUnit, placeholder: l("Drops per dose", "عدد القطرات"), unitTitle: l("Unit", "الوحدة"), units: ["drops", "other"], isArabic: isArabic)
            areaPicker(target: true)
        case "inhaler":
            DoseInputRow(value: $doseQuantity, unit: $doseQuantityUnit, placeholder: l("Puffs per use", "عدد البخات"), unitTitle: l("Unit", "الوحدة"), units: ["puffs", "doses", "other"], isArabic: isArabic)
        case "spray":
            DoseInputRow(value: $doseQuantity, unit: $doseQuantityUnit, placeholder: l("Sprays per dose", "عدد الرشات"), unitTitle: l("Unit", "الوحدة"), units: ["sprays", "doses", "other"], isArabic: isArabic)
            areaPicker(target: true)
        case "injection":
            DoseInputRow(value: $doseQuantity, unit: $doseQuantityUnit, placeholder: l("Injection dose", "جرعة الحقن"), unitTitle: l("Unit", "الوحدة"), units: ["units", "mL", "mg", "IU", "other"], isArabic: isArabic)
            routePicker
        case "patch":
            DoseInputRow(value: $doseQuantity, unit: $doseQuantityUnit, placeholder: l("Patch count", "عدد اللصقات"), unitTitle: l("Unit", "الوحدة"), units: ["patches", "other"], isArabic: isArabic)
            areaPicker(target: false)
        case "tablet", "capsule", "suppository":
            DoseInputRow(value: $doseQuantity, unit: $doseQuantityUnit, placeholder: l("Dose per intake", "الجرعة في كل مرة"), unitTitle: l("Unit", "الوحدة"), units: countOnlyUnitsForCurrentForm, isArabic: isArabic)
        default:
            if currentFormRule.visibility.quantityPerDoseVisible {
                DoseInputRow(value: $doseQuantity, unit: $doseQuantityUnit, placeholder: l("Dose per intake", "الجرعة في كل مرة"), unitTitle: l("Unit", "الوحدة"), units: currentFormRule.defaultDoseUnitOptions, isArabic: isArabic)
            }
            if currentFormRule.visibility.doseFreeTextVisible {
                TextField(l("Dose instructions", "تعليمات الجرعة"), text: $doseDisplay)
                    .textFieldStyle(ISTSEHMedicationTextFieldStyle())
                    .multilineTextAlignment(isArabic ? .trailing : .leading)
            }
        }
    }

    @ViewBuilder
    private var manualOptionalDoseFields: some View {
        if currentFormRule.visibility.strengthVisible {
            DoseInputRow(value: $strengthValue, unit: $strengthUnit, placeholder: l("Strength", "التركيز"), unitTitle: l("Unit", "الوحدة"), units: strengthUnits, isArabic: isArabic)
        }

        if currentFormRule.visibility.concentrationVisible || shouldOfferTopicalConcentration {
            DoseInputRow(value: $concentrationAmount, unit: $concentrationUnit, placeholder: l("Concentration", "التركيز"), unitTitle: l("Unit", "الوحدة"), units: concentrationUnits, isArabic: isArabic)
        }

        TextField(l("Display label", "وصف الجرعة"), text: $doseDisplay)
            .textFieldStyle(ISTSEHMedicationTextFieldStyle())
            .multilineTextAlignment(isArabic ? .trailing : .leading)
            .onSubmit { updateDoseDisplayFromFields() }
    }

    private var routePicker: some View {
        Picker(l("Route", "طريقة الاستخدام"), selection: $route) {
            ForEach(routeOptions, id: \.self) { option in
                Text(localizedRoute(option)).tag(option)
            }
        }
        .pickerStyle(.menu)
    }

    private func areaPicker(target: Bool) -> some View {
        Picker(target ? l("Target area", "مكان الاستخدام") : l("Application area", "منطقة الاستخدام"), selection: $applicationArea) {
            ForEach(applicationAreaOptions, id: \.self) { option in
                Text(localizedArea(option)).tag(option)
            }
        }
        .pickerStyle(.menu)
    }

    private var countOnlyUnitsForCurrentForm: [String] {
        let countUnits = currentFormRule.defaultDoseUnitOptions.filter { !["mg", "mcg", "g"].contains($0) }
        return countUnits.contains("other") ? countUnits : countUnits + ["other"]
    }

    private var hasOptionalDoseFields: Bool {
        currentFormRule.visibility.strengthVisible
            || currentFormRule.visibility.concentrationVisible
            || shouldOfferTopicalConcentration
            || !doseDisplay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shouldOfferTopicalConcentration: Bool {
        ["cream", "ointment", "gel"].contains(MedicationFormRules.normalizedForm(medicationForm))
    }

    private var visualStep: some View {
        WizardCard {
            VStack(alignment: .center, spacing: 20) {
                Text(l("Shape", "الشكل"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                SelectionGrid(options: visualOptionsForSelectedForm, selection: $visualShape, isArabic: isArabic)
                    .frame(maxWidth: .infinity)

                Text(l("Colors", "اللون"))
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)

                ColorSwatchSection(
                    title: l("Medication color", "لون الدواء"),
                    swatches: visualColorSwatches,
                    selection: $visualColor,
                    isArabic: isArabic
                )
                .frame(maxWidth: .infinity)

                ColorSwatchSection(
                    title: l("Background color", "لون الخلفية"),
                    swatches: visualBackgroundSwatches,
                    selection: $visualBackgroundColor,
                    isArabic: isArabic
                )
                .frame(maxWidth: .infinity)

                Button(l("Skip visual identifier", "تخطي التمييز البصري")) {
                    visualShape = ""
                    visualColor = ""
                    visualBackgroundColor = ""
                    moveForward()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    private var scheduleTypeStep: some View {
        WizardCard {
            VStack(alignment: languageHorizontalAlignment, spacing: 14) {
                SelectionList(options: scheduleOptions, selection: Binding(
                    get: { scheduleMode.storageValue },
                    set: { value in
                        scheduleMode = MedicationScheduleMode.fromStorage(value, isPrn: value == "as_needed" || value == "emergency_only")
                        if scheduleMode.isPRN {
                            remindersEnabled = false
                            dosageTimes = []
                        } else {
                            if dosageTimes.isEmpty { useSuggestedSchedule() }
                        }
                    }
                ), isArabic: isArabic)

                if scheduleMode == .daily {
                    Stepper(l("\(timesPerDay)x per day", "\(timesPerDay) مرات يوميًا"), value: $timesPerDay, in: 1...6)
                        .onChange(of: timesPerDay) { _, _ in useSuggestedSchedule() }
                } else if scheduleMode == .weekly || scheduleMode == .specificDays {
                    weekdayPicker
                } else if scheduleMode == .everyXDays {
                    Stepper(l("Every \(intervalDays) days", "كل \(intervalDays) أيام"), value: $intervalDays, in: 2...30)
                } else {
                    Label(l("No fixed schedule will be created for this medication.", "لا يتم إنشاء جدول ثابت لهذا الدواء."), systemImage: "bell.slash")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: languageFrameAlignment)
                        .multilineTextAlignment(languageTextAlignment)
                }
            }
        }
    }

    private var scheduleTimesStep: some View {
        WizardCard {
            VStack(alignment: languageHorizontalAlignment, spacing: 14) {
                Button {
                    useSuggestedSchedule(preservingExistingDoseRows: true)
                    isManualSchedule = false
                } label: {
                    Label(l("Use ISTSEH suggested schedule", "استخدام جدول استصح المقترح"), systemImage: "sparkles")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)

                ForEach(dosageTimes.indices, id: \.self) { index in
                    HStack {
                        DatePicker(l("Dose \(index + 1)", "جرعة \(index + 1)"), selection: $dosageTimes[index], displayedComponents: .hourAndMinute)
                            .onChange(of: dosageTimes[index]) { _, _ in isManualSchedule = true }
                        Button {
                            dosageTimes.remove(at: index)
                            isManualSchedule = true
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.red)
                    }
                }

                HStack {
                    Spacer()
                    Button {
                        dosageTimes.append(Date())
                        isManualSchedule = true
                    } label: {
                        Label(l("Add time", "إضافة وقت"), systemImage: "plus.circle")
                            .frame(minWidth: 180, minHeight: 42)
                    }
                    .buttonStyle(.bordered)
                    .tint(.istsehGreen)
                    Spacer()
                }
                .padding(.top, 6)
            }
        }
    }

    private var foodStep: some View {
        WizardCard {
            FoodRuleSelectionList(
                options: foodOptions,
                selection: $foodRule,
                isArabic: isArabic,
                onSelect: { useSuggestedSchedule() }
            )
        }
    }

    private var durationStep: some View {
        WizardCard {
            VStack(alignment: languageHorizontalAlignment, spacing: 16) {
                WizardDateRow(title: l("Start date", "تاريخ البدء"), selection: $start, isArabic: isArabic)
                    .padding(.vertical, 4)
                WizardToggleRow(title: l("Has end date", "يوجد تاريخ انتهاء"), isOn: $hasEndDate, isArabic: isArabic)
                    .padding(.vertical, 4)
                if hasEndDate {
                    WizardDateRow(title: l("End date", "تاريخ الانتهاء"), selection: $end, isArabic: isArabic)
                        .padding(.vertical, 4)
                }
                WizardToggleRow(title: l("Reminders", "التذكيرات"), isOn: $remindersEnabled, isArabic: isArabic)
                    .disabled(scheduleMode.isPRN)
                    .padding(.vertical, 4)
                if settings.role == .caregiver {
                    WizardToggleRow(title: l("Caregiver reminders", "تذكيرات مقدم الرعاية"), isOn: $caregiverRemindersEnabled, isArabic: isArabic)
                        .disabled(scheduleMode.isPRN || !remindersEnabled)
                        .padding(.vertical, 4)
                }

                refillReminderSection

                VStack(alignment: languageHorizontalAlignment, spacing: 8) {
                    Text(l("Notes", "ملاحظات"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: languageFrameAlignment)
                        .multilineTextAlignment(languageTextAlignment)
                    ZStack(alignment: isArabic ? .topTrailing : .topLeading) {
                        if notes.isEmpty {
                            Text(l("Add any notes about this medication", "أضف ملاحظات عن الدواء، إن وجدت"))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $notes)
                            .frame(minHeight: 124)
                            .scrollContentBackground(.hidden)
                            .multilineTextAlignment(isArabic ? .trailing : .leading)
                            .padding(8)
                    }
                    .background(Color.istsehCard, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.istsehCardStroke))
                }
            }
        }
    }

    private var refillReminderSection: some View {
        VStack(alignment: languageHorizontalAlignment, spacing: 12) {
            Divider().padding(.vertical, 4)
            Text(l("Refill reminder", "تذكير إعادة الصرف"))
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: languageFrameAlignment)
                .multilineTextAlignment(languageTextAlignment)
            WizardToggleRow(title: l("Remind me before I run out", "ذكرني قبل نفاد الدواء"), isOn: $refillReminderEnabled, isArabic: isArabic)
                .padding(.vertical, 2)

            if refillReminderEnabled {
                DoseInputRow(
                    value: $refillCurrentSupply,
                    unit: $refillSupplyUnit,
                    placeholder: l("Current supply", "الكمية الحالية"),
                    unitTitle: l("Unit", "الوحدة"),
                    units: refillSupplyUnits,
                    isArabic: isArabic
                )
                DoseInputRow(
                    value: $refillThresholdQuantity,
                    unit: $refillSupplyUnit,
                    placeholder: l("Remind me when I have", "ذكرني عندما يتبقى"),
                    unitTitle: l("Unit", "الوحدة"),
                    units: refillSupplyUnits,
                    isArabic: isArabic
                )

                if let estimatedRefillDate {
                    Text(l(
                        "Based on your supply and schedule, ISTSEH will remind you around \(estimatedRefillDate.formatted(date: .abbreviated, time: .omitted)).",
                        "بناءً على الكمية والجدول، سيذكرك استصح تقريبًا في \(estimatedRefillDate.formatted(date: .abbreviated, time: .omitted))."
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: languageFrameAlignment)
                    .multilineTextAlignment(languageTextAlignment)
                } else {
                    Text(l(
                        "Add current supply and threshold. ISTSEH will estimate the refill date automatically when the schedule has enough information.",
                        "أدخل الكمية الحالية وحد التنبيه. سيحسب استصح تاريخ إعادة الصرف تلقائيًا عندما تكون معلومات الجدول كافية."
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: languageFrameAlignment)
                    .multilineTextAlignment(languageTextAlignment)
                }
            }
        }
    }

    private var reviewStep: some View {
        WizardCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    MedicationVisualView(
                        form: medicationForm.nilIfEmpty,
                        shapeID: visualShape.nilIfEmpty,
                        medicationColorID: visualColor.nilIfEmpty,
                        backgroundColorID: visualBackgroundColor.nilIfEmpty,
                        size: 64
                    )
                    Spacer()
                }
                ReviewRow(title: l("Medication", "الدواء"), value: name)
                ReviewRow(title: l("Status", "الحالة"), value: sourceType == .identified ? l("Identified", "تم التعرف عليه") : l("Manual medication", "دواء مضاف يدويًا"))
                ReviewRow(title: l("Form", "الشكل"), value: displayForm)
                ReviewRow(title: l("Strength", "التركيز"), value: displayStrength)
                ReviewRow(title: l("Dose", "الجرعة"), value: displayDose)
                ReviewRow(title: l("Schedule", "الجدول"), value: scheduleSummary)
                if foodTimingVisible {
                    ReviewRow(title: l("Food", "الطعام"), value: localizedFoodRuleTitle(foodRule))
                }
                ReviewRow(title: l("Duration", "المدة"), value: durationSummary)
                ReviewRow(title: l("Reminders", "التذكيرات"), value: remindersEnabled && !scheduleMode.isPRN ? l("On", "مفعلة") : l("Off", "متوقفة"))
                ReviewRow(title: l("Refill reminder", "تذكير إعادة الصرف"), value: refillReminderEnabled ? l("On", "مفعل") : l("Off", "متوقف"))
                if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ReviewRow(title: l("Notes", "ملاحظات"), value: notes)
                }
                Text(l("Safety checks run before saving.", "يتم فحص السلامة قبل الحفظ."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var weekdayPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l("Days", "الأيام")).font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(weekdayOptions, id: \.id) { item in
                    Button {
                        if selectedWeekdays.contains(item.id) {
                            selectedWeekdays.remove(item.id)
                        } else {
                            selectedWeekdays.insert(item.id)
                        }
                    } label: {
                        Text(isArabic ? item.ar : item.en)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(.bordered)
                    .tint(selectedWeekdays.contains(item.id) ? .istsehGreen : .secondary)
                }
            }
        }
    }

    private func moveForward() {
        validationError = validationMessage(for: step)
        guard validationError == nil else { return }
        if step == .dose && !foodTimingVisible {
            step = .visual
            return
        }
        if step == .scheduleType && scheduleMode.isPRN {
            step = .duration
            return
        }
        if let next = step.next { step = next }
    }

    private func moveBack() {
        validationError = nil
        if step == .visual && !foodTimingVisible {
            step = .dose
            return
        }
        if step == .duration && scheduleMode.isPRN {
            step = .scheduleType
            return
        }
        if let previous = step.previous { step = previous }
    }

    private func validationMessage(for step: WizardStep) -> String? {
        switch step {
        case .confirm:
            return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? l("Medication name is required.", "اسم الدواء مطلوب.") : nil
        case .form:
            if medicationForm == "other" && customFormText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return l("Describe the other form.", "اكتب الشكل الآخر.")
            }
            return nil
        case .dose:
            if strengthUnit == "other" && customUnitText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return l("Enter the custom unit.", "أدخل الوحدة الأخرى.")
            }
            return nil
        case .scheduleType:
            if (scheduleMode == .weekly || scheduleMode == .specificDays) && selectedWeekdays.isEmpty {
                return l("Choose at least one day.", "اختر يومًا واحدًا على الأقل.")
            }
            return nil
        case .scheduleTimes:
            return nil
        case .duration:
            return hasEndDate && start > end ? l("End date must be after start date.", "تاريخ الانتهاء يجب أن يكون بعد تاريخ البدء.") : nil
        default:
            return nil
        }
    }

    private func useSuggestedSchedule(preservingExistingDoseRows: Bool = false) {
        guard !scheduleMode.isPRN else {
            if !preservingExistingDoseRows { dosageTimes = [] }
            return
        }
        let existingDoseCount = dosageTimes.count
        let requestedCount = preservingExistingDoseRows && existingDoseCount > 0 ? existingDoseCount : max(timesPerDay, 1)
        let tempMed = Medication(
            id: UUID().uuidString,
            name: name,
            dosage: displayDose,
            frequencyPerDay: requestedCount,
            startDate: start,
            endDate: effectiveEndDate,
            foodRule: foodRule,
            notes: nil,
            ingredients: capturedIngredients,
            minIntervalHours: parsedMinInterval,
            rxcui: capturedRxCUI,
            dosageTimes: nil,
            asNeeded: false
        )
        let suggested = adjustedSuggestedTimes(
            Scheduler.preferredTimes(for: tempMed, on: start.startOfDay, settings: settings),
            targetCount: requestedCount
        )
        if preservingExistingDoseRows && existingDoseCount > 0 {
            dosageTimes = dosageTimes.indices.map { index in
                suggested[safe: index] ?? dosageTimes[index]
            }
        } else {
            dosageTimes = suggested
        }
    }

    private func adjustedSuggestedTimes(_ suggested: [Date], targetCount: Int) -> [Date] {
        guard targetCount > 0 else { return [] }
        var times = Array(suggested.prefix(targetCount))
        while times.count < targetCount {
            let index = times.count
            let hour = 8 + Int((Double(index) * 12.0 / Double(max(targetCount, 1))).rounded(.down))
            let fallback = Calendar.current.date(bySettingHour: min(hour, 22), minute: 0, second: 0, of: start) ?? start
            times.append(fallback)
        }
        return times
    }

    private func runSafetyCheck() {
        validationError = validationMessage(for: .duration)
        guard validationError == nil else { return }
        isCheckingSafety = true
        offlineSafetyMessage = nil
        safetyWarnings = []
        safetySourceTrace = []
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                await medsRepo.fetchMeds()
                let pendingID = editingMed?.id ?? "pending-\(UUID().uuidString)"
                let currentMed = SafetyMedicationInput(id: pendingID, name: trimmedName, rxcui: capturedRxCUI, ingredients: capturedIngredients)
                let existing = medsRepo.meds
                    .filter { !$0.isArchived && $0.id != editingMed?.id }
                    .map { SafetyMedicationInput(id: $0.id, name: $0.name, rxcui: $0.rxcui, ingredients: $0.ingredients ?? []) }
                let response = try await DrugInfo.checkSafety(
                    patientId: SupabaseManager.shared.currentUserID?.uuidString.lowercased(),
                    deviceToken: SupabaseManager.shared.patientDeviceToken,
                    medications: [currentMed] + existing,
                    lang: isArabic ? "Arabic" : "English"
                )

                await MainActor.run {
                    isCheckingSafety = false
                    let relevant = response.warnings.filter { warningApplies($0, pendingID: pendingID, medName: trimmedName) }
                    if relevant.isEmpty {
                        save()
                    } else {
                        safetyWarnings = relevant
                        safetySourceTrace = response.source_trace
                        showSafetyWarnings = true
                    }
                }
            } catch {
                let localResult = InteractionEngine.checkConflicts(
                    meds: [(trimmedName, capturedIngredients)] + medsRepo.meds.filter { $0.id != editingMed?.id }.map { ($0.name, $0.ingredients ?? []) }
                )
                await MainActor.run {
                    isCheckingSafety = false
                    let relevant = localResult.conflicts.filter { $0.medA.caseInsensitiveCompare(trimmedName) == .orderedSame || $0.medB.caseInsensitiveCompare(trimmedName) == .orderedSame }
                    if relevant.isEmpty {
                        save()
                    } else {
                        safetyWarnings = relevant.map {
                            SafetyWarning(type: .drugInteraction, severity: .major, meds: [$0.medA, $0.medB], ingredients: [], description: $0.explanation, management: l("Consult your doctor for advice.", "استشر طبيبك."), source: "local_engine", is_deterministic: true, requires_acknowledgement: true, can_continue: true)
                        }
                        safetySourceTrace = ["local_engine"]
                        offlineSafetyMessage = localResult.warningMessage
                        showSafetyWarnings = true
                    }
                }
            }
        }
    }

    private func warningApplies(_ warning: SafetyWarning, pendingID: String, medName: String) -> Bool {
        if warning.affected_medication_ids?.contains(pendingID) == true { return true }
        let normalizedName = medName.lowercased()
        return warning.meds.map { $0.lowercased() }.contains { $0.contains(normalizedName) || normalizedName.contains($0) }
            || !Set(warning.ingredients.map { $0.lowercased() }).isDisjoint(with: Set(capturedIngredients.map { $0.lowercased() }))
    }

    private func save() {
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm:ss"
        let times = scheduleMode.isPRN ? [] : DoseTextFormatter.deduplicatedTimeStrings(dosageTimes.map { timeFmt.string(from: $0) })
        let savedScheduleMode: MedicationScheduleMode = (!scheduleMode.isPRN && times.isEmpty) ? .asNeeded : scheduleMode
        let scanWasConfirmedInThisForm = scanMetadata?.scanSource == "manual_from_scan"
        let med = LocalMed(
            id: editingMed?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            dosage: displayDose,
            frequencyPerDay: savedScheduleMode.isPRN ? 1 : max(timesPerDay, times.count, 1),
            startDate: start,
            endDate: effectiveEndDate,
            foodRule: foodRule,
            dosageTimes: times,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            ingredients: capturedIngredients.isEmpty ? nil : capturedIngredients,
            rxcui: capturedRxCUI,
            minIntervalHours: parsedMinInterval,
            isArchived: false,
            asNeeded: savedScheduleMode.isPRN,
            isManualSchedule: isManualSchedule,
            catalogId: sourceType == .identified ? catalogId : nil,
            sourceType: sourceType,
            medicationForm: medicationForm.isEmpty ? nil : medicationForm,
            customFormText: customFormText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            strengthValue: effectiveStrengthValue,
            strengthUnit: effectiveStrengthUnit,
            customUnitText: customUnitText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            doseAmount: doseAmount,
            doseAmountUnit: doseAmount == nil ? nil : doseAmountUnit.nilIfEmpty,
            doseQuantity: doseQuantity,
            doseUnit: doseQuantity == nil ? nil : (doseQuantityUnit.nilIfEmpty ?? doseUnit),
            doseQuantityUnit: doseQuantity == nil ? nil : doseQuantityUnit.nilIfEmpty,
            strengthAmount: effectiveStrengthValue,
            parsedStrengthUnit: effectiveStrengthUnit,
            concentrationAmount: concentrationAmount,
            concentrationUnit: concentrationAmount == nil ? nil : concentrationUnit.nilIfEmpty,
            route: route.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            applicationArea: applicationArea.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            doseDisplay: displayDose.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            foodRuleSource: foodRuleSource.nilIfEmpty,
            doseDetailsSource: doseDetailsSource.nilIfEmpty,
            isDoseAutoFilled: isDoseAutoFilled,
            doseDetailsConfirmedByUser: doseDetailsConfirmedByUser,
            scheduleMode: savedScheduleMode,
            timesPerDay: savedScheduleMode == .daily ? timesPerDay : nil,
            timesPerWeek: (savedScheduleMode == .weekly || savedScheduleMode == .specificDays) ? max(selectedWeekdays.count, 1) : nil,
            selectedWeekdays: savedScheduleMode.isPRN ? [] : Array(selectedWeekdays).sorted(),
            intervalDays: savedScheduleMode == .everyXDays ? intervalDays : nil,
            remindersEnabled: remindersEnabled && !savedScheduleMode.isPRN && !times.isEmpty,
            caregiverRemindersEnabled: caregiverRemindersEnabled,
            visualShape: visualShape.nilIfEmpty,
            visualColor: visualColor.nilIfEmpty,
            visualBackgroundColor: visualBackgroundColor.nilIfEmpty,
            refillReminderEnabled: refillReminderEnabled,
            refillCurrentSupply: refillReminderEnabled ? refillCurrentSupply : nil,
            refillSupplyUnit: refillReminderEnabled ? refillSupplyUnit : nil,
            refillThresholdQuantity: refillReminderEnabled ? refillThresholdQuantity : nil,
            refillEstimatedRunoutDate: refillReminderEnabled ? estimatedRefillDate : nil,
            refillReminderDate: effectiveRefillReminderDate,
            refillReminderMode: refillReminderEnabled ? "automatic" : nil,
            refillNotes: refillReminderEnabled ? refillNotes.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty : nil,
            sourceMetadata: nil,
            scanSource: scanMetadata?.scanSource ?? editingMed?.scanSource ?? "manual",
            scanConfidence: scanMetadata?.scanConfidence ?? editingMed?.scanConfidence,
            scanConfirmedByUser: scanWasConfirmedInThisForm ? true : (scanMetadata?.scanConfirmedByUser ?? editingMed?.scanConfirmedByUser ?? false),
            scanExtractedFields: scanMetadata?.extractedFields ?? editingMed?.scanExtractedFields,
            scanCandidateSnapshot: scanMetadata?.candidateSnapshot ?? editingMed?.scanCandidateSnapshot
        )
        #if DEBUG
        print("""
        Add medication selected visual/refill before save
        visual_shape: \(visualShape.nilIfEmpty ?? "nil")
        visual_color: \(visualColor.nilIfEmpty ?? "nil")
        visual_background_color: \(visualBackgroundColor.nilIfEmpty ?? "nil")
        medication_form: \(medicationForm.nilIfEmpty ?? "nil")
        refill_enabled: \(refillReminderEnabled)
        refill_current_supply present: \(refillCurrentSupply != nil)
        refill_threshold present: \(refillThresholdQuantity != nil)
        refill_reminder_mode: \(refillReminderEnabled ? "automatic" : "off")
        refill_reminder_date present: \(effectiveRefillReminderDate != nil)
        scan_source: \(scanMetadata?.scanSource ?? editingMed?.scanSource ?? "manual")
        scan_confirmed_by_user: \(scanMetadata?.scanConfirmedByUser ?? editingMed?.scanConfirmedByUser ?? false)
        """)
        #endif
        onSave(med)
        dismiss()
    }

    private func scheduleLookup(for input: String) {
        fetchTask?.cancel()
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        resetIdentificationForInput(trimmed)
        guard sourceType == .manual, trimmed.count >= 3 else {
            identificationState = trimmed.isEmpty ? .idle : .notIdentified
            return
        }
        identificationState = .checking
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
        do {
            if let catalogPayload = try await strictCatalogPayload(for: medName) {
                applyIdentifiedPayload(
                    catalogPayload.normalizedForPatientDisplay(fallbackTitle: catalogPayload.title),
                    source: "catalog",
                    confidence: 1,
                    reason: "catalog id present and normalized name matched"
                )
                return
            }

            let payload = try await DrugInfo.fetchDetails(name: medName)
            let hasOfficialIdentifier = payload.id != nil || payload.rxcui?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            guard hasOfficialIdentifier else {
                markNotIdentified(
                    input: medName,
                    source: "drug-intel",
                    candidateNames: [payload.title],
                    confidence: 0,
                    reason: "drug-info response had no catalog id or RxCUI"
                )
                return
            }

            let entry = try? await MedCatalogRepo.shared.upsert(from: payload, searchedName: medName)
            let finalPayload = (entry?.payload ?? payload).normalizedForPatientDisplay(fallbackTitle: medName)
            applyIdentifiedPayload(
                finalPayload,
                source: "drug-intel",
                confidence: payload.rxcui == nil ? 0.92 : 1,
                reason: "official identifier present"
            )
        } catch {
            markNotIdentified(
                input: medName,
                source: "lookup-error",
                candidateNames: [],
                confidence: 0,
                reason: "\(error)"
            )
        }
    }

    private func resetIdentificationForInput(_ input: String) {
        sourceType = .manual
        catalogId = nil
        capturedRxCUI = nil
        capturedIngredients = []
        parsedMinInterval = nil
        dosageOptions = []
        selectedDosageOption = nil
        infoChips = []
        if input.isEmpty {
            identificationState = .idle
        }
    }

    private func applyIdentifiedPayload(_ finalPayload: DrugPayload, source: String, confidence: Double, reason: String) {
        dosageOptions = MedicationStrengthFormatter.displayableStrengths(from: finalPayload.strengths)
        selectedDosageOption = nil
        foodRule = FoodRule.fromStorage(finalPayload.foodRule)
        foodRuleSource = foodRule == .none ? "" : "source"
        parsedMinInterval = finalPayload.minIntervalHours
        capturedIngredients = finalPayload.ingredients
        capturedRxCUI = finalPayload.rxcui
        catalogId = finalPayload.id?.uuidString
        sourceType = .identified
        identificationState = .identified
        infoChips = PatientLabelSanitizer.cleanBullets(from: finalPayload.indications, max: 4)
        #if DEBUG
        debugIdentification(rawInput: name, source: source, candidateNames: [finalPayload.title], confidence: confidence, selectedID: catalogId, reason: reason, finalState: "identified")
        #endif
    }

    private func markNotIdentified(input: String, source: String, candidateNames: [String], confidence: Double, reason: String) {
        sourceType = .manual
        catalogId = nil
        capturedRxCUI = nil
        capturedIngredients = []
        parsedMinInterval = nil
        dosageOptions = []
        selectedDosageOption = nil
        identificationState = .notIdentified
        infoChips = [l("No matching database result. You can continue manually.", "لا توجد نتيجة مطابقة. يمكنك المتابعة يدويًا.")]
        #if DEBUG
        debugIdentification(rawInput: input, source: source, candidateNames: candidateNames, confidence: confidence, selectedID: nil, reason: reason, finalState: "notIdentified")
        #endif
    }

    private var patientHeaderText: String {
        let patientName = settings.activePatientName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let patientName, !patientName.isEmpty {
            return l("Adding for \(patientName)", "إضافة لـ \(patientName)")
        }
        return l("Adding for My Profile", "إضافة لملفي")
    }

    private var effectiveEndDate: Date {
        hasEndDate ? end : Calendar.current.date(byAdding: .year, value: 20, to: start) ?? end
    }

    private var displayForm: String {
        medicationForm == "other" ? customFormText : optionTitle(medicationForm, in: medicationForms, isArabic: isArabic)
    }

    private var displayStrength: String {
        if let selectedDosageOption, !selectedDosageOption.isEmpty { return selectedDosageOption }
        guard let strengthValue, strengthValue > 0 else { return l("Unknown", "غير معروف") }
        let unit = strengthUnit == "other" ? customUnitText : unitLabel(strengthUnit, isArabic: isArabic)
        return "\(strengthValue.formatted()) \(unit)"
    }

    private var doseSizeSummary: String {
        let form = MedicationFormRules.normalizedForm(medicationForm)
        if currentFormRule.visibility.doseFreeTextVisible {
            let concentration = concentrationAmount.map { "\($0.formatted()) \(concentrationUnit)" }
            return concentration ?? displayStrengthOrFallback
        }
        if currentFormRule.visibility.concentrationVisible, let concentrationAmount {
            return "\(concentrationAmount.formatted()) \(concentrationUnit)"
        }
        if form == "drops" || form == "inhaler" || form == "spray" {
            return quantityPerDoseSummary
        }
        return displayStrengthOrFallback
    }

    private var displayStrengthOrFallback: String {
        let value = displayStrength
        if value == l("Unknown", "غير معروف"), !doseDisplay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return doseDisplay
        }
        return value
    }

    private var doseDescriptionSummary: String {
        let explicit = doseDisplay.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }

        let form = MedicationFormRules.normalizedForm(medicationForm)
        switch form {
        case "cream", "ointment", "gel":
            let amount = doseQuantity.map { "\($0.formatted()) \(doseQuantityUnit)" }
            let area = applicationArea.isEmpty ? nil : localizedArea(applicationArea)
            return [amount, area].compactMap { $0 }.joined(separator: " - ").nilIfEmpty ?? l("Apply as directed", "يستخدم حسب التعليمات")
        case "liquid":
            return quantityPerDoseSummary
        case "drops", "inhaler", "spray", "patch", "suppository":
            return quantityPerDoseSummary
        case "injection":
            let routeText = route.isEmpty ? nil : localizedRoute(route)
            return [displayStrengthOrFallback, routeText].compactMap { $0 }.joined(separator: " - ")
        default:
            if displayStrengthOrFallback != l("Unknown", "غير معروف") {
                return "\(quantityPerDoseSummary) / \(displayStrengthOrFallback)"
            }
            return quantityPerDoseSummary
        }
    }

    private var effectiveStrengthValue: Double? {
        strengthValue ?? selectedDosageOption.flatMap { parseStrengthOption($0)?.value }
    }

    private var effectiveStrengthUnit: String? {
        if strengthUnit == "other" {
            return customUnitText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }
        if strengthValue != nil { return strengthUnit }
        return selectedDosageOption.flatMap { parseStrengthOption($0)?.unit }
    }

    private var displayDose: String {
        if !doseDisplay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return doseDisplay
        }
        guard let doseQuantity, doseQuantity > 0 else { return "" }
        let quantity = doseQuantity
        let unit = doseQuantityUnit == "other" ? customUnitText : unitLabel(doseQuantityUnit, isArabic: isArabic)
        return "\(quantity.formatted()) \(unit)"
    }

    private var quantityPerDoseSummary: String {
        let quantity = doseQuantity ?? doseAmount ?? 0
        let unit = doseQuantityUnit.isEmpty ? doseUnit : doseQuantityUnit
        return "\(quantity.formatted()) \(unitLabel(unit, isArabic: isArabic))"
    }

    private var currentFormRule: MedicationFormRule {
        MedicationFormRules.rule(for: medicationForm)
    }

    private var foodTimingVisible: Bool {
        MedicationFormRules.shouldShowFoodTiming(
            formID: medicationForm,
            foodRule: foodRule,
            sourceBacked: foodRuleSource == "source" || sourceType == .identified
        )
    }

    private var visualOptionsForSelectedForm: [WizardOption] {
        switch medicationForm {
        case "tablet":
            return tabletVisualShapes
        case "capsule":
            return capsuleVisualShapes
        case "liquid":
            return liquidVisualShapes
        case "drops":
            return dropsVisualShapes
        case "injection":
            return injectionVisualShapes
        case "inhaler", "device":
            return deviceVisualShapes
        case "cream", "ointment", "gel", "topical", "lotion":
            return creamVisualShapes
        case "patch":
            return patchVisualShapes
        case "spray":
            return sprayVisualShapes
        case "suppository":
            return suppositoryVisualShapes
        default:
            return genericVisualShapes
        }
    }

    private var defaultDoseUnitForForm: String {
        switch medicationForm {
        case "capsule": return "capsules"
        case "liquid": return "mL"
        case "drops": return "drops"
        case "inhaler", "spray": return "puffs"
        case "tablet": return "tablets"
        default: return doseUnit
        }
    }

    private func applySuggestedStrength(_ value: String) {
        let parsedDetails = MedicationDoseParser.parse(value, preferredForm: medicationForm)
        applyParsedDoseDetails(parsedDetails, source: "auto")
        if let parsed = parseStrengthOption(value), strengthValue == nil {
            strengthValue = parsed.value
            strengthUnit = parsed.unit
        }
    }

    private func applyParsedDoseDetails(_ details: ParsedMedicationDoseDetails, source: String) {
        if medicationForm.isEmpty || medicationForm == "other" {
            medicationForm = details.doseForm ?? medicationForm
        }
        doseAmount = details.doseAmount
        doseAmountUnit = details.doseUnit ?? doseAmountUnit
        strengthValue = details.strengthAmount ?? strengthValue
        strengthUnit = details.strengthUnit ?? strengthUnit
        concentrationAmount = details.concentrationAmount
        concentrationUnit = details.concentrationUnit ?? concentrationUnit
        doseQuantity = details.quantityPerDose ?? doseQuantity
        doseQuantityUnit = details.quantityUnit ?? defaultDoseUnitForForm
        doseUnit = doseQuantityUnit
        route = details.route ?? route
        applicationArea = details.applicationArea ?? applicationArea
        doseDisplay = details.displayLabel
        doseDetailsSource = source
        isDoseAutoFilled = source == "auto"
        doseDetailsConfirmedByUser = !details.isConfident
    }

    private func updateDoseDisplayFromFields() {
        let quantityText = doseQuantity.map { "\($0.formatted()) \(doseQuantityUnit)" }
        let strengthText = strengthValue.map { "\($0.formatted()) \(effectiveStrengthUnit ?? strengthUnit)" }
        if let quantityText, let strengthText {
            doseDisplay = "\(quantityText) / \(strengthText)"
        } else if let quantityText {
            doseDisplay = quantityText
        } else if let strengthText {
            doseDisplay = strengthText
        }
    }

    private func updateDoseDisplayFromFieldsIfNeeded() {
        guard isManualDoseEditing else { return }
        updateDoseDisplayFromFields()
    }

    private func parseStrengthOption(_ value: String) -> (value: Double, unit: String, doseQuantity: Double, doseUnit: String)? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(mg|mcg|g|mL|IU|%|units|puffs|drops|tablets|capsules)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: value, range: NSRange(location: 0, length: (value as NSString).length)),
              match.numberOfRanges >= 3 else { return nil }
        let number = (value as NSString).substring(with: match.range(at: 1))
        let unit = (value as NSString).substring(with: match.range(at: 2))
        guard let amount = Double(number) else { return nil }
        return (amount, normalizedUnit(unit), 1, defaultDoseUnitForForm)
    }

    private func normalizedUnit(_ unit: String) -> String {
        let lower = unit.lowercased()
        if lower == "ml" { return "mL" }
        if lower == "iu" { return "IU" }
        if unit == "%" { return "%" }
        return strengthUnits.contains(unit) ? unit : lower
    }

    private var scheduleSummary: String {
        if scheduleMode.isPRN { return scheduleMode == .emergencyOnly ? l("Emergency only", "للطوارئ فقط") : l("As needed only", "عند الحاجة فقط") }
        let times = dosageTimes.map { $0.formatted(date: .omitted, time: .shortened) }.joined(separator: ", ")
        switch scheduleMode {
        case .daily: return l("Daily, \(timesPerDay)x per day", "يوميًا، \(timesPerDay) مرات") + (times.isEmpty ? "" : " - \(times)")
        case .weekly, .specificDays: return l("Selected days", "أيام محددة") + (times.isEmpty ? "" : " - \(times)")
        case .everyXDays: return l("Every \(intervalDays) days", "كل \(intervalDays) أيام") + (times.isEmpty ? "" : " - \(times)")
        case .asNeeded, .emergencyOnly: return l("As needed", "عند الحاجة")
        }
    }

    private func localizedFoodRuleTitle(_ rule: FoodRule) -> String {
        switch rule {
        case .none: return l("No food instructions", "بدون تعليمات طعام")
        case .beforeFood: return l("Before food", "قبل الأكل")
        case .withFood: return l("With food", "مع الأكل")
        case .afterFood: return l("After food", "بعد الأكل")
        case .avoidWithFood: return l("Avoid with food", "تجنب تناوله مع الطعام")
        case .notSure: return l("Not sure", "غير متأكد")
        }
    }

    private var durationSummary: String {
        let startText = start.formatted(date: .abbreviated, time: .omitted)
        if !hasEndDate { return l("Starts \(startText), no end date", "يبدأ \(startText)، بدون تاريخ انتهاء") }
        return "\(startText) - \(end.formatted(date: .abbreviated, time: .omitted))"
    }

    private var estimatedRefillDate: Date? {
        guard refillReminderEnabled,
              !scheduleMode.isPRN,
              let current = refillCurrentSupply,
              let threshold = refillThresholdQuantity,
              let dose = doseQuantity,
              current > threshold,
              dose > 0 else { return nil }
        let dailyUse = dailyDoseUseEstimate * dose
        guard dailyUse > 0 else { return nil }
        let daysUntilThreshold = max(Int(floor((current - threshold) / dailyUse)), 0)
        return refillNotificationDate(from: Calendar.current.date(byAdding: .day, value: daysUntilThreshold, to: start) ?? start)
    }

    private var effectiveRefillReminderDate: Date? {
        guard refillReminderEnabled else { return nil }
        return estimatedRefillDate
    }

    private var dailyDoseUseEstimate: Double {
        switch scheduleMode {
        case .daily:
            return Double(max(dosageTimes.count, timesPerDay, 1))
        case .weekly, .specificDays:
            let selectedDays = max(selectedWeekdays.count, 1)
            let dosesPerSelectedDay = max(dosageTimes.count, 1)
            return Double(selectedDays * dosesPerSelectedDay) / 7.0
        case .everyXDays:
            let dosesPerUseDay = max(dosageTimes.count, 1)
            return Double(dosesPerUseDay) / Double(max(intervalDays, 1))
        case .asNeeded, .emergencyOnly:
            return 0
        }
    }

    private func refillNotificationDate(from day: Date) -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    private var isArabic: Bool {
        if let stored = UserDefaults.standard.string(forKey: "appearance.language"), !stored.isEmpty {
            return stored == "ar"
        }
        return Locale.current.language.languageCode?.identifier == "ar"
    }

    private var languageHorizontalAlignment: HorizontalAlignment { isArabic ? .trailing : .leading }
    private var languageTextAlignment: TextAlignment { isArabic ? .trailing : .leading }
    private var languageFrameAlignment: Alignment { isArabic ? .trailing : .leading }

    private func l(_ en: String, _ ar: String) -> String { isArabic ? ar : en }

    private func strictCatalogPayload(for medName: String) async throws -> DrugPayload? {
        struct Row: Decodable {
            let id: String
            let name: String
            let how_to_take: [String]?
            let common_side_effects: [String]?
            let interactions_to_avoid: [String]?
            let food_rule: String?
            let min_interval_hours: Int?
            let strengths: [String]?
            let what_for: [String]?
            let warnings: [String]?
            let rxcui: String?
            let active_ingredients: [String]?
        }

        let trimmed = medName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedInput = normalizedMedicationName(trimmed)
        let rows: [Row] = try await SupabaseManager.shared.client
            .from("medications")
            .select()
            .ilike("name", pattern: trimmed)
            .limit(5)
            .execute()
            .value

        let selected = rows.first { normalizedMedicationName($0.name) == normalizedInput }
        #if DEBUG
        debugIdentification(rawInput: medName, source: "catalog", candidateNames: rows.map(\.name), confidence: selected == nil ? 0 : 1, selectedID: selected?.id, reason: "strict catalog lookup", finalState: selected == nil ? "notIdentified" : "identified")
        #endif

        guard let row = selected else { return nil }
        return DrugPayload(
            title: row.name,
            strengths: MedicationStrengthFormatter.displayableStrengths(from: row.strengths ?? []),
            dosageForms: [],
            foodRule: row.food_rule,
            minIntervalHours: row.min_interval_hours,
            ingredients: row.active_ingredients ?? [],
            indications: row.what_for ?? [],
            howToTake: row.how_to_take ?? [],
            commonSideEffects: row.common_side_effects ?? [],
            importantWarnings: row.warnings ?? [],
            interactionsToAvoid: row.interactions_to_avoid ?? [],
            references: nil,
            kbKey: nil,
            rxcui: row.rxcui,
            id: UUID(uuidString: row.id)
        )
    }

    private func normalizedMedicationName(_ value: String) -> String {
        value
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9\u{0600}-\u{06FF}]+"#, with: "", options: .regularExpression)
    }

    #if DEBUG
    private func debugIdentification(rawInput: String, source: String, candidateNames: [String], confidence: Double, selectedID: String?, reason: String, finalState: String) {
        print("""
        🧪 Medication identification
        rawInput: \(rawInput)
        normalizedInput: \(normalizedMedicationName(rawInput))
        lookupSource: \(source)
        candidateNames: \(candidateNames)
        confidenceScore: \(confidence)
        selectedCandidateId: \(selectedID ?? "nil")
        rxCUIPresent: \(capturedRxCUI != nil)
        catalogIdPresent: \(selectedID != nil)
        finalIdentificationState: \(finalState)
        reason: \(reason)
        """)
    }
    #endif

    private static func dates(from strings: [String], on date: Date) -> [Date] {
        strings.compactMap { value in
            let parts = value.split(separator: ":")
            guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
            return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: date)
        }
    }
}

private enum WizardStep: CaseIterable {
    case confirm, form, dose, food, visual, scheduleType, scheduleTimes, duration, review

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    var next: WizardStep? { Self.allCases[safe: index + 1] }
    var previous: WizardStep? { Self.allCases[safe: index - 1] }

    func title(isArabic: Bool) -> String {
        let titles = isArabic
            ? ["تأكيد الدواء", "شكل الدواء", "التركيز والجرعة", "تعليمات الطعام", "تمييز بصري", "نوع الجدول", "أوقات الجرعات", "المدة والتذكيرات", "المراجعة والسلامة"]
            : ["Confirm Medication", "Choose Form", "Strength and Dose", "Food Instructions", "Visual Identification", "Schedule Type", "Schedule Times", "Duration and Reminders", "Review and Safety"]
        return titles[index]
    }
}

private enum MedicationIdentificationState {
    case idle
    case checking
    case identified
    case notIdentified
    case manual
}

private struct WizardOption: Identifiable {
    let id: String
    let englishTitle: String
    let arabicTitle: String
    let systemImage: String

    func title(isArabic: Bool) -> String { isArabic ? arabicTitle : englishTitle }
}

private let medicationForms = [
    WizardOption(id: "tablet", englishTitle: "Tablet", arabicTitle: "قرص", systemImage: "pills.fill"),
    WizardOption(id: "capsule", englishTitle: "Capsule", arabicTitle: "كبسولة", systemImage: "capsule.fill"),
    WizardOption(id: "liquid", englishTitle: "Liquid", arabicTitle: "شراب", systemImage: "drop.fill"),
    WizardOption(id: "drops", englishTitle: "Drops", arabicTitle: "قطرات", systemImage: "drop.triangle.fill"),
    WizardOption(id: "injection", englishTitle: "Injection", arabicTitle: "حقنة", systemImage: "syringe.fill"),
    WizardOption(id: "inhaler", englishTitle: "Inhaler", arabicTitle: "بخاخ", systemImage: "wind"),
    WizardOption(id: "cream", englishTitle: "Cream", arabicTitle: "كريم", systemImage: "cross.case.fill"),
    WizardOption(id: "ointment", englishTitle: "Ointment", arabicTitle: "مرهم", systemImage: "cross.case.fill"),
    WizardOption(id: "patch", englishTitle: "Patch", arabicTitle: "لصقة", systemImage: "square.fill"),
    WizardOption(id: "spray", englishTitle: "Spray", arabicTitle: "رذاذ", systemImage: "humidity.fill"),
    WizardOption(id: "suppository", englishTitle: "Suppository", arabicTitle: "تحميلة", systemImage: "diamond.fill"),
    WizardOption(id: "device", englishTitle: "Device", arabicTitle: "جهاز", systemImage: "medical.thermometer.fill"),
    WizardOption(id: "other", englishTitle: "Other", arabicTitle: "أخرى", systemImage: "ellipsis.circle")
]

private let tabletVisualShapes = [
    WizardOption(id: "tablet_rounded", englishTitle: "Rounded", arabicTitle: "مستدير", systemImage: "pills.fill"),
    WizardOption(id: "tablet_circle", englishTitle: "Circle", arabicTitle: "دائري", systemImage: "pills.fill"),
    WizardOption(id: "tablet_soft", englishTitle: "Soft square", arabicTitle: "مربع ناعم", systemImage: "pills.fill"),
    WizardOption(id: "oval", englishTitle: "Oval", arabicTitle: "بيضاوي", systemImage: "capsule.fill"),
    WizardOption(id: "diamond", englishTitle: "Diamond", arabicTitle: "معيّن", systemImage: "diamond.fill"),
    WizardOption(id: "other", englishTitle: "Other", arabicTitle: "أخرى", systemImage: "ellipsis.circle")
]

private let capsuleVisualShapes = [
    WizardOption(id: "capsule_rounded", englishTitle: "Rounded", arabicTitle: "مستدير", systemImage: "capsule.fill"),
    WizardOption(id: "capsule_circle", englishTitle: "Circle", arabicTitle: "دائري", systemImage: "capsule.fill"),
    WizardOption(id: "capsule_horizontal", englishTitle: "Wide", arabicTitle: "عريض", systemImage: "capsule.fill"),
    WizardOption(id: "capsule_soft", englishTitle: "Soft square", arabicTitle: "مربع ناعم", systemImage: "capsule.fill"),
    WizardOption(id: "other", englishTitle: "Other", arabicTitle: "أخرى", systemImage: "ellipsis.circle")
]

private let liquidVisualShapes = [
    WizardOption(id: "liquid", englishTitle: "Bottle", arabicTitle: "زجاجة", systemImage: "cross.vial.fill"),
    WizardOption(id: "cup", englishTitle: "Dose cup", arabicTitle: "كوب جرعة", systemImage: "drop.fill"),
    WizardOption(id: "spoon", englishTitle: "Oral syringe", arabicTitle: "سرنجة فموية", systemImage: "syringe.fill"),
    WizardOption(id: "other", englishTitle: "Other", arabicTitle: "أخرى", systemImage: "ellipsis.circle")
]

private let dropsVisualShapes = [
    WizardOption(id: "drops", englishTitle: "Dropper", arabicTitle: "قطارة", systemImage: "drop.triangle.fill"),
    WizardOption(id: "dropBottle", englishTitle: "Drops bottle", arabicTitle: "زجاجة قطرات", systemImage: "drop.fill"),
    WizardOption(id: "other", englishTitle: "Other", arabicTitle: "أخرى", systemImage: "ellipsis.circle")
]

private let injectionVisualShapes = [
    WizardOption(id: "syringe", englishTitle: "Syringe", arabicTitle: "حقنة", systemImage: "syringe.fill"),
    WizardOption(id: "vial", englishTitle: "Vial", arabicTitle: "قارورة", systemImage: "cross.vial.fill"),
    WizardOption(id: "injectionPen", englishTitle: "Injection pen", arabicTitle: "قلم حقن", systemImage: "pencil"),
    WizardOption(id: "other", englishTitle: "Other", arabicTitle: "أخرى", systemImage: "ellipsis.circle")
]

private let deviceVisualShapes = [
    WizardOption(id: "inhaler", englishTitle: "Inhaler", arabicTitle: "بخاخ", systemImage: "wind"),
    WizardOption(id: "device", englishTitle: "Device", arabicTitle: "جهاز", systemImage: "medical.thermometer.fill"),
    WizardOption(id: "other", englishTitle: "Other", arabicTitle: "أخرى", systemImage: "ellipsis.circle")
]

private let creamVisualShapes = [
    WizardOption(id: "cream_tube", englishTitle: "Tube", arabicTitle: "أنبوب", systemImage: "cross.case.fill"),
    WizardOption(id: "ointment", englishTitle: "Ointment", arabicTitle: "مرهم", systemImage: "cross.case.fill"),
    WizardOption(id: "gel", englishTitle: "Gel", arabicTitle: "جل", systemImage: "cross.case.fill"),
    WizardOption(id: "jar", englishTitle: "Jar", arabicTitle: "علبة", systemImage: "shippingbox.fill"),
    WizardOption(id: "other", englishTitle: "Other", arabicTitle: "أخرى", systemImage: "ellipsis.circle")
]

private let patchVisualShapes = [
    WizardOption(id: "patch", englishTitle: "Patch", arabicTitle: "لصقة", systemImage: "bandage.fill"),
    WizardOption(id: "other", englishTitle: "Other", arabicTitle: "أخرى", systemImage: "ellipsis.circle")
]

private let sprayVisualShapes = [
    WizardOption(id: "spray", englishTitle: "Spray", arabicTitle: "رذاذ", systemImage: "humidity.fill"),
    WizardOption(id: "inhaler", englishTitle: "Inhaler", arabicTitle: "بخاخ", systemImage: "wind"),
    WizardOption(id: "other", englishTitle: "Other", arabicTitle: "أخرى", systemImage: "ellipsis.circle")
]

private let suppositoryVisualShapes = [
    WizardOption(id: "suppository", englishTitle: "Suppository", arabicTitle: "تحميلة", systemImage: "diamond.fill"),
    WizardOption(id: "other", englishTitle: "Other", arabicTitle: "أخرى", systemImage: "ellipsis.circle")
]

private let genericVisualShapes = [
    WizardOption(id: "liquid", englishTitle: "Bottle", arabicTitle: "زجاجة", systemImage: "cross.vial.fill"),
    WizardOption(id: "device", englishTitle: "Device", arabicTitle: "جهاز", systemImage: "medical.thermometer.fill"),
    WizardOption(id: "other", englishTitle: "Other", arabicTitle: "أخرى", systemImage: "ellipsis.circle")
]

private let scheduleOptions = [
    WizardOption(id: "daily", englishTitle: "Daily", arabicTitle: "يوميًا", systemImage: "sun.max.fill"),
    WizardOption(id: "weekly", englishTitle: "Weekly", arabicTitle: "أسبوعيًا", systemImage: "calendar"),
    WizardOption(id: "specific_days", englishTitle: "Specific days", arabicTitle: "أيام محددة", systemImage: "calendar.badge.checkmark"),
    WizardOption(id: "every_x_days", englishTitle: "Every X days", arabicTitle: "كل عدة أيام", systemImage: "repeat"),
    WizardOption(id: "as_needed", englishTitle: "As needed only", arabicTitle: "عند الحاجة فقط", systemImage: "bell.slash.fill"),
    WizardOption(id: "emergency_only", englishTitle: "Emergency only", arabicTitle: "للطوارئ فقط", systemImage: "cross.case.fill")
]

private let foodOptions = [
    WizardOption(id: "none", englishTitle: "No food instructions", arabicTitle: "بدون تعليمات طعام", systemImage: "fork.knife.circle"),
    WizardOption(id: "beforeFood", englishTitle: "Before food", arabicTitle: "قبل الأكل", systemImage: "arrow.left.circle"),
    WizardOption(id: "withFood", englishTitle: "With food", arabicTitle: "مع الأكل", systemImage: "fork.knife"),
    WizardOption(id: "afterFood", englishTitle: "After food", arabicTitle: "بعد الأكل", systemImage: "arrow.right.circle"),
    WizardOption(id: "avoidWithFood", englishTitle: "Avoid with food", arabicTitle: "تجنب تناوله مع الطعام", systemImage: "exclamationmark.triangle"),
    WizardOption(id: "notSure", englishTitle: "Not sure", arabicTitle: "غير متأكد", systemImage: "questionmark.circle")
]

private let strengthUnits = ["mg", "mcg", "g", "mL", "IU", "%", "units", "puffs", "drops", "tablets", "capsules", "other"]
private let refillSupplyUnits = ["tablets", "capsules", "mL", "doses", "puffs", "units", "other"]
private let concentrationUnits = ["mg/mL", "mcg/mL", "units/mL", "IU/mL", "mg/5 mL", "other"]
private let routeOptions = ["", "subcutaneous", "intramuscular", "intravenous", "unknown"]
private let applicationAreaOptions = ["", "skin", "eye", "ear", "nose", "oral", "other"]
private let visualColorSwatches = [
    MedicationColorSwatch(id: "green", englishTitle: "Green", arabicTitle: "أخضر", color: Color(red: 0.18, green: 0.72, blue: 0.44)),
    MedicationColorSwatch(id: "sage", englishTitle: "Sage", arabicTitle: "أخضر رمادي", color: Color(red: 0.42, green: 0.58, blue: 0.46)),
    MedicationColorSwatch(id: "mint", englishTitle: "Mint", arabicTitle: "نعناعي", color: Color(red: 0.22, green: 0.70, blue: 0.56)),
    MedicationColorSwatch(id: "emerald", englishTitle: "Emerald", arabicTitle: "زمردي", color: Color(red: 0.15, green: 0.60, blue: 0.42)),
    MedicationColorSwatch(id: "teal", englishTitle: "Teal", arabicTitle: "أخضر مزرق", color: Color(red: 0.10, green: 0.56, blue: 0.58)),
    MedicationColorSwatch(id: "aqua", englishTitle: "Aqua", arabicTitle: "مائي", color: Color(red: 0.12, green: 0.54, blue: 0.68)),
    MedicationColorSwatch(id: "coral", englishTitle: "Coral", arabicTitle: "مرجاني", color: Color(red: 0.82, green: 0.38, blue: 0.38)),
    MedicationColorSwatch(id: "rose", englishTitle: "Rose", arabicTitle: "وردي", color: Color(red: 0.78, green: 0.32, blue: 0.46)),
    MedicationColorSwatch(id: "peach", englishTitle: "Peach", arabicTitle: "خوخي", color: Color(red: 0.82, green: 0.52, blue: 0.32)),
    MedicationColorSwatch(id: "amber", englishTitle: "Amber", arabicTitle: "عنبر", color: Color(red: 0.78, green: 0.58, blue: 0.16)),
    MedicationColorSwatch(id: "lavender", englishTitle: "Lavender", arabicTitle: "لافندر", color: Color(red: 0.52, green: 0.42, blue: 0.78)),
    MedicationColorSwatch(id: "purple", englishTitle: "Purple", arabicTitle: "بنفسجي", color: Color(red: 0.58, green: 0.36, blue: 0.76)),
    MedicationColorSwatch(id: "slate", englishTitle: "Slate", arabicTitle: "رصاصي", color: Color(red: 0.38, green: 0.44, blue: 0.52)),
    MedicationColorSwatch(id: "sand", englishTitle: "Sand", arabicTitle: "رملي", color: Color(red: 0.62, green: 0.48, blue: 0.32)),
    MedicationColorSwatch(id: "neutral", englishTitle: "Neutral", arabicTitle: "محايد", color: Color(red: 0.34, green: 0.38, blue: 0.42))
]
private let visualBackgroundSwatches = [
    MedicationColorSwatch(id: "softGreen", englishTitle: "Soft green", arabicTitle: "أخضر هادئ", color: Color(red: 0.91, green: 0.97, blue: 0.93)),
    MedicationColorSwatch(id: "softMint", englishTitle: "Soft mint", arabicTitle: "نعناعي هادئ", color: Color(red: 0.89, green: 0.97, blue: 0.94)),
    MedicationColorSwatch(id: "softTeal", englishTitle: "Soft teal", arabicTitle: "أخضر مزرق هادئ", color: Color(red: 0.88, green: 0.96, blue: 0.96)),
    MedicationColorSwatch(id: "softAqua", englishTitle: "Soft aqua", arabicTitle: "مائي هادئ", color: Color(red: 0.89, green: 0.95, blue: 0.97)),
    MedicationColorSwatch(id: "softCoral", englishTitle: "Soft coral", arabicTitle: "مرجاني هادئ", color: Color(red: 0.98, green: 0.92, blue: 0.92)),
    MedicationColorSwatch(id: "softRose", englishTitle: "Soft rose", arabicTitle: "وردي هادئ", color: Color(red: 0.98, green: 0.91, blue: 0.94)),
    MedicationColorSwatch(id: "softPeach", englishTitle: "Soft peach", arabicTitle: "خوخي هادئ", color: Color(red: 1.00, green: 0.94, blue: 0.90)),
    MedicationColorSwatch(id: "softAmber", englishTitle: "Soft amber", arabicTitle: "عنبر هادئ", color: Color(red: 1.00, green: 0.96, blue: 0.86)),
    MedicationColorSwatch(id: "softLavender", englishTitle: "Soft lavender", arabicTitle: "لافندر هادئ", color: Color(red: 0.94, green: 0.93, blue: 1.00)),
    MedicationColorSwatch(id: "softSand", englishTitle: "Soft sand", arabicTitle: "رملي هادئ", color: Color(red: 0.97, green: 0.94, blue: 0.90)),
    MedicationColorSwatch(id: "mist", englishTitle: "Mist", arabicTitle: "ضبابي", color: Color(red: 0.88, green: 0.94, blue: 0.92)),
    MedicationColorSwatch(id: "neutral", englishTitle: "Neutral", arabicTitle: "محايد", color: Color(.secondarySystemBackground)),
    MedicationColorSwatch(id: "warm", englishTitle: "Warm", arabicTitle: "دافئ", color: Color(red: 0.98, green: 0.95, blue: 0.88)),
    MedicationColorSwatch(id: "blush", englishTitle: "Blush", arabicTitle: "وردي خفيف", color: Color(red: 0.98, green: 0.92, blue: 0.93)),
    MedicationColorSwatch(id: "dark", englishTitle: "Dark", arabicTitle: "داكن", color: Color(red: 0.10, green: 0.14, blue: 0.20))
]
private let weekdayOptions = [(1, "Sun", "الأحد"), (2, "Mon", "الاثنين"), (3, "Tue", "الثلاثاء"), (4, "Wed", "الأربعاء"), (5, "Thu", "الخميس"), (6, "Fri", "الجمعة"), (7, "Sat", "السبت")].map { (id: $0.0, en: $0.1, ar: $0.2) }

private func optionTitle(_ id: String, in options: [WizardOption], isArabic: Bool) -> String {
    options.first(where: { $0.id == id })?.title(isArabic: isArabic) ?? id
}

private func unitLabel(_ id: String, isArabic: Bool) -> String {
    guard isArabic else { return id == "other" ? "Other" : id }
    switch id {
    case "units": return "وحدات"
    case "puffs": return "بخات"
    case "drops": return "قطرات"
    case "tablets": return "أقراص"
    case "capsules": return "كبسولات"
    case "doses": return "جرعات"
    case "mL": return "مل"
    case "sprays": return "رشات"
    case "patches": return "لصقات"
    case "suppositories": return "تحميلات"
    case "small amount": return "كمية صغيرة"
    case "medium amount": return "كمية متوسطة"
    case "large amount": return "كمية كبيرة"
    case "other": return "أخرى"
    default: return id
    }
}

private func localizedRoute(_ id: String, isArabic: Bool = UserDefaults.standard.string(forKey: "appearance.language") == "ar") -> String {
    guard isArabic else { return id.isEmpty ? "Not set" : id.capitalized }
    switch id {
    case "subcutaneous": return "تحت الجلد"
    case "intramuscular": return "عضلي"
    case "intravenous": return "وريدي"
    case "unknown": return "غير معروف"
    case "": return "غير محدد"
    default: return id
    }
}

private func localizedArea(_ id: String, isArabic: Bool = UserDefaults.standard.string(forKey: "appearance.language") == "ar") -> String {
    guard isArabic else { return id.isEmpty ? "Not set" : id.capitalized }
    switch id {
    case "skin": return "الجلد"
    case "eye": return "العين"
    case "ear": return "الأذن"
    case "nose": return "الأنف"
    case "oral": return "الفم"
    case "other": return "أخرى"
    case "": return "غير محدد"
    default: return id
    }
}

private func medicationSwatchColor(_ id: String) -> Color {
    visualColorSwatches.first(where: { $0.id == id })?.color ?? Color.istsehGreen
}

private func backgroundSwatchColor(_ id: String) -> Color {
    visualBackgroundSwatches.first(where: { $0.id == id })?.color ?? Color.istsehGreen.opacity(0.18)
}

private struct WizardCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        VStack(alignment: ISTSEHLayout.horizontalAlignment, spacing: 14) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: ISTSEHLayout.frameAlignment)
        .background(Color.istsehCard, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.istsehCardStroke))
    }
}

private struct StatusTag: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if !ISTSEHLayout.isArabic {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.istsehGreen)
                    .font(.title3)
            }
            VStack(alignment: ISTSEHLayout.horizontalAlignment, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(ISTSEHLayout.textAlignment)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(ISTSEHLayout.textAlignment)
            }
            Spacer(minLength: 0)
            if ISTSEHLayout.isArabic {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.istsehGreen)
                    .font(.title3)
            }
        }
        .padding(12)
        .background(Color.istsehGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct MedicationColorSwatch: Identifiable {
    let id: String
    let englishTitle: String
    let arabicTitle: String
    let color: Color

    func title(isArabic: Bool) -> String { isArabic ? arabicTitle : englishTitle }
}

private struct ColorSwatchSection: View {
    let title: String
    let swatches: [MedicationColorSwatch]
    @Binding var selection: String
    let isArabic: Bool

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.center)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 14) {
                ForEach(swatches) { swatch in
                    Button { selection = swatch.id } label: {
                        VStack(spacing: 6) {
                            Circle()
                                .fill(swatch.color)
                                .frame(width: 44, height: 44)
                                .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 1))
                                .overlay {
                                    if selection == swatch.id {
                                        Circle()
                                            .stroke(Color.istsehGreen, lineWidth: 4)
                                            .frame(width: 54, height: 54)
                                    }
                                }
                            Text(swatch.title(isArabic: isArabic))
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 74)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct VisualPreviewDock: View {
    let form: String?
    let shapeID: String
    let visualColor: String
    let visualBackgroundColor: String
    let label: String
    var size: CGFloat = 96

    var body: some View {
        VStack(spacing: 6) {
            MedicationVisualView(
                form: form,
                shapeID: shapeID,
                medicationColorID: visualColor,
                backgroundColorID: visualBackgroundColor,
                size: size
            )
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct WizardDateRow: View {
    let title: String
    @Binding var selection: Date
    let isArabic: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isArabic {
                DatePicker("", selection: $selection, displayedComponents: .date)
                    .labelsHidden()
                Spacer(minLength: 12)
                rowTitle
            } else {
                rowTitle
                Spacer(minLength: 12)
                DatePicker("", selection: $selection, displayedComponents: .date)
                    .labelsHidden()
            }
        }
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
    }

    private var rowTitle: some View {
        Text(title)
            .font(.body)
            .multilineTextAlignment(isArabic ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: isArabic ? .trailing : .leading)
    }
}

private struct WizardToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let isArabic: Bool

    var body: some View {
        HStack(spacing: 12) {
            if isArabic {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                Spacer(minLength: 12)
                rowTitle
            } else {
                rowTitle
                Spacer(minLength: 12)
                Toggle("", isOn: $isOn)
                    .labelsHidden()
            }
        }
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
    }

    private var rowTitle: some View {
        Text(title)
            .font(.body)
            .multilineTextAlignment(isArabic ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: isArabic ? .trailing : .leading)
    }
}

private struct DoseInputRow: View {
    @Binding var value: Double?
    @Binding var unit: String
    let placeholder: String
    let unitTitle: String
    let units: [String]
    let isArabic: Bool

    var body: some View {
        HStack(spacing: 10) {
            if isArabic {
                unitPicker
                numericField
            } else {
                numericField
                unitPicker
            }
        }
    }

    private var numericField: some View {
        NumericTextField(value: $value, placeholder: placeholder, allowsDecimal: true, maxFractionDigits: 2)
            .frame(height: 48)
            .padding(.horizontal, 12)
            .background(Color.istsehCard, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.istsehCardStroke))
            .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
    }

    private var unitPicker: some View {
        Picker(unitTitle, selection: $unit) {
            ForEach(units, id: \.self) { Text(unitLabel($0, isArabic: isArabic)).tag($0) }
        }
        .pickerStyle(.menu)
        .frame(minWidth: 98, minHeight: 48)
        .padding(.horizontal, 8)
        .background(Color.istsehGreen.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.istsehGreen.opacity(0.35)))
    }
}

private struct ISTSEHMedicationTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(12)
            .background(Color.istsehCard, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.istsehCardStroke))
    }
}

private struct SelectionGrid: View {
    let options: [WizardOption]
    @Binding var selection: String
    let isArabic: Bool

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(options) { option in
                Button { selection = option.id } label: {
                    VStack(spacing: 8) {
                        Image(systemName: option.systemImage).font(.title3)
                        Text(option.title(isArabic: isArabic))
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 86)
                }
                .buttonStyle(.bordered)
                .tint(selection == option.id ? .istsehGreen : .secondary)
            }
        }
    }
}

private struct SelectionList: View {
    let options: [WizardOption]
    @Binding var selection: String
    let isArabic: Bool

    var body: some View {
        VStack(spacing: 8) {
            ForEach(options) { option in
                Button { selection = option.id } label: {
                    HStack(spacing: 12) {
                        if isArabic {
                            Image(systemName: "checkmark.circle.fill")
                                .opacity(selection == option.id ? 1 : 0)
                                .frame(width: 22)
                            Text(option.title(isArabic: isArabic))
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            Image(systemName: option.systemImage)
                                .frame(width: 26)
                        } else {
                            Image(systemName: option.systemImage)
                                .frame(width: 26)
                            Text(option.title(isArabic: isArabic))
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "checkmark.circle.fill")
                                .opacity(selection == option.id ? 1 : 0)
                                .frame(width: 22)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 46)
                }
                .buttonStyle(.bordered)
                .tint(selection == option.id ? .istsehGreen : .secondary)
            }
        }
    }
}

private struct FoodRuleSelectionList: View {
    let options: [WizardOption]
    @Binding var selection: FoodRule
    let isArabic: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            ForEach(options) { option in
                let rule = FoodRule.fromStorage(option.id)
                Button {
                    selection = rule
                    onSelect()
                } label: {
                    HStack(spacing: 12) {
                        if isArabic {
                            if selection == rule {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.istsehGreen)
                            }
                            Spacer()
                            Text(option.title(isArabic: isArabic))
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.trailing)
                            Image(systemName: option.systemImage)
                                .frame(width: 26)
                                .foregroundStyle(selection == rule ? Color.istsehGreen : .secondary)
                        } else {
                            Image(systemName: option.systemImage)
                                .frame(width: 26)
                                .foregroundStyle(selection == rule ? Color.istsehGreen : .secondary)
                            Text(option.title(isArabic: isArabic))
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.leading)
                            Spacer()
                            if selection == rule {
                                Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.istsehGreen)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(minHeight: 54)
                    .background(selection == rule ? Color.istsehGreen.opacity(0.12) : Color.istsehCard, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(selection == rule ? Color.istsehGreen : Color.istsehCardStroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ChipPicker: View {
    let options: [String]
    @Binding var selection: String
    var titleProvider: (String) -> String = { $0 }

    var body: some View {
        MedicationWizardFlowLayout(spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button(titleProvider(option)) { selection = option }
                    .buttonStyle(.bordered)
                    .tint(selection == option ? .istsehGreen : .secondary)
            }
        }
    }
}

private struct MedicationWizardFlowLayout<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: spacing)], spacing: spacing) {
            content
        }
    }
}

private struct ReviewRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: ISTSEHLayout.horizontalAlignment, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(ISTSEHLayout.textAlignment)
            Text(value)
                .font(.body)
                .multilineTextAlignment(ISTSEHLayout.textAlignment)
        }
        .frame(maxWidth: .infinity, alignment: ISTSEHLayout.frameAlignment)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
