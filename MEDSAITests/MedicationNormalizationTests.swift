import XCTest
@testable import MEDSAI

final class MedicationNormalizationTests: XCTestCase {
    func testSanitizerRemovesColchicineArtifacts() {
        let raw = """
        5 WARNINGS AND PRECAUTIONS Error! Hyperlink reference not valid.
        Serious adverse reactions may occur with colchicine toxicity.
        Reference ID: 123456
        """

        let clean = PatientLabelSanitizer.cleanText(raw)

        XCTAssertNotNil(clean)
        XCTAssertFalse(clean?.contains("WARNINGS AND PRECAUTIONS") ?? true)
        XCTAssertFalse(clean?.contains("Error! Hyperlink reference not valid.") ?? true)
        XCTAssertFalse(clean?.contains("Reference ID") ?? true)
        XCTAssertTrue(clean?.contains("Serious adverse reactions") ?? false)
    }

    func testSanitizerCleansMekinistAdverseReactionNumbering() {
        let raw = """
        6 ADVERSE REACTIONS The following clinically significant adverse reactions are described elsewhere in labeling:
        1)] Hemorrhage may occur.
        2)] Colitis can happen.
        3)] Cardiomyopathy has been reported.
        """

        let bullets = PatientLabelSanitizer.cleanBullets(from: [raw], max: 5)

        XCTAssertTrue(bullets.contains("Hemorrhage may occur."))
        XCTAssertTrue(bullets.contains("Colitis can happen."))
        XCTAssertTrue(bullets.contains("Cardiomyopathy has been reported."))
        XCTAssertFalse(bullets.contains { $0.contains("ADVERSE REACTIONS") })
        XCTAssertFalse(bullets.contains { $0.contains("1)]") || $0.contains("2)]") })
    }

    func testSanitizerRemovesFdaSectionPrefixes() {
        let indication = PatientLabelSanitizer.cleanText(
            "1 INDICATIONS AND USAGE Colchicine tablets are indicated for prophylaxis of gout flares."
        )
        let dosage = PatientLabelSanitizer.cleanText(
            "2 DOSAGE AND ADMINISTRATION Take exactly as prescribed by your clinician."
        )

        XCTAssertEqual(indication, "Colchicine tablets are indicated for prophylaxis of gout flares.")
        XCTAssertEqual(dosage, "Take exactly as prescribed by your clinician.")
    }

    func testStrengthFormatterNormalizesDecimalsAndDeduplicates() {
        let strengths = MedicationStrengthFormatter.displayableStrengths(from: [
            ".5 mg",
            "0.50mg",
            ".6 mg",
            ".3 mg",
            "6 [hp_X]/mL"
        ])

        XCTAssertEqual(strengths, ["0.5 mg", "0.6 mg", "0.3 mg"])
    }

    func testSearchDeduplicatorUsesStableVisibleIdentity() {
        let first = DrugPayload(
            title: "Colchicine",
            strengths: [".50mg"],
            dosageForms: ["Tablet"],
            foodRule: nil,
            minIntervalHours: nil,
            ingredients: [],
            indications: ["1 INDICATIONS AND USAGE Used for gout flares."],
            howToTake: [],
            commonSideEffects: [],
            importantWarnings: [],
            interactionsToAvoid: [],
            references: nil,
            kbKey: nil,
            rxcui: "201",
            id: nil
        )
        let second = DrugPayload(
            title: "colchicine",
            strengths: ["0.5 mg"],
            dosageForms: ["tablet"],
            foodRule: nil,
            minIntervalHours: nil,
            ingredients: [],
            indications: ["Used for gout flares."],
            howToTake: [],
            commonSideEffects: [],
            importantWarnings: [],
            interactionsToAvoid: [],
            references: nil,
            kbKey: nil,
            rxcui: "201",
            id: nil
        )

        let unique = MedicationSearchDeduplicator.deduplicate([first, second])

        XCTAssertEqual(unique.count, 1)
        XCTAssertEqual(unique.first?.strengths, ["0.5 mg"])
        XCTAssertEqual(unique.first?.indications, ["Used for gout flares."])
    }

    func testDoseParserHandlesTabletStrength() {
        let details = MedicationDoseParser.parse("500 mg tablet", preferredForm: "tablet")

        XCTAssertEqual(details.doseForm, "tablet")
        XCTAssertEqual(details.strengthAmount, 500)
        XCTAssertEqual(details.strengthUnit, "mg")
        XCTAssertEqual(details.quantityPerDose, 1)
        XCTAssertEqual(details.quantityUnit, "tablets")
        XCTAssertTrue(details.isConfident)
    }

    func testDoseParserHandlesLiquidConcentration() {
        let details = MedicationDoseParser.parse("Amoxicillin 250 mg/5 ml suspension", preferredForm: "liquid")

        XCTAssertEqual(details.doseForm, "liquid")
        XCTAssertEqual(details.concentrationAmount, 250)
        XCTAssertEqual(details.concentrationUnit, "mg/mL")
        XCTAssertTrue(details.isConfident)
    }

    func testDoseParserHandlesInhalerDropsAndPatchForms() {
        let inhaler = MedicationDoseParser.parse("1 puff", preferredForm: "inhaler")
        XCTAssertEqual(inhaler.doseForm, "inhaler")
        XCTAssertEqual(inhaler.quantityPerDose, 1)
        XCTAssertEqual(inhaler.quantityUnit, "puffs")

        let drops = MedicationDoseParser.parse("2 drops eye drops", preferredForm: "drops")
        XCTAssertEqual(drops.doseForm, "drops")
        XCTAssertEqual(drops.quantityPerDose, 2)
        XCTAssertEqual(drops.quantityUnit, "drops")
        XCTAssertEqual(drops.applicationArea, "eye")

        let patch = MedicationDoseParser.parse("1 patch", preferredForm: "patch")
        XCTAssertEqual(patch.doseForm, "patch")
        XCTAssertEqual(patch.quantityUnit, "patches")
    }

    func testFormRulesHideFoodTimingForNonOralForms() {
        XCTAssertFalse(MedicationFormRules.shouldShowFoodTiming(formID: "injection", foodRule: .none, sourceBacked: false))
        XCTAssertFalse(MedicationFormRules.shouldShowFoodTiming(formID: "cream", foodRule: .none, sourceBacked: false))
        XCTAssertFalse(MedicationFormRules.shouldShowFoodTiming(formID: "inhaler", foodRule: .none, sourceBacked: false))
        XCTAssertTrue(MedicationFormRules.shouldShowFoodTiming(formID: "tablet", foodRule: .none, sourceBacked: false))
        XCTAssertTrue(MedicationFormRules.shouldShowFoodTiming(formID: "injection", foodRule: .withFood, sourceBacked: true))
    }
}
