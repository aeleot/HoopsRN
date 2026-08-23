import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showProfile = false

    @ObservedObject private var authService: AuthService
    @ObservedObject private var userProfileService: UserProfileService
    private let courtService: CourtService
    private let locationService: LocationService
    private let gameService: GameService
    /// Observed, unlike the other services held here, because the header
    /// itself reads it: the profile button carries a dot while a friend request
    /// is unanswered, and a plain `let` wouldn't redraw when one arrives.
    @ObservedObject private var friendService: FriendService
    private let recentCourtsStore: RecentCourtsStore

    /// Two tabs, not three: Friends moved into `ProfileView` as a pane, which
    /// is what freed this slot. Adding the next one means adding a case here
    /// and a branch in `content(headerHeight:)` — nothing else in the header is
    /// written for a fixed count.
    private let tabs: [(String, String)] = [
        ("Court Map", "map"),
        ("Local Runs", "calendar"),
    ]

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
        // inside it.
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
            mainInterface
        }
    }

    private var mainInterface: some View {
        GeometryReader { geo in
            let headerHeight = geo.size.height * 0.14

            // The header floats *over* the content rather than stacking above
            // it, so the map can run to every edge of the screen. The two list
            // tabs get the header's height back as safe area, which lets their
            // scroll content pass under the glass instead of starting below it.
            ZStack(alignment: .top) {
                content(headerHeight: headerHeight)

                header
                    .frame(height: headerHeight)
                    .frame(maxWidth: .infinity)
                    .background(alignment: .top) {
                        // Extended past the top safe area so the glass carries
                        // on under the status bar — otherwise the clock sits
                        // directly on the map.
                        //
                        // `contentShape` is load-bearing, not decoration: the
                        // bar's fill is clear, a clear fill doesn't hit-test,
                        // and the map is now its ZStack sibling *underneath*
                        // rather than a panel below it. Without this, every
                        // tap and drag on the header reached MapKit and panned
                        // the map — including taps on the tab pills.
                        Rectangle()
                            .fill(.clear)
                            .glassEffect(.regular, in: .rect)
                            .contentShape(Rectangle())
                            .ignoresSafeArea(edges: .top)
                    }
            }
            .environment(\.floatingHeaderHeight, headerHeight)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func content(headerHeight: CGFloat) -> some View {
        ZStack {
            MapTab(
                courtService: courtService,
                locationService: locationService,
                userProfileService: userProfileService,
                gameService: gameService,
                recentCourtsStore: recentCourtsStore
            )
                .opacity(selectedTab == 0 ? 1 : 0)
                .allowsHitTesting(selectedTab == 0)

            if selectedTab == 1 {
                LocalRunsTab(
                    gameService: gameService,
                    courtService: courtService,
                    userProfileService: userProfileService
                )
                .safeAreaPadding(.top, headerHeight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            HStack {
                // The whole header is pinned to 14% of the screen below, so
                // the type in it is capped and allowed to shrink rather than
                // being clipped by its own bar.
                Text("Let's go hoop \(Text(userName).fontWeight(.bold)).")
                    .hooprFont(28, maximumSize: 34)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showProfile = true
                    }
                } label: {
                    Image(systemName: "person.crop.circle.fill")
                        .hooprFont(32, maximumSize: 38)
                        .foregroundStyle(Color.hooprSecondaryText)
                        // The Friends pill used to carry this dot. Friends is a
                        // pane of the profile now, so the button that opens the
                        // profile is what says something is waiting inside it.
                        //
                        // Red, matching the inbox badge it leads to, and not
                        // the brand orange: this header is already orange in
                        // places, and a notification has to read as one thing
                        // to deal with rather than as more brand.
                        .overlay(alignment: .topTrailing) {
                            if hasUnansweredRequests {
                                Circle()
                                    .fill(Color.hooprRed)
                                    // A ring in the header's own colour, so the
                                    // dot reads as sitting on the glyph rather
                                    // than as part of it.
                                    .stroke(Color.hooprBackground, lineWidth: 2)
                                    .frame(width: 11, height: 11)
                                    .offset(x: 1, y: -1)
                            }
                        }
                }
                .accessibilityLabel(
                    hasUnansweredRequests ? "Profile, requests waiting" : "Profile"
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            HStack(spacing: 6) {
                ForEach(0..<tabs.count, id: \.self) { index in
                    let isSelected = selectedTab == index

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = index
                        }
                    } label: {
                        // The pills share one row inside the pinned
                        // header, so these are capped tightly and scale down
                        // before they'd truncate.
                        HStack(spacing: 5) {
                            Image(systemName: tabs[index].1)
                                .hooprFont(12, weight: .medium, maximumSize: 15)
                            Text(tabs[index].0)
                                .hooprFont(12, weight: .semibold, maximumSize: 15)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(
                            isSelected ? Color.hooprOnBrand : Color.hooprPrimaryText
                        )
                        // The pills sit on glass now, so an unselected one is
                        // clear glass rather than an opaque grey fill — which
                        // over a moving map would read as a hole in the bar.
                        .glassEffect(
                            isSelected
                                ? .regular.tint(Color.hooprOrange).interactive()
                                : .clear.interactive(),
                            in: .rect(cornerRadius: 12)
                        )
                    }
                    .accessibilityLabel(tabs[index].0)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    /// Reads the stored profile name. Falls back to a neutral greeting while
    /// the first snapshot is in flight or before provisioning finishes.
    private var userName: String {
        userProfileService.currentProfile?.userName ?? "there"
    }

    /// Whether the profile button should carry a badge dot.
    ///
    /// Only *incoming* requests count — a request you sent isn't waiting on
    /// you. Reading the service directly rather than through `FriendsViewModel`
    /// keeps the dot alive while the profile is closed, which is the entire
    /// reason it's here: an inbox you can only discover by already being inside
    /// it isn't a notification.
    private var hasUnansweredRequests: Bool {
        !friendService.incomingRequests.isEmpty
    }
}

/// How tall the header hovering over the content is.
///
/// The two list tabs get this back as safe-area padding, which `MainTabView`
/// applies for them. The map tab can't: its whole point is that the map runs
/// underneath the header, so only its *floating chrome* is inset — and that
/// happens deep enough inside `MapTab` that threading it through as an
/// initialiser argument would mean the shell dictating a private layout
/// detail of one tab.
extension EnvironmentValues {
    @Entry var floatingHeaderHeight: CGFloat = 0
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
