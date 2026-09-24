import SwiftUI

/// One pending squad invite, with Join/Decline inline — a row in the inbox's
/// `DividedRows`, not a card (UI revamp Phase 2b).
///
/// Lives here rather than in `Views/Seasons/` because the inbox is now its
/// only home — squad invites used to render inline on Squad home, where a
/// leader can invite from squad detail but there was nowhere to *answer* one.
/// Moved to sit beside friend requests instead: both are "something's
/// waiting on you," and the inbox is where that already lives.
struct SquadInviteRow: View {
    let row: SquadViewModel.IncomingInvite
    let isBlocked: Bool

    /// Why Join isn't on offer — already on a squad, or the list hasn't loaded.
    /// When set, the button is *absent* rather than dimmed: `hooprPress` adds
    /// nothing to a disabled state, and a greyed capsule would leave the reason
    /// to be guessed. Declining stays, so the invite can still be cleared.
    let joinBlockedReason: String?

    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let squad = row.squad {
                SquadCrest(squad: squad, size: SquadCrest.Size.card)
            } else {
                SquadCrest(
                    iconKey: Squad.defaultIconKey,
                    colorKey: Squad.defaultColorKey,
                    size: SquadCrest.Size.card
                )
                .redacted(reason: .placeholder)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.squadName)
                    .hooprType(.subhead)
                    .foregroundStyle(Color.hooprPrimaryText)

                // The reason replaces the roster line rather than adding a
                // third: with no Join to weigh, how full the squad is stops
                // being the thing worth reading.
                Text(joinBlockedReason
                    ?? row.squad.map { "\($0.format.displayName) · \($0.rosterText)" }
                    ?? "Invited you to join")
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            // Each drawn at its label's size inside a full 44pt target, so a
            // row stays compact without shrinking what a thumb has to hit.
            HStack(spacing: 4) {
                if joinBlockedReason == nil {
                    Button("Join", action: onAccept)
                        .buttonStyle(.hooprFilled(.compact))
                }

                Button(action: onDecline) {
                    Text("Decline")
                        .hooprFont(14)
                        .foregroundStyle(Color.hooprRed)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .disabled(isBlocked)
        }
        .padding(.vertical, 8)
    }
}
