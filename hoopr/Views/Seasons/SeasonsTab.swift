import SwiftUI

/// The Seasons tab — squad home, or the empty state before there is a squad.
///
/// Two states over one scroll view. With no squad it's a hero empty state that
/// explains what a season *is* before asking for anything; with a squad it's
/// squad home — crest, record, roster, and the one card that matters right now.
///
/// **Redesigned in UI revamp Phase 2b**. The tab
/// opened on the word "Seasons" at 28pt — the tab bar's own label — over a
/// stack of three cards, and the squad's **record** — the one number in the
/// app nobody can type, a query over results two leaders independently
/// confirmed — was 13pt grey text inside the first of them. Now the tab opens
/// on a band like Home's and Runs': the squad's crest and name, and the record
/// set as the screen's numeral, with its last five results as dots beside it. The match card
/// follows directly, so **Queue up** sits under the band rather than two cards
/// down, and the roster is rows rather than a card.
///
/// **The band is neutral, not the squad's colour — measured, not chosen.** The
/// brief proposed the crest colour as the band's ground. No tint strong enough
/// to read as the squad's colour keeps the band at AA: at 14% the secondary
/// text falls to 4.26:1 on the gold crest in dark mode, and the baseline under
/// its 3:1 floor on red and gold even at 10%. So the colour lives in the crest
/// — large, full-strength, its glyph asserted at AA on every fill — which does
/// the same job: you know whose squad this is before you read the name.
///
/// **The matchmaking card carries searching and match found as states rather than
/// destinations** — the design always described this space as "next
/// match, searching, or find a match", so `MatchmakingCard` swaps its contents
/// in place instead of pushing anywhere.
struct SeasonsTab: View {
    @StateObject private var viewModel: SquadViewModel

    /// Holds `MatchmakingService` and `SeasonGameService` together and
    /// sequences claim → create → mark matched across them. See its own doc
    /// comment for why a write sequence lives in a view model.
    @StateObject private var matchmaking: MatchmakingViewModel

    /// Observed because `InboxButton` reads it for its badge.
    @ObservedObject private var friendService: FriendService

    /// Stored rather than only threaded into the two view models above:
    /// pushing game day builds a fresh `GameDayViewModel` on demand, and that
    /// join needs all four directly.
    private let squadService: SquadService
    private let seasonGameService: SeasonGameService
    private let userProfileService: UserProfileService
    private let courtService: CourtService
    private let notificationService: NotificationService

    private let onOpenInbox: () -> Void

    /// A match the inbox asked to open, handed down by the shell. Consumed —
    /// the stack is replaced with its screen — and written back `nil`, the
    /// same hand-off `MapTab` uses for `courtToSelect`, so the same match can
    /// be opened twice.
    @Binding private var matchToOpen: MatchDestination?

    /// The two screens the inbox can open, from outside this tab. Narrower
    /// than `Route`, which stays private: nothing outside needs to push squad
    /// detail.
    enum MatchDestination: Hashable {
        case gameDay(mySquadId: String, game: SeasonGame)
        case result(mySquadId: String, game: SeasonGame)

        fileprivate var route: Route {
            switch self {
            case .gameDay(let mySquadId, let game): .gameDay(mySquadId: mySquadId, game: game)
            case .result(let mySquadId, let game): .result(mySquadId: mySquadId, game: game)
            }
        }
    }

    /// Wrapped for `sheet(item:)` rather than presented with `isPresented` —
    /// the house convention, and the one that survives a rapid re-tap without
    /// going inert.
    private struct CreateRoute: Identifiable {
        let id = "create-squad"
    }

    /// The queue sheet, presented with `sheet(item:)` like every other sheet here.
    private struct QueueRoute: Identifiable {
        let id = "queue"
        let squad: Squad
    }

    /// Every push this stack makes. Game day and the result screen carry the match itself
    /// rather than just its ID — `SeasonGame` is already `Hashable`, and the
    /// object is already in hand at every call site that pushes it, so there's
    /// nothing to look back up.
    fileprivate enum Route: Hashable {
        case squad(String)
        case gameDay(mySquadId: String, game: SeasonGame)
        case result(mySquadId: String, game: SeasonGame)
    }

    @State private var creating: CreateRoute?
    @State private var queueing: QueueRoute?
    @State private var path: [Route] = []

    /// Squad detail and game day zoom out of what was tapped — the band's
    /// squad, a row, the match card — and back into it (UI revamp Phase 3).
    @Namespace private var zoom

    /// The zoom source ID for a squad, shared by the band, the rows and the
    /// push's destination.
    private static func zoomID(forSquad id: String) -> String { "squad-\(id)" }

