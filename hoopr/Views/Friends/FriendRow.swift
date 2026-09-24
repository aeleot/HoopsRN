import SwiftUI

/// One person, as a row: avatar, name over a subtitle, and whatever control
/// the list they're in calls for.
///
/// Replaces the tall `FriendCard` this tab used to stack. A friends list is a
/// list of *people*, and a full-width button under each name made twelve friends
/// read as twelve forms.
///
/// **A row, not a card, since UI revamp Phase 2b** (`UI_REDESIGN_BRIEF.md`
/// §5.9). It carried an inline, unnamed copy of the card recipe (radius 14,
/// border, shadow) around every person; the lists now put these in
/// `DividedRows`, with the hairline starting under the name
/// (`FriendRow.textInset`).
///
/// Deliberately state-free, like `GameCard`: it renders what it's handed and
/// reports taps. The trailing control is supplied by the caller rather than
/// derived from a mode flag, so one row serves the friends list, the search
/// results and both inbox sections without knowing which it's in.
struct FriendRow<Trailing: View>: View {
    let row: FriendsViewModel.Row

    /// The line under the name — a home court, a handle, "Wants to add you".
    let subtitle: String

    /// Opening this person's profile. The identity half of the row is the
    /// target; the trailing control keeps its own.
    let onOpen: () -> Void

    @ViewBuilder let trailing: Trailing

    private static var avatarDiameter: CGFloat { PlayerAvatar.Size.row }

    /// Where a `DividedRows` hairline starts, so it runs under the name rather
    /// than the avatar.
    static var textInset: CGFloat { avatarDiameter + 12 }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    PlayerAvatar(initial: row.initial, diameter: Self.avatarDiameter)

                    if row.isResolved {
                        identity
                    } else {
                        skeleton
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                subtitle.isEmpty ? row.nameForProse : "\(row.nameForProse), \(subtitle)"
            )
            .accessibilityHint("Double tap to view profile")

            trailing
        }
        .padding(.vertical, 10)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.displayName)
                .hooprType(.subhead)
                .foregroundStyle(Color.hooprPrimaryText)
                .lineLimit(1)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .hooprType(.caption)
                    .foregroundStyle(Color.hooprSecondaryText)
                    .lineLimit(1)
            }
        }
    }

    /// Held space rather than a name, while the profile lookup is in flight.
    /// The row is still fully actionable — the friendship is the real data, the
    /// name is a decoration on it — so this is a placeholder, not a disabled
    /// state.
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.hooprFill)
                .frame(width: 120, height: 13)
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.hooprFill)
                .frame(width: 76, height: 10)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    let profile = UserProfile(
        id: "abc",
        userName: "Jordan Ellis",
        userNameLower: "jordan ellis",
        homeCourtId: nil,
        preferredRadius: nil,
        favoriteCourtIds: nil,
        createdAt: Date(),
        updatedAt: Date(),
        completedGameCount: nil,
        participationStreak: nil,
        lastCompletedAt: nil
    )

    return DividedRows(leadingInset: 56) {
        FriendRow(
            row: .init(uid: "abc", profile: profile, relationship: .friends),
            subtitle: "Durham Central Park",
            onOpen: {}
        ) {
            FriendStateChip(title: "Friends", symbol: "checkmark")
        }

        FriendRow(
            row: .init(uid: "def", profile: nil, relationship: .none),
            subtitle: "",
            onOpen: {}
        ) {
            FriendActionButton(
                action: .add,
                isPending: false,
                isDisabled: false,
                playerName: "this player",
                onTap: {}
            )
        }
    }
    .padding(16)
    .background(Color.hooprBackground)
}
