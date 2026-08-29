import SwiftUI

/// A squad's crest: its SF Symbol on a filled disc in its palette colour.
///
/// **One view with a size parameter, not five drawings.** The crest appears at
/// five sizes across Seasons — squad home, a match card, a list row, the pool,
/// and an inline row — and every proportion inside it (glyph, hairline) is
/// derived from that one number, so a new size needs no new drawing and can't
/// disagree with the others about how big the glyph is.
///
/// Colour comes from `Color.hooprSquad(_:)` rather than from the caller: the
/// document stores a palette *key*, and resolving it in one place is what keeps
/// a crest appearance-aware. The glyph is `hooprOnCrest`, whose contrast
/// against all eight fills is pinned in `ThemeContrastTests`.
struct SquadCrest: View {
    let iconKey: String
    let colorKey: String
    let size: CGFloat

    init(iconKey: String, colorKey: String, size: CGFloat = Size.row) {
        self.iconKey = iconKey
        self.colorKey = colorKey
        self.size = size
    }

    init(squad: Squad, size: CGFloat = Size.row) {
        self.init(iconKey: squad.iconKey, colorKey: squad.colorKey, size: size)
    }

    /// The five sizes the design actually calls for, named so a call site says
    /// *where* it is rather than what number it picked.
    enum Size {
        /// Squad home.
        static let hero: CGFloat = 64
        /// A match card.
        static let card: CGFloat = 44
        /// A list row.
        static let row: CGFloat = 32
        /// The matchmaking pool.
        static let pool: CGFloat = 24
        /// Beside a line of text.
        static let inline: CGFloat = 20
    }

    var body: some View {
        Circle()
            .fill(Color.hooprSquad(colorKey))
            .overlay(
                // The fills are light by construction — that's what lets the
                // glyph be dark — which leaves a pale crest with very little
                // edge against a white page. The hairline is what gives the
                // disc a boundary there, and it's the same one `cardChrome`
                // uses so a crest and a card are outlined alike.
                Circle().stroke(Color.hooprBorder, lineWidth: max(1, size * 0.02))
            )
            .overlay(
                Image(systemName: iconKey)
                    // Fixed rather than `hooprFont`: the glyph is locked inside
                    // a frame that can't grow, which is the case `Typography`
                    // names as keeping `.font(.system(size:))`. The crest is
                    // never the only carrier of meaning — a name always sits
                    // beside it — so it doesn't need to scale with the text.
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(Color.hooprOnCrest)
            )
            .frame(width: size, height: size)
            // Decorative: every crest in the app is rendered next to the squad
            // name, so announcing it separately would read the squad twice.
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 16) {
        ForEach(Squad.colorKeys, id: \.self) { key in
            HStack(spacing: 12) {
                SquadCrest(iconKey: Squad.defaultIconKey, colorKey: key, size: SquadCrest.Size.hero)
                SquadCrest(iconKey: "flame.fill", colorKey: key, size: SquadCrest.Size.card)
                SquadCrest(iconKey: "bolt.fill", colorKey: key, size: SquadCrest.Size.row)
                SquadCrest(iconKey: "crown.fill", colorKey: key, size: SquadCrest.Size.pool)
                SquadCrest(iconKey: "star.fill", colorKey: key, size: SquadCrest.Size.inline)
            }
        }
    }
    .padding()
    .background(Color.hooprBackground)
}
