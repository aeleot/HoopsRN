import SwiftUI

/// Gates the app behind authentication: nothing but the login screen is
/// reachable until Firebase reports a signed-in user.
struct RootView: View {
    @StateObject private var viewModel: RootViewModel

    private let authService: AuthService
    private let courtService: CourtService
    private let locationService: LocationService
    private let userProfileService: UserProfileService
    private let gameService: GameService
    private let friendService: FriendService
    private let recentCourtsStore: RecentCourtsStore

    init(
        authService: AuthService,
        courtService: CourtService,
        locationService: LocationService,
        userProfileService: UserProfileService,
        gameService: GameService,
        friendService: FriendService,
        recentCourtsStore: RecentCourtsStore
    ) {
        self.authService = authService
        self.courtService = courtService
        self.locationService = locationService
        self.userProfileService = userProfileService
        self.gameService = gameService
        self.friendService = friendService
        self.recentCourtsStore = recentCourtsStore
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
                    userProfileService: userProfileService,
                    gameService: gameService,
                    friendService: friendService,
                    recentCourtsStore: recentCourtsStore
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
                .hooprFont(44)
                .foregroundStyle(Color.hooprBrandText)

            ProgressView()
                .tint(Color.hooprSecondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.hooprBackground)
    }
}

#Preview {
    let authService = AuthService()
    RootView(
        authService: authService,
        courtService: CourtService(),
        locationService: LocationService(),
        userProfileService: UserProfileService(authService: authService),
        gameService: GameService(authService: authService),
        friendService: FriendService(authService: authService),
        recentCourtsStore: RecentCourtsStore()
    )
}
