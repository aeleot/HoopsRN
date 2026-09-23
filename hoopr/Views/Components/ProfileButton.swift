import SwiftUI

/// The button that opens the profile, carried by every tab except the profile
/// itself.
///
/// It used to live once, in the floating header the tabs shared. With the tab
/// bar moved to the bottom that header is gone, so each tab draws its own —
/// which is exactly why this is a component and not three copies: the badge
/// rule below is the part worth having in one place.
///
/// One appearance, not a per-tab ground: the map used to draw this in a glass
/// circle, matching the search field it sat beside. That made it the one
/// glyph in the app that looked different depending which tab you were on —
/// so it's gone, and the map now carries the same plain glyph Home and Runs
/// always have.
///
/// One position, too — see `Slot`. Having one appearance wasn't enough: each
/// tab placed the button itself, and the three placements disagreed by up to
/// 8pt across and 4pt down, so it visibly jumped on every tab switch.
struct ProfileButton: View {
    /// Where every tab puts the button, so switching tabs never moves it.
    ///
    /// Home's placement, which the others were measured against: the frame's
    /// top `top` below the safe area and its trailing edge on
    /// `Spacing.pageMargin`. Home, Runs and Seasons lay the button out at the
    /// top of their first row; the map centres it on its search field, and
    /// uses `centerY` to put that centre in the same place.
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

    /// 10% up on the 32pt it was, so it holds its own against the band's 44pt
    /// numeral. The cap still fits `Slot.size`, which is what keeps Dynamic
    /// Type from moving it.
    private static let glyphSize: CGFloat = 35.2
    private static let glyphMaximumSize: CGFloat = 41.8

    /// Observed rather than passed as a count so the dot stays live while the
    /// tab that owns it is on screen. Reading the service directly is what
    /// keeps this working when the profile is closed — an inbox you can only
    /// discover by already being inside it isn't a notification.
    @ObservedObject var friendService: FriendService

    /// Same reasoning as `friendService`: a squad invite is the second kind of
    /// thing the inbox collects, and the badge has to agree with it without
    /// the Seasons tab having ever been opened this session.
    @ObservedObject var squadService: SquadService

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "person.crop.circle.fill")
                .hooprFont(Self.glyphSize, maximumSize: Self.glyphMaximumSize)
                .foregroundStyle(Color.hooprSecondaryText)
                // Widens the tap target to the 44pt floor without widening the
                // glyph, the same way `CourtRow`'s star does.
                .frame(width: Slot.size, height: Slot.size)
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if hasUnansweredRequests {
                        Circle()
                            .fill(Color.hooprRed)
                            // A ring in the page's own background, so the dot
                            // reads as sitting on the glyph rather than as
                            // part of it.
                            .stroke(Color.hooprBackground, lineWidth: 2)
                            // Scaled with the glyph, and pulled in to stay on
                            // its rim at 45° now that the glyph fills more of
                            // the frame.
                            .frame(width: 12, height: 12)
                            .offset(x: -3.5, y: 3.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasUnansweredRequests ? "Profile, notifications waiting" : "Profile")
    }

    private var hasUnansweredRequests: Bool {
        !friendService.incomingRequests.isEmpty || !squadService.incomingInvites.isEmpty
    }
}
