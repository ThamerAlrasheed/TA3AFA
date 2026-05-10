import SwiftUI

struct RootView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Group {
            if shouldShowMainApp {
                RootTabView()
            } else {
                LandingPageView()
            }
        }
        .animation(.default, value: shouldShowMainApp)
        .alert("Access Revoked", isPresented: Binding(
            get: { settings.sessionRevokedMessage != nil },
            set: { if !$0 { settings.sessionRevokedMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let msg = settings.sessionRevokedMessage {
                Text(msg)
            }
        }
    }

    private var shouldShowMainApp: Bool {
        // Regular/caregiver users: require Supabase Auth session
        // Patient users: require device token (passwordless)
        guard settings.onboardingCompleted && settings.didChooseEntry else { return false }
        return SupabaseManager.shared.currentUserID != nil
    }
}
