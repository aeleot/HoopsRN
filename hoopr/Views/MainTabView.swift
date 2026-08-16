import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var showProfile = false

    @ObservedObject private var authService: AuthService
    @ObservedObject private var userProfileService: UserProfileService
    private let courtService: CourtService
    private let locationService: LocationService
    private let gameService: GameService
    /// Observed, unlike the other services held here, because the header itself
    /// reads it: the Friends pill carries a dot while a request is unanswered,
    /// and a plain `let` wouldn't redraw when one arrives.
    @ObservedObject private var friendService: FriendService
    private let recentCourtsStore: RecentCourtsStore

    private let tabs: [(String, String)] = [
        ("Court Map", "map"),
        ("Local Runs", "calendar"),
        ("Friends", "person.2.fill"),
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
                courtService: courtService
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
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()

                    HStack {
                        // The whole header is pinned to 14% of the screen
                        // below, so the type in it is capped and allowed to
                        // shrink rather than being clipped by its own bar.
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
                        }
                        .accessibilityLabel("Profile")
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                    HStack(spacing: 6) {
                        ForEach(0..<tabs.count, id: \.self) { index in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedTab = index
                                }
                            } label: {
                                // Three tabs share one row inside the pinned
                                // header, so these are capped tightly and
                                // scale down before they'd truncate.
                                HStack(spacing: 5) {
                                    Image(systemName: tabs[index].1)
                                        .hooprFont(12, weight: .medium, maximumSize: 15)
                                    Text(tabs[index].0)
                                        .hooprFont(12, weight: .semibold, maximumSize: 15)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)

                                    // A dot, not a count: the pills share one
                                    // row inside a header pinned to 14% of the
                                    // screen, and there's no width for a
                                    // number. The exact figure is on the
                                    // inbox button one tap away.
                                    if hasUnansweredRequests(at: index) {
                                        Circle()
                                            .fill(
                                                selectedTab == index
                                                    ? Color.hooprOnBrand
                                                    : Color.hooprOrange
                                            )
                                            .frame(width: 6, height: 6)
                                    }
                                }
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity)
                                .background(
                                    selectedTab == index ? Color.hooprOrange : Color.hooprFill
                                )
                                .foregroundStyle(
                                    selectedTab == index ? Color.hooprOnBrand : Color.hooprSecondaryText
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .accessibilityLabel(
                                hasUnansweredRequests(at: index)
                                    ? "\(tabs[index].0), requests waiting"
                                    : tabs[index].0
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .frame(height: geo.size.height * 0.14)
                .background(Color.hooprBackground)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.hooprBorder)
                        .frame(height: 1)
                }
                .zIndex(1)

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
                    }

                    if selectedTab == 2 {
                        FriendsTab(
                            friendService: friendService,
                            userProfileService: userProfileService,
                            courtService: courtService
                        )
                    }
                }
                .clipped()
            }
        }
        .ignoresSafeArea(edges: .bottom)
    }

    /// Reads the stored profile name. Falls back to a neutral greeting while
    /// the first snapshot is in flight or before provisioning finishes.
    private var userName: String {
        userProfileService.currentProfile?.userName ?? "there"
    }

    /// Whether the tab at `index` should carry a badge dot.
    ///
    /// Only Friends has one, and only for *incoming* requests — a request you
    /// sent isn't waiting on you. Reading the service directly rather than
    /// through `FriendsViewModel` keeps the dot alive while the tab is
    /// unmounted, which is the entire reason it's here: an inbox you can only
    /// discover by already being on its tab isn't a notification.
    private func hasUnansweredRequests(at index: Int) -> Bool {
        index == friendsTabIndex && !friendService.incomingRequests.isEmpty
    }

    private var friendsTabIndex: Int { 2 }
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
