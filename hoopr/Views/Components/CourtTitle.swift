import SwiftUI

/// A court's name as a heading: the court glyph, then the name, which wraps and
/// never truncates.
///
/// Shared by Home's band and the map's court card because both set the same
/// name at the same size in the same width, and the rule below has to hold for
/// both or neither.
///
/// **The glyph is shed at every accessibility text size.** It is ornament
/// beside the name, and at those sizes the name needs the width more. The
/// threshold is measured, and the first version of it was measured wrong: the
/// court glyph is a landscape symbol that draws wider than its font size, and
/// the room below was first computed from the font size.
///
/// With the real width of the glyph this was set against (`sportscourt.fill`,
/// 1.56× its font size — 63.7pt at `.accessibility3`; the basketball court
/// that replaced it, `Image.court`, is narrower at 1.36×, so every margin below
/// only grew), at `.accessibility3`:
///
/// - **Wrapping (Home):** the widest word in the dataset, "Pearsontown", is
///   287pt against 290pt beside the glyph — a 3pt margin, and it breaks
///   mid-word one size up. Without the glyph it has 362pt.
/// - **One line (the map's card):** "East End" is 188pt against 186pt beside
///   the glyph and the card's controls, so it was cut to "East E…" on the
///   device. Without the glyph it has 258pt, and at `.accessibility1` the full
///   "East End Park" fits.
///
/// So the rule is the plain one — the revamp's own *drop the ornament*, and
/// `MAP_LAYER.md`'s *badges are shed, the name is not* — and
/// `CourtCardLayoutTests` measures it with the symbol's drawn width.
struct CourtTitle: View {
    let name: String
    /// Marks the name as a heading for VoiceOver's rotor. The map card is a
    /// place page and wants it; Home's band is one tappable answer and doesn't.
    var isHeader: Bool = false

    /// How a name that doesn't fit is handled.
    ///
    /// - `wraps` — Home's band, where the run's court is the screen's answer
    ///   and is set in full, over as many lines as it takes.
    /// - `fitsOneLine` — the map's court card, which keeps one compact header
    ///   row: the name sheds "Park", then its court number, then is cut
    ///   (`CourtName`). The user's call, 2026-09-22: the full name is one tap
    ///   away, and it is what the Runs tab shows.
    enum Fit { case wraps, fitsOneLine }
    var fit: Fit = .wraps

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Whether the glyph has room beside the name at `size` — not at any
    /// accessibility size. See above.
    nonisolated static func showsGlyph(at size: DynamicTypeSize) -> Bool {
        !size.isAccessibilitySize
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            if Self.showsGlyph(at: dynamicTypeSize) {
                Image.court
                    .hooprType(.headline)
                    .foregroundStyle(Color.hooprBrandAccent)
                    .accessibilityHidden(true)
            }

            Group {
                switch fit {
                case .wraps:
                    Text(name)
                        .lineLimit(HomeHeroMetrics.courtNameLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                case .fitsOneLine:
                    CourtName(name: name)
                }
            }
            .hooprType(.title)
            .foregroundStyle(Color.hooprPrimaryText)
            .accessibilityAddTraits(isHeader ? .isHeader : [])
        }
    }
}
