import SwiftUI

/// A player's circle: their initial when the name has resolved, a neutral glyph
/// while it hasn't.
///
/// An empty circle would read as a broken image rather than a pending lookup,
/// which is the whole reason this has a fallback at all. Extracted because the
/// friends list, the inbox and the profile sheet all draw the same circle, and
/// the alternative was a fourth copy of it.
///
/// Sizing is deliberately **not** Dynamic Type: the glyph and the initial are
/// fractions of a fixed-diameter circle, so scaling them would push them past
/// their own container. The same exception `ProfileRow`'s leading square takes,
/// for the same reason.
///
/// There was an `onBrand` variant that filled the circle white for the orange
/// profile header. That header is gone — every avatar in the app now sits on a
/// surface — so the variant went with it.
struct PlayerAvatar: View {
    /// Every diameter the app draws an avatar at, named by where (UI revamp
    /// Phase 6) — the shape `SquadCrest.Size` has, so a new screen picks a
    /// size rather than inventing a sixth.
    enum Size {
        /// Beside a name in a bar — the profile's top bar.
        static let inline: CGFloat = 28
        /// A squad roster or an invite row, where the crest sets the scale.
        static let roster: CGFloat = 34
        /// A friends-list row.
        static let row: CGFloat = 44
        /// The player sheet's header.
        static let sheet: CGFloat = 56
        /// Your own profile — the base the identity block scales from with
        /// Dynamic Type.
        static let profile: CGFloat = 72
    }

    /// One or two uppercased letters, or empty to select the fallback glyph.
    let initial: String

    let diameter: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.hooprFill)

            Group {
                if initial.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: diameter * 0.5))
                } else {
                    Text(initial)
                        .font(.system(size: diameter * 0.38, weight: .bold))
                }
            }
            .foregroundStyle(
                initial.isEmpty ? Color.hooprSecondaryText : Color.hooprBrandAccent
            )
        }
        .frame(width: diameter, height: diameter)
        // The name it stands for is always rendered beside it, so announcing
        // the letter as well is noise.
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 16) {
        PlayerAvatar(initial: "J", diameter: 44)
        PlayerAvatar(initial: "", diameter: 44)
        PlayerAvatar(initial: "EA", diameter: 72)
    }
    .padding()
    .background(Color.hooprBackground)
}
