import SwiftUI

/// The button that opens the profile, carried by every tab except the profile
/// itself.
///
/// It used to live once, in the floating header the tabs shared. With the tab
/// bar moved to the bottom that header is gone, so each tab draws its own —
/// which is exactly why this is a component and not three copies: the badge
/// rule below is the part worth having in one place.
struct ProfileButton: View {
    /// Two grounds, one glyph. `plain` sits on a page background (Home, Runs);
    /// `glass` sits on the map, where the button floats over moving content
    /// and needs the same 46pt glass circle the recenter control uses.
    enum Style {
        case plain
        case glass
    }

    /// Observed rather than passed as a count so the dot stays live while the
    /// tab that owns it is on screen. Reading the service directly is what
    /// keeps this working when the profile is closed — an inbox you can only
    /// discover by already being inside it isn't a notification.
    @ObservedObject var friendService: FriendService

    var style: Style = .plain
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            glyph
                .overlay(alignment: .topTrailing) {
                    if hasUnansweredRequests {
                        Circle()
                            .fill(Color.hooprRed)
                            // A ring in the ground's own colour, so the dot
                            // reads as sitting on the glyph rather than as
                            // part of it.
                            .stroke(ringColor, lineWidth: 2)
                            .frame(width: 11, height: 11)
                            .offset(x: badgeOffset.x, y: badgeOffset.y)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasUnansweredRequests ? "Profile, requests waiting" : "Profile")
    }

    @ViewBuilder
    private var glyph: some View {
        switch style {
        case .plain:
            Image(systemName: "person.crop.circle.fill")
                .hooprFont(32, maximumSize: 38)
                .foregroundStyle(Color.hooprSecondaryText)
                // Widens the tap target to the 44pt floor without widening the
                // glyph, the same way `CourtRow`'s star does.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())

        case .glass:
            Image(systemName: "person.crop.circle.fill")
                .hooprFont(22, weight: .semibold, maximumSize: 26)
                .foregroundStyle(Color.hooprSecondaryText)
                .frame(width: 46, height: 46)
                .glassEffect(.regular.interactive(), in: .circle)
        }
    }

    /// Red, matching the inbox badge it leads to, and not the brand orange: a
    /// notification has to read as one thing to deal with rather than as more
    /// brand — and the tab bar beneath is already orange where it's selected.
    private var ringColor: Color {
        switch style {
        case .plain: Color.hooprBackground
        case .glass: Color.hooprSurface
        }
    }

    /// The glass variant's glyph is inset inside a 46pt circle, so its dot
    /// needs pulling in further than the plain one's to stay on the glyph.
    private var badgeOffset: (x: CGFloat, y: CGFloat) {
        switch style {
        case .plain: (-5, 5)
        case .glass: (-11, 11)
        }
    }

    private var hasUnansweredRequests: Bool {
        !friendService.incomingRequests.isEmpty
    }
}
