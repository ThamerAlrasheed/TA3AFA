import Foundation

// MARK: - Condition Catalog Model

struct ConditionCatalogItem: Identifiable, Hashable {
    let id: String
    let displayName: String
    let normalizedName: String
    let category: String
    let aliases: [String]
}

// MARK: - Condition Catalog

enum ConditionCatalog {

    static let categories: [String] = [
        "Metabolic",
        "Heart & Blood Pressure",
        "Respiratory",
        "Kidney & Liver",
        "Neurological",
        "Mental Health",
        "Other"
    ]

    static let items: [ConditionCatalogItem] = [

        // ── Metabolic ─────────────────────────────────────────────────────
        ConditionCatalogItem(
            id: "diabetes",
            displayName: "Diabetes",
            normalizedName: "diabetes",
            category: "Metabolic",
            aliases: ["type 1 diabetes", "type 2 diabetes", "high blood sugar", "T1D", "T2D"]
        ),
        ConditionCatalogItem(
            id: "hypertension",
            displayName: "Hypertension",
            normalizedName: "hypertension",
            category: "Metabolic",
            aliases: ["high blood pressure", "elevated blood pressure"]
        ),
        ConditionCatalogItem(
            id: "hyperlipidemia",
            displayName: "High Cholesterol",
            normalizedName: "hyperlipidemia",
            category: "Metabolic",
            aliases: ["hyperlipidemia", "dyslipidemia", "high triglycerides"]
        ),
        ConditionCatalogItem(
            id: "thyroid_disease",
            displayName: "Thyroid Disease",
            normalizedName: "thyroid_disease",
            category: "Metabolic",
            aliases: ["hypothyroidism", "hyperthyroidism", "thyroid disorder"]
        ),
        ConditionCatalogItem(
            id: "obesity",
            displayName: "Obesity",
            normalizedName: "obesity",
            category: "Metabolic",
            aliases: []
        ),

        // ── Heart & Blood Pressure ────────────────────────────────────────
        ConditionCatalogItem(
            id: "heart_disease",
            displayName: "Heart Disease",
            normalizedName: "heart_disease",
            category: "Heart & Blood Pressure",
            aliases: ["coronary artery disease", "CAD", "ischemic heart disease"]
        ),
        ConditionCatalogItem(
            id: "heart_failure",
            displayName: "Heart Failure",
            normalizedName: "heart_failure",
            category: "Heart & Blood Pressure",
            aliases: ["congestive heart failure", "CHF"]
        ),
        ConditionCatalogItem(
            id: "atrial_fibrillation",
            displayName: "Atrial Fibrillation",
            normalizedName: "atrial_fibrillation",
            category: "Heart & Blood Pressure",
            aliases: ["AFib", "AF", "irregular heartbeat"]
        ),
        ConditionCatalogItem(
            id: "stroke_history",
            displayName: "Stroke History",
            normalizedName: "stroke_history",
            category: "Heart & Blood Pressure",
            aliases: ["previous stroke", "CVA", "cerebrovascular accident"]
        ),

        // ── Respiratory ───────────────────────────────────────────────────
        ConditionCatalogItem(
            id: "asthma",
            displayName: "Asthma",
            normalizedName: "asthma",
            category: "Respiratory",
            aliases: ["bronchial asthma"]
        ),
        ConditionCatalogItem(
            id: "copd",
            displayName: "COPD",
            normalizedName: "copd",
            category: "Respiratory",
            aliases: ["chronic obstructive pulmonary disease", "emphysema", "chronic bronchitis"]
        ),
        ConditionCatalogItem(
            id: "sleep_apnea",
            displayName: "Sleep Apnea",
            normalizedName: "sleep_apnea",
            category: "Respiratory",
            aliases: ["obstructive sleep apnea", "OSA"]
        ),

        // ── Kidney & Liver ────────────────────────────────────────────────
        ConditionCatalogItem(
            id: "chronic_kidney_disease",
            displayName: "Chronic Kidney Disease",
            normalizedName: "chronic_kidney_disease",
            category: "Kidney & Liver",
            aliases: ["CKD", "kidney disease", "renal disease"]
        ),
        ConditionCatalogItem(
            id: "liver_disease",
            displayName: "Liver Disease",
            normalizedName: "liver_disease",
            category: "Kidney & Liver",
            aliases: ["hepatic disease", "cirrhosis", "hepatitis"]
        ),

        // ── Neurological ──────────────────────────────────────────────────
        ConditionCatalogItem(
            id: "epilepsy",
            displayName: "Epilepsy",
            normalizedName: "epilepsy",
            category: "Neurological",
            aliases: ["seizures", "seizure disorder"]
        ),
        ConditionCatalogItem(
            id: "parkinsons_disease",
            displayName: "Parkinson's Disease",
            normalizedName: "parkinsons_disease",
            category: "Neurological",
            aliases: ["Parkinson's", "PD"]
        ),
        ConditionCatalogItem(
            id: "dementia",
            displayName: "Dementia",
            normalizedName: "dementia",
            category: "Neurological",
            aliases: ["Alzheimer's disease", "Alzheimer's", "cognitive decline"]
        ),
        ConditionCatalogItem(
            id: "migraine",
            displayName: "Migraine",
            normalizedName: "migraine",
            category: "Neurological",
            aliases: ["migraine headaches", "chronic migraine"]
        ),

        // ── Mental Health ─────────────────────────────────────────────────
        ConditionCatalogItem(
            id: "depression",
            displayName: "Depression",
            normalizedName: "depression",
            category: "Mental Health",
            aliases: ["major depressive disorder", "MDD"]
        ),
        ConditionCatalogItem(
            id: "anxiety",
            displayName: "Anxiety",
            normalizedName: "anxiety",
            category: "Mental Health",
            aliases: ["anxiety disorder", "generalized anxiety", "GAD"]
        ),
        ConditionCatalogItem(
            id: "bipolar_disorder",
            displayName: "Bipolar Disorder",
            normalizedName: "bipolar_disorder",
            category: "Mental Health",
            aliases: ["bipolar", "manic depression"]
        ),

        // ── Other ─────────────────────────────────────────────────────────
        ConditionCatalogItem(
            id: "pregnancy",
            displayName: "Pregnancy",
            normalizedName: "pregnancy",
            category: "Other",
            aliases: ["pregnant"]
        ),
        ConditionCatalogItem(
            id: "glaucoma",
            displayName: "Glaucoma",
            normalizedName: "glaucoma",
            category: "Other",
            aliases: ["eye pressure"]
        ),
        ConditionCatalogItem(
            id: "peptic_ulcer",
            displayName: "Stomach Ulcer",
            normalizedName: "peptic_ulcer",
            category: "Other",
            aliases: ["peptic ulcer", "gastric ulcer", "duodenal ulcer"]
        ),
        ConditionCatalogItem(
            id: "gout",
            displayName: "Gout",
            normalizedName: "gout",
            category: "Other",
            aliases: ["uric acid", "gouty arthritis"]
        ),
        ConditionCatalogItem(
            id: "anemia",
            displayName: "Anemia",
            normalizedName: "anemia",
            category: "Other",
            aliases: ["iron deficiency", "low hemoglobin"]
        ),
    ]

    // MARK: - Search Helpers

    static func groupedFiltered(by query: String) -> [(category: String, items: [ConditionCatalogItem])] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let filtered: [ConditionCatalogItem]
        if q.isEmpty {
            filtered = items
        } else {
            filtered = items.filter { item in
                item.displayName.lowercased().contains(q)
                || item.normalizedName.lowercased().contains(q)
                || item.category.lowercased().contains(q)
                || item.aliases.contains { $0.lowercased().contains(q) }
            }
        }

        var seen = Set<String>()
        var order: [String] = []
        for item in filtered where !seen.contains(item.category) {
            seen.insert(item.category)
            order.append(item.category)
        }
        return order.map { cat in
            (cat, filtered.filter { $0.category == cat })
        }
    }

    static func item(named name: String) -> ConditionCatalogItem? {
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        return items.first {
            $0.displayName.lowercased() == lower
            || $0.normalizedName.lowercased() == lower
            || $0.aliases.contains { $0.lowercased() == lower }
        }
    }
}
