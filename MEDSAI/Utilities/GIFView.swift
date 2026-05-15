import SwiftUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

// MARK: - GIFView
// Plays a bundled GIF file using UIImageView + ImageIO — no third-party deps.
// Usage:  GIFView(named: "medsai_loading")

struct GIFView: UIViewRepresentable {
    let named: String

    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .clear
        if let image = GIFView.animatedImage(named: named) {
            imageView.image = image
        }
        return imageView
    }

    func updateUIView(_ uiView: UIImageView, context: Context) {}

    // MARK: - GIF Decoder
    static func animatedImage(named name: String) -> UIImage? {
        let extensions = ["gif", "GIF"]
        var url: URL?
        for ext in extensions {
            if let u = Bundle.main.url(forResource: name, withExtension: ext) {
                url = u; break
            }
        }
        guard let gifURL = url,
              let data = try? Data(contentsOf: gifURL) else { return nil }
        return animatedImage(data: data)
    }

    static func animatedImage(data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        var images: [UIImage] = []
        var totalDuration: Double = 0

        for i in 0 ..< count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let frameDuration = GIFView.frameDuration(at: i, source: source)
            totalDuration += frameDuration
            // Repeat each frame proportionally (target 60 fps bucket)
            let frameCount = max(1, Int(frameDuration * 60))
            for _ in 0 ..< frameCount {
                images.append(UIImage(cgImage: cgImage))
            }
        }

        return UIImage.animatedImage(with: images, duration: totalDuration)
    }

    private static func frameDuration(at index: Int, source: CGImageSource) -> Double {
        let defaultDuration = 0.1
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
              let gifProps = props[kCGImagePropertyGIFDictionary as String] as? [String: Any]
        else { return defaultDuration }

        let unclampedDelay = gifProps[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double
        let delay = gifProps[kCGImagePropertyGIFDelayTime as String] as? Double
        let duration = unclampedDelay ?? delay ?? defaultDuration
        return duration < 0.011 ? defaultDuration : duration
    }
}
