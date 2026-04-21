import SwiftUI

// MARK: - Details — try catalog first, else GPT then cache
struct MedDetailView: View {
    let medName: String
    var catalogId: String?

    @State private var loading = true
    @State private var payload: DrugPayload?
    @State private var errorText: String?

    var headerTitle: String { payload?.title.isEmpty == false ? payload!.title : medName }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if loading {
                    ProgressView("Loading info…")
                } else if let p = payload {
                    Text(headerTitle).font(.largeTitle).bold().padding(.bottom, 4)

                    if !p.strengths.isEmpty { WrapChips(items: p.strengths) }

                    // Rules section with human-readable labels
                    let foodLabel: String? = {
                        switch p.foodRule {
                        case "afterFood", "after_food": return "Take after eating"
                        case "beforeFood", "before_food": return "Take before eating"
                        case "none": return nil
                        default: return p.foodRule
                        }
                    }()
                    let ruleItems = [foodLabel, p.minIntervalHours.map { "Minimum interval: \($0)h" }].compactMap { $0 }
                    if !ruleItems.isEmpty { InfoSection(title: "Rules", bullets: ruleItems) }

                    if !p.indications.isEmpty { InfoSection(title: "What it’s for", bullets: p.indications) }
                    if !p.howToTake.isEmpty { InfoSection(title: "How to take", bullets: p.howToTake) }
                    if !p.interactionsToAvoid.isEmpty { InfoSection(title: "Don’t mix with", bullets: p.interactionsToAvoid) }
                    if !p.commonSideEffects.isEmpty { InfoSection(title: "Common side effects", bullets: p.commonSideEffects) }
                    if !p.importantWarnings.isEmpty { InfoSection(title: "Important warnings", bullets: p.importantWarnings) }

                    Text("Source: AI-extracted drug information. Educational only — not medical advice.")
                        .font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                } else if let e = errorText {
                    ContentUnavailableView("No information", systemImage: "doc.text.magnifyingglass", description: Text(e))
                        .padding(.top, 16)
                }
            }
            .padding()
        }
        .navigationTitle(headerTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
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
            let rxcui: String?
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
                strengths: row.strengths ?? [],
                dosageForms: [],
                foodRule: row.food_rule,
                minIntervalHours: row.min_interval_hours,
                ingredients: [],
                indications: row.what_for ?? [],
                howToTake: row.how_to_take ?? [],
                commonSideEffects: row.common_side_effects ?? [],
                importantWarnings: [],
                interactionsToAvoid: row.interactions_to_avoid ?? [],
                references: nil,
                kbKey: nil,
                rxcui: row.rxcui,
                id: UUID(uuidString: row.id)
            )
        } catch { return nil }
    }

    private func load() async {
        loading = true; defer { loading = false }

        // 1) Try catalog by catalogId, then by medName
        if let p = await loadFromCatalog() {
            self.payload = p; return
        }

        // 2) AI Fallback
        do {
            let p = try await DrugInfo.fetchDetails(name: medName)
            self.payload = p
        } catch {
            errorText = "Could not find information for \(medName)."
        }
    }
}
