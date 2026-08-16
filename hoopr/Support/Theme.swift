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
///
/// ## The palette
///
/// Five source colours — jet `#2D3142`, slate `#4F5D75`, silver `#BCC0C8`,
/// white, and coral `#EF8354` — with the rest derived from them. **Light is the
/// flagship**: light-mode separation comes from a jet-tinted neutral ramp plus
/// border and shadow, the way Material's light theme works. Dark mode is built
/// the way Material's dark theme is: jet at 0dp with semi-transparent white
/// overlays standing in for elevation, not hand-picked greys.
///
/// ## Two constraints worth knowing before editing anything here
///
/// **Coral cannot be darkened.** A filled coral control needs a label clearing
/// 4.5:1. Coral takes a *jet* label while it stays light (4.94:1 at its given
/// lightness) or a *white* label once it drops below ~44% lightness (4.55:1) —
/// but between roughly 46% and 58% lightness **neither passes**. The palette's
/// coral sits just above that band, so "deepen it slightly" walks straight into
/// a control whose label fails whichever colour it takes.
///
/// **Coral has an elevation ceiling in dark mode.** As *text* it is 4.94:1 on
/// the 0dp surface but 3.37:1 at 8dp and 2.97:1 at 24dp, because the elevation
/// overlay lightens the ground beneath it. Coral text belongs on backgrounds
/// and low cards; anywhere higher it appears as a *fill* carrying a jet label,
/// which the overlay never touches.
extension Color {

    // MARK: - Brand

    /// The action colour: coral. Identical in both appearances — unlike the
    /// orange it replaced, it needs no dark-mode lift, because it already
    /// clears AA on jet (4.94:1) and lifting it would only hurt the jet label
    /// that sits on top of it.
    ///
    /// Reserved for *things you can tap that advance you*. Selection, focus and
    /// decoration go to `hooprSecondary`; the moment coral also means "selected"
    /// it stops meaning anything.
    static let hooprBrand = Color.hoopr(
        light: UIColor(red: 239 / 255, green: 131 / 255, blue: 84 / 255, alpha: 1),
        dark: UIColor(red: 239 / 255, green: 131 / 255, blue: 84 / 255, alpha: 1)
    )

    /// A deeper coral for the far end of the profile header's gradient and for
    /// selected map pins.
    ///
    /// Stops at 4.63:1 against `hooprOnBrand` rather than going darker: the
    /// header carries small italic text across the whole gradient, so every
    /// stop has to clear AA, not just the light end.
    static let hooprBrandDeep = Color.hoopr(
        light: UIColor(red: 236 / 255, green: 124 / 255, blue: 74 / 255, alpha: 1),
        dark: UIColor(red: 236 / 255, green: 124 / 255, blue: 74 / 255, alpha: 1)
    )

    /// Coral where it has to be *read* rather than filled — inline links, a
    /// headline accent, a small glyph on a pale surface.
    ///
    /// Coral itself is 2.61:1 on white and unusable as text. This is the same
    /// hue (18°) dropped to 42% lightness, giving 4.99:1.
    ///
    /// The dark value is coral *lifted* to 72% lightness rather than left at
    /// its base: plain coral is 4.19:1 on a 1dp card, so coral text on any
    /// raised surface would sit under AA. Lifting it clears 5.34:1 at 1dp and
    /// 4.67:1 at 4dp — the elevation ceiling in this file's header note is what
    /// this value exists to solve.
    ///
    /// Never use it for body copy — Material reserves coloured text for
    /// headlines, buttons and links.
    static let hooprBrandText = Color.hoopr(
        light: UIColor(red: 191 / 255, green: 74 / 255, blue: 24 / 255, alpha: 1),
        dark: UIColor(red: 243 / 255, green: 160 / 255, blue: 124 / 255, alpha: 1)
    )

