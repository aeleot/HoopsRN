import XCTest
import UIKit
@testable import hoopr

/// Pins `HomeViewModel.rankHotCourts`, the one piece of derived logic on the
/// Home tab.
///
/// Worth pinning because two of its rules are invisible until they break in
/// production: a `[String: Int]` has no stable iteration order, so without the
/// name tie-break the hot list silently reshuffles itself between rebuilds
/// while showing identical numbers; and a court with no games has to be absent
/// rather than a zero, or "hot right now" fills up with cold courts the moment
/// a city is quiet.
///
/// Pure and `nonisolated`, so none of this needs a service or Firebase — the
/// same shape `FindAMatchViewModelTests` uses for `gameCountsByCourt`.
final class HomeViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private func court(_ id: String, name: String, city: String = "Durham") -> Court {
        Court(
            id: id,
            name: name,
            latitude: 35.99,
            longitude: -78.90,
            address: "1 Test Way",
            city: city,
            hoops: 2,
            surface: nil,
            isLit: nil,
            isCovered: nil,
            access: .public,
            osmType: nil,
            osmId: nil
        )
    }

    // MARK: - The stats card

    /// "1 wk", not "1 wks" — which is what the card said before 2026-09-22.
    func testTheStreakIsSingularAtOneWeek() {
        XCTAssertEqual(StatsCard.streakText(weeks: 1), "1 wk")
        XCTAssertEqual(StatsCard.streakText(weeks: 3), "3 wks")
        XCTAssertEqual(StatsCard.streakText(weeks: 0), "0 wks")
    }

    /// VoiceOver reads "wk" as letters, so the spoken form spells it out.
    func testTheSpokenStreakSpellsOutWeeks() {
        XCTAssertEqual(StatsCard.spokenStreak(weeks: 1), "1 week streak")
        XCTAssertEqual(StatsCard.spokenStreak(weeks: 4), "4 week streak")
    }

    /// The three stats, in the order and with the icons the card has always
    /// had — the redesign briefly cut them to a sentence, and the user noticed
    /// the icons were gone.
    @MainActor
    func testTheCardCarriesItsThreeStatsWithTheirIcons() {
        let card = StatsCard(completedCount: 2, participationStreak: 1, lastCompletedText: "Yesterday")

        XCTAssertEqual(card.stats.map(\.label), ["Runs", "Streak", "Last Run"])
        XCTAssertEqual(card.stats.map(\.value), ["2", "1 wk", "Yesterday"])
        XCTAssertEqual(card.stats.map(\.symbol), ["basketball.fill", "flame.fill", "clock.fill"])
        XCTAssertEqual(card.stats.map(\.spoken), ["2 runs", "1 week streak", "last run yesterday"])
    }

    // MARK: - The card cannot break mid-word

    /// **The row is used wherever it fits, which is up to `.xxxLarge`.** The
    /// old card gave each stat an equal third — 93pt at the default size, when
    /// "Yesterday" needs 92, and 116 one step up — which is how it came to
    /// break "Last / Run" mid-word. The columns now hug their content, so the
    /// question is only whether the *sum* fits.
    func testTheStatsRowFitsThroughTheLargestNonAccessibilitySize() {
        for category in [UIContentSizeCategory.large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge] {
            XCTAssertLessThanOrEqual(
                StatsCardMetrics.rowWidth(at: category), StatsCardMetrics.innerWidth,
                "the row should still fit at \(category.rawValue)"
            )
        }
    }

    /// And from the first accessibility size it can't, so `ViewThatFits`
    /// stacks it. If this ever stops being true the stack is unreachable, and
    /// the only thing left guarding the words is luck.
    func testTheStatsCardStacksAtAccessibilitySizes() {
        XCTAssertGreaterThan(
            StatsCardMetrics.rowWidth(at: .accessibilityMedium), StatsCardMetrics.innerWidth
        )
    }

    /// In the stack each value has the card's whole width, and even the widest
    /// one at the largest text size fits it on one line — so there is no size
    /// at which a stat has to break inside a word.
    func testEveryStatFitsOnOneLineInTheStackAtEverySize() {
        for category in [UIContentSizeCategory.accessibilityExtraLarge, .accessibilityExtraExtraExtraLarge] {
            for column in StatsCardMetrics.worstCase {
                XCTAssertLessThanOrEqual(
                    StatsCardMetrics.width(of: column.value, role: .headline, at: category),
                    StatsCardMetrics.innerWidth,
                    "\"\(column.value)\" would have to break at \(category.rawValue)"
                )
            }
        }
    }

    // MARK: - Ranking

    func testOrdersByGameCountDescending() {
        let courts = [
            court("a", name: "Alpha"),
            court("b", name: "Bravo"),
            court("c", name: "Charlie"),
        ]

        let ranked = HomeViewModel.rankHotCourts(
            counts: ["a": 1, "b": 5, "c": 3],
            courts: courts,
            limit: 3
        )

        XCTAssertEqual(ranked.map(\.court.id), ["b", "c", "a"])
        XCTAssertEqual(ranked.map(\.gameCount), [5, 3, 1])
    }

    /// The rule that keeps the list from reshuffling between rebuilds.
    func testTiesBreakOnDisplayNameSoOrderIsStable() {
        let courts = [
            court("z", name: "Zulu"),
            court("a", name: "Alpha"),
            court("m", name: "Mike"),
        ]
        let counts = ["z": 2, "a": 2, "m": 2]

        let first = HomeViewModel.rankHotCourts(counts: counts, courts: courts, limit: 3)
        XCTAssertEqual(first.map(\.court.id), ["a", "m", "z"])

        // Same inputs in a different order must produce the same output — a
        // dictionary's iteration order is not guaranteed between runs.
        let reversed = HomeViewModel.rankHotCourts(
            counts: counts,
            courts: courts.reversed(),
            limit: 3
        )
        XCTAssertEqual(reversed.map(\.court.id), ["a", "m", "z"])
    }

    /// Ties break on `displayName`, not the stored `name` — the dataset's
    /// "Basketball Court" boilerplate would otherwise sort courts by a string
    /// the user never sees.
    func testTieBreakUsesDisplayNameNotStoredName() {
        let courts = [
            court("first", name: "Basketball Court Alpha"),
            court("second", name: "Basketball Court Zulu"),
        ]

        let ranked = HomeViewModel.rankHotCourts(
            counts: ["first": 1, "second": 1],
            courts: courts,
            limit: 2
        )

        XCTAssertEqual(
            ranked.map(\.court.displayName),
            courts.map(\.displayName).sorted(),
            "the tie-break must agree with what the row actually renders"
        )
    }

    func testCourtsWithNoGamesAreAbsentRatherThanZero() {
        let courts = [court("a", name: "Alpha"), court("b", name: "Bravo")]

        let ranked = HomeViewModel.rankHotCourts(
            counts: ["a": 2],
            courts: courts,
            limit: 3
        )

        XCTAssertEqual(ranked.map(\.court.id), ["a"])
    }

    /// A count of zero is as good as absent — neither is "hot".
    func testAnExplicitZeroCountIsDroppedToo() {
        let ranked = HomeViewModel.rankHotCourts(
            counts: ["a": 0],
            courts: [court("a", name: "Alpha")],
            limit: 3
        )

        XCTAssertTrue(ranked.isEmpty)
    }

    func testHonoursTheLimit() {
        let courts = (1...10).map { court("c\($0)", name: "Court \($0)") }
        let counts = Dictionary(uniqueKeysWithValues: courts.map { ($0.id, 1) })

        let ranked = HomeViewModel.rankHotCourts(counts: counts, courts: courts, limit: 3)

        XCTAssertEqual(ranked.count, 3)
    }

    /// Guards the `limit > 0` early return — a non-positive limit must produce
    /// an empty list rather than trapping in `prefix`.
    func testANonPositiveLimitYieldsNothing() {
        let courts = [court("a", name: "Alpha")]

        XCTAssertTrue(HomeViewModel.rankHotCourts(counts: ["a": 3], courts: courts, limit: 0).isEmpty)
        XCTAssertTrue(HomeViewModel.rankHotCourts(counts: ["a": 3], courts: courts, limit: -1).isEmpty)
    }

    /// A count for a court that isn't in the dataset can't be rendered, so it
    /// must be skipped rather than crashing the ranking.
    func testCountsForUnknownCourtsAreIgnored() {
        let ranked = HomeViewModel.rankHotCourts(
            counts: ["ghost": 9, "a": 1],
            courts: [court("a", name: "Alpha")],
            limit: 3
        )

        XCTAssertEqual(ranked.map(\.court.id), ["a"])
    }

    func testAnEmptyDatasetYieldsNothing() {
        XCTAssertTrue(HomeViewModel.rankHotCourts(counts: ["a": 4], courts: [], limit: 3).isEmpty)
    }

    /// The Home tab shows three. Pinned so a change to the constant is a
    /// deliberate edit here rather than a silent layout shift.
    func testHotCourtLimitIsThree() {
        XCTAssertEqual(HomeViewModel.hotCourtLimit, 3)
    }

    // MARK: - lastCompletedText

    /// Same shape as the `rankHotCourts` tests above: pure function, no
    /// service construction. Dates are computed off the real `Date()` rather
    /// than hardcoded literals, because `lastCompletedText` resolves
    /// "today"/"yesterday" via `Calendar.isDateInToday`/`isDateInYesterday`,
    /// which compare against the actual current date regardless of the
    /// `relativeTo` argument — see the note in the report-back for why that
    /// parameter doesn't make the relative cases independently testable.
    private func expectedMonthDay(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }

    /// The lazy-init / brand-new-account default.
    func testNilDateReturnsEmDash() {
        XCTAssertEqual(HomeViewModel.lastCompletedText(for: nil), "—")
    }

    func testTodayReturnsToday() {
        XCTAssertEqual(HomeViewModel.lastCompletedText(for: Date()), "Today")
    }

    func testYesterdayReturnsYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        XCTAssertEqual(HomeViewModel.lastCompletedText(for: yesterday), "Yesterday")
    }

    /// The boundary between the two relative cases and the absolute fallback.
    func testTwoDaysAgoReturnsFormattedDateNotTodayOrYesterday() {
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        XCTAssertEqual(HomeViewModel.lastCompletedText(for: twoDaysAgo), expectedMonthDay(for: twoDaysAgo))
    }

    /// Pins the deliberate no-year simplification so it can't drift in silently.
    func testOverAYearAgoStillOmitsTheYear() {
        let overAYearAgo = Calendar.current.date(byAdding: .day, value: -400, to: Date())!
        let text = HomeViewModel.lastCompletedText(for: overAYearAgo)

        XCTAssertEqual(text, expectedMonthDay(for: overAYearAgo))
        XCTAssertFalse(text.contains(String(Calendar.current.component(.year, from: overAYearAgo))))
    }
}
