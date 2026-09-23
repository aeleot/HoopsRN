import XCTest
import SwiftUI
import UIKit
@testable import hoopr

/// Pins the map court card's header against the two things that broke it.
///
/// At `.accessibility3` the card showed "East En…" and "Durham · 0.…"
/// (`plans/UI_REVAMP_AUDIT.md` §7.4): the star and close buttons scaled with
/// the text, took the width the name needed, and the name truncated — against
/// `MAP_LAYER.md`'s own rule that *badges are shed, the name is not*. The
/// redesign fixed it with two mechanisms, and each is asserted here rather than
/// trusted to one screenshot of one short court name:
///
/// 1. **The controls can't grow into the name's width** — their glyphs are
///    capped inside fixed 44pt targets.
/// 2. **The name can always wrap at a word** — no court in the shipped dataset
///    has a word too wide for the card at the largest size, so the name never
///    needs to truncate or break mid-word; it only ever takes more lines.
@MainActor
final class CourtCardLayoutTests: XCTestCase {

    /// How wide the court glyph actually draws at `category`.
    ///
    /// **Not its font size.** The court glyph is a landscape symbol, wider
    /// than its point size — which is what this file got wrong the first time,
    /// measuring the name's room from 40.7pt when the glyph (then
    /// `sportscourt.fill`, 1.56×) drew 63.7pt at `.accessibility3`. The card
    /// then showed "East E…" on the device while this file predicted "East
    /// End". The basketball court that replaced it is measured the same way.
    private func drawnGlyphWidth(at category: UIContentSizeCategory) throws -> CGFloat {
        let pointSize = HooprFontMetrics.scaledSize(HooprTextRole.headline.size, at: category)
        let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let image = try XCTUnwrap(
            UIImage(named: CourtSymbol.name, in: .main, with: config),
            "the court symbol isn't in the app's asset catalog"
        )
        return image.size.width
    }

    /// The width a wrapping court name gets on Home's line: the page, less the
    /// glyph and its gap wherever the glyph is shown.
    private func wrappingNameWidth(at category: UIContentSizeCategory, showsGlyph: Bool) throws -> CGFloat {
        HomeHeroMetrics.contentWidth - (showsGlyph ? try drawnGlyphWidth(at: category) + Spacing.sm : 0)
    }

