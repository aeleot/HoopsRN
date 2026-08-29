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
    private let squadService: SquadService
    private let matchmakingService: MatchmakingService
    private let seasonGameService: SeasonGameService
    private let recentCourtsStore: RecentCourtsStore

    init(
        authService: AuthService,
        courtService: CourtService,
        locationService: LocationService,
        userProfileService: UserProfileService,
        gameService: GameService,
        friendService: FriendService,
        squadService: SquadService,
        matchmakingService: MatchmakingService,
        seasonGameService: SeasonGameService,
        recentCourtsStore: RecentCourtsStore
    ) {
        self.authService = authService
        self.courtService = courtService
        self.locationService = locationService
        self.userProfileService = userProfileService
        self.gameService = gameService
        self.friendService = friendService
        self.squadService = squadService
        self.matchmakingService = matchmakingService
        self.seasonGameService = seasonGameService
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
                    squadService: squadService,
                    matchmakingService: matchmakingService,
                    seasonGameService: seasonGameService,
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
                .foregroundStyle(Color.hooprOrange)

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
        squadService: SquadService(authService: authService),
        matchmakingService: MatchmakingService(authService: authService),
        seasonGameService: SeasonGameService(authService: authService),
        recentCourtsStore: RecentCourtsStore()
    )
}
