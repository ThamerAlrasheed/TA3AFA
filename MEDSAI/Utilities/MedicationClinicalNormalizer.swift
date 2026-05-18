import Foundation

struct MedicationClinicalDetails: Codable {
    let displayName: String
    let genericName: String?
    let activeIngredients: [String]
    let inactiveIngredients: [String]
    let strengths: [String]
    let dosageForms: [String]
    let routes: [String]
    let indicationsPatientText: [String]
    let howToTakePatientText: [String]
    let sideEffectsPatientText: [String]
    let warningsPatientText: [String]
    let interactionsPatientText: [String]
    let sourceMetadata: [String]
    let lastUpdated: Date?
    let confidence: Double
    let needsReview: Bool

    init(payload: DrugPayload, fallbackTitle: String? = nil) {
        let title = PatientLabelSanitizer.cleanTitle(payload.title).flatMap { $0.isEmpty ? nil : $0 }
            ?? PatientLabelSanitizer.cleanTitle(fallbackTitle ?? "")
            ?? "Medication"

        self.displayName = title
        self.genericName = nil
        self.activeIngredients = PatientLabelSanitizer.cleanShortList(payload.ingredients)
        self.inactiveIngredients = []
        self.strengths = MedicationStrengthFormatter.displayableStrengths(from: payload.strengths)
        self.dosageForms = PatientLabelSanitizer.cleanShortList(payload.dosageForms)
        self.routes = []
        self.indicationsPatientText = PatientLabelSanitizer.cleanBullets(from: payload.indications, max: 4)
        self.howToTakePatientText = PatientLabelSanitizer.cleanBullets(from: payload.howToTake, max: 5)
        self.sideEffectsPatientText = PatientLabelSanitizer.cleanBullets(from: payload.commonSideEffects, max: 5)
        self.warningsPatientText = PatientLabelSanitizer.cleanBullets(from: payload.importantWarnings, max: 5)
        self.interactionsPatientText = PatientLabelSanitizer.cleanBullets(from: payload.interactionsToAvoid, max: 4)
        self.sourceMetadata = payload.references ?? []
        self.lastUpdated = nil
        self.confidence = payload.rxcui == nil ? 0.72 : 0.9
        self.needsReview = payload.rxcui == nil
    }
}

enum PatientLabelSanitizer {
    static let unavailableMessage = "No reliable information found from the selected source."

    private static let sectionHeadings = [
        "BOXED WARNING",
        "INDICATIONS AND USAGE",
        "DOSAGE AND ADMINISTRATION",
        "DOSAGE FORMS AND STRENGTHS",
        "CONTRAINDICATIONS",
        "WARNINGS AND PRECAUTIONS",
        "WARNINGS",
        "PRECAUTIONS",
        "ADVERSE REACTIONS",
        "DRUG INTERACTIONS",
        "USE IN SPECIFIC POPULATIONS",
        "OVERDOSAGE",
        "DESCRIPTION",
        "CLINICAL PHARMACOLOGY",
        "NONCLINICAL TOXICOLOGY",
        "CLINICAL STUDIES",
        "HOW SUPPLIED/STORAGE AND HANDLING",
        "PATIENT COUNSELING INFORMATION",
        "INFORMATION FOR PATIENTS",
        "MEDICATION GUIDE"
    ]

    private static var sectionHeadingPattern: String {
        sectionHeadings
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
    }

    static func cleanTitle(_ raw: String) -> String? {
        cleanText(raw, maxCharacters: 120)
    }

    static func cleanText(_ raw: String, maxCharacters: Int = 320) -> String? {
        var value = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "•", with: "\n• ")
            .replacingOccurrences(of: "·", with: "\n• ")
            .replacingOccurrences(of: "‣", with: "\n• ")

        guard !value.isEmpty else { return nil }

        value = value
            .replacingOccurrences(
                of: #"(?i)\berror!\s*hyperlink reference not valid\.?"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)\breference id:\s*[a-z0-9\-]+"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)\bsee\s+(?:warnings and precautions|adverse reactions|drug interactions|clinical studies|full prescribing information)\s*\([^)]+\)"#,
                with: " ",
                options: .regularExpression
            )

        let headingPattern = #"(?im)(^|[\n.;])\s*(?:\d+(?:\.\d+)?\s+)?(?:"# + sectionHeadingPattern + #")\b\s*[:.\-–—]?\s*"#
        value = value.replacingOccurrences(of: headingPattern, with: "$1", options: .regularExpression)

