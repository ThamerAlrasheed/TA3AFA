import Foundation
import UIKit

protocol MedicationImageFallbackAnalyzing {
    func analyze(image: UIImage) async throws -> [MedicationScanCandidate]
}

struct ImageToDrugFallbackAnalyzer: MedicationImageFallbackAnalyzing {
    func analyze(image: UIImage) async throws -> [MedicationScanCandidate] {
        guard let data = image.jpegDataForScanFallback(),
              data.count > 256 else {
            throw NSError(
                domain: "MedicationScanPipeline",
                code: 422,
                userInfo: [NSLocalizedDescriptionKey: "We couldn't prepare this photo. Please try again or choose another image."]
            )
        }
        let base64 = data.base64EncodedString()
        let result = try await DrugInfo.analyzeImage(base64: base64)
        return result.candidates.map { candidate in
            MedicationScanCandidate(
                medicationId: nil,
                brandName: candidate.name,
                genericName: nil,
                activeIngredients: [],
                strength: candidate.strength,
                dosageForm: candidate.dosage_form,
                manufacturer: nil,
                matchScore: min(max(candidate.confidence, 0), 1),
                matchReasons: ["AI image recognition fallback"],
                source: "image_to_drug_fallback",
                requiresConfirmation: true
            )
        }
    }
}

final class MedicationScanPipeline {
    static let highConfidenceCandidateThreshold = 0.85
    static let mediumConfidenceCandidateThreshold = 0.65
    static let fallbackThreshold = 0.45

    private let ocrService: MedicationOCRScanning
    private let fieldExtractor: MedicationFieldExtractionPipeline
    private let candidateMatcher: MedicationCandidateMatching
    private let textResolver: ScanTextResolving
    private let imageFallback: MedicationImageFallbackAnalyzing

    init(
        ocrService: MedicationOCRScanning = MedicationOCRService(),
        fieldExtractor: MedicationFieldExtractionPipeline = MedicationFieldExtractionPipeline(),
        candidateMatcher: MedicationCandidateMatching = MedicationCandidateMatcher(),
        textResolver: ScanTextResolving = ScanTextResolverClient(),
        imageFallback: MedicationImageFallbackAnalyzing = ImageToDrugFallbackAnalyzer()
    ) {
        self.ocrService = ocrService
        self.fieldExtractor = fieldExtractor
        self.candidateMatcher = candidateMatcher
        self.textResolver = textResolver
        self.imageFallback = imageFallback
    }

