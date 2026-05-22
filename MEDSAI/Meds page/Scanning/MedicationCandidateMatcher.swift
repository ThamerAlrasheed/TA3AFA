import Foundation

protocol MedicationCandidateMatching {
    func findCandidates(for extracted: MedicationExtractedFields) async throws -> [MedicationScanCandidate]
}

final class MedicationCandidateMatcher: MedicationCandidateMatching {
    struct CatalogRow: Decodable, Hashable {
        let id: String
        let name: String
        let strengths: [String]?
        let active_ingredients: [String]?
        let rxcui: String?
        let barcode_values: [String]?
        let brand_aliases: [String]?
        let generic_aliases: [String]?
        let normalized_brand_name: String?
        let normalized_generic_name: String?
        let normalized_strength: String?
        let dosage_form_normalized: String?
        let manufacturer_normalized: String?
    }

    struct LegacyCatalogRow: Decodable {
        let id: String
        let name: String
        let strengths: [String]?
        let active_ingredients: [String]?
        let rxcui: String?
    }

    private let supabase: SupabaseManager

    init(supabase: SupabaseManager = .shared) {
        self.supabase = supabase
    }

    func findCandidates(for extracted: MedicationExtractedFields) async throws -> [MedicationScanCandidate] {
        var rows = Set<CatalogRow>()

        if let barcode = extracted.barcode?.trimmingCharacters(in: .whitespacesAndNewlines), !barcode.isEmpty {
            rows.formUnion(try await searchBarcode(barcode))
        }

        for term in searchTerms(from: extracted) {
            rows.formUnion(try await search(column: "name", term: term))
            rows.formUnion(try await search(column: "normalized_brand_name", term: Self.normalize(term)))
            rows.formUnion(try await search(column: "normalized_generic_name", term: Self.normalize(term)))
        }

        let candidates = rows.map { Self.score(row: $0, extracted: extracted) }
            .filter { $0.matchScore > 0.05 }
            .sorted { lhs, rhs in
                if lhs.matchScore == rhs.matchScore { return lhs.brandName < rhs.brandName }
                return lhs.matchScore > rhs.matchScore
            }

        return Array(candidates.prefix(5))
    }

    static func score(row: CatalogRowLike, extracted: MedicationExtractedFields) -> MedicationScanCandidate {
        let candidateBrand = row.name
        let candidateBrandNormalized = normalize(candidateBrand)
        let brandNormalized = extracted.possibleBrandName.map(normalize)
        let genericNormalized = extracted.possibleGenericName.map(normalize)
        let ingredientNormalized = extracted.possibleActiveIngredients.map(normalize)
        let strengthText = strengthString(value: extracted.strengthValue, unit: extracted.strengthUnit)
        let strengthNormalized = strengthText.map(normalizeStrength)
        let candidateStrengths = row.strengthValues.map(normalizeStrength)
        let candidateIngredients = row.activeIngredients.map(normalize)
        let candidateAliases = (row.brandAliases + row.genericAliases).map(normalize)
        let candidateGeneric = row.genericAliases.first ?? row.activeIngredients.first
        var identityScore = 0.0
        var supportScore = 0.0
        var reasons: [String] = []

        if let barcode = extracted.barcode, row.barcodeValues.contains(where: { normalize($0) == normalize(barcode) }) {
            identityScore += 0.75
            reasons.append("Barcode matched")
        }

        if let brandNormalized {
            if candidateBrandNormalized == brandNormalized || candidateAliases.contains(brandNormalized) {
                identityScore += 0.50
                reasons.append("Brand name matched")
            } else if candidateBrandNormalized.hasPrefix(brandNormalized)
                        || brandNormalized.hasPrefix(candidateBrandNormalized)
                        || candidateBrandNormalized.contains(brandNormalized)
                        || candidateAliases.contains(where: { $0.contains(brandNormalized) || brandNormalized.contains($0) }) {
                identityScore += 0.30
                reasons.append("Brand name matched")
            }
        }

        if let genericNormalized,
           candidateIngredients.contains(genericNormalized) || candidateAliases.contains(genericNormalized) {
            identityScore += 0.35
            reasons.append("Generic name matched")
        }

        if !ingredientNormalized.isEmpty,
           !Set(ingredientNormalized).isDisjoint(with: Set(candidateIngredients + candidateAliases)) {
            identityScore += 0.30
            reasons.append("Active ingredient matched")
        }

        if let strengthNormalized,
           candidateStrengths.contains(where: { $0 == strengthNormalized || $0.contains(strengthNormalized) || strengthNormalized.contains($0) }) {
            supportScore += 0.20
            reasons.append("Strength matched")
        }

        if let form = extracted.dosageForm.map(normalize),
           row.dosageFormNormalized.map(normalize) == form || row.strengthValues.map(normalize).contains(where: { $0.contains(form) }) {
            supportScore += 0.08
            reasons.append("Dosage form matched")
        }

        if let manufacturer = extracted.manufacturer.map(normalize),
           row.manufacturerNormalized.map(normalize)?.contains(manufacturer) == true {
            supportScore += 0.03
            reasons.append("Manufacturer matched")
        }

        var normalizedScore = min(identityScore + supportScore, 1.0)
        if identityScore == 0 {
            normalizedScore = min(normalizedScore, 0.35)
        } else if identityScore < 0.35 {
            normalizedScore = min(normalizedScore, 0.55)
        }

        return MedicationScanCandidate(
            medicationId: UUID(uuidString: row.id),
            brandName: candidateBrand,
            genericName: candidateGeneric,
            activeIngredients: row.activeIngredients,
            strength: row.strengthValues.first,
            dosageForm: row.dosageFormNormalized ?? extracted.dosageForm,
            manufacturer: row.manufacturerNormalized,
            matchScore: normalizedScore,
            matchReasons: reasons.isEmpty ? ["Catalog candidate"] : reasons,
            source: "supabase_catalog",
            requiresConfirmation: true
        )
    }

