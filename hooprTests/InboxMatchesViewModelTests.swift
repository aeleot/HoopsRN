import XCTest
@testable import hoopr

/// Which season matches the inbox lists, and which screen each row opens.
///
/// The inbox is where every tapped notification lands, and the notifications
/// are all about matches — so a match missing here is a reminder that opens
/// on nothing, and a finished one left here is clutter at the top of the
/// inbox for the rest of the season.
final class InboxMatchesViewModelTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let hour: TimeInterval = 60 * 60

    /// "squad-home" is led by "leader-home"; the signed-in user is on it.
    private func game(
        id: String = "game-1",
        tipOffIn offset: TimeInterval,
        status: SeasonGame.Status = .scheduled,
        homeReport: String? = nil,
        awayReport: String? = nil
    ) -> SeasonGame {
        SeasonGame(
            id: id,
            format: .threeVThree,
            region: "Durham",
            homeSquadId: "squad-home",
            awaySquadId: "squad-away",
            squadIds: ["squad-home", "squad-away"],
            homeLeaderId: "leader-home",
            awayLeaderId: "leader-away",
            homeSquadName: "Rim Reapers",
            awaySquadName: "Court Vision",
            courtId: "court-1",
            scheduledTime: now.addingTimeInterval(offset),
            status: status,
            arrivedPlayerIds: [],
            homeReport: homeReport,
            awayReport: awayReport,
            homeScore: nil,
            awayScore: nil,
            result: nil,
            cancelledBySquadId: nil,
            createdBy: "leader-away",
            createdAt: nil,
            updatedAt: nil,
            confirmedAt: nil
        )
    }

    private func rows(_ games: [SeasonGame], uid: String = "leader-home") -> [InboxMatchesViewModel.Row] {
        InboxMatchesViewModel.rows(games: games, mySquadIds: ["squad-home"], uid: uid, now: now)
    }

    // MARK: - Upcoming

    func testAMatchStillToComeIsListedAndOpensGameDay() {
        let listed = rows([game(tipOffIn: 3 * hour)])

        XCTAssertEqual(listed.map(\.kind), [.upcoming])
        XCTAssertEqual(listed.first?.mySquadId, "squad-home")
        XCTAssertEqual(listed.first?.opponentName, "Court Vision")
    }

    /// The tip-off notification fires at T+0 and asks you to mark arrival,
    /// which is on game day — so a match under way still opens there.
    func testAMatchUnderWayStillOpensGameDay() {
        XCTAssertEqual(rows([game(tipOffIn: -30 * 60)]).map(\.kind), [.upcoming])
    }

    /// A player who doesn't lead a side can't report, so a played match stays
    /// on game day for them until it drops off.
    func testANonLeaderIsNeverAskedToReport() {
        XCTAssertEqual(rows([game(tipOffIn: -2 * hour)], uid: "a-player").map(\.kind), [.upcoming])
        XCTAssertTrue(rows([game(tipOffIn: -4 * hour)], uid: "a-player").isEmpty)
    }

    // MARK: - Waiting on your report

    /// From the recap's T+90 a leader is sent to the result, not game day.
    func testFromTheRecapALeaderIsSentToReport() {
        XCTAssertEqual(rows([game(tipOffIn: -2 * hour)]).map(\.kind), [.report])
    }

    func testBeforeTheRecapALeaderStillGetsGameDay() {
        XCTAssertEqual(rows([game(tipOffIn: -hour)]).map(\.kind), [.upcoming])
    }

    /// Once you've reported, the match is waiting on the other leader.
    func testAReportYouveMadeIsNotListed() {
        XCTAssertTrue(rows([game(tipOffIn: -4 * hour, homeReport: "squad-home")]).isEmpty)
    }

    func testADisputedMatchAsksTheLeaderAgain() {
        let disputed = game(
            tipOffIn: -4 * hour,
            status: .disputed,
            homeReport: "squad-home",
            awayReport: "squad-away"
        )
        XCTAssertEqual(rows([disputed]).map(\.kind), [.disputed])
    }

    func testAnUnreportedMatchDropsOffAfterTheWindow() {
        let window = InboxMatchesViewModel.reportWindow
        XCTAssertEqual(rows([game(tipOffIn: -(window - hour))]).map(\.kind), [.report])
        XCTAssertTrue(rows([game(tipOffIn: -(window + hour))]).isEmpty)
    }

    // MARK: - Never listed

    func testCancelledAndConfirmedMatchesAreNotListed() {
        XCTAssertTrue(rows([
            game(id: "a", tipOffIn: 3 * hour, status: .cancelled),
            game(id: "b", tipOffIn: -4 * hour, status: .confirmed, homeReport: "squad-home", awayReport: "squad-home"),
        ]).isEmpty)
    }

    func testAMatchNotOnMySquadIsNotListed() {
        let listed = InboxMatchesViewModel.rows(
            games: [game(tipOffIn: 3 * hour)],
            mySquadIds: ["someone-else"],
            uid: "leader-home",
            now: now
        )
        XCTAssertTrue(listed.isEmpty)
    }

    // MARK: - Order

    /// Answers first — they're what's waiting on you — then soonest tip-off.
    func testReportsLeadThenSoonestFirst() {
        let listed = rows([
            game(id: "later", tipOffIn: 48 * hour),
            game(id: "sooner", tipOffIn: 2 * hour),
            game(id: "played", tipOffIn: -2 * hour),
        ])
        XCTAssertEqual(listed.map(\.id), ["played", "sooner", "later"])
    }
}
