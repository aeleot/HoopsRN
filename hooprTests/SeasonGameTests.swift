import XCTest
@testable import hoopr

/// `SeasonGame`'s pure logic: the derived record, the form guide, the
/// create-time validation that mirrors the rules, and the queue windows.
///
/// The record is the one worth reading twice. `squads` deliberately stores no
/// `wins`/`losses` — a stored counter on a document you control is a number you
/// can type — so a squad's record is arithmetic over confirmed matches two
/// leaders had to agree on. Until Phase 6 ships, that arithmetic runs over an
/// empty set. **These tests exercise it against a populated one anyway**, which
/// is the whole reason the derivation is written now: a ticket that hardcoded
/// zeros would silently keep reading zero after Phase 6 lands, and nothing would
/// fail to say so.
final class SeasonGameTests: XCTestCase {

    // MARK: - Fixtures

    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    private func game(
        id: String = "game-1",
        home: String = "squad-home",
        away: String = "squad-away",
        status: SeasonGame.Status = .scheduled,
        result: String? = nil,
        scheduledOffset: TimeInterval = 3600,
        arrived: [String] = [],
        createdOffset: TimeInterval? = nil,
        homeReport: String? = nil,
        awayReport: String? = nil,
        homeScore: Int? = nil,
        awayScore: Int? = nil
    ) -> SeasonGame {
        SeasonGame(
            id: id,
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
            arrivedPlayerIds: arrived,
            homeReport: homeReport,
            awayReport: awayReport,
            homeScore: homeScore,
            awayScore: awayScore,
            result: result,
            cancelledBySquadId: nil,
            createdBy: "leader-away",
            createdAt: createdOffset.map { now.addingTimeInterval($0) },
            updatedAt: nil,
            confirmedAt: nil
        )
    }

    /// A match that has already been played, which is the only kind that can be
    /// reported.
    private func playedGame(
        status: SeasonGame.Status = .scheduled,
        result: String? = nil,
        homeReport: String? = nil,
        awayReport: String? = nil
    ) -> SeasonGame {
        game(
            status: status,
            result: result,
            scheduledOffset: -3600,
            homeReport: homeReport,
            awayReport: awayReport
        )
    }

    /// Applies a report write the way the transaction's `updateData` map does,
    /// so a test can assert what the *document* reads as afterwards rather than
    /// only what the write said.
    private func applying(
        _ write: SeasonGame.ReportWrite,
        to match: SeasonGame
    ) -> SeasonGame {
        SeasonGame(
            id: match.id,
            format: match.format,
            region: match.region,
            homeSquadId: match.homeSquadId,
            awaySquadId: match.awaySquadId,
            squadIds: match.squadIds,
            homeLeaderId: match.homeLeaderId,
            awayLeaderId: match.awayLeaderId,
            homeSquadName: match.homeSquadName,
            awaySquadName: match.awaySquadName,
            courtId: match.courtId,
            scheduledTime: match.scheduledTime,
            status: write.status,
            arrivedPlayerIds: match.arrivedPlayerIds,
            homeReport: write.field == .home ? write.winningSquadId : match.homeReport,
            awayReport: write.field == .away ? write.winningSquadId : match.awayReport,
            homeScore: write.homeScore ?? match.homeScore,
            awayScore: write.awayScore ?? match.awayScore,
            result: write.result,
            cancelledBySquadId: match.cancelledBySquadId,
            createdBy: match.createdBy,
            createdAt: match.createdAt,
            updatedAt: now,
            confirmedAt: write.confirms ? now : match.confirmedAt
        )
    }

    private func ticket(
        squadId: String = "squad-home",
        leaderId: String = "leader-home",
        memberIds: [String] = ["leader-home", "member-home"],
        courtIds: [String] = ["court-1", "court-2"],
        windowOffset: TimeInterval = 1800,
        windowLength: TimeInterval = 4 * 3600,
        format: SquadFormat = .threeVThree,
        region: String = "Durham"
    ) -> MatchTicket {
        MatchTicket(
            squadId: squadId,
            leaderId: leaderId,
            squadName: "Squad \(squadId)",
            memberIds: memberIds,
            format: format,
            region: region,
            courtIds: courtIds,
            windowStart: now.addingTimeInterval(windowOffset),
            windowEnd: now.addingTimeInterval(windowOffset + windowLength),
            wins: 0,
            losses: 0,
            status: .open,
            claimedBy: nil,
            claimedAt: nil,
            matchedGameId: nil,
            createdAt: now,
            expiresAt: now.addingTimeInterval(2 * 3600)
        )
    }

