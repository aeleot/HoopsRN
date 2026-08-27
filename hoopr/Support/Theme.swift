import SwiftUI
import UIKit

/// The app's colour palette, defined once and resolved per appearance.
///
/// Every colour here is a *role* — "the text you read first", "the surface a
/// card sits on" — rather than a shade, because the shade differs between light
/// and dark mode and the role doesn't. Views name the role; this file owns what
/// it looks like. That's the whole mechanism keeping the app appearance-aware:
/// there are no literal colours left in `Views/`, so there is nowhere for a
/// light-only value to hide.
///
/// Resolution goes through `UIColor`'s dynamic provider rather than SwiftUI's
/// `Color`, because a `UIColor` closure is re-evaluated whenever the trait
/// collection changes — including inside `UIKit`-backed surfaces like the map
/// annotations in `MapView`, which a SwiftUI-only `@Environment(\.colorScheme)`
/// switch would never reach.
extension Color {

    // MARK: - Brand

    /// The action colour. Slightly lifted in dark mode: the light-mode orange
    /// is tuned against white and reads muddy on a near-black surface.
    ///
    /// **Retuned on 2026-08-22** to `#EE6730` — a deliberately redder hue
    /// (17.4°, down from 29.6°) for a warmer, more saturated brand mark. The
    /// dark-mode lift keeps the same per-channel ratio the previous tuning
    /// used (green ×1.102, blue ×1.612, red unchanged), so it stays "the same
    /// colour, lifted" rather than a separately-eyeballed shade. `hooprOnBrand`
    /// still clears AA comfortably against both (6.61:1 / 7.15:1), well above
    /// the 4.5:1 floor `ThemeContrastTests` pins, though the redder, slightly
    /// darker orange narrows that margin from the previous tuning's 9.17:1 /
    /// 10.24:1. **Does not touch** the separate AA failure tracked in
    /// `GAPS.md` — `hooprOrange` as a *foreground* still fails in light mode,
    /// and stays failing here; that needs a second, deliberately different,
    /// readable role, not a retune of this one.
    static let hooprOrange = Color.hoopr(
        light: UIColor(red: 238 / 255, green: 103 / 255, blue: 48 / 255, alpha: 1),
        dark: UIColor(red: 238 / 255, green: 114 / 255, blue: 77 / 255, alpha: 1)
    )

    static let hooprDarkOrange = Color.hoopr(
        light: UIColor(red: 214 / 255, green: 93 / 255, blue: 43 / 255, alpha: 1),
        dark: UIColor(red: 214 / 255, green: 103 / 255, blue: 69 / 255, alpha: 1)
    )

    /// Errors and destructive actions. The light-mode red fails contrast on a
    /// dark background, so dark mode uses a lighter, less saturated one.
    static let hooprRed = Color.hoopr(
        light: UIColor(red: 185 / 255, green: 14 / 255, blue: 10 / 255, alpha: 1),
        dark: UIColor(red: 255 / 255, green: 105 / 255, blue: 97 / 255, alpha: 1)
    )

    /// Content drawn *on top of* `hooprOrange` — a button's label, a selected
    /// chip's text, the map pin's glyph.
    ///
    /// **Black, not white, and this is the one value here you must not flip on
    /// taste.** The brand orange is a light colour in both appearances, so a
    /// white label on it fails AA badly regardless of exactly how it's tuned —
    /// 2.55:1 / 2.25:1 against the original fully-saturated orange, and *worse*
    /// (2.29:1 / 2.05:1) against the softened one below, because desaturating
    /// toward white moves the fill's own luminance closer to white's. Black
    /// clears 9.17:1 / 10.24:1 on `hooprOrange`, and 7.42:1 / 9.17:1 on
    /// `hooprDarkOrange` behind the selected map pin.
    ///
    /// Fixed rather than dynamic, because the ground it sits on doesn't invert:
    /// orange stays light in dark mode, so the label that reads on it stays
    /// dark. Darkening the orange until white passed would take it to roughly
    /// `rgb(187, 93, 0)` — a brown, not a brand.
    ///
    /// `ThemeContrastTests` fails if this pairing ever slips back under AA. It
    /// shipped as white once and nothing caught it.
    static let hooprOnBrand = Color.black