    /// Content drawn *on top of* `hooprBrand` — a button's label, a selected
    /// chip's text, the glyph in a map pin.
    ///
    /// Jet, not white. White on coral is 2.61:1 and fails AA outright; jet is
    /// 4.94:1. Fixed across both appearances, because the coral underneath it
    /// doesn't invert either.
    static let hooprOnBrand = Color.hoopr(
        light: UIColor(red: 45 / 255, green: 49 / 255, blue: 66 / 255, alpha: 1),
        dark: UIColor(red: 45 / 255, green: 49 / 255, blue: 66 / 255, alpha: 1)
    )

    // MARK: - Secondary

    /// The accent that absorbs everything coral shouldn't be doing: focus
    /// rings, selection controls, sliders, selected chips, decorative glyphs,
    /// and the waitlist state.
    ///
    /// Slate is deliberately quiet — it recedes so coral stays the loudest
    /// thing on screen. The dark value is slate lightened 45% toward white;
    /// raw slate is 1.94:1 on jet and invisible there.
    static let hooprSecondary = Color.hoopr(
        light: UIColor(red: 79 / 255, green: 93 / 255, blue: 117 / 255, alpha: 1),
        dark: UIColor(red: 158 / 255, green: 166 / 255, blue: 179 / 255, alpha: 1)
    )

    /// Content drawn on top of a filled `hooprSecondary` surface. White in
    /// light mode (6.66:1 on slate); jet in dark, where the secondary is a pale
    /// slate.
    static let hooprOnSecondary = Color.hoopr(
        light: .white,
        dark: UIColor(red: 45 / 255, green: 49 / 255, blue: 66 / 255, alpha: 1)
    )

    // MARK: - Status

    /// A run with room — roster under 70%. Reads as "go" before the text does.
    static let hooprOpen = Color.hoopr(
        light: UIColor(red: 47 / 255, green: 125 / 255, blue: 91 / 255, alpha: 1),
        dark: UIColor(red: 127 / 255, green: 212 / 255, blue: 168 / 255, alpha: 1)
    )

    /// A run filling up — roster at 70% or more but not yet full. The highest
    /// intent moment in the app, so it gets its own colour rather than sharing
    /// coral's.
    ///
    /// Sits at hue 46°, not the 36° first tried: 36° is only 18° off coral and
    /// lands on the *orange* axis, which at the lightness AA forces reads as
    /// brown. Pushing to 46° with high saturation keeps it gold. Light mode
    /// can't go brighter — yellow's own luminance is so high that a genuinely
    /// bright one measures ~1.4:1 on white, so hue is the only lever available.
    static let hooprFilling = Color.hoopr(
        light: UIColor(red: 144 / 255, green: 111 / 255, blue: 4 / 255, alpha: 1),
        dark: UIColor(red: 230 / 255, green: 208 / 255, blue: 137 / 255, alpha: 1)
    )

    /// Errors and destructive actions.
    ///
    /// Re-tuned from the previous `#B90E0A`, which was far more saturated than
    /// anything else in this palette and read as a foreign element. Note it now
    /// sits near coral in hue, so a destructive control is distinguished by
    /// *shape* — tinted text on `hooprFill`, never a filled capsule — rather
    /// than by colour alone.
    static let hooprRed = Color.hoopr(
        light: UIColor(red: 179 / 255, green: 64 / 255, blue: 60 / 255, alpha: 1),
        dark: UIColor(red: 232 / 255, green: 144 / 255, blue: 138 / 255, alpha: 1)
    )

    // There is deliberately no `hooprOnError`. Nothing in the app fills a
    // surface with the error colour — `ErrorBanner` tints its own ground at 8%
    // and draws red text on it, and a destructive button is red text on
    // `hooprFill`. An "on error" role would be a token with no call site, and
    // the pairing it claimed to protect would never be rendered.

    // MARK: - Surfaces

    /// The page behind everything.
    ///
    /// Light mode comes *off* pure white — background and surface were both
    /// `#FFFFFF` before, a 1.00:1 ratio, so every card depended entirely on its
    /// border and a 6% shadow. Dark mode is jet at 0dp.
    static let hooprBackground = Color.hoopr(
        light: UIColor(red: 246 / 255, green: 247 / 255, blue: 249 / 255, alpha: 1),
        dark: UIColor(red: 45 / 255, green: 49 / 255, blue: 66 / 255, alpha: 1)
    )

