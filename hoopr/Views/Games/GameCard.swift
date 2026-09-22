import SwiftUI

/// One scheduled run in the Local Runs lists.
///
/// Deliberately state-free: it renders what it's handed and reports taps. Both
/// sections use the same card, so a run reads identically whether you're in it
/// or looking at it — only the primary action differs.
struct GameCard: View {
    let listing: LocalRunsViewModel.Listing
    let action: LocalRunsViewModel.Action
    let isHost: Bool
    let isWaitlisted: Bool
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

    @State private var isConfirmingCancel = false
    @State private var isConfirmingComplete = false

    private var game: Game { listing.game }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            details

            if let friendsHereText = listing.friendsHereText {
                friendsHere(friendsHereText)
            }

            capacity

            // Host-only, matching the invite design: an invite-only run is the
            // host's to hand out, and every private run in this list is one
            // they created until the receiving half of the link ships.
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
        .cardChrome()
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

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "basketball.fill")
                .hooprFont(18)
                .foregroundStyle(Color.hooprBrandAccent)

            VStack(alignment: .leading, spacing: 3) {
                Text(listing.courtName)
                    .hooprFont(16, weight: .semibold)
                    .foregroundStyle(Color.hooprPrimaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(game.scheduledText())
                    .hooprFont(14, weight: .medium)
                    .foregroundStyle(Color.hooprSecondaryText)
            }

            Spacer(minLength: 8)

            if let badge = badge {
                Text(badge.text)
                    .hooprFont(11, weight: .bold)
                    .foregroundStyle(badge.foreground)
                    .padding(.horizontal, Spacing.Pill.horizontal)
                    .padding(.vertical, Spacing.Pill.vertical)
                    .background(Capsule().fill(badge.wash.opacity(0.12)))
            }
        }
    }

    private var details: some View {
        HStack(spacing: 14) {
            detail(symbol: "person.2.fill", text: game.rosterText)

            if let distanceText = listing.distanceText {
                detail(symbol: "location.fill", text: distanceText)
            }

            if !game.isPublic {
                detail(symbol: "lock.fill", text: game.visibilityText)
            }

            Spacer(minLength: 0)
        }
    }

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
            Image(systemName: symbol)
                .hooprFont(11)
            Text(text)
                .hooprFont(13)
        }
        .foregroundStyle(Color.hooprSecondaryText)
    }

    /// How full the run is, at a glance. The bar is the only thing on the card
    /// that reads before the text does, which is the decision a player is
    /// actually making.
    private var capacity: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.hooprFill)

                Capsule()
                    .fill(game.isFull ? Color.hooprSecondaryText : Color.hooprBrandAccent)
                    .frame(width: geo.size.width * filledFraction)
            }
        }
        .frame(height: 5)
        .accessibilityLabel(game.rosterText)
    }

    /// Clamped, so a hand-edited over-full roster can't draw past the track.
    private var filledFraction: CGFloat {
        guard game.maxPlayers > 0 else { return 0 }
        return min(1, CGFloat(game.playerIds.count) / CGFloat(game.maxPlayers))
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
        .buttonStyle(.plain)
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
        .buttonStyle(.plain)
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
        if isHost { return ("HOSTING", Color.hooprBrandAccent, Color.hooprOrange) }
        if isWaitlisted { return ("WAITLIST", Color.hooprSecondaryText, Color.hooprSecondaryText) }
        if game.isFull { return ("FULL", Color.hooprSecondaryText, Color.hooprSecondaryText) }
        return nil
    }
}
