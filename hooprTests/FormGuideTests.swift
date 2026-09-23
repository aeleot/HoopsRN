import XCTest
import SwiftUI
import UIKit
@testable import hoopr

/// The form guide as five dots (2026-09-22): the padding that keeps the row
/// five long, what VoiceOver reads, and whether the row still sits beside the
/// record numeral on Seasons' band.
@MainActor
final class FormGuideTests: XCTestCase {

    // MARK: - Slots

    /// Two results and three grey dots. Played results come first, from the
    /// left, the most recent leftmost, as `SeasonGame.form` orders them.
    func testFewerThanFiveResultsArePaddedWithUnplayedSlots() {
        XCTAssertEqual(FormGuide.slots(for: [.win, .loss]), [.win, .loss, nil, nil, nil])
    }

    /// A squad that hasn't played shows five grey dots, not an empty row.
    func testNoResultsIsFiveUnplayedSlots() {
        XCTAssertEqual(FormGuide.slots(for: []), [nil, nil, nil, nil, nil])
    }

    func testFiveResultsFillEverySlot() {
        let form: [SeasonGame.Outcome] = [.win, .win, .loss, .win, .loss]
        XCTAssertEqual(FormGuide.slots(for: form), form.map { Optional($0) })
    }

    /// `SeasonGame.form` caps at five today, but the view doesn't rely on it.
    /// A longer list keeps its first five, which are the most recent.
    func testMoreThanFiveResultsKeepsTheMostRecentFive() {
        let form: [SeasonGame.Outcome] = [.loss, .win, .win, .win, .win, .loss, .loss]
        XCTAssertEqual(FormGuide.slots(for: form), [.loss, .win, .win, .win, .win])
    }

    // MARK: - Speech

    /// Only the played results are read. The grey slots are placeholders, and
    /// the record beside them already says how many games were played.
    func testVoiceOverReadsThePlayedResultsInOrder() {
        XCTAssertEqual(
            FormGuide.spokenForm([.win, .loss]),
            "Recent form, most recent first: win, loss"
        )
    }

    // MARK: - Fit beside the record

    /// The record line puts the dots beside the numeral when they fit and
    /// beneath it when they don't. These measure which one a reader gets. The
    /// numeral is uncapped (`HooprTextRole.numeral`), so the question is how
    /// wide a record can get at `.accessibility3` before the dots move under it.
    ///
    /// Default dots beside a double-digit record: fits (336pt of 362pt).
    func testTheDotsSitBesideADoubleDigitRecordThroughAccessibility3() {
        assertFitsBeside("10–10", dotDiameter: FormDotMetrics.diameter)
    }

    /// The larger dots *Differentiate Without Color* draws are 142pt. They sit
    /// beside a single-digit record at every size, and at `.accessibility3` a
    /// "10–10" pushes them beneath the numeral (366pt of 362pt, measured). That
    /// is the `ViewThatFits` fallback doing its job, pinned so nobody reads the
    /// stacked layout as a bug.
    func testMarkedDotsSitBesideASingleDigitRecordAndStackUnderALongOne() {
        assertFitsBeside("9–9", dotDiameter: FormDotMetrics.markedDiameter)
        XCTAssertGreaterThan(
            rowWidth("10–10", dotDiameter: FormDotMetrics.markedDiameter, at: .accessibilityExtraLarge),
            HomeHeroMetrics.contentWidth,
            "a double-digit record now fits beside the marked dots at .accessibility3; update the comment on SquadRecordLine"
        )
    }

    private func assertFitsBeside(_ record: String, dotDiameter: CGFloat, line: UInt = #line) {
        for category in [UIContentSizeCategory.large, .accessibilityExtraLarge] {
            let width = rowWidth(record, dotDiameter: dotDiameter, at: category)
            XCTAssertLessThanOrEqual(
                width, HomeHeroMetrics.contentWidth,
                "\"\(record)\" and \(dotDiameter)pt dots are \(width)pt at \(category.rawValue)",
                line: line
            )
        }
    }

    private func rowWidth(_ record: String, dotDiameter: CGFloat, at category: UIContentSizeCategory) -> CGFloat {
        let dots = CGFloat(FormGuide.length) * dotDiameter
            + CGFloat(FormGuide.length - 1) * FormDotMetrics.spacing
        return numeralWidth(record, at: category) + Spacing.lg + dots
    }

    private func numeralWidth(_ text: String, at category: UIContentSizeCategory) -> CGFloat {
        let role = HooprTextRole.numeral
        let size = HooprFontMetrics.scaledSize(role.size, maximumSize: role.maximumSize, at: category)
        let font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: role.uiFontWeight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}
