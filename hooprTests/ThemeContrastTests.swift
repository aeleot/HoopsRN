import XCTest
import SwiftUI
import UIKit
@testable import hoopr

/// Pins every colour pairing the UI actually makes to WCAG AA.
///
/// This file existed once before, against the coral palette that `a6e5668`
/// introduced, and was deleted wholesale when `eb67f1c` reverted that commit —
/// it asserted on roles (`hooprBrand`, `hooprBrandText`, `hooprOnSecondary`)
/// that stopped existing. Nothing replaced it, and the palette it left behind
/// reintroduced the exact defect the original was written to catch:
/// `hooprOnBrand` was `Color.white` on the brand orange, measuring 2.55:1 in
/// light mode and 2.25:1 in dark — under AA, and under even the 3:1 large-text
/// floor, on every primary button in the app.
///
/// So the arithmetic below is ported (it's palette-independent — pure maths on
/// two resolved colours) and the assertions are rewritten against the roles
/// that exist today. A ratio is arithmetic, not taste, which is exactly
/// why it belongs in a test rather than in a design review.
///
/// The pairings are the real ones, not every combination: a role is only
/// asserted against grounds it is actually drawn on. Adding a pairing here that
/// nothing renders would pin a number for its own sake.
final class ThemeContrastTests: XCTestCase {

    // MARK: - WCAG arithmetic

    /// WCAG 2.1 relative luminance. The 0.03928 branch and the 2.4 exponent are
    /// from the spec, not an approximation of it.
    private func luminance(_ color: UIColor, _ style: UIUserInterfaceStyle) -> CGFloat {
        let traits = UITraitCollection(userInterfaceStyle: style)
        let resolved = color.resolvedColor(with: traits)

        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)

        func channel(_ c: CGFloat) -> CGFloat {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    private func ratio(_ a: Color, on b: Color, _ style: UIUserInterfaceStyle) -> CGFloat {
        let la = luminance(UIColor(a), style)
        let lb = luminance(UIColor(b), style)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Asserts a pairing clears `floor` in **both** appearances.
    ///
    /// Both every time, because the two resolve to different values and have
    /// historically failed independently — `hooprOnRed` is the standing proof:
    /// white on it passes at 6.71:1 in light and fails at 2.82:1 in dark, so a
    /// light-mode-only check would have called it clean.
    private func assertContrast(
        _ foreground: Color,
        on background: Color,
        atLeast floor: CGFloat,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (style, name) in [(UIUserInterfaceStyle.light, "light"), (.dark, "dark")] {
            let measured = ratio(foreground, on: background, style)
            XCTAssertGreaterThanOrEqual(
                measured, floor,
                String(
                    format: "%@ in %@ mode: %.2f:1, need %.2f:1",
                    label, name, Double(measured), Double(floor)
                ),
                file: file, line: line
            )
        }
    }

    /// The colour a translucent wash actually *is*: `tint` at `alpha` over
    /// `ground`, resolved for `style`.
    ///
    /// A badge is drawn as `tint.opacity(0.12)` over a card, so the ground its
    /// text sits on is this composite, not the card — and it is darker and more
    /// orange than the card, which is what quietly pushed HOSTING's orange text
    /// to 2.78:1 while a check against `hooprSurface` said 3.17.
    private func washed(
        _ tint: Color, alpha: CGFloat, over ground: Color, _ style: UIUserInterfaceStyle
    ) -> UIColor {
        let traits = UITraitCollection(userInterfaceStyle: style)
        var t: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) = (0, 0, 0, 0)
        var g: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) = (0, 0, 0, 0)
        UIColor(tint).resolvedColor(with: traits).getRed(&t.r, green: &t.g, blue: &t.b, alpha: &t.a)
        UIColor(ground).resolvedColor(with: traits).getRed(&g.r, green: &g.g, blue: &g.b, alpha: &g.a)
        return UIColor(
            red: t.r * alpha + g.r * (1 - alpha),
            green: t.g * alpha + g.g * (1 - alpha),
            blue: t.b * alpha + g.b * (1 - alpha),
            alpha: 1
        )
    }