    func process(
        imageBundle: MedicationScanImageBundle,
        allowGPTResolver: Bool,
        allowImageFallback: Bool
    ) async throws -> MedicationScanDecision {
        let scanSessionId = UUID()
        var ocrProfile: OCRImageQualityProfile = .balanced
        var ocrRetryUsed = false

        let ocrImage = imageBundle.ocrImage
        var ocrResult = try await ocrService.scan(image: ocrImage)
        var extracted = await fieldExtractor.extract(from: ocrResult)
        var candidates: [MedicationScanCandidate] = []

        do {
            candidates = try await candidateMatcher.findCandidates(for: extracted)
        } catch {
            #if DEBUG
            print("Medication candidate matching failed: \(error)")
            #endif
        }

        var decision = MedicationScanDecision(
            ocrResult: ocrResult,
            extractedFields: extracted,
            candidates: candidates,
            selectedCandidate: candidates.first,
            scanSessionId: scanSessionId,
            requiresFallback: Self.shouldFallback(ocrResult: ocrResult, candidates: candidates),
            fallbackReason: Self.fallbackReason(ocrResult: ocrResult, candidates: candidates, extracted: extracted),
            ocrProfile: ocrProfile,
            ocrRetryUsed: ocrRetryUsed,
            originalWidth: Double(imageBundle.originalSize.width),
            originalHeight: Double(imageBundle.originalSize.height),
            previewWidth: Double(imageBundle.previewImage.size.width * imageBundle.previewImage.scale),
            previewHeight: Double(imageBundle.previewImage.size.height * imageBundle.previewImage.scale),
            ocrWidth: Double(ocrImage.size.width * ocrImage.scale),
            ocrHeight: Double(ocrImage.size.height * ocrImage.scale)
        )

        // Retry with detailed resolution if local scan OCR is weak
        if Self.isWeakOCR(ocrResult: ocrResult, decision: decision) {
            if let detailedImage = imageBundle.detailedOCRImage() {
                #if DEBUG
                print("OCR results were weak. Retrying with detailed OCR image (maxDimension 2800)...")
                #endif
                ocrProfile = .detailed
                ocrRetryUsed = true

                let retryResult = try await ocrService.scan(image: detailedImage)
                let retryExtracted = await fieldExtractor.extract(from: retryResult)
                var retryCandidates: [MedicationScanCandidate] = []
                do {
                    retryCandidates = try await candidateMatcher.findCandidates(for: retryExtracted)
                } catch {
                    #if DEBUG
                    print("Medication retry candidate matching failed: \(error)")
                    #endif
                }

                let retryDecision = MedicationScanDecision(
                    ocrResult: retryResult,
                    extractedFields: retryExtracted,
                    candidates: retryCandidates,
                    selectedCandidate: retryCandidates.first,
                    scanSessionId: scanSessionId,
                    requiresFallback: Self.shouldFallback(ocrResult: retryResult, candidates: retryCandidates),
                    fallbackReason: Self.fallbackReason(ocrResult: retryResult, candidates: retryCandidates, extracted: retryExtracted),
                    ocrProfile: ocrProfile,
                    ocrRetryUsed: ocrRetryUsed,
                    originalWidth: decision.originalWidth,
                    originalHeight: decision.originalHeight,
                    previewWidth: decision.previewWidth,
                    previewHeight: decision.previewHeight,
                    ocrWidth: decision.ocrWidth,
                    ocrHeight: decision.ocrHeight,
                    detailedOcrWidth: Double(detailedImage.size.width * detailedImage.scale),
                    detailedOcrHeight: Double(detailedImage.size.height * detailedImage.scale)
                )

                decision = retryDecision
                ocrResult = retryResult
                extracted = retryExtracted
                candidates = retryCandidates
            }
        }

        if allowGPTResolver, Self.shouldUseTextResolver(decision) {
            decision = await resolveWithTextGPT(decision)
        }

        if allowImageFallback, Self.shouldCallImageFallback(ocrResult: decision.ocrResult, candidates: decision.candidates) {
            if let data = imageBundle.fallbackImageData() {
                decision = try await appendImageFallback(data: data, decision: decision)
            }
        }

        decision.ocrProfile = ocrProfile
        decision.ocrRetryUsed = ocrRetryUsed

        #if DEBUG
        let ocrPixelWidth = ocrImage.cgImage?.width ?? Int(ocrImage.size.width * ocrImage.scale)
        let ocrPixelHeight = ocrImage.cgImage?.height ?? Int(ocrImage.size.height * ocrImage.scale)

        let previewPixelWidth = imageBundle.previewImage.cgImage?.width ?? Int(imageBundle.previewImage.size.width * imageBundle.previewImage.scale)
        let previewPixelHeight = imageBundle.previewImage.cgImage?.height ?? Int(imageBundle.previewImage.size.height * imageBundle.previewImage.scale)

        var detailedPixelStr = "n/a"
        if ocrRetryUsed, let detailed = imageBundle.detailedOCRImage() {
            let detW = detailed.cgImage?.width ?? Int(detailed.size.width * detailed.scale)
            let detH = detailed.cgImage?.height ?? Int(detailed.size.height * detailed.scale)
            detailedPixelStr = "\(detW)x\(detH)"
        }

        let fallbackSize = (allowImageFallback && Self.shouldCallImageFallback(ocrResult: decision.ocrResult, candidates: decision.candidates)) ? (imageBundle.fallbackImageData()?.count ?? 0) : 0
        let fallbackSizeStr = fallbackSize > 0 ? "\(fallbackSize) bytes" : "not triggered"

        print("""
        Scan image sizes:
        original: \(Int(imageBundle.originalSize.width))x\(Int(imageBundle.originalSize.height))
        ocr: \(ocrPixelWidth)x\(ocrPixelHeight)
        preview: \(previewPixelWidth)x\(previewPixelHeight)
        detailed retry ocr: \(detailedPixelStr)
        fallback image byte size: \(fallbackSizeStr)
        OCR line count: \(decision.ocrResult.lines.count)
        average OCR confidence: \(String(format: "%.2f", Self.averageConfidence(ocrResult.lines)))
        """)
        #endif

        return decision
    }

    func processImageFallback(data: Data, appendingTo decision: MedicationScanDecision) async throws -> MedicationScanDecision {
        try await appendImageFallback(data: data, decision: decision)
    }

