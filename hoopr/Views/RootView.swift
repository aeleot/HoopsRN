import SwiftUI

/// Gates the app behind authentication: nothing but the login screen is
/// reachable until Firebase reports a signed-in user.
struct RootView: View {
    @StateObject private var viewModel: RootViewModel

    private let authService: AuthService
    private let courtService: CourtService
    private let locationService: LocationService
    private let userProfileService: UserProfileService

    init(
        authService: AuthService,
        courtService: CourtService,
        locationService: LocationService,
        userProfileService: UserProfileService
    ) {
        self.authService = authService
        self.courtService = courtService
        self.locationService = locationService
        self.userProfileService = userProfileService
        _viewModel = StateObject(wrappedValue: RootViewModel(authService: authService))
    }

    var body: some View {
        Group {
            switch viewModel.destination {
            case .launching:
                LaunchScreen()
            case .login:
                LoginView(authService: authService)
                    .transition(.opacity)
            case .main:
                MainTabView(
                    authService: authService,
                    courtService: courtService,
                    locationService: locationService,
                    userProfileService: userProfileService
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.destination)
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
    let authService = AuthService()
    RootView(
        authService: authService,
        courtService: CourtService(),
        locationService: LocationService(),
        userProfileService: UserProfileService(authService: authService)
    )
}