    /// `assertContrast` for a foreground on a translucent wash. Both
    /// appearances, for the same reason.
    private func assertContrast(
        _ foreground: Color,
        onWashOf tint: Color,
        alpha: CGFloat,
        over ground: Color,
        atLeast floor: CGFloat,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (style, name) in [(UIUserInterfaceStyle.light, "light"), (.dark, "dark")] {
            let lf = luminance(UIColor(foreground), style)
            let lb = luminance(washed(tint, alpha: alpha, over: ground, style), style)
            let measured = (max(lf, lb) + 0.05) / (min(lf, lb) + 0.05)
            XCTAssertGreaterThanOrEqual(
                measured, floor,
                String(
                    format: "%@ in %@ mode: %.2f:1, need %.2f:1",
                    label, name, Double(measured), Double(floor)
                ),
                file: file, line: line
            )
        }
    }

    /// Body text, and any text below 18pt / 14pt-bold.
    private let aaText: CGFloat = 4.5
    /// Large text, icons, and the boundary of a UI component.
    private let aaLarge: CGFloat = 3.0

    // MARK: - Filled brand controls

    /// **The regression this file exists for.**
    ///
    /// Every primary button in the app is `hooprOnBrand` on `hooprOrange`:
    /// LoginView's submit, MapTab's "Start Run", GameCard's Join/Leave,
    /// FriendActionButton, ChangePasswordSheet's send, plus the selected states
    /// on MainTabView's tab pills, MapTab's filter chips, ProfileView's pane
    /// selector and CreateGameSheet's visibility segments.
    func testBrandButtonLabelClearsAA() {
        assertContrast(.hooprOnBrand, on: .hooprOrange, atLeast: aaText, "on-brand label on brand fill")
    }

    /// `hooprDarkOrange` **is not currently painted anywhere.** It was the
    /// selected map pin's disc and then the cluster disc; `CourtHeat` took over
    /// the first and clustering was removed entirely on 2026-08-22, leaving
    /// this test as the role's only reference. Kept rather than deleted because
    /// the role is still a defined part of the palette and this costs nothing
    /// to hold — but if `hooprDarkOrange` is ever retired, this goes with it.
    /// Asserted at the text floor rather than the graphic one because it clears
    /// it comfortably and a tighter bound here costs nothing.
    func testBrandLabelOnDeepBrandClearsAA() {
        assertContrast(.hooprOnBrand, on: .hooprDarkOrange, atLeast: aaText, "on-brand label on deep brand fill")
    }

    /// The inbox badge's count, the one label in the app on a solid red fill.
    ///
    /// This is why `hooprOnRed` is a role of its own rather than a reuse of
    /// `hooprOnBrand`: `hooprRed` is deep in light mode and deliberately
    /// lightened in dark, so the label that reads on it has to invert with it.
    func testInboxBadgeCountClearsAAOnRed() {
        assertContrast(.hooprOnRed, on: .hooprRed, atLeast: aaText, "badge count on red fill")
    }

    // MARK: - Squad crests

    /// **Every squad palette colour, in both appearances, in the same commit
    /// that introduces them.**
    ///
    /// Eight new colours used as fills behind a glyph is exactly the shape that
    /// grows a gap list by eight entries in one stroke — `GAPS.md` already
    /// carries one entry for `hooprOrange` as a foreground, and that one is
    /// there because the pairing was never measured before it shipped. These
    /// were measured first: the fills are light in both appearances by
    /// construction, which is what lets `hooprOnCrest` be a fixed dark colour
    /// rather than one that has to invert.
    ///
    /// Held to the 4.5:1 **text** floor, not the 3:1 graphic one a glyph would
    /// need. The extra margin is deliberate — a squad initial or a record
    /// inside the disc is an obvious next step, and re-litigating eight colours
    /// at that point is worse than clearing the higher bar now.
    func testEverySquadCrestFillCarriesItsGlyph() {
        for key in Squad.colorKeys {
            assertContrast(
                .hooprOnCrest,
                on: .hooprSquad(key),
                atLeast: aaText,
                "crest glyph on the '\(key)' fill"
            )
        }
    }

