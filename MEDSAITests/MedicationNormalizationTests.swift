import XCTest
import UIKit
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

    func testDoseFormatterUsesMedicationNameOnlyTitle() {
        let med = localMed(name: "Panadol", doseQuantity: 1, doseUnit: "tablets")

        XCTAssertEqual(DoseTextFormatter.medicationTitle(med.name), "Panadol")
        XCTAssertEqual(med.doseActionText(), "Panadol")
        XCTAssertFalse(med.doseActionText().contains("Take"))
    }

    func testDoseFormatterShowsValidDoseUnderTitle() {
        XCTAssertEqual(DoseTextFormatter.formatDoseAmount(for: localMed(doseQuantity: 1, doseUnit: "tablets")), "1 tablet")
        XCTAssertEqual(DoseTextFormatter.formatDoseAmount(for: localMed(doseQuantity: 2, doseUnit: "capsules")), "2 capsules")
        XCTAssertEqual(DoseTextFormatter.formatDoseAmount(for: localMed(strengthValue: 10, strengthUnit: "mg")), "10 mg")
        XCTAssertEqual(DoseTextFormatter.formatDoseAmount(for: localMed(doseQuantity: 5, doseUnit: "mL")), "5 mL")
    }

    func testDoseFormatterHidesMissingInvalidAndHugeDoseAmounts() {
        XCTAssertNil(DoseTextFormatter.formatDoseAmount(for: localMed()))
        XCTAssertNil(DoseTextFormatter.formatDoseAmount(for: localMed(doseQuantity: 0, doseUnit: "tablets")))
        XCTAssertNil(DoseTextFormatter.formatDoseAmount(for: localMed(doseQuantity: 11, doseUnit: nil)))
        XCTAssertNil(DoseTextFormatter.formatDoseAmount(for: localMed(doseQuantity: 12_312_313, doseUnit: "mL", doseDisplay: "12,312,313 mL / 1,123,123 mg/mL")))
    }

    func testDoseFormatterFoodInstructionsHideNoneAndShowActualRules() {
        XCTAssertNil(DoseTextFormatter.formatFoodInstruction(.none))
        XCTAssertEqual(DoseTextFormatter.formatFoodInstruction(.afterFood), "After food")
        XCTAssertEqual(DoseTextFormatter.formatFoodInstruction(.beforeFood), "Before food")
        XCTAssertEqual(DoseTextFormatter.formatFoodInstruction(.withFood), "With food")
    }

    func testDoseFormatterFrequencyTextIsShort() {
        XCTAssertEqual(DoseTextFormatter.formatFrequency(for: localMed(timesPerDay: 1, frequencyPerDay: 1)), "Once daily")
        XCTAssertEqual(DoseTextFormatter.formatFrequency(for: localMed(timesPerDay: 2, frequencyPerDay: 2)), "Twice daily")
        XCTAssertEqual(DoseTextFormatter.formatFrequency(for: localMed(timesPerDay: 3, frequencyPerDay: 3)), "3 times daily")
        XCTAssertEqual(DoseTextFormatter.formatFrequency(for: localMed(scheduleMode: .asNeeded, asNeeded: true)), "As needed")
    }

    func testDoseFormatterDeduplicatesTimes() {
        XCTAssertEqual(
            DoseTextFormatter.deduplicatedTimeStrings(["21:17:00", "07:15:00", "21:17:30", "07:15"]),
            ["07:15:00", "21:17:00"]
        )
    }

    func testUnscheduledMedicationDoesNotCreateTodayDoseRows() {
        let med = localMed(scheduleMode: .asNeeded, asNeeded: true, dosageTimes: [])

        XCTAssertFalse(med.isScheduled(on: Date()))
    }

    func testRuleBasedScanParserExtractsCommonEnglishAndArabicPackages() {
        let extractor = RuleBasedMedicationFieldExtractor()

        let panadol = extractor.extract(from: ocr("Panadol Paracetamol 500 mg tablets"))
        XCTAssertEqual(panadol.possibleBrandName, "Panadol")
        XCTAssertEqual(panadol.possibleGenericName, "Paracetamol")
        XCTAssertEqual(panadol.strengthValue, 500)
        XCTAssertEqual(panadol.strengthUnit, "mg")
        XCTAssertEqual(panadol.dosageForm, "tablet")

        let augmentin = extractor.extract(from: ocr("Augmentin 625 mg tablets"))
        XCTAssertEqual(augmentin.possibleBrandName, "Augmentin")
        XCTAssertEqual(augmentin.strengthValue, 625)
        XCTAssertEqual(augmentin.dosageForm, "tablet")

        let combo = extractor.extract(from: ocr("Amoxicillin/Clavulanic acid 500 mg/125 mg"))
        XCTAssertEqual(combo.strengthValue, 500)
        XCTAssertEqual(combo.strengthUnit, "mg")
        XCTAssertTrue((combo.possibleBrandName ?? "").contains("Amoxicillin"))

        let arabic = extractor.extract(from: ocr("بنادول باراسيتامول ٥٠٠ ملجم أقراص"))
        XCTAssertEqual(arabic.possibleBrandName, "بنادول")
        XCTAssertEqual(arabic.possibleGenericName, "باراسيتامول")
        XCTAssertEqual(arabic.strengthValue, 500)
        XCTAssertEqual(arabic.strengthUnit, "mg")
        XCTAssertEqual(arabic.dosageForm, "tablet")
    }

    func testRuleBasedScanParserExtractsSyrupCreamAndIgnoresQuantity() {
        let extractor = RuleBasedMedicationFieldExtractor()

        let syrup = extractor.extract(from: ocr("Cetirizine 5 mg/5 mL syrup 100 ml"))
        XCTAssertEqual(syrup.possibleBrandName, "Cetirizine")
        XCTAssertEqual(syrup.strengthValue, 5)
        XCTAssertEqual(syrup.strengthUnit, "mg/5 mL")
        XCTAssertEqual(syrup.dosageForm, "syrup")
        XCTAssertNil(syrup.packageQuantity)

        let cream = extractor.extract(from: ocr("Hydrocortisone 1% cream"))
        XCTAssertEqual(cream.possibleBrandName, "Hydrocortisone")
        XCTAssertEqual(cream.strengthValue, 1)
        XCTAssertEqual(cream.strengthUnit, "%")
        XCTAssertEqual(cream.dosageForm, "cream")
    }

    func testCandidateMatchingScoresExpectedSignals() {
        let exactRow = TestCatalogRow(
            id: UUID().uuidString,
            name: "Panadol",
            strengthValues: ["500 mg"],
            activeIngredients: ["Paracetamol"],
            dosageFormNormalized: "tablet"
        )
        let brandOnlyRow = TestCatalogRow(id: UUID().uuidString, name: "Panadol")
        let strengthOnlyRow = TestCatalogRow(id: UUID().uuidString, name: "Unknown", strengthValues: ["500 mg"])
        let barcodeRow = TestCatalogRow(id: UUID().uuidString, name: "Other", barcodeValues: ["123456"])

        let extracted = extractedFields(
            brand: "Panadol",
            generic: "Paracetamol",
            ingredients: ["Paracetamol"],
            strengthValue: 500,
            strengthUnit: "mg",
            form: "tablet",
            barcode: "123456"
        )

        let exact = MedicationCandidateMatcher.score(row: exactRow, extracted: extracted)
        let brandOnly = MedicationCandidateMatcher.score(row: brandOnlyRow, extracted: extracted)
        let strengthOnly = MedicationCandidateMatcher.score(row: strengthOnlyRow, extracted: extracted)
        let barcode = MedicationCandidateMatcher.score(row: barcodeRow, extracted: extracted)

        XCTAssertGreaterThanOrEqual(exact.matchScore, 0.85)
        XCTAssertGreaterThanOrEqual(brandOnly.matchScore, 0.25)
        XCTAssertLessThan(strengthOnly.matchScore, 0.45)
        XCTAssertGreaterThanOrEqual(barcode.matchScore, 0.60)
        XCTAssertTrue(barcode.matchReasons.contains("Barcode matched"))
    }

    func testScanFallbackThresholds() {
        XCTAssertTrue(MedicationScanPipeline.shouldFallback(ocrResult: .empty, candidates: []))
        XCTAssertTrue(MedicationScanPipeline.shouldCallImageFallback(ocrResult: .empty, candidates: []))

        let low = MedicationScanCandidate(medicationId: nil, brandName: "Maybe", genericName: nil, activeIngredients: [], strength: nil, dosageForm: nil, manufacturer: nil, matchScore: 0.4, matchReasons: [], source: "supabase_catalog", requiresConfirmation: true)
        let high = MedicationScanCandidate(medicationId: nil, brandName: "Panadol", genericName: nil, activeIngredients: [], strength: "500 mg", dosageForm: "tablet", manufacturer: nil, matchScore: 0.9, matchReasons: [], source: "supabase_catalog", requiresConfirmation: true)

        XCTAssertTrue(MedicationScanPipeline.shouldFallback(ocrResult: ocr("uncertain text"), candidates: [low]))
        XCTAssertTrue(MedicationScanPipeline.shouldCallImageFallback(ocrResult: ocr("uncertain text"), candidates: [low]))
        XCTAssertFalse(MedicationScanPipeline.shouldFallback(ocrResult: ocr("Panadol 500 mg tablets"), candidates: [high]))
        XCTAssertFalse(MedicationScanPipeline.shouldCallImageFallback(ocrResult: ocr("Panadol 500 mg tablets"), candidates: [high]))
    }

    func testScanSaveMetadataManualAndConfirmed() {
        let manual = MedicationScanSaveMetadata.manual
        XCTAssertEqual(manual.scanSource, "manual")
        XCTAssertNil(manual.scanConfidence)
        XCTAssertFalse(manual.scanConfirmedByUser)
        XCTAssertNil(manual.extractedFields)

        let candidate = MedicationScanCandidate(medicationId: UUID(), brandName: "Panadol", genericName: "Paracetamol", activeIngredients: ["Paracetamol"], strength: "500 mg", dosageForm: "tablet", manufacturer: nil, matchScore: 0.92, matchReasons: ["Brand name matched"], source: "supabase_catalog", requiresConfirmation: true)
        let confirmed = MedicationScanSaveMetadata.confirmed(
            source: "apple_ocr",
            confidence: candidate.matchScore,
            extractedFields: extractedFields(brand: "Panadol", strengthValue: 500, strengthUnit: "mg", form: "tablet"),
            candidates: [candidate]
        )

        XCTAssertEqual(confirmed.scanSource, "apple_ocr")
        XCTAssertEqual(confirmed.scanConfidence, 0.92)
        XCTAssertTrue(confirmed.scanConfirmedByUser)
        XCTAssertEqual(confirmed.extractedFields?.possibleBrandName, "Panadol")
        XCTAssertEqual(confirmed.candidateSnapshot?.count, 1)
    }

    func testScanParserRejectsMarketingTextAsMedicationName() {
        let extractor = RuleBasedMedicationFieldExtractor()

        for text in ["fast relief", "extra strength", "sugar free", "new formula", "سريع المفعول", "خالي من السكر"] {
            let fields = extractor.extract(from: ocr(text))
            XCTAssertNil(fields.possibleBrandName, text)
            XCTAssertTrue(RuleBasedMedicationFieldExtractor.isSuspiciousMedicationName(text), text)
        }
    }

    func testScanParserRejectsNumericAndShortFragmentsAsHighConfidenceNames() {
        let extractor = RuleBasedMedicationFieldExtractor()

        for text in ["1,2,3", "20", "10", "..."] {
            let fields = extractor.extract(from: ocr(text))
            XCTAssertNil(fields.possibleBrandName, text)
            XCTAssertTrue(fields.confidence.brandName < 0.42, text)
        }
    }

    func testScanParserExtractsGeneralStrengthFormats() {
        let extractor = RuleBasedMedicationFieldExtractor()

        let paracetamol = extractor.extract(from: ocr("Paracetamol 500 mg"))
        XCTAssertEqual(paracetamol.strengthValue, 500)
        XCTAssertEqual(paracetamol.strengthUnit, "mg")

        let liquid = extractor.extract(from: ocr("Cetirizine 5 mg/5 mL syrup"))
        XCTAssertEqual(liquid.strengthValue, 5)
        XCTAssertEqual(liquid.strengthUnit, "mg/5 mL")

        let combo = extractor.extract(from: ocr("Amoxicillin 500 mg / Clavulanic acid 125 mg tablets"))
        XCTAssertEqual(combo.strengthValue, 500)
        XCTAssertEqual(combo.strengthUnit, "mg")

        let cream = extractor.extract(from: ocr("Hydrocortisone 1% cream"))
        XCTAssertEqual(cream.strengthValue, 1)
        XCTAssertEqual(cream.strengthUnit, "%")
    }

    func testScanParserSeparatesQuantityFromStrength() {
        let extractor = RuleBasedMedicationFieldExtractor()

        let tablets = extractor.extract(from: ocr("20 tablets"))
        XCTAssertNil(tablets.strengthValue)
        XCTAssertNil(tablets.packageQuantity)

        let bottle = extractor.extract(from: ocr("Cetirizine syrup 100 mL bottle"))
        XCTAssertNil(bottle.strengthValue)
        XCTAssertNil(bottle.packageQuantity)

        let liquid = extractor.extract(from: ocr("Cetirizine 5 mg/5 mL syrup 100 mL"))
        XCTAssertEqual(liquid.strengthValue, 5)
        XCTAssertNil(liquid.packageQuantity)
    }

    func testScanParserDetectsDosageFormsWithoutDefaultingToTablet() {
        let extractor = RuleBasedMedicationFieldExtractor()

        XCTAssertEqual(extractor.extract(from: ocr("film coated tablets")).dosageForm, "tablet")
        XCTAssertEqual(extractor.extract(from: ocr("ophthalmic solution")).dosageForm, "ophthalmic solution")
        XCTAssertEqual(extractor.extract(from: ocr("cream")).dosageForm, "cream")
        XCTAssertEqual(extractor.extract(from: ocr("syrup")).dosageForm, "syrup")
        XCTAssertEqual(extractor.extract(from: ocr("قطرات للعين")).dosageForm, "eye drops")
        XCTAssertNil(extractor.extract(from: ocr("Paracetamol 500 mg")).dosageForm)
    }

    func testScanParserIgnoresDirectionsAndWarningText() {
        let extractor = RuleBasedMedicationFieldExtractor()

        let fields = extractor.extract(from: ocr("Directions: take one tablet daily\nWarning: keep out of reach"))

        XCTAssertNil(fields.possibleBrandName)
        XCTAssertNil(fields.packageQuantity)
        XCTAssertTrue(fields.rawDirectionsText.isEmpty)
        XCTAssertTrue(fields.rawWarningsText.isEmpty)
    }

    func testFormOnlyAndStrengthOnlyDoNotCreateIdentity() {
        let extractor = RuleBasedMedicationFieldExtractor()

        let formOnly = extractor.extract(from: ocr("tablets"))
        XCTAssertNil(formOnly.possibleBrandName)
        XCTAssertEqual(formOnly.dosageForm, "tablet")

        let strengthOnly = extractor.extract(from: ocr("500 mg"))
        XCTAssertNil(strengthOnly.possibleBrandName)
        XCTAssertNil(strengthOnly.possibleGenericName)
        XCTAssertEqual(strengthOnly.strengthValue, 500)
    }

    func testMedicationFormSuggestsIconWithoutBeingRequired() {
        XCTAssertEqual(MedicationIconSuggestion.suggestedShapeID(for: "tablets"), "tablet")
        XCTAssertEqual(MedicationIconSuggestion.suggestedShapeID(for: "كبسولات"), "capsule")
        XCTAssertEqual(MedicationIconSuggestion.suggestedShapeID(for: "oral solution"), "liquid")
        XCTAssertEqual(MedicationIconSuggestion.suggestedShapeID(for: nil), nil)
    }

    func testScanParserExtractsActiveIngredientContext() {
        let extractor = RuleBasedMedicationFieldExtractor()

        let english = extractor.extract(from: ocr("each tablet contains paracetamol 500 mg"))
        XCTAssertEqual(english.possibleGenericName, "paracetamol")
        XCTAssertTrue(english.possibleActiveIngredients.isEmpty)

        let arabic = extractor.extract(from: ocr("يحتوي كل قرص على باراسيتامول ٥٠٠ ملجم"))
        XCTAssertEqual(arabic.possibleGenericName, "باراسيتامول")
        XCTAssertTrue(arabic.possibleActiveIngredients.isEmpty)
    }

    func testCandidateMatchingRequiresIdentityEvidenceForHighConfidence() {
        let strengthOnlyRow = TestCatalogRow(id: UUID().uuidString, name: "Different", strengthValues: ["500 mg"])
        let manufacturerOnlyRow = TestCatalogRow(id: UUID().uuidString, name: "Different", manufacturerNormalized: "pfizer")
        let brandStrengthRow = TestCatalogRow(id: UUID().uuidString, name: "Panadol", strengthValues: ["500 mg"])

        let strengthOnly = MedicationCandidateMatcher.score(
            row: strengthOnlyRow,
            extracted: extractedFields(strengthValue: 500, strengthUnit: "mg")
        )
        let manufacturerOnly = MedicationCandidateMatcher.score(
            row: manufacturerOnlyRow,
            extracted: extractedFields(brand: nil, strengthValue: nil, strengthUnit: nil, form: nil, barcode: nil, manufacturer: "pfizer")
        )
        let brandStrength = MedicationCandidateMatcher.score(
            row: brandStrengthRow,
            extracted: extractedFields(brand: "Panadol", strengthValue: 500, strengthUnit: "mg")
        )

        XCTAssertLessThan(strengthOnly.matchScore, MedicationScanPipeline.fallbackThreshold)
        XCTAssertLessThan(manufacturerOnly.matchScore, MedicationScanPipeline.fallbackThreshold)
        XCTAssertGreaterThanOrEqual(brandStrength.matchScore, MedicationScanPipeline.mediumConfidenceCandidateThreshold)
        XCTAssertLessThan(brandStrength.matchScore, MedicationScanPipeline.highConfidenceCandidateThreshold)
    }

    func testConfirmationGatingRequiresSelectedReliableCandidate() {
        let catalogCandidate = MedicationScanCandidate(medicationId: UUID(), brandName: "Panadol", genericName: "Paracetamol", activeIngredients: ["Paracetamol"], strength: "500 mg", dosageForm: "tablet", manufacturer: nil, matchScore: 0.86, matchReasons: ["Brand name matched", "Strength matched"], source: "supabase_catalog", requiresConfirmation: true)
        let lowCandidate = MedicationScanCandidate(medicationId: UUID(), brandName: "Panadol", genericName: nil, activeIngredients: [], strength: nil, dosageForm: nil, manufacturer: nil, matchScore: 0.44, matchReasons: ["Brand name matched"], source: "supabase_catalog", requiresConfirmation: true)
        let noIdCandidate = MedicationScanCandidate(medicationId: nil, brandName: "Panadol", genericName: nil, activeIngredients: [], strength: "500 mg", dosageForm: "tablet", manufacturer: nil, matchScore: 0.86, matchReasons: ["Brand name matched"], source: "supabase_catalog", requiresConfirmation: true)
        let fallbackCandidate = MedicationScanCandidate(medicationId: nil, brandName: "Panadol", genericName: nil, activeIngredients: [], strength: "500 mg", dosageForm: "tablet", manufacturer: nil, matchScore: 0.78, matchReasons: ["AI image recognition fallback"], source: "image_to_drug_fallback", requiresConfirmation: true)

        XCTAssertFalse(MedScanConfirmationView.isConfirmableCandidate(nil))
        XCTAssertTrue(MedScanConfirmationView.isConfirmableCandidate(catalogCandidate))
        XCTAssertFalse(MedScanConfirmationView.isConfirmableCandidate(lowCandidate))
        XCTAssertFalse(MedScanConfirmationView.isConfirmableCandidate(noIdCandidate))
        XCTAssertTrue(MedScanConfirmationView.isConfirmableCandidate(fallbackCandidate))
        XCTAssertFalse(MedScanConfirmationView.isConfirmableCandidate(
            MedicationScanCandidate(medicationId: UUID(), brandName: "fast relief", genericName: nil, activeIngredients: [], strength: nil, dosageForm: nil, manufacturer: nil, matchScore: 0.9, matchReasons: ["Brand name matched"], source: "supabase_catalog", requiresConfirmation: true)
        ))
    }

    func testManualFromScanMetadataIsMarkedUnverifiedUntilAddFormSave() {
        let fields = extractedFields(brand: "Maybe", strengthValue: 500, strengthUnit: "mg")
        let metadata = MedicationScanSaveMetadata.manualFromScan(extractedFields: fields, candidates: [])

        XCTAssertEqual(metadata.scanSource, "manual_from_scan")
        XCTAssertNil(metadata.scanConfidence)
        XCTAssertFalse(metadata.scanConfirmedByUser)
        XCTAssertEqual(metadata.extractedFields?.possibleBrandName, "Maybe")
    }

    func testImageHelpersDownscaleLargeImagesAndCompressFallbackJPEG() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let large = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1800), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1800))
            UIColor.black.setFill()
            "Panadol 500 mg".draw(at: CGPoint(x: 100, y: 100), withAttributes: [.font: UIFont.systemFont(ofSize: 120)])
        }

        let ocr = large.downscaledForOCR()
        let preview = large.downscaledForPreview()
        let ocrMax = max(ocr.cgImage?.width ?? Int(ocr.size.width * ocr.scale), ocr.cgImage?.height ?? Int(ocr.size.height * ocr.scale))
        let previewMax = max(preview.cgImage?.width ?? Int(preview.size.width * preview.scale), preview.cgImage?.height ?? Int(preview.size.height * preview.scale))
        let fallbackData = large.jpegDataForScanFallback()

        XCTAssertLessThanOrEqual(ocrMax, 2200)
        XCTAssertLessThanOrEqual(previewMax, 900)
        XCTAssertNotNil(fallbackData)
        XCTAssertLessThan(fallbackData?.count ?? .max, 1_500_000)
    }

    func testMedicationScanImageBundleDownscalesAndReleasesOriginal() {
        let originalWidth: CGFloat = 3000
        let originalHeight: CGFloat = 2000
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        let large = UIGraphicsImageRenderer(size: CGSize(width: originalWidth, height: originalHeight), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: originalWidth, height: originalHeight))
            UIColor.black.setFill()
            "Panadol 500 mg".draw(at: CGPoint(x: 100, y: 100), withAttributes: [.font: UIFont.systemFont(ofSize: 120)])
        }

        let bundle = MedicationScanImageBundle(original: large)

        // Verify original dimensions metadata is recorded
        XCTAssertEqual(bundle.originalSize.width, originalWidth)
        XCTAssertEqual(bundle.originalSize.height, originalHeight)

        // Verify preview dimensions (should be max 900)
        let previewSize = bundle.previewImage.size
        XCTAssertLessThanOrEqual(max(previewSize.width, previewSize.height), 900)

        // Verify OCR dimensions (should be max 2200 for balanced profile)
        let ocrSize = bundle.ocrImage.size
        XCTAssertLessThanOrEqual(max(ocrSize.width, ocrSize.height), 2200)

        // Verify that OCR image is not the same as preview image (preview image is way smaller)
        XCTAssertNotEqual(previewSize, ocrSize)
        XCTAssertLessThan(previewSize.width * previewSize.height, ocrSize.width * ocrSize.height)

        // Verify detailed OCR dimensions (should be max 2800)
        if let detailedOcr = bundle.detailedOCRImage() {
            let detailedSize = detailedOcr.size
            XCTAssertLessThanOrEqual(max(detailedSize.width, detailedSize.height), 2800)
            XCTAssertGreaterThan(detailedSize.width * detailedSize.height, ocrSize.width * ocrSize.height)
        } else {
            XCTFail("Detailed OCR image should be available")
        }

        // Verify fallback image data
        if let fallbackData = bundle.fallbackImageData() {
            XCTAssertLessThan(fallbackData.count, 2_000_000)
            if let fallbackImage = UIImage(data: fallbackData) {
                let fallbackSize = fallbackImage.size
                XCTAssertLessThanOrEqual(max(fallbackSize.width, fallbackSize.height), 1800)
            } else {
                XCTFail("Fallback JPEG data should compile back to a valid UIImage")
            }
        } else {
            XCTFail("Fallback image data should be available")
        }
    }

    private func ocr(_ text: String) -> MedicationOCRResult {
        MedicationOCRResult(
            rawText: text,
            lines: [MedicationOCRLine(text: text, confidence: 0.9, boundingBox: nil, source: "manual")],
            detectedLanguages: text.range(of: #"\p{Arabic}"#, options: .regularExpression) == nil ? ["en"] : ["ar"],
            barcodes: [],
            createdAt: Date(),
            imageQuality: MedicationImageQuality(isBlurry: false, isLowLight: false, hasLowTextDensity: false, warnings: [])
        )
    }

    private func localMed(
        name: String = "Zyrtec",
        doseQuantity: Double? = nil,
        doseUnit: String? = nil,
        doseDisplay: String? = nil,
        strengthValue: Double? = nil,
        strengthUnit: String? = nil,
        timesPerDay: Int? = nil,
        frequencyPerDay: Int = 1,
        scheduleMode: MedicationScheduleMode = .daily,
        asNeeded: Bool = false,
        dosageTimes: [String] = ["08:00:00"]
    ) -> LocalMed {
        LocalMed(
            name: name,
            dosage: doseDisplay ?? "",
            frequencyPerDay: frequencyPerDay,
            startDate: Calendar.current.startOfDay(for: Date()),
            endDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
            dosageTimes: dosageTimes,
            asNeeded: asNeeded,
            medicationForm: nil,
            strengthValue: strengthValue,
            strengthUnit: strengthUnit,
            doseQuantity: doseQuantity,
            doseUnit: doseUnit,
            doseQuantityUnit: doseUnit,
            doseDisplay: doseDisplay,
            doseDetailsConfirmedByUser: false,
            scheduleMode: scheduleMode,
            timesPerDay: timesPerDay,
            remindersEnabled: !asNeeded
        )
    }

    private func extractedFields(
        brand: String? = nil,
        generic: String? = nil,
        ingredients: [String] = [],
        strengthValue: Double? = nil,
        strengthUnit: String? = nil,
        form: String? = nil,
        barcode: String? = nil,
        manufacturer: String? = nil
    ) -> MedicationExtractedFields {
        MedicationExtractedFields(
            possibleBrandName: brand,
            possibleGenericName: generic,
            possibleActiveIngredients: ingredients,
            strengthValue: strengthValue,
            strengthUnit: strengthUnit,
            dosageForm: form,
            packageQuantity: nil,
            manufacturer: manufacturer,
            barcode: barcode,
            languageHints: ["en"],
            rawWarningsText: [],
            rawDirectionsText: [],
            confidence: .low,
            extractionMethod: "rule_based",
            needsUserConfirmation: true
        )
    }
}

private struct TestCatalogRow: CatalogRowLike {
    let id: String
    let name: String
    var strengthValues: [String] = []
    var activeIngredients: [String] = []
    var barcodeValues: [String] = []
    var brandAliases: [String] = []
    var genericAliases: [String] = []
    var dosageFormNormalized: String?
    var manufacturerNormalized: String?
}
