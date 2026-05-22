import SwiftUI
import Foundation

struct SearchView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var historyRepo = SearchHistoryRepo()
    @AppStorage("appearance.language") private var languageCode: String =
        Locale.current.language.languageCode?.identifier ?? "en"
    private var isArabic: Bool { languageCode == "ar" }

    @State private var query: String = ""
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var results: [SearchMedicineResult] = []
    @State private var hasSearched = false
    @State private var searchRevision = 0
    @State private var activeSearchID: UUID?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchTaskIdentity: String {
        "\(trimmedQuery.lowercased())|\(searchRevision)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.istsehPageBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        searchField

                        if trimmedQuery.isEmpty {
                            recentSection
                            idleState
                        } else if trimmedQuery.count < 3 {
                            SearchStateCard(
                                systemImage: "text.magnifyingglass",
                                title: "Keep typing",
                                message: "Enter at least 3 letters to search medicine information."
                            )
                        } else if isLoading {
                            LoadingSearchCard()
                        } else if let err = errorText {
                            SearchStateCard(
                                systemImage: "exclamationmark.triangle.fill",
                                title: "Search unavailable",
                                message: err
                            )
                        } else if !results.isEmpty {
                            resultsContent(results)
                        } else if hasSearched {
                            SearchStateCard(
                                systemImage: "magnifyingglass",
                                title: "No medicine found",
                                message: "Check the spelling or try another name."
                            )
                        } else {
                            LoadingSearchCard()
                        }

                        Spacer(minLength: 84)
                        safetyNote
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                }
                .avoidsTabBar()
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isArabic ? "البحث" : "Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if settings.role == .caregiver {
                    ToolbarItem(placement: .topBarLeading) {
                        CareProfileMenu { }
                            .environmentObject(settings)
                    }
                }
            }
            .onAppear {
                historyRepo.start(limit: 6)
            }
            .task(id: searchTaskIdentity) {
                await searchIfNeeded()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Search")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.primary)

            Text("Look up medicine information")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.istsehGreen)

            TextField("Search for a medicine", text: $query)
                .font(.body.weight(.medium))
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    errorText = nil
                    hasSearched = false
                    activeSearchID = nil
                    searchRevision += 1
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }

            if isLoading {
                ISTSEHLoadingView(message: "", style: .compact)
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
        .background(Color.istsehCard)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.istsehCardStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 4)
    }

    @ViewBuilder
    private var recentSection: some View {
        if !historyRepo.recent.isEmpty {
            SearchChipSection(title: "Recently searched") {
                SearchChipWrap(items: Array(historyRepo.recent.prefix(6))) { value in
                    runChipSearch(value)
                }
            }
        }
    }

    @ViewBuilder
    private var idleState: some View {
        if historyRepo.recent.isEmpty {
            SearchIntroState()
                .padding(.top, 42)
        } else {
            SearchSupportNote()
                .padding(.top, 4)
        }
    }

    private func resultsContent(_ results: [SearchMedicineResult]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(results.count == 1 ? "Result" : "Results")
                .font(.headline)
                .foregroundStyle(.primary)

            ForEach(results) { result in
                NavigationLink {
                    MedDetailView(
                        medName: result.payload.title,
                        catalogId: result.payload.id?.uuidString
                    )
                } label: {
                    MedicineResultCard(result: result, fallbackTitle: trimmedQuery)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var safetyNote: some View {
        Text("Information is for reference and does not replace medical advice.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 10)
            .padding(.horizontal, 18)
    }

    private func runChipSearch(_ value: String) {
        query = value
        searchRevision += 1
    }

    private func readableFoodRule(_ value: String?) -> String? {
        switch value {
        case "afterFood", "after_food":
            return "Take after eating"
        case "beforeFood", "before_food":
            return "Take before eating"
        case "withFood", "with_food":
            return "Take with food"
        case "none", nil:
            return nil
        default:
            return value
        }
    }

    private func searchIfNeeded() async {
        let trimmed = trimmedQuery
        guard trimmed.count >= 3 else {
            results = []
            errorText = nil
            hasSearched = false
            isLoading = false
            activeSearchID = nil
            return
        }

        let searchID = UUID()
        activeSearchID = searchID

        do {
            try await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, activeSearchID == searchID, trimmed == trimmedQuery else { return }

            isLoading = true
            errorText = nil
            hasSearched = false
            results = []
            defer {
                if activeSearchID == searchID {
                    isLoading = false
                }
            }

            let catalogResults = (try? await searchCatalog(for: trimmed)) ?? []
            guard !Task.isCancelled, activeSearchID == searchID, trimmed == trimmedQuery else { return }

            if catalogResults.isEmpty {
                let payload = try await DrugInfo.fetchDetails(name: trimmed)
                guard !Task.isCancelled, activeSearchID == searchID, trimmed == trimmedQuery else { return }
                results = [
                    SearchMedicineResult(
                        payload: payload.normalizedForPatientDisplay(fallbackTitle: trimmed),
                        source: .details
                    )
                ]
            } else {
                results = catalogResults
            }
            hasSearched = true
            await historyRepo.add(query: trimmed)
            historyRepo.start(limit: 6)
        } catch is CancellationError {
            // Normal behavior during typing, do nothing.
        } catch {
            guard activeSearchID == searchID else { return }
            errorText = "Couldn't fetch drug info. \(error.localizedDescription)"
            results = []
            hasSearched = true
        }
    }

    private func searchCatalog(for query: String) async throws -> [SearchMedicineResult] {
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

        let rows: [CatalogRow] = try await SupabaseManager.shared.client
            .from("medications")
            .select("id,name,food_rule,min_interval_hours,interactions_to_avoid,common_side_effects,how_to_take,strengths,what_for,warnings,rxcui,active_ingredients")
            .ilike("name", pattern: "%\(query)%")
            .order("name", ascending: true)
            .limit(12)
            .execute()
            .value

        let payloads = rows.map { row in
            DrugPayload(
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

        return MedicationSearchDeduplicator.deduplicate(payloads).map { payload in
            return SearchMedicineResult(payload: payload, source: .catalog)
        }
    }
}

private struct SearchChipSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            content
        }
    }
}

private struct SearchChipWrap: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        FlexibleWrap(items: items) { item in
            Button {
                onTap(item)
            } label: {
                Label(item, systemImage: "pills.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.istsehGreen)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(Color.istsehGreenSoft, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SearchIntroState: View {
    var body: some View {
        VStack(spacing: 16) {
            ISTSEHIconBadge(systemName: "magnifyingglass")
                .scaleEffect(1.18)

            VStack(spacing: 6) {
                Text("Search for a medicine")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text("Find usage, side effects, and safety information.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 38)
    }
}

private struct SearchSupportNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.headline)
                .foregroundStyle(Color.istsehGreen)
            Text("Select a recent search or type a medicine name to look up usage, side effects, and safety information.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.istsehCard.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct SearchStateCard: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        SearchSurface {
            VStack(spacing: 14) {
                ISTSEHIconBadge(systemName: systemImage)
                    .scaleEffect(1.3)
                    .padding(.bottom, 4)

                Text(title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
    }
}

private struct LoadingSearchCard: View {
    @AppStorage("appearance.language") private var languageCode: String =
        Locale.current.language.languageCode?.identifier ?? "en"

    var body: some View {
        SearchSurface {
            ISTSEHLoadingView(
                message: languageCode == "ar" ? "جاري البحث" : "Searching",
                style: .inline
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SearchMedicineResult: Identifiable {
    let payload: DrugPayload
    let source: SearchResultSource

    var id: String {
        MedicationSearchDeduplicator.resultKey(
            title: payload.title,
            strengths: payload.strengths,
            dosageForms: payload.dosageForms,
            rxcui: payload.rxcui,
            sourceID: payload.id?.uuidString
        )
    }
}

private enum SearchResultSource {
    case catalog
    case details
}

private struct MedicineResultCard: View {
    let result: SearchMedicineResult
    let fallbackTitle: String

    private var payload: DrugPayload { result.payload }

    private var displayTitle: String {
        payload.title.isEmpty ? fallbackTitle : payload.title
    }

    private var summary: String? {
        payload.indications.first ?? payload.howToTake.first
    }

    private var strengthItems: [String] {
        Array(MedicationStrengthFormatter.displayableStrengths(from: payload.strengths + payload.dosageForms).prefix(6))
    }

    var body: some View {
        SearchSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ISTSEHIconBadge(systemName: "pills.fill")

                    VStack(alignment: .leading, spacing: 6) {
                        Text(displayTitle)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.primary)

                        if let summary {
                            Text(summary)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }

                if !strengthItems.isEmpty {
                    SearchTagWrap(items: strengthItems)
                }

            }
        }
    }
}

private struct SearchInfoCard<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        SearchSurface {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .foregroundStyle(.primary)
                content
            }
        }
    }
}

private struct SearchBulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items.prefix(4), id: \.self) { item in
                SearchBullet(text: item)
            }
        }
    }
}

private struct SearchBullet: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.istsehGreen)
                .frame(width: 6, height: 6)
                .padding(.top, 8)
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SearchTagWrap: View {
    let items: [String]

    var body: some View {
        FlexibleWrap(items: items, horizontalSpacing: 8, verticalSpacing: 8) { item in
            Text(item)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.istsehGreen)
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background(Color.istsehGreenSoft, in: Capsule())
        }
    }
}

private struct SearchBadgeModel: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
}

private struct SearchBadge: View {
    let model: SearchBadgeModel

    var body: some View {
        Label(model.title, systemImage: model.systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.istsehGreen)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.istsehGreenSoft, in: Capsule())
    }
}

private struct SearchSurface<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.istsehCard)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.istsehCardStroke, lineWidth: 1)
        )
        .shadow(
            color: colorScheme == .dark ? .clear : Color.istsehGreen.opacity(0.08),
            radius: 14,
            x: 0,
            y: 8
        )
    }
}
