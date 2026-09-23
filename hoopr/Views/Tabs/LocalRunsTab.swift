import SwiftUI

/// The Runs tab: everything on the schedule, soonest first.
///
/// **Redesigned in UI revamp Phase 2b** (`UI_REDESIGN_BRIEF.md` §5.2). It used
/// to be two collapsible sections — *Queued Games* and *Public Games* — over
/// one scroll view, on the reasoning that they are read together ("am I busy,
/// and what else is on?"). That reasoning holds; the shape it produced did
/// not. Two headers, two count capsules, two chevrons and a full-bleed rule
/// spent the entire first viewport on furniture, and the first `Join` sat
/// around 240pt down the page.
///
/// So the split is gone and the reading it served survives: **one list ordered
/// by tip-off**, with the runs you're on marked by a rail down the card's
/// leading edge, under a band that states how many games are on the schedule
/// and where you stand on it. Rank replaced disclosure.
///
/// **This overturns a `UI_SHELL.md` invariant** — "a list screen is built from
/// the `LocalRunsTab` parts: collapsible section header, one shared card, one
/// write in flight". The shared card and the single write are untouched; the
/// collapsible header is not. Confirmed with the user at Checkpoint 1 before
/// any of this was written. The cost is real and recorded: you can no longer
/// fold the public half away, and the hero's counts plus the rail are what
/// replace it.
struct LocalRunsTab: View {
    @StateObject private var viewModel: LocalRunsViewModel

    /// Observed because `ProfileButton` reads it for its badge dot.
    @ObservedObject private var friendService: FriendService

    /// Same reason as `friendService` — `ProfileButton`'s badge also carries
    /// squad invites now.
    @ObservedObject private var squadService: SquadService

    private let onOpenProfile: () -> Void

    /// The empty board's one action. Handed up like Home's — switching tabs is
    /// the shell's job.
    private let onOpenMap: () -> Void

