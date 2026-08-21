import SwiftUI

/// One person, as a compact card: avatar, name over a subtitle, and whatever
/// control the list they're in calls for.
///
/// Replaces the tall `FriendCard` this tab used to stack. A friends list is a
/// list of *people*, and a full-width button under each name made twelve friends
/// read as twelve forms. The chrome is still the app's card — `hooprSurface`, a
/// 1pt `hooprBorder`, the same 6% shadow `GameCard` and `ProfileRow` carry — at
/// roughly a third of the height.
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

    private static var avatarDiameter: CGFloat { 44 }

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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.hooprSurface)
                .shadow(color: Color.hooprShadow(opacity: 0.06), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.hooprBorder, lineWidth: 1)
        )
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.displayName)
                .hooprFont(16, weight: .semibold)
                .foregroundStyle(Color.hooprPrimaryText)
                .lineLimit(1)

            if !subtitle.isEmpty {
                Text(subtitle)
                    .hooprFont(13)
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
        updatedAt: Date()
    )

    return VStack(spacing: 10) {
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
