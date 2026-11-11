import XCTest
@testable import hoopr

/// `SeasonGameNotifications.plan(for:opponentName:courtName:now:)` — the part
/// of Phase 5 whose bugs are invisible on a screen. `UNUserNotificationCenter`
/// cannot be exercised here (`NotificationService` is a `@MainActor` class over
/// a vendor singleton, and no test in this suite instantiates a service), so
/// this is the only place a wrong fire date, a duplicating identifier, or a
/// mistimed reminder is ever caught.
final class SeasonGameNotificationsTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_756_000_000)

    private func game(
        id: String = "game-1",
        status: SeasonGame.Status = .scheduled,
        scheduledOffset: TimeInterval = 4 * 3600
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
            scheduledTime: now.addingTimeInterval(scheduledOffset),
            status: status,
            arrivedPlayerIds: [],
            homeReport: nil,
            awayReport: nil,
            homeScore: nil,
            awayScore: nil,
            result: nil,
            cancelledBySquadId: nil,
            createdBy: "leader-away",
            createdAt: now,
            updatedAt: nil,
            confirmedAt: nil
        )
    }

    // MARK: - A future game plans all three

    func testAFutureGamePlansThreeNotifications() {
        let planned = SeasonGameNotifications.plan(
            for: game(),
            opponentName: "Court Vision",
            courtName: "Duke Park",
            now: now
        )

        XCTAssertEqual(planned.count, 3)
        XCTAssertEqual(Set(planned.map(\.identifier)).count, 3, "identifiers must be distinct")
    }

    func testTheReminderFiresSixtyMinutesBeforeTipOff() {
        let match = game(scheduledOffset: 4 * 3600)
        let planned = SeasonGameNotifications.plan(
            for: match, opponentName: "Court Vision", courtName: "Duke Park", now: now
        )

        let reminder = planned.first { $0.identifier.hasSuffix(":reminder") }
        XCTAssertEqual(
            reminder?.fireDate,
            match.scheduledTime.addingTimeInterval(-SeasonGameNotifications.reminderLead)
        )
        XCTAssertEqual(reminder?.body, "3v3 vs Court Vision in an hour — Duke Park")
    }

    func testTipOffFiresExactlyAtScheduledTime() {
        let match = game()
        let planned = SeasonGameNotifications.plan(
            for: match, opponentName: "Court Vision", courtName: "Duke Park", now: now
        )

        let tipoff = planned.first { $0.identifier.hasSuffix(":tipoff") }
        XCTAssertEqual(tipoff?.fireDate, match.scheduledTime)
        XCTAssertEqual(tipoff?.body, "Tip-off. Tap to mark your squad as arrived.")
    }

    func testRecapFiresNinetyMinutesAfterTipOff() {
        let match = game()
        let planned = SeasonGameNotifications.plan(
            for: match, opponentName: "Court Vision", courtName: "Duke Park", now: now
        )

        let recap = planned.first { $0.identifier.hasSuffix(":recap") }
        XCTAssertEqual(
            recap?.fireDate,
            match.scheduledTime.addingTimeInterval(SeasonGameNotifications.recapDelay)
        )
        XCTAssertEqual(recap?.body, "How'd it go? Record the result.")
    }

    // MARK: - None for a cancelled match

    func testACancelledMatchPlansNothingRegardlessOfTiming() {
        let match = game(status: .cancelled, scheduledOffset: 4 * 3600)
        let planned = SeasonGameNotifications.plan(
            for: match, opponentName: "Court Vision", courtName: "Duke Park", now: now
        )
        XCTAssertTrue(planned.isEmpty)
    }

    // MARK: - Past triggers are omitted, not backdated

    /// A `UNTimeIntervalNotificationTrigger` fires immediately for a past
    /// date rather than refusing it — so a trigger already behind `now` has to
    /// be dropped here, or "you joined a match starting in five minutes" would
    /// dump every notification on the phone at once.
    func testAGameFullyInThePastPlansNothing() {
        let match = game(scheduledOffset: -4 * 3600)
        let planned = SeasonGameNotifications.plan(
            for: match,
            opponentName: "Court Vision",
            courtName: "Duke Park",
            // Well past even the recap window.
            now: now.addingTimeInterval(3 * 3600)
        )
        XCTAssertTrue(planned.isEmpty)
    }

    /// Between tip-off and the recap window, only the recap is still ahead of
    /// `now` — and it still gets scheduled. Ship-it-anyway: the recap
    /// points at a screen Phase 6 hasn't built yet, but a notification added
    /// later would miss every game played between now and then.
    func testAGameJustPastTipOffStillPlansTheRecap() {
        let match = game(scheduledOffset: -10 * 60)
        let planned = SeasonGameNotifications.plan(
            for: match, opponentName: "Court Vision", courtName: "Duke Park", now: now
        )

        XCTAssertEqual(planned.count, 1)
        XCTAssertTrue(planned[0].identifier.hasSuffix(":recap"))
    }

    /// Between the reminder's own moment and tip-off, the reminder has already
    /// passed but tip-off and the recap haven't.
    func testAGameBetweenReminderAndTipOffPlansTipOffAndRecapOnly() {
        let match = game(scheduledOffset: 30 * 60)
        let planned = SeasonGameNotifications.plan(
            for: match, opponentName: "Court Vision", courtName: "Duke Park", now: now
        )

        let kinds = Set(planned.compactMap { $0.identifier.components(separatedBy: ":").last })
        XCTAssertEqual(kinds, ["tipoff", "recap"])
    }

    // MARK: - Stable identifiers across a re-plan

    func testReplanningTheSameGameProducesIdenticalIdentifiers() {
        let match = game()
        let first = SeasonGameNotifications.plan(
            for: match, opponentName: "Court Vision", courtName: "Duke Park", now: now
        )
        let second = SeasonGameNotifications.plan(
            for: match,
            opponentName: "Court Vision",
            courtName: "Duke Park",
            now: now.addingTimeInterval(60)
        )

        XCTAssertEqual(Set(first.map(\.identifier)), Set(second.map(\.identifier)))
    }

    /// A shrinking plan — fewer entries because time has passed — still names
    /// the *same* identifier for whichever kind survives in both. This is what
    /// makes `NotificationService`'s remove-then-add land on the same slot
    /// even as a match moves through its own timeline.
    func testTheRecapIdentifierIsIdenticalWhetherPlannedEarlyOrLate() {
        let match = game(scheduledOffset: 4 * 3600)

        let early = SeasonGameNotifications.plan(
            for: match, opponentName: "Court Vision", courtName: "Duke Park", now: now
        )
        let late = SeasonGameNotifications.plan(
            for: match,
            opponentName: "Court Vision",
            courtName: "Duke Park",
            now: match.scheduledTime.addingTimeInterval(10 * 60) // past tip-off; only recap remains
        )

        let earlyRecap = early.first { $0.identifier.hasSuffix(":recap") }
        let lateRecap = late.first { $0.identifier.hasSuffix(":recap") }

        XCTAssertEqual(late.count, 1, "only the recap should remain this late")
        XCTAssertEqual(earlyRecap?.identifier, lateRecap?.identifier)
    }

    func testIdentifierFormat() {
        XCTAssertEqual(
            SeasonGameNotifications.identifier(for: "abc123", kind: .reminder),
            "seasonGame:abc123:reminder"
        )
        XCTAssertEqual(
            SeasonGameNotifications.identifier(for: "abc123", kind: .tipoff),
            "seasonGame:abc123:tipoff"
        )
        XCTAssertEqual(
            SeasonGameNotifications.identifier(for: "abc123", kind: .recap),
            "seasonGame:abc123:recap"
        )
    }

    func testAllIdentifiersNamesAllThreeRegardlessOfWhatWasPlanned() {
        // What `NotificationService` removes before adding — always three,
        // even when the last plan only produced one, so a shrinking plan
        // actually clears the ones it dropped.
        let all = SeasonGameNotifications.allIdentifiers(for: "game-9")
        XCTAssertEqual(Set(all), [
            "seasonGame:game-9:reminder",
            "seasonGame:game-9:tipoff",
            "seasonGame:game-9:recap",
        ])
    }

    // MARK: - Two different games never collide

    func testTwoDifferentGamesProduceDisjointIdentifiers() {
        let a = SeasonGameNotifications.plan(
            for: game(id: "game-a"), opponentName: "Court Vision", courtName: "Duke Park", now: now
        )
        let b = SeasonGameNotifications.plan(
            for: game(id: "game-b"), opponentName: "Court Vision", courtName: "Duke Park", now: now
        )

        XCTAssertTrue(Set(a.map(\.identifier)).isDisjoint(with: Set(b.map(\.identifier))))
    }
}
