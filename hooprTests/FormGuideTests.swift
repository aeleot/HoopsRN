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
    /// Default dots, with "L5", beside a single-digit record: fits at every
    /// size (282pt of 362pt at `.accessibility3`).
    func testTheDotsSitBesideASingleDigitRecordThroughAccessibility3() {
        assertFitsBeside((9, 9), dotDiameter: FormDotMetrics.diameter)
    }

    /// And beside a double-digit record at the default size (297pt of 362pt)
    /// — but not at `.accessibility3`, where "L5" costs the fit this row used
    /// to have (367pt of 362pt, measured). The `ViewThatFits` fallback moves
    /// the row beneath the numeral, pinned so nobody reads that as a bug.
    func testTheDotsSitBesideADoubleDigitRecordAndStackUnderItAtAccessibility3() {
        XCTAssertLessThanOrEqual(
            rowWidth((10, 10), dotDiameter: FormDotMetrics.diameter, at: .large),
            HomeHeroMetrics.contentWidth
        )
        XCTAssertGreaterThan(
            rowWidth((10, 10), dotDiameter: FormDotMetrics.diameter, at: .accessibilityExtraLarge),
            HomeHeroMetrics.contentWidth,
            "a double-digit record now fits beside the dots at .accessibility3; update the comment on SquadRecordLine"
        )
    }

    /// The larger dots *Differentiate Without Color* draws are 142pt. They sit
    /// beside a single-digit record at every size, and at `.accessibility3` a
    /// "10–10" pushes them beneath the numeral (397pt of 362pt, measured).
    func testMarkedDotsSitBesideASingleDigitRecordAndStackUnderALongOne() {
        assertFitsBeside((9, 9), dotDiameter: FormDotMetrics.markedDiameter)
        XCTAssertGreaterThan(
            rowWidth((10, 10), dotDiameter: FormDotMetrics.markedDiameter, at: .accessibilityExtraLarge),
            HomeHeroMetrics.contentWidth,
            "a double-digit record now fits beside the marked dots at .accessibility3; update the comment on SquadRecordLine"
        )
    }

    private typealias Record = (wins: Int, losses: Int)

    private func assertFitsBeside(_ record: Record, dotDiameter: CGFloat, line: UInt = #line) {
        for category in [UIContentSizeCategory.large, .accessibilityExtraLarge] {
            let width = rowWidth(record, dotDiameter: dotDiameter, at: category)
            XCTAssertLessThanOrEqual(
                width, HomeHeroMetrics.contentWidth,
                "\(record.wins)–\(record.losses) and \(dotDiameter)pt dots are \(width)pt at \(category.rawValue)",
                line: line
            )
        }
    }

    private func rowWidth(_ record: Record, dotDiameter: CGFloat, at category: UIContentSizeCategory) -> CGFloat {
        let dots = CGFloat(FormGuide.length) * dotDiameter
            + CGFloat(FormGuide.length - 1) * FormDotMetrics.spacing
        let caption = captionWidth(at: category) + FormDotMetrics.captionSpacing
        return numeralWidth(record, at: category) + Spacing.lg + caption + dots
    }

    /// "L5" as `FormGuide` draws it: the label role, capped, with its kerning.
    private func captionWidth(at category: UIContentSizeCategory) -> CGFloat {
        let role = HooprTextRole.label
        let size = HooprFontMetrics.scaledSize(role.size, maximumSize: role.maximumSize, at: category)
        let text = NSAttributedString(string: FormGuide.caption, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: role.uiFontWeight),
            .kern: role.kerning,
        ])
        return ceil(text.size().width)
    }

    /// The numeral as `SquadRecordLine` draws it: digits and spaces at the
    /// numeral role, the dash at `RecordDash`'s smaller size and lighter weight.
    private func numeralWidth(_ record: Record, at category: UIContentSizeCategory) -> CGFloat {
        typealias Dash = SquadRecordLine.RecordDash
        let role = HooprTextRole.numeral
        let size = HooprFontMetrics.scaledSize(role.size, maximumSize: role.maximumSize, at: category)
        let digits: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: size, weight: role.uiFontWeight),
        ]
        let text = NSMutableAttributedString(string: "\(record.wins)\(Dash.space)", attributes: digits)
        text.append(NSAttributedString(
            string: Dash.glyph,
            attributes: [.font: UIFont.systemFont(ofSize: size * Dash.scale, weight: Dash.uiFontWeight)]
        ))
        text.append(NSAttributedString(string: "\(Dash.space)\(record.losses)", attributes: digits))
        return ceil(text.size().width)
    }
}
