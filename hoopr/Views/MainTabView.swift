import SwiftUI

struct MainTabView: View {
    /// The four top-level destinations. Named `Screen` rather than `Tab`
    /// because `SwiftUI.Tab` is the builder used below and shadowing it here
    /// would make the `TabView` unreadable.
    private enum Screen: Hashable {
        case home
        case map
        case runs
        case seasons
    }

    /// Home, not the map. The map answers "where can I hoop?", which is a
    /// question you only have once you've decided to go out; Home answers
    /// "am I signed up for something tonight?", which is the more common
    /// reason to open the app at all.
    @State private var selectedScreen: Screen = .home
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
    private let squadService: SquadService
    private let recentCourtsStore: RecentCourtsStore

    init(
        authService: AuthService,
        courtService: CourtService,
        locationService: LocationService,
        userProfileService: UserProfileService,
        gameService: GameService,
        friendService: FriendService,
        squadService: SquadService,
        recentCourtsStore: RecentCourtsStore
    ) {
        self.authService = authService
        self.courtService = courtService
        self.locationService = locationService
        self.userProfileService = userProfileService
        self.gameService = gameService
        self.friendService = friendService
        self.squadService = squadService
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

    /// A native `TabView`, not the hand-rolled glass header this replaced.
    ///
    /// The header was pinned to 14% of the screen and floated over the content,
    /// which cost three things the system gives away: the pills were ~40pt tall
    /// against Apple's 44pt floor, the greeting and the labels both had to
    /// carry `minimumScaleFactor` to survive Dynamic Type, and the bar needed a
    /// `contentShape` on a clear fill just so taps stopped falling through to
    /// MapKit. A real tab bar is 44pt-compliant, Dynamic Type-aware,
    /// VoiceOver-labelled and hit-tested by the system.
    ///
    /// It also keeps every tab's state alive once mounted, which is what the
    /// old shell was faking with `.opacity`/`.allowsHitTesting` on a permanently
    /// mounted `MapTab`.
    private var tabs: some View {
        TabView(selection: $selectedScreen) {
            Tab("Home", systemImage: "house.fill", value: Screen.home) {
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

            Tab("Map", systemImage: "map.fill", value: Screen.map) {
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

            Tab("Runs", systemImage: "calendar", value: Screen.runs) {
                LocalRunsTab(
                    gameService: gameService,
                    courtService: courtService,
                    userProfileService: userProfileService,
                    friendService: friendService,
                    onOpenProfile: openProfile
                )
            }

            // Fourth, and the practical ceiling. The label was measured before
            // it was fixed, per the plan's §5: rendered at `.accessibility3`,
            // "Seasons" is 42pt wide in the 80pt slot a four-tab bar gives it
            // on a 320pt screen. It keeps the noun the feature is actually
            // called rather than being shortened to "Squad" pre-emptively.
            //
            // The reason there's room is worth knowing — `UITabBar` clamps its
            // own content size category at XXL and shows the large-content HUD
            // at accessibility sizes instead of growing the titles, so these
            // labels stay at 10pt however large the reader's text is. That's
            // UIKit's behaviour, not ours, so `TabBarLabelTests` asserts the
            // outcome (every label fits) rather than the clamp.
            Tab("Seasons", systemImage: "trophy.fill", value: Screen.seasons) {
                SeasonsTab(
                    squadService: squadService,
                    friendService: friendService,
                    userProfileService: userProfileService,
                    courtService: courtService,
                    onOpenProfile: openProfile
                )
            }
        }
        // Selected items take the brand orange; unselected ones stay in the
        // system's grey. Worth knowing: this paints the brand as a *foreground*
        // on a light ground, which is the pairing `GAPS.md` tracks as failing
        // AA — see `ThemeContrastTests.testTabBarSelectionIsATrackedGap`.
        .tint(Color.hooprOrange)
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
        squadService: SquadService(authService: authService),
        recentCourtsStore: RecentCourtsStore()
    )
}
