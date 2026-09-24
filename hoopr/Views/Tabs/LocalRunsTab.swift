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
        ScrollViewReader { proxy in
            content(scrollTo: { day in
                withAnimation(.hooprSpring) {
                    proxy.scrollTo(day, anchor: .top)
                }
            })
        }
    }

    private func content(scrollTo: @escaping (Date) -> Void) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                heroBand(scrollTo: scrollTo)

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
        .hooprStatusBarScrim()
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
    /// **Redesigned 2026-09-23, at the user's request** — the band was "very
    /// plain, very grey", and its header "does not make sense". It said "3
    /// games on the schedule" under an eyebrow that flipped between "Tonight"
    /// and "Coming up", over "You're suited up for all 3": three lines of
    /// copy for what a calendar says at a glance. Now:
    ///
    /// - **The week** (`RunsWeekStrip`) — seven days, a dot a run, filled where
    ///   you're on it; tapping a day scrolls the board to it.
    /// - **The count leads** — "3 runs" under the "This week" label — and the
    ///   week closes the band, with a waitlist place or runs after the week
    ///   over it when there are any (the user's layout, 2026-09-23).
    /// - **The juice** — the brand orange rising from the leading edge, as on
    ///   Home, and the court half off the trailing edge (`RunsBandCourt`), as
    ///   Home has its ball. Both at luminances every pairing on the band
    ///   already clears.
    ///
    /// **Compact** (the user's call, 2026-09-23: "make the header smaller"):
    /// the label and the count share the profile button's row rather than
    /// stacking under it, the count is `title` rather than the 44pt numeral,
    /// and the band closes tighter under the week.
    ///
    /// **Opened up a little** (the user's call, 2026-09-24): the count sat
    /// hard against both the top and the calendar. It now starts 12pt down
    /// from its row's top (was 4) and there is 20pt between that row and the
    /// week (was 12) — 16pt taller in all. The profile button does not move:
    /// its slot is the same point on every tab, so the room is made by the
    /// text block's own padding rather than by the band's.
    private func heroBand(scrollTo: @escaping (Date) -> Void) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This week")
                        .hooprType(.label)
                        .foregroundStyle(Color.hooprSecondaryText)

                    if viewModel.hasLoaded {
                        weekCount
                    } else {
                        placeholder(width: 110, height: 30)
                    }
                }
                .padding(.top, Spacing.md)

                Spacer(minLength: 0)

                ProfileButton(friendService: friendService, squadService: squadService, action: onOpenProfile)
            }

            bandAnswer(scrollTo: scrollTo)
        }
        .padding(.horizontal, Spacing.pageMargin)
        // The profile button's slot — the same point on every tab.
        .padding(.top, ProfileButton.Slot.top)
        .padding(.bottom, Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                HeroWash(placement: .leading(.hooprBrandWash))
                RunsBandCourt()
            }
            .clipped()
            .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.hooprSeparatorStrong)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func bandAnswer(scrollTo: @escaping (Date) -> Void) -> some View {
        if !viewModel.hasLoaded {
            placeholder(width: 362, height: 76)
                .accessibilityLabel("Loading the schedule")
        } else {
            // The count sits up in the top row; a waitlist place or runs after
            // the week, when there are any, and the calendar close the band
            // (the user's layout, 2026-09-23).
            VStack(alignment: .leading, spacing: Spacing.md) {
                if viewModel.waitlistedCount > 0 || viewModel.laterCount > 0 {
                    standing
                }
                RunsWeekStrip(days: viewModel.weekStrip, onSelect: scrollTo)
            }
        }
    }

    /// "3 runs", under the "This week" label, so the line doesn't say the
    /// week again. `title`, not the numeral: the band is compact now, and the
    /// week strip under it is what the eye goes to.
    private var weekCount: some View {
        let count = viewModel.weekStrip.reduce(0) { $0 + $1.total }

        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(count)")
                .hooprType(.title)
                .monospacedDigit()
                .foregroundStyle(Color.hooprPrimaryText)
                .hooprNumericTransition(count)

            Text(count == 1 ? "run" : "runs")
                .hooprType(.headline)
                .foregroundStyle(Color.hooprSecondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count == 1 ? "1 run this week" : "\(count) runs this week")
    }

    /// What the week's dots can't say — a waitlist place, and runs after the
    /// week — each a glyph, a number and what it counts, and only when there
    /// is one. **"You're in" is gone** (the user's call, 2026-09-23): the
    /// strip's filled dots are the runs you're in, so the line said it twice.
    private var standing: some View {
        let waitlisted = viewModel.waitlistedCount
        let later = viewModel.laterCount

        return FlowLayout(spacing: Spacing.lg, lineSpacing: Spacing.sm) {
            if waitlisted > 0 {
                RunsBandStat(
                    symbol: "hourglass",
                    value: "\(waitlisted)",
                    unit: "waitlisted",
                    spoken: "Waitlisted for \(waitlisted)"
                )
            }

            if later > 0 {
                RunsBandStat(
                    symbol: "calendar.badge.clock",
                    value: "\(later)",
                    unit: "later",
                    spoken: later == 1 ? "1 more run after this week" : "\(later) more runs after this week"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            VStack(alignment: .leading, spacing: Spacing.interRow) {
                ForEach(viewModel.sections) { section in
                    sectionHeader(section)
                        .id(section.day)

                    ForEach(section.entries) { entry in
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
            }
            // A run arriving or leaving the board moves the others out of its
            // way rather than jumping them — keyed on which runs are listed, so
            // a roster changing inside a card doesn't re-run it.
            .animation(.hooprSwap, value: viewModel.timeline.map(\.id))
            .padding(.horizontal, Spacing.pageMargin)
            .padding(.top, Spacing.md)
        }
    }

    /// A day's heading: "Today" and its date, and how many runs are on it.
    /// Where the strip's tap lands, so it also carries the card's lost day.
    private func sectionHeader(_ section: LocalRunsViewModel.DaySection) -> some View {
        let title = LocalRunsViewModel.sectionTitle(for: section.day, now: Date())
        let count = section.entries.count

        return HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            Text(title)
                .hooprType(.label)
                .foregroundStyle(Color.hooprPrimaryText)

            Text(section.day.formatted(.dateTime.month(.abbreviated).day()))
                .hooprType(.caption)
                .foregroundStyle(Color.hooprSecondaryText)

            Spacer(minLength: Spacing.sm)

            Text(count == 1 ? "1 run" : "\(count) runs")
                .hooprType(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.hooprSecondaryText)
        }
        .padding(.top, Spacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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

            Button("Start one", action: onOpenMap)
                .buttonStyle(.hooprFilled(.regular))
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
