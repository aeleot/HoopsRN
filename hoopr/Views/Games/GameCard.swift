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
    let onAction: () -> Void

    @State private var isConfirmingCancel = false

    private var game: Game { listing.game }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            details
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
        }
        .padding(16)
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
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "basketball.fill")
                .hooprFont(18)
                .foregroundStyle(Color.hooprOrange)

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
                    .foregroundStyle(badge.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(badge.tint.opacity(0.12)))
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
                    .fill(game.isFull ? Color.hooprSecondaryText : Color.hooprOrange)
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

    /// At most one badge, in priority order — your own relationship to the run
    /// says more than its status does.
    private var badge: (text: String, tint: Color)? {
        if isHost { return ("HOSTING", Color.hooprOrange) }
        if isWaitlisted { return ("WAITLIST", Color.hooprSecondaryText) }
        if game.isFull { return ("FULL", Color.hooprSecondaryText) }
        return nil
    }
}
