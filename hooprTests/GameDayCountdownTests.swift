import XCTest
@testable import hoopr

/// Game day's band headline — the countdown as a label over a numeral — and
/// the arrival board's count.
///
/// The windows are the ones the old one-line headline used, and the ones the
/// T-0 and T+90 notifications describe, so the screen and the notification
/// that pointed at it can't disagree. Every boundary is pinned here because
/// none of them can be reached on one device without a live match.
final class GameDayCountdownTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func headline(in seconds: TimeInterval, cancelled: Bool = false) -> GameDayCountdown.Headline {
        GameDayCountdown.headline(
            scheduled: now.addingTimeInterval(seconds),
            now: now,
            isCancelled: cancelled
        )
    }

    // MARK: - Counting down

    func testMinutesOut() {
        let h = headline(in: 42 * 60 + 30)
        XCTAssertEqual(h.label, "Tip-off in")
        XCTAssertEqual(h.value, "42m")
        XCTAssertEqual(h.spoken, "Tip-off in 42 minutes")
    }

    func testHoursAndMinutesOut() {
        XCTAssertEqual(headline(in: (60 + 42) * 60).value, "1h 42m")
        XCTAssertEqual(headline(in: (60 + 42) * 60).spoken, "Tip-off in 1 hour 42 minutes")
    }

    /// "1h", not the "1h 0m" the old headline produced on the hour.
    func testAZeroSecondUnitIsDropped() {
        XCTAssertEqual(headline(in: 60 * 60).value, "1h")
        XCTAssertEqual(headline(in: 2 * 24 * 60 * 60).value, "2d")
    }

    /// A match booked for tomorrow evening reads in days and hours, not
    /// "26h 5m".
    func testMoreThanADayOutReadsInDays() {
        let h = headline(in: (26 * 60 + 5) * 60)
        XCTAssertEqual(h.value, "1d 2h")
        XCTAssertEqual(h.spoken, "Tip-off in 1 day 2 hours")
    }

    /// Singular at one, so VoiceOver never says "1 minutes".
    func testOneUnitIsSingular() {
        XCTAssertEqual(headline(in: 90).spoken, "Tip-off in 1 minute")
    }

    // MARK: - The windows

    /// Inside the last minute it's tip-off, not "0m".
    func testTheLastMinuteIsNow() {
        XCTAssertEqual(headline(in: 60).value, "Now")
        XCTAssertEqual(headline(in: 59).value, "Now")
    }

    /// "Now" holds until the reporting delay has passed — the same T+90 the
    /// "Record the result" notification fires at.
    func testNowHoldsUntilTheReportingDelay() {
        XCTAssertEqual(headline(in: -30 * 60).value, "Now")
        XCTAssertEqual(headline(in: -SeasonGame.reportingDelay + 1).value, "Now")
        XCTAssertEqual(headline(in: -SeasonGame.reportingDelay).value, "Final")
    }

    /// Cancelled outranks every window: a called-off match never counts down.
    func testCancelledOutranksTheCountdown() {
        for seconds in [3600.0, 0, -SeasonGame.reportingDelay * 2] {
            let h = headline(in: seconds, cancelled: true)
            XCTAssertEqual(h.value, "Cancelled")
            XCTAssertEqual(h.spoken, "This match was cancelled")
        }
    }

    // MARK: - The arrival count

    func testTheBoardCountsOnlyThisRostersArrivals() {
        let rows = ["a", "b", "c"].map {
            SquadViewModel.MemberRow(uid: $0, profile: nil, isLeader: $0 == "a")
        }
        // "z" is on the other squad; it must not count here.
        let side = ArrivalBoard.Side(name: "Your squad", rows: rows, arrivedUids: ["a", "c", "z"])
        XCTAssertEqual(side.arrivedCount, 2)
    }
}
