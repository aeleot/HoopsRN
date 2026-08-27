import SwiftUI

/// The Home tab: what you're committed to, then where the action is.
///
/// The app used to open on the map. The map answers "where can I hoop?" — a
/// question you only have once you've already decided to go out. It can't
/// answer "am I signed up for something tonight?", which is the more common
/// reason to open the app at all, so that answer is what this screen leads
/// with.
///
/// Every card here reads state the app already holds. There is deliberately no
/// stats card: nothing records that a run happened yet, so "runs this week"
/// and a streak have no honest source. See `HomeViewModel`.
struct HomeTab: View {
    @StateObject private var viewModel: HomeViewModel
    @ObservedObject private var friendService: FriendService

    /// Handed up rather than handled here — switching tabs is the shell's job,
    /// and Home is the one screen that wants to send you somewhere else.
    let onOpenProfile: () -> Void
    let onOpenRuns: () -> Void
    let onOpenMap: (Court?) -> Void

    init(
        authService: AuthService,
        courtService: CourtService,
        gameService: GameService,
        userProfileService: UserProfileService,
        friendService: FriendService,
        onOpenProfile: @escaping () -> Void,
        onOpenRuns: @escaping () -> Void,
        onOpenMap: @escaping (Court?) -> Void
    ) {
        self.friendService = friendService
        self.onOpenProfile = onOpenProfile
        self.onOpenRuns = onOpenRuns
        self.onOpenMap = onOpenMap
        _viewModel = StateObject(wrappedValue: HomeViewModel(
            authService: authService,
            courtService: courtService,
            gameService: gameService,
            userProfileService: userProfileService,
            friendService: friendService
        ))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                section("Next run") {
                    if let listing = viewModel.nextRun {
                        nextRunCard(listing)
                    } else {
                        noRunCard
                    }
                }

                section("Hot right now") {
                    hotCourtsCard
                }

                if viewModel.incomingRequestCount > 0 {
                    friendRequestBanner
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
        .background(Color.hooprBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header

    /// The greeting the floating header used to carry. It gets a full line
    /// here instead of 14% of the screen minus a profile button, so it no
    /// longer has to scale itself down to fit.
    private var header: some View {
        HStack(alignment: .top) {
            Text("Let's go hoop \(Text(viewModel.greetingName).fontWeight(.bold)).")
                .hooprFont(28, maximumSize: 40)
                .foregroundStyle(Color.hooprPrimaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            ProfileButton(friendService: friendService, action: onOpenProfile)
                .offset(x: 8)
        }
        .padding(.top, 8)
    }

    /// One section label plus its content. Every card on this screen is
    /// introduced the same way, so the shape lives here once.
    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .hooprFont(12, weight: .bold, maximumSize: 16)
                .kerning(0.6)
                .foregroundStyle(Color.hooprSecondaryText)

            content()
        }
    }

    // MARK: - Next run

    /// Read-only on purpose. `GameCard` carries join/leave/cancel and the
    /// invite link, which are decisions that belong on the runs list; here the
    /// card is a pointer to that list, so the only thing it does is navigate.
    private func nextRunCard(_ listing: LocalRunsViewModel.Listing) -> some View {
        Button(action: onOpenRuns) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "basketball.fill")
                        .hooprFont(18)
                        .foregroundStyle(Color.hooprOrange)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(listing.courtName)
                            .hooprFont(17, weight: .semibold)
                            .foregroundStyle(Color.hooprPrimaryText)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        Text(listing.game.scheduledText())
                            .hooprFont(14, weight: .medium)
                            .foregroundStyle(Color.hooprSecondaryText)
                    }

                    Spacer(minLength: 8)

                    if let badge {
                        Text(badge.text)
                            .hooprFont(11, weight: .bold)
                            .foregroundStyle(badge.tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(badge.tint.opacity(0.12)))
                    }
                }

                HStack(spacing: 14) {
                    detail(symbol: "person.2.fill", text: listing.game.rosterText)

                    if let distanceText = listing.distanceText {
                        detail(symbol: "location.fill", text: distanceText)
                    }

                    Spacer(minLength: 0)
                }

