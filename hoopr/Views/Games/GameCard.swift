import SwiftUI

/// One scheduled run on the Runs board.
///
/// Deliberately state-free: it renders what it's handed and reports taps. One
/// card for every run, so a run reads identically whether you're in it or
/// looking at it — only the primary action differs.
///
/// **Redesigned in UI revamp Phase 2b** (`UI_REDESIGN_BRIEF.md` §5.2). The
/// board is now one list ordered by tip-off rather than two collapsible
/// sections, which changes what this card has to do:
///
/// - **The time leads**, set in `headline` with tabular figures, because it is
///   the row's *rank* — the reader is scanning a schedule, not a set of boxes.
/// - **Spots left replaces the capacity bar.** The bar and `rosterText`
///   answered the same question twice, in a graphic and in 13pt grey; the
///   decision is "can I still get on it", which is one number, so it is set as
///   one and the bar is gone.
/// - **`isYours` draws a rail** down the leading edge. That mark is what the
///   *Queued Games* / *Public Games* split used to say, and it says it without
///   spending a viewport on two headers and two chevrons.
/// - **A waitlisted card says the waitlist doesn't move.** See `waitlistNote`.
///
/// It keeps `cardChrome()`, which is the one container on the screen that
/// earns its edges under §2c: a run is a single tappable unit carrying its own
/// controls.
struct GameCard: View {
    let listing: LocalRunsViewModel.Listing
    let action: LocalRunsViewModel.Action
    let isHost: Bool
    let isWaitlisted: Bool
    /// You're on this run's roster. Drawn as the leading rail — see the type
    /// doc. Defaults to `false` so the map's court card, which lists runs at
    /// one court rather than a board, doesn't have to answer a question it
    /// isn't asking.
    var isYours: Bool = false
    /// This card's write is in flight.
    let isPending: Bool
    /// Another card's write is in flight, so this one's button is inert.
    let isDisabled: Bool
    /// The host may mark this run finished — it's theirs and it has started.
    /// Independent of `action`, not a case of it: after tip-off a host has both
    /// this and "Cancel run", and `Action` only ever offers one thing.
    let canComplete: Bool
    let onAction: () -> Void
    let onComplete: () -> Void

    /// Shared by the clip and the chrome so the rail can't disagree with the
    /// border it runs down.
    private static let cornerRadius: CGFloat = 16

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var isConfirmingCancel = false
    @State private var isConfirmingComplete = false

    private var game: Game { listing.game }

    var body: some View {
        HStack(spacing: 0) {
            rail

            VStack(alignment: .leading, spacing: Spacing.md) {
                header
                courtLine

                // Nothing left to say for a public run with no distance —
                // and an empty row would still take the stack's spacing.
                if listing.distanceText != nil || !game.isPublic {
                    details
                }

                if let friendsHereText = listing.friendsHereText {
                    friendsHere(friendsHereText)
                }

                if isWaitlisted {
                    waitlistNote
                }

                // Host-only, matching the invite design: an invite-only run is
                // the host's to hand out, and every private run in this list is
                // one they created until the receiving half of the link ships.
                if isHost && !game.isPublic {
                    InviteLinkCard(link: game.inviteLink)
                }

                if action != .none {
                    primaryButton
                }

                if canComplete {
                    completeButton
                }
            }
            .padding(Spacing.cardPadding)
        }
        // Clipped to the card's own shape before the chrome goes on, or the
        // rail's square corners poke out past the rounded border.
        .clipShape(RoundedRectangle(cornerRadius: GameCard.cornerRadius))
        .cardChrome(cornerRadius: GameCard.cornerRadius)
        .confirmationDialog(
            "Cancel this run?",
            isPresented: $isConfirmingCancel,
            titleVisibility: .visible
        ) {
            Button("Cancel run", role: .destructive, action: onAction)
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("Everyone on the roster loses their spot. This can't be undone.")
        }
        // Completion is one-way — the update rule refuses a second write — and
        // it freezes the roster, so the dialog has to say both. The card also
        // vanishes from this list afterwards, which reads as a deletion unless
        // something has already framed it as the run being over.
        .confirmationDialog(
            "Mark this run complete?",
            isPresented: $isConfirmingComplete,
            titleVisibility: .visible
        ) {
            Button("Mark complete", action: onComplete)
            Button("Not yet", role: .cancel) {}
        } message: {
            Text("It moves to your stats and leaves this list. The roster is frozen and this can't be undone.")
        }
    }