    /// The fallback for a colour key the app doesn't know — a hand-edited
    /// document, or a palette entry removed after squads were created with it.
    ///
    /// It resolves to a *palette* colour rather than to `hooprFill`, which is
    /// dark in dark mode and would make the unknown-key crest the one
    /// unreadable one in the app. Asserted rather than assumed, because the
    /// fallback is the branch nothing on screen exercises.
    func testAnUnknownCrestKeyStillProducesAReadableFill() {
        assertContrast(
            .hooprOnCrest,
            on: .hooprSquad("chartreuse"),
            atLeast: aaText,
            "crest glyph on the fallback fill"
        )
    }

    /// Eight fills that read as eight teams. Not a WCAG rule — it's the
    /// property that makes a crest identify a squad at a glance, and two
    /// palette entries that resolve to the same colour would silently halve
    /// the picker.
    func testSquadPaletteColoursAreDistinct() {
        let resolved = Squad.colorKeys.map { key in
            UIColor(Color.hooprSquad(key))
                .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
                .description
        }

        XCTAssertEqual(
            Set(resolved).count, Squad.colorKeys.count,
            "Two squad palette keys resolve to the same colour, so two squads can't be told apart by their crest."
        )
    }

    // MARK: - Text on surfaces

    func testPrimaryTextOnEverySurfaceItIsDrawnOn() {
        assertContrast(.hooprPrimaryText, on: .hooprBackground, atLeast: aaText, "primary text on background")
        assertContrast(.hooprPrimaryText, on: .hooprSurface, atLeast: aaText, "primary text on surface")
        assertContrast(.hooprPrimaryText, on: .hooprFill, atLeast: aaText, "primary text on fill")
    }

    func testSecondaryTextOnEverySurfaceItIsDrawnOn() {
        assertContrast(.hooprSecondaryText, on: .hooprBackground, atLeast: aaText, "secondary text on background")
        assertContrast(.hooprSecondaryText, on: .hooprSurface, atLeast: aaText, "secondary text on surface")
        assertContrast(.hooprSecondaryText, on: .hooprFill, atLeast: aaText, "secondary text on fill")
    }

    /// Red is *text* everywhere except the inbox badge — error banners, the
    /// destructive button labels on `hooprFill`, Sign Out, "Remove home court",
    /// and the "Restricted" court badge. `hooprFill` is the tightest of the
    /// three grounds, which is what `CourtBadges` documents inline.
    func testErrorTextOnEverySurfaceItIsDrawnOn() {
        assertContrast(.hooprRed, on: .hooprBackground, atLeast: aaText, "error text on background")
        assertContrast(.hooprRed, on: .hooprSurface, atLeast: aaText, "error text on surface")
        assertContrast(.hooprRed, on: .hooprFill, atLeast: aaText, "error text on fill")
    }

    // MARK: - Brand as a mark