    static func isWeakOCR(ocrResult: MedicationOCRResult, decision: MedicationScanDecision) -> Bool {
        let usefulLines = ocrResult.lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if usefulLines.count < 3 { return true }

        let hasAlphabetic = ocrResult.rawText.range(of: #"\p{L}"#, options: .regularExpression) != nil
        if !hasAlphabetic { return true }

        let hasBrand = decision.extractedFields.possibleBrandName != nil && !(decision.extractedFields.possibleBrandName?.isEmpty ?? true)
        let hasGeneric = decision.extractedFields.possibleGenericName != nil && !(decision.extractedFields.possibleGenericName?.isEmpty ?? true)
        let hasIngredients = !decision.extractedFields.possibleActiveIngredients.isEmpty
        if !hasBrand && !hasGeneric && !hasIngredients {
            return true
        }

        let confidences = ocrResult.lines.compactMap(\.confidence)
        let avgConfidence = confidences.isEmpty ? 0.0 : (confidences.reduce(0, +) / Double(confidences.count))
        if avgConfidence < 0.60 { return true }

        if decision.candidates.isEmpty {
            if let brand = decision.extractedFields.possibleBrandName,
               RuleBasedMedicationFieldExtractor.isSuspiciousMedicationName(brand) {
                return true
            }
        }

        return false
    }

    private static func averageConfidence(_ lines: [MedicationOCRLine]) -> Double {
        let confidences = lines.compactMap(\.confidence)
        guard !confidences.isEmpty else { return 0.0 }
        return confidences.reduce(0, +) / Double(confidences.count)
    }

    static func shouldFallback(ocrResult: MedicationOCRResult, candidates: [MedicationScanCandidate]) -> Bool {
        if ocrResult.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        guard let top = candidates.map(\.matchScore).max() else { return true }
        return top < mediumConfidenceCandidateThreshold
    }

    static func shouldCallImageFallback(ocrResult: MedicationOCRResult, candidates: [MedicationScanCandidate]) -> Bool {
        if ocrResult.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        guard let top = candidates.map(\.matchScore).max() else { return true }
        return top < fallbackThreshold
    }

    private static func shouldUseTextResolver(_ decision: MedicationScanDecision) -> Bool {
        guard !decision.ocrResult.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let topScore = decision.candidates.map(\.matchScore).max() else { return false }
        return topScore < highConfidenceCandidateThreshold
    }

    private static func fallbackReason(
        ocrResult: MedicationOCRResult,
        candidates: [MedicationScanCandidate],
        extracted: MedicationExtractedFields
    ) -> String? {
        if ocrResult.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "OCR returned no usable text."
        }
        if candidates.isEmpty {
            if extracted.barcode != nil {
                return "Barcode was detected, but no catalog match was found."
            }
            return "No catalog candidate matched the OCR result."
        }
        if let top = candidates.map(\.matchScore).max(), top < mediumConfidenceCandidateThreshold {
            return "Top catalog match is below confirmation confidence."
        }
        return nil
    }

    private func resolveWithTextGPT(_ decision: MedicationScanDecision) async -> MedicationScanDecision {
        do {
            let response = try await textResolver.resolve(decision: decision)
            var updated = decision
            if let bestId = response.bestMatchMedicationId,
               let index = updated.candidates.firstIndex(where: { $0.medicationId?.uuidString.lowercased() == bestId.lowercased() }) {
                var selected = updated.candidates[index]
                selected.source = "gpt_assisted"
                selected.requiresConfirmation = true
                let hasIdentityEvidence = selected.matchReasons.contains {
                    $0.localizedCaseInsensitiveContains("Brand")
                        || $0.localizedCaseInsensitiveContains("Generic")
                        || $0.localizedCaseInsensitiveContains("Active ingredient")
                        || $0.localizedCaseInsensitiveContains("Barcode")
                }
                if response.confidence == "high", hasIdentityEvidence, selected.matchScore >= Self.mediumConfidenceCandidateThreshold {
                    selected.matchScore = max(selected.matchScore, Self.highConfidenceCandidateThreshold)
                } else if response.confidence == "medium", hasIdentityEvidence, selected.matchScore >= Self.fallbackThreshold {
                    selected.matchScore = max(selected.matchScore, Self.mediumConfidenceCandidateThreshold)
                }
                if !response.reason.isEmpty {
                    selected.matchReasons = Array(Set(selected.matchReasons + [response.reason])).sorted()
                }
                updated.candidates[index] = selected
                updated.candidates.sort { $0.matchScore > $1.matchScore }
                updated.selectedCandidate = selected
            }
            updated.requiresFallback = response.needsFallback || Self.shouldFallback(ocrResult: updated.ocrResult, candidates: updated.candidates)
            updated.fallbackReason = response.needsFallback ? response.fallbackReason : updated.fallbackReason
            return updated
        } catch {
            #if DEBUG
            print("scan-text-resolver failed; continuing with local scan result: \(error)")
            #endif
            return decision
        }
    }

    private func appendImageFallback(data: Data, decision: MedicationScanDecision) async throws -> MedicationScanDecision {
        var updated = decision
        let base64 = data.base64EncodedString()
        let result = try await DrugInfo.analyzeImage(base64: base64)
        let fallbackCandidates = result.candidates.map { candidate in
            MedicationScanCandidate(
                medicationId: nil,
                brandName: candidate.name,
                genericName: nil,
                activeIngredients: [],
                strength: candidate.strength,
                dosageForm: candidate.dosage_form,
                manufacturer: nil,
                matchScore: min(max(candidate.confidence, 0), 1),
                matchReasons: ["AI image recognition fallback"],
                source: "image_to_drug_fallback",
                requiresConfirmation: true
            )
        }
        if fallbackCandidates.isEmpty { return updated }

        let existingIds = Set(updated.candidates.map(\.id))
        let merged = updated.candidates + fallbackCandidates.filter { !existingIds.contains($0.id) }
        updated.candidates = merged.sorted { $0.matchScore > $1.matchScore }
        updated.selectedCandidate = updated.candidates.first
        updated.requiresFallback = false
        updated.fallbackReason = nil
        return updated
    }
}
