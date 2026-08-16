import SwiftUI

/// The one button every friendship action is drawn as, wherever it appears.
///
/// Compact in a row's trailing slot, wide in the profile sheet's action bar —
/// one component either way, so "Accept" can't read as a primary action in the
/// inbox and a secondary one on a profile. Colour comes from
/// `FriendsViewModel.Action.isDestructive`, matching `GameCard`'s treatment of
/// the same distinction.
struct FriendActionButton: View {
    enum Size {
        /// Sits beside a name in a list row.
        case compact
        /// Fills an action bar.
        case wide
    }

    let action: FriendsViewModel.Action
    var size: Size = .compact

    /// This player's write is in flight.
    let isPending: Bool

    /// Someone else's write is in flight, so this button is inert.
    let isDisabled: Bool

    /// Only for the accessibility label — the visible title is the action's.
    let playerName: String

    let onTap: () -> Void

    private var foreground: Color {
        action.isDestructive ? Color.hooprRed : Color.hooprOnBrand
    }

    private var background: Color {
        action.isDestructive ? Color.hooprFill : Color.hooprBrand
    }

    var body: some View {
        Button(action: onTap) {
            Group {
                if isPending {
                    ProgressView()
                        .tint(foreground)
                } else {
                    Text(size == .wide ? action.longTitle : action.title)
                        .hooprFont(size == .wide ? 16 : 14, weight: .semibold, maximumSize: 20)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(minWidth: size == .wide ? nil : 72)
            .frame(maxWidth: size == .wide ? .infinity : nil)
            .frame(height: size == .wide ? 50 : 36)
            .padding(.horizontal, size == .wide ? 0 : 12)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: size == .wide ? 12 : 10))
        }
        .buttonStyle(.plain)
        .disabled(isPending || isDisabled)
        // Only the *blocked* case dims: a button showing its own spinner is
        // already saying it's busy, and fading it too reads as broken.
        .opacity(isDisabled && !isPending ? Color.hooprDisabledOpacity : 1)
        .accessibilityLabel("\(action.longTitle), \(playerName)")
    }
}

/// A relationship with nothing quick to do about it — "Requested", "Friends".
///
/// Deliberately not a button: the full set of actions for these two states
/// (cancel, unfriend) lives on the profile sheet and in the inbox, both one tap
/// away, and putting an unfriend control in a search result is a mis-tap waiting
/// to happen.
struct FriendStateChip: View {
    let title: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol)
                    .hooprFont(11, weight: .semibold, maximumSize: 15)
            }
            Text(title)
                .hooprFont(13, weight: .semibold, maximumSize: 17)
                .lineLimit(1)
        }
        .foregroundStyle(Color.hooprSecondaryText)
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color.hooprFill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 12) {
        HStack(spacing: 10) {
            FriendActionButton(
                action: .add,
                isPending: false,
                isDisabled: false,
                playerName: "Jordan",
                onTap: {}
            )
            FriendActionButton(
                action: .decline,
                isPending: false,
                isDisabled: false,
                playerName: "Jordan",
                onTap: {}
            )
            FriendStateChip(title: "Friends", symbol: "checkmark")
        }

        FriendActionButton(
            action: .accept,
            size: .wide,
            isPending: false,
            isDisabled: false,
            playerName: "Jordan",
            onTap: {}
        )
    }
    .padding()
    .background(Color.hooprBackground)
}
