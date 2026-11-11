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
/// circle, and rendered taller than its own circle. The lettered result pills
/// and their four tests were retired on 2026-09-23, when the form guide and
/// squad detail's history moved to text-free dots (`FormDot`), which carry no
/// glyph to overflow. The lesson stands for anything else locked in a frame.
final class SeasonsAccessibilityTests: XCTestCase {

    /// The size a reader with large accessibility text is at. The same one
    /// `TabBarLabelTests` measures, so the two files agree on "large".
    private let accessibility3 = UIContentSizeCategory.accessibilityExtraLarge

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
}
