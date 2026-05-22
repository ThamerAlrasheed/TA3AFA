import CoreImage
import Foundation
import UIKit
import Vision

protocol MedicationOCRScanning {
    func scan(image: UIImage) async throws -> MedicationOCRResult
}

enum MedicationOCRError: LocalizedError {
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "We could not read this image. Please try another photo."
        }
    }
}

final class MedicationOCRService: MedicationOCRScanning {
    private let recognitionLanguages = ["en-US", "ar"]

    func scan(image: UIImage) async throws -> MedicationOCRResult {
        let scanImage = image
        guard let cgImage = scanImage.cgImage else { throw MedicationOCRError.unreadableImage }

        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.recognitionLanguages = recognitionLanguages
        textRequest.minimumTextHeight = 0.012

        let barcodeRequest = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: scanImage.cgImagePropertyOrientation)

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([textRequest, barcodeRequest])
                    let lines = Self.ocrLines(from: textRequest.results ?? [])
                    let rawText = lines.map(\.text).joined(separator: "\n")
                    let barcodes = Self.barcodes(from: barcodeRequest.results ?? [])
                    let detectedLanguages = Self.detectedLanguages(from: rawText)
                    let imageQuality = Self.imageQuality(
                        image: scanImage,
                        cgImage: cgImage,
                        lines: lines,
                        rawText: rawText
                    )

                    #if DEBUG
                    if UserDefaults.standard.bool(forKey: "scan.debug.logOCRText") {
                        print("Medication OCR debug text: \(rawText)")
                    } else {
                        print("Medication OCR finished: lines=\(lines.count), words=\(Self.wordCount(rawText)), barcodes=\(barcodes.count), warnings=\(imageQuality.warnings.count)")
                    }
                    #endif

                    continuation.resume(returning: MedicationOCRResult(
                        rawText: rawText,
                        lines: lines,
                        detectedLanguages: detectedLanguages,
                        barcodes: barcodes,
                        createdAt: Date(),
                        imageQuality: imageQuality
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func ocrLines(from observations: [VNRecognizedTextObservation]) -> [MedicationOCRLine] {
        observations
            .sorted {
                let left = $0.boundingBox
                let right = $1.boundingBox
                if abs(left.midY - right.midY) > 0.025 { return left.midY > right.midY }
                return left.minX < right.minX
            }
            .compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return MedicationOCRLine(
                    text: text,
                    confidence: Double(candidate.confidence),
                    boundingBox: observation.boundingBox,
                    source: "vision"
                )
            }
    }

    private static func barcodes(from observations: [VNBarcodeObservation]) -> [MedicationBarcode] {
        observations.compactMap { observation in
            guard let value = observation.payloadStringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return MedicationBarcode(
                value: value,
                symbology: observation.symbology.rawValue,
                confidence: Double(observation.confidence)
            )
        }
    }

    private static func detectedLanguages(from rawText: String) -> [String] {
        var languages: [String] = []
        if rawText.range(of: #"\p{Arabic}"#, options: .regularExpression) != nil {
            languages.append("ar")
        }
        if rawText.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil {
            languages.append("en")
        }
        return languages
    }

    private static func imageQuality(
        image: UIImage,
        cgImage: CGImage,
        lines: [MedicationOCRLine],
        rawText: String
    ) -> MedicationImageQuality {
        let words = wordCount(rawText)
        let hasLowTextDensity = words < 4
        let isBlurry = max(image.size.width, image.size.height) < 700 || averageTextConfidence(lines) < 0.35
        let isLowLight = averageBrightness(cgImage: cgImage) < 0.24

        let minDimension = min(image.size.width * image.scale, image.size.height * image.scale)
        let isLowResolution = minDimension < 900

        var warnings: [String] = []
        if lines.isEmpty { warnings.append("no text found") }
        if hasLowTextDensity { warnings.append("too few words found") }
        if isBlurry { warnings.append("possible blurry image") }
        if isLowLight { warnings.append("possible low-light image") }
        if isLowResolution { warnings.append("low OCR resolution") }

        return MedicationImageQuality(
            isBlurry: isBlurry,
            isLowLight: isLowLight,
            hasLowTextDensity: hasLowTextDensity,
            warnings: warnings
        )
    }

    private static func wordCount(_ text: String) -> Int {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.trimmingCharacters(in: .punctuationCharacters).isEmpty }
            .count
    }

    private static func averageTextConfidence(_ lines: [MedicationOCRLine]) -> Double {
        let values = lines.compactMap(\.confidence)
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func averageBrightness(cgImage: CGImage) -> Double {
        let ciImage = CIImage(cgImage: cgImage)
        let extent = ciImage.extent
        guard !extent.isEmpty else { return 1 }

        let filter = CIFilter(name: "CIAreaAverage")
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(CIVector(cgRect: extent), forKey: kCIInputExtentKey)
        guard let output = filter?.outputImage else { return 1 }

        var bitmap = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()])
            .render(
                output,
                toBitmap: &bitmap,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: nil
            )

        let red = Double(bitmap[0]) / 255.0
        let green = Double(bitmap[1]) / 255.0
        let blue = Double(bitmap[2]) / 255.0
        return (red + green + blue) / 3.0
    }
}

private extension UIImage {
    var cgImagePropertyOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
