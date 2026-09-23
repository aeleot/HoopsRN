import XCTest
@testable import hoopr

/// What a row in squad detail's game history says, from one squad's side.
///
/// Pure (`SquadHistoryRow`'s `nonisolated static` helpers), so every status is
/// covered without a view. The two rules that matter most here are the ones
/// the screen can't show on a single device:
/// - a match nobody confirmed never looks like a loss (grey dot, not red);
/// - a match awaiting the other leader never implies a deadline, because it
///   waits forever (`gaps/SEASONS.md`).
final class SquadHistoryRowTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let home = "squad-home"
    private let away = "squad-away"

    private func game(
        status: SeasonGame.Status = .scheduled,
        result: String? = nil,
        scheduledOffset: TimeInterval = -3600,
        homeReport: String? = nil,
        awayReport: String? = nil,
        homeScore: Int? = nil,
        awayScore: Int? = nil
    ) -> SeasonGame {
        SeasonGame(
            id: "game-1",
            format: .threeVThree,
            region: "Durham",
            homeSquadId: home,
            awaySquadId: away,
            squadIds: [home, away],
            homeLeaderId: "leader-home",
            awayLeaderId: "leader-away",
            homeSquadName: "Rim Reapers",
            awaySquadName: "Court Vision",
            courtId: "court-1",
            scheduledTime: now.addingTimeInterval(scheduledOffset),
            status: status,
            arrivedPlayerIds: [],
            homeReport: homeReport,
            awayReport: awayReport,
            homeScore: homeScore,
            awayScore: awayScore,
            result: result,
            cancelledBySquadId: nil,
            createdBy: "leader-away",
            createdAt: nil,
            updatedAt: nil,
            confirmedAt: nil
        )
    }

    private func status(_ game: SeasonGame, uid: String? = "leader-home") -> (text: String, isCallToAction: Bool) {
        SquadHistoryRow.status(for: game, squadId: home, uid: uid, now: now)
    }

    // MARK: - Confirmed

    /// The word, not just the colour: the band's dots rely on colour, and this
    /// list is where the result is spelled out.
    func testAConfirmedResultIsAWordFromThisSquadsSide() {
        let won = game(status: .confirmed, result: home, homeReport: home, awayReport: home)
        let lost = game(status: .confirmed, result: away, homeReport: away, awayReport: away)

        XCTAssertEqual(status(won).text, "Won")
        XCTAssertEqual(status(lost).text, "Lost")
        XCTAssertEqual(SquadHistoryRow.outcome(for: won, squadId: home), .win)
        XCTAssertEqual(SquadHistoryRow.outcome(for: lost, squadId: home), .loss)
    }

    /// This squad's score first, whichever side of the match it was on.
    func testTheScoreReadsFromThisSquadsSide() {
        let confirmed = game(status: .confirmed, result: away, homeScore: 15, awayScore: 21)

        XCTAssertEqual(SquadHistoryRow.score(for: confirmed, squadId: home), "15–21")
        XCTAssertEqual(SquadHistoryRow.score(for: confirmed, squadId: away), "21–15")
    }

    /// A score is optional; a confirmed result without one shows none rather
    /// than a made-up "0–0".
    func testNoScoreEnteredShowsNone() {
        let confirmed = game(status: .confirmed, result: home)
        XCTAssertNil(SquadHistoryRow.score(for: confirmed, squadId: home))
    }

    // MARK: - Not a result

    /// Disputed, cancelled, and not-yet-reported all take the grey dot. A match
    /// nobody confirmed is not a loss and must never look like one.
    func testNothingUnconfirmedTakesAResultColour() {
        for unconfirmed in [
            game(status: .disputed, homeReport: home, awayReport: away),
            game(status: .cancelled),
            game(status: .scheduled),
            game(status: .scheduled, scheduledOffset: 3600),
        ] {
            XCTAssertNil(SquadHistoryRow.outcome(for: unconfirmed, squadId: home), "\(unconfirmed.status)")
            XCTAssertNil(SquadHistoryRow.score(for: unconfirmed, squadId: home), "\(unconfirmed.status)")
        }
    }

    /// Designed, not an error — so it's stated plainly, and not as a call to
    /// action in the list (the result screen is where re-reporting lives).
    func testADisputeSaysSoWithoutAlarm() {
        let disputed = game(status: .disputed, homeReport: home, awayReport: away)
        XCTAssertEqual(status(disputed).text, "Results don't match")
        XCTAssertFalse(status(disputed).isCallToAction)
    }

    func testACancelledMatchSaysSo() {
        XCTAssertEqual(status(game(status: .cancelled)).text, "Cancelled")
    }

    // MARK: - Scheduled

    func testAMatchStillToComeIsScheduled() {
        XCTAssertEqual(status(game(scheduledOffset: 3600)).text, "Scheduled")
    }

    /// The one row in the list that asks for something: this leader played
    /// and hasn't reported.
    func testALeaderWhoOwesAReportIsAskedForIt() {
        let played = game()
        XCTAssertEqual(status(played).text, "Report the result")
        XCTAssertTrue(status(played).isCallToAction)
    }

    /// Reported, and the other leader hasn't. **No deadline in the words** —
    /// the match waits forever, and "Waiting on" is what `ResultView` says.
    func testAReportedMatchWaitsOnTheOtherSquadWithNoDeadline() {
        let reported = game(homeReport: home)
        let text = status(reported).text

        XCTAssertEqual(text, "Waiting on Court Vision")
        XCTAssertFalse(status(reported).isCallToAction)
        for word in ["hours", "days", "expire", "forfeit", "until", "deadline"] {
            XCTAssertFalse(text.lowercased().contains(word), "\"\(text)\" implies a deadline")
        }
    }

    /// A member who isn't the leader can't report, so the row doesn't ask them
    /// to. It says the result isn't in.
    func testAMemberWhoCantReportIsNotAsked() {
        let played = game()
        XCTAssertEqual(status(played, uid: "a-member").text, "Result not in yet")
        XCTAssertFalse(status(played, uid: "a-member").isCallToAction)
        XCTAssertEqual(status(played, uid: nil).text, "Result not in yet")
    }
}
