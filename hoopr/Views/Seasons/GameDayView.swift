import SwiftUI

/// Screen 7 — game day. Countdown, court, both rosters with live arrival, and
/// "We're here."
///
/// Renders the same regardless of notification permission: a denial states
/// once what won't arrive, never a banner, never asked again — the game-day
/// screen's job is to show the game, not to nag about a decision the user
/// already made.
///
/// **Redesigned in UI revamp Phase 2b** (`UI_REDESIGN_BRIEF.md` §5.6). The
/// screen answers *do I leave now?*, and the answer, "Tip-off in 42m", was
/// 22pt inside a card, above seven more cards. Now the countdown is the band's
/// numeral (`GameDayBand`), **We're here** sits directly under the band, and
/// the two rosters are one side-by-side comparison with arrival counts
/// (`ArrivalBoard`). The band carries the back button, as squad detail's does.
///
/// **Not verifiable on one device** — it needs a live match between two
/// accounts (`gaps/SEASONS.md`). The band and the board take plain values, so
/// a render harness can draw them without a view model; that render is this
/// screen's evidence.
struct GameDayView: View {
    @StateObject private var viewModel: GameDayViewModel

    /// Screen 8. Passed in rather than pushed from here because the stack — and
    /// its `Route` — belong to `SeasonsTab`, the same way `MatchmakingCard`
    /// takes `onOpenGameDay`.
    private let onOpenResult: (SeasonGame) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var confirmingCancel = false

    init(
        game: SeasonGame,
        mySquadId: String,
        seasonGameService: SeasonGameService,
        squadService: SquadService,
        userProfileService: UserProfileService,
        notificationService: NotificationService,
        courtService: CourtService,
        onOpenResult: @escaping (SeasonGame) -> Void
    ) {
        self.onOpenResult = onOpenResult
        _viewModel = StateObject(wrappedValue: GameDayViewModel(
            game: game,
            mySquadId: mySquadId,
            seasonGameService: seasonGameService,
            squadService: squadService,
            userProfileService: userProfileService,
            notificationService: notificationService,
            courtService: courtService
        ))
    }

    private var game: SeasonGame { viewModel.game }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Re-evaluated each minute, so "Tip-off in 42m" counts down
                // while the screen is open rather than only when something
                // else redraws it.
                TimelineView(.everyMinute) { context in
                    GameDayBand(
                        headline: GameDayCountdown.headline(
                            scheduled: game.scheduledTime,
                            now: context.date,
                            isCancelled: game.status == .cancelled
                        ),
                        courtName: viewModel.courtName,
                        detail: detailLine
                    )
                }

