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

    /// **The hero band is the app's first filled region that is also a text
    /// ground**, so every pairing drawn on it is asserted here rather than
    /// inherited from the roles it happens to resolve to. The band is what
    /// replaced `cardChrome()` on the redesigned screens; if it ever stops
    /// clearing AA, the screens' whole answer becomes unreadable at once.
    func testEveryPairingDrawnOnTheHeroBand() {
        assertContrast(.hooprPrimaryText, on: .hooprHeroBand, atLeast: aaText, "hero numeral on the band")
        assertContrast(.hooprSecondaryText, on: .hooprHeroBand, atLeast: aaText, "band label and details")
        assertContrast(.hooprBrandAccent, on: .hooprHeroBand, atLeast: aaText, "a mark on the band")
        assertContrast(.hooprRed, on: .hooprHeroBand, atLeast: aaText, "an error message on the band")
        assertContrast(.hooprSeparatorStrong, on: .hooprHeroBand, atLeast: aaLarge, "the band's own baseline")
    }

    /// The baseline is what tells the band from the page, and it is the only
    /// thing that does in light mode — where the band is `#F5F5F5` on white, a
    /// 1.09:1 region you feel rather than see. So the *line* has to clear the
    /// 3:1 graphic floor against **both** sides of itself, or the boundary the
    /// redesign uses in place of a card edge isn't a boundary.
    func testTheBaselineSeparatesTheBandFromThePageOnBothSides() {
        assertContrast(.hooprSeparatorStrong, on: .hooprHeroBand, atLeast: aaLarge, "baseline against the band")
        assertContrast(.hooprSeparatorStrong, on: .hooprBackground, atLeast: aaLarge, "baseline against the page")
    }

    /// The band resolves to values the palette already proves — `hooprFill` in
    /// light, `hooprElevatedSurface` in dark — and this is what pins that, so
    /// the role can't quietly become a third value nobody measured.
    func testTheHeroBandResolvesToTheLadderItClaims() {
        XCTAssertEqual(
            UIColor(Color.hooprHeroBand).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)),
            UIColor(Color.hooprFill).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)),
            "in light the band is the fill value: nothing is lighter than the white page"
        )
        XCTAssertEqual(
            UIColor(Color.hooprHeroBand).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)),
            UIColor(Color.hooprElevatedSurface).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)),
            "in dark the band carries its lift in the fill, one step above a card"
        )
    }

    // MARK: - Hero washes (UI revamp Phase 4)

    /// Every wash the app draws: one per crest colour, and the brand's.
    private var washes: [(name: String, color: Color)] {
        Squad.colorKeys.map { ($0, Color.hooprSquadWash($0)) } + [("brand", Color.hooprBrandWash)]
    }

    /// **The premise the washes rest on.** Each has the band's own relative
    /// luminance, in both appearances — which is what lets a band carry a
    /// squad's colour without moving a single ratio drawn on it.
    func testEveryWashHasTheBandsLuminance() {
        for (name, wash) in washes {
            for style in [UIUserInterfaceStyle.light, .dark] {
                let band = luminance(UIColor(Color.hooprHeroBand), style)
                XCTAssertEqual(
                    luminance(UIColor(wash), style), band, accuracy: band * 0.005,
                    "\(name) wash, style \(style.rawValue)"
                )
            }
        }
    }

    /// And it is the squad's colour, not the band again. In dark mode every
    /// wash carries a visible cast — its channels spread at least 0.08 apart,
    /// where the band's spread is 0.008. (Light mode can't: see
    /// `Color.hooprSquadWash` on the gamut near white.)
    func testEveryDarkWashIsVisiblyItsColour() {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        for (name, wash) in washes {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(wash).resolvedColor(with: dark).getRed(&r, green: &g, blue: &b, alpha: &a)
            XCTAssertGreaterThanOrEqual(max(r, g, b) - min(r, g, b), 0.08, "\(name) wash reads as grey")
        }
    }

    /// **Everything drawn on a band clears its floor on every colour the mesh
    /// draws** — each wash, and the sRGB mixes between a wash and the plain
    /// band at a quarter, half and three quarters, which are where two
    /// equal-luminance colours mixed in sRGB dip darkest. The pairings are the
    /// band's: its text, a mark, an error, the baseline, and the form dots.
    func testEveryBandPairingHoldsAcrossEveryWash() {
        let pairings: [(color: Color, floor: CGFloat, label: String)] = [
            (.hooprPrimaryText, aaText, "primary text"),
            (.hooprSecondaryText, aaText, "secondary text"),
            (.hooprBrandAccent, aaText, "a mark"),
            (.hooprRed, aaText, "an error"),
            (.hooprSeparatorStrong, aaLarge, "the baseline"),
            (.hooprFormWin, aaLarge, "a win dot"),
            (.hooprFormLoss, aaLarge, "a loss dot"),
            (.hooprFormUnplayed, 2.0, "an unplayed dot"),
        ]
        for (name, wash) in washes {
            for fraction: CGFloat in [1, 0.75, 0.5, 0.25] {
                for style in [UIUserInterfaceStyle.light, .dark] {
                    let ground = luminance(washed(wash, alpha: fraction, over: .hooprHeroBand, style), style)
                    for pairing in pairings {
                        let mark = luminance(UIColor(pairing.color), style)
                        let measured = (max(mark, ground) + 0.05) / (min(mark, ground) + 0.05)
                        XCTAssertGreaterThanOrEqual(
                            measured, pairing.floor,
                            String(
                                format: "%@ on the %@ wash at %.0f%%, style %d: %.2f:1",
                                pairing.label, name, Double(fraction * 100), style.rawValue, Double(measured)
                            )
                        )
                    }
                }
            }
        }
    }

    /// Home's HOSTING pill is an orange wash on the band, and the band is now
    /// Home's brand wash (2026-09-23) — orange on orange, so it is asserted on
    /// that composite, and on the plain band it sits on while the wash fades
    /// in. **At the 12% a card's pill uses it failed on both** — 4.44:1 on the
    /// plain band in dark, a defect since Phase 2b that nothing asserted,
    /// because the badge test above measures over a card. Home's pill is 8%.
    func testTheHostingPillReadsOnHomesBand() {
        assertContrast(
            .hooprBrandAccent, onWashOf: .hooprOrange, alpha: 0.08, over: .hooprHeroBand,
            atLeast: aaText, "HOSTING on the plain band"
        )
        assertContrast(
            .hooprBrandAccent, onWashOf: .hooprOrange, alpha: 0.08, over: .hooprBrandWash,
            atLeast: aaText, "HOSTING on Home's brand wash"
        )
    }

    /// Home's half-ball is the brand orange at a pressed row's luminance, so
    /// the text that can run over it — the detail line, a long court name —
    /// and the profile button on top of it read as they do on a pressed row.
    func testHomesBallSitsAtTheHoverFillsLuminance() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let target = luminance(UIColor(Color.hooprHoverFill), style)
            XCTAssertEqual(
                luminance(UIColor(Color.hooprBrandWatermark), style), target, accuracy: target * 0.005,
                "style \(style.rawValue)"
            )
        }
    }

    /// What can reach the band's right third: the detail line's spots and
    /// distance, a long court name, the profile button, and the arrow at the
    /// last row's end — primary text, so it is the first pairing below. (It was
    /// the accent's "Your runs" cue until 2026-09-24.)
    ///
    /// **Not the HOSTING pill, and it would fail** (4.08:1 in dark): it is
    /// always the first item on its line, its text capped at 14pt, so it
    /// spans at most the band's first 110pt and the ball starts at 268pt.
    /// If the pill ever moves right, this is the pairing to add.
    func testEverythingDrawnOverHomesBallReads() {
        assertContrast(.hooprPrimaryText, on: .hooprBrandWatermark, atLeast: aaText, "court name and the arrow over the ball")
        assertContrast(.hooprSecondaryText, on: .hooprBrandWatermark, atLeast: aaText, "detail line and profile button over the ball")
        assertContrast(.hooprBrandAccent, on: .hooprBrandWatermark, atLeast: aaText, "a mark over the ball")
    }

    /// And it is visibly a shape on the band, not the band again.
    func testHomesBallStepsOffTheBand() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            XCTAssertGreaterThan(
                ratio(.hooprBrandWatermark, on: .hooprHeroBand, style), 1.05,
                "style \(style.rawValue)"
            )
        }
    }

    // MARK: - Grouped forms

    /// The grouped ground resolves to proven values — `hooprFill` in light,
    /// the page in dark — so it can't quietly become a value nobody measured.
    func testTheGroupedGroundResolvesToTheValuesItClaims() {
        let light = UITraitCollection(userInterfaceStyle: .light)
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        XCTAssertEqual(
            UIColor(Color.hooprGroupedBackground).resolvedColor(with: light),
            UIColor(Color.hooprFill).resolvedColor(with: light)
        )
        XCTAssertEqual(
            UIColor(Color.hooprGroupedBackground).resolvedColor(with: dark),
            UIColor(Color.hooprBackground).resolvedColor(with: dark)
        )
    }

    /// What `CreateGameSheet` draws on the ground itself, outside its panels:
    /// the court's name and glyph, its address, and an error.
    func testEveryPairingDrawnOnTheGroupedGround() {
        assertContrast(.hooprPrimaryText, on: .hooprGroupedBackground, atLeast: aaText, "court name on the grouped ground")
        assertContrast(.hooprSecondaryText, on: .hooprGroupedBackground, atLeast: aaText, "address on the grouped ground")
        assertContrast(.hooprBrandAccent, on: .hooprGroupedBackground, atLeast: aaText, "court glyph on the grouped ground")
        assertContrast(.hooprRed, on: .hooprGroupedBackground, atLeast: aaText, "an error on the grouped ground")
    }

    /// A panel is told from the ground by its fill alone — no edge, no
    /// shadow — so the two must differ in both appearances.
    func testAPanelSeparatesFromTheGroupedGroundInBothAppearances() {
        for (style, name) in [(UIUserInterfaceStyle.light, "light"), (.dark, "dark")] {
            XCTAssertGreaterThan(
                ratio(.hooprSurface, on: .hooprGroupedBackground, style), 1.05,
                "in \(name) mode a panel must step off the grouped ground"
            )
        }
    }

    // MARK: - The form guide's dots

    /// A played dot is a graphic you have to read to know the result, so each
    /// one clears WCAG 1.4.11's 3:1 on both grounds the guide is drawn on:
    /// Seasons' band and `SquadDetailView`'s card. The win green on the light
    /// band (3.15:1) is the binding case. It sets how light that green can go.
    func testEveryPlayedFormDotClearsTheGraphicFloorOnItsGrounds() {
        for ground in [Color.hooprHeroBand, .hooprSurface] {
            assertContrast(.hooprFormWin, on: ground, atLeast: aaLarge, "win dot")
            assertContrast(.hooprFormLoss, on: ground, atLeast: aaLarge, "loss dot")
        }
    }

    /// The unplayed dot is a placeholder, so it is held to *visible* (2:1) and
    /// to *quieter than either result* in both appearances, not to 3:1. A grey
    /// as heavy as the win and loss dots would read as a third kind of result.
    func testTheUnplayedDotIsVisibleButQuieterThanEitherResult() {
        for ground in [Color.hooprHeroBand, .hooprSurface] {
            assertContrast(.hooprFormUnplayed, on: ground, atLeast: 2.0, "unplayed dot")

            for style in [UIUserInterfaceStyle.light, .dark] {
                let unplayed = ratio(.hooprFormUnplayed, on: ground, style)
                XCTAssertLessThan(unplayed, ratio(.hooprFormWin, on: ground, style), "unplayed vs win, \(style.rawValue)")
                XCTAssertLessThan(unplayed, ratio(.hooprFormLoss, on: ground, style), "unplayed vs loss, \(style.rawValue)")
            }
        }
    }

    /// **The finding, pinned.** To a red-green colour-blind reader the two dots
    /// differ only in lightness, and WCAG counts lightness as a second cue at
    /// 3:1. That isn't reachable while both dots clear 3:1 on the band. The
    /// widest gap is 1.95:1 in light and 2.25:1 in dark, which is why
    /// *Differentiate Without Color* marks the dots. This holds the gap
    /// where it is, so a retune can't close it without failing here.
    func testWinAndLossStayAsFarApartInLightnessAsTheFloorAllows() {
        assertContrast(.hooprFormWin, on: .hooprFormLoss, atLeast: 1.9, "win against loss")
    }

    /// The ✓ and ✕ that *Differentiate Without Color* draws are graphics, so
    /// 3:1 on the dot they sit on. White on the light dots, black on the dark
    /// ones. The weakest is white on the light green, at 3.44:1.
    func testTheDifferentiateWithoutColorMarkReadsOnBothResults() {
        assertContrast(.hooprOnFormResult, on: .hooprFormWin, atLeast: aaLarge, "✓ on the win dot")
        assertContrast(.hooprOnFormResult, on: .hooprFormLoss, atLeast: aaLarge, "✕ on the loss dot")
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