    // MARK: - The derived record

    func testAnUnplayedSquadHasAnEmptyRecordAndSitsAtTheMidpoint() {
        let record = SeasonGame.record(for: "squad-home", in: [])

        XCTAssertEqual(record.wins, 0)
        XCTAssertEqual(record.losses, 0)
        XCTAssertTrue(record.isUnplayed)
        // The midpoint, matching `MatchRules.recordRating`. Treating "no
        // record" as "loses everything" would rank every new squad against the
        // worst opponents in the pool.
        XCTAssertEqual(record.winPercentage, 0.5)
    }

    func testOnlyConfirmedMatchesCount() {
        let games = [
            game(id: "1", status: .confirmed, result: "squad-home"),
            game(id: "2", status: .confirmed, result: "squad-away"),
            // None of these may move the record.
            game(id: "3", status: .scheduled),
            game(id: "4", status: .cancelled),
            game(id: "5", status: .disputed),
            // Confirmed but resultless is a contradiction the rules forbid;
            // skipped rather than trusted.
            game(id: "6", status: .confirmed, result: nil),
        ]

        let record = SeasonGame.record(for: "squad-home", in: games)
        XCTAssertEqual(record.wins, 1)
        XCTAssertEqual(record.losses, 1)
        XCTAssertEqual(record.played, 2)
    }

    func testARecordIsReadFromBothSidesOfTheSameMatch() {
        let games = [
            game(id: "1", status: .confirmed, result: "squad-home"),
            game(id: "2", status: .confirmed, result: "squad-home"),
            game(id: "3", status: .confirmed, result: "squad-away"),
        ]

        let home = SeasonGame.record(for: "squad-home", in: games)
        let away = SeasonGame.record(for: "squad-away", in: games)

        XCTAssertEqual(home.wins, 2)
        XCTAssertEqual(home.losses, 1)
        XCTAssertEqual(away.wins, 1)
        XCTAssertEqual(away.losses, 2)
        // Every match one squad won is one the other lost.
        XCTAssertEqual(home.wins, away.losses)
        XCTAssertEqual(home.losses, away.wins)
    }

    func testAMatchASquadIsNotInDoesNotCount() {
        let games = [
            game(id: "1", home: "squad-x", away: "squad-y", status: .confirmed, result: "squad-x")
        ]

        XCTAssertTrue(SeasonGame.record(for: "squad-home", in: games).isUnplayed)
    }

    func testWinPercentage() {
        let games = [
            game(id: "1", status: .confirmed, result: "squad-home"),
            game(id: "2", status: .confirmed, result: "squad-home"),
            game(id: "3", status: .confirmed, result: "squad-home"),
            game(id: "4", status: .confirmed, result: "squad-away"),
        ]

        XCTAssertEqual(SeasonGame.record(for: "squad-home", in: games).winPercentage, 0.75)
        XCTAssertEqual(SeasonGame.record(for: "squad-home", in: games).displayText, "3–1")
    }

    // MARK: - The form guide

    func testFormIsMostRecentFirstAndCappedAtFive() {
        let games = (1...8).map { index in
            game(
                id: "\(index)",
                status: .confirmed,
                // Odd indexes are wins for home.
                result: index.isMultiple(of: 2) ? "squad-away" : "squad-home",
                scheduledOffset: TimeInterval(index) * 3600
            )
        }

        let form = SeasonGame.form(for: "squad-home", in: games)

        XCTAssertEqual(form.count, 5)
        // Most recent first: index 8 (a loss), then 7 (a win), and so on.
        XCTAssertEqual(form, [.loss, .win, .loss, .win, .loss])
    }

    func testFormExcludesUnconfirmedMatches() {
        let games = [
            game(id: "1", status: .confirmed, result: "squad-home", scheduledOffset: 3600),
            game(id: "2", status: .cancelled, scheduledOffset: 7200),
            game(id: "3", status: .disputed, scheduledOffset: 10800),
        ]

        XCTAssertEqual(SeasonGame.form(for: "squad-home", in: games), [.win])
    }

    func testFormIsEmptyForAnUnplayedSquad() {
        XCTAssertTrue(SeasonGame.form(for: "squad-home", in: []).isEmpty)
    }

    // MARK: - Reading a match

