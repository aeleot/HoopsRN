import SwiftUI
import UIKit

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
    /// Observed, same reason as `friendService`: `ProfileButton`'s badge now
    /// carries squad invites too, and it reads this directly rather than
    /// through whichever screen's own `SquadViewModel` happens to be alive.
    @ObservedObject private var squadService: SquadService
    private let matchmakingService: MatchmakingService
    private let seasonGameService: SeasonGameService
    private let notificationService: NotificationService
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
        notificationService: NotificationService,
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
        self.notificationService = notificationService
        self.recentCourtsStore = recentCourtsStore

        Self.configureTabBarAppearance()
    }

    /// Gives the bar a fixed, opaque presence instead of the system's default
    /// floating glass, which reads as translucent chrome rather than a
    /// permanent fixture. `hooprFill` — the "filled but unemphasised region"
    /// role already used for field backgrounds — is the surface; the selected
    /// item sits on `hooprHoverFill`, the same "selected without being loud"
    /// role a pressed row uses.
    ///
    /// Set on `UITabBar.appearance()` rather than a per-instance property:
    /// SwiftUI's `TabView` still bridges to `UITabBarController` on iPhone, so
    /// the proxy default is what the bar it builds actually reads. Idempotent,
    /// so calling it from every `init()` is harmless.
    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.hooprFill)
        appearance.selectionIndicatorTintColor = UIColor(Color.hooprHoverFill)

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
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
                friendService: friendService,
                squadService: squadService
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
                    squadService: squadService,
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
                    squadService: squadService,
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
                    squadService: squadService,
                    onOpenProfile: openProfile,
                    onOpenMap: {
                        courtToShowOnMap = nil
                        selectedScreen = .map
                    }
                )
            }

            // Fourth, and the practical ceiling. The label was measured before
            // it was fixed: rendered at `.accessibility3`,
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
                    matchmakingService: matchmakingService,
                    seasonGameService: seasonGameService,
                    friendService: friendService,
                    userProfileService: userProfileService,
                    courtService: courtService,
                    notificationService: notificationService,
                    onOpenProfile: openProfile
                )
            }
        }
        // Selected items take the brand mark; unselected ones stay in the
        // system's grey. `hooprBrandAccent`, not `hooprOrange`: the tint colours
        // the glyph *and* its ~10pt label, so this is the brand drawn as a
        // foreground, which the filled orange fails as (3.17:1 on white).
        // iOS 26 also adjusts a tint before drawing it — it rendered
        // `hooprOrange` as `#E55E27` in light and `#FF8F6A` in dark — so the
        // assertion in `ThemeContrastTests` is on the nominal value this hands
        // over, and the rendered figure is re-measured from a screenshot.
        .tint(Color.hooprBrandAccent)
        // Belt-and-suspenders with `configureTabBarAppearance()`: this is the
        // SwiftUI-native path to the same fixed, opaque bar, for whichever
        // rendering path the system takes for the four-item `Tab` builder.
        .toolbarBackground(Color.hooprFill, for: .tabBar)
        .toolbarBackgroundVisibility(.visible, for: .tabBar)
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
        matchmakingService: MatchmakingService(authService: authService),
        seasonGameService: SeasonGameService(authService: authService),
        notificationService: NotificationService(),
        recentCourtsStore: RecentCourtsStore()
    )
}
