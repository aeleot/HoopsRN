import Combine
import SwiftUI
import UIKit

struct MainTabView: View {
    /// The five top-level destinations. Named `Screen` rather than `Tab`
    /// because `SwiftUI.Tab` is the builder used below and shadowing it here
    /// would make the `TabView` unreadable.
    private enum Screen: Hashable {
        case home
        case map
        case runs
        case seasons
        case profile
    }

    /// The inbox, presented with `sheet(item:)` like every other sheet in the
    /// app. A fresh `id` per request, so a second request while one is being
    /// dismissed is a new presentation rather than a no-op.
    private struct InboxRoute: Identifiable {
        let id = UUID()
    }

    /// Home, not the map. The map answers "where can I hoop?", which is a
    /// question you only have once you've decided to go out; Home answers
    /// "am I signed up for something tonight?", which is the more common
    /// reason to open the app at all.
    @State private var selectedScreen: Screen = .home
    @State private var inbox: InboxRoute?

    /// A court handed to the map from Home's hot list. The map consumes it and
    /// writes back `nil`, so tapping the same court twice selects it twice
    /// rather than going inert after the first.
    @State private var courtToShowOnMap: Court?

    /// A match the inbox asked to open. Handed to `SeasonsTab`, which replaces
    /// its stack with the match's screen and writes back `nil` — the
    /// `courtToShowOnMap` hand-off, for the Seasons tab.
    @State private var matchToOpen: SeasonsTab.MatchDestination?

