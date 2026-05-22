import Foundation

struct MedicationOCRNormalizer {
    static func normalizeLine(_ text: String) -> String {
        var value = convertArabicIndicDigits(text)
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        value = value
            .replacingOccurrences(of: #"[\|•·]{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[=]{1,}$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[.،,;:]{2,}"#, with: ".", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "|•·=/\\")))

        let replacements: [(String, String)] = [
            (#"(?i)\bmg\."#, "mg"),
            (#"(?i)\bml\b"#, "mL"),
            (#"(?i)\bµg\b"#, "mcg"),
            (#"(?i)\bmcg\b"#, "mcg"),
            (#"ملجم|مجم|ملغ"#, "mg"),
            (#"ميكروغرام|ميكروجرام"#, "mcg"),
            (#"(?<![ء-ي])مل(?![ء-ي])"#, "mL"),
            (#"٪"#, "%")
        ]

        for (pattern, replacement) in replacements {
            value = value.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }

        return value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func normalizeForMatching(_ text: String) -> String {
        var value = normalizeLine(text)
            .lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        let dosageReplacements: [(String, String)] = [
            (#"\btablets?\b|\btabs?\b"#, " tablet "),
            (#"\bcapsules?\b|\bcaps?\b"#, " capsule "),
            (#"\boral solution\b"#, " solution "),
            (#"\beye drops?\b|\bophthalmic solution\b|\bophthalmic emulsion\b"#, " drops "),
            (#"أقراص|قرص"#, " tablet "),
            (#"كبسولات|كبسولة"#, " capsule "),
            (#"قطرات للعين|قطرات|قطرة"#, " drops "),
            (#"شراب"#, " syrup "),
            (#"معلق"#, " suspension "),
            (#"محلول"#, " solution ")
        ]

        for (pattern, replacement) in dosageReplacements {
            value = value.replacingOccurrences(of: pattern, with: replacement, options: [.regularExpression, .caseInsensitive])
        }

        return value
            .replacingOccurrences(of: #"[^a-z0-9\u{0600}-\u{06FF}/%+. ]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func convertArabicIndicDigits(_ text: String) -> String {
        let digits = [
            "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
            "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
            "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
            "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9"
        ]

        return digits.reduce(text) { partial, pair in
            partial.replacingOccurrences(of: pair.key, with: pair.value)
        }
    }
}
