import SwiftUI

/// One pending squad invite, with Join/Decline inline.
///
/// Lives here rather than in `Views/Seasons/` because the inbox is now its
/// only home — squad invites used to render inline on Squad home, where a
/// leader can invite from squad detail but there was nowhere to *answer* one.
/// Moved to sit beside friend requests instead: both are "something's
/// waiting on you," and the inbox is where that already lives.
struct SquadInviteRow: View {
    let row: SquadViewModel.IncomingInvite
    let isBlocked: Bool
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
                    .hooprFont(15, weight: .semibold)
                    .foregroundStyle(Color.hooprPrimaryText)

                Text(row.squad.map { "\($0.format.displayName) · \($0.rosterText)" } ?? "Invited you to join")
                    .hooprFont(13)
                    .foregroundStyle(Color.hooprSecondaryText)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button("Join", action: onAccept)
                    .buttonStyle(.plain)
                    .hooprFont(14, weight: .semibold)
                    .foregroundStyle(Color.hooprOnBrand)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.hooprOrange))

                Button("Decline", action: onDecline)
                    .buttonStyle(.plain)
                    .hooprFont(14)
                    .foregroundStyle(Color.hooprRed)
            }
            .disabled(isBlocked)
        }
        .padding(12)
        .cardChrome(cornerRadius: 12)
    }
}
