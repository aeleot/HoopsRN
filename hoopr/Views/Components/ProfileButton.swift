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
struct ProfileButton: View {
    /// Observed rather than passed as a count so the dot stays live while the
    /// tab that owns it is on screen. Reading the service directly is what
    /// keeps this working when the profile is closed — an inbox you can only
    /// discover by already being inside it isn't a notification.
    @ObservedObject var friendService: FriendService

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "person.crop.circle.fill")
                .hooprFont(32, maximumSize: 38)
                .foregroundStyle(Color.hooprSecondaryText)
                // Widens the tap target to the 44pt floor without widening the
                // glyph, the same way `CourtRow`'s star does.
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .overlay(alignment: .topTrailing) {
                    if hasUnansweredRequests {
                        Circle()
                            .fill(Color.hooprRed)
                            // A ring in the page's own background, so the dot
                            // reads as sitting on the glyph rather than as
                            // part of it.
                            .stroke(Color.hooprBackground, lineWidth: 2)
                            .frame(width: 11, height: 11)
                            .offset(x: -5, y: 5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(hasUnansweredRequests ? "Profile, requests waiting" : "Profile")
    }

    private var hasUnansweredRequests: Bool {
        !friendService.incomingRequests.isEmpty
    }
}