                VStack(alignment: .leading, spacing: Spacing.section) {
                    if let errorMessage = viewModel.errorMessage {
                        ErrorBanner(
                            message: errorMessage,
                            onRetry: nil,
                            onDismiss: { viewModel.dismissError() }
                        )
                    }

                    actions

                    // A cancelled match has no arrivals to count; "0 of 3
                    // here" under "Cancelled" would only be noise.
                    if game.status != .cancelled {
                        arrivalBoard
                    }

                    if viewModel.canCancel {
                        cancelButton
                    }
                }
                .padding(.horizontal, Spacing.pageMargin)
                .padding(.top, Spacing.xxl)
                .padding(.bottom, Spacing.xxxl)
            }
        }
        .background(Color.hooprBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The band carries the back button, as squad detail's does. See
        // `BandBackButton`. The title stays for VoiceOver.
        .navigationTitle("Game day")
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityAction(.escape) { dismiss() }
    }

    private var arrivalBoard: some View {
        ArrivalBoard(
            ours: ArrivalBoard.Side(
                name: "Your squad",
                rows: viewModel.myRoster,
                arrivedUids: Set(game.arrivedPlayerIds)
            ),
            theirs: ArrivalBoard.Side(
                name: viewModel.opponentName,
                rows: viewModel.opponentRoster,
                arrivedUids: Set(game.arrivedPlayerIds)
            )
        )
    }

    /// "Saturday 7:30 PM · vs Court Vision" — when, and against whom.
    private var detailLine: String {
        let when = game.scheduledTime.formatted(.dateTime.weekday(.wide).hour().minute())
        return "\(when) · vs \(viewModel.opponentName)"
    }

    // MARK: - Actions

    /// The one thing this screen asks of someone standing outdoors, directly
    /// under the band. Once they've arrived it becomes a statement rather than
    /// a disabled button — a disabled button dims its label, and "You're
    /// marked as here" is the line they came back to read.
    @ViewBuilder
    private var actions: some View {
        let showsArriveButton = game.status == .scheduled && !viewModel.hasArrived

        VStack(alignment: .leading, spacing: Spacing.md) {
            if showsArriveButton {
                arrivedButton
                    .transition(.hooprLift)
            } else if viewModel.hasArrived && game.status == .scheduled {
                arrivedStatus
                    .transition(.hooprLift)
            }

            if viewModel.canOpenResult {
                resultButton(isPrimary: !showsArriveButton)
                    .transition(.hooprLift)
            }

            if viewModel.notificationsAreDenied {
                Text("Notifications are off, so reminders for this match won't arrive.")
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // "We're here" giving way to "You're marked as here".
        .animation(.hooprSwap, value: viewModel.hasArrived)
        .sensoryFeedback(trigger: viewModel.hasArrived) { old, new in
            Self.arrivalFeedback(wasHere: old, isHere: new)
        }
    }

    private var arrivedButton: some View {
        Button {
            Task { await viewModel.markArrived() }
        } label: {
            HStack(spacing: Spacing.sm) {
                if viewModel.isMarkingArrived {
                    ProgressView().tint(Color.hooprOnBrand)
                } else {
                    Image(systemName: "mappin.circle.fill")
                        .hooprFont(17, weight: .semibold, maximumSize: 24)
                }
                Text("We're here")
                    .hooprType(.headline)
            }
            .foregroundStyle(Color.hooprOnBrand)
            .padding(.vertical, Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Capsule().fill(Color.hooprOrange))
            .contentShape(Capsule())
        }
        .buttonStyle(.hooprPress)
        .disabled(viewModel.isMarkingArrived)
    }

    private var arrivedStatus: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .hooprFont(17, weight: .semibold, maximumSize: 24)
                .foregroundStyle(Color.hooprBrandAccent)
                .accessibilityHidden(true)
            Text("You're marked as here")
                .hooprType(.headline)
                .foregroundStyle(Color.hooprPrimaryText)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    /// Marking yourself here is felt as well as seen (UI revamp Phase 3) —
    /// only on the change from not-here to here, which only your own tap
    /// makes, never on opening the screen already marked.
    nonisolated static func arrivalFeedback(wasHere: Bool, isHere: Bool) -> SensoryFeedback? {
        !wasHere && isHere ? .success : nil
    }

    /// Where §4's T+90 notification — "How'd it go? Record the result." —
    /// actually lands. The filled button when it is the only thing left to do;
    /// a row under "We're here" while both still apply.
    @ViewBuilder
    private func resultButton(isPrimary: Bool) -> some View {
        Button {
            onOpenResult(game)
        } label: {
            if isPrimary {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "trophy.fill")
                        .hooprFont(17, weight: .semibold, maximumSize: 24)
                    Text(viewModel.resultButtonTitle)
                        .hooprType(.headline)
                }
                .foregroundStyle(Color.hooprOnBrand)
                .padding(.vertical, Spacing.md)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Capsule().fill(Color.hooprOrange))
                .contentShape(Capsule())
            } else {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "trophy.fill")
                        .hooprFont(15, weight: .semibold, maximumSize: 22)
                        .foregroundStyle(Color.hooprBrandAccent)
                    Text(viewModel.resultButtonTitle)
                        .hooprType(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.hooprPrimaryText)
                    Spacer(minLength: Spacing.sm)
                    Image(systemName: "chevron.right")
                        .hooprFont(13, weight: .semibold, maximumSize: 18)
                        .foregroundStyle(Color.hooprSecondaryText)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.hooprPress)
    }

    /// Quiet and last, and behind a confirmation. It used to cancel on one
    /// tap, for both squads, with nothing to undo it.
    private var cancelButton: some View {
        Button {
            confirmingCancel = true
        } label: {
            Text("Cancel match")
                .hooprType(.body)
                .fontWeight(.semibold)
                .foregroundStyle(Color.hooprRed)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .confirmationDialog(
            "Cancel this match?",
            isPresented: $confirmingCancel,
            titleVisibility: .visible
        ) {
            Button("Cancel match", role: .destructive) {
                Task { await viewModel.cancel() }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("It's called off for both squads and won't count toward either record.")
        }
    }
}

// MARK: - The countdown

/// What the band says about tip-off, as a label over a value — "Tip-off in"
/// over "42m" — so the value can be the numeral.
///
/// The same windows the old headline used: counting down while more than a
/// minute out, "Now" until the reporting delay has passed, then "Final" — the
/// same moments the T-0 and T+90 notifications describe, so the screen and the
/// copy that pointed at it never disagree. `nonisolated` and handed `now` so
/// every boundary is testable.
nonisolated enum GameDayCountdown {
    struct Headline: Equatable {
        let label: String
        let value: String
        /// The whole thing as a sentence, for VoiceOver — "42m" reads as
        /// "42 meters".
        let spoken: String
    }

    static func headline(scheduled: Date, now: Date, isCancelled: Bool) -> Headline {
        if isCancelled {
            return Headline(label: "Game day", value: "Cancelled", spoken: "This match was cancelled")
        }

        let interval = scheduled.timeIntervalSince(now)

        if interval > 60 {
            let (value, spoken) = remaining(minutes: Int(interval / 60))
            return Headline(label: "Tip-off in", value: value, spoken: "Tip-off in \(spoken)")
        } else if interval > -SeasonGame.reportingDelay {
            return Headline(label: "Tip-off", value: "Now", spoken: "Tip-off now")
        } else {
            return Headline(label: "Game day", value: "Final", spoken: "Final")
        }
    }

    /// "2d 3h", "1h 42m", "1h", "42m". Days past 24 hours, so a match booked
    /// for tomorrow evening doesn't read "26h 5m"; a zero second unit is
    /// dropped rather than shown as "1h 0m".
    static func remaining(minutes: Int) -> (value: String, spoken: String) {
        let days = minutes / (24 * 60)
        let hours = (minutes % (24 * 60)) / 60
        let mins = minutes % 60

        if days > 0 {
            return join((days, "d", "day"), (hours, "h", "hour"))
        } else if hours > 0 {
            return join((hours, "h", "hour"), (mins, "m", "minute"))
        } else {
            return join((mins, "m", "minute"), (0, "", ""))
        }
    }

    private static func join(
        _ first: (Int, String, String),
        _ second: (Int, String, String)
    ) -> (value: String, spoken: String) {
        func spoken(_ unit: (Int, String, String)) -> String {
            "\(unit.0) \(unit.2)\(unit.0 == 1 ? "" : "s")"
        }
        guard second.0 > 0 else {
            return ("\(first.0)\(first.1)", spoken(first))
        }
        return ("\(first.0)\(first.1) \(second.0)\(second.1)", "\(spoken(first)) \(spoken(second))")
    }
}

// MARK: - The band

/// Game day's hero: the countdown as the numeral, then the court, then when
/// and against whom. The same band as the rest of the app (Home's shape: a
/// numeral, then the court's name with its glyph), carrying its own back
/// button as squad detail's does.
struct GameDayBand: View {
    let headline: GameDayCountdown.Headline
    let courtName: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            BandBackButton()

            VStack(alignment: .leading, spacing: Spacing.sm) {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(headline.label)
                        .hooprType(.label)
                        .foregroundStyle(Color.hooprSecondaryText)

                    Text(headline.value)
                        .hooprType(.numeral)
                        .foregroundStyle(Color.hooprPrimaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(headline.spoken)
                .accessibilityAddTraits(.isHeader)

                CourtTitle(name: courtName)

                Text(detail)
                    .hooprType(.body)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Spacing.pageMargin)
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
}

// MARK: - The arrival board

/// Both rosters as one comparison: ours beside theirs, each with how many of
/// them are here as a number, then who. It replaces two roster cards, and the
/// count is the question the cards made you answer by counting ticks.
///
/// Side by side at the default sizes; one above the other at the
/// accessibility sizes, where two columns would cut every name.
struct ArrivalBoard: View {
    struct Side {
        let name: String
        let rows: [SquadViewModel.MemberRow]
        let arrivedUids: Set<String>

        var arrivedCount: Int { rows.filter { arrivedUids.contains($0.uid) }.count }
    }

    let ours: Side
    let theirs: Side

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Who's here")
                .hooprType(.label)
                .foregroundStyle(Color.hooprSecondaryText)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    column(ours)
                    column(theirs)
                }
            } else {
                HStack(alignment: .top, spacing: Spacing.lg) {
                    column(ours)
                    Rectangle()
                        .fill(Color.hooprBorder)
                        .frame(width: 1)
                    column(theirs)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func column(_ side: Side) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(side.name)
                    .hooprType(.subhead)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                    Text("\(side.arrivedCount)")
                        .hooprType(.title)
                        .monospacedDigit()
                        .foregroundStyle(Color.hooprPrimaryText)
                        .hooprNumericTransition(side.arrivedCount)
                    Text("of \(side.rows.count) here")
                        .hooprType(.caption)
                        .foregroundStyle(Color.hooprSecondaryText)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(side.arrivedCount) of \(side.rows.count) here")
                // Someone arriving ticks the count up and their circle over
                // (UI revamp Phase 3) — on the change only.
                .animation(.hooprSnap, value: side.arrivedUids)
            }

            if side.rows.isEmpty {
                ProgressView()
                    .padding(.vertical, Spacing.sm)
            } else {
                ForEach(side.rows) { member in
                    arrivalRow(member, arrived: side.arrivedUids.contains(member.uid))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The empty circle is `hooprSeparatorStrong`, a mark held to 3:1 on every
    /// ground. It was secondary text at 40% opacity, which nothing asserted.
    private func arrivalRow(_ member: SquadViewModel.MemberRow, arrived: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: arrived ? "checkmark.circle.fill" : "circle")
                .hooprFont(17, weight: .semibold, maximumSize: 24)
                .foregroundStyle(arrived ? Color.hooprBrandAccent : Color.hooprSeparatorStrong)
                .contentTransition(.symbolEffect(.replace))

            if member.isResolved {
                Text(member.displayName)
                    .hooprType(.body)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } else {
                // A skeleton rather than "Unknown player", as `SquadMemberRow`.
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.hooprFill)
                    .frame(width: 90, height: 14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(member.nameForProse), \(arrived ? "here" : "not here yet")")
    }
}