    @ObservedObject private var authService: AuthService
    @ObservedObject private var userProfileService: UserProfileService
    private let courtService: CourtService
    private let locationService: LocationService
    private let gameService: GameService
    /// Plain `let`s: the badge that reads them is `InboxButton`, which
    /// observes both itself, so nothing here has to redraw when a request or
    /// an invite arrives.
    private let friendService: FriendService
    private let squadService: SquadService
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
        tabs
            // One inbox, presented over whichever tab is showing — by that
            // tab's `InboxButton`, by Home's friend-request row, and by a
            // tapped notification. Here rather than in each tab so there is
            // exactly one presenter and one route into it.
            .sheet(item: $inbox) { _ in
                inboxSheet {
                    inbox = nil
                }
            }
            // `@Published` replays its current value on subscription, so a
            // request left by the tap that *launched* the app — before this
            // view existed — is picked up the moment it appears, not only
            // ones that arrive while it's on screen.
            .onReceive(notificationService.$inboxRequest.compactMap { $0 }) { _ in
                notificationService.consumeInboxRequest()
                openInboxForNotification()
            }
            // The `seasonGames` listener, pointed at every squad the user is
            // on for the whole signed-in session. It used to be pointed from
            // the Seasons tab, which left it idle until that tab was first
            // opened — and the inbox now lists matches, which a notification
            // tap can open before any other screen has been shown. Squad
            // detail's history reads off the same listener, so a squad missing
            // from it would render an empty season rather than its own.
            .onReceive(squadService.$squads.map { $0.map(\.id) }.removeDuplicates()) { squadIds in
                seasonGameService.observe(squadIds: squadIds)
            }
    }

    /// The inbox with everything but its dismissal wired, so the sheet and the
    /// stacked presentation (`openInboxForNotification()`) build it one way.
    private func inboxSheet(onDismiss: @escaping () -> Void) -> InboxSheet {
        InboxSheet(
            friendService: friendService,
            squadService: squadService,
            userProfileService: userProfileService,
            courtService: courtService,
            seasonGameService: seasonGameService,
            onOpenMatch: openMatch,
            onDismiss: onDismiss
        )
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
                    onOpenInbox: openInbox,
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
                    onOpenInbox: openInbox
                )
            }

            Tab("Runs", systemImage: "calendar", value: Screen.runs) {
                LocalRunsTab(
                    gameService: gameService,
                    courtService: courtService,
                    userProfileService: userProfileService,
                    friendService: friendService,
                    squadService: squadService,
                    onOpenInbox: openInbox,
                    onOpenMap: {
                        courtToShowOnMap = nil
                        selectedScreen = .map
                    }
                )
            }

            // The widest label, measured before it was fixed: rendered at
            // `.accessibility3`, "Seasons" is 42pt wide — inside the 64pt slot
            // a five-tab bar gives it on a 320pt screen. It keeps the noun the
            // feature is actually called rather than being shortened to
            // "Squad" pre-emptively.
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
                    matchToOpen: $matchToOpen,
                    onOpenInbox: openInbox
                )
            }

            // Fifth, since 2026-09-25: the profile was a full-screen takeover
            // behind a person glyph in every tab's corner, and that corner
            // went to the inbox. `TabBarLabelTests` measures all five.
            Tab("Profile", systemImage: "person.crop.circle.fill", value: Screen.profile) {
                ProfileView(
                    authService: authService,
                    userProfileService: userProfileService,
                    courtService: courtService,
                    friendService: friendService,
                    squadService: squadService,
                    onOpenInbox: openInbox
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
        // rendering path the system takes for the `Tab` builder.
        .toolbarBackground(Color.hooprFill, for: .tabBar)
        .toolbarBackgroundVisibility(.visible, for: .tabBar)
    }

    private func openInbox() {
        inbox = InboxRoute()
    }

    /// A notification tap's route to the inbox, which — unlike a tap on the
    /// tray — can arrive while some other sheet is up: a half-filled
    /// `CreateGameSheet`, a profile edit, the queue. The `.sheet` above can't
    /// present then, because its presenter is already presenting, and the tap
    /// used to be silently lost.
    ///
    /// **So it stacks the inbox on top instead of closing what's there**
    /// (2026-09-25). Closing it would throw away whatever the person was in the
    /// middle of; stacked, Done returns them to it. It has to be UIKit to do
    /// that — a SwiftUI sheet can only be presented by the view that owns it,
    /// and the open sheet belongs to some tab. Nothing is presented → the
    /// ordinary sheet. The inbox already up → nothing to do.
    private func openInboxForNotification() {
        guard inbox == nil else { return }
        guard let top = ModalStack.topmost() else {
            openInbox()
            return
        }
        guard !(top is UIHostingController<InboxSheet>) else { return }

        let presenter = ModalStack.Weak()
        let host = UIHostingController(rootView: inboxSheet {
            presenter.controller?.dismiss(animated: true)
        })
        presenter.controller = host

        // An alert can't present anything. It's dismissed rather than kept:
        // an alert is a question, not work in progress, and it'll be asked
        // again by whatever raised it.
        if let alert = top as? UIAlertController, let under = alert.presentingViewController {
            alert.dismiss(animated: false) {
                under.present(host, animated: true)
            }
        } else {
            top.present(host, animated: true)
        }
    }

    /// A match row in the inbox: close the inbox, and anything stacked under
    /// it, then open the match on the Seasons tab — game day for a match to
    /// come, the result screen for one waiting on a report.
    private func openMatch(_ row: InboxMatchesViewModel.Row) {
        let destination: SeasonsTab.MatchDestination = switch row.kind {
        case .upcoming: .gameDay(mySquadId: row.mySquadId, game: row.game)
        case .report, .disputed: .result(mySquadId: row.mySquadId, game: row.game)
        }

        let navigate = {
            selectedScreen = .seasons
            matchToOpen = destination
        }

        if inbox != nil {
            inbox = nil
            navigate()
        } else {
            // The stacked inbox, over another sheet. Going to the match means
            // leaving that sheet too, so the whole stack is dismissed.
            ModalStack.dismissAll(completion: navigate)
        }
    }
}

/// The UIKit side of `openInboxForNotification()`: finding what's on top, and
/// clearing the stack. Kept here, beside its only caller.
private enum ModalStack {
    final class Weak {
        weak var controller: UIViewController?
    }

    private static var root: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        return scene?.keyWindow?.rootViewController
    }

    /// The top of the presentation stack, or `nil` when nothing is presented
    /// over the root — the case the ordinary `.sheet` handles.
    static func topmost() -> UIViewController? {
        guard var top = root?.presentedViewController else { return nil }
        while let next = top.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        return top.isBeingDismissed ? top.presentingViewController : top
    }

    static func dismissAll(completion: @escaping () -> Void) {
        guard let root, root.presentedViewController != nil else {
            completion()
            return
        }
        root.dismiss(animated: true, completion: completion)
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
