import XCTest
@testable import hoopr

/// The result screen's words in each state (`ResultCopy`).
///
/// Two rules from `gaps/SEASONS.md` that can't be seen on one device, because
/// they need two leaders reporting to each other:
/// - a match awaiting the other leader **waits forever** — no timeout, no
///   forfeit, no nudge — so nothing may imply one is coming;
/// - a dispute is a designed outcome, and reads as a disagreement, not a
///   failure.
final class ResultCopyTests: XCTestCase {

    private let mine = "squad-home"
    private let theirs = "squad-away"

    private func text(
        _ outcome: SeasonGame.ReportOutcome,
        myReport: String? = nil,
        opponentReport: String? = nil,
        isTooEarly: Bool = false,
        isLeader: Bool = true
    ) -> ResultCopy.Text {
        ResultCopy.text(
            outcome: outcome,
            mySquadId: mine,
            myReport: myReport,
            opponentReport: opponentReport,
            opponentName: "Court Vision",
            isTooEarly: isTooEarly,
            isLeader: isLeader,
            name: { $0 == self.mine ? "Raptorz" : "Court Vision" }
        )
    }

    private let deadlineWords = ["hour", "day", "expire", "forfeit", "until", "deadline", "soon", "remind"]

    private func assertNoDeadline(_ copy: ResultCopy.Text, file: StaticString = #filePath, line: UInt = #line) {
        let all = ([copy.headline] + copy.body).joined(separator: " ").lowercased()
        for word in deadlineWords {
            XCTAssertFalse(all.contains(word), "\"\(all)\" implies a deadline (\(word))", file: file, line: line)
        }
    }

    // MARK: - Confirmed

    func testAWinIsYours() {
        XCTAssertEqual(text(.confirmed(mine)).headline, "You won")
    }

    func testALossNamesTheWinner() {
        XCTAssertEqual(text(.confirmed(theirs)).headline, "Court Vision won")
    }

    // MARK: - Waiting

    /// Reported, and the other leader hasn't. It waits forever, so the words
    /// say whose move it is and nothing about when.
    func testWaitingOnTheOtherLeaderHasNoDeadline() {
        let copy = text(.awaitingReport, myReport: mine)
        XCTAssertEqual(copy.headline, "Waiting on Court Vision")
        assertNoDeadline(copy)
    }

    func testAMemberWaitsOnTheLeadersWithNoDeadline() {
        let copy = text(.awaitingReport, isLeader: false)
        XCTAssertEqual(copy.headline, "Waiting on the leaders")
        assertNoDeadline(copy)
    }

    func testALeaderWhoHasntReportedIsAsked() {
        XCTAssertEqual(text(.awaitingReport).headline, "How'd it go?")
    }

    func testBeforeTipOffItsNotPlayedYet() {
        XCTAssertEqual(text(.awaitingReport, isTooEarly: true).headline, "Not played yet")
    }

    // MARK: - Disputed

    /// Says what each side said, and how it resolves — not that something
    /// went wrong.
    func testADisputeSaysWhoSaidWhatAndHowItResolves() {
        let copy = text(.disputed, myReport: mine, opponentReport: theirs)

        XCTAssertEqual(copy.headline, "Results don't match")
        XCTAssertEqual(copy.body.first, "You said Raptorz won. Court Vision said Court Vision won.")
        XCTAssertTrue(copy.body.contains { $0.contains("report again") })

        let all = ([copy.headline] + copy.body).joined(separator: " ").lowercased()
        for word in ["error", "failed", "wrong result", "invalid"] {
            XCTAssertFalse(all.contains(word), "a dispute reads as a failure: \(word)")
        }
    }

    /// Without both reports in hand (a member's view), it still says what
    /// happened rather than naming nobody.
    func testADisputeWithoutTheReportsStillSaysWhatHappened() {
        XCTAssertEqual(
            text(.disputed, isLeader: false).body.first,
            "The two squads reported different winners."
        )
    }
}
