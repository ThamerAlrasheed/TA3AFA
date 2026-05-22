import SwiftUI

// MARK: - MEDSAILoadingView
// Compatibility wrapper for older call sites. New loading UI should use ISTSEHLoadingView directly.

struct MEDSAILoadingView: View {
    var message: String?

    var body: some View {
        ISTSEHLoadingView(
            message: message ?? LoadingMessage.profile.text,
            style: .fullScreen
        )
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
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .zIndex(998)

                ISTSEHLoadingView(
                    message: message ?? LoadingMessage.profile.text,
                    style: .card
                )
                .padding(.horizontal, 28)
                .zIndex(999)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

// MARK: - View Extension
extension View {
    func loadingOverlay(isLoading: Bool, message: String? = nil) -> some View {
        modifier(LoadingOverlayModifier(isLoading: isLoading, message: message))
    }
}
