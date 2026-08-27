import SwiftUI

struct MainTabView: View {
    /// Home, not the map. The map answers "where can I hoop?", which is a
    /// question you only have once you've decided to go out; Home answers
    /// "am I signed up for something tonight?", which is the more common
    /// reason to open the app at all.
    ///
    /// The destination set itself lives on `HooprTab`, so the `TabView` here
    /// and the shelf that draws it read the same list in the same order.
    @State private var selectedScreen: HooprTab = .home
    @State private var showProfile = false

    /// A court handed to the map from Home's hot list. The map consumes it and
    /// writes back `nil`, so tapping the same court twice selects it twice
    /// rather than going inert after the first.
    @State private var courtToShowOnMap: Court?

    @ObservedObject private var authService: AuthService
    @ObservedObject private var userProfileService: UserProfileService
    private let courtService: CourtService
    private let locationService: LocationService
    private let gameService: GameService
    /// Observed, unlike the other services held here, because `ProfileButton`
    /// reads it: the button carries a dot while a friend request is unanswered,
    /// and a plain `let` wouldn't redraw when one arrives.
    @ObservedObject private var friendService: FriendService
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
    }

    var body: some View {
        // The profile takes over the whole screen — it has its own header and
        // back button — so it replaces this interface rather than rendering
        // inside it. That is also what satisfies "the profile button appears
        // everywhere except the profile": there is no tab bar behind it.
        if showProfile {
            ProfileView(
                authService: authService,
                userProfileService: userProfileService,
                courtService: courtService,
                friendService: friendService
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showProfile = false
                }
            }
            .transition(.opacity)
        } else {
            tabs
        }
    }

    /// A `TabView` for its content and its state retention, with the system's
    /// bar hidden and `HooprTabBar` drawn in its place.
    ///
    /// **The split is deliberate.** `TabView` is what keeps every tab's state
    /// alive once mounted — the map's region, zoom and sheet detent survive a
    /// switch for free, which the pre-2026-08-26 shell was faking with
    /// `.opacity` on a permanently mounted `MapTab`. That is worth keeping. But
    /// iOS 26 draws its bar as a floating pill centred over the content, and a
    /// shelf that reaches both screen edges is not something the platform
    /// exposes a way to ask for, so the bar itself is hand-drawn. See
    /// `HooprTabBar` for what that costs and how each piece is earned back.
    ///
    /// `.safeAreaInset` rather than a `ZStack`: the shelf has to *reserve* its
    /// height, not float over the content. `MapTab` sizes its sheet from
    /// `safeAreaInsets.bottom`, and this is what keeps that number honest.
    private var tabs: some View {
        TabView(selection: $selectedScreen) {
            Tab(HooprTab.home.title, systemImage: HooprTab.home.symbol, value: HooprTab.home) {
                HomeTab(
                    authService: authService,
                    courtService: courtService,
                    gameService: gameService,
                    userProfileService: userProfileService,
                    friendService: friendService,
                    onOpenProfile: openProfile,
                    onOpenRuns: { selectedScreen = .runs },
                    onOpenMap: { court in
                        courtToShowOnMap = court
                        selectedScreen = .map
                    }
                )
            }

            Tab(HooprTab.map.title, systemImage: HooprTab.map.symbol, value: HooprTab.map) {
                MapTab(
                    courtService: courtService,
                    locationService: locationService,
                    userProfileService: userProfileService,
                    gameService: gameService,
                    recentCourtsStore: recentCourtsStore,
                    friendService: friendService,
                    courtToSelect: $courtToShowOnMap,
                    onOpenProfile: openProfile
                )
            }

            Tab(HooprTab.runs.title, systemImage: HooprTab.runs.symbol, value: HooprTab.runs) {
                LocalRunsTab(
                    gameService: gameService,
                    courtService: courtService,
                    userProfileService: userProfileService,
                    friendService: friendService,
                    onOpenProfile: openProfile
                )
            }
        }
        // The system bar is hidden, not restyled — it cannot be made to span
        // the screen. `HooprTabBar` below takes its place.
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HooprTabBar(selection: $selectedScreen)
        }
    }

    private func openProfile() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showProfile = true
        }
    }
}

#Preview {
    let authService = AuthService()
    MainTabView(
        authService: authService,
        courtService: CourtService(),
        locationService: LocationService(),
        userProfileService: UserProfileService(authService: authService),
        gameService: GameService(authService: authService),
        friendService: FriendService(authService: authService),
        recentCourtsStore: RecentCourtsStore()
    )
}
