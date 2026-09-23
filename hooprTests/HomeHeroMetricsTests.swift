import XCTest
import SwiftUI
import UIKit
@testable import hoopr

/// Measures Home's hero against the data it actually has to render.
///
/// **Written because a two-line cap looked correct in a screenshot and was
/// wrong.** The redesigned band sets the court name in the `title` role, which
/// `UIFontMetrics` takes from 28pt to 47pt at `.accessibility3`. The screen
/// captured for evidence showed "East End Park" — thirteen characters, one
/// line, fits — while five courts in the shipped dataset need three or four.
/// A `.lineLimit(2)` truncated those silently, and no screenshot would have
/// shown it unless one of those courts happened to be the next run.
///
/// So the cap is asserted against the whole dataset rather than against the
/// example. This is the `ResultPillMetrics` / `SeasonsAccessibilityTests`
/// pattern: the number a layout depends on is measured, not eyeballed.
@MainActor
final class HomeHeroMetricsTests: XCTestCase {

    private let axl = UIContentSizeCategory.accessibilityExtraLarge

    private func bundledCourtNames() throws -> [String] {
        let names = CourtService().courts.map(\.displayName)
        try XCTSkipIf(names.isEmpty, "courts.json not reachable from the test host")
        return names
    }

    // MARK: - The cap

    /// The guard itself. If someone reintroduces a finite line limit to make
    /// the band tidier, this is what tells them which courts it would cut.
    func testNoCourtInTheDatasetIsTruncatedByTheBandsLineLimit() throws {
        guard let limit = HomeHeroMetrics.courtNameLineLimit else {
            return // nil means it reflows — nothing can be truncated
        }

        let offenders = try bundledCourtNames()
            .map { ($0, HomeHeroMetrics.lineCount(of: $0, role: .title, at: axl)) }
            .filter { $0.1 > limit }

        XCTAssertTrue(
            offenders.isEmpty,
            "lineLimit(\(limit)) truncates \(offenders.count) courts at .accessibility3, "
            + "worst: \(offenders.max(by: { $0.1 < $1.1 })!)"
        )
    }

    /// And the reason the cap is `nil` rather than a larger number: the worst
    /// case is genuinely long, so any cap tidy enough to be worth setting is
    /// one that cuts a real court.
    func testTheDatasetContainsNamesTooLongForTwoLines() throws {
        let worst = try bundledCourtNames()
            .map { ($0, HomeHeroMetrics.lineCount(of: $0, role: .title, at: axl)) }
            .max { $0.1 < $1.1 }!

        XCTAssertGreaterThan(
            worst.1, 2,
            "if the longest court now fits two lines, the cap could come back — but check the dataset first"
        )
    }

    /// A short name still takes one line, so the band isn't paying for the
    /// worst case in the common one.
    func testATypicalCourtNameIsOneLineEvenAtAccessibilitySizes() {
        XCTAssertEqual(HomeHeroMetrics.lineCount(of: "East End Park", role: .title, at: axl), 1)
    }

    // MARK: - The numeral

    /// The hero itself. A time string is short, but at 65.3pt it is not
    /// *arbitrarily* short — this pins that the widest one the formatter can
    /// produce still takes a single line, because the band gives it
    /// `lineLimit(1)` and a wrap there would look like a bug rather than a
    /// reflow.
    func testTheHeroTimeFitsOneLineAtEveryTextSize() {
        let widest = "12:45 PM"

        for category in [UIContentSizeCategory.large, axl, .accessibilityExtraExtraExtraLarge] {
            XCTAssertEqual(
                HomeHeroMetrics.lineCount(of: widest, role: .numeral, at: category), 1,
                "the hero time wrapped at \(category.rawValue)"
            )
        }
    }

    /// The empty state's answer is words, not a number, and it is allowed to
    /// wrap — this just pins that it wraps rather than needing a cap.
    func testTheEmptyAnswerReflowsWithinTwoLines() {
        let lines = HomeHeroMetrics.lineCount(of: "Nothing on tonight", role: .display, at: axl)
        XCTAssertLessThanOrEqual(lines, 2)
    }

    // MARK: - The measurement itself

    /// `lineCount` has to describe what the screen draws, so it resolves its
    /// font through the same metrics the modifier does.
    func testMeasurementUsesTheSameScaledSizeAsTheModifier() {
        let expected = HooprFontMetrics.scaledSize(HooprTextRole.title.size, at: axl)
        XCTAssertEqual(expected, 47.0, accuracy: 0.05)

        // Twice the width should never need more lines than half of it.
        let narrow = HomeHeroMetrics.lineCount(
            of: "Saint Thomas More Academy High School Campus",
            role: .title, width: HomeHeroMetrics.contentWidth / 2, at: axl
        )
        let wide = HomeHeroMetrics.lineCount(
            of: "Saint Thomas More Academy High School Campus",
            role: .title, width: HomeHeroMetrics.contentWidth, at: axl
        )
        XCTAssertGreaterThan(narrow, wide)
    }

    /// Every role's `uiFontWeight` matches its `weight`, or a measurement is
    /// describing text the app doesn't draw.
    func testEveryRoleBridgesItsWeightFaithfully() {
        let expected: [HooprTextRole: UIFont.Weight] = [
            .numeral: .bold, .display: .bold, .title: .bold, .label: .bold, .badge: .bold,
            .headline: .semibold, .subhead: .semibold,
            .body: .regular, .caption: .regular,
        ]

        for role in HooprTextRole.allCases {
            XCTAssertEqual(role.uiFontWeight, expected[role], "\(role)")
        }
    }
}