    func testOpponentIsResolvedFromEitherSide() {
        let match = game()

        XCTAssertEqual(match.opponentSquadId(of: "squad-home"), "squad-away")
        XCTAssertEqual(match.opponentSquadId(of: "squad-away"), "squad-home")
        XCTAssertNil(match.opponentSquadId(of: "squad-elsewhere"))

        XCTAssertEqual(match.opponentName(of: "squad-home"), "Court Vision")
        XCTAssertEqual(match.opponentName(of: "squad-away"), "Rim Reapers")
    }

    func testEitherLeaderMayCancelAScheduledMatchAndNobodyElseMay() {
        let match = game()

        XCTAssertTrue(match.canCancel(uid: "leader-home"))
        XCTAssertTrue(match.canCancel(uid: "leader-away"))
        XCTAssertFalse(match.canCancel(uid: "member-home"))
    }

    func testACancelledMatchCannotBeCancelledAgain() {
        let match = game(status: .cancelled)

        XCTAssertFalse(match.canCancel(uid: "leader-home"))
        XCTAssertFalse(match.canCancel(uid: "leader-away"))
    }

    func testAMatchStaysUpcomingThroughItsGracePeriod() {
        let match = game(scheduledOffset: -3600)

        XCTAssertTrue(match.isUpcoming(at: now), "an hour after tip-off is still game day")
        XCTAssertFalse(
            match.isUpcoming(at: now.addingTimeInterval(SeasonGame.visibilityGrace + 1)),
            "past the grace period it is history"
        )
    }

    func testACancelledMatchIsNeverUpcoming() {
        XCTAssertFalse(game(status: .cancelled).isUpcoming(at: now))
    }

    func testLedSquadIsResolvedForEachLeader() {
        let match = game()

        XCTAssertEqual(match.ledSquadId(for: "leader-home"), "squad-home")
        XCTAssertEqual(match.ledSquadId(for: "leader-away"), "squad-away")
        XCTAssertNil(match.ledSquadId(for: "member-away"))
    }

    // MARK: - The report derivation
    //
    // This is the arithmetic mutual confirmation is made of, and the rules
    // compute it identically from the same two fields — so these tests are
    // pinning both copies at once. `firestore-tests/results.test.mjs` is where
    // the server half is evaluated against two distinct authenticated leaders.

    func testOneReportSettlesNothing() {
        XCTAssertEqual(SeasonGame.outcome(homeReport: nil, awayReport: nil), .awaitingReport)
        XCTAssertEqual(
            SeasonGame.outcome(homeReport: "squad-home", awayReport: nil),
            .awaitingReport
        )
        XCTAssertEqual(
            SeasonGame.outcome(homeReport: nil, awayReport: "squad-home"),
            .awaitingReport
        )
    }

    func testTwoReportsAgreeingConfirmTheWinner() {
        XCTAssertEqual(
            SeasonGame.outcome(homeReport: "squad-home", awayReport: "squad-home"),
            .confirmed("squad-home")
        )
        XCTAssertEqual(
            SeasonGame.outcome(homeReport: "squad-away", awayReport: "squad-away"),
            .confirmed("squad-away")
        )
    }

    func testTwoReportsDisagreeingDisputeAndNameNoWinner() {
        let outcome = SeasonGame.outcome(homeReport: "squad-home", awayReport: "squad-away")

        XCTAssertEqual(outcome, .disputed)
        // The field the record query reads. A disputed match counts for nobody
        // precisely because this stays nil.
        XCTAssertNil(outcome.result)
        XCTAssertEqual(outcome.status, .disputed)
    }

    func testEachOutcomeCarriesTheStatusTheRulesDerive() {
        XCTAssertEqual(SeasonGame.ReportOutcome.awaitingReport.status, .scheduled)
        XCTAssertEqual(SeasonGame.ReportOutcome.disputed.status, .disputed)
        XCTAssertEqual(SeasonGame.ReportOutcome.confirmed("squad-home").status, .confirmed)

        XCTAssertNil(SeasonGame.ReportOutcome.awaitingReport.result)
        XCTAssertNil(SeasonGame.ReportOutcome.disputed.result)
        XCTAssertEqual(SeasonGame.ReportOutcome.confirmed("squad-home").result, "squad-home")
    }

    // MARK: - What a report write contains