    private func width(of text: String, at category: UIContentSizeCategory) -> CGFloat {
        let size = HooprFontMetrics.scaledSize(HooprTextRole.title.size, at: category)
        let font = UIFont.systemFont(ofSize: size, weight: HooprTextRole.title.uiFontWeight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    // MARK: - 1. The controls stay in their frames

    /// The favourite and close glyphs are capped (19 → 24pt, 24 → 30pt), so at
    /// every text size they fit their 44pt targets — and a control that can't
    /// grow can't take the name's width.
    func testTheCardControlsNeverOutgrowTheirTargets() {
        let categories: [UIContentSizeCategory] = [
            .large, .extraExtraExtraLarge, .accessibilityExtraLarge, .accessibilityExtraExtraExtraLarge,
        ]
        for category in categories {
            XCTAssertLessThanOrEqual(HooprFontMetrics.scaledSize(19, maximumSize: 24, at: category), 44)
            XCTAssertLessThanOrEqual(HooprFontMetrics.scaledSize(24, maximumSize: 30, at: category), 44)
        }
    }

    // MARK: - 2. Every court name can wrap without breaking a word

    /// **The guarantee the old header didn't have, and the reason
    /// `CourtTitle` sheds its glyph from `.accessibility4`.** A name can only
    /// break inside a word if one unbreakable run of letters is wider than the
    /// line — so every such run in every court name in the bundled dataset is
    /// measured, at every accessibility size, against the width the name
    /// actually gets there: beside the glyph where it's shown, the whole line
    /// where it isn't.
    ///
    /// Hyphens are break points, like spaces — "Bentley-Ridge" wraps as
    /// "Bentley- / Ridge", which is a proper wrap. The first version of this
    /// test split on spaces only, failed on exactly that name, and was wrong.
    func testNoCourtNameEverBreaksMidWordAtAnyAccessibilitySize() throws {
        let names = CourtService().courts.map(\.displayName)
        try XCTSkipIf(names.isEmpty, "courts.json not reachable from the test host")

        let segments = Set(names.flatMap {
            $0.split(whereSeparator: { $0 == " " || $0 == "-" }).map(String.init)
        })

        let sizes: [(DynamicTypeSize, UIContentSizeCategory)] = [
            (.accessibility1, .accessibilityMedium),
            (.accessibility2, .accessibilityLarge),
            (.accessibility3, .accessibilityExtraLarge),
            (.accessibility4, .accessibilityExtraExtraLarge),
            (.accessibility5, .accessibilityExtraExtraExtraLarge),
        ]
        for (dynamicType, category) in sizes {
            let available = try wrappingNameWidth(
                at: category, showsGlyph: CourtTitle.showsGlyph(at: dynamicType)
            )
            let widest = segments.max { width(of: $0, at: category) < width(of: $1, at: category) }!

            XCTAssertLessThanOrEqual(
                width(of: widest, at: category), available,
                "\"\(widest)\" would break mid-word at \(dynamicType)"
            )
        }
    }

    /// The glyph goes at every accessibility size and nowhere else.
    func testTheCourtGlyphIsShedAtEveryAccessibilitySize() {
        for size in [DynamicTypeSize.large, .xLarge, .xxxLarge] {
            XCTAssertTrue(CourtTitle.showsGlyph(at: size), "\(size)")
        }
        for size in [DynamicTypeSize.accessibility1, .accessibility3, .accessibility5] {
            XCTAssertFalse(CourtTitle.showsGlyph(at: size), "\(size)")
        }
    }

    /// Why: the glyph draws wider than its font size, by enough to matter
    /// (about 1.36× for the basketball court). Pinned so the next measurement
    /// of the name's room uses the drawn width.
    func testTheCourtGlyphDrawsWiderThanItsFontSize() throws {
        let category = UIContentSizeCategory.accessibilityExtraLarge
        let pointSize = HooprFontMetrics.scaledSize(HooprTextRole.headline.size, at: category)
        XCTAssertGreaterThan(try drawnGlyphWidth(at: category), pointSize * 1.3)
    }

    /// **The card's header is one row, and the name gives way inside it.**
    /// At `.accessibility3` the glyph is gone and the name has the row less its
    /// two 44pt controls and the gaps: "East End Park" still can't fit, and the
    /// first form of it that does is "East End" — a real name, not the
    /// "East E…" the device showed while the glyph was still taking 63.7pt.
    func testAtAccessibility3TheCardShowsEastEndRatherThanACutName() {
        let category = UIContentSizeCategory.accessibilityExtraLarge
        XCTAssertFalse(CourtTitle.showsGlyph(at: .accessibility3))

        let room = HomeHeroMetrics.contentWidth - Spacing.sm * 2 - 88   // two row gaps + two 44pt targets
        let shown = CourtName.forms(of: "East End Park").first { width(of: $0, at: category) <= room }
        XCTAssertEqual(shown, "East End")
    }

    /// And at the first accessibility size the whole name fits — shedding the
    /// glyph gives the name back more than it costs.
    func testAtAccessibility1TheCardShowsTheWholeName() {
        let category = UIContentSizeCategory.accessibilityMedium
        let room = HomeHeroMetrics.contentWidth - Spacing.sm * 2 - 88
        XCTAssertLessThanOrEqual(width(of: "East End Park", at: category), room)
    }

    // MARK: - The licence notice

    /// The notice is the dataset's own, kept rather than restated. If a
    /// rebuilt `courts.json` changes its source, the footer changes with it.
    func testTheCourtDataKeepsItsLicenceNotice() throws {
        let service = CourtService()
        try XCTSkipIf(service.courts.isEmpty, "courts.json not reachable from the test host")

        let attribution = try XCTUnwrap(service.attribution, "the dataset's attribution was dropped again")
        XCTAssertTrue(attribution.contains("OpenStreetMap"))
        XCTAssertTrue(attribution.contains("ODbL"))
    }

    func testTheNoticeLinksToOpenStreetMapsCopyrightPage() {
        XCTAssertEqual(CourtService.attributionURL.host(), "www.openstreetmap.org")
        XCTAssertEqual(CourtService.attributionURL.path(), "/copyright")
    }
}