    // MARK: - Sections

    /// The rail: you're on this run.
    ///
    /// Three points wide, flush to the card's leading edge inside its border,
    /// and `clear` when the run isn't yours — so every card is the same width
    /// and the rail reads as a mark rather than as a change of layout. This is
    /// what replaced the *Queued Games* / *Public Games* split.
    private var rail: some View {
        Rectangle()
            .fill(isYours ? Color.hooprBrandAccent : Color.clear)
            .frame(width: 3)
            .frame(maxHeight: .infinity)
    }

    /// The row's rank line: **when**, and whether there is room.
    ///
    /// Both are numbers, both are set as numbers, and they sit at the two ends
    /// of the same line because they are the two halves of one decision —
    /// *can I be there, and will I get on*. `monospacedDigit` so a roster
    /// filling up doesn't shuffle the line's width under the reader.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            // All three on one line, which is how it reads at every size the
            // width allows.
            HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                timeLabel
                badgeLabel
                Spacer(minLength: Spacing.sm)
                spotsLeft
            }

            // Out of room: the badge drops to its own line and the two numbers
            // keep the rank line to themselves.
            //
            // **Without this the time itself wrapped.** At `.accessibility3`
            // the three items overflowed and SwiftUI broke the *first* one, so
            // "6:45 PM" rendered as "6:45 / PM" — a reflow rather than a clip,
            // so it passed the no-truncation rule while destroying the thing
            // the line exists to do. The badge is the least load-bearing of
            // the three, so it is what moves.
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    timeLabel
                    Spacer(minLength: Spacing.sm)
                    spotsLeft
                }

                badgeLabel
            }
        }
    }

    /// `lineLimit(1)` is deliberate and is *not* a clip risk: a formatted time
    /// is a handful of characters, and `ViewThatFits` above guarantees it has
    /// a layout with room for them. What the limit prevents is the wrap.
    private var timeLabel: some View {
        Text(timeText)
            .hooprType(.headline)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(Color.hooprPrimaryText)
    }

    @ViewBuilder
    private var badgeLabel: some View {
        if let badge {
            Text(badge.text)
                .hooprType(.badge)
                .foregroundStyle(badge.foreground)
                .padding(.horizontal, Spacing.Pill.horizontal)
                .padding(.vertical, Spacing.Pill.vertical)
                .background(Capsule().fill(badge.wash.opacity(0.12)))
        }
    }

    /// "in 9" / "Full". The number the join decision turns on, at the same
    /// weight as the time.
    ///
    /// **This is what replaced the capacity bar.** The bar drew a ratio and
    /// `rosterText` restated it as "1 / 10 players" in 13pt grey — two
    /// renderings of one fact, neither of which is the question. The question
    /// is whether there is room.
    @ViewBuilder
    private var spotsLeft: some View {
        if game.isFull {
            Text("Full")
                .hooprType(.caption)
                .foregroundStyle(Color.hooprSecondaryText)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(game.openSlots)")
                    .hooprType(.headline)
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(Color.hooprPrimaryText)
                    // Someone joining rolls the number down in place: a live
                    // count, animated on change only.
                    .hooprNumericTransition(game.openSlots)

                Text(game.openSlots == 1 ? "spot" : "spots")
                    .hooprType(.caption)
                    .lineLimit(1)
                    .foregroundStyle(Color.hooprSecondaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(game.openSlots == 1 ? "1 spot left" : "\(game.openSlots) spots left")
        }
    }

    /// Where. Second, because the board is ordered by time — you already know
    /// roughly when, and the court is what you weigh against it.
    ///
    /// Led by the court glyph (2026-09-23), the mark Home's band and the map
    /// card set a court's name with — so a run's *where* reads the same
    /// everywhere. Shed at the accessibility sizes, as `CourtTitle` sheds it.
    private var courtLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if CourtTitle.showsGlyph(at: dynamicTypeSize) {
                Image.court
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprBrandAccent)
            }

            Text(listing.courtName)
                .hooprType(.subhead)
                .foregroundStyle(Color.hooprPrimaryText)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The distance, and whether it's invite-only.
    ///
    /// **The day left this line on 2026-09-23**: the board is grouped under a
    /// heading per day now (`LocalRunsTab.sectionHeader`), which is what used
    /// to need it here — two runs at "6:45 PM" on different days sort
    /// correctly but read identically without one.
    ///
    /// A `ViewThatFits` ladder rather than a plain `HStack` — the old row was
    /// flat, which is what let it break mid-word at `.accessibility3`
    /// (`gaps/ACCESSIBILITY.md`).
    private var details: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.md) { detailPieces }

            VStack(alignment: .leading, spacing: Spacing.xs) { detailPieces }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var detailPieces: some View {
        if let distanceText = listing.distanceText {
            detail(symbol: "location.fill", text: distanceText)
        }

        if !game.isPublic {
            detail(symbol: "lock.fill", text: game.visibilityText)
        }
    }

    /// **The one place this redesign adds information rather than re-ranking
    /// it.**
    ///
    /// A full run hands you a waitlist place, and that place **never
    /// promotes**: when a confirmed player leaves, the freed slot is not
    /// passed on. That is not an oversight — the update rule forbids writing
    /// another user's uid, which is the same rule that makes every roster
    /// write safe, so fixing it needs either a host action or a Cloud Function
    /// (`gaps/GAMES.md`). Until then the card said nothing, and a waitlist
    /// that looks like a queue is the one place this screen over-promised.
    ///
    /// Worded as a limitation with a next step, not as a dead end: you are
    /// still on the list, and the host can still make room.
    private var waitlistNote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .hooprType(.caption)

            Text("Waitlist spots don't move up yet — ask the host if someone drops.")
                .hooprType(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(Color.hooprSecondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Both come from `Game`, which is where a run's presentation strings
    /// live — so the board's rank line and Home's band can't disagree about
    /// what time the same run is at.
    private var timeText: String { game.timeText }

    /// Who you know is already on this run — the one piece of social proof on
    /// the card, and the reason `plans/FRIENDS.md` §4 calls it "you can now see
    /// it's worth joining."
    ///
    /// **Its own line, not a fourth `detail`:** that row is a plain `HStack`
    /// with no `ViewThatFits` ladder, so a fourth entry overflows at
    /// accessibility text sizes. **And not the header badge:** that slot is at
    /// most one badge about *your own* relationship to the run, and who else is
    /// here is a different question — folding them into one priority chain
    /// would mean a run you host could never show it.
    ///
    /// `hooprPrimaryText`, so it outweighs the grey details above it. (It
    /// avoided orange when `hooprOrange` failed AA as a foreground; that
    /// constraint went with `hooprBrandAccent`, so this now stands as a
    /// hierarchy choice rather than an accessibility one.)
    private func friendsHere(_ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "person.2.wave.2.fill")
                .hooprFont(11)

            Text(text)
                .hooprFont(13, weight: .semibold)
        }
        .foregroundStyle(Color.hooprPrimaryText)
    }

    private func detail(symbol: String, text: String) -> some View {
        HStack(spacing: 4) {
            // Sized against the caption beside it rather than given a role:
            // a glyph is not text and the uppercase roles carry a text case.
            Image(systemName: symbol)
                .hooprFont(11)
            Text(text)
                .hooprType(.caption)
        }
        .foregroundStyle(Color.hooprSecondaryText)
    }

    private var primaryButton: some View {
        Button {
            if action == .cancel {
                isConfirmingCancel = true
            } else {
                onAction()
            }
        } label: {
            Group {
                if isPending {
                    ProgressView()
                        .tint(action.isDestructive ? Color.hooprRed : Color.hooprOnBrand)
                } else {
                    Text(action.title)
                        .hooprFont(15, weight: .semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .foregroundStyle(action.isDestructive ? Color.hooprRed : Color.hooprOnBrand)
            .background(action.isDestructive ? Color.hooprFill : Color.hooprOrange)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.hooprPress)
        .disabled(isPending || isDisabled)
        .opacity(isDisabled && !isPending ? 0.5 : 1)
    }

    /// Recording that the run happened, for the host only.
    ///
    /// **Secondary, not a second primary.** It's bordered over `hooprFill` like
    /// `InviteLinkCard` — the card's other host-only affordance — so the thing a
    /// player is deciding still reads first. Not destructive either: completing
    /// takes nothing away, it's the run finishing as intended, and drawing it in
    /// `hooprRed` next to "Cancel run" would make two very different outcomes
    /// look alike.
    ///
    /// Shares `isPending`/`isDisabled` with the primary button because it shares
    /// `pendingGameId` with it — while either write is in flight, neither is
    /// tappable.
    private var completeButton: some View {
        Button {
            isConfirmingComplete = true
        } label: {
            Group {
                if isPending {
                    ProgressView()
                        .tint(Color.hooprPrimaryText)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle")
                            .hooprFont(13, weight: .semibold, maximumSize: 17)
                        Text("Mark complete")
                            .hooprFont(15, weight: .semibold)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .foregroundStyle(Color.hooprPrimaryText)
            .background(Color.hooprFill)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.hooprBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.hooprPress)
        .disabled(isPending || isDisabled)
        .opacity(isDisabled && !isPending ? 0.5 : 1)
    }

    /// At most one badge, in priority order — your own relationship to the run
    /// says more than its status does.
    ///
    /// **`foreground` and `wash` are separate colours**, because the text has
    /// to be *read* and the ground behind it is a fill. HOSTING's text is
    /// `hooprBrandAccent` (4.87:1 on its own 12% wash in light, 4.90:1 in
    /// dark) over a wash of the vivid `hooprOrange`; drawn as orange on that
    /// wash it measured 2.78:1 in light mode. The other two are secondary text
    /// on a wash of itself, unchanged.
    private var badge: (text: String, foreground: Color, wash: Color)? {
        if isHost { return ("Hosting", Color.hooprBrandAccent, Color.hooprOrange) }
        if isWaitlisted { return ("Waitlist", Color.hooprSecondaryText, Color.hooprSecondaryText) }
        if game.isFull { return ("Full", Color.hooprSecondaryText, Color.hooprSecondaryText) }
        return nil
    }
}

extension LocalRunsViewModel.ConfirmationKind {
    /// What a confirmed write on a run feels like (UI revamp Phase 3), on the
    /// Runs board and the map's court card alike. Getting on a run, or
    /// finishing one, is a success; leaving and cancelling take something away
    /// and are a light tap — deliberate, not celebrated.
    ///
    /// Fired off a view model's `lastConfirmation`, which only a write the user
    /// made and the server accepted sets — a roster changing under the
    /// listener never buzzes.
    var feedback: SensoryFeedback? {
        switch self {
        case .action(.join), .action(.joinWaitlist), .completed:
            return .success
        case .action(.leave), .action(.cancel):
            return .impact(weight: .light)
        case .action(.none):
            return nil
        }
    }
}