    /// A card or sheet raised above `hooprBackground`. White in light mode —
    /// Material's baseline for cards — and jet plus a 5% white overlay in dark,
    /// which is the 1dp rung of the elevation ramp rather than a picked grey.
    static let hooprSurface = Color.hoopr(
        light: .white,
        dark: UIColor(red: 56 / 255, green: 59 / 255, blue: 75 / 255, alpha: 1)
    )

    /// A filled but unemphasised region: text-field backgrounds, unselected
    /// chips, the empty half of a capacity bar.
    ///
    /// In dark mode this sits *below* `hooprSurface` rather than above it. A
    /// field is recessed into its card, not raised off it, so an elevation rung
    /// was the wrong model — and the practical effect matters: every rung above
    /// the surface lightens the ground, and `hooprRed` on the 4dp rung measures
    /// 4.05:1, under AA, on the destructive button that is drawn exactly there.
    /// Sinking the fill instead puts it at 5.07:1.
    static let hooprFill = Color.hoopr(
        light: UIColor(red: 237 / 255, green: 238 / 255, blue: 242 / 255, alpha: 1),
        dark: UIColor(red: 49 / 255, green: 53 / 255, blue: 72 / 255, alpha: 1)
    )

    /// Hairlines and outlines. Stronger than the old `#E8E8E8`: light mode
    /// leans harder on borders now that white cards sit on a near-white ground.
    static let hooprBorder = Color.hoopr(
        light: UIColor(red: 222 / 255, green: 224 / 255, blue: 231 / 255, alpha: 1),
        dark: UIColor(red: 74 / 255, green: 78 / 255, blue: 92 / 255, alpha: 1)
    )

    /// Card and sheet shadows, at the depth the call site asks for.
    ///
    /// Takes the light-mode opacity because that's what the design was drawn
    /// against, and deepens it in dark mode: a 6%-black shadow that reads as a
    /// soft lift on white is invisible on a near-black background. Separation
    /// in dark mode comes mostly from `hooprSurface` sitting above
    /// `hooprBackground` — this keeps the halo from disappearing entirely.
    ///
    /// The shadow is jet-tinted rather than pure black, so it warms into the
    /// palette instead of greying it out.
    static func hooprShadow(opacity: Double) -> Color {
        hoopr(
            light: UIColor(red: 45 / 255, green: 49 / 255, blue: 66 / 255, alpha: opacity),
            dark: UIColor(white: 0, alpha: min(1, opacity * 4))
        )
    }

    // MARK: - Text

    /// The text you read first — titles, values, primary labels.
    ///
    /// Jet rather than pure black: 12.89:1 on white is still comfortably AAA,
    /// and it ties body copy to the brand's hue instead of sitting outside the
    /// palette.
    static let hooprPrimaryText = Color.hoopr(
        light: UIColor(red: 45 / 255, green: 49 / 255, blue: 66 / 255, alpha: 1),
        dark: .white
    )

    /// Supporting text: captions, metadata, inactive labels. Slate on light
    /// (6.66:1), silver on dark (7.06:1) — both palette colours doing the same
    /// job on their own ground.
    static let hooprSecondaryText = Color.hoopr(
        light: UIColor(red: 79 / 255, green: 93 / 255, blue: 117 / 255, alpha: 1),
        dark: UIColor(red: 188 / 255, green: 192 / 255, blue: 200 / 255, alpha: 1)
    )

    // MARK: - States

    /// The opacity a disabled control's content is drawn at.
    ///
    /// One value, from Material's text-legibility guidance, replacing the
    /// scattered `0.4` and `0.5` literals that produced a different disabled
    /// look on almost every screen.
    static let hooprDisabledOpacity: Double = 0.38

    // MARK: - Resolution

    /// Wraps a light/dark pair in a `UIColor` that resolves against whatever
    /// trait collection asks for it.
    private static func hoopr(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
