import Foundation

// MARK: - Allergy Catalog Model

struct AllergyCatalogItem: Identifiable, Hashable {
    let id: String
    let displayName: String
    let normalizedName: String
    let category: String
    let aliases: [String]
    let drugClass: String?
}

// MARK: - Allergy Catalog

enum AllergyCatalog {

    static let categories: [String] = [
        "Pain Relievers",
        "Antibiotics",
        "Other Medications",
        "Food & Other"
    ]

    static let items: [AllergyCatalogItem] = [

        // ── Pain Relievers ────────────────────────────────────────────────
        AllergyCatalogItem(
            id: "ibuprofen",
            displayName: "Ibuprofen",
            normalizedName: "ibuprofen",
            category: "Pain Relievers",
            aliases: ["Brufen", "Advil", "Motrin", "Nurofen"],
            drugClass: "nsaid"
        ),
        AllergyCatalogItem(
            id: "aspirin",
            displayName: "Aspirin",
            normalizedName: "aspirin",
            category: "Pain Relievers",
            aliases: ["ASA", "acetylsalicylic acid"],
            drugClass: "nsaid"
        ),
        AllergyCatalogItem(
            id: "naproxen",
            displayName: "Naproxen",
            normalizedName: "naproxen",
            category: "Pain Relievers",
            aliases: ["Aleve", "Naprosyn"],
            drugClass: "nsaid"
        ),
        AllergyCatalogItem(
            id: "diclofenac",
            displayName: "Diclofenac",
            normalizedName: "diclofenac",
            category: "Pain Relievers",
            aliases: ["Voltaren", "Cataflam"],
            drugClass: "nsaid"
        ),
        AllergyCatalogItem(
            id: "nsaid",
            displayName: "NSAIDs (class)",
            normalizedName: "nsaid",
            category: "Pain Relievers",
            aliases: ["NSAID", "nonsteroidal anti-inflammatory", "anti-inflammatory painkillers"],
            drugClass: "nsaid"
        ),
        AllergyCatalogItem(
            id: "acetaminophen",
            displayName: "Paracetamol / Acetaminophen",
            normalizedName: "acetaminophen",
            category: "Pain Relievers",
            aliases: ["Panadol", "Tylenol", "paracetamol"],
            drugClass: nil
        ),

        // ── Antibiotics ───────────────────────────────────────────────────
        AllergyCatalogItem(
            id: "penicillin",
            displayName: "Penicillin",
            normalizedName: "penicillin",
            category: "Antibiotics",
            aliases: ["Penicillins"],
            drugClass: "penicillin"
        ),
        AllergyCatalogItem(
            id: "amoxicillin",
            displayName: "Amoxicillin",
            normalizedName: "amoxicillin",
            category: "Antibiotics",
            aliases: ["Augmentin", "Amoxil"],
            drugClass: "penicillin"
        ),
        AllergyCatalogItem(
            id: "cephalosporin",
            displayName: "Cephalosporins",
            normalizedName: "cephalosporin",
            category: "Antibiotics",
            aliases: ["cephalexin", "cefuroxime", "ceftriaxone"],
            drugClass: "cephalosporin"
        ),
        AllergyCatalogItem(
            id: "sulfonamide",
            displayName: "Sulfa Antibiotics",
            normalizedName: "sulfonamide",
            category: "Antibiotics",
            aliases: ["sulfonamide", "sulfamethoxazole", "trimethoprim-sulfamethoxazole", "Bactrim", "Septrin"],
            drugClass: "sulfonamide"
        ),
        AllergyCatalogItem(
            id: "macrolide",
            displayName: "Macrolides",
            normalizedName: "macrolide",
            category: "Antibiotics",
            aliases: ["azithromycin", "clarithromycin", "erythromycin", "Z-Pak"],
            drugClass: "macrolide"
        ),
        AllergyCatalogItem(
            id: "fluoroquinolone",
            displayName: "Quinolones / Fluoroquinolones",
            normalizedName: "fluoroquinolone",
            category: "Antibiotics",
            aliases: ["ciprofloxacin", "levofloxacin", "moxifloxacin"],
            drugClass: "fluoroquinolone"
        ),
        AllergyCatalogItem(
            id: "tetracycline",
            displayName: "Tetracyclines",
            normalizedName: "tetracycline",
            category: "Antibiotics",
            aliases: ["doxycycline", "minocycline"],
            drugClass: "tetracycline"
        ),

        // ── Other Medications ─────────────────────────────────────────────
        AllergyCatalogItem(
            id: "insulin",
            displayName: "Insulin",
            normalizedName: "insulin",
            category: "Other Medications",
            aliases: ["insulin glargine", "insulin lispro", "Lantus", "Humalog"],
            drugClass: nil
        ),
        AllergyCatalogItem(
            id: "metformin",
            displayName: "Metformin",
            normalizedName: "metformin",
            category: "Other Medications",
            aliases: ["Glucophage"],
            drugClass: nil
        ),
        AllergyCatalogItem(
            id: "ace_inhibitor",
            displayName: "ACE Inhibitors",
            normalizedName: "ace_inhibitor",
            category: "Other Medications",
            aliases: ["lisinopril", "enalapril", "ramipril"],
            drugClass: "ace_inhibitor"
        ),
        AllergyCatalogItem(
            id: "statin",
            displayName: "Statins",
            normalizedName: "statin",
            category: "Other Medications",
            aliases: ["atorvastatin", "simvastatin", "rosuvastatin", "Lipitor", "Crestor"],
            drugClass: "statin"
        ),
        AllergyCatalogItem(
            id: "opioid",
            displayName: "Opioids",
            normalizedName: "opioid",
            category: "Other Medications",
            aliases: ["morphine", "codeine", "tramadol", "oxycodone"],
            drugClass: "opioid"
        ),
        AllergyCatalogItem(
            id: "contrast_dye",
            displayName: "Contrast Dye",
            normalizedName: "contrast_dye",
            category: "Other Medications",
            aliases: ["iodine contrast", "radiology dye"],
            drugClass: nil
        ),
        AllergyCatalogItem(
            id: "latex",
            displayName: "Latex",
            normalizedName: "latex",
            category: "Other Medications",
            aliases: [],
            drugClass: nil
        ),

        // ── Food & Other ──────────────────────────────────────────────────
        AllergyCatalogItem(
            id: "peanuts",
            displayName: "Peanuts",
            normalizedName: "peanuts",
            category: "Food & Other",
            aliases: ["groundnuts"],
            drugClass: nil
        ),
        AllergyCatalogItem(
            id: "tree_nuts",
            displayName: "Tree Nuts",
            normalizedName: "tree_nuts",
            category: "Food & Other",
            aliases: ["almonds", "cashews", "walnuts", "pistachios"],
            drugClass: nil
        ),
        AllergyCatalogItem(
            id: "shellfish",
            displayName: "Shellfish",
            normalizedName: "shellfish",
            category: "Food & Other",
            aliases: ["shrimp", "crab", "lobster"],
            drugClass: nil
        ),
        AllergyCatalogItem(
            id: "eggs",
            displayName: "Eggs",
            normalizedName: "eggs",
            category: "Food & Other",
            aliases: [],
            drugClass: nil
        ),
        AllergyCatalogItem(
            id: "milk",
            displayName: "Milk / Dairy",
            normalizedName: "milk",
            category: "Food & Other",
            aliases: ["dairy", "lactose"],
            drugClass: nil
        ),
        AllergyCatalogItem(
            id: "soy",
            displayName: "Soy",
            normalizedName: "soy",
            category: "Food & Other",
            aliases: ["soybean"],
            drugClass: nil
        ),
        AllergyCatalogItem(
            id: "wheat",
            displayName: "Wheat",
            normalizedName: "wheat",
            category: "Food & Other",
            aliases: ["gluten"],
            drugClass: nil
        ),
        AllergyCatalogItem(
            id: "sesame",
            displayName: "Sesame",
            normalizedName: "sesame",
            category: "Food & Other",
            aliases: ["tahini"],
            drugClass: nil
        ),
    ]

    // MARK: - Search Helpers

    static func groupedFiltered(by query: String) -> [(category: String, items: [AllergyCatalogItem])] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        let filtered: [AllergyCatalogItem]
        if q.isEmpty {
            filtered = items
        } else {
            filtered = items.filter { item in
                item.displayName.lowercased().contains(q)
                || item.normalizedName.lowercased().contains(q)
                || item.category.lowercased().contains(q)
                || item.aliases.contains { $0.lowercased().contains(q) }
                || (item.drugClass?.lowercased().contains(q) == true)
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

    static func item(named name: String) -> AllergyCatalogItem? {
        let lower = name.lowercased().trimmingCharacters(in: .whitespaces)
        return items.first {
            $0.displayName.lowercased() == lower
            || $0.normalizedName.lowercased() == lower
            || $0.aliases.contains { $0.lowercased() == lower }
        }
    }
}