    func testTheFirstReportCarriesNoResult() {
        let write = SeasonGame.reportWrite(
            field: .home,
            winner: "squad-home",
            homeScore: nil,
            awayScore: nil,
            standingHomeReport: nil,
            standingAwayReport: nil
        )

        XCTAssertEqual(write.status, .scheduled)
        XCTAssertNil(write.result, "one leader saying so is not mutual confirmation")
        XCTAssertFalse(write.confirms)
    }

    func testTheSecondAgreeingReportIsTheOneThatConfirms() {
        // The prompt's Phase 6 test case #2, as pure logic: the write that
        // completes a matching pair also lands the result, in the same commit.
        let write = SeasonGame.reportWrite(
            field: .away,
            winner: "squad-home",
            homeScore: nil,
            awayScore: nil,
            standingHomeReport: "squad-home",
            standingAwayReport: nil
        )

        XCTAssertEqual(write.status, .confirmed)
        XCTAssertEqual(write.result, "squad-home")
        XCTAssertTrue(write.confirms)
    }

    func testTheSecondDisagreeingReportDisputesAndNamesNobody() {
        let write = SeasonGame.reportWrite(
            field: .away,
            winner: "squad-away",
            homeScore: nil,
            awayScore: nil,
            standingHomeReport: "squad-home",
            standingAwayReport: nil
        )

        XCTAssertEqual(write.status, .disputed)
        XCTAssertNil(write.result)
    }

    func testAReportWriteOnlyEverMovesItsOwnField() {
        // The pinning, as data: a home write leaves the away report exactly
        // where it was, whatever it says. The rules enforce the same thing by
        // leaving the other key out of `affectedKeys().hasOnly`.
        let match = playedGame(status: .disputed, homeReport: "squad-home", awayReport: "squad-away")

        let write = SeasonGame.reportWrite(
            field: .home,
            winner: "squad-away",
            homeScore: nil,
            awayScore: nil,
            standingHomeReport: match.homeReport,
            standingAwayReport: match.awayReport
        )

        let after = applying(write, to: match)
        XCTAssertEqual(after.homeReport, "squad-away")
        XCTAssertEqual(after.awayReport, "squad-away", "the other leader's report is untouched")
    }

    func testADisputedMatchIsResolvedByReReportingToAgree() {
        // The design's own stated recovery path from a dispute.
        // Re-reporting is the same write path called again, not a second
        // feature — if it weren't, a disputed match could never leave `disputed`.
        let disputed = playedGame(
            status: .disputed,
            homeReport: "squad-home",
            awayReport: "squad-away"
        )

        XCTAssertTrue(disputed.isReportable)

        let write = SeasonGame.reportWrite(
            field: .home,
            winner: "squad-away",
            homeScore: nil,
            awayScore: nil,
            standingHomeReport: disputed.homeReport,
            standingAwayReport: disputed.awayReport
        )

        let resolved = applying(write, to: disputed)
        XCTAssertEqual(resolved.status, .confirmed)
        XCTAssertEqual(resolved.result, "squad-away")
        XCTAssertNotNil(resolved.confirmedAt)
    }

    func testAConfirmedResultMovesBothSquadsRecords() {
        // The other half of test case #2: the derivation Phase 4 wrote against
        // an empty set now returns something, without either function changing.
        let played = playedGame()

        let first = applying(
            SeasonGame.reportWrite(
                field: .home, winner: "squad-home",
                homeScore: nil, awayScore: nil,
                standingHomeReport: nil, standingAwayReport: nil
            ),
            to: played
        )
        let confirmed = applying(
            SeasonGame.reportWrite(
                field: .away, winner: "squad-home",
                homeScore: nil, awayScore: nil,
                standingHomeReport: first.homeReport, standingAwayReport: first.awayReport
            ),
            to: first
        )

        XCTAssertEqual(SeasonGame.record(for: "squad-home", in: [confirmed]).wins, 1)
        XCTAssertEqual(SeasonGame.record(for: "squad-away", in: [confirmed]).losses, 1)
        XCTAssertEqual(SeasonGame.form(for: "squad-home", in: [confirmed]), [.win])
        XCTAssertEqual(SeasonGame.form(for: "squad-away", in: [confirmed]), [.loss])
    }

