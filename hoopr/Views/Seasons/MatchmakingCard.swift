import SwiftUI

/// Screens 5 and 6 — searching, and match found.
///
/// **States of squad home, not separate destinations.** Plan §5's screen 2
/// already describes this space as "the one card that matters right now — *next
/// match*, *searching*, or *find a match*", so all three live in one card that
/// swaps its contents rather than three screens a user has to navigate between.
///
/// **The swap is a transition, not a cut** (UI revamp Phase 3). The states used
/// to replace each other in a single frame — the most consequential change on
/// the tab, "we found you a match", drawn exactly like a re-render. Now the
/// outgoing state fades as the incoming one lifts in (`hooprLift`), the card's
/// edge fades in with a match, and the card's height follows on `hooprSwap`.
/// Keyed on the *kind* of state, so an update inside one — the opponent's
/// crest arriving, the search clock ticking — never re-runs it. A search turning
/// into a match also gives a success haptic (`feedback(from:to:)`).
struct MatchmakingCard: View {
    @ObservedObject private var viewModel: MatchmakingViewModel

    private let squad: Squad
    private let onQueue: () -> Void
    private let onOpenGameDay: (SeasonGame) -> Void
    /// Where the push into game day zooms out of (`hooprZoomSource`).
    private let zoomNamespace: Namespace.ID

    init(
        viewModel: MatchmakingViewModel,
        squad: Squad,
        zoomNamespace: Namespace.ID,
        onQueue: @escaping () -> Void,
        onOpenGameDay: @escaping (SeasonGame) -> Void
    ) {
        self.viewModel = viewModel
        self.squad = squad
        self.zoomNamespace = zoomNamespace
        self.onQueue = onQueue
        self.onOpenGameDay = onOpenGameDay
    }

    /// The zoom source ID for a match, shared with the push's destination.
    static func zoomID(for game: SeasonGame) -> String { "game-\(game.id)" }

    /// The card is always a zoom source — a modifier that came and went with
    /// the match would give the card a new identity at exactly the moment it
    /// should be animating — and only a match's ID is one a push asks for.
    private static func zoomSourceID(for phase: MatchmakingViewModel.Phase) -> String {
        if case .matched(let game) = phase { return zoomID(for: game) }
        return "matchmaking"
    }

