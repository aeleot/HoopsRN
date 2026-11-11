import SwiftUI

/// Everything that's happened to you and everything waiting on you, as one
/// feed of cards.
///
/// Opened from `InboxButton`, the tray in the top-right corner of every tab,
/// badged with everything waiting on you — and by tapping any notification
/// the app posts (`NotificationService`). Presented once, by `MainTabView`,
/// over whichever tab is showing.
///
/// **Four kinds of card** (`InboxCard`), in this order:
/// - **Matches** (2026-09-25) — the season matches the queue made, or that
///   are waiting on your report. Every tapped notification opens this sheet,
///   and the only notifications the app sends are about a match, so these
///   come first and each opens the screen that answers it
///   (`InboxMatchesViewModel`).
/// - **Friend requests**, answered inline.
/// - **Squad invites**, answered inline. They used to render on Squad home,
///   where there was nowhere to answer one.
/// - **New friends** (2026-09-28) — someone accepted a request you sent. The
///   only card that asks nothing, so the only one you can dismiss.
///
/// **No section headers, and no Sent list** (2026-09-28, at the user's
/// request). It used to be four titled sections, two of them shown even when
/// empty, which made a single request read as a form. Requests you've sent
/// aren't news — they're waiting on someone else — and can still be cancelled
/// from that player's profile. Still no `InboxItem` enum: the four kinds share
/// a card, not a model, and each keeps its own view model.
struct InboxSheet: View {
    /// Built per presentation, like `CreateGameSheet`'s — the inbox used to
    /// borrow the profile's, back when it could only be opened from inside the
    /// profile. Both mirror the services, so a fresh pair opens on the same
    /// requests and invites any other screen is showing.
    @StateObject private var viewModel: FriendsViewModel
    @StateObject private var squadViewModel: SquadViewModel
    @StateObject private var matchesViewModel: InboxMatchesViewModel

    private let onOpenMatch: (InboxMatchesViewModel.Row) -> Void
    private let onDismiss: () -> Void

