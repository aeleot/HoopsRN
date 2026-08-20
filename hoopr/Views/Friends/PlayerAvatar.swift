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
/// their own container. The same exception `ProfileView`'s avatar takes, for the
/// same reason.
struct PlayerAvatar: View {
    /// A single uppercased letter, or empty to select the fallback glyph.
    let initial: String

    let diameter: CGFloat

    /// Reversed for the orange profile header, where the circle sits on the
    /// brand colour rather than on a surface.
    var onBrand = false

    var body: some View {
        ZStack {
            Circle()
                .fill(onBrand ? Color.hooprOnBrand : Color.hooprFill)

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
                initial.isEmpty && !onBrand ? Color.hooprSecondaryText : Color.hooprOrange
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
        PlayerAvatar(initial: "E", diameter: 56, onBrand: true)
            .padding(8)
            .background(Color.hooprOrange)
    }
    .padding()
    .background(Color.hooprBackground)
}