    /// **The tracked gap, closed by a role rather than a retune.**
    ///
    /// `hooprOrange` is a *fill* — it measures 3.17:1 on white and 2.91:1 on
    /// `hooprFill`, under the 4.5:1 a mark needs — so every text, glyph, focus
    /// ring, selection stroke and control tint draws `hooprBrandAccent`
    /// instead: the same hue and saturation, deepened until it reads. This is
    /// the assertion that used to be a test pinning the *failing* ratio, which
    /// is why it could go stale unnoticed (it passed on 2.29 and on 3.17 alike).
    ///
    /// Every ground a mark is actually drawn on, both appearances: the page and
    /// a card (the profile's rows, Login's "Sign up", the tab bar), a fill
    /// (`PlayerAvatar`'s initial, `InviteLinkCard`'s link glyph), a raised
    /// surface, and a pressed row. `BrandMarkUsageTests` is what stops a view
    /// drawing `hooprOrange` in those places again.
    func testBrandAccentClearsAAOnEveryGroundAMarkIsDrawnOn() {
        assertContrast(.hooprBrandAccent, on: .hooprBackground, atLeast: aaText, "brand accent on background")
        assertContrast(.hooprBrandAccent, on: .hooprSurface, atLeast: aaText, "brand accent on surface")
        assertContrast(.hooprBrandAccent, on: .hooprFill, atLeast: aaText, "brand accent on fill")
        assertContrast(.hooprBrandAccent, on: .hooprElevatedSurface, atLeast: aaText, "brand accent on elevated surface")
        assertContrast(.hooprBrandAccent, on: .hooprHoverFill, atLeast: aaText, "brand accent on hover fill")
    }

    /// A badge's text and an icon tile's glyph sit on a **wash of the vivid
    /// orange**, not on the card: HOSTING (12%) and the profile rows' and Home's
    /// friend-request tiles (14%). The wash is darker and more orange than the
    /// card, and it is the tightest ground the accent is drawn on — 4.76:1 in
    /// light mode at 14% — which is why it is asserted separately.
    func testBrandAccentClearsAAOnTheOrangeWashesBehindBadgesAndIconTiles() {
        assertContrast(
            .hooprBrandAccent, onWashOf: .hooprOrange, alpha: 0.12, over: .hooprSurface,
            atLeast: aaText, "HOSTING badge text on its 12% orange wash"
        )
        assertContrast(
            .hooprBrandAccent, onWashOf: .hooprOrange, alpha: 0.14, over: .hooprSurface,
            atLeast: aaText, "icon-tile glyph on its 14% orange wash"
        )
    }

    /// **The tab bar's selected item — the pairing that was the gap's most
    /// prominent instance, now passing.**
    ///
    /// `MainTabView` hands the system `hooprBrandAccent`, and this asserts that
    /// nominal value on the grounds this code controls: the page (Home, Runs,
    /// Seasons) and a card (the map's tab, whose band is `hooprSurface`).
    ///
    /// **What it does not, and cannot, assert is what iOS 26 finally draws.**
    /// The system adjusts a tint before painting it: sampled from screenshots,
    /// `hooprOrange` rendered as `#E55E27` on a `#EDEDED` pill in light mode
    /// (3.01:1 — the real on-screen figure, not the 2.55 this comment used to
    /// quote) and as `#FF8F6A` on `#3A3A3A` in dark (5.09:1). The rendered value
    /// is re-measured from a screenshot whenever the tint changes: with
    /// `hooprBrandAccent` the live app measured 5.32:1 in light (`#AF3706` on
    /// `#EDEDED`) and 4.98:1 in dark (`#FF8C68` on `#3A3A3A`).
    func testTabBarSelectionClearsAA() {
        assertContrast(.hooprBrandAccent, on: .hooprBackground, atLeast: aaText, "selected tab on the page")
        assertContrast(.hooprBrandAccent, on: .hooprSurface, atLeast: aaText, "selected tab on the map tab's band")
    }

    /// A mark in the tinted-square icon tile of a destructive profile row —
    /// Sign Out — on its own 14% red wash. Asserted because `ProfileRowTint`
    /// gave the destructive case a wash of its own to keep, and a wash a role
    /// owns is a pairing someone has to have measured.
    func testDestructiveRowMarkClearsAAOnItsOwnWash() {
        assertContrast(
            .hooprRed, onWashOf: .hooprRed, alpha: 0.14, over: .hooprSurface,
            atLeast: aaText, "Sign Out mark on its 14% red wash"
        )
    }