    /// Content drawn *on top of* a solid `hooprRed` fill — today only the
    /// inbox badge's count.
    ///
    /// The one role here that genuinely has to invert. `hooprRed` is deep in
    /// light mode and deliberately lightened in dark mode (so it holds contrast
    /// against a near-black page), which flips which label reads on it: white
    /// is 6.71:1 light but 2.82:1 dark, black is 3.13:1 light but 7.45:1 dark.
    /// No fixed colour clears AA on both, so this resolves per appearance —
    /// 6.71:1 and 7.45:1.
    ///
    /// Distinct from `hooprOnBrand` on purpose. The badge borrowed that role
    /// while it was white, which happened to pass in light mode and hid the
    /// dark-mode failure behind a name that promised something else.
    static let hooprOnRed = Color.hoopr(light: .white, dark: UIColor(white: 0, alpha: 1))

    // MARK: - Surfaces

    /// The page behind everything. Pure black in dark mode, matching
    /// `systemBackground`, so cards have something to lift off.
    static let hooprBackground = Color.hoopr(
        light: .white,
        dark: UIColor(white: 0, alpha: 1)
    )

    /// A card or sheet raised above `hooprBackground`. Identical to the
    /// background in light mode — the app separates cards with a border and a
    /// shadow there, not a fill — and lifted in dark mode, where a shadow
    /// against black conveys nothing.
    static let hooprSurface = Color.hoopr(
        light: .white,
        dark: UIColor(red: 28 / 255, green: 28 / 255, blue: 30 / 255, alpha: 1)
    )

    /// A filled but unemphasised region: text-field backgrounds, unselected
    /// chips, the empty half of a capacity bar.
    static let hooprFill = Color.hoopr(
        light: UIColor(white: 245 / 255, alpha: 1),
        dark: UIColor(red: 44 / 255, green: 44 / 255, blue: 46 / 255, alpha: 1)
    )

    /// Hairlines and outlines.
    static let hooprBorder = Color.hoopr(
        light: UIColor(white: 232 / 255, alpha: 1),
        dark: UIColor(red: 58 / 255, green: 58 / 255, blue: 60 / 255, alpha: 1)
    )

    /// Card and sheet shadows, at the depth the call site asks for.
    ///
    /// Takes the light-mode opacity because that's what the design was drawn
    /// against, and deepens it in dark mode: a 6%-black shadow that reads as a
    /// soft lift on white is invisible on a near-black background. Separation
    /// in dark mode comes mostly from `hooprSurface` sitting above
    /// `hooprBackground` — this keeps the halo from disappearing entirely.
    static func hooprShadow(opacity: Double) -> Color {
        hoopr(
            light: UIColor(white: 0, alpha: opacity),
            dark: UIColor(white: 0, alpha: min(1, opacity * 4))
        )
    }

    // MARK: - Text

    /// The text you read first — titles, values, primary labels.
    static let hooprPrimaryText = Color.hoopr(
        light: .black,
        dark: UIColor(white: 242 / 255, alpha: 1)
    )

    /// Supporting text: captions, metadata, inactive labels. The dark-mode
    /// value is lighter than a straight inversion of the light-mode grey,
    /// which would land at roughly 2:1 against black.
    static let hooprSecondaryText = Color.hoopr(
        light: UIColor(white: 102 / 255, alpha: 1),
        dark: UIColor(white: 160 / 255, alpha: 1)
    )

    // MARK: - Resolution

    /// Wraps a light/dark pair in a `UIColor` that resolves against whatever
    /// trait collection asks for it.
    private static func hoopr(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
