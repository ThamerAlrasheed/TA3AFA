import Foundation

struct FieldCandidate<Value> {
    let value: Value
    let score: Double
    let reasons: [String]
    let sourceLine: String?
    let lineIndex: Int?
}

protocol MedicationLocalAIClassifying {
    func classify(ocrResult: MedicationOCRResult) async throws -> MedicationExtractedFields
}

final class RuleBasedMedicationFieldExtractor: MedicationLocalAIClassifying {
    func classify(ocrResult: MedicationOCRResult) async throws -> MedicationExtractedFields {
        extract(from: ocrResult)
    }

    func extract(from ocrResult: MedicationOCRResult) -> MedicationExtractedFields {
        let lines = ocrResult.lines
            .map { MedicationOCRNormalizer.normalizeLine($0.text) }
            .filter { !$0.isEmpty }
        let normalizedText = lines.joined(separator: "\n")

        let strengthCandidates = Self.extractStrengthCandidates(from: lines)
        let dosageFormCandidates = Self.extractDosageFormCandidates(from: lines)
        let manufacturerCandidates = Self.extractManufacturerCandidates(from: lines)
        let activeIngredientCandidates = Self.extractActiveIngredientCandidates(from: lines)
        let brandCandidates = Self.extractMedicationNameCandidates(from: lines)

        let strength = strengthCandidates.first
        let dosageForm = dosageFormCandidates.first
        let manufacturer = manufacturerCandidates.first
        let brandName = brandCandidates.first
        let activeIngredients = Self.uniqueIngredients(from: activeIngredientCandidates)
        let genericName = Self.extractGenericName(
            from: lines,
            brandName: brandName?.value,
            activeIngredients: activeIngredients,
            strengthRawText: strength?.value.rawText
        )
        let confidence = Self.confidence(
            brand: brandName,
            generic: genericName,
            ingredients: activeIngredientCandidates,
            strength: strength,
            form: dosageForm,
            quantity: nil,
            manufacturer: manufacturer,
            usefulTextFound: Self.wordCount(normalizedText) >= 2
        )

        return MedicationExtractedFields(
            possibleBrandName: brandName?.value,
            possibleGenericName: genericName,
            possibleActiveIngredients: [],
            strengthValue: strength?.value.value,
            strengthUnit: strength?.value.unit,
            dosageForm: dosageForm?.value,
            packageQuantity: nil,
            manufacturer: manufacturer?.value,
            barcode: ocrResult.barcodes.first?.value,
            languageHints: ocrResult.detectedLanguages,
            rawWarningsText: [],
            rawDirectionsText: [],
            confidence: confidence,
            extractionMethod: "rule_based",
            needsUserConfirmation: true
        )
    }

    static func normalizeDigits(_ value: String) -> String {
        MedicationOCRNormalizer.convertArabicIndicDigits(value)
    }

    static func normalizedSearchText(_ value: String) -> String {
        MedicationOCRNormalizer.normalizeForMatching(value)
    }

    static func extractStrength(from text: String) -> (value: Double?, unit: String?, rawText: String?) {
        guard let best = extractStrengthCandidates(from: [MedicationOCRNormalizer.normalizeLine(text)]).first else {
            return (nil, nil, nil)
        }
        return (best.value.value, best.value.unit, best.value.rawText)
    }

    static func extractDosageForm(from text: String) -> String? {
        extractDosageFormCandidates(from: [MedicationOCRNormalizer.normalizeLine(text)]).first?.value
    }

    static func extractPackageQuantity(from text: String) -> String? {
        extractPackageQuantityCandidates(from: [MedicationOCRNormalizer.normalizeLine(text)]).first?.value
    }

    static func extractManufacturer(from lines: [String]) -> String? {
        extractManufacturerCandidates(from: lines.map(MedicationOCRNormalizer.normalizeLine)).first?.value
    }

    static func extractActiveIngredients(from lines: [String]) -> [String] {
        uniqueIngredients(from: extractActiveIngredientCandidates(from: lines.map(MedicationOCRNormalizer.normalizeLine)))
    }