                capacityBar(for: listing.game)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardChrome()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap to open your runs")
    }

    /// Matches `GameCard`'s priority order — your own relationship to the run
    /// says more than its status does.
    private var badge: (text: String, tint: Color)? {
        if viewModel.isHostingNextRun { return ("HOSTING", Color.hooprOrange) }
        if viewModel.isWaitlistedOnNextRun { return ("WAITLIST", Color.hooprSecondaryText) }
        if viewModel.nextRun?.game.isFull == true { return ("FULL", Color.hooprSecondaryText) }
        return nil
    }

    private func detail(symbol: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .hooprFont(11)
            Text(text)
                .hooprFont(13)
        }
        .foregroundStyle(Color.hooprSecondaryText)
    }

    /// How full the run is, at a glance — the same bar `GameCard` draws, so a
    /// run reads identically on both screens.
    private func capacityBar(for game: Game) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.hooprFill)

                Capsule()
                    .fill(game.isFull ? Color.hooprSecondaryText : Color.hooprOrange)
                    .frame(width: geo.size.width * filledFraction(for: game))
            }
        }
        .frame(height: 5)
        .accessibilityLabel(game.rosterText)
    }

    /// Clamped, so a hand-edited over-full roster can't draw past the track.
    private func filledFraction(for game: Game) -> CGFloat {
        guard game.maxPlayers > 0 else { return 0 }
        return min(1, CGFloat(game.playerIds.count) / CGFloat(game.maxPlayers))
    }

    /// The empty state is a call to action, not an apology — with nothing on
    /// your calendar the useful next move is finding a court.
    private var noRunCard: some View {
        VStack(spacing: 4) {
            Image(systemName: "basketball")
                .hooprFont(30, maximumSize: 38)
                .foregroundStyle(Color.hooprSecondaryText)
                .padding(.bottom, 6)

            Text("No runs lined up")
                .hooprFont(16, weight: .bold)
                .foregroundStyle(Color.hooprPrimaryText)

            Text("Find a court and start one tonight.")
                .hooprFont(13)
                .foregroundStyle(Color.hooprSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)

            Button {
                onOpenMap(nil)
            } label: {
                Text("Find a court")
                    .hooprFont(15, weight: .semibold)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .foregroundStyle(Color.hooprOnBrand)
                    .background(Color.hooprOrange)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .cardChrome()
    }

    // MARK: - Hot right now

    @ViewBuilder
    private var hotCourtsCard: some View {
        if viewModel.hotCourts.isEmpty {
            Text("Nothing scheduled anywhere today. Be the first.")
                .hooprFont(13)
                .foregroundStyle(Color.hooprSecondaryText)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardChrome()
        } else {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.hotCourts.enumerated()), id: \.element.id) { index, hot in
                    if index > 0 {
                        Divider()
                            .overlay(Color.hooprBorder)
                            .padding(.leading, 38)
                    }

                    hotCourtRow(hot)
                }
            }
            .cardChrome()
        }
    }

    private func hotCourtRow(_ hot: HomeViewModel.HotCourt) -> some View {
        Button {
            onOpenMap(hot.court)
        } label: {
            HStack(spacing: 12) {
                // The same scale the map pins use, so a court's colour means
                // the same thing on both screens.
                Circle()
                    .fill(CourtHeat.color(forGameCount: hot.gameCount))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(hot.court.displayName)
                        .hooprFont(15, weight: .semibold)
                        .foregroundStyle(Color.hooprPrimaryText)
                        .lineLimit(1)

                    Text(hot.court.city)
                        .hooprFont(12, weight: .regular, maximumSize: 16)
                        .foregroundStyle(Color.hooprSecondaryText)
                }

                Spacer(minLength: 8)

                Text(gameCountText(hot.gameCount))
                    .hooprFont(13, weight: .semibold)
                    .foregroundStyle(Color.hooprSecondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap to see this court on the map")
    }

    /// Says "4+" at the ceiling rather than the true count, because the pin
    /// colour stops changing there — a row reading "7 today" beside a pin that
    /// looks identical to a 4 would promise a distinction the map can't show.
    private func gameCountText(_ count: Int) -> String {
        count >= CourtHeat.maxTier
            ? "\(CourtHeat.maxTier)+ today"
            : "\(count) today"
    }

    // MARK: - Friend requests

    private var friendRequestBanner: some View {
        Button(action: onOpenProfile) {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .hooprFont(17)
                    .foregroundStyle(Color.hooprOrange)
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 11)
                            .fill(Color.hooprOrange.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(requestText)
                        .hooprFont(14, weight: .semibold)
                        .foregroundStyle(Color.hooprPrimaryText)
                        .multilineTextAlignment(.leading)

                    Text("Tap to respond")
                        .hooprFont(12, maximumSize: 16)
                        .foregroundStyle(Color.hooprSecondaryText)
                }

                Spacer(minLength: 8)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardChrome(cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Double tap to open your inbox")
    }

    private var requestText: String {
        viewModel.incomingRequestCount == 1
            ? "1 friend request"
            : "\(viewModel.incomingRequestCount) friend requests"
    }
}

/// The card recipe the app already draws by hand in `GameCard`, `FriendRow`
/// and `ProfileRow` — surface, hairline, soft lift.
///
/// Extracted here because Home needs it in four places and a fourth
/// hand-rolled copy is where a design system starts drifting. The existing
/// three are left alone deliberately: folding them in is a refactor with its
/// own diff, not something to smuggle into a new screen.
private extension View {
    func cardChrome(cornerRadius: CGFloat = 16) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.hooprSurface)
                .shadow(color: Color.hooprShadow(opacity: 0.06), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.hooprBorder, lineWidth: 1)
        )
    }
}
