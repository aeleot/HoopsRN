import SwiftUI

/// The Seasons tab — plan §5, screens 1 and 2.
///
/// Two states over one scroll view. With no squad it's a hero empty state that
/// explains what a season *is* before asking for anything; with a squad it's
/// squad home — crest, record, roster, and the one card that matters right now.
///
/// **The matchmaking card carries screens 5 and 6 as states rather than
/// destinations** — plan §5's screen 2 already describes this space as "next
/// match, searching, or find a match", so `MatchmakingCard` swaps its contents
/// in place instead of pushing anywhere.
struct SeasonsTab: View {
    @StateObject private var viewModel: SquadViewModel

    /// Holds `MatchmakingService` and `SeasonGameService` together and
    /// sequences claim → create → mark matched across them. See its own doc
    /// comment for why a write sequence lives in a view model.
    @StateObject private var matchmaking: MatchmakingViewModel

    /// Observed because `ProfileButton` reads it for its badge dot.
    @ObservedObject private var friendService: FriendService

    /// Stored rather than only threaded into the two view models above:
    /// pushing screen 7 builds a fresh `GameDayViewModel` on demand, and that
    /// join needs all four directly.
    private let squadService: SquadService
    private let seasonGameService: SeasonGameService
    private let userProfileService: UserProfileService
    private let courtService: CourtService
    private let notificationService: NotificationService

    private let onOpenProfile: () -> Void

    /// Wrapped for `sheet(item:)` rather than presented with `isPresented` —
    /// the house convention, and the one that survives a rapid re-tap without
    /// going inert.
    private struct CreateRoute: Identifiable {
        let id = "create-squad"
    }

    /// Screen 4, presented with `sheet(item:)` like every other sheet here.
    private struct QueueRoute: Identifiable {
        let id = "queue"
        let squad: Squad
    }

    /// Every push this stack makes. Screens 7 and 8 carry the match itself
    /// rather than just its ID — `SeasonGame` is already `Hashable`, and the
    /// object is already in hand at every call site that pushes it, so there's
    /// nothing to look back up.
    private enum Route: Hashable {
        case squad(String)
        case gameDay(mySquadId: String, game: SeasonGame)
        case result(mySquadId: String, game: SeasonGame)
    }

    @State private var creating: CreateRoute?
    @State private var queueing: QueueRoute?
    @State private var path: [Route] = []

    init(
        squadService: SquadService,
        matchmakingService: MatchmakingService,
        seasonGameService: SeasonGameService,
        friendService: FriendService,
        userProfileService: UserProfileService,
        courtService: CourtService,
        notificationService: NotificationService,
        onOpenProfile: @escaping () -> Void
    ) {
        self.friendService = friendService
        self.squadService = squadService
        self.seasonGameService = seasonGameService
        self.userProfileService = userProfileService
        self.courtService = courtService
        self.notificationService = notificationService
        self.onOpenProfile = onOpenProfile
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
                VStack(alignment: .leading, spacing: Spacing.interCard) {
                    header

                    if let errorMessage = viewModel.errorMessage {
                        ErrorBanner(
                            message: errorMessage,
                            // Only when a listener is down. An action that
                            // failed is retried by repeating the action.
                            onRetry: viewModel.isRecovering ? { viewModel.retry() } : nil,
                            onDismiss: { viewModel.dismissError() }
                        )
                    }

                    if !viewModel.hasLoaded {
                        loading
                    } else if let squad = viewModel.primarySquad {
                        squadHome(squad)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, Spacing.pageMargin)
                .padding(.bottom, 32)
            }
            .background(Color.hooprBackground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Every squad the user is on, not just the primary one: screen 9's
            // history reads off this listener, and a secondary squad's detail
            // view would otherwise render an empty season rather than its own.
            // `array-contains-any` serves up to ten squads from one query.
            .task(id: viewModel.squads.map(\.id)) {
                seasonGameService.observe(squadIds: viewModel.squads.map(\.id))
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
                case .gameDay(let mySquadId, let game):
                    GameDayView(
                        game: game,
                        mySquadId: mySquadId,
                        seasonGameService: seasonGameService,
                        squadService: squadService,
                        userProfileService: userProfileService,
                        notificationService: notificationService,
                        courtService: courtService,
                        onOpenResult: { played in
                            path.append(.result(mySquadId: mySquadId, game: played))
                        }
                    )
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

    /// The squad's record, read from the derived query rather than a stored
    /// counter. Reads as "No games played yet" until Phase 6 confirms
    /// something, and starts moving on its own the day it does.
    private var recordText: String {
        let record = matchmaking.myRecord
        return record.isUnplayed ? "No games played yet" : "\(record.displayText) this season"
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("Seasons")
                .hooprFont(28, weight: .bold, maximumSize: 40)
                .foregroundStyle(Color.hooprPrimaryText)

            Spacer(minLength: 8)

            ProfileButton(friendService: friendService, squadService: squadService, action: onOpenProfile)
                .offset(x: 8)
        }
        .padding(.top, 8)
    }

    private var loading: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.top, 40)
    }

    // MARK: - Screen 1: no squad