    static func normalize(_ value: String) -> String {
        MedicationOCRNormalizer.normalizeForMatching(value)
            .replacingOccurrences(of: #"\b(tablets?|tabs?|capsules?|caps?|film coated|أقراص|قرص|كبسولات|كبسولة)\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizeStrength(_ value: String) -> String {
        normalize(value)
            .replacingOccurrences(of: "milligram", with: "mg")
            .replacingOccurrences(of: "microgram", with: "mcg")
            .replacingOccurrences(of: "ملجم", with: "mg")
            .replacingOccurrences(of: "مجم", with: "mg")
            .replacingOccurrences(of: "ملغ", with: "mg")
            .replacingOccurrences(of: "مل", with: "ml")
            .replacingOccurrences(of: " ml", with: " ml")
    }

    static func strengthString(value: Double?, unit: String?) -> String? {
        guard let value, let unit, !unit.isEmpty else { return nil }
        let number = value.rounded() == value ? String(Int(value)) : String(value)
        return "\(number) \(unit)"
    }

    private func searchTerms(from extracted: MedicationExtractedFields) -> [String] {
        var terms: [String] = []
        [extracted.possibleBrandName, extracted.possibleGenericName].compactMap { $0 }.forEach { terms.append($0) }
        terms.append(contentsOf: extracted.possibleActiveIngredients)
        return Array(Set(terms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.count >= 3 }))
            .prefix(6)
            .map { String($0) }
    }

    private func search(column: String, term: String) async throws -> [CatalogRow] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return [] }
        do {
            let rows: [CatalogRow] = try await supabase.retry {
                try await self.supabase.client
                    .from("medications")
                    .select(self.extendedSelect)
                    .ilike(column, pattern: "%\(trimmed)%")
                    .limit(8)
                    .execute()
                    .value
            }
            return rows
        } catch {
            guard column == "name" else { return [] }
            let legacy: [LegacyCatalogRow] = try await supabase.retry {
                try await self.supabase.client
                    .from("medications")
                    .select(self.legacySelect)
                    .ilike("name", pattern: "%\(trimmed)%")
                    .limit(8)
                    .execute()
                    .value
            }
            return legacy.map(CatalogRow.init(legacy:))
        }
    }

    private func searchBarcode(_ barcode: String) async throws -> [CatalogRow] {
        do {
            let rows: [CatalogRow] = try await supabase.retry {
                try await self.supabase.client
                    .from("medications")
                    .select(self.extendedSelect)
                    .contains("barcode_values", value: [barcode])
                    .limit(5)
                    .execute()
                    .value
            }
            return rows
        } catch {
            return []
        }
    }

    private var extendedSelect: String {
        "id,name,strengths,active_ingredients,rxcui,barcode_values,brand_aliases,generic_aliases,normalized_brand_name,normalized_generic_name,normalized_strength,dosage_form_normalized,manufacturer_normalized"
    }

    private var legacySelect: String {
        "id,name,strengths,active_ingredients,rxcui"
    }
}

protocol CatalogRowLike {
    var id: String { get }
    var name: String { get }
    var strengthValues: [String] { get }
    var activeIngredients: [String] { get }
    var barcodeValues: [String] { get }
    var brandAliases: [String] { get }
    var genericAliases: [String] { get }
    var dosageFormNormalized: String? { get }
    var manufacturerNormalized: String? { get }
}

extension MedicationCandidateMatcher.CatalogRow: CatalogRowLike {
    var strengthValues: [String] { strengths ?? [] }
    var activeIngredients: [String] { active_ingredients ?? [] }
    var barcodeValues: [String] { barcode_values ?? [] }
    var brandAliases: [String] { brand_aliases ?? [] }
    var genericAliases: [String] { generic_aliases ?? [] }
    var dosageFormNormalized: String? { dosage_form_normalized }
    var manufacturerNormalized: String? { manufacturer_normalized }
}

private extension MedicationCandidateMatcher.CatalogRow {
    init(legacy: MedicationCandidateMatcher.LegacyCatalogRow) {
        self.init(
            id: legacy.id,
            name: legacy.name,
            strengths: legacy.strengths,
            active_ingredients: legacy.active_ingredients,
            rxcui: legacy.rxcui,
            barcode_values: nil,
            brand_aliases: nil,
            generic_aliases: nil,
            normalized_brand_name: nil,
            normalized_generic_name: nil,
            normalized_strength: nil,
            dosage_form_normalized: nil,
            manufacturer_normalized: nil
        )
    }
}