    static func isSuspiciousMedicationName(_ value: String) -> Bool {
        let normalized = MedicationOCRNormalizer.normalizeForMatching(value)
        guard !normalized.isEmpty else { return true }
        if normalized.count < 3 { return true }
        if isOnlyNumbersOrPunctuation(normalized) { return true }
        if isMostlyNumbersOrPunctuation(normalized) { return true }
        if containsAny(normalized, terms: marketingStopPhrases + packagingStopPhrases + warningTerms + directionTerms) {
            return true
        }
        if extractStrength(from: normalized).value != nil && normalized.components(separatedBy: .whitespaces).count <= 2 {
            return true
        }
        if extractPackageQuantity(from: normalized) != nil && normalized.components(separatedBy: .whitespaces).count <= 3 {
            return true
        }
        if dosageFormMappings.contains(where: { normalized == MedicationOCRNormalizer.normalizeForMatching($0.term) }) {
            return true
        }
        if manufacturerSuffixes.contains(where: { normalized.contains(MedicationOCRNormalizer.normalizeForMatching($0)) }) {
            return true
        }
        return false
    }

    private static func extractMedicationNameCandidates(from lines: [String]) -> [FieldCandidate<String>] {
        lines.enumerated().compactMap { index, line in
            guard let value = cleanedMedicationNameCandidate(from: line) else { return nil }
            guard !isSuspiciousMedicationName(value) else { return nil }

            var score = 0.34
            var reasons = ["Contains alphabetic medication-like text"]
            if index <= 2 {
                score += 0.10
                reasons.append("Early OCR line")
            }
            if extractStrength(from: line).value != nil {
                score += 0.12
                reasons.append("Appears near strength")
            }
            if extractDosageForm(from: line) != nil {
                score += 0.08
                reasons.append("Appears near dosage form")
            }
            if adjacentLines(lines, around: index).contains(where: { extractStrength(from: $0).value != nil || extractDosageForm(from: $0) != nil }) {
                score += 0.10
                reasons.append("Adjacent to strength or form")
            }
            if line.range(of: #"\p{L}"#, options: .regularExpression) != nil {
                score += 0.08
            }
            if containsAny(line, terms: marketingStopPhrases) {
                score -= 0.30
                reasons.append("Marketing phrase penalty")
            }
            if containsAny(line, terms: packagingStopPhrases) {
                score -= 0.40
                reasons.append("Packaging phrase penalty")
            }
            if containsAny(line, terms: warningTerms + directionTerms) {
                score -= 0.35
                reasons.append("Warning or direction penalty")
            }

            guard score >= 0.42 else { return nil }
            return FieldCandidate(value: value, score: min(score, 0.92), reasons: reasons, sourceLine: line, lineIndex: index)
        }
        .sorted { $0.score > $1.score }
    }