    init(
        gameService: GameService,
        courtService: CourtService,
        userProfileService: UserProfileService,
        friendService: FriendService,
        squadService: SquadService,
        onOpenProfile: @escaping () -> Void,
        onOpenMap: @escaping () -> Void
    ) {
        self.friendService = friendService
        self.squadService = squadService
        self.onOpenProfile = onOpenProfile
        self.onOpenMap = onOpenMap
        _viewModel = StateObject(wrappedValue: LocalRunsViewModel(
            gameService: gameService,
            courtService: courtService,
            userProfileService: userProfileService,
            friendService: friendService
        ))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                heroBand

                if let errorMessage = viewModel.errorMessage {
                    ErrorBanner(
                        message: errorMessage,
                        // Only when a listener is down. An action that failed —
                        // a join that lost a race — has nothing here to retry;
                        // the user taps the card's button again.
                        onRetry: viewModel.isRecovering ? { viewModel.retry() } : nil,
                        onDismiss: { viewModel.dismissError() }
                    )
                    .padding(.horizontal, Spacing.pageMargin)
                    .padding(.top, Spacing.md)
                }

                board
            }
            .padding(.bottom, 32)
        }
        .background(Color.hooprBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // On the screen, not the list: cancelling the last run empties the
        // board in the same update that confirms the cancel.
        .sensoryFeedback(trigger: viewModel.lastConfirmation) { _, new in
            new?.kind.feedback
        }
    }

    // MARK: - The band

    /// The board's summary, and the screen's hero.
    ///
    /// The tab used to open on the word "Runs" at 28pt — the tab bar's own
    /// label, restated as the largest thing on the screen. It states a number
    /// instead: how many games are on the schedule, which is the question the
    /// tab exists to answer and the only one that can't be answered by
    /// scrolling.
    ///
    /// Written for a player, quietly: the board is *the schedule*, and the
    /// line under it says where you stand on it — suited up, waitlisted, or a
    /// free agent — rather than a count of rows.
    private var heroBand: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                Text(viewModel.eyebrowText)
                    .hooprType(.label)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .padding(.top, Spacing.xs)

                Spacer(minLength: 0)

                ProfileButton(friendService: friendService, squadService: squadService, action: onOpenProfile)
            }

            bandAnswer
        }
        .padding(.horizontal, Spacing.pageMargin)
        // The profile button's slot — the same point on every tab.
        .padding(.top, ProfileButton.Slot.top)
        .padding(.bottom, Spacing.xxl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Color.hooprHeroBand.ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.hooprSeparatorStrong)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var bandAnswer: some View {
        if !viewModel.hasLoaded {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                placeholder(width: 150, height: 46)
                placeholder(width: 210, height: 18)
            }
            .accessibilityLabel("Loading the schedule")
        } else {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                let count = viewModel.timelineCount
                let schedule = LocalRunsViewModel.scheduleText(count: count)

                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    Text("\(count)")
                        .hooprType(.numeral)
                        .foregroundStyle(Color.hooprPrimaryText)
                        .hooprNumericTransition(count)

                    Text(schedule)
                        .hooprType(.headline)
                        .foregroundStyle(Color.hooprSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(count) \(schedule)")

                rosterLine
            }
        }
    }

    /// Where you stand, marked with the rail your runs carry below.
    ///
    /// The rail is the same mark as `GameCard`'s, in the same accent and
    /// width, so the band is what teaches it: the line that says "you're
    /// suited up" is drawn the way the runs you're suited up for are. A free
    /// agent has no runs to point at, so no rail — and the line drops to
    /// secondary, because it's a state rather than news.
    ///
    /// It replaced "you're in 2 · within 14 miles" in 13pt grey, which read as
    /// a footnote and put the radius — a fact about the board — on the line
    /// about you. The radius left the band; see `eyebrowText`.
    private var rosterLine: some View {
        HStack(spacing: Spacing.sm) {
            if viewModel.hasRosterSpot {
                Capsule()
                    .fill(Color.hooprBrandAccent)
                    .frame(width: 3)
            }

            Text(viewModel.rosterText)
                .hooprType(.body)
                .fontWeight(viewModel.hasRosterSpot ? .semibold : .regular)
                .foregroundStyle(viewModel.hasRosterSpot ? Color.hooprPrimaryText : Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Lets the rail take the text's height, however many lines it wraps to.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private func placeholder(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.hooprHoverFill)
            .frame(width: width, height: height)
    }

    // MARK: - The board

    /// One list, ordered by tip-off. No sections, no disclosure.
    @ViewBuilder
    private var board: some View {
        if !viewModel.hasLoaded {
            // Distinct from "nothing on": the listener hasn't answered.
            Text("Checking the schedule…")
                .hooprType(.body)
                .foregroundStyle(Color.hooprSecondaryText)
                .padding(.horizontal, Spacing.pageMargin)
                .padding(.top, Spacing.xxl)
        } else if viewModel.timeline.isEmpty {
            emptyBoard
        } else {
            VStack(spacing: Spacing.interRow) {
                ForEach(viewModel.timeline) { entry in
                    // Resolved once, so the button that's rendered and the
                    // one that fires can't disagree — a confirmation
                    // dialog reading "Cancel run" must not perform a join.
                    let action = viewModel.action(for: entry.listing)

                    GameCard(
                        listing: entry.listing,
                        action: action,
                        isHost: viewModel.isHost(entry.listing),
                        isWaitlisted: viewModel.isWaitlisted(entry.listing),
                        isYours: entry.isYours,
                        isPending: viewModel.pendingGameId == entry.id,
                        // One write at a time, so a second tap can't race
                        // the transaction already in flight.
                        isDisabled: viewModel.pendingGameId != nil
                            && viewModel.pendingGameId != entry.id,
                        // Resolved at render, so the control appears on the
                        // next rebuild after tip-off rather than on a timer
                        // — the same cadence `Game.isVisible(at:)` retires a
                        // run on, and the rule is the real gate anyway.
                        canComplete: viewModel.canComplete(entry.listing),
                        onAction: {
                            Task { await viewModel.perform(action, on: entry.listing) }
                        },
                        onComplete: {
                            Task { await viewModel.complete(entry.listing) }
                        }
                    )
                    .transition(.hooprLift)
                    .hooprScrollLift()
                }
            }
            // A run arriving or leaving the board moves the others out of its
            // way rather than jumping them — keyed on which runs are listed, so
            // a roster changing inside a card doesn't re-run it.
            .animation(.hooprSwap, value: viewModel.timeline.map(\.id))
            .padding(.horizontal, Spacing.pageMargin)
            .padding(.top, Spacing.xl)
        }
    }

    /// Loaded, and genuinely nothing on.
    ///
    /// A composition rather than a grey sentence: the screen that has nothing
    /// to show is also the screen best placed to say what to do about it, and
    /// starting a run is the one thing that fixes an empty board. This is the
    /// only filled button on the tab, and it exists only in this state.
    private var emptyBoard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text(viewModel.emptyBoardText)
                .hooprType(.body)
                .foregroundStyle(Color.hooprSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onOpenMap) {
                Text("Start one")
                    .hooprType(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.hooprOnBrand)
                    .padding(.horizontal, Spacing.xl)
                    .frame(minHeight: 44)
                    .background(Color.hooprOrange)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.hooprPress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.pageMargin)
        .padding(.top, Spacing.xxl)
    }
}

#Preview {
    let authService = AuthService()
    LocalRunsTab(
        gameService: GameService(authService: authService),
        courtService: CourtService(),
        userProfileService: UserProfileService(authService: authService),
        friendService: FriendService(authService: authService),
        squadService: SquadService(authService: authService),
        onOpenProfile: {},
        onOpenMap: {}
    )
}
