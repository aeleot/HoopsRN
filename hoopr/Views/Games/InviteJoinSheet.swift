import SwiftUI

/// What an invite link opens: the run it names, and the one thing to do about
/// it.
///
/// Presented by `MainTabView` for an `InviteRouter.Request`, over whichever tab
/// is showing — and over whatever sheet is already up, the way a notification
/// tap stacks the inbox. Never shown signed out: `RootView` only builds the tab
/// shell for a signed-in user, and the request waits in `InviteRouter` until it
/// does.
///
/// **Every state a link can land in is a designed state**, not just the happy
/// path: room to join, full (the waitlist, with what it can't do), already on
/// it, on its waitlist, your own run, over, called off, and couldn't load.
/// Each says what it is and offers the next thing; none impersonates another.
///
/// Built from the create sheet's vocabulary — a grouped background, one
/// `FormPanel` of glyph rows for the run, one large filled button — so a run
/// reads the same whether you are making one or being asked to one.
struct InviteJoinSheet: View {
    @StateObject private var viewModel: InviteJoinViewModel
    /// Close the sheet and show the Runs tab, where a joined run now lives.
    let onOpenRuns: () -> Void
    let onDismiss: () -> Void

    init(
        gameId: String,
        gameService: GameService,
        courtService: CourtService,
        onOpenRuns: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: InviteJoinViewModel(
            gameId: gameId,
            gameService: gameService,
            courtService: courtService
        ))
        self.onOpenRuns = onOpenRuns
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(.horizontal, Spacing.pageMargin)
                    .padding(.top, Spacing.sm)
                    .padding(.bottom, Spacing.xxl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(.hooprSwap, value: viewModel.phase)
            }
            .background(Color.hooprGroupedBackground)
            .navigationTitle("Invite")
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
        .task { await viewModel.load() }
        // Only a join the server accepted — `joinCount` never moves on a load,
        // so opening a run you're already on doesn't buzz.
        .sensoryFeedback(.success, trigger: viewModel.joinCount)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            loading

        case .loaded(let game):
            if let landing = viewModel.landing {
                loaded(game, landing: landing)
                    .transition(.hooprLift)
            }

        case .missing:
            VStack(alignment: .leading, spacing: Spacing.xl) {
                heading(
                    symbol: "calendar.badge.exclamationmark",
                    copy: InviteJoinViewModel.missingCopy
                )
            }
            .transition(.hooprLift)

        case .failed(let message):
            VStack(alignment: .leading, spacing: Spacing.xl) {
                heading(
                    symbol: "exclamationmark.triangle.fill",
                    copy: .init(title: "Couldn't open this invite", message: message)
                )

                Button("Try again") {
                    Task { await viewModel.load() }
                }
                .buttonStyle(.hooprFilled(.large, role: .secondary))
            }
            .transition(.hooprLift)
        }
    }

    // MARK: - States

    private var loading: some View {
        VStack(spacing: Spacing.md) {
            ProgressView()
                .tint(Color.hooprSecondaryText)
            Text("Opening invite…")
                .hooprType(.caption)
                .foregroundStyle(Color.hooprSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Spacing.xxxl)
        .accessibilityElement(children: .combine)
    }

    private func loaded(_ game: Game, landing: InviteJoinViewModel.Landing) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            heading(symbol: Self.symbol(for: landing), copy: InviteJoinViewModel.copy(for: landing))

            runPanel(game)

            actions(for: landing)
        }
    }

    /// The glyph, the one-line answer, and the sentence under it —
    /// `SheetHeading`, the create sheet's "Your run is set" block, so the two
    /// read as one family.
    private func heading(symbol: String, copy: InviteJoinViewModel.Copy) -> some View {
        SheetHeading(symbol: symbol, title: copy.title, message: copy.message)
    }

    /// Where, when, and whether there's room — the three things anyone
    /// deciding on a run needs, in the create sheet's row grammar. **Never
    /// who**: a run shows how many are on it, not their names, on every
    /// surface (`gaps/GAMES.md`'s named ceilings).
    private func runPanel(_ game: Game) -> some View {
        FormPanel {
            FormRow(glyph: FormRowGlyph(.court, isLandscape: true)) {
                summary(viewModel.courtName, detail: place)
            }
            .accessibilityElement(children: .combine)

            FormRow(glyph: FormRowGlyph(systemName: "clock.fill")) {
                summary("\(game.dayText()) at \(game.timeText)", detail: nil)
            }
            .accessibilityElement(children: .combine)

            FormRow(glyph: FormRowGlyph(systemName: "person.3.fill")) {
                summary(game.spotsText, detail: game.rosterText)
            } trailing: {
                if !game.isPublic {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .hooprFont(11)
                        Text(game.visibilityText)
                            .hooprType(.caption)
                    }
                    .foregroundStyle(Color.hooprSecondaryText)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// "Durham · 1.2 mi", either half alone, or nothing.
    private var place: String? {
        let parts = [viewModel.city, viewModel.distanceText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func summary(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .hooprType(.subhead)
                .foregroundStyle(Color.hooprPrimaryText)
            if let detail, !detail.isEmpty {
                Text(detail)
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    /// One primary action at most, and a way to the run afterwards.
    ///
    /// The join button is the board's own `Action`, titled the same — "Join",
    /// "Join waitlist" — and it writes through the board's own path. Once
    /// you're on the run (or it's yours) the next thing is seeing it where it
    /// lives, so that's what's offered instead; an over run offers nothing but
    /// Done.
    @ViewBuilder
    private func actions(for landing: InviteJoinViewModel.Landing) -> some View {
        if let action = landing.action {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Button {
                    Task { await viewModel.join() }
                } label: {
                    if viewModel.isJoining {
                        ProgressView()
                    } else {
                        Text(action.title)
                    }
                }
                .buttonStyle(.hooprFilled(.large))
                .disabled(viewModel.isJoining)

                if let joinError = viewModel.joinError {
                    ProblemLine(message: joinError)
                }
            }
        } else if landing != .over {
            Button(action: onOpenRuns) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "calendar")
                    Text("See it in Runs")
                }
            }
            .buttonStyle(.hooprFilled(.large, role: .secondary))
        }
    }

    private static func symbol(for landing: InviteJoinViewModel.Landing) -> String {
        switch landing {
        case .join:       "envelope.open.fill"
        case .waitlist:   "person.badge.clock.fill"
        case .hosting:    "megaphone.fill"
        case .onRoster:   "checkmark.circle.fill"
        case .onWaitlist: "hourglass"
        case .over:       "flag.checkered"
        }
    }
}