    func testADisagreementMovesNeitherSquadsRecord() {
        let played = playedGame()

        let first = applying(
            SeasonGame.reportWrite(
                field: .home, winner: "squad-home",
                homeScore: nil, awayScore: nil,
                standingHomeReport: nil, standingAwayReport: nil
            ),
            to: played
        )
        let disputed = applying(
            SeasonGame.reportWrite(
                field: .away, winner: "squad-away",
                homeScore: nil, awayScore: nil,
                standingHomeReport: first.homeReport, standingAwayReport: first.awayReport
            ),
            to: first
        )

        XCTAssertTrue(SeasonGame.record(for: "squad-home", in: [disputed]).isUnplayed)
        XCTAssertTrue(SeasonGame.record(for: "squad-away", in: [disputed]).isUnplayed)
        XCTAssertTrue(SeasonGame.form(for: "squad-home", in: [disputed]).isEmpty)
    }

    func testAScoreRidesAlongAndNeverBecomesTheResult() {
        let write = SeasonGame.reportWrite(
            field: .home,
            winner: "squad-home",
            homeScore: 21,
            awayScore: 18,
            standingHomeReport: nil,
            standingAwayReport: nil
        )

        XCTAssertEqual(write.homeScore, 21)
        XCTAssertEqual(write.awayScore, 18)
        // Cosmetic — a score of 21–18 is not a claim about who
        // won, and the record never reads it.
        XCTAssertNil(write.result)
    }

    // MARK: - Who may report, and when

    func testEachLeaderOwnsExactlyOneReportField() {
        let match = playedGame()

        XCTAssertEqual(match.reportField(for: "leader-home"), .home)
        XCTAssertEqual(match.reportField(for: "leader-away"), .away)
        XCTAssertNil(match.reportField(for: "member-home"))

        // The raw values are the Firestore field names the rules pin.
        XCTAssertEqual(SeasonGame.ReportField.home.rawValue, "homeReport")
        XCTAssertEqual(SeasonGame.ReportField.away.rawValue, "awayReport")
    }

    func testAReportIsReadBackFromItsOwnLeadersPointOfView() {
        let match = playedGame(homeReport: "squad-home", awayReport: "squad-away")

        XCTAssertEqual(match.report(by: "leader-home"), "squad-home")
        XCTAssertEqual(match.opponentReport(by: "leader-home"), "squad-away")
        XCTAssertEqual(match.report(by: "leader-away"), "squad-away")
        XCTAssertEqual(match.opponentReport(by: "leader-away"), "squad-home")
        XCTAssertNil(match.report(by: "member-away"))
    }

    func testBothLeadersMayReportAPlayedMatchAndNobodyElseMay() {
        let match = playedGame()

        XCTAssertTrue(match.canReport(uid: "leader-home", at: now))
        XCTAssertTrue(match.canReport(uid: "leader-away", at: now))
        XCTAssertFalse(match.canReport(uid: "member-home", at: now))
        XCTAssertFalse(match.canReport(uid: "stranger", at: now))
    }

    func testAMatchCannotBeReportedBeforeItIsPlayed() {
        // The design's "after `scheduledTime`", which the rules enforce as
        // `request.time >= scheduledTime` rather than assume.
        let upcoming = game(scheduledOffset: 3600)

        XCTAssertFalse(upcoming.canReport(uid: "leader-home", at: now))
        XCTAssertEqual(
            upcoming.validateReport(winner: "squad-home", by: "leader-home", now: now),
            .notPlayed
        )
    }

    func testADisputedMatchIsStillReportableButAConfirmedOneIsNot() {
        XCTAssertTrue(playedGame(status: .disputed).isReportable)
        XCTAssertTrue(playedGame(status: .scheduled).isReportable)

        // Agreement is not unilaterally revocable: a leader able to re-report a
        // match both sides settled could turn their own loss back into a
        // dispute, which is weaker than the standard the design claims to meet.
        XCTAssertFalse(playedGame(status: .confirmed, result: "squad-away").isReportable)
        XCTAssertFalse(playedGame(status: .cancelled).isReportable)
    }

    func testValidateReportNamesTheFirstProblem() {
        let match = playedGame()

        XCTAssertNil(match.validateReport(winner: "squad-home", by: "leader-home", now: now))
        XCTAssertNil(match.validateReport(winner: "squad-away", by: "leader-home", now: now),
                     "a leader may report a win for the other squad")

        XCTAssertEqual(
            match.validateReport(winner: "squad-home", by: "member-home", now: now),
            .notLeader
        )
        XCTAssertEqual(
            match.validateReport(winner: "squad-elsewhere", by: "leader-home", now: now),
            .unknownWinner
        )
        XCTAssertEqual(
            playedGame(status: .confirmed, result: "squad-home")
                .validateReport(winner: "squad-home", by: "leader-home", now: now),
            .notScheduled
        )
    }

