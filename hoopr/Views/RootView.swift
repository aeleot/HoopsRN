import SwiftUI

/// Gates the app behind authentication: nothing but the login screen is
/// reachable until Firebase reports a signed-in user.
struct RootView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        Group {
            if !authManager.hasLoadedInitialState {
                // Firebase restores a cached session asynchronously on launch.
                // Holding here avoids flashing the login screen at returning users.
                LaunchScreen()
            } else if !authManager.isSignedIn {
                LoginView()
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: authManager.userID)
        .animation(.easeInOut(duration: 0.2), value: authManager.hasLoadedInitialState)
    }
}

private struct LaunchScreen: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "basketball.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.hooprOrange)

            ProgressView()
                .tint(Color.hooprSecondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }
}

#Preview {
    RootView()
        .environmentObject(AuthManager())
}
