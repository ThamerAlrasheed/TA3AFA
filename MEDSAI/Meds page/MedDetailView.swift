import SwiftUI

// MARK: - Details — try catalog first, else GPT then cache
struct MedDetailView: View {
    let medName: String
    var catalogId: String?
    var med: LocalMed? = nil

    @State private var loading = true
    @State private var payload: DrugPayload?
    @State private var errorText: String?

    var headerTitle: String { med?.name ?? (payload?.title.isEmpty == false ? payload!.title : medName) }

    var body: some View {
        ZStack {
            Color.istsehPageBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: isArabic ? .trailing : .leading, spacing: 16) {
                    if loading {
                        ISTSEHCard {
                            BrandedLoadingView(
                                message: LoadingMessage.custom("Loading medication info…", "جاري تحميل معلومات الدواء…").text,
                                style: .inline
                            )
                        }
                    } else {
                        let details = payload.map { MedicationClinicalDetails(payload: $0, fallbackTitle: medName) }
                        ISTSEHCard {
                            HStack(alignment: .top, spacing: 14) {
                                MedicationVisualView(
                                    form: med?.medicationForm,
                                    shapeID: med?.visualShape,
                                    medicationColorID: med?.visualColor,
                                    backgroundColorID: med?.visualBackgroundColor,
                                    size: 58
                                )

                                VStack(alignment: isArabic ? .trailing : .leading, spacing: 10) {
                                    Text(med?.name ?? details?.displayName ?? medName)
                                        .font(.title.weight(.bold))
                                        .foregroundStyle(.primary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .multilineTextAlignment(isArabic ? .trailing : .leading)

                                    Text(statusText)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(isArabic ? .trailing : .leading)
                                }

                                Spacer(minLength: 0)
                            }

                            if let details, !details.strengths.isEmpty {
                                DetailStrengthScroll(items: details.strengths)
                                    .padding(.top, 2)
                            }
                        }

                        if let med {
                            medicationPlanSection(med)
                            refillSection(med)
                        }

                        if let p = payload, let details {
                            let ruleItems = rules(for: p)
                            if !ruleItems.isEmpty { detailSection(title: "Rules", bullets: ruleItems) }

                            detailSection(title: "What it's for", bullets: fallback(details.indicationsPatientText))
                            detailSection(title: "How to take", bullets: fallback(details.howToTakePatientText))
                            detailSection(title: "Do not mix with", bullets: fallback(details.interactionsPatientText))
                            detailSection(title: "Common side effects", bullets: fallback(details.sideEffectsPatientText))
                            detailSection(title: "Important warnings", bullets: fallback(details.warningsPatientText))
                        } else if med?.sourceType == .manual || catalogId == nil {
                            ISTSEHCard {
                                Text(noOfficialInfoText)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else if let e = errorText {
                            ContentUnavailableView("No information", systemImage: "doc.text.magnifyingglass", description: Text(e))
                                .padding(.top, 16)
                        }

                        Text("Information is for reference and does not replace medical advice.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(headerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
    }

    private func detailSection(title: String, bullets: [String]) -> some View {
        ISTSEHCard {
            InfoSection(title: title, bullets: bullets)
        }
    }

    private func medicationPlanSection(_ med: LocalMed) -> some View {
        ISTSEHCard {
            VStack(alignment: isArabic ? .trailing : .leading, spacing: 12) {
                Text(isArabic ? "خطة الدواء" : "Your medication plan")
                    .font(.headline)

                DetailPlanRow(title: isArabic ? "الشكل" : "Form", value: med.medicationForm ?? (isArabic ? "غير محدد" : "Not set"))
                if let strength = med.strengthSummary {
                    DetailPlanRow(title: isArabic ? "التركيز" : "Strength", value: strength)
                }
                DetailPlanRow(title: isArabic ? "الجرعة" : "Dose", value: med.doseDisplay ?? med.dosage)
                if let concentrationAmount = med.concentrationAmount, let concentrationUnit = med.concentrationUnit {
                    DetailPlanRow(title: isArabic ? "التركيز" : "Concentration", value: "\(concentrationAmount.formatted()) \(concentrationUnit)")
                }
                if let route = med.route, !route.isEmpty {
                    DetailPlanRow(title: isArabic ? "طريقة الاستخدام" : "Route", value: route)
                }
                if let area = med.applicationArea, !area.isEmpty {
                    DetailPlanRow(title: isArabic ? "منطقة الاستخدام" : "Application area", value: area)
                }
                DetailPlanRow(title: isArabic ? "الجدول" : "Schedule", value: med.scheduleSummary(isArabic: isArabic))
                if MedicationFormRules.shouldShowFoodTiming(formID: med.medicationForm, foodRule: med.foodRule, sourceBacked: med.foodRuleSource == "source") {
                    DetailPlanRow(title: isArabic ? "تعليمات الطعام" : "Food rule", value: med.foodRuleLabel(isArabic: isArabic))
                }
                DetailPlanRow(title: isArabic ? "المدة" : "Duration", value: durationText(for: med))
                DetailPlanRow(title: isArabic ? "التذكيرات" : "Reminders", value: med.remindersEnabled && !med.asNeeded ? (isArabic ? "مفعلة" : "On") : (isArabic ? "متوقفة" : "Off"))
                if let notes = med.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    DetailPlanRow(title: isArabic ? "ملاحظات" : "Notes", value: notes)
                }
            }
        }
    }

    private func refillSection(_ med: LocalMed) -> some View {
        ISTSEHCard {
            VStack(alignment: isArabic ? .trailing : .leading, spacing: 12) {
                Text(isArabic ? "تذكير إعادة الصرف" : "Refill reminder")
                    .font(.headline)

                if med.refillReminderEnabled {
                    if let supply = med.refillCurrentSupply {
                        DetailPlanRow(title: isArabic ? "الكمية الحالية" : "Current supply", value: "\(supply.formatted()) \(refillUnitLabel(med.refillSupplyUnit))")
                    }
                    if let threshold = med.refillThresholdQuantity {
                        DetailPlanRow(title: isArabic ? "ذكرني عندما يتبقى" : "Threshold", value: "\(threshold.formatted()) \(refillUnitLabel(med.refillSupplyUnit))")
                    }
                    if let date = med.refillReminderDate {
                        DetailPlanRow(title: isArabic ? "تاريخ التذكير" : "Reminder date", value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let notes = med.refillNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        DetailPlanRow(title: isArabic ? "ملاحظات" : "Notes", value: notes)
                    }
                } else {
                    Text(isArabic ? "تذكير إعادة الصرف متوقف" : "Refill reminder off")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func fallback(_ bullets: [String]) -> [String] {
        bullets.isEmpty ? [PatientLabelSanitizer.unavailableMessage] : bullets
    }

    private func rules(for payload: DrugPayload) -> [String] {
        let foodLabel: String? = {
            switch payload.foodRule {
            case "afterFood", "after_food": return "Take after eating"
            case "beforeFood", "before_food": return "Take before eating"
            case "withFood", "with_food": return "Take with food"
            case "none": return nil
            default: return payload.foodRule
            }
        }()

        return [foodLabel, payload.minIntervalHours.map { "Minimum interval: \($0)h" }]
            .compactMap { $0 }
    }

    private func durationText(for med: LocalMed) -> String {
        let start = med.startDate.formatted(date: .abbreviated, time: .omitted)
        let end = med.endDate.formatted(date: .abbreviated, time: .omitted)
        return "\(start) - \(end)"
    }

    private var isArabic: Bool {
        UserDefaults.standard.string(forKey: "appearance.language") == "ar"
    }

    private var statusText: String {
        med?.sourceType == .manual
            ? (isArabic ? "دواء مضاف يدويًا" : "Manual medication")
            : (isArabic ? "معلومات الدواء" : "Medication information")
    }

    private var noOfficialInfoText: String {
        isArabic
            ? "لا تتوفر معلومات رسمية لهذا الدواء المضاف يدويًا."
            : "No official drug information is available for this manually added medication."
    }

    private func refillUnitLabel(_ unit: String?) -> String {
        guard isArabic else { return unit ?? "" }
        switch unit {
        case "tablets": return "أقراص"
        case "capsules": return "كبسولات"
        case "mL": return "مل"
        case "doses": return "جرعات"
        case "puffs": return "بخات"
        case "units": return "وحدات"
        case "other": return "أخرى"
        default: return unit ?? ""
        }
    }

    private func loadFromCatalog() async -> DrugPayload? {
        struct CatalogRow: Decodable {
            let id: String
            let name: String
            let food_rule: String?
            let min_interval_hours: Int?
            let interactions_to_avoid: [String]?
            let common_side_effects: [String]?
            let how_to_take: [String]?
            let strengths: [String]?
            let what_for: [String]?
            let warnings: [String]?
            let rxcui: String?
            let active_ingredients: [String]?
        }
        do {
            var query = SupabaseManager.shared.client.from("medications").select()
            
            if let cid = catalogId {
                query = query.eq("id", value: cid)
            } else {
                query = query.ilike("name", pattern: medName)
            }
            
            let rows: [CatalogRow] = try await query
                .limit(1)
                .execute()
                .value
            
            guard let row = rows.first else { return nil }
            
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
            ).normalizedForPatientDisplay(fallbackTitle: medName)
        } catch { return nil }
    }

    private func load() async {
        loading = true; defer { loading = false }

        // 1) Try catalog by catalogId, then by medName
        if let p = await loadFromCatalog() {
            self.payload = p.normalizedForPatientDisplay(fallbackTitle: medName); return
        }

        if med?.sourceType == .manual || catalogId == nil {
            errorText = "No official drug information is available for this manually added medication."
            return
        }

        // 2) AI Fallback
        do {
            let p = try await DrugInfo.fetchDetails(name: medName)
            self.payload = p.normalizedForPatientDisplay(fallbackTitle: medName)
        } catch {
            errorText = "Could not find information for \(medName)."
        }
    }
}

private struct DetailStrengthScroll: View {
    let items: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.istsehGreen)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.istsehGreenSoft, in: Capsule())
                }
            }
            .padding(.vertical, 1)
        }
    }
}

private struct DetailPlanRow: View {
    @Environment(\.layoutDirection) private var layoutDirection
    let title: String
    let value: String

    private var isRTL: Bool { layoutDirection == .rightToLeft }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: isRTL ? .trailing : .leading)
                .multilineTextAlignment(isRTL ? .trailing : .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: isRTL ? .trailing : .leading)
                .multilineTextAlignment(isRTL ? .trailing : .leading)
        }
    }
}