    // MARK: - Validation, mirroring the create rule

    func testAValidMatchPasses() {
        let home = ticket()
        let away = ticket(
            squadId: "squad-away",
            leaderId: "leader-away",
            memberIds: ["leader-away"],
            courtIds: ["court-1"]
        )

        XCTAssertNil(
            SeasonGame.validate(
                homeTicket: home,
                awayTicket: away,
                courtId: "court-1",
                scheduledTime: now.addingTimeInterval(3600),
                now: now
            )
        )
    }

    func testACourtTheHomeSquadNeverOfferedIsRejected() {
        // The rule the server enforces with `courtIds.hasAll([courtId])`, and
        // the reason the court is always drawn from the *home* list.
        let home = ticket(courtIds: ["court-1"])
        let away = ticket(
            squadId: "squad-away",
            leaderId: "leader-away",
            memberIds: ["leader-away"],
            courtIds: ["court-9"]
        )

        XCTAssertEqual(
            SeasonGame.validate(
                homeTicket: home,
                awayTicket: away,
                courtId: "court-9",
                scheduledTime: now.addingTimeInterval(3600),
                now: now
            ),
            .courtNotOffered
        )
    }

    func testATimeOutsideTheHomeWindowIsRejected() {
        let home = ticket(windowOffset: 1800, windowLength: 3600)
        let away = ticket(squadId: "squad-away", leaderId: "leader-away", memberIds: ["leader-away"])

        for offset in [TimeInterval(600), TimeInterval(9 * 3600)] {
            XCTAssertEqual(
                SeasonGame.validate(
                    homeTicket: home,
                    awayTicket: away,
                    courtId: "court-1",
                    scheduledTime: now.addingTimeInterval(offset),
                    now: now
                ),
                .timeOutsideWindow,
                "offset \(offset) should fall outside the window"
            )
        }
    }

    func testASharedPlayerIsRejected() {
        // A person cannot play themselves — the rule most likely to be quietly
        // dropped, checked here as well as in `MatchRules`.
        let home = ticket(memberIds: ["leader-home", "shared"])
        let away = ticket(
            squadId: "squad-away",
            leaderId: "leader-away",
            memberIds: ["leader-away", "shared"]
        )

        XCTAssertEqual(
            SeasonGame.validate(
                homeTicket: home,
                awayTicket: away,
                courtId: "court-1",
                scheduledTime: now.addingTimeInterval(3600),
                now: now
            ),
            .sharedPlayer
        )
    }

    func testASquadCannotPlayItself() {
        let home = ticket()

        XCTAssertEqual(
            SeasonGame.validate(
                homeTicket: home,
                awayTicket: home,
                courtId: "court-1",
                scheduledTime: now.addingTimeInterval(3600),
                now: now
            ),
            .sameSquad
        )
    }

    func testAMismatchedFormatOrRegionIsRejected() {
        let home = ticket()

        let otherFormat = ticket(
            squadId: "squad-away",
            leaderId: "leader-away",
            memberIds: ["leader-away"],
            format: .fiveVFive
        )
        XCTAssertEqual(
            SeasonGame.validate(
                homeTicket: home, awayTicket: otherFormat,
                courtId: "court-1", scheduledTime: now.addingTimeInterval(3600), now: now
            ),
            .formatMismatch
        )

        let otherRegion = ticket(
            squadId: "squad-away",
            leaderId: "leader-away",
            memberIds: ["leader-away"],
            region: "Raleigh"
        )
        XCTAssertEqual(
            SeasonGame.validate(
                homeTicket: home, awayTicket: otherRegion,
                courtId: "court-1", scheduledTime: now.addingTimeInterval(3600), now: now
            ),
            .regionMismatch
        )
    }

    func testATipOffInsideTheLeadTimeIsRejected() {
        let home = ticket(windowOffset: 0, windowLength: 4 * 3600)
        let away = ticket(squadId: "squad-away", leaderId: "leader-away", memberIds: ["leader-away"])

        XCTAssertEqual(
            SeasonGame.validate(
                homeTicket: home,
                awayTicket: away,
                courtId: "court-1",
                scheduledTime: now.addingTimeInterval(60),
                now: now
            ),
            .scheduleTooSoon
        )
    }