    var body: some View {
        let phase = viewModel.phase
        let isMatched = Self.kind(of: phase) == .matched

        ZStack(alignment: .topLeading) {
            switch phase {
            case .idle:              idleState.transition(.hooprLift)
            case .searching:         searchingState.transition(.hooprLift)
            case .settling:          settlingState.transition(.hooprLift)
            case .matched(let game): matchState(game).transition(.hooprLift)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // **A card only when there's a match** (UI revamp Phase 2b). A match is
        // one tappable unit — the whole body opens game day — so it earns its
        // edges; "Find a match" and the search are a section of the page under
        // the band, and a box around them grouped nothing the heading doesn't.
        .padding(isMatched ? Spacing.cardPadding : 0)
        .cardChrome(isShown: isMatched)
        .hooprZoomSource(id: Self.zoomSourceID(for: phase), in: zoomNamespace)
        .animation(.hooprSwap, value: Self.kind(of: phase))
        .sensoryFeedback(trigger: phase) { old, new in
            Self.feedback(from: old, to: new)
        }
    }

    /// The four states without the match they carry — what the transition is
    /// keyed on.
    enum Kind: Hashable {
        case idle, searching, settling, matched
    }

    nonisolated static func kind(of phase: MatchmakingViewModel.Phase) -> Kind {
        switch phase {
        case .idle:      .idle
        case .searching: .searching
        case .settling:  .settling
        case .matched:   .matched
        }
    }

    /// **Match found is the one change here worth a haptic**, and only when
    /// it's news: a search (or the moment after one) turning into a match.
    /// Opening the tab onto a match that already exists goes `idle → matched`
    /// as the listeners arrive, and says nothing — a buzz on every visit would
    /// be the "programmatic rebuild" Phase 3 rules out.
    nonisolated static func feedback(
        from old: MatchmakingViewModel.Phase,
        to new: MatchmakingViewModel.Phase
    ) -> SensoryFeedback? {
        switch (kind(of: old), kind(of: new)) {
        case (.searching, .matched), (.settling, .matched): .success
        default: nil
        }
    }

    // MARK: - Find a match

    private var idleState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Find a match")
                .hooprType(.headline)
                .foregroundStyle(Color.hooprPrimaryText)

            Text("Queue your squad and we'll pair you with another one nearby.")
                .hooprType(.body)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.canQueue {
                Button(action: onQueue) {
                    Text("Queue up")
                        .hooprFont(16, weight: .semibold)
                        .foregroundStyle(Color.hooprOnBrand)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.hooprOrange))
                }
                .buttonStyle(.hooprPress)
                .padding(.top, 2)
            } else {
                // Not an error and not a disabled button with no explanation:
                // the roster can see the state, and knows whose move it is.
                Text("Your squad's leader queues you up.")
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
            }
        }
    }

    // MARK: - Between the commit and the card

    /// The match is made and hasn't arrived here yet.
    ///
    /// Normally a few hundred milliseconds: the match and both tickets are
    /// written in one transaction, but they reach this client on two separate
    /// listeners, and the ticket's usually wins. Without a state of its own the
    /// card would fall back to "Find a match" in that gap and then jump to the
    /// match — a flash of the wrong answer, and an offer to queue that would be
    /// refused if anyone were fast enough to take it.
    private var settlingState: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Color.hooprBrandAccent)

            Text("Match found")
                .hooprType(.headline)
                .foregroundStyle(Color.hooprPrimaryText)

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Match found. Loading the details.")
    }

    // MARK: - Screen 5: searching

    private var searchingState: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView().tint(Color.hooprBrandAccent)

                Text(viewModel.isWidening ? "Widening the search" : "Looking for a match")
                    .hooprType(.headline)
                    .foregroundStyle(Color.hooprPrimaryText)

                Spacer(minLength: 0)

                Text(elapsedText)
                    .hooprFont(14)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .monospacedDigit()
            }

            // The copy is true *because* relaxation is actually widening the
            // criteria — `MatchRules.relaxation(for:now:)` is what this reads,
            // not a timer that happens to agree with it. A search that silently
            // lowered its standards would produce a mismatch nobody could
            // explain.
            Text(statusLine)
                .hooprFont(14)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if viewModel.isLeader {
                Button {
                    Task { await viewModel.leaveQueue() }
                } label: {
                    Text("Cancel search")
                        .hooprFont(15, weight: .semibold)
                        .foregroundStyle(Color.hooprSecondaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var elapsedText: String {
        let total = Int(viewModel.elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var statusLine: String {
        if viewModel.isStillLooking {
            // Contention, not an error. Losing races is what a healthy pool
            // looks like from the inside, so this stays a quiet line rather
            // than a banner.
            return "Busy out there — still looking."
        }

        switch viewModel.poolCount {
        case 0:
            return viewModel.isWidening
                ? "No other squads queued yet. We're widening how far and how evenly matched we'll go."
                : "No other squads queued yet. We'll keep watching."
        case 1:
            return "1 other squad queued nearby."
        default:
            return "\(viewModel.poolCount) other squads queued nearby."
        }
    }

    // MARK: - Screen 6: match found

    @ViewBuilder
    private func matchState(_ game: SeasonGame) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // The whole card body opens game day — screen 7 — except the
            // cancel control below, which stays its own un-nested button so
            // cancelling never also navigates.
            Button {
                onOpenGameDay(game)
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Next match")
                            .hooprFont(13, weight: .semibold)
                            .foregroundStyle(Color.hooprSecondaryText)
                            .textCase(.uppercase)

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .hooprFont(12, weight: .semibold)
                            .foregroundStyle(Color.hooprSecondaryText)
                    }

                    HStack(spacing: 12) {
                        SquadCrest(squad: squad, size: SquadCrest.Size.card)

                        Text("vs")
                            .hooprFont(14, weight: .semibold)
                            .foregroundStyle(Color.hooprSecondaryText)

                        // The opponent's crest keys aren't on the game
                        // document — names are denormalized so history survives
                        // a disbanded squad, the icon and colour are not — so
                        // the view model fetches the squad. Until it lands, a
                        // redacted placeholder rather than a wrong crest: this
                        // rendered a hardcoded shield in blue for every
                        // opponent until Phase 7, which is a crest that lies
                        // rather than one that hasn't arrived.
                        if let opponent = viewModel.opponentSquad {
                            SquadCrest(squad: opponent, size: SquadCrest.Size.card)
                        } else {
                            SquadCrest(
                                iconKey: Squad.defaultIconKey,
                                colorKey: Squad.defaultColorKey,
                                size: SquadCrest.Size.card
                            )
                            .redacted(reason: .placeholder)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(opponentName(in: game))
                                .hooprFont(17, weight: .semibold)
                                .foregroundStyle(Color.hooprPrimaryText)
                                .multilineTextAlignment(.leading)

                            Text(opponentRecordText)
                                .hooprFont(13)
                                .foregroundStyle(Color.hooprSecondaryText)
                        }

                        Spacer(minLength: 0)
                    }
                    // Both crests are decorative and hidden, so without this
                    // the row announces only the opponent — the matchup is
                    // carried entirely by two glyphs a screen reader can't see,
                    // and "who is playing whom" never gets said.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "\(squad.name) versus \(opponentName(in: game)). \(opponentRecordText)"
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        detailRow(
                            icon: "mappin.and.ellipse",
                            text: viewModel.courtName(id: game.courtId)
                        )
                        detailRow(
                            icon: "clock",
                            text: game.scheduledTime.formatted(
                                .dateTime.weekday(.wide).hour().minute()
                            )
                        )
                        if game.isHome(squad.id) {
                            detailRow(icon: "house", text: "Your court")
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.hooprPress)

            if !viewModel.duplicateGames.isEmpty {
                // The window between a game landing and both tickets being
                // marked matched can produce a second match. Rules can't query,
                // so this isn't prevented server-side — the earliest-created one
                // is rendered and a leader cancels the other.
                Text("You have more than one match scheduled. Cancel the one you don't want.")
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprRed)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if viewModel.isLeader {
                Button {
                    Task { await viewModel.cancel(game: game) }
                } label: {
                    Text("Cancel match")
                        .hooprFont(15, weight: .semibold)
                        .foregroundStyle(Color.hooprRed)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func opponentName(in game: SeasonGame) -> String {
        game.opponentName(of: squad.id) ?? "Opponent"
    }

    private var opponentRecordText: String {
        guard let record = viewModel.opponentRecord else { return "Record loading…" }
        return record.isUnplayed ? "No games played yet" : "\(record.displayText) this season"
    }

    private func detailRow(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .hooprFont(13)
                .foregroundStyle(Color.hooprSecondaryText)
                .frame(width: 18)

            Text(text)
                .hooprFont(14)
                .foregroundStyle(Color.hooprPrimaryText)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
    }
}
