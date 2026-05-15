import SwiftUI

// MARK: - MEDSAILoadingView
// Full-screen branded loading screen using the app's GIF animation.
// Drop on any view:  .loadingOverlay(isLoading: $isLoading)
//                    .loadingOverlay(isLoading: $isLoading, message: "Checking safety…")

struct MEDSAILoadingView: View {
    var message: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                GIFView(named: "medsai_loading")
                    .frame(width: 220, height: 220)

                if let msg = message {
                    Text(msg)
                        .font(.subheadline)
                        .foregroundColor(Color(hex: "#4ADE80").opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.25)))
    }
}

// MARK: - LoadingOverlayModifier
private struct LoadingOverlayModifier: ViewModifier {
    let isLoading: Bool
    var message: String?

    func body(content: Content) -> some View {
        ZStack {
            content
            if isLoading {
                MEDSAILoadingView(message: message)
                    .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

// MARK: - View Extension  (one-liner usage)
extension View {
    /// Overlay the full-screen MEDSAI loading animation whenever `isLoading` is true.
    ///
    ///     .loadingOverlay(isLoading: viewModel.isFetching)
    ///     .loadingOverlay(isLoading: viewModel.isFetching, message: "Checking interactions…")
    func loadingOverlay(isLoading: Bool, message: String? = nil) -> some View {
        modifier(LoadingOverlayModifier(isLoading: isLoading, message: message))
    }
}

// MARK: - Hex colour helper (local, avoids import conflicts)
private extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        let v = UInt64(h, radix: 16) ?? 0
        let r = Double((v >> 16) & 0xFF) / 255
        let g = Double((v >>  8) & 0xFF) / 255
        let b = Double( v        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
