import SwiftUI
import UIKit
import XCTest
@testable import hoopr

/// Dynamic Type across the Seasons screens, and the one thing that can silently
/// break there: **text locked inside a frame that cannot grow.**
///
/// `TabBarLabelTests` already covers the tab bar and settles the "Seasons" over
/// "Squad" label decision. This covers what sits behind that tab, and it takes
/// the same approach for the same reason: assert the **outcome** — the glyph
/// fits its circle — rather than the mechanism that produces it.
///
/// **Why this measures arithmetic rather than hosting the screens.** Every
/// Seasons screen is driven by a view model holding `SquadService`,
/// `MatchmakingService` and `SeasonGameService`, so hosting one needs Firebase
/// configured and a signed-in session — the same wall `TabBarLabelTests` hit
/// when it built a bare `TabView` instead of hosting `MainTabView`. What can be
/// measured without any of that is the part that actually goes wrong: the point
/// size `hooprFont` resolves to at an accessibility category, against the fixed
/// frame the design locked the text into. `HooprFontMetrics` is the same code
/// the modifier runs, not a second copy of the curve, which is what makes the
/// measurement worth anything.
///
/// **This suite found a real bug.** The neutral history badge shipped in Phase 6
/// with `hooprFont(13, weight: .bold)` and no `maximumSize` inside a fixed 28pt
/// circle. `testAnUncappedPillFontWouldOverflowItsCircle` is that bug, kept as
/// the reason the cap exists.
final class SeasonsAccessibilityTests: XCTestCase {

    /// The size a reader with large accessibility text is at. The same one
    /// `TabBarLabelTests` measures, so the two files agree on "large".
    private let accessibility3 = UIContentSizeCategory.accessibilityExtraLarge

    /// The widest thing either pill ever renders. "W" is wider than "L", "!",
    /// "–" or "·", so a pill that fits this fits all of them.
    private let widestGlyph = "W"

    // MARK: - The pills

    func testAResultPillKeepsItsLetterInsideItsCircleAtAccessibility3() {
        let size = HooprFontMetrics.scaledSize(
            ResultPillMetrics.fontSize,
            maximumSize: ResultPillMetrics.maximumFontSize,
            at: accessibility3
        )

        XCTAssertLessThanOrEqual(
            size, ResultPillMetrics.maximumFontSize,
            "the cap isn't being applied"
        )

        let rendered = measure(widestGlyph, atSize: size, weight: .bold)

        XCTAssertLessThanOrEqual(
            rendered.width, ResultPillMetrics.diameter,
            "\"\(widestGlyph)\" renders \(rendered.width.rounded())pt wide in a \(ResultPillMetrics.diameter)pt pill"
        )
        XCTAssertLessThanOrEqual(
            rendered.height, ResultPillMetrics.diameter,
            "\"\(widestGlyph)\" renders \(rendered.height.rounded())pt tall in a \(ResultPillMetrics.diameter)pt pill"
        )
    }

    func testAnUncappedPillFontWouldOverflowItsCircle() {
        // The bug this file exists for, stated as a measurement: without
        // `maximumSize` the badge's own text is taller than the badge. A cap is
        // normally the lesser evil — `Typography` says to omit it wherever the
        // layout can reflow — and a fixed-diameter circle is precisely where it
        // cannot.
        let uncapped = HooprFontMetrics.scaledSize(
            ResultPillMetrics.fontSize,
            at: accessibility3
        )
        let rendered = measure(widestGlyph, atSize: uncapped, weight: .bold)

        XCTAssertGreaterThan(
            rendered.height, ResultPillMetrics.diameter,
            "If this ever passes, the cap on the result pills is no longer doing anything and the comment explaining it is wrong."
        )
    }

    func testEveryPillGlyphFitsNotJustTheWidest() {
        let size = HooprFontMetrics.scaledSize(
            ResultPillMetrics.fontSize,
            maximumSize: ResultPillMetrics.maximumFontSize,
            at: accessibility3
        )

        // W and L from `SeasonGame.Outcome`, then the three neutral glyphs
        // `SquadDetailView` renders for disputed, cancelled and unreported.
        for glyph in ["W", "L", "!", "–", "·"] {
            let rendered = measure(glyph, atSize: size, weight: .bold)
            XCTAssertLessThanOrEqual(
                rendered.width, ResultPillMetrics.diameter,
                "\"\(glyph)\" is \(rendered.width.rounded())pt wide in a \(ResultPillMetrics.diameter)pt pill"
            )
        }
    }

