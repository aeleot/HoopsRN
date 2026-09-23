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

    /// The brand **fill** — buttons, selected chips and pills, the tint on
    /// active glass, and the low-opacity wash behind a mark. Slightly lifted
    /// in dark mode: the light-mode orange is tuned against white and reads
    /// muddy on a near-black surface.
    ///
    /// **A fill, never a mark.** Drawn as a *foreground* on a light ground it
    /// measures 3.17:1 on white, 2.91:1 on `hooprFill` and 2.78:1 on its own
    /// 12% wash — all under the 4.5:1 text floor — so text, glyphs, strokes,
    /// spinners and control tints use `hooprBrandAccent` instead, which is
    /// this hue deepened until it reads. `hooprOnBrand` on this fill is
    /// 6.62:1 in light and 7.15:1 in dark.
    ///
    /// **Retuned on 2026-08-22** to `#EE6730` — a deliberately redder hue
    /// (17.4°, down from 29.6°) for a warmer, more saturated brand mark. The
    /// dark-mode lift keeps the same per-channel ratio the previous tuning
    /// used (green ×1.102, blue ×1.612, red unchanged), so it stays "the same
    /// colour, lifted" rather than a separately-eyeballed shade.
    static let hooprOrange = Color.hoopr(light: brandOrangeLight, dark: brandOrangeDark)

    private static let brandOrangeLight = UIColor(red: 238 / 255, green: 103 / 255, blue: 48 / 255, alpha: 1)
    private static let brandOrangeDark = UIColor(red: 238 / 255, green: 114 / 255, blue: 77 / 255, alpha: 1)

    /// The brand **mark** — orange drawn as something you *read*: text,
    /// glyphs, focus rings and selection strokes, the capacity bar, spinner /
    /// slider / date-picker tints, and the tab bar's selected item.
    ///
    /// **Light is `#B8400F`:** `hooprOrange`'s own hue (17.4°) and saturation,
    /// with lightness lowered until it clears 4.5:1 on every ground a mark is
    /// actually drawn on — 5.56:1 on white, 5.10 on `hooprFill`, 4.87 and 4.76
    /// on the 12% and 14% orange washes behind badges and icon tiles, and 4.70
    /// on `hooprHoverFill`. It is the *lightest* value that clears with
    /// headroom, on purpose: the floor pins the lightness, so keeping the
    /// hue and saturation is what stops the app reading as two unrelated
    /// oranges. (The earlier suggestion of `#B4491E` also clears, but is
    /// visibly duller.)
    ///
    /// **Dark is `hooprOrange`'s own dark value.** It already clears 4.5:1 on
    /// every dark ground — 7.15 on the page, 5.79 on a card, 4.74 on a fill —
    /// so there is nothing to deepen there and the two roles converge.
    ///
    /// **Never a fill.** Black on it is 3.78:1, so it can't carry the
    /// `hooprOnBrand` labels the filled orange does; a mark and a surface are
    /// different jobs, which is why this is a role and not a retune of
    /// `hooprOrange`. `ThemeContrastTests` asserts every ground above.
    static let hooprBrandAccent = Color.hoopr(
        light: UIColor(red: 184 / 255, green: 64 / 255, blue: 15 / 255, alpha: 1),
        dark: brandOrangeDark
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
    /// (2.29:1 / 2.05:1) against the softened one, because desaturating
    /// toward white moves the fill's own luminance closer to white's. Against
    /// today's `#EE6730` black clears 6.62:1 in light and 7.15:1 in dark, and
    /// 5.46:1 / 5.89:1 on `hooprDarkOrange`. (Earlier revisions of this comment
    /// quoted 9.17 / 10.24 and 7.42 / 9.17, which were the figures for a
    /// lighter orange that no longer exists.)
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

    // MARK: - Squad crests

    /// Content drawn *on top of* a squad's crest fill — the SF Symbol at the
    /// centre of the disc.
    ///
    /// **Black, and a role of its own rather than a reuse of `hooprOnBrand`.**
    /// The two happen to resolve to the same value today and are answering
    /// different questions: `hooprOnBrand` reads on the one brand orange, this
    /// one reads on eight palette fills chosen independently of it. Borrowing
    /// the brand role is exactly the mistake the inbox badge made before
    /// `hooprOnRed` existed — it passed by luck, under a name that promised
    /// something else, and hid a failure until someone measured it.
    ///
    /// Fixed rather than dynamic for the same reason `hooprOnBrand` is: every
    /// crest fill below is a *light* colour in both appearances, so the glyph
    /// that reads on it stays dark. `ThemeContrastTests` measures all eight
    /// against this at the 4.5:1 text floor — stricter than the 3:1 a glyph
    /// needs, so a squad initial or a record could be dropped into the disc
    /// later without re-litigating the palette.
    static let hooprOnCrest = Color.black

    /// The fill behind a squad's crest glyph, for a `Squad.colorKey`.
    ///
    /// Keys, not colours, are what `squads` stores — a stored hex would bypass
    /// this table and with it the whole appearance-aware mechanism. The rules
    /// allowlist the same eight keys, and `FirestoreRulesParityTests` fails if
    /// the two lists drift.
    ///
    /// An unrecognised key resolves to the default rather than to a neutral
    /// fill: `hooprFill` is dark in dark mode, and a black glyph on it would be
    /// the one unreadable crest in the app. A drifted document renders as the
    /// wrong colour, which is visible and harmless; it never renders as
    /// nothing.
    static func hooprSquad(_ colorKey: String) -> Color {
        squadPalette[colorKey] ?? squadPalette[Squad.defaultColorKey] ?? hooprOrange
    }

    /// The eight crest fills, each light enough in both appearances that
    /// `hooprOnCrest` clears AA on it — measured, not eyeballed; see
    /// `ThemeContrastTests.testEverySquadCrestFillCarriesItsGlyph`.
    ///
    /// Dark-mode values are the light ones lifted 12% toward white, the same
    /// "same colour, lifted" move `hooprOrange` makes: a fill tuned against
    /// white reads muddy on a near-black page.
    private static let squadPalette: [String: Color] = [
        "orange": hoopr(light: rgb(242, 121, 47),  dark: rgb(244, 137, 72)),
        "red":    hoopr(light: rgb(242, 85, 75),   dark: rgb(244, 105, 97)),
        "pink":   hoopr(light: rgb(242, 114, 168), dark: rgb(244, 131, 178)),
        "purple": hoopr(light: rgb(185, 140, 240), dark: rgb(193, 154, 242)),
        "blue":   hoopr(light: rgb(95, 170, 245),  dark: rgb(114, 180, 246)),
        "teal":   hoopr(light: rgb(69, 199, 192),  dark: rgb(91, 206, 200)),
        "green":  hoopr(light: rgb(99, 201, 122),  dark: rgb(118, 207, 138)),
        "gold":   hoopr(light: rgb(240, 194, 48),  dark: rgb(242, 201, 73)),
    ]

    private static func rgb(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> UIColor {
        UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
    }

    // MARK: - Form guide

    /// A win in `FormGuide`'s row of five dots. Green for a win and red for a
    /// loss, at the user's direction (2026-09-22), replacing the orange "W"
    /// pill.
    ///
    /// **Each played dot clears 3:1**, the floor WCAG 1.4.11 sets for a
    /// graphic you need to read, on every ground the guide is drawn on: the
    /// hero band and a card. Win is 3.15:1 on the light band, which sets how
    /// light this green can go. Its dark value is the same hue lifted, as
    /// `hooprOrange`'s is.
    ///
    /// **The colours can't carry win and loss alone, and that was measured.**
    /// For a red-green colour-blind reader, two fills differ only in how light
    /// they are, and WCAG counts that as a second cue at 3:1 between them. With
    /// both dots held to 3:1 against the band, the widest gap reachable is
    /// 1.95:1 in light and 2.25:1 in dark. So the record numeral says how many
    /// of each, VoiceOver reads the order, and with iOS's *Differentiate
    /// Without Color* setting on, each played dot carries a ✓ or ✕.
    /// `ThemeContrastTests` asserts all of it.
    static let hooprFormWin = Color.hoopr(
        light: UIColor(red: 46 / 255, green: 158 / 255, blue: 74 / 255, alpha: 1),
        dark: UIColor(red: 74 / 255, green: 222 / 255, blue: 128 / 255, alpha: 1)
    )

    /// A loss in `FormGuide`. A role of its own rather than `hooprRed`, which
    /// is for errors: a loss is a result, not a failure. Light mode shares the
    /// error red's value. Dark mode is deeper than the error red's `#FF6961`,
    /// which is only 1.62:1 away from the win green in lightness. This is
    /// 2.25:1, the widest gap that keeps both dots at 3:1 on the band.
    static let hooprFormLoss = Color.hoopr(
        light: UIColor(red: 185 / 255, green: 14 / 255, blue: 10 / 255, alpha: 1),
        dark: UIColor(red: 229 / 255, green: 72 / 255, blue: 77 / 255, alpha: 1)
    )

    /// A slot not yet played. The squad has fewer than five confirmed results.
    ///
    /// **Deliberately quieter than a played dot, at about 2:1 on the band
    /// rather than 3:1.** It is a placeholder, not a result. The record
    /// numeral beside it already says how many games were played, and a grey
    /// as heavy as the win and loss dots would read as a third kind of
    /// result. `ThemeContrastTests` holds it visible, and below both played
    /// dots.
    static let hooprFormUnplayed = Color.hoopr(
        light: UIColor(red: 174 / 255, green: 174 / 255, blue: 178 / 255, alpha: 1),
        dark: UIColor(red: 84 / 255, green: 84 / 255, blue: 86 / 255, alpha: 1)
    )

    /// The ✓ or ✕ drawn on a played dot when *Differentiate Without Color* is
    /// on. White in light mode, black in dark: the dark dots are light
    /// colours, so the label flips, as `hooprOnRed`'s does. It is at least
    /// 3.44:1 on either dot in either appearance.
    static let hooprOnFormResult = Color.hoopr(light: .white, dark: UIColor(white: 0, alpha: 1))

    // MARK: - Heat

    /// The "how busy is this court **today**" ramp: five fills, each paired
    /// with the label that reads on it.
    ///
    /// **One table, so a fill and its label can't be retuned apart.** The map
    /// pin's count is drawn on these fills, and it used to borrow
    /// `hooprOnBrand` (black) for every one of them — which is 6.62:1 on the
    /// quietest stop and only **4.01:1 and 3.43:1** on the two deepest, under
    /// the 4.5:1 a 12pt bold label needs, on exactly the courts where the
    /// number matters most. White clears both (5.24 / 6.12). The crossover is
    /// tier 2, where black is 4.74 and white 4.43; `ThemeContrastTests`
    /// asserts every tier so a retune that moves it fails loudly.
    ///
    /// **Fixed rather than routed through the light/dark provider**, on
    /// purpose and unchanged from when this lived in `CourtHeat`: it is a data
    /// scale read against the map's own muted basemap in both appearances, not
    /// app chrome that should invert. Stop 0 therefore hardcodes
    /// `hooprOrange`'s **light** value rather than referencing the role — if
    /// the brand orange is retuned this stop does not follow, and
    /// `CourtHeatTests` pins the hex to catch the two drifting apart.
    ///
    /// The three middle stops are a straight linear RGB interpolation between
    /// the ends, which lands them on roughly even perceived-brightness steps;
    /// keep that if you retune, because uneven steps read as "these two mean
    /// the same thing" even when the counts differ. The busiest stop was
    /// rederived on 2026-08-22 at the same ratio to stop 0 the old ceiling
    /// held to the old stop 0 (R ×0.80, G ×0.31, B ×0.33).
    private static let heatStops: [(fill: Color, label: Color)] = [
        (Color(red: 0xEE / 255, green: 0x67 / 255, blue: 0x30 / 255), .black), // EE6730 — hooprOrange's light value, nothing today
        (Color(red: 0xE2 / 255, green: 0x55 / 255, blue: 0x28 / 255), .black), // E25528
        (Color(red: 0xD7 / 255, green: 0x44 / 255, blue: 0x20 / 255), .black), // D74420
        (Color(red: 0xCB / 255, green: 0x32 / 255, blue: 0x18 / 255), .white), // CB3218
        (Color(red: 0xBF / 255, green: 0x20 / 255, blue: 0x10 / 255), .white), // BF2010 — deep red, busiest tier
    ]

    /// The top tier a court can reach; everything at or above it reads the
    /// same. `CourtHeat` exposes it as `maxTier`.
    static let hooprHeatMaxTier = heatStops.count - 1

    /// The fill for a heat tier. Out-of-range tiers clamp rather than trap —
    /// a lookup table should never crash on a bad index.
    static func hooprHeat(tier: Int) -> Color {
        heatStops[clampedHeatTier(tier)].fill
    }

    /// Content drawn *on top of* `hooprHeat(tier:)` — the pin's count. Its own
    /// role rather than a reuse of `hooprOnBrand`, for the reason above.
    static func hooprOnHeat(tier: Int) -> Color {
        heatStops[clampedHeatTier(tier)].label
    }

    private static func clampedHeatTier(_ tier: Int) -> Int {
        min(max(tier, 0), heatStops.count - 1)
    }

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

    /// A surface raised one level above `hooprSurface` — a card sitting inside
    /// a sheet, a popover, anything that floats over cards rather than over
    /// the page.
    ///
    /// **The two appearances carry the lift differently, and that is the
    /// design, not an oversight.** Dark mode carries it in the fill: `#242426`
    /// is one visible step above a card (1.10:1) and one below a field
    /// (`hooprFill`, 1.11:1), so the ladder reads page → card → raised →
    /// field. Light mode cannot: nothing is lighter than white, so a raised
    /// surface there *is* white and the lift comes from `hooprShadow` at a
    /// deeper opacity plus `hooprSeparatorStrong`. The role exists so a call
    /// site says "raised" once and this file decides what that looks like —
    /// which is also what lets the light value change later without touching
    /// a view.
    ///
    /// **Whether light mode's page ground moves off pure white is a design
    /// decision this role does not make.** `hooprBackground` and
    /// `hooprSurface` stay identical white in light — that is a documented,
    /// test-pinned choice (`testCardSeparatesFromBackgroundInDarkMode`) — and
    /// moving it re-tunes `hooprFill` and `hooprBorder` on every screen. It
    /// belongs to the redesign brief, not to a token phase.
    static let hooprElevatedSurface = Color.hoopr(
        light: .white,
        dark: UIColor(red: 36 / 255, green: 36 / 255, blue: 38 / 255, alpha: 1)
    )

    /// The ground a screen's hero stands on — the full-bleed band at the top
    /// of Home, Runs and Seasons, closed by a `hooprSeparatorStrong` baseline.
    ///
    /// **It is the thing that replaces the card.** The redesign stops drawing a
    /// box around every section; what used to say "these belong together" with
    /// four edges and a shadow now says it with one region and one line. So
    /// this role is a *text ground*, which no filled region in the app was
    /// before — every pairing drawn on it is asserted in `ThemeContrastTests`.
    ///
    /// It resolves to values the palette already proves rather than new ones:
    /// `hooprFill` in light (nothing is lighter than the white page, so the
    /// band reads as a faint region and the baseline carries the boundary),
    /// `hooprElevatedSurface` in dark (where a fill *can* carry lift, and the
    /// band sits one step above a card). It is named for the job rather than
    /// spelled as either of those at the call site, because a view saying
    /// "field ground" where it means "hero band" is how a palette drifts.
    static let hooprHeroBand = Color.hoopr(
        light: UIColor(white: 245 / 255, alpha: 1),
        dark: UIColor(red: 36 / 255, green: 36 / 255, blue: 38 / 255, alpha: 1)
    )

    /// The ground of a grouped form — a sheet whose fields sit in panels
    /// (`FormPanel`), the way an iOS inset-grouped list does. The panels are
    /// `hooprSurface`, so the page steps *down* around them: grey under white
    /// in light, black under the lifted card in dark.
    ///
    /// Like `hooprHeroBand`, it resolves to values the palette already proves
    /// — `hooprFill` in light, `hooprBackground` in dark — so every text and
    /// mark pairing drawn on it is one `ThemeContrastTests` already holds, and
    /// it is named for the job so a view never says "field" where it means
    /// "page".
    static let hooprGroupedBackground = Color.hoopr(
        light: UIColor(white: 245 / 255, alpha: 1),
        dark: UIColor(white: 0, alpha: 1)
    )

    /// A filled but unemphasised region: text-field backgrounds, unselected
    /// chips, the empty half of a capacity bar.
    static let hooprFill = Color.hoopr(
        light: UIColor(white: 245 / 255, alpha: 1),
        dark: UIColor(red: 44 / 255, green: 44 / 255, blue: 46 / 255, alpha: 1)
    )

    /// A row or control that is being touched, hovered by a pointer, or
    /// selected without being loud about it — drawn over a card or the page,
    /// where it has to read as a visible step up: 1.18:1 above a card in light
    /// and 1.26:1 in dark.
    ///
    /// Light is `#ECECEC`, which matches the pill the iOS 26 tab bar draws
    /// behind its selected item (`#EDEDED`, sampled from a screenshot) to
    /// within a step: a pressed row and the system's own selection read as the
    /// same family.
    ///
    /// **Dark is `#2E2E30`, and it is deliberately no lighter.** It sits within
    /// a hair of `hooprFill` (1.03:1) — a pressed row is not a *field*, and is
    /// never drawn on one — because the text on it has to survive too: primary
    /// text, secondary text and `hooprBrandAccent` are all asserted at 4.5:1 on
    /// it in both appearances, and the accent is the ceiling. `#303032` is
    /// already 4.48:1. Anything lighter would need the accent lightened, which
    /// is the wrong end to fix it from.
    static let hooprHoverFill = Color.hoopr(
        light: UIColor(white: 236 / 255, alpha: 1),
        dark: UIColor(red: 46 / 255, green: 46 / 255, blue: 48 / 255, alpha: 1)
    )

    /// Hairlines and outlines.
    static let hooprBorder = Color.hoopr(
        light: UIColor(white: 232 / 255, alpha: 1),
        dark: UIColor(red: 58 / 255, green: 58 / 255, blue: 60 / 255, alpha: 1)
    )

    /// A line that has to be *seen*, where `hooprBorder` is content to be
    /// felt: the outline of a control that would otherwise be identified only
    /// by a 1.09:1 fill, a drag handle, a divider that carries structure.
    ///
    /// `hooprBorder` is deliberately faint — 1.2:1 on white — and that is right
    /// for a hairline that only tidies a card's edge. It is wrong for a
    /// component boundary, which WCAG 1.4.11 wants at **3:1** against what it
    /// sits on. This role clears that on every ground in both appearances
    /// (light `#868686`: 3.64 on white, 3.34 on `hooprFill`, 3.08 on
    /// `hooprHoverFill`; dark `#78787C`: 4.78 on the page, 3.17 on a fill).
    /// It is measured, not adopted, in Phase 1: switching a field outline to
    /// it is a visible change that belongs with the composition that wants it.
    static let hooprSeparatorStrong = Color.hoopr(
        light: UIColor(white: 134 / 255, alpha: 1),
        dark: UIColor(red: 120 / 255, green: 120 / 255, blue: 124 / 255, alpha: 1)
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
