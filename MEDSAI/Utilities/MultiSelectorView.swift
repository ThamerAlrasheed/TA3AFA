import SwiftUI

enum MedicalProfileText {
    static var isArabic: Bool {
        UserDefaults.standard.string(forKey: "appearance.language") == "ar"
    }

    static var allergies: String { isArabic ? "الحساسية" : "Allergies" }
    static var chronicConditions: String { isArabic ? "الأمراض المزمنة" : "Chronic Conditions" }
    static var addCustomAllergy: String { isArabic ? "إضافة حساسية مخصصة" : "Add custom allergy" }
    static var addCustomCondition: String { isArabic ? "إضافة مرض مزمن مخصص" : "Add custom condition" }
    static var typeCustomAllergy: String { isArabic ? "اكتب حساسية مخصصة" : "Type a custom allergy" }
    static var typeCustomCondition: String { isArabic ? "اكتب مرضًا مزمنًا مخصصًا" : "Type a custom condition" }
    static var searchAllergies: String { isArabic ? "ابحث عن حساسية" : "Search allergies" }
    static var searchConditions: String { isArabic ? "ابحث عن مرض مزمن" : "Search chronic conditions" }
    static var noSearchResults: String { isArabic ? "لا توجد نتائج مطابقة." : "No matching results." }
    static var noAllergies: String { isArabic ? "لم تتم إضافة أي حساسية." : "No allergies added." }
    static var noConditions: String { isArabic ? "لم تتم إضافة أي أمراض مزمنة." : "No chronic conditions added." }
    static var selectAllThatApply: String { isArabic ? "اختر كل ما ينطبق" : "Select all that apply" }
    static var customPlaceholder: String { isArabic ? "اكتب اسمًا مخصصًا" : "Type a custom item" }
    static var add: String { isArabic ? "إضافة" : "Add" }
    static var remove: String { isArabic ? "إزالة" : "Remove" }
    static var medicalProfile: String { isArabic ? "الملف الطبي" : "Medical Profile" }
    static var dailyRoutine: String { isArabic ? "الروتين اليومي" : "Daily Routine" }
    static var notifications: String { isArabic ? "التذكيرات" : "Notifications" }
    static var skipForNow: String { isArabic ? "تخطي الآن" : "Skip for now" }
    static var continueText: String { isArabic ? "متابعة" : "Continue" }
    static var back: String { isArabic ? "رجوع" : "Back" }
    static var finishSetup: String { isArabic ? "إنهاء الإعداد" : "Finish setup" }
    static var comingLater: String { isArabic ? "قريبًا" : "Coming later" }
    static var premiumTitle: String { isArabic ? "مزايا رعاية إضافية قريبًا" : "More care tools are coming" }
    static var premiumSubtitle: String {
        isArabic
            ? "تنبيهات عائلية متقدمة، دعم إعادة صرف الدواء، وتنبيهات سلامة أعمق ستتوفر لاحقًا."
            : "Advanced family alerts, refill support, and deeper safety insights will be available later."
    }
    static var careTitle: String { isArabic ? "رعاية تناسب يومك" : "Care that fits your day." }
    static var careSubtitle: String {
        isArabic
            ? "اضبط روتينك وملفك الطبي والتذكيرات حتى يساعدك استصح في تنظيم أدويتك بطريقة أوضح وأكثر أمانًا."
            : "Set up your routine, medical profile, and reminders so ISTSEH can build a safer medication schedule around your life."
    }
}

struct MedicalProfileSelectionView: View {
    let title: String
    let subtitle: String
    let presets: [String]
    let searchPlaceholder: String
    let customTitle: String
    let customPlaceholder: String
    @Binding var selectedItems: [String]
    @Binding var customItem: String

    @State private var searchText = ""

    init(
        title: String,
        subtitle: String,
        presets: [String],
        searchPlaceholder: String,
        customTitle: String,
        customPlaceholder: String,
        selectedItems: Binding<[String]>,
        customItem: Binding<String> = .constant("")
    ) {
        self.title = title
        self.subtitle = subtitle
        self.presets = presets
        self.searchPlaceholder = searchPlaceholder
        self.customTitle = customTitle
        self.customPlaceholder = customPlaceholder
        self._selectedItems = selectedItems
        self._customItem = customItem
    }