        value = value
            .replacingOccurrences(
                of: #"(?m)(^|\n)\s*(?:[-*•]\s*)?(?:\d+\s*\)\]\s*|\(?\d+(?:\.\d+)?\)?[\].)]\s*)"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?m)(^|\n)\s*[-*•]+\s*"#,
                with: "$1",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\n{2,}"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        value = stripDanglingPunctuation(value)
        guard isUseful(value) else { return nil }

        if value.count > maxCharacters {
            value = String(value.prefix(maxCharacters))
            if let lastSentence = value.lastIndex(where: { ".;:".contains($0) }) {
                value = String(value[...lastSentence])
            } else if let lastSpace = value.lastIndex(of: " ") {
                value = String(value[..<lastSpace]) + "..."
            }
        }

        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func cleanBullets(from rawValues: [String], max: Int = 5) -> [String] {
        var output: [String] = []
        var seen = Set<String>()

        for raw in rawValues {
            for candidate in bulletCandidates(from: raw) {
                guard let clean = cleanText(candidate, maxCharacters: 180) else { continue }
                guard !isSourceBoilerplate(clean) else { continue }

                let key = canonicalKey(clean)
                guard seen.insert(key).inserted else { continue }

                output.append(clean)
                if output.count >= max { return output }
            }
        }

        return output
    }

    static func cleanShortList(_ rawValues: [String]) -> [String] {
        var output: [String] = []
        var seen = Set<String>()

        for raw in rawValues {
            guard let clean = cleanText(raw, maxCharacters: 90) else { continue }
            let key = canonicalKey(clean)
            guard seen.insert(key).inserted else { continue }
            output.append(clean)
        }

        return output
    }

    static func fallbackBullets(_ rawValues: [String], max: Int = 5) -> [String] {
        let clean = cleanBullets(from: rawValues, max: max)
        return clean.isEmpty ? [unavailableMessage] : clean
    }

    private static func bulletCandidates(from raw: String) -> [String] {
        let prepared = raw
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: #"(?m)\s+(?=\d+\s*\)\])"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)\s+(?=\(?\d+\)?[\].)]\s+[A-Z])"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"[-*]\s*•"#, with: "\n•", options: .regularExpression)
            .replacingOccurrences(of: "•", with: "\n• ")
            .replacingOccurrences(of: "·", with: "\n• ")
            .replacingOccurrences(of: "‣", with: "\n• ")

        let lineParts = prepared
            .components(separatedBy: .newlines)
            .flatMap { $0.components(separatedBy: ";") }

        var candidates: [String] = []
        for part in lineParts {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.count > 220 {
                candidates.append(contentsOf: trimmed
                    .replacingOccurrences(of: #"\.\s+"#, with: ".\n", options: .regularExpression)
                    .components(separatedBy: .newlines))
            } else {
                candidates.append(trimmed)
            }
        }

        return candidates
    }

    private static func stripDanglingPunctuation(_ value: String) -> String {
        var out = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while out.first.map({ ":;,-–—.".contains($0) }) == true {
            out.removeFirst()
            out = out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return out
    }

    private static func isUseful(_ value: String) -> Bool {
        let lower = value.lowercased()
        guard value.count >= 3 else { return false }
        guard !lower.contains("error! hyperlink reference not valid") else { return false }
        guard lower.range(of: #"^reference id:"#, options: .regularExpression) == nil else { return false }
        guard lower.range(of: #"^(?:\d+|\d+\.\d+)$"#, options: .regularExpression) == nil else { return false }
        guard lower.range(of: #"^(?:table|figure)\s+\d+"#, options: .regularExpression) == nil else { return false }
        return true
    }

    private static func isSourceBoilerplate(_ value: String) -> Bool {
        let lower = value.lowercased()
        let patterns = [
            #"^the following clinically significant adverse reactions"#,
            #"^because clinical trials are conducted"#,
            #"^the data described below reflect"#,
            #"^to report suspected adverse reactions"#,
            #"^see full prescribing information"#,
            #"^see warnings and precautions"#,
            #"^these highlights do not include all the information"#
        ]

        return patterns.contains { lower.range(of: $0, options: .regularExpression) != nil }
    }

    private static func canonicalKey(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum MedicationSearchDeduplicator {
    static func deduplicate(_ payloads: [DrugPayload]) -> [DrugPayload] {
        var seen = Set<String>()
        var output: [DrugPayload] = []

        for payload in payloads {
            let normalized = payload.normalizedForPatientDisplay()
            let key = resultKey(
                title: normalized.title,
                strengths: normalized.strengths,
                dosageForms: normalized.dosageForms,
                rxcui: normalized.rxcui,
                sourceID: normalized.id?.uuidString
            )
            guard seen.insert(key).inserted else { continue }
            output.append(normalized)
        }

        return output
    }

    static func resultKey(
        title: String,
        strengths: [String],
        dosageForms: [String],
        rxcui: String?,
        sourceID: String?
    ) -> String {
        _ = sourceID
        let nameKey = title
            .lowercased()
            .replacingOccurrences(of: #"[^a-z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let strengthKey = MedicationStrengthFormatter.displayableStrengths(from: strengths)
            .map { $0.lowercased() }
            .sorted()
            .joined(separator: "|")
        let formKey = PatientLabelSanitizer.cleanShortList(dosageForms)
            .map { $0.lowercased() }
            .sorted()
            .joined(separator: "|")

        return [
            rxcui?.lowercased(),
            nameKey,
            strengthKey,
            formKey
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        .joined(separator: "::")
    }
}

extension DrugPayload {
    func normalizedForPatientDisplay(fallbackTitle: String? = nil) -> DrugPayload {
        let details = MedicationClinicalDetails(payload: self, fallbackTitle: fallbackTitle)
        return DrugPayload(
            title: details.displayName,
            strengths: details.strengths,
            dosageForms: details.dosageForms,
            foodRule: foodRule,
            minIntervalHours: minIntervalHours,
            ingredients: details.activeIngredients,
            indications: details.indicationsPatientText,
            howToTake: details.howToTakePatientText,
            commonSideEffects: details.sideEffectsPatientText,
            importantWarnings: details.warningsPatientText,
            interactionsToAvoid: details.interactionsPatientText,
            references: references,
            kbKey: kbKey,
            rxcui: rxcui,
            id: id
        )
    }
}
