import XCTest
import SwiftUI
import UIKit
@testable import hoopr

/// Pins every colour pairing the UI actually makes to WCAG AA.
///
/// This exists because the palette shipped a real defect that nothing caught:
/// `hooprOnBrand` was `Color.white` on the brand colour, which measured 2.55:1
/// in light mode and 2.25:1 in dark — below AA (4.5:1) and below even the 3:1
/// large-text floor — on every primary button in the app. A ratio is arithmetic
/// on two resolved colours, so it's exactly the kind of thing a test should own
/// rather than a design review.
///
/// The pairings below are the real ones, not every combination: a role is only
/// asserted against the grounds it's actually drawn on. Adding a role here
/// without a call site would pin a number nobody renders.
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

    /// Asserts a pairing clears `floor` in both appearances.
    ///
    /// Both are checked every time because the two appearances resolve to
    /// different values and have historically failed independently — the old
    /// dark-mode brand lift improved the colour as text while pushing the
    /// button label further under.
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

    /// Body text and any text below 18pt / 14pt-bold.
    private let aaText: CGFloat = 4.5
    /// Large text, icons, and the boundary of a UI component.
    private let aaLarge: CGFloat = 3.0

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

    // MARK: - Filled controls

    /// The regression this whole file was written for.
    func testBrandButtonLabelClearsAA() {
        assertContrast(.hooprOnBrand, on: .hooprBrand, atLeast: aaText, "on-brand label on brand fill")
    }

    /// The profile header runs a gradient from `hooprBrand` to `hooprBrandDeep`
    /// and carries small italic text the whole way, so the deep end has to clear
    /// AA too — not just the light end.
    func testBrandGradientCarriesItsLabelAtBothEnds() {
        assertContrast(.hooprOnBrand, on: .hooprBrandDeep, atLeast: aaText, "on-brand label on deep brand")
    }

    /// The selected visibility chip in `CreateGameSheet` is the only filled
    /// secondary surface in the app, and it shipped this pairing wrong once:
    /// the label stayed `hooprOnBrand` when the fill moved from brand to
    /// secondary, putting jet on slate at 1.94:1 in light mode.
    func testFilledSecondaryControl() {
        assertContrast(.hooprOnSecondary, on: .hooprSecondary, atLeast: aaText, "on-secondary label on secondary fill")
    }

    /// A destructive button is tinted text on `hooprFill`, never a filled
    /// capsule — so this is the pairing that has to hold, not white-on-red.
    func testDestructiveTextOnFill() {
        assertContrast(.hooprRed, on: .hooprFill, atLeast: aaText, "error text on fill")
        assertContrast(.hooprRed, on: .hooprSurface, atLeast: aaText, "error text on surface")
    }

    // MARK: - Brand as text

    /// `hooprBrand` is deliberately *not* checked as text: it is 2.61:1 on white
    /// and exists only as a fill. `hooprBrandText` is the readable companion,
    /// and it has to hold on the 1dp card too — plain coral is 4.19:1 there,
    /// which is what the dark value's lift exists to fix.
    ///
    /// `hooprFill` takes the graphic floor rather than the text one: the only
    /// brand-coloured mark drawn on a fill is `PlayerAvatar`'s initial, which is
    /// bold and sized as a fraction of the circle — large text, not body copy.
    func testBrandTextIsReadableOnEverySurface() {
        assertContrast(.hooprBrandText, on: .hooprBackground, atLeast: aaText, "brand text on background")
        assertContrast(.hooprBrandText, on: .hooprSurface, atLeast: aaText, "brand text on surface")
        assertContrast(.hooprBrandText, on: .hooprFill, atLeast: aaLarge, "avatar initial on fill")
    }

    /// The avatar's initial sits on `hooprOnBrand` when it's on the header.
    func testAvatarInitialOnBrandCircle() {
        assertContrast(.hooprBrand, on: .hooprOnBrand, atLeast: aaText, "brand initial on on-brand circle")
    }

    // MARK: - Status

    /// Roster badges are outlined rather than filled precisely so their text
    /// lands on the card ground, where every status colour clears AA — on
    /// `hooprFill` two of them do not.
    ///
    /// Only `hooprSurface` is asserted because that is the only ground a badge
    /// is drawn on: every badge lives inside a `GameCard` or a `CourtRow`, both
    /// of which are surfaces. Asserting against the page background would pin a
    /// number nothing renders.
    func testStatusColoursAsBadgeText() {
        for (color, name) in [
            (Color.hooprOpen, "open"),
            (Color.hooprFilling, "filling"),
            (Color.hooprSecondary, "waitlist"),
            (Color.hooprSecondaryText, "full"),
            (Color.hooprRed, "restricted")
        ] {
            assertContrast(color, on: .hooprSurface, atLeast: aaText, "\(name) badge text on surface")
        }
    }

    /// The capacity bar is a 5pt graphic, so it takes the 3:1 component floor
    /// rather than the text one — but it still has to be visible against the
    /// track it sits in.
    func testCapacityBarAgainstItsTrack() {
        assertContrast(.hooprOpen, on: .hooprFill, atLeast: aaLarge, "open bar on track")
        assertContrast(.hooprFilling, on: .hooprFill, atLeast: aaLarge, "filling bar on track")
        assertContrast(.hooprSecondaryText, on: .hooprFill, atLeast: aaLarge, "full bar on track")
    }

    // MARK: - Secondary accents

    /// Focus rings and slider tints are UI component boundaries, so 3:1 — but
    /// they must also beat the border they replace, or focus would be invisible.
    func testSecondaryAccentAgainstSurfaces() {
        assertContrast(.hooprSecondary, on: .hooprSurface, atLeast: aaLarge, "secondary accent on surface")
        assertContrast(.hooprSecondary, on: .hooprFill, atLeast: aaLarge, "secondary accent on fill")
    }

    // MARK: - Map markers

    /// The pin glyph is a 15pt bold symbol and the cluster count a 14pt bold
    /// label — both large/graphic, so 3:1. The selected pin is the tighter of
    /// the two because its disc is the deeper coral.
    func testMapMarkerGlyphOnBothDiscStates() {
        assertContrast(.hooprOnBrand, on: .hooprBrand, atLeast: aaLarge, "pin glyph on unselected disc")
        assertContrast(.hooprOnBrand, on: .hooprBrandDeep, atLeast: aaLarge, "pin glyph on selected disc")
    }

    // MARK: - Surface separation

    /// Cards have to be distinguishable from the page behind them. Light mode
    /// used to fail this outright — background and surface were both pure white,
    /// a 1.00:1 ratio, leaving the card held up entirely by its border.
    func testCardSeparatesFromBackground() {
        for (style, name) in [(UIUserInterfaceStyle.light, "light"), (.dark, "dark")] {
            let measured = ratio(.hooprSurface, on: .hooprBackground, style)
            XCTAssertGreaterThan(
                measured, 1.0,
                "surface must not be identical to background in \(name) mode"
            )
        }
    }

    /// Disabled content is a single documented value rather than the assortment
    /// of 0.4 and 0.5 literals this replaced.
    func testDisabledOpacityMatchesGuidance() {
        XCTAssertEqual(Color.hooprDisabledOpacity, 0.38, accuracy: 0.001)
    }
}