    init(
        friendService: FriendService,
        squadService: SquadService,
        userProfileService: UserProfileService,
        courtService: CourtService,
        seasonGameService: SeasonGameService,
        onOpenMatch: @escaping (InboxMatchesViewModel.Row) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onOpenMatch = onOpenMatch
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: FriendsViewModel(
            friendService: friendService,
            userProfileService: userProfileService,
            courtService: courtService
        ))
        _squadViewModel = StateObject(wrappedValue: SquadViewModel(
            squadService: squadService,
            friendService: friendService,
            userProfileService: userProfileService,
            courtService: courtService
        ))
        _matchesViewModel = StateObject(wrappedValue: InboxMatchesViewModel(
            seasonGameService: seasonGameService,
            squadService: squadService,
            courtService: courtService
        ))
    }

    /// This sheet's own profile route — see `PlayerRoute`.
    @State private var presentedPlayer: PlayerRoute?

    private var isEmpty: Bool {
        matchesViewModel.rows.isEmpty
            && viewModel.incomingRequests.isEmpty
            && squadViewModel.incomingInvites.isEmpty
            && viewModel.recentlyAccepted.isEmpty
    }

    /// Every card's identity, in order — what the feed animates on, so an
    /// answered request slides out rather than blinking away.
    private var cardIds: [String] {
        matchesViewModel.rows.map { "match:\($0.id)" }
            + viewModel.incomingRequests.map { "request:\($0.id)" }
            + squadViewModel.incomingInvites.map { "invite:\($0.id)" }
            + viewModel.recentlyAccepted.map { "accepted:\($0.id)" }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        // One feed, no headers: each card names its own kind.
                        // Matches first — a notification tap lands here, and
                        // the match it was about is what that person came for
                        // (answers before upcoming, `InboxMatchesViewModel`).
                        // Then what's asking for a yes or no, then news.
                        LazyVStack(spacing: Spacing.interRow) {
                            ForEach(matchesViewModel.rows) { row in
                                matchCard(row)
                            }
                            ForEach(viewModel.incomingRequests) { row in
                                requestCard(row)
                            }
                            ForEach(squadViewModel.incomingInvites) { row in
                                squadInviteCard(row)
                            }
                            ForEach(viewModel.recentlyAccepted) { row in
                                acceptedCard(row)
                            }
                        }
                        .padding(.horizontal, Spacing.pageMargin)
                        .padding(.top, Spacing.lg)
                        .padding(.bottom, Spacing.xxl)
                        .animation(.hooprSnap, value: cardIds)
                    }
                }
            }
            .background(Color.hooprBackground)
            .navigationTitle("Inbox")
            #if os(iOS) || os(visionOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.hooprBrandAccent)
                }
            }
        }
        .sheet(item: $presentedPlayer) { route in
            PlayerProfileSheet(uid: route.uid, viewModel: viewModel) {
                presentedPlayer = nil
            }
        }
    }

    // MARK: - Cards

    /// A season match — made by the queue, or waiting on your report. The
    /// whole card opens it: game day to come, the result screen after.
    private func matchCard(_ row: InboxMatchesViewModel.Row) -> some View {
        let style = MatchStyle(row.kind)
        return InboxCard(
            eyebrow: style.eyebrow,
            symbol: style.symbol,
            tint: style.tint,
            title: "\(row.game.format.displayName) vs \(row.opponentName)",
            detail: matchesViewModel.detail(for: row),
            detailTint: row.kind == .upcoming ? .hooprSecondaryText : .hooprBrandAccent,
            onOpen: { onOpenMatch(row) },
            openHint: row.kind == .upcoming ? "Opens game day" : "Opens the result"
        ) {
            InboxGlyph(symbol: "basketball.fill", tint: style.tint)
        } actions: {
            EmptyView()
        }
    }

    private func requestCard(_ row: FriendsViewModel.Row) -> some View {
        InboxCard(
            eyebrow: "Friend request",
            symbol: "person.badge.plus",
            title: row.isResolved ? row.displayName : "Someone",
            detail: "Wants to add you as a friend",
            onOpen: { presentedPlayer = PlayerRoute(uid: row.uid) },
            openHint: "Opens their profile"
        ) {
            PlayerAvatar(initial: row.initial, diameter: PlayerAvatar.Size.row)
        } actions: {
            // Every action the relationship offers, inline — this is the
            // screen whose whole job is answering.
            ForEach(viewModel.actions(for: row.relationship), id: \.self) { action in
                friendActionButton(action, for: row)
            }
        }
    }

    private func squadInviteCard(_ row: SquadViewModel.IncomingInvite) -> some View {
        let joinBlockedReason = squadViewModel.joinBlockedReason(for: row.invite)
        return InboxCard(
            eyebrow: "Squad invite",
            symbol: "shield.lefthalf.filled",
            title: row.squadName,
            // The reason replaces the roster line: with no Join to weigh, how
            // full the squad is stops being the thing worth reading.
            detail: joinBlockedReason
                ?? row.squad.map { "\($0.format.displayName) · \($0.rosterText)" }
                ?? "Invited you to join"
        ) {
            if let squad = row.squad {
                SquadCrest(squad: squad, size: InboxCard<EmptyView, EmptyView>.leadingColumn)
            } else {
                SquadCrest(
                    iconKey: Squad.defaultIconKey,
                    colorKey: Squad.defaultColorKey,
                    size: InboxCard<EmptyView, EmptyView>.leadingColumn
                )
                .redacted(reason: .placeholder)
            }
        } actions: {
            // Join is *absent* rather than dimmed when it's blocked, so the
            // reason above isn't left to be guessed; Decline stays, so the
            // invite can still be cleared.
            Group {
                if joinBlockedReason == nil {
                    Button("Join") { Task { await squadViewModel.acceptInvite(row.invite) } }
                        .buttonStyle(.hooprFilled(.compact))
                }
                Button("Decline") { Task { await squadViewModel.declineInvite(row.invite) } }
                    .buttonStyle(.hooprFilled(.compact, role: .destructive))
            }
            .disabled(squadViewModel.isBlocked(row.id))
        }
    }

    /// Someone said yes to a request you sent. Asks nothing, so it's the one
    /// card with an ×; it also ages out on its own
    /// (`FriendsViewModel.acceptanceWindow`).
    private func acceptedCard(_ row: FriendsViewModel.Row) -> some View {
        InboxCard(
            eyebrow: "New friend",
            symbol: "person.2.fill",
            title: row.isResolved ? row.displayName : "Someone",
            detail: "Accepted your friend request",
            onOpen: { presentedPlayer = PlayerRoute(uid: row.uid) },
            openHint: "Opens their profile",
            onDismiss: { viewModel.dismissAcceptance(from: row.uid) }
        ) {
            PlayerAvatar(initial: row.initial, diameter: PlayerAvatar.Size.row)
        } actions: {
            EmptyView()
        }
    }

    /// The app's compact button, carrying `FriendActionButton`'s pending and
    /// blocked states: the acting card spins, every other card's controls dim.
    private func friendActionButton(
        _ action: FriendsViewModel.Action,
        for row: FriendsViewModel.Row
    ) -> some View {
        let isPending = viewModel.pendingUid == row.uid
        let isBlocked = viewModel.isBlocked(row.uid)
        return Button {
            Task { await viewModel.perform(action, on: row.uid) }
        } label: {
            if isPending {
                ProgressView()
            } else {
                Text(action.title)
            }
        }
        .buttonStyle(.hooprFilled(.compact, role: action.isDestructive ? .destructive : .primary))
        .disabled(isPending || isBlocked)
        .opacity(isBlocked && !isPending ? 0.5 : 1)
        .accessibilityLabel("\(action.longTitle), \(row.nameForProse)")
    }

    /// How each kind of match card announces itself.
    private struct MatchStyle {
        let eyebrow: String
        let symbol: String
        let tint: Color

        init(_ kind: InboxMatchesViewModel.Row.Kind) {
            switch kind {
            case .upcoming:
                eyebrow = "Upcoming match"
                symbol = "calendar"
                tint = .hooprBrandAccent
            case .report:
                eyebrow = "Report result"
                symbol = "square.and.pencil"
                tint = .hooprBrandAccent
            case .disputed:
                eyebrow = "Result disputed"
                symbol = "exclamationmark.triangle.fill"
                tint = .hooprRed
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .hooprFont(38, maximumSize: 48)
                .foregroundStyle(Color.hooprSecondaryText)

            Text(viewModel.inboxEmptyText)
                .hooprType(.body)
                .foregroundStyle(Color.hooprSecondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