    init(
        squadService: SquadService,
        matchmakingService: MatchmakingService,
        seasonGameService: SeasonGameService,
        friendService: FriendService,
        userProfileService: UserProfileService,
        courtService: CourtService,
        notificationService: NotificationService,
        matchToOpen: Binding<MatchDestination?>,
        onOpenInbox: @escaping () -> Void
    ) {
        _matchToOpen = matchToOpen
        self.friendService = friendService
        self.squadService = squadService
        self.seasonGameService = seasonGameService
        self.userProfileService = userProfileService
        self.courtService = courtService
        self.notificationService = notificationService
        self.onOpenInbox = onOpenInbox
        _viewModel = StateObject(wrappedValue: SquadViewModel(
            squadService: squadService,
            friendService: friendService,
            userProfileService: userProfileService,
            courtService: courtService
        ))
        _matchmaking = StateObject(wrappedValue: MatchmakingViewModel(
            matchmakingService: matchmakingService,
            seasonGameService: seasonGameService,
            courtService: courtService,
            squadService: squadService,
            notificationService: notificationService
        ))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    band

                    VStack(alignment: .leading, spacing: Spacing.section) {
                        if let errorMessage = viewModel.errorMessage {
                            ErrorBanner(
                                message: errorMessage,
                                // Only when a listener is down. An action that
                                // failed is retried by repeating the action.
                                onRetry: viewModel.isRecovering ? { viewModel.retry() } : nil,
                                onDismiss: { viewModel.dismissError() }
                            )
                        }

                        if viewModel.hasLoaded, let squad = viewModel.primarySquad {
                            squadHome(squad)
                        }
                    }
                    .padding(.horizontal, Spacing.pageMargin)
                    .padding(.top, Spacing.xxl)
                    .padding(.bottom, Spacing.xxxl)
                }
            }
            .hooprStatusBarScrim()
            .background(Color.hooprBackground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // The `seasonGames` listener used to be pointed from here, which
            // left it idle until this tab was first opened. It's `MainTabView`'s
            // now: the inbox lists matches, and a notification tap can open
            // the inbox before this tab has ever been shown.
            //
            // `initial: true` because a match can be the reason this tab is
            // mounted at all — the inbox selects it and sets the binding in
            // the same transaction.
            .onChange(of: matchToOpen, initial: true) { _, destination in
                guard let destination else { return }
                path = [destination.route]
                matchToOpen = nil
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .squad(let squadId):
                    SquadDetailView(
                        viewModel: viewModel,
                        squadId: squadId,
                        seasonGameService: seasonGameService,
                        onOpenResult: { game in
                            path.append(.result(mySquadId: squadId, game: game))
                        }
                    )
                    .hooprZoomDestination(sourceID: Self.zoomID(forSquad: squadId), in: zoom)
                case .gameDay(let mySquadId, let game):
                    GameDayView(
                        game: game,
                        mySquadId: mySquadId,
                        squadColorKey: viewModel.squad(id: mySquadId)?.colorKey,
                        seasonGameService: seasonGameService,
                        squadService: squadService,
                        userProfileService: userProfileService,
                        notificationService: notificationService,
                        courtService: courtService,
                        onOpenResult: { played in
                            path.append(.result(mySquadId: mySquadId, game: played))
                        }
                    )
                    .hooprZoomDestination(sourceID: MatchmakingCard.zoomID(for: game), in: zoom)
                case .result(let mySquadId, let game):
                    ResultView(
                        game: game,
                        mySquadId: mySquadId,
                        seasonGameService: seasonGameService,
                        squadService: squadService
                    )
                }
            }
            .sheet(item: $creating) { _ in
                CreateSquadSheet(
                    viewModel: viewModel,
                    onCreated: { _ in creating = nil },
                    onCancel: { creating = nil }
                )
            }
            .sheet(item: $queueing) { route in
                QueueSheet(
                    viewModel: matchmaking,
                    squad: route.squad,
                    onDismiss: { queueing = nil }
                )
            }
        }
    }

    // MARK: - The band

    /// The tab's hero — the same band as Home and
    /// Runs: full-bleed, `hooprHeroBand`, closed by a `hooprSeparatorStrong`
    /// baseline, the inbox button in its shared slot.
    private var band: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Text(bandLabel)
                    .hooprType(.label)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .padding(.top, Spacing.xs)

                Spacer(minLength: 0)

                InboxButton(friendService: friendService, squadService: squadService, action: onOpenInbox)
            }

            bandAnswer
        }
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.top, InboxButton.Slot.top)
        .padding(.bottom, Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The squad's own colour, at the band's luminance (UI revamp Phase 4)
        // — plain until the squad has loaded, and plain with no squad, where
        // there's no one's colour to show yet.
        .background {
            HeroWash(placement: bandWash)
                .ignoresSafeArea(edges: .top)
                .animation(.hooprSwap, value: bandWash)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.hooprSeparatorStrong)
                .frame(height: 1)
        }
    }

    private var bandWash: HeroWash.Placement {
        guard viewModel.hasLoaded, let squad = viewModel.primarySquad else { return .plain }
        return .leading(.hooprSquadWash(squad.colorKey))
    }

    private var bandLabel: String {
        viewModel.hasLoaded && viewModel.primarySquad != nil ? "This season" : "Seasons"
    }

    @ViewBuilder
    private var bandAnswer: some View {
        if !viewModel.hasLoaded {
            loadingAnswer
        } else if let squad = viewModel.primarySquad {
            squadAnswer(squad)
        } else {
            emptyAnswer
        }
    }

    // MARK: - Squad home

    /// Whose squad, and how they're doing. The name and crest open squad
    /// detail, as the header card did; the record under them is the hero.
    /// Both halves are shared with squad detail (`SquadBand.swift`), so the
    /// push opens on the band that was tapped.
    private func squadAnswer(_ squad: Squad) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Button {
                path.append(.squad(squad.id))
            } label: {
                SquadIdentity(squad: squad, showsDisclosure: true)
                    .contentShape(Rectangle())
                    .hooprZoomSource(id: Self.zoomID(forSquad: squad.id), in: zoom)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens squad details")

            SquadRecordLine(record: matchmaking.myRecord, form: matchmaking.myForm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Below the band: the one live thing, then who's on the squad.
    @ViewBuilder
    private func squadHome(_ squad: Squad) -> some View {
        MatchmakingCard(
            viewModel: matchmaking,
            squad: squad,
            zoomNamespace: zoom,
            onQueue: { queueing = QueueRoute(squad: squad) },
            onOpenGameDay: { game in
                path.append(.gameDay(mySquadId: squad.id, game: game))
            }
        )
        // Re-pointed whenever the primary squad changes, which is also the
        // first render — the view model no-ops on a repeat.
        .task(id: squad.id) { matchmaking.start(squad: squad) }

        rosterSection(squad)
    }

    /// Rows under a label, not a card: the roster is one list, and a box
    /// around it grouped nothing the label doesn't.
    private func rosterSection(_ squad: Squad) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("Roster")
                    .hooprType(.label)
                    .foregroundStyle(Color.hooprSecondaryText)

                Spacer()

                Text(squad.rosterText)
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)
            }

            VStack(spacing: 0) {
                ForEach(Array(viewModel.members(of: squad).enumerated()), id: \.element.id) { index, member in
                    if index > 0 {
                        Divider().overlay(Color.hooprBorder)
                    }
                    SquadMemberRow(member: member)
                        .padding(.vertical, Spacing.sm)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - No squad

    /// A hero, not an error. Someone with no squad hasn't failed at anything —
    /// they've arrived at a feature they haven't used, and the screen's job is
    /// to say what it's for in one sentence.
    ///
    /// The brief's model for the whole app (assumption A5), so it keeps its
    /// shape — crest, one line, one action — and moves into the band, left
    /// aligned like Home's empty state, with the same compact button.
    private var emptyAnswer: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SquadCrest(
                iconKey: Squad.defaultIconKey,
                colorKey: Squad.defaultColorKey,
                size: SquadCrest.Size.hero
            )
            .padding(.bottom, Spacing.xs)

            Text("Play a season")
                .hooprType(.title)
                .foregroundStyle(Color.hooprPrimaryText)

            Text("Form a squad, queue for 3v3 matches against other squads nearby, and build a record that actually means something.")
                .hooprType(.body)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                creating = CreateRoute()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill")
                    Text("Create a squad")
                }
            }
            .buttonStyle(.hooprFilled(.regular))
            .padding(.top, Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The squads listener hasn't answered. Shapes at the hero's proportions,
    /// so nothing moves when it does — and never the empty state's "Play a
    /// season", which would tell a squad leader they have no squad.
    private var loadingAnswer: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            Circle()
                .fill(Color.hooprHoverFill)
                .frame(width: SquadCrest.Size.hero, height: SquadCrest.Size.hero)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.hooprHoverFill)
                    .frame(width: 180, height: 28)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.hooprHoverFill)
                    .frame(width: 110, height: 14)
            }
        }
        .accessibilityLabel("Loading your squad")
    }
}

/// One person on a roster, or one person the leader could invite.
///
/// Shared by squad home and the detail screen so a member reads identically in
/// both — the role `FriendRow` plays on the friends list.
struct SquadMemberRow: View {
    let member: SquadViewModel.MemberRow

    /// A control on the trailing edge — "Invite", or the leader's badge.
    var trailing: AnyView?

    init(member: SquadViewModel.MemberRow, trailing: AnyView? = nil) {
        self.member = member
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            PlayerAvatar(initial: member.initial, diameter: PlayerAvatar.Size.roster)

            VStack(alignment: .leading, spacing: 2) {
                if member.isResolved {
                    Text(member.displayName)
                        .hooprFont(15, weight: .semibold)
                        .foregroundStyle(Color.hooprPrimaryText)
                } else {
                    // A skeleton rather than "Unknown player": the name is a
                    // decoration on a membership that's already real.
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.hooprFill)
                        .frame(width: 120, height: 14)
                }

                if member.isLeader {
                    Text("Leader")
                        .hooprFont(12)
                        .foregroundStyle(Color.hooprSecondaryText)
                }
            }

            Spacer(minLength: 8)

            if let trailing {
                trailing
            }
        }
    }
}
