import XCTest
@testable import hoopr

/// Guards what deleting an account does to everything that names it
/// (`AccountDeletionPlan`, `PRE_LAUNCH_AUDIT.md` §2.1) — the order of the
/// steps and which documents are left alone, both of which are the design.
final class AccountDeletionPlanTests: XCTestCase {
    typealias Step = AccountDeletionPlan.SquadStep

    private let me = "me"
    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func squad(_ id: String, leader: String, members: [String]) -> Squad {
        Squad(
            id: id,
            name: "Rim Reapers",
            nameLower: "rim reapers",
            leaderId: leader,
            memberIds: members,
            format: .threeVThree,
            iconKey: Squad.defaultIconKey,
            colorKey: Squad.defaultColorKey,
            region: "Durham",
            createdAt: nil,
            updatedAt: nil
        )
    }

    private func match(
        _ id: String,
        home: String,
        away: String,
        status: SeasonGame.Status = .scheduled
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
            scheduledTime: now.addingTimeInterval(3600),
            status: status,
            arrivedPlayerIds: [],
            homeReport: nil,
            awayReport: nil,
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

    // MARK: - Season play

    /// The bug this order prevents (audit §3.7): disbanding first deletes the
    /// only document that authorises the cancel, and the other squad is left
    /// "Waiting on…" a report that can never come.
    func testALedSquadCancelsItsMatchAndLeavesTheQueueBeforeItIsDisbanded() {
        let steps = AccountDeletionPlan.squadSteps(
            uid: me,
            squads: [squad("mine", leader: me, members: [me, "friend"])],
            seasonGames: [match("g1", home: "mine", away: "theirs")]
        )

        XCTAssertEqual(steps, [
            .cancelMatch(gameId: "g1", squadId: "mine"),
            .withdrawTicket(squadId: "mine"),
            .disband(squadId: "mine"),
        ])
    }

    /// A member isn't the squad: it keeps its match, its ticket and its
    /// leader, and loses one player.
    func testASquadTheAccountIsOnlyOnIsLeftAndNothingElse() {
        let steps = AccountDeletionPlan.squadSteps(
            uid: me,
            squads: [squad("theirs", leader: "captain", members: ["captain", me])],
            seasonGames: [match("g1", home: "theirs", away: "other")]
        )

        XCTAssertEqual(steps, [.leave(squadId: "theirs")])
    }

    /// Finished matches are history both squads keep; only a `scheduled` one
    /// is cancelled (and only that write would be admitted by the rules).
    func testOnlyScheduledMatchesAreCancelled() {
        let steps = AccountDeletionPlan.squadSteps(
            uid: me,
            squads: [squad("mine", leader: me, members: [me])],
            seasonGames: [
                match("done", home: "mine", away: "a", status: .confirmed),
                match("off", home: "mine", away: "b", status: .cancelled),
                match("argued", home: "c", away: "mine", status: .disputed),
                match("next", home: "d", away: "mine"),
            ]
        )

        XCTAssertEqual(steps, [
            .cancelMatch(gameId: "next", squadId: "mine"),
            .withdrawTicket(squadId: "mine"),
            .disband(squadId: "mine"),
        ])
    }

    func testAnotherSquadsMatchIsNeverTouched() {
        let steps = AccountDeletionPlan.squadSteps(
            uid: me,
            squads: [squad("mine", leader: me, members: [me])],
            seasonGames: [match("elsewhere", home: "x", away: "y")]
        )

        XCTAssertFalse(steps.contains { if case .cancelMatch = $0 { true } else { false } })
    }

    /// The published list is the account's own squads, but the plan doesn't
    /// lean on that: a squad it isn't on yields nothing.
    func testASquadTheAccountIsNotOnYieldsNoSteps() {
        let steps = AccountDeletionPlan.squadSteps(
            uid: me,
            squads: [squad("strangers", leader: "a", members: ["a", "b"])],
            seasonGames: []
        )

        XCTAssertTrue(steps.isEmpty)
    }

    /// Same input, same order — a retry walks the steps the first try did.
    func testTheOrderIsStableAcrossSquads() {
        let squads = [
            squad("b-joined", leader: "captain", members: ["captain", me]),
            squad("a-led", leader: me, members: [me]),
        ]

        let steps = AccountDeletionPlan.squadSteps(uid: me, squads: squads, seasonGames: [])

        XCTAssertEqual(steps, [
            .withdrawTicket(squadId: "a-led"),
            .disband(squadId: "a-led"),
            .leave(squadId: "b-joined"),
        ])
        XCTAssertEqual(
            steps,
            AccountDeletionPlan.squadSteps(uid: me, squads: squads.reversed(), seasonGames: [])
        )
    }

    // MARK: - Runs

    func testAHostedRunIsCancelledUnlessItAlreadyHappened() {
        for status in ["open", "full", "in_progress"] {
            XCTAssertEqual(AccountDeletionPlan.runAction(hostId: me, status: status, uid: me), .cancel, status)
        }
        // Deleting it would take it out of every other player's history.
        XCTAssertEqual(AccountDeletionPlan.runAction(hostId: me, status: "completed", uid: me), .keep)
    }

    /// Mirrors the roster rule's `resource.data.status in ['open', 'full']`:
    /// asking to leave any other run would be refused and stop the deletion.
    func testAJoinedRunIsLeftOnlyWhileTheRulesAllowIt() {
        XCTAssertEqual(AccountDeletionPlan.runAction(hostId: "host", status: "open", uid: me), .leave)
        XCTAssertEqual(AccountDeletionPlan.runAction(hostId: "host", status: "full", uid: me), .leave)
        XCTAssertEqual(AccountDeletionPlan.runAction(hostId: "host", status: "in_progress", uid: me), .keep)
        XCTAssertEqual(AccountDeletionPlan.runAction(hostId: "host", status: "completed", uid: me), .keep)
        XCTAssertEqual(AccountDeletionPlan.runAction(hostId: "host", status: "something-new", uid: me), .keep)
    }

    // MARK: - The confirmation

    func testTheWordArmsTheButtonWhateverItsCaseOrSpacing() {
        XCTAssertTrue(AccountDeletionPlan.isConfirmed("DELETE"))
        XCTAssertTrue(AccountDeletionPlan.isConfirmed(" delete\n"))
        XCTAssertFalse(AccountDeletionPlan.isConfirmed("DELET"))
        XCTAssertFalse(AccountDeletionPlan.isConfirmed(""))
    }

    func testDeleteNeedsBothProofsAndNothingInFlight() {
        XCTAssertTrue(DeleteAccountViewModel.canDelete(password: "pw", confirmation: "delete", isDeleting: false))
        XCTAssertFalse(DeleteAccountViewModel.canDelete(password: "", confirmation: "DELETE", isDeleting: false))
        XCTAssertFalse(DeleteAccountViewModel.canDelete(password: "pw", confirmation: "", isDeleting: false))
        XCTAssertFalse(DeleteAccountViewModel.canDelete(password: "pw", confirmation: "DELETE", isDeleting: true))
    }

    // MARK: - Wording

    func testAWrongPasswordIsNamedAndEveryLaterFailureSaysItCanResume() {
        XCTAssertEqual(
            DeleteAccountViewModel.message(for: AuthError.wrongCredentials),
            DeleteAccountViewModel.wrongPassword
        )
        XCTAssertEqual(
            DeleteAccountViewModel.message(for: SquadError.permissionDenied),
            DeleteAccountViewModel.interrupted
        )

        let offline = DeleteAccountViewModel.message(for: GameError.network)
        XCTAssertTrue(offline.hasPrefix(FailureText.network))
        XCTAssertTrue(offline.hasSuffix(DeleteAccountViewModel.interrupted))
    }

    /// A led squad is other people's too, so the sheet says so before asking
    /// for anything — and says nothing about squads to someone who leads none.
    func testTheSheetWarnsAboutASquadOnlyWhenOneWillBeDisbanded() {
        XCTAssertFalse(DeleteAccountSheet.consequences(ledSquadNames: []).contains("disbanded"))
        XCTAssertTrue(
            DeleteAccountSheet.consequences(ledSquadNames: ["Rim Reapers"])
                .contains("Rim Reapers is disbanded for everyone on it")
        )
        XCTAssertTrue(DeleteAccountSheet.consequences(ledSquadNames: ["A", "B"]).contains("squads you lead"))
    }
}