    private static func cleanedMedicationNameCandidate(from line: String) -> String? {
        var value = line
        if let strength = extractStrength(from: value).rawText,
           let range = value.range(of: strength, options: [.caseInsensitive, .diacriticInsensitive]) {
            value = String(value[..<range.lowerBound])
        }

        value = removePackageQuantity(from: value)
        value = removeDosageWords(from: value)
        value = removeStopPhrases(from: value, phrases: marketingStopPhrases)
        value = value
            .replacingOccurrences(of: #"\b(film coated|coated)\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

        guard !value.isEmpty else { return nil }

        let words = value.split(separator: " ").map(String.init).filter { !genericStopWords.contains($0.lowercased()) }
        guard let first = words.first else { return nil }
        if lineContainsStrengthOrForm(line), words.count > 1 {
            return first
        }
        return words.joined(separator: " ")
    }

    private static func extractGenericName(
        from lines: [String],
        brandName: String?,
        activeIngredients: [String],
        strengthRawText: String?
    ) -> String? {
        if let first = activeIngredients.first { return first }

        for line in lines.prefix(6) {
            var cleaned = line
            if let strengthRawText {
                cleaned = cleaned.replacingOccurrences(of: strengthRawText, with: "", options: [.caseInsensitive, .diacriticInsensitive])
            }
            cleaned = removeDosageWords(from: cleaned)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

            guard let brandName,
                  cleaned.localizedCaseInsensitiveContains(brandName) else { continue }
            let generic = cleaned
                .replacingOccurrences(of: brandName, with: "", options: [.caseInsensitive, .diacriticInsensitive])
                .split(separator: " ")
                .map(String.init)
                .filter { !genericStopWords.contains($0.lowercased()) && !isSuspiciousMedicationName($0) }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if generic.count >= 3 { return generic }
        }
        return nil
    }

    private static func extractStrengthCandidates(from lines: [String]) -> [FieldCandidate<(value: Double, unit: String, rawText: String)>] {
        let patterns = [
            #"(?i)(\d+(?:\.\d+)?)\s*(mg|mcg|g|iu|IU)\s*/\s*(\d+(?:\.\d+)?)\s*(mL|ml|mg|mcg|g|iu|IU)"#,
            #"(?i)(\d+(?:\.\d+)?)\s*(mg|mcg|g)\s*/\s*(mL|ml)"#,
            #"(?i)(\d+(?:\.\d+)?)\s*(mg|mcg|g|iu|IU|%)(?=$|\s|[^\w])"#
        ]

        var candidates: [FieldCandidate<(value: Double, unit: String, rawText: String)>] = []
        for (index, line) in lines.enumerated() {
            for pattern in patterns {
                for match in matches(pattern: pattern, in: line) {
                    guard match.numberOfRanges >= 3 else { continue }
                    let raw = substring(line, match.range)
                    guard !isPackageQuantity(raw, line: line),
                          let value = Double(substring(line, match.range(at: 1))) else { continue }
                    let unit = normalizedStrengthUnit(from: match, in: line, raw: raw)
                    var score = 0.76
                    var reasons = ["Strength pattern matched"]
                    if containsAny(line, terms: packagingStopPhrases + warningTerms + directionTerms) {
                        score -= 0.20
                        reasons.append("Packaging or warning context penalty")
                    }
                    if containsDosageFormTerm(line) {
                        score += 0.06
                        reasons.append("Dosage form nearby")
                    }
                    candidates.append(FieldCandidate(value: (value, unit, raw), score: min(max(score, 0), 0.94), reasons: reasons, sourceLine: line, lineIndex: index))
                }
            }
        }

        return candidates.sorted { lhs, rhs in
            if lhs.score == rhs.score { return (lhs.lineIndex ?? 0) < (rhs.lineIndex ?? 0) }
            return lhs.score > rhs.score
        }
    }

    private static func extractDosageFormCandidates(from lines: [String]) -> [FieldCandidate<String>] {
        var candidates: [FieldCandidate<String>] = []
        for (index, line) in lines.enumerated() {
            let normalized = MedicationOCRNormalizer.normalizeLine(line)
                .lowercased()
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            for mapping in dosageFormMappings.sorted(by: { $0.term.count > $1.term.count }) {
                let term = MedicationOCRNormalizer.normalizeLine(mapping.term)
                    .lowercased()
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                guard containsFormTerm(normalizedLine: normalized, term: term) else { continue }
                var score = 0.72
                var reasons = ["Dosage form term matched"]
                if containsStrengthPattern(line) {
                    score += 0.06
                    reasons.append("Strength nearby")
                }
                candidates.append(FieldCandidate(value: mapping.form, score: score, reasons: reasons, sourceLine: line, lineIndex: index))
                break
            }
        }
        return candidates.sorted { $0.score > $1.score }
    }

    private static func containsFormTerm(normalizedLine: String, term: String) -> Bool {
        guard !term.isEmpty else { return false }
        if term.range(of: #"[a-z0-9]"#, options: .regularExpression) != nil {
            return normalizedLine.range(
                of: #"(^|\s)\#(NSRegularExpression.escapedPattern(for: term))($|\s)"#,
                options: .regularExpression
            ) != nil
        }
        return normalizedLine.contains(term)
    }

    private static func extractPackageQuantityCandidates(from lines: [String]) -> [FieldCandidate<String>] {
        let pattern = #"(?i)\b(\d+)\s*(tablets?|tabs?|capsules?|caps?|patches?|vials?|ampoules?|ampules?|sachets?|bottles?|unit dose|mL|ml|أقراص|قرص|كبسولات|كبسولة|أمبولات|أمبول|فيال|زجاجة|عبوة|لصقة|أكياس|كيس)\b"#
        var candidates: [FieldCandidate<String>] = []
        for (index, line) in lines.enumerated() {
            for match in matches(pattern: pattern, in: line) {
                let raw = substring(line, match.range)
                guard !isStrengthDenominator(match: match, in: line) else { continue }
                var score = 0.62
                if containsAny(raw, terms: ["tablet", "capsule", "قرص", "كبسولة", "أقراص", "كبسولات"]) { score += 0.08 }
                candidates.append(FieldCandidate(value: raw, score: score, reasons: ["Package quantity matched"], sourceLine: line, lineIndex: index))
            }
        }
        return candidates.sorted { $0.score > $1.score }
    }

    private static func extractManufacturerCandidates(from lines: [String]) -> [FieldCandidate<String>] {
        lines.enumerated().compactMap { index, line in
            let normalized = MedicationOCRNormalizer.normalizeForMatching(line)
            guard manufacturerSuffixes.contains(where: { normalized.contains(MedicationOCRNormalizer.normalizeForMatching($0)) }) else { return nil }
            return FieldCandidate(value: line, score: 0.62, reasons: ["Manufacturer/company pattern matched"], sourceLine: line, lineIndex: index)
        }
        .sorted { $0.score > $1.score }
    }

    private static func extractActiveIngredientCandidates(from lines: [String]) -> [FieldCandidate<String>] {
        let patterns = [
            #"(?i)(?:active ingredients?|contains|each tablet contains|each capsule contains|each\s+5\s*mL\s+contains|composition|generic name|ingredient|equivalent to)\s*:?\s*(.+)"#,
            #"(?i)(?:المادة الفعالة|المواد الفعالة|يحتوي كل|يحتوي|التركيب|كل قرص يحتوي|كل كبسولة تحتوي|كل 5 mL تحتوي)\s*:?\s*(.+)"#
        ]
        var candidates: [FieldCandidate<String>] = []

        for (index, line) in lines.enumerated() {
            for pattern in patterns {
                guard let match = firstMatch(pattern: pattern, in: line), match.numberOfRanges > 1 else { continue }
                let captured = cleanIngredientText(substring(line, match.range(at: 1)))
                for ingredient in splitIngredientList(captured) where ingredient.count >= 3 {
                    candidates.append(FieldCandidate(value: ingredient, score: 0.82, reasons: ["Active ingredient context matched"], sourceLine: line, lineIndex: index))
                }
            }

            if line.contains("/"), extractStrength(from: line).value != nil {
                let beforeStrength = textBeforeFirstStrength(in: line)
                for ingredient in splitIngredientList(cleanIngredientText(beforeStrength)) where ingredient.count >= 3 {
                    candidates.append(FieldCandidate(value: ingredient, score: 0.68, reasons: ["Multi-ingredient pattern matched"], sourceLine: line, lineIndex: index))
                }
            }
        }

        return candidates.sorted { $0.score > $1.score }
    }

    private static func confidence(
        brand: FieldCandidate<String>?,
        generic: String?,
        ingredients: [FieldCandidate<String>],
        strength: FieldCandidate<(value: Double, unit: String, rawText: String)>?,
        form: FieldCandidate<String>?,
        quantity: FieldCandidate<String>?,
        manufacturer: FieldCandidate<String>?,
        usefulTextFound: Bool
    ) -> MedicationFieldConfidence {
        let brandScore = brand?.score ?? 0
        let genericScore = generic == nil ? 0 : 0.64
        let ingredientScore = ingredients.first?.score ?? 0
        let strengthScore = strength?.score ?? 0
        let formScore = form?.score ?? 0
        let quantityScore = quantity?.score ?? 0
        let manufacturerScore = manufacturer?.score ?? 0
        let identityScore = max(brandScore, genericScore, ingredientScore)
        var overall = identityScore * 0.76
            + strengthScore * 0.08
            + formScore * 0.08
            + manufacturerScore * 0.04
        if usefulTextFound, overall == 0 { overall = 0.12 }

        return MedicationFieldConfidence(
            brandName: brandScore,
            genericName: genericScore,
            activeIngredients: ingredientScore,
            strength: strengthScore,
            dosageForm: formScore,
            packageQuantity: quantityScore,
            manufacturer: manufacturerScore,
            overall: min(overall, 0.92)
        )
    }

    private static func normalizedStrengthUnit(from match: NSTextCheckingResult, in line: String, raw: String) -> String {
        let firstUnit = match.numberOfRanges > 2 ? substring(line, match.range(at: 2)).lowercased() : ""
        if raw.contains("/") {
            if match.numberOfRanges > 4 {
                let denominator = substring(line, match.range(at: 3))
                let denominatorUnit = substring(line, match.range(at: 4)).lowercased()
                if denominatorUnit == "ml" { return "\(normalizeUnit(firstUnit))/\(denominator) mL" }
                return normalizeUnit(firstUnit)
            }
            return "\(normalizeUnit(firstUnit))/mL"
        }
        return normalizeUnit(firstUnit.isEmpty ? raw : firstUnit)
    }

    private static func normalizeUnit(_ value: String) -> String {
        switch value.lowercased() {
        case "ml", "مل": return "mL"
        case "iu", "وحدة": return "IU"
        case "ملجم", "مجم", "ملغ", "mg": return "mg"
        case "mcg", "µg", "ميكروغرام", "ميكروجرام": return "mcg"
        case "جم", "g": return "g"
        case "٪", "%": return "%"
        default: return value.lowercased()
        }
    }

    private static func cleanIngredientText(_ value: String) -> String {
        removeDosageWords(from: value)
            .replacingOccurrences(of: #"(?i)\b\d+(?:\.\d+)?\s*(mg|mcg|g|iu|mL|ml|%)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(on|على|من)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private static func splitIngredientList(_ value: String) -> [String] {
        value
            .replacingOccurrences(of: #"(?i)\s+(?:and|plus)\s+"#, with: " + ", options: .regularExpression)
            .components(separatedBy: CharacterSet(charactersIn: "+,،/"))
            .map { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty && !isSuspiciousMedicationName($0) }
    }

    private static func uniqueIngredients(from candidates: [FieldCandidate<String>]) -> [String] {
        var seen = Set<String>()
        var values: [String] = []
        for candidate in candidates {
            let key = MedicationOCRNormalizer.normalizeForMatching(candidate.value)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            values.append(candidate.value)
        }
        return values
    }

    private static func removeStopPhrases(from value: String, phrases: [String]) -> String {
        phrases.reduce(value) { partial, phrase in
            partial.replacingOccurrences(of: phrase, with: " ", options: [.caseInsensitive, .diacriticInsensitive])
        }
    }

    private static func removeDosageWords(from value: String) -> String {
        dosageFormMappings.reduce(value) { partial, mapping in
            partial.replacingOccurrences(of: mapping.term, with: " ", options: [.caseInsensitive, .diacriticInsensitive])
        }
    }

    private static func removePackageQuantity(from value: String) -> String {
        value.replacingOccurrences(
            of: #"(?i)\b\d+\s*(tablets?|tabs?|capsules?|caps?|patches?|vials?|ampoules?|ampules?|sachets?|bottles?|unit dose|mL|ml|أقراص|قرص|كبسولات|كبسولة|أمبولات|أمبول|فيال|زجاجة|عبوة|لصقة|أكياس|كيس)\b"#,
            with: " ",
            options: .regularExpression
        )
    }

    private static func isPackageQuantity(_ raw: String, line: String) -> Bool {
        let normalized = MedicationOCRNormalizer.normalizeForMatching(raw)
        if normalized.contains("tablet") || normalized.contains("capsule") || normalized.contains("bottle") { return true }
        if normalized.contains("قرص") || normalized.contains("كبسولة") || normalized.contains("زجاجة") { return true }
        return false
    }

    private static func isStrengthDenominator(match: NSTextCheckingResult, in line: String) -> Bool {
        guard let range = Range(match.range, in: line) else { return false }
        let prefix = String(line[..<range.lowerBound]).suffix(4)
        return prefix.contains("/")
    }

    private static func textBeforeFirstStrength(in line: String) -> String {
        guard let raw = extractStrength(from: line).rawText,
              let range = line.range(of: raw, options: [.caseInsensitive, .diacriticInsensitive]) else {
            return line
        }
        return String(line[..<range.lowerBound])
    }

    private static func lineContainsStrengthOrForm(_ value: String) -> Bool {
        extractStrength(from: value).value != nil || extractDosageForm(from: value) != nil
    }

    private static func containsStrengthPattern(_ value: String) -> Bool {
        let normalized = MedicationOCRNormalizer.normalizeLine(value)
        return firstMatch(pattern: #"(?i)\d+(?:\.\d+)?\s*(mg|mcg|g|iu|IU|%)(?=$|\s|[^\w])"#, in: normalized) != nil
            || firstMatch(pattern: #"(?i)\d+(?:\.\d+)?\s*(mg|mcg|g)\s*/\s*(?:\d+(?:\.\d+)?\s*)?(mL|ml|mg|mcg|g)"#, in: normalized) != nil
    }

    private static func containsDosageFormTerm(_ value: String) -> Bool {
        let normalized = MedicationOCRNormalizer.normalizeForMatching(value)
        return dosageFormMappings.contains { normalized.contains(MedicationOCRNormalizer.normalizeForMatching($0.term)) }
    }

    private static func adjacentLines(_ lines: [String], around index: Int) -> [String] {
        [index - 1, index + 1].compactMap { lines.indices.contains($0) ? lines[$0] : nil }
    }

    private static func isOnlyNumbersOrPunctuation(_ value: String) -> Bool {
        value.range(of: #"\p{L}"#, options: .regularExpression) == nil
    }

    private static func isMostlyNumbersOrPunctuation(_ value: String) -> Bool {
        let scalars = value.unicodeScalars.filter { !$0.properties.isWhitespace }
        guard !scalars.isEmpty else { return true }
        let nonLetters = scalars.filter { !$0.properties.isAlphabetic }.count
        return Double(nonLetters) / Double(scalars.count) > 0.65
    }

    private static func wordCount(_ text: String) -> Int {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.trimmingCharacters(in: .punctuationCharacters).isEmpty }
            .count
    }

    private static func containsAny(_ value: String, terms: [String]) -> Bool {
        let normalized = MedicationOCRNormalizer.normalizeForMatching(value)
        return terms.contains { normalized.contains(MedicationOCRNormalizer.normalizeForMatching($0)) }
    }

    private static func firstMatch(pattern: String, in text: String) -> NSTextCheckingResult? {
        matches(pattern: pattern, in: text).first
    }

    private static func matches(pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func substring(_ text: String, _ range: NSRange) -> String {
        guard let swiftRange = Range(range, in: text) else { return "" }
        return String(text[swiftRange])
    }

    private static let dosageFormMappings: [(term: String, form: String)] = [
        ("ophthalmic emulsion", "ophthalmic emulsion"),
        ("ophthalmic solution", "ophthalmic solution"),
        ("eye drops", "eye drops"),
        ("ear drops", "ear drops"),
        ("oral solution", "oral solution"),
        ("tablet", "tablet"), ("tablets", "tablet"), ("tab", "tablet"),
        ("capsule", "capsule"), ("capsules", "capsule"), ("cap", "capsule"),
        ("syrup", "syrup"), ("suspension", "suspension"), ("solution", "solution"),
        ("drops", "drops"), ("drop", "drops"), ("ophthalmic", "ophthalmic solution"),
        ("cream", "cream"), ("ointment", "ointment"), ("gel", "gel"), ("lotion", "lotion"),
        ("spray", "spray"), ("inhaler", "inhaler"), ("injection", "injection"),
        ("vial", "vial"), ("ampoule", "ampoule"), ("ampule", "ampoule"),
        ("suppository", "suppository"), ("patch", "patch"), ("sachet", "sachet"), ("powder", "powder"),
        ("قطرات للعين", "eye drops"), ("قطرات للأذن", "ear drops"), ("للأذن", "ear drops"), ("للعين", "eye drops"),
        ("أقراص", "tablet"), ("قرص", "tablet"),
        ("كبسولات", "capsule"), ("كبسولة", "capsule"),
        ("شراب", "syrup"), ("معلق", "suspension"), ("محلول", "solution"),
        ("قطرات", "drops"), ("قطرة", "drops"),
        ("كريم", "cream"), ("مرهم", "ointment"), ("جل", "gel"), ("بخاخ", "spray"),
        ("حقن", "injection"), ("فيال", "vial"), ("أمبول", "ampoule"),
        ("لبوس", "suppository"), ("لصقة", "patch"), ("كيس", "sachet"), ("مسحوق", "powder")
    ]

    private static let marketingStopPhrases = [
        "fast relief", "relief", "extra strength", "maximum strength", "new", "improved",
        "sugar free", "preservative free", "non drowsy", "once daily", "long lasting",
        "easy open", "original", "advanced", "complete", "formula", "symptoms", "symptom relief",
        "سريع المفعول", "خالي من السكر", "خالي من المواد الحافظة", "جديد",
        "تركيبة", "مفعول", "أعراض", "راحة", "طويل المفعول"
    ]

    private static let packagingStopPhrases = [
        "batch", "lot", "expiry", "exp", "mfg", "manufactured", "store below",
        "keep out of reach", "read leaflet", "unit dose", "bottle", "box", "carton",
        "التشغيلة", "تاريخ الانتهاء", "يحفظ", "بعيدا عن متناول الأطفال",
        "بعيداً عن متناول الأطفال", "النشرة الداخلية", "عبوة", "زجاجة"
    ]

    private static let warningTerms = [
        "warning", "caution", "contraindication", "keep out", "do not use",
        "تحذير", "تنبيه", "يحفظ", "موانع"
    ]

    private static let directionTerms = [
        "directions", "dosage", "take", "use as directed", "for oral use",
        "طريقة", "الجرعة", "استعمال", "يستعمل"
    ]

    private static let manufacturerSuffixes = [
        "pharma", "pharmaceutical", "laboratories", "laboratory", "labs", "company",
        "co.", "ltd", "inc", "gmbh", "s.a.", "hikma", "gsk", "pfizer", "novartis", "sanofi",
        "للصناعات الدوائية", "شركة", "فارما", "مختبرات", "الدوائية", "للأدوية"
    ]

    private static let genericStopWords: Set<String> = [
        "tablet", "tablets", "tab", "capsule", "capsules", "cap", "film", "coated",
        "syrup", "suspension", "solution", "cream", "ointment", "gel", "spray",
        "دواء", "أقراص", "قرص", "كبسولات", "كبسولة", "شراب", "معلق", "محلول"
    ]
}

final class AppleMedicationFieldExtractor: MedicationLocalAIClassifying {
    private let fallback = RuleBasedMedicationFieldExtractor()

    func classify(ocrResult: MedicationOCRResult) async throws -> MedicationExtractedFields {
        #if canImport(FoundationModels)
        // FoundationModels is intentionally not invoked until the deployment target
        // and API contract are stable in this project. The scanner remains local-first
        // by using the deterministic parser.
        #endif
        return try await fallback.classify(ocrResult: ocrResult)
    }
}

final class MedicationFieldExtractionPipeline {
    private let ruleBased: RuleBasedMedicationFieldExtractor
    private let appleClassifier: MedicationLocalAIClassifying?
    private let useAppleLocalAI: Bool

    init(
        ruleBased: RuleBasedMedicationFieldExtractor = RuleBasedMedicationFieldExtractor(),
        appleClassifier: MedicationLocalAIClassifying? = AppleMedicationFieldExtractor(),
        useAppleLocalAI: Bool = false
    ) {
        self.ruleBased = ruleBased
        self.appleClassifier = appleClassifier
        self.useAppleLocalAI = useAppleLocalAI
    }

    func extract(from ocrResult: MedicationOCRResult) async -> MedicationExtractedFields {
        if useAppleLocalAI, let appleClassifier {
            do {
                var fields = try await appleClassifier.classify(ocrResult: ocrResult)
                if fields.extractionMethod == "rule_based" {
                    fields.extractionMethod = "fallback"
                }
                return fields
            } catch {
                var fields = ruleBased.extract(from: ocrResult)
                fields.extractionMethod = "fallback"
                return fields
            }
        }
        return ruleBased.extract(from: ocrResult)
    }
}
