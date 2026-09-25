import SwiftUI

/// The button that opens the inbox, carried by every tab — Profile included.
///
/// **It took the profile button's place** (2026-09-25, at the user's request).
/// The profile used to be a full-screen takeover behind a person glyph in
/// this slot, and the inbox sat one level further in, in the profile's top
/// bar. Profile is a tab now, so the slot went to the thing the old button's
/// notification dot was really pointing at: an inbox you had to open a screen
/// to reach wasn't a notification, and a dot that meant "go to the profile,
/// then look for the tray" was a signpost rather than a door.
///
/// One appearance and one position on every tab — see `Slot`. Each tab lays
/// the button out itself, so the constants are what keep it from jumping
/// when you switch.
struct InboxButton: View {
    /// Where every tab puts the button, so switching tabs never moves it.
    ///
    /// The frame's top `top` below the safe area and its trailing edge on
    /// `Spacing.pageMargin`. Home, Runs and Seasons lay the button out at the
    /// top of their band's first row; the map centres it on its search field
    /// and uses `centerY` to put that centre in the same place; the profile's
    /// top bar pads to it.
    ///
    /// Only fixed values, so the position can't depend on Dynamic Type or on
    /// what shares the row. The glyph grows with the reader's text size, but
    /// inside the fixed frame.
    enum Slot {
        /// The frame — also the 44pt tap-target floor.
        static let size: CGFloat = 44
        /// From the top of the safe area to the top of the frame.
        static let top: CGFloat = Spacing.md
        /// From the top of the safe area to the button's centre.
        static let centerY: CGFloat = top + size / 2
    }

    /// Sized to the frame rather than to the band's numeral: a tray drawn as
    /// large as the old person glyph (35pt) filled the slot edge to edge and
    /// left the badge nowhere to sit.
    private static let glyphSize: CGFloat = 22
    private static let glyphMaximumSize: CGFloat = 28

    /// Observed rather than handed a count, so the badge stays live on every
    /// tab without any screen's own view model having to be alive.
    @ObservedObject var friendService: FriendService

    /// The second kind of thing the inbox collects. Read here for the same
    /// reason as `friendService` — the badge has to agree with the inbox
    /// without the Seasons tab having been opened this session.
    @ObservedObject var squadService: SquadService

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "tray.fill")
                .hooprFont(Self.glyphSize, weight: .medium, maximumSize: Self.glyphMaximumSize)
                .foregroundStyle(Color.hooprPrimaryText)
                // Something new bounces the tray once (UI revamp Phase 3);
                // answering it doesn't.
                .hooprBounce(onRiseOf: waitingCount)
                .frame(width: Slot.size, height: Slot.size)
                .overlay(alignment: .topTrailing) {
                    if waitingCount > 0 {
                        HooprCountBadge(text: badgeText, count: waitingCount)
                            .offset(x: -1, y: 3)
                            .transition(.hooprPop)
                    }
                }
                .animation(.hooprSnap, value: waitingCount > 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Inbox")
        .accessibilityValue(accessibilityValue)
    }

    /// Everything waiting on you: friend requests plus squad invites — the two
    /// sections of `InboxSheet` that are asking for an answer. Requests *you*
    /// sent aren't counted; they're waiting on someone else.
    ///
    /// Read off the services rather than `FriendsViewModel.unansweredCount`,
    /// which counts friend requests only. The profile's old tray used that and
    /// so disagreed with the profile button's dot whenever a squad invite was
    /// the only thing waiting.
    static func waitingCount(incomingRequests: Int, incomingInvites: Int) -> Int {
        incomingRequests + incomingInvites
    }

    /// Kept to two glyphs so it fits the badge at every Dynamic Type size.
    static func badgeText(for count: Int) -> String {
        count > 9 ? "9+" : "\(count)"
    }

    private var waitingCount: Int {
        Self.waitingCount(
            incomingRequests: friendService.incomingRequests.count,
            incomingInvites: squadService.incomingInvites.count
        )
    }

    private var badgeText: String { Self.badgeText(for: waitingCount) }

    private var accessibilityValue: String {
        switch waitingCount {
        case 0: "Nothing waiting"
        case 1: "1 item waiting"
        default: "\(waitingCount) items waiting"
        }
    }
}
