import SwiftUI

/// Screen 7 — game day. Countdown, court, both rosters with live arrival, and
/// "We're here."
///
/// Renders the same regardless of notification permission: a denial states
/// once what won't arrive, never a banner, never asked again — the game-day
/// screen's job is to show the game, not to nag about a decision the user
/// already made.
struct GameDayView: View {
    @StateObject private var viewModel: GameDayViewModel

    /// Screen 8. Passed in rather than pushed from here because the stack — and
    /// its `Route` — belong to `SeasonsTab`, the same way `MatchmakingCard`
    /// takes `onOpenGameDay`.
    private let onOpenResult: (SeasonGame) -> Void

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.interCard) {
                if viewModel.game.status == .cancelled {
                    cancelledBanner
                }

                if let errorMessage = viewModel.errorMessage {
                    ErrorBanner(
                        message: errorMessage,
                        onRetry: nil,
                        onDismiss: { viewModel.dismissError() }
                    )
                }

                countdownCard
                courtCard

                if viewModel.notificationsAreDenied {
                    notificationsDeniedNote
                }

                rosterCard(title: "Your squad", rows: viewModel.myRoster)
                rosterCard(title: viewModel.opponentName, rows: viewModel.opponentRoster)

                if viewModel.game.status == .scheduled {
                    arrivedButton
                }

                if viewModel.canOpenResult {
                    resultButton
                }

                if viewModel.canCancel {
                    cancelButton
                }
            }
            .padding(16)
        }
        .background(Color.hooprBackground)
        .navigationTitle("Game day")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Sections

    private var cancelledBanner: some View {
        Text("This match was cancelled.")
            .hooprFont(14, weight: .semibold)
            .foregroundStyle(Color.hooprOnRed)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.hooprRed))
    }

    private var countdownCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(countdownHeadline)
                .hooprFont(22, weight: .bold)
                .foregroundStyle(Color.hooprPrimaryText)

            Text(viewModel.game.scheduledTime.formatted(.dateTime.weekday(.wide).hour().minute()))
                .hooprFont(15)
                .foregroundStyle(Color.hooprSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.cardPadding)
        .cardChrome()
    }

    /// "Tip-off in 42m", "Tip-off now", or "Final" once the window has
    /// closed — the same countdown a T-0/T+90 notification is describing, so
    /// the screen and the copy that pointed at it never disagree.
    private var countdownHeadline: String {
        let interval = viewModel.game.scheduledTime.timeIntervalSinceNow

        if interval > 60 {
            let minutes = Int(interval / 60)
            if minutes >= 60 {
                return "Tip-off in \(minutes / 60)h \(minutes % 60)m"
            }
            return "Tip-off in \(minutes)m"
        } else if interval > -SeasonGame.reportingDelay {
            return "Tip-off now"
        } else {
            return "Final"
        }
    }

    private var courtCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.and.ellipse")
                .hooprFont(18)
                .foregroundStyle(Color.hooprBrandAccent)

            Text(viewModel.courtName)
                .hooprFont(15, weight: .medium)
                .foregroundStyle(Color.hooprPrimaryText)

            Spacer(minLength: 0)
        }
        .padding(Spacing.cardPadding)
        .cardChrome()
    }

    private var notificationsDeniedNote: some View {
        Text("Notifications are off, so reminders for this match won't arrive.")
            .hooprFont(13)
            .foregroundStyle(Color.hooprSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 4)
    }

    private func rosterCard(title: String, rows: [SquadViewModel.MemberRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .hooprFont(13, weight: .semibold)
                .foregroundStyle(Color.hooprSecondaryText)
                .textCase(.uppercase)

            if rows.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ForEach(rows) { member in
                    SquadMemberRow(
                        member: member,
                        trailing: AnyView(arrivalMark(for: member.uid))
                    )
                }
            }
        }
        .padding(Spacing.cardPadding)
        .cardChrome()
    }

    private func arrivalMark(for uid: String) -> some View {
        Group {
            if viewModel.game.hasArrived(uid) {
                Image(systemName: "checkmark.circle.fill")
                    .hooprFont(18)
                    .foregroundStyle(Color.hooprBrandAccent)
                    .accessibilityLabel("Arrived")
            } else {
                Image(systemName: "circle")
                    .hooprFont(18)
                    .foregroundStyle(Color.hooprSecondaryText.opacity(0.4))
                    .accessibilityLabel("Not arrived yet")
            }
        }
    }

    private var arrivedButton: some View {
        Button {
            Task { await viewModel.markArrived() }
        } label: {
            HStack {
                if viewModel.isMarkingArrived {
                    ProgressView().tint(Color.hooprOnBrand)
                } else {
                    Image(systemName: viewModel.hasArrived ? "checkmark.circle.fill" : "mappin.circle")
                }
                Text(viewModel.hasArrived ? "You're marked as here" : "We're here")
                    .hooprFont(16, weight: .semibold)
            }
            .foregroundStyle(Color.hooprOnBrand)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Capsule().fill(viewModel.hasArrived ? Color.hooprFill : Color.hooprOrange))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.hasArrived || viewModel.isMarkingArrived)
    }

    /// Where §4's T+90 notification — "How'd it go? Record the result." —
    /// actually lands. Phase 5 shipped that copy before this screen existed;
    /// this is the tap-through it was always pointing at.
    private var resultButton: some View {
        Button {
            onOpenResult(viewModel.game)
        } label: {
            HStack {
                Image(systemName: "trophy")
                Text(viewModel.resultButtonTitle)
                    .hooprFont(16, weight: .semibold)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .hooprFont(13, weight: .semibold)
            }
            .foregroundStyle(Color.hooprPrimaryText)
            .padding(Spacing.cardPadding)
            .cardChrome()
        }
        .buttonStyle(.plain)
    }

    private var cancelButton: some View {
        Button {
            Task { await viewModel.cancel() }
        } label: {
            Text("Cancel match")
                .hooprFont(15, weight: .semibold)
                .foregroundStyle(Color.hooprRed)
        }
        .buttonStyle(.plain)
    }
}