    // MARK: - squadIds ordering

    func testSquadIdsAreAlwaysHomeThenAway() {
        // The create rule asserts this array *equals* [home, away]. Built in the
        // other order it is a `permission-denied` with no obvious cause, which
        // is exactly the kind of thing worth pinning.
        XCTAssertEqual(SeasonGame.squadIds(home: "b", away: "a"), ["b", "a"])
        XCTAssertEqual(SeasonGame.squadIds(home: "a", away: "b"), ["a", "b"])
    }

    // MARK: - Queue windows

    func testTonightRunsFromNowUntilTenWhenItIsAlreadyEvening() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        let sevenPM = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 29, hour: 19, minute: 0
        ))!

        let window = QueueWindow.tonight.window(
            format: .threeVThree, now: sevenPM, calendar: calendar
        )

        XCTAssertNotNil(window)
        XCTAssertEqual(window?.start, sevenPM, "already past 5pm, so the window starts now")
        XCTAssertEqual(
            window?.end,
            calendar.date(bySettingHour: 22, minute: 0, second: 0, of: sevenPM)
        )
    }

    func testTonightStartsAtFiveWhenItIsStillMorning() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        let nineAM = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 29, hour: 9, minute: 0
        ))!

        let window = QueueWindow.tonight.window(
            format: .threeVThree, now: nineAM, calendar: calendar
        )

        XCTAssertEqual(
            window?.start,
            calendar.date(bySettingHour: 17, minute: 0, second: 0, of: nineAM)
        )
    }

    func testTonightDisablesItselfOnceThereIsNoRoomForAGame() {
        // 9:30pm leaves half an hour, and a 3v3 is an hour. Returning nil is
        // what lets the chip disable itself rather than offering a window the
        // rules would refuse.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        let nineThirty = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 29, hour: 21, minute: 30
        ))!

        XCTAssertNil(
            QueueWindow.tonight.window(format: .threeVThree, now: nineThirty, calendar: calendar)
        )
    }

    func testTomorrowEveningIsAlwaysAFullEvening() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!

        let nineThirtyPM = calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 29, hour: 21, minute: 30
        ))!

        let window = QueueWindow.tomorrowEvening.window(
            format: .threeVThree, now: nineThirtyPM, calendar: calendar
        )

        XCTAssertNotNil(window)
        XCTAssertEqual(
            window.map { $0.end.timeIntervalSince($0.start) },
            5 * 3600,
            "five to ten, whatever time it is now"
        )
    }

    func testCustomHasNoDerivedWindow() {
        XCTAssertNil(QueueWindow.custom.window(format: .threeVThree, now: now))
    }

    func testExpiryIsClampedIntoTheTicketLifetimeRange() {
        // A window closing in five minutes would produce a ticket the create
        // rule refuses; a window a week out would produce one that outlives its
        // own usefulness. Both are clamped, because the user chose a window and
        // not an expiry.
        let soon = QueueWindow.expiry(forWindowEnd: now.addingTimeInterval(300), now: now)
        XCTAssertEqual(
            soon.timeIntervalSince(now),
            MatchTicket.lifetimeRange.lowerBound,
            accuracy: 1
        )

        let distant = QueueWindow.expiry(
            forWindowEnd: now.addingTimeInterval(7 * 24 * 3600),
            now: now
        )
        XCTAssertEqual(
            distant.timeIntervalSince(now),
            MatchTicket.lifetimeRange.upperBound,
            accuracy: 1
        )

        let ordinary = QueueWindow.expiry(forWindowEnd: now.addingTimeInterval(4 * 3600), now: now)
        XCTAssertEqual(ordinary.timeIntervalSince(now), 4 * 3600, accuracy: 1)
    }

    func testADerivedExpiryAlwaysClearsTicketValidation() {
        // The property that matters: whatever window a chip produces, the ticket
        // it builds must pass the same validation the create rule mirrors.
        for window in QueueWindow.allCases {
            guard let range = window.window(format: .threeVThree, now: Date()) else { continue }
            let expiry = QueueWindow.expiry(forWindowEnd: range.end)

            XCTAssertNil(
                MatchTicket.validate(
                    courtIds: ["court-1"],
                    windowStart: range.start,
                    windowEnd: range.end,
                    expiresAt: expiry,
                    format: .threeVThree
                ),
                "\(window.rawValue) produced a ticket its own validation refuses"
            )
        }
    }
}
