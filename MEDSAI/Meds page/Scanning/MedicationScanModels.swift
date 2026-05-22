import CoreGraphics
import Foundation
import UIKit

enum OCRImageQualityProfile: String, Codable, Hashable {
    case fast
    case balanced
    case detailed
}

struct MedicationScanImageBundle {
    let previewImage: UIImage
    let ocrImage: UIImage
    let originalSize: CGSize
    private let detailedImageProvider: () -> UIImage?
    private let fallbackDataProvider: () -> Data?

    init(original: UIImage) {
        let fixed = original.fixedOrientation()
        let pixelWidth = fixed.cgImage?.width ?? Int(fixed.size.width * fixed.scale)
        let pixelHeight = fixed.cgImage?.height ?? Int(fixed.size.height * fixed.scale)
        self.originalSize = CGSize(width: pixelWidth, height: pixelHeight)
        
        self.previewImage = fixed.downscaledForPreview(maxDimension: 900)
        self.ocrImage = fixed.downscaledForOCR(maxDimension: 2200)

        let detailed = fixed.downscaledForOCR(maxDimension: 2800)
        self.detailedImageProvider = { detailed }

        let fallbackSource = fixed.downscaledForFallback(maxDimension: 1800)
        self.fallbackDataProvider = {
            autoreleasepool {
                fallbackSource.jpegData(compressionQuality: 0.85)
            }
        }
    }

    func detailedOCRImage() -> UIImage? {
        detailedImageProvider()
    }

    func fallbackImageData() -> Data? {
        fallbackDataProvider()
    }
}

struct MedicationOCRLine: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var text: String
    var confidence: Double?
    var boundingBox: CGRect?
    var source: String
}

struct MedicationOCRResult: Codable, Hashable {
    var rawText: String
    var lines: [MedicationOCRLine]
    var detectedLanguages: [String]
    var barcodes: [MedicationBarcode]
    var createdAt: Date
    var imageQuality: MedicationImageQuality

    static var empty: MedicationOCRResult {
        MedicationOCRResult(
            rawText: "",
            lines: [],
            detectedLanguages: [],
            barcodes: [],
            createdAt: Date(),
            imageQuality: MedicationImageQuality(
                isBlurry: false,
                isLowLight: false,
                hasLowTextDensity: true,
                warnings: ["no text found"]
            )
        )
    }
}

struct MedicationBarcode: Codable, Hashable {
    var value: String
    var symbology: String?
    var confidence: Double?
}

struct MedicationImageQuality: Codable, Hashable {
    var isBlurry: Bool
    var isLowLight: Bool
    var hasLowTextDensity: Bool
    var warnings: [String]
}

struct MedicationExtractedFields: Codable, Hashable {
    var possibleBrandName: String?
    var possibleGenericName: String?
    var possibleActiveIngredients: [String]
    var strengthValue: Double?
    var strengthUnit: String?
    var dosageForm: String?
    var packageQuantity: String?
    var manufacturer: String?
    var barcode: String?
    var languageHints: [String]
    var rawWarningsText: [String]
    var rawDirectionsText: [String]
    var confidence: MedicationFieldConfidence
    var extractionMethod: String
    var needsUserConfirmation: Bool
}

struct MedicationFieldConfidence: Codable, Hashable {
    var brandName: Double
    var genericName: Double
    var activeIngredients: Double
    var strength: Double
    var dosageForm: Double
    var packageQuantity: Double
    var manufacturer: Double
    var overall: Double

    static var low: MedicationFieldConfidence {
        MedicationFieldConfidence(
            brandName: 0,
            genericName: 0,
            activeIngredients: 0,
            strength: 0,
            dosageForm: 0,
            packageQuantity: 0,
            manufacturer: 0,
            overall: 0
        )
    }
}

struct MedicationScanCandidate: Identifiable, Codable, Hashable {
    var id: String { medicationId?.uuidString ?? "\(brandName)-\(strength ?? "")-\(source)" }
    var medicationId: UUID?
    var brandName: String
    var genericName: String?
    var activeIngredients: [String]
    var strength: String?
    var dosageForm: String?
    var manufacturer: String?
    var matchScore: Double
    var matchReasons: [String]
    var source: String
    var requiresConfirmation: Bool
}

struct MedicationScanDecision: Identifiable, Codable, Hashable {
    var id: UUID { scanSessionId }
    var ocrResult: MedicationOCRResult
    var extractedFields: MedicationExtractedFields
    var candidates: [MedicationScanCandidate]
    var selectedCandidate: MedicationScanCandidate?
    var scanSessionId: UUID
    var requiresFallback: Bool
    var fallbackReason: String?
    var ocrProfile: OCRImageQualityProfile = .balanced
    var ocrRetryUsed: Bool = false
    var originalWidth: Double?
    var originalHeight: Double?
    var previewWidth: Double?
    var previewHeight: Double?
    var ocrWidth: Double?
    var ocrHeight: Double?
    var detailedOcrWidth: Double?
    var detailedOcrHeight: Double?
    var fallbackByteSize: Int?

    var topCandidate: MedicationScanCandidate? {
        candidates.sorted { $0.matchScore > $1.matchScore }.first
    }
}

struct MedicationScanSaveMetadata: Codable, Hashable {
    var scanSource: String
    var scanConfidence: Double?
    var scanConfirmedByUser: Bool
    var extractedFields: MedicationExtractedFields?
    var candidateSnapshot: [MedicationScanCandidate]?

    static var manual: MedicationScanSaveMetadata {
        MedicationScanSaveMetadata(
            scanSource: "manual",
            scanConfidence: nil,
            scanConfirmedByUser: false,
            extractedFields: nil,
            candidateSnapshot: nil
        )
    }

    static func manualFromScan(
        extractedFields: MedicationExtractedFields?,
        candidates: [MedicationScanCandidate]
    ) -> MedicationScanSaveMetadata {
        MedicationScanSaveMetadata(
            scanSource: "manual_from_scan",
            scanConfidence: nil,
            scanConfirmedByUser: false,
            extractedFields: extractedFields?.identityOnlyForScanSave(),
            candidateSnapshot: candidates.isEmpty ? nil : candidates
        )
    }

    static func confirmed(
        source: String,
        confidence: Double?,
        extractedFields: MedicationExtractedFields,
        candidates: [MedicationScanCandidate]
    ) -> MedicationScanSaveMetadata {
        MedicationScanSaveMetadata(
            scanSource: source,
            scanConfidence: confidence,
            scanConfirmedByUser: true,
            extractedFields: extractedFields.identityOnlyForScanSave(),
            candidateSnapshot: candidates
        )
    }
}

extension MedicationExtractedFields {
    func identityOnlyForScanSave() -> MedicationExtractedFields {
        var copy = self
        copy.possibleActiveIngredients = []
        copy.packageQuantity = nil
        copy.rawWarningsText = []
        copy.rawDirectionsText = []
        copy.languageHints = []
        return copy
    }
}