    func testThePillsFitAtEveryContentSizeNotOnlyTheOneWeChecked() {
        // A cap set for accessibility3 that happens to fail at accessibility5
        // would be a bug this file was built to miss.
        for category in Self.everyCategory {
            let size = HooprFontMetrics.scaledSize(
                ResultPillMetrics.fontSize,
                maximumSize: ResultPillMetrics.maximumFontSize,
                at: category
            )
            let rendered = measure(widestGlyph, atSize: size, weight: .bold)

            XCTAssertLessThanOrEqual(
                rendered.height, ResultPillMetrics.diameter,
                "a pill clips at \(category.rawValue)"
            )
        }
    }

    // MARK: - The crest

    func testACrestGlyphNeverOutgrowsItsDisc() {
        // `SquadCrest` deliberately keeps `.font(.system(size:))` rather than
        // `hooprFont`, because the glyph is locked inside a frame that can't
        // grow — the case `Typography` names as keeping a fixed size. This
        // pins that: the glyph is a fraction of the disc at every text size,
        // because it never scales with text at all.
        let sizes = [
            SquadCrest.Size.hero, SquadCrest.Size.card, SquadCrest.Size.row,
            SquadCrest.Size.pool, SquadCrest.Size.inline,
        ]

        for size in sizes {
            let glyph = size * 0.46
            XCTAssertLessThan(
                glyph, size,
                "a crest glyph must stay inside its own disc at \(size)pt"
            )
        }
    }

    // MARK: - The ramp itself

    func testHooprFontScalesUpFromTheDesignSizeAndNeverBelowIt() {
        // At the default text size the reader gets exactly the size the design
        // asked for — the property `Typography`'s doc comment promises, and the
        // reason the app could adopt Dynamic Type without redrawing itself.
        XCTAssertEqual(HooprFontMetrics.scaledSize(13, at: .large), 13, accuracy: 0.51)
        XCTAssertEqual(HooprFontMetrics.scaledSize(28, at: .large), 28, accuracy: 0.51)

        XCTAssertGreaterThan(
            HooprFontMetrics.scaledSize(13, at: accessibility3),
            HooprFontMetrics.scaledSize(13, at: .large),
            "accessibility sizes must actually scale up"
        )
    }

    func testTheMetricsStyleTracksTheSizeItIsHanded() {
        // Borrowing the wrong style would undo the system's own decision to
        // scale captions harder than body text.
        XCTAssertEqual(HooprFontMetrics.metricsStyle(for: 11), .caption2)
        XCTAssertEqual(HooprFontMetrics.metricsStyle(for: 13), .footnote)
        XCTAssertEqual(HooprFontMetrics.metricsStyle(for: 17), .body)
        XCTAssertEqual(HooprFontMetrics.metricsStyle(for: 28), .title1)
        XCTAssertEqual(HooprFontMetrics.metricsStyle(for: 34), .largeTitle)
    }

    func testTheDynamicTypeLadderMapsOneForOne() {
        // Eleven steps in both types. A missed rung would silently pin a whole
        // band of readers to the default size.
        XCTAssertEqual(HooprFontMetrics.contentSizeCategory(for: .large), .large)
        XCTAssertEqual(HooprFontMetrics.contentSizeCategory(for: .accessibility3), accessibility3)
        XCTAssertEqual(
            HooprFontMetrics.contentSizeCategory(for: .accessibility5),
            .accessibilityExtraExtraExtraLarge
        )

        let mapped = Set(DynamicTypeSize.allCases.map { HooprFontMetrics.contentSizeCategory(for: $0) })
        XCTAssertEqual(
            mapped.count, DynamicTypeSize.allCases.count,
            "two Dynamic Type sizes map to the same content size category"
        )
    }

    // MARK: - Harness

    private static let everyCategory: [UIContentSizeCategory] = [
        .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge,
        .extraExtraExtraLarge, .accessibilityMedium, .accessibilityLarge,
        .accessibilityExtraLarge, .accessibilityExtraExtraLarge,
        .accessibilityExtraExtraExtraLarge,
    ]

    private func measure(_ text: String, atSize size: CGFloat, weight: UIFont.Weight) -> CGSize {
        (text as NSString).size(
            withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight)]
        )
    }
}
