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
    static let hooprOrange = Color.hoopr(
        light: UIColor(red: 255 / 255, green: 126 / 255, blue: 0 / 255, alpha: 1),
        dark: UIColor(red: 255 / 255, green: 145 / 255, blue: 38 / 255, alpha: 1)
    )

    static let hooprDarkOrange = Color.hoopr(
        light: UIColor(red: 230 / 255, green: 111 / 255, blue: 0 / 255, alpha: 1),
        dark: UIColor(red: 255 / 255, green: 126 / 255, blue: 0 / 255, alpha: 1)
    )

    /// Errors and destructive actions. The light-mode red fails contrast on a
    /// dark background, so dark mode uses a lighter, less saturated one.
    static let hooprRed = Color.hoopr(
        light: UIColor(red: 185 / 255, green: 14 / 255, blue: 10 / 255, alpha: 1),
        dark: UIColor(red: 255 / 255, green: 105 / 255, blue: 97 / 255, alpha: 1)
    )

    /// Content drawn *on top of* `hooprOrange` — a button's label, a selected
    /// chip's text. Fixed white in both appearances, because the brand orange
    /// it sits on doesn't invert.
    static let hooprOnBrand = Color.white

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