    /// A hero, not an error. Someone with no squad hasn't failed at anything —
    /// they've arrived at a feature they haven't used, and the screen's job is
    /// to say what it's for in one sentence.
    private var emptyState: some View {
        VStack(spacing: 14) {
            SquadCrest(
                iconKey: Squad.defaultIconKey,
                colorKey: Squad.defaultColorKey,
                size: SquadCrest.Size.hero
            )
            .padding(.top, 24)

            Text("Play a season")
                .hooprFont(22, weight: .bold)
                .foregroundStyle(Color.hooprPrimaryText)

            Text("Form a squad, queue for 3v3 matches against other squads nearby, and build a record that actually means something.")
                .hooprFont(15)
                .foregroundStyle(Color.hooprSecondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            Button {
                creating = CreateRoute()
            } label: {
                Text("Create a squad")
                    .hooprFont(16, weight: .semibold)
                    .foregroundStyle(Color.hooprOnBrand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12).fill(Color.hooprOrange)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 12)
    }

    // MARK: - Screen 2: squad home

    @ViewBuilder
    private func squadHome(_ squad: Squad) -> some View {
        VStack(alignment: .leading, spacing: Spacing.interCard) {
            Button {
                path.append(.squad(squad.id))
            } label: {
                squadHeader(squad)
            }
            .buttonStyle(.plain)

            MatchmakingCard(
                viewModel: matchmaking,
                squad: squad,
                onQueue: { queueing = QueueRoute(squad: squad) },
                onOpenGameDay: { game in
                    path.append(.gameDay(mySquadId: squad.id, game: game))
                }
            )
            // Re-pointed whenever the primary squad changes, which is also the
            // first render — the view model no-ops on a repeat.
            .task(id: squad.id) { matchmaking.start(squad: squad) }

            rosterCard(squad)

            // More than one squad is legal — the schema doesn't stop it — so
            // the others get rows rather than being silently dropped by
            // `primarySquad`.
            if viewModel.squads.count > 1 {
                otherSquads(besides: squad)
            }

            Button {
                creating = CreateRoute()
            } label: {
                Text("Create another squad")
                    .hooprFont(15, weight: .semibold)
                    .foregroundStyle(Color.hooprSecondaryText)
            }
            .buttonStyle(.plain)
        }
    }

    private func squadHeader(_ squad: Squad) -> some View {
        HStack(spacing: 14) {
            SquadCrest(squad: squad, size: SquadCrest.Size.hero)

            VStack(alignment: .leading, spacing: 4) {
                Text(squad.name)
                    .hooprFont(22, weight: .bold)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .multilineTextAlignment(.leading)

                Text("\(squad.format.displayName) · \(squad.region)")
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)

                // The record is a *query* over confirmed games, not a stored
                // counter (plan §1.1), so it moves the moment two leaders
                // agree on a result with nothing to invalidate.
                SquadRecordLine(recordText: recordText, form: matchmaking.myForm)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .hooprFont(14, weight: .semibold)
                .foregroundStyle(Color.hooprSecondaryText)
        }
        .padding(Spacing.cardPadding)
        .cardChrome()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens squad details")
    }

    private func rosterCard(_ squad: Squad) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Roster")
                    .hooprFont(13, weight: .semibold)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .textCase(.uppercase)

                Spacer()

                Text(squad.rosterText)
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
            }

            ForEach(viewModel.members(of: squad)) { member in
                SquadMemberRow(member: member)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .cardChrome()
    }

    @ViewBuilder
    private func otherSquads(besides primary: Squad) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your other squads")
                .hooprFont(13, weight: .semibold)
                .foregroundStyle(Color.hooprSecondaryText)
                .textCase(.uppercase)

            ForEach(viewModel.squads.filter { $0.id != primary.id }) { squad in
                Button {
                    path.append(.squad(squad.id))
                } label: {
                    HStack(spacing: 12) {
                        SquadCrest(squad: squad, size: SquadCrest.Size.row)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(squad.name)
                                .hooprFont(15, weight: .semibold)
                                .foregroundStyle(Color.hooprPrimaryText)
                            Text(squad.rosterText)
                                .hooprFont(13)
                                .foregroundStyle(Color.hooprSecondaryText)
                        }

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .hooprFont(13, weight: .semibold)
                            .foregroundStyle(Color.hooprSecondaryText)
                    }
                    .padding(12)
                    .cardChrome(cornerRadius: 12)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// The squad's record with its recent form beside it — "1–0 this season (W)".
///
/// **Beside when it fits, beneath when it doesn't.** The pills are fixed-diameter
/// circles (`ResultPillMetrics`, and the cap is load-bearing), so five of them
/// are 164pt wide before the record's own text is counted, and the column this
/// sits in is about 230pt at the default text size. One to three results fit
/// beside the record; four or five, and every result at the accessibility sizes,
/// take the column instead — the same `ViewThatFits` rule the queue sheet's time
/// chips follow and for the same reason: a row that stops fitting takes a column
/// rather than being squeezed or clipped.
///
/// Stateless, and internal rather than private, so the width at which it flips
/// can be rendered and looked at without standing up a `SeasonsTab`.
struct SquadRecordLine: View {
    let recordText: String
    let form: [SeasonGame.Outcome]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.sm) {
                record
                FormGuide(form: form)
            }

            VStack(alignment: .leading, spacing: Spacing.hairline) {
                record
                FormGuide(form: form)
            }
        }
    }

    private var record: some View {
        Text(recordText)
            .hooprFont(13)
            .foregroundStyle(Color.hooprSecondaryText)
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
            PlayerAvatar(initial: member.initial, diameter: 34)

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
