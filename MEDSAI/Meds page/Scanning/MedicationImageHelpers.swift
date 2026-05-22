import UIKit

extension UIImage {
    func fixedOrientation() -> UIImage {
        if imageOrientation == .up { return self }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        return autoreleasepool {
            UIGraphicsImageRenderer(size: size, format: format).image { _ in
                self.draw(in: CGRect(origin: .zero, size: size))
            }
        }
    }

    func downscaledForOCR(maxDimension: CGFloat = 2200) -> UIImage {
        downscaledForMedicationScan(maxDimension: maxDimension)
    }

    func downscaledForPreview(maxDimension: CGFloat = 900) -> UIImage {
        downscaledForMedicationScan(maxDimension: maxDimension)
    }

    func downscaledForFallback(maxDimension: CGFloat = 1800) -> UIImage {
        downscaledForMedicationScan(maxDimension: maxDimension)
    }

    func jpegDataForScanFallback(maxDimension: CGFloat = 1400, quality: CGFloat = 0.78) -> Data? {
        autoreleasepool {
            let image = downscaledForMedicationScan(maxDimension: maxDimension)
            return image.jpegData(compressionQuality: quality)
        }
    }

    private func downscaledForMedicationScan(maxDimension: CGFloat) -> UIImage {
        guard maxDimension > 0 else { return self }

        let pixelWidth = CGFloat(cgImage?.width ?? Int(size.width * scale))
        let pixelHeight = CGFloat(cgImage?.height ?? Int(size.height * scale))
        let longestSide = max(pixelWidth, pixelHeight)
        let targetScale = longestSide > maxDimension ? maxDimension / longestSide : 1
        let targetSize = CGSize(
            width: max(1, round(pixelWidth * targetScale)),
            height: max(1, round(pixelHeight * targetScale))
        )

        guard targetScale < 1 || imageOrientation != .up || scale != 1 else { return self }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return autoreleasepool {
            UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
                self.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        }
    }
}

