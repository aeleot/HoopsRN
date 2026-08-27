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
/// two resolved colours) and the assertions are rewritten against the eleven
/// roles that exist today. A ratio is arithmetic, not taste, which is exactly
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

    // MARK: - Known gap

    /// `hooprOrange` is **not** asserted as a foreground, and that is a recorded
    /// defect rather than an oversight — see `context/GAPS.md`.
    ///
    /// It is drawn as a mark on pale grounds in a dozen places (profile row
    /// icons, `PlayerAvatar`'s initials, the map's recenter glyph, `CourtRow`'s
    /// filled star, `GameCard`'s basketball) where it measures 2.55:1 on
    /// background and surface and 2.34:1 on fill in **light mode** — under both
    /// the text and the graphic floor. Dark mode is fine (9.33 / 7.56 / 6.19),
    /// because the orange is lifted and the grounds are dark.
    ///
    /// Fixing it needs a second brand role — a deepened orange for marks that
    /// are read rather than filled, which is what the reverted palette's
    /// `hooprBrandText` was — plus a sweep of those call sites. That is a design
    /// decision and a wider change than the pairing this file was restored to
    /// pin, so it is tracked rather than asserted. **Add the assertion here in
    /// the same change that adds the role**; this comment is the reminder.
    func testBrandAsForegroundIsATrackedGap() throws {
        let lightOnFill = ratio(.hooprOrange, on: .hooprFill, .light)
        XCTAssertLessThan(
            lightOnFill, aaLarge,
            """
            hooprOrange now clears \(aaLarge):1 as a foreground on hooprFill in \
            light mode (\(String(format: "%.2f", Double(lightOnFill))):1). If \
            that is because a readable brand role landed, replace this test with \
            real assertions and strike the gap from context/GAPS.md.
            """
        )
    }

    /// The tab bar's selected item, which became the **most prominent**
    /// instance of the gap above when navigation moved to the bottom on
    /// 2026-08-26.
    ///
    /// The old shell never hit this: its tab pills painted `hooprOrange` as a
    /// *fill* with `hooprOnBrand` on top, which is the pairing
    /// `testBrandButtonLabelClearsAA` pins at 6.61:1. The shelf inverts that —
    /// `HooprTabBar` draws the selected item's glyph **and** its 11pt label in
    /// the brand colour, on a `hooprSurface` ground. 11pt is normal text by
    /// WCAG's reckoning, so it needs 4.5:1 and gets ~2.55:1.
    ///
    /// Measured against `hooprBackground` rather than `hooprSurface` because
    /// the two are the same pure white in light mode, and `hooprBackground` is
    /// the tighter of the pair in dark.
    ///
    /// Shipped knowingly: an orange selected tab was an explicit product
    /// decision, and the alternatives both cost something real. A monochrome
    /// bar passes but drops the brand from the app's most-seen control;
    /// `hooprDarkOrange` only reaches ~3.85:1, which clears the graphic floor
    /// and still misses the text one. The genuine fix is the deepened
    /// `hooprOrange`-as-text role the gap above already calls for — roughly
    /// `#B4491E`, which measures ~5.4:1 on white.
    ///
    /// Asserted in the failing direction on purpose, exactly like the test
    /// above: **this goes green the day the gap closes**, which is the signal
    /// to replace it with a real assertion.
    func testTabBarSelectionIsATrackedGap() throws {
        let lightOnBackground = ratio(.hooprOrange, on: .hooprBackground, .light)
        XCTAssertLessThan(
            lightOnBackground, aaText,
            """
            hooprOrange now clears \(aaText):1 as a foreground on \
            hooprBackground in light mode \
            (\(String(format: "%.2f", Double(lightOnBackground))):1). If a \
            readable brand role landed, point HooprTabBar's selected colour at \
            it, replace this test with a real assertion, and strike the gap \
            from context/GAPS.md.
            """
        )
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