    /// WAITLIST and FULL badges: secondary text on a 12% wash of itself. Not new
    /// colours — but the badge's tuple changed shape when HOSTING's foreground
    /// and wash were split, and the pairing had never been measured.
    func testWaitlistAndFullBadgesClearAAOnTheirOwnWash() {
        assertContrast(
            .hooprSecondaryText, onWashOf: .hooprSecondaryText, alpha: 0.12, over: .hooprSurface,
            atLeast: aaText, "WAITLIST / FULL badge text on its 12% wash"
        )
    }

    // MARK: - Elevation

    /// **Dark mode's ladder — page, card, raised, field — and that every rung is
    /// a step a reader can see.**
    ///
    /// Each rung is one visible step up: 1.23:1 from the page to a card, 1.10
    /// to a raised surface, 1.11 to a field. The floor here is 1.08 — well below
    /// what is drawn, so a one-value retune doesn't fail it, and well above 1.0,
    /// which is what a collapsed ladder measures. Dark only, for the reason
    /// `testCardSeparatesFromBackgroundInDarkMode` gives: a shadow on black
    /// carries nothing, so the fill has to.
    func testDarkElevationLadderRisesInVisibleSteps() {
        let dark = UIUserInterfaceStyle.dark
        let rungs: [(String, Color)] = [
            ("page", .hooprBackground), ("card", .hooprSurface),
            ("raised", .hooprElevatedSurface), ("field", .hooprFill),
        ]
        for (lower, upper) in zip(rungs, rungs.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                ratio(upper.1, on: lower.1, dark), 1.08,
                "In dark mode the \(upper.0) must sit a visible step above the \(lower.0)"
            )
            XCTAssertGreaterThan(
                luminance(UIColor(upper.1), dark), luminance(UIColor(lower.1), dark),
                "In dark mode the \(upper.0) must be lighter than the \(lower.0), not darker"
            )
        }
    }

    /// Light mode has one raised level and it is white, so the raised surface
    /// **equals** the card there by design — nothing is lighter than white, and
    /// the lift comes from `hooprShadow` and `hooprSeparatorStrong` instead.
    ///
    /// Asserted so that it is a *recorded* decision. If light mode's page ground
    /// ever moves off pure white (a design call this token phase does not make —
    /// see the doc comment on `hooprElevatedSurface`), this is the test that
    /// says the role now has a value to choose, and goes red on purpose.
    func testLightRaisedSurfaceIsWhiteByDesign() {
        XCTAssertEqual(
            ratio(.hooprElevatedSurface, on: .hooprSurface, .light), 1.0, accuracy: 0.001,
            "light-mode raised surface no longer equals the card — see hooprElevatedSurface before changing this"
        )
    }

    /// A pressed or hovered row has to be **a visible step above the card it is
    /// pressed on**, and its text has to survive being pressed.
    ///
    /// Deliberately *not* asserted against `hooprFill`: a pressed row is never
    /// drawn on a field, and the brand accent's 4.5:1 caps how light the dark
    /// value can go, which leaves it within 1.03:1 of a fill. Asserting a gap
    /// there would encode a design the colour cannot have. What it must do is
    /// stand off a card — primary text, secondary text and `hooprBrandAccent`
    /// all clear 4.5:1 on it (4.61:1 for the accent in dark, against that
    /// floor), which is what "a row stays readable while it is pressed" means.
    func testHoverFillIsAVisibleStepAboveACardAndKeepsTextReadable() {
        for (style, name) in [(UIUserInterfaceStyle.light, "light"), (.dark, "dark")] {
            XCTAssertGreaterThanOrEqual(
                ratio(.hooprHoverFill, on: .hooprSurface, style), 1.08,
                "hover fill must be a visible step from a card in \(name) mode"
            )
        }
        assertContrast(.hooprPrimaryText, on: .hooprHoverFill, atLeast: aaText, "primary text on hover fill")
        assertContrast(.hooprSecondaryText, on: .hooprHoverFill, atLeast: aaText, "secondary text on hover fill")
    }

    /// Text on a raised surface. `hooprElevatedSurface` is a ground text is
    /// drawn on, so it gets the same two assertions the other grounds have.
    func testTextOnTheRaisedSurface() {
        assertContrast(.hooprPrimaryText, on: .hooprElevatedSurface, atLeast: aaText, "primary text on raised surface")
        assertContrast(.hooprSecondaryText, on: .hooprElevatedSurface, atLeast: aaText, "secondary text on raised surface")
    }

    /// **The strong separator is a component boundary, so it has to clear the
    /// 3:1 that WCAG 1.4.11 asks of one** — on every ground it could sit on, in
    /// both appearances. `hooprBorder` is deliberately faint (1.2:1 on white)
    /// and would fail this; that is the whole reason the second role exists.
    func testStrongSeparatorClearsTheGraphicFloorOnEveryGround() {
        assertContrast(.hooprSeparatorStrong, on: .hooprBackground, atLeast: aaLarge, "strong separator on background")
        assertContrast(.hooprSeparatorStrong, on: .hooprSurface, atLeast: aaLarge, "strong separator on surface")
        assertContrast(.hooprSeparatorStrong, on: .hooprFill, atLeast: aaLarge, "strong separator on fill")
        assertContrast(.hooprSeparatorStrong, on: .hooprElevatedSurface, atLeast: aaLarge, "strong separator on raised surface")
        assertContrast(.hooprSeparatorStrong, on: .hooprHoverFill, atLeast: aaLarge, "strong separator on hover fill")
    }

    /// And the reason the role isn't just `hooprBorder`: the hairline is
    /// *meant* to sit under the graphic floor. If this ever fails, the two roles
    /// have converged and one of them is redundant.
    func testHairlineBorderIsDeliberatelyFainterThanTheStrongSeparator() {
        for (style, name) in [(UIUserInterfaceStyle.light, "light"), (.dark, "dark")] {
            XCTAssertLessThan(
                ratio(.hooprBorder, on: .hooprBackground, style),
                ratio(.hooprSeparatorStrong, on: .hooprBackground, style),
                "in \(name) mode the hairline must be fainter than the strong separator"
            )
        }
    }

    // MARK: - Heat

    /// **Every tier of the heat ramp carries its label — the assertion that
    /// found a real failure.**
    ///
    /// The map pin's count is drawn on these fills. It used to be
    /// `hooprOnBrand` (black) on all five, which is 6.62:1 on the quietest and
    /// only 4.01 and 3.43 on tiers 3 and 4: under the 4.5:1 a 12pt bold label
    /// needs, on exactly the courts busy enough to matter. Nothing asserted it,
    /// because the ramp lived outside `Theme.swift` and `CourtHeatTests` only
    /// pinned the fills. `hooprOnHeat(tier:)` flips to white where black stops
    /// clearing; this holds every tier to it, in both appearances (the ramp is
    /// fixed, so they are equal — asserted through the shared helper anyway).
    func testEveryHeatTierCarriesItsLabel() {
        for tier in 0...Color.hooprHeatMaxTier {
            assertContrast(
                .hooprOnHeat(tier: tier),
                on: .hooprHeat(tier: tier),
                atLeast: aaText,
                "pin count on heat tier \(tier)"
            )
        }
    }

    // MARK: - Surface separation

    /// Cards must be distinguishable from the page — but in **dark mode only**.
    ///
    /// Light mode is deliberately 1.00:1: `hooprSurface` and `hooprBackground`
    /// are both pure white there, and the palette separates a card with a
    /// border and a shadow instead of a fill. The predecessor of this file
    /// asserted separation in both appearances, which encoded the opposite
    /// design decision — worth knowing before anyone "restores" it.
    func testCardSeparatesFromBackgroundInDarkMode() {
        XCTAssertGreaterThan(
            ratio(.hooprSurface, on: .hooprBackground, .dark), 1.0,
            "surface must lift off the background in dark mode, where there is no shadow to do it"
        )
    }
}
