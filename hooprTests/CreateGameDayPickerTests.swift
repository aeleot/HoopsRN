import XCTest
@testable import hoopr

/// The create sheet's day chips: which days they offer, what picking one does
/// to the time, and what each says.
///
/// The sheet splits the tip-off into a day (a strip of chips) and a time (a
/// wheel), so picking a day has to keep the time — and has to land somewhere
/// `Game.validate` accepts when that time has already passed on the day
/// picked.
@MainActor
final class CreateGameDayPickerTests: XCTestCase {

    private let calendar = Calendar.current

    /// Wednesday 23 September 2026, 12:00 local.
    private var noon: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12))!
    }

    private func window(from now: Date) -> ClosedRange<Date> {
        now.addingTimeInterval(Game.minimumLeadTime) ... now.addingTimeInterval(Game.schedulingWindow)
    }

    private func at(_ hour: Int, _ minute: Int = 0, daysFrom base: Date, _ days: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: days, to: base)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    // MARK: - Which days

    /// Today through the last day of the window: 30 days on, so 31 chips.
    func testTheChipsRunFromTodayToTheLastDayTheRulesAllow() {
        let days = CreateGameViewModel.dayOptions(in: window(from: noon))

        XCTAssertEqual(days.count, 31)
        XCTAssertEqual(days.first, calendar.startOfDay(for: noon))
        XCTAssertEqual(days.last, calendar.startOfDay(for: noon.addingTimeInterval(Game.schedulingWindow)))
    }

    /// At 11:57 PM the earliest tip-off is tomorrow, so today has no chip.
    func testTodayHasNoChipWhenNoTipOffIsLeftInIt() {
        let lateNight = at(23, 57, daysFrom: noon)
        let days = CreateGameViewModel.dayOptions(in: window(from: lateNight))

        XCTAssertEqual(days.first, calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: noon)!))
    }

    // MARK: - Picking a day

    /// Moving a 7:30 PM run to Saturday keeps 7:30 PM.
    func testPickingADayKeepsTheTime() {
        let picked = CreateGameViewModel.tipOff(
            on: calendar.startOfDay(for: at(0, daysFrom: noon, 3)),
            keepingTimeOf: at(19, 30, daysFrom: noon),
            within: window(from: noon)
        )
        XCTAssertEqual(picked, at(19, 30, daysFrom: noon, 3))
    }

    /// A 9 AM run moved to today, at noon, can't be at 9 AM: it becomes the
    /// next quarter hour the rules allow — 12:15 PM — still today.
    func testATimeAlreadyPastTodayBecomesTheNextQuarterHour() {
        let picked = CreateGameViewModel.tipOff(
            on: calendar.startOfDay(for: noon),
            keepingTimeOf: at(9, daysFrom: noon, 1),
            within: window(from: noon)
        )
        XCTAssertEqual(picked, at(12, 15, daysFrom: noon))
        XCTAssertNil(Game.validate(courtId: "c", scheduledTime: picked, maxPlayers: 10, now: noon))
    }

    /// On the last day, a time past the end of the window becomes its end.
    func testATimePastTheWindowBecomesItsEnd() {
        let range = window(from: noon)
        let picked = CreateGameViewModel.tipOff(
            on: calendar.startOfDay(for: range.upperBound),
            keepingTimeOf: at(19, daysFrom: noon),
            within: range
        )
        XCTAssertEqual(picked, range.upperBound)
    }

    // MARK: - What a chip says

    func testTodaysChipSaysToday() {
        let text = CreateGameViewModel.dayChipText(for: calendar.startOfDay(for: noon), now: noon)

        XCTAssertEqual(text.weekday, "Today")
        XCTAssertEqual(text.number, "23")
        XCTAssertTrue(text.spoken.hasPrefix("Today, Wednesday"), text.spoken)
    }

    func testAnotherDaysChipSaysItsWeekday() {
        let text = CreateGameViewModel.dayChipText(for: at(0, daysFrom: noon, 1), now: noon)

        XCTAssertEqual(text.weekday, "Thu")
        XCTAssertEqual(text.number, "24")
        XCTAssertEqual(text.spoken, "Thursday, September 24")
    }
}