    private var filteredPresets: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return presets }
        return presets.filter { item in
            item.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: MedicalProfileText.isArabic ? .trailing : .leading, spacing: 16) {
            VStack(alignment: MedicalProfileText.isArabic ? .trailing : .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(MedicalProfileText.isArabic ? .trailing : .leading)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(MedicalProfileText.isArabic ? .trailing : .leading)
            }
            .frame(maxWidth: .infinity, alignment: MedicalProfileText.isArabic ? .trailing : .leading)

            if selectedItems.isEmpty {
                Text(title == MedicalProfileText.allergies ? MedicalProfileText.noAllergies : MedicalProfileText.noConditions)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(MedicalProfileText.isArabic ? .trailing : .leading)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: MedicalProfileText.isArabic ? .trailing : .leading)
            } else {
                FlowLayout(spacing: 8, isRTL: MedicalProfileText.isArabic) {
                    ForEach(selectedItems, id: \.self) { item in
                        SelectableMedicalTag(
                            title: item,
                            isSelected: true,
                            showsRemove: true
                        ) {
                            remove(item)
                        }
                    }
                }
            }

            Divider()
                .overlay(Color.istsehCardStroke)

            MedicalSearchField(placeholder: searchPlaceholder, text: $searchText)

            if filteredPresets.isEmpty {
                Text(MedicalProfileText.noSearchResults)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                FlowLayout(spacing: 8, isRTL: MedicalProfileText.isArabic) {
                    ForEach(filteredPresets, id: \.self) { item in
                        SelectableMedicalTag(
                            title: item,
                            isSelected: contains(item),
                            showsRemove: false
                        ) {
                            toggle(item)
                        }
                    }
                }
            }

            VStack(alignment: MedicalProfileText.isArabic ? .trailing : .leading, spacing: 10) {
                Text(customTitle)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: MedicalProfileText.isArabic ? .trailing : .leading)

                CustomMedicalItemInput(
                    placeholder: customPlaceholder,
                    text: $customItem
                ) {
                    add(customItem)
                }
            }
            .padding(14)
            .background(Color.istsehPageBackground.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.istsehCardStroke, lineWidth: 1)
            )
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: MedicalProfileText.isArabic ? .trailing : .leading)
        .background(Color.istsehCard)
        .clipShape(RoundedRectangle(cornerRadius: ISTSEHSpacing.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ISTSEHSpacing.cardRadius, style: .continuous)
                .stroke(Color.istsehCardStroke, lineWidth: 1)
        )
    }

    private func contains(_ item: String) -> Bool {
        selectedItems.contains { $0.caseInsensitiveCompare(item) == .orderedSame }
    }

    private func toggle(_ item: String) {
        if contains(item) {
            remove(item)
        } else {
            add(item)
        }
    }

    private func add(_ item: String) {
        let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !contains(trimmed) else { return }
        selectedItems.append(trimmed)
        customItem = ""
    }

    private func remove(_ item: String) {
        selectedItems.removeAll { $0.caseInsensitiveCompare(item) == .orderedSame }
    }
}

struct AllergySelectionSection: View {
    @Binding var selectedItems: [String]
    var pendingCustomText: Binding<String> = .constant("")

    var body: some View {
        MedicalProfileSelectionView(
            title: MedicalProfileText.allergies,
            subtitle: MedicalProfileText.selectAllThatApply,
            presets: AllergyCatalog.items.map(\.displayName),
            searchPlaceholder: MedicalProfileText.searchAllergies,
            customTitle: MedicalProfileText.addCustomAllergy,
            customPlaceholder: MedicalProfileText.typeCustomAllergy,
            selectedItems: $selectedItems,
            customItem: pendingCustomText
        )
    }
}

struct ConditionSelectionSection: View {
    @Binding var selectedItems: [String]
    var pendingCustomText: Binding<String> = .constant("")

    var body: some View {
        MedicalProfileSelectionView(
            title: MedicalProfileText.chronicConditions,
            subtitle: MedicalProfileText.selectAllThatApply,
            presets: ConditionCatalog.items.map(\.displayName),
            searchPlaceholder: MedicalProfileText.searchConditions,
            customTitle: MedicalProfileText.addCustomCondition,
            customPlaceholder: MedicalProfileText.typeCustomCondition,
            selectedItems: $selectedItems,
            customItem: pendingCustomText
        )
    }
}

struct SelectableMedicalTag: View {
    let title: String
    let isSelected: Bool
    let showsRemove: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: showsRemove ? "xmark.circle.fill" : (isSelected ? "checkmark.circle.fill" : "plus.circle"))
                    .font(.caption.weight(.bold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? Color.istsehGreen : Color.primary)
            .background(isSelected ? Color.istsehGreenSoft : Color.istsehPageBackground.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.istsehGreen.opacity(0.45) : Color.istsehCardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(showsRemove ? MedicalProfileText.remove : MedicalProfileText.add) \(title)")
    }
}

struct CustomMedicalItemInput: View {
    let placeholder: String
    @Binding var text: String
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill")
                .foregroundStyle(Color.istsehGreen)
                .frame(width: 20)

            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .multilineTextAlignment(MedicalProfileText.isArabic ? .trailing : .leading)
                .onSubmit(onAdd)

            Button(action: onAdd) {
                Text(MedicalProfileText.add)
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.istsehGreen)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.istsehCard)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.istsehCardStroke, lineWidth: 1)
        )
    }
}

private struct MedicalSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .multilineTextAlignment(MedicalProfileText.isArabic ? .trailing : .leading)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.istsehPageBackground.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.istsehCardStroke, lineWidth: 1)
        )
    }
}

struct MultiSelectorView: View {
    let title: String
    let presets: [String]
    @Binding var selectedItems: [String]

    var body: some View {
        MedicalProfileSelectionView(
            title: title,
            subtitle: MedicalProfileText.selectAllThatApply,
            presets: presets,
            searchPlaceholder: title == MedicalProfileText.allergies ? MedicalProfileText.searchAllergies : MedicalProfileText.searchConditions,
            customTitle: title == MedicalProfileText.allergies ? MedicalProfileText.addCustomAllergy : MedicalProfileText.addCustomCondition,
            customPlaceholder: title == MedicalProfileText.allergies ? MedicalProfileText.typeCustomAllergy : MedicalProfileText.typeCustomCondition,
            selectedItems: $selectedItems,
            customItem: .constant("")
        )
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var isRTL: Bool = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if currentX + size.width > width {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
        return CGSize(width: width, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var rows: [[(LayoutSubview, CGSize)]] = [[]]
        var rowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > bounds.width, rows.last?.isEmpty == false {
                rows.append([])
                rowWidth = 0
            }
            rows[rows.count - 1].append((subview, size))
            rowWidth += size.width + spacing
        }

        var currentY = bounds.minY
        for row in rows {
            let rowHeight = row.map { $0.1.height }.max() ?? 0
            var currentX = isRTL ? bounds.maxX : bounds.minX

            for (subview, size) in row {
                if isRTL {
                    currentX -= size.width
                    subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
                    currentX -= spacing
                } else {
                    subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
                    currentX += size.width + spacing
                }
            }
            currentY += rowHeight + spacing
        }
    }
}
