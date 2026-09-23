import FirebaseFirestore
import XCTest
@testable import hoopr

/// Guards the contract between `Game` and the documents actually stored in the
/// `games` collection, plus the pure rules the client and `firestore.rules`
/// both encode. Decoding runs through `Firestore.Decoder` — the same decoder
/// `GameService` uses — so a field rename breaks a test here rather than
/// silently emptying the Local Runs lists.
final class GameTests: XCTestCase {

    private let decoder = Firestore.Decoder()

    // MARK: - Decoding

    private func storedDocument(
        overrides: [String: Any] = [:],
        removing keys: [String] = []
    ) -> [String: Any] {
        var document: [String: Any] = [
            "id": "game-001",
            "hostId": "host-uid",
            "courtId": "court-abc",
            "scheduledTime": Timestamp(date: Date(timeIntervalSince1970: 1_780_000_000)),
            "isPublic": true,
            "maxPlayers": 10,
            "status": "open",
            "playerIds": ["host-uid", "player-2"],
            "queuedPlayerIds": [],
            "createdAt": Timestamp(date: Date(timeIntervalSince1970: 1_779_000_000)),
            "updatedAt": Timestamp(date: Date(timeIntervalSince1970: 1_779_000_030)),
        ]
        document.merge(overrides) { _, new in new }
        keys.forEach { document.removeValue(forKey: $0) }
        return document
    }

    func testDecodesStoredDocumentShape() throws {
        let game = try decoder.decode(Game.self, from: storedDocument())

        XCTAssertEqual(game.id, "game-001")
        XCTAssertEqual(game.hostId, "host-uid")
        XCTAssertEqual(game.courtId, "court-abc")
        XCTAssertEqual(game.scheduledTime, Date(timeIntervalSince1970: 1_780_000_000))
        XCTAssertTrue(game.isPublic)
        XCTAssertEqual(game.maxPlayers, 10)
        XCTAssertEqual(game.status, .open)
        XCTAssertEqual(game.playerIds, ["host-uid", "player-2"])
        XCTAssertTrue(game.queuedPlayerIds.isEmpty)
        XCTAssertEqual(game.createdAt, Date(timeIntervalSince1970: 1_779_000_000))
        XCTAssertEqual(game.updatedAt, Date(timeIntervalSince1970: 1_779_000_030))
    }

    /// A document read back before the server resolves its `serverTimestamp()`
    /// sentinels carries nulls on both bookkeeping fields — the same reason
    /// `UserProfile` keeps them optional. `scheduledTime` is client-supplied
    /// and must stay required.
    func testDecodesPendingServerTimestamps() throws {
        let game = try decoder.decode(
            Game.self,
            from: storedDocument(overrides: [
                "createdAt": NSNull(),
                "updatedAt": NSNull(),
            ])
        )

        XCTAssertNil(game.createdAt)
        XCTAssertNil(game.updatedAt)
        XCTAssertEqual(game.scheduledTime, Date(timeIntervalSince1970: 1_780_000_000))
    }

    /// A run with no tip-off time can't be scheduled, listed, or aged out.
    /// It must fail loudly rather than decode into something unusable.
    func testMissingScheduledTimeFailsToDecode() {
        XCTAssertThrowsError(
            try decoder.decode(Game.self, from: storedDocument(removing: ["scheduledTime"]))
        )
    }

    func testMissingCourtIdFailsToDecode() {
        XCTAssertThrowsError(
            try decoder.decode(Game.self, from: storedDocument(removing: ["courtId"]))
        )
    }

    /// The wire format is snake-cased for this one case; a drift here would
    /// otherwise only show up as a run that refuses to decode in production.
    func testDecodesInProgressStatusRawValue() throws {
        let game = try decoder.decode(
            Game.self,
            from: storedDocument(overrides: ["status": "in_progress"])
        )

        XCTAssertEqual(game.status, .inProgress)
        XCTAssertEqual(Game.Status.inProgress.rawValue, "in_progress")
    }

    // MARK: - Derived status

    /// The client computes this on the write path and `firestore.rules`
    /// recomputes it server-side. If they disagree, every write is rejected as
    /// `permission-denied`.
    func testStatusIsDerivedFromRoster() {
        XCTAssertEqual(Game.status(playerCount: 1, maxPlayers: 10), .open)
        XCTAssertEqual(Game.status(playerCount: 9, maxPlayers: 10), .open)
        XCTAssertEqual(Game.status(playerCount: 10, maxPlayers: 10), .full)
        // An over-filled roster is still full, not "past full".
        XCTAssertEqual(Game.status(playerCount: 11, maxPlayers: 10), .full)
    }

    // MARK: - Form validation

    /// `Game.validate` is the only thing standing between the form and a
    /// `permission-denied`, so every branch the create rule can reject needs a
    /// case here.
    func testValidateAcceptsAWellFormedRun() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)

        XCTAssertNil(Game.validate(
            courtId: "court-abc",
            scheduledTime: now.addingTimeInterval(3_600),
            maxPlayers: 10,
            now: now
        ))
    }

    func testValidateRejectsAnEmptyCourt() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)

        for courtId in ["", "   "] {
            XCTAssertEqual(
                Game.validate(
                    courtId: courtId,
                    scheduledTime: now.addingTimeInterval(3_600),
                    maxPlayers: 10,
                    now: now
                ),
                .invalidCourt,
                "Whitespace is not a court ID"
            )
        }
    }

    func testValidateRejectsRosterSizesOutsideTheRange() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)

        func validate(_ maxPlayers: Int) -> GameError? {
            Game.validate(
                courtId: "court-abc",
                scheduledTime: now.addingTimeInterval(3_600),
                maxPlayers: maxPlayers,
                now: now
            )
        }

        XCTAssertEqual(validate(Game.maxPlayersRange.lowerBound - 1), .invalidRoster)
        XCTAssertEqual(validate(Game.maxPlayersRange.upperBound + 1), .invalidRoster)
        XCTAssertEqual(validate(0), .invalidRoster)
        // The bounds themselves are legal — the rules use the same inclusive range.
        XCTAssertNil(validate(Game.maxPlayersRange.lowerBound))
        XCTAssertNil(validate(Game.maxPlayersRange.upperBound))
    }

    func testValidateRejectsSchedulesOutsideTheWindow() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)

        func validate(offset: TimeInterval) -> GameError? {
            Game.validate(
                courtId: "court-abc",
                scheduledTime: now.addingTimeInterval(offset),
                maxPlayers: 10,
                now: now
            )
        }

        XCTAssertEqual(validate(offset: -3_600), .scheduleTooSoon, "The past is not schedulable")
        XCTAssertEqual(validate(offset: 0), .scheduleTooSoon, "\"Now\" would race the round trip")
        XCTAssertEqual(
            validate(offset: Game.minimumLeadTime - 1),
            .scheduleTooSoon,
            "Just inside the notice window is still too soon"
        )
        XCTAssertNil(validate(offset: Game.minimumLeadTime), "The boundary itself is allowed")
        XCTAssertNil(validate(offset: Game.schedulingWindow))
        XCTAssertEqual(validate(offset: Game.schedulingWindow + 1), .scheduleTooFar)
    }

    /// Court is checked before roster, roster before schedule — so a form with
    /// several problems names one at a time in a stable order rather than
    /// flickering between them.
    func testValidateReportsProblemsInAStableOrder() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)

        XCTAssertEqual(
            Game.validate(courtId: "", scheduledTime: now, maxPlayers: 0, now: now),
            .invalidCourt
        )
        XCTAssertEqual(
            Game.validate(courtId: "court-abc", scheduledTime: now, maxPlayers: 0, now: now),
            .invalidRoster
        )
    }

    func testValidMaxPlayersClampsToSupportedRange() {
        XCTAssertEqual(Game.validMaxPlayers(0), Game.maxPlayersRange.lowerBound)
        XCTAssertEqual(Game.validMaxPlayers(1), Game.maxPlayersRange.lowerBound)
        XCTAssertEqual(Game.validMaxPlayers(10), 10)
        XCTAssertEqual(Game.validMaxPlayers(999), Game.maxPlayersRange.upperBound)
    }

    func testOpenSlotsNeverGoesNegative() throws {
        let overfilled = try decoder.decode(
            Game.self,
            from: storedDocument(overrides: [
                "maxPlayers": 2,
                "playerIds": ["a", "b", "c"],
                "status": "full",
            ])
        )

        XCTAssertEqual(overfilled.openSlots, 0)
        XCTAssertTrue(overfilled.isFull)
    }

    // MARK: - Roster membership

    func testRosterMembershipQueries() throws {
        let game = try decoder.decode(
            Game.self,
            from: storedDocument(overrides: [
                "playerIds": ["host-uid", "player-2"],
                "queuedPlayerIds": ["waiting-1"],
            ])
        )

        XCTAssertTrue(game.isHost("host-uid"))
        XCTAssertFalse(game.isHost("player-2"))
        XCTAssertTrue(game.hasPlayer("player-2"))
        XCTAssertFalse(game.hasPlayer("waiting-1"))
        XCTAssertTrue(game.hasWaitlisted("waiting-1"))

        // Signed out: every membership question answers no rather than
        // matching a document that happens to carry an empty string.
        XCTAssertFalse(game.isHost(nil))
        XCTAssertFalse(game.hasPlayer(nil))
        XCTAssertFalse(game.hasWaitlisted(nil))
    }

    // MARK: - Visibility

    /// The Firestore query's cutoff is fixed when its listener attaches, so
    /// this predicate is what actually retires a run during a long session.
    func testVisibilityFollowsTheGraceWindow() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)

        func game(offset: TimeInterval, status: String = "open") throws -> Game {
            try decoder.decode(
                Game.self,
                from: storedDocument(overrides: [
                    "scheduledTime": Timestamp(date: now.addingTimeInterval(offset)),
                    "status": status,
                ])
            )
        }

        XCTAssertTrue(try game(offset: 3_600).isVisible(at: now), "Upcoming runs are listed")
        XCTAssertTrue(
            try game(offset: -Game.visibilityGrace + 60).isVisible(at: now),
            "A run already underway is still joinable"
        )
        XCTAssertFalse(
            try game(offset: -Game.visibilityGrace - 60).isVisible(at: now),
            "A run past its grace window drops out"
        )
        XCTAssertFalse(
            try game(offset: 3_600, status: "completed").isVisible(at: now),
            "A completed run is never listed, however soon it was scheduled"
        )
    }

    func testVisibilityCutoffMatchesTheGraceWindow() {
        let now = Date(timeIntervalSince1970: 1_780_000_000)

        XCTAssertEqual(
            Game.visibilityCutoff(from: now),
            now.addingTimeInterval(-Game.visibilityGrace)
        )
    }

    // MARK: - Participation streak

    private func streakCalendar() -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func weeksAgo(_ n: Int, from now: Date) -> Date {
        streakCalendar().date(byAdding: .weekOfYear, value: -n, to: now)!
    }

    private func completedGame(at date: Date) throws -> Game {
        try decoder.decode(
            Game.self,
            from: storedDocument(overrides: [
                "status": "completed",
                "completedAt": Timestamp(date: date),
            ])
        )
    }

    func testStreakWithNoGamesIsZero() {
        XCTAssertEqual(Game.calculateStreak(from: []), 0)
    }

    /// A game with no `completedAt` — never happens for a real completed run,
    /// but the function shouldn't crash or miscount if it did.
    func testStreakIgnoresGamesWithoutACompletionTimestamp() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let game = try decoder.decode(Game.self, from: storedDocument())

        XCTAssertEqual(Game.calculateStreak(from: [game], now: now), 0)
    }

    func testStreakCountsACompletionInTheCurrentWeek() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let game = try completedGame(at: now)

        XCTAssertEqual(Game.calculateStreak(from: [game], now: now), 1)
    }

    func testStreakCollapsesMultipleCompletionsInTheSameWeek() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let games = try [now, now.addingTimeInterval(3_600)].map { try completedGame(at: $0) }

        XCTAssertEqual(Game.calculateStreak(from: games, now: now), 1)
    }

    func testStreakCountsConsecutiveWeeksBackFromNow() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let games = try (0...2).map { try completedGame(at: weeksAgo($0, from: now)) }

        XCTAssertEqual(Game.calculateStreak(from: games, now: now), 3)
    }

    /// The rule that gives the streak its name: a run three weeks back can't
    /// bridge a week with nothing in it.
    func testStreakStopsAtTheFirstGapInWeeks() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        // Weeks 0 and 1 have a completion; week 2 is skipped; week 3 does too.
        let games = try [0, 1, 3].map { try completedGame(at: weeksAgo($0, from: now)) }

        XCTAssertEqual(Game.calculateStreak(from: games, now: now), 2)
    }

    /// Mirrors the plan's own example: a streak that hasn't posted a
    /// completion yet this week reads as `0`, even with a run last week and
    /// the week before.
    func testStreakResetsWhenTheCurrentWeekHasNoCompletion() throws {
        let now = Date(timeIntervalSince1970: 1_780_000_000)
        let games = try [1, 2].map { try completedGame(at: weeksAgo($0, from: now)) }

        XCTAssertEqual(
            Game.calculateStreak(from: games, now: now), 0,
            "current week is empty, so the streak has already reset"
        )
    }

    // MARK: - Presentation

    func testScheduledTextIsRelativeForTodayAndTomorrow() throws {
        let calendar = Calendar.current
        let now = Date()

        func game(at date: Date) throws -> Game {
            try decoder.decode(
                Game.self,
                from: storedDocument(overrides: ["scheduledTime": Timestamp(date: date)])
            )
        }

        // Mid-afternoon, so "+1 day" can't spill across a boundary and land on
        // the wrong calendar day.
        let today = calendar.date(bySettingHour: 14, minute: 30, second: 0, of: now)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let nextWeek = calendar.date(byAdding: .day, value: 7, to: today)!

        XCTAssertTrue(try game(at: today).scheduledText(relativeTo: now).hasPrefix("Today · "))
        XCTAssertTrue(try game(at: tomorrow).scheduledText(relativeTo: now).hasPrefix("Tomorrow · "))

        let absolute = try game(at: nextWeek).scheduledText(relativeTo: now)
        XCTAssertFalse(absolute.hasPrefix("Today"))
        XCTAssertFalse(absolute.hasPrefix("Tomorrow"))
        XCTAssertTrue(absolute.contains(" · "))
    }

    func testRosterText() throws {
        let game = try decoder.decode(Game.self, from: storedDocument())
        XCTAssertEqual(game.rosterText, "2 / 10 players")
    }

    // MARK: - Invite link

    /// The format the (unbuilt) deep-link handler will have to parse. Pinning
    /// it here means the scheme can't be changed on one side alone.
    func testInviteLinkFormat() throws {
        let game = try decoder.decode(Game.self, from: storedDocument())

        XCTAssertEqual(game.inviteLink, "hoopsrn://game/game-001")
        XCTAssertEqual(InviteLink.text(forGameId: "5FQxT2mKpLwd0aZbYc19"),
                       "hoopsrn://game/5FQxT2mKpLwd0aZbYc19")
    }

    /// Firestore's own IDs are alphanumeric, so this only guards a hand-written
    /// one — but a link that isn't a URL is worse than no link.
    func testInviteLinkEncodesAnUnsafeId() {
        let link = InviteLink.text(forGameId: "a b/c?d")

        XCTAssertEqual(link, "hoopsrn://game/a%20b%2Fc%3Fd")
        XCTAssertNotNil(URL(string: link))
    }

    // MARK: - Distance

    func testDistanceFormatting() {
        // One decimal under ten miles, whole numbers above.
        XCTAssertEqual(Distance.text(Distance.meters(miles: 1.24)), "1.2 mi")
        XCTAssertEqual(Distance.text(Distance.meters(miles: 12.4)), "12 mi")
        XCTAssertEqual(Distance.miles(Distance.meters(miles: 5)), 5, accuracy: 0.0001)
    }

    /// Home's band and the map's court card set the number and the unit at
    /// different weights, so they read the two halves separately. The joined
    /// form must still be exactly the halves put back together — the rounding
    /// rule lives in one place, and the split can't round differently from the
    /// string every other surface shows.
    func testTheSplitDistanceRejoinsToTheSameString() {
        for miles in [0.04, 0.7, 1.24, 9.94, 9.96, 12.4, 104.6] {
            let meters = Distance.meters(miles: miles)
            XCTAssertEqual(
                "\(Distance.valueText(meters)) \(Distance.unit)", Distance.text(meters),
                "the split and joined forms disagree at \(miles) mi"
            )
        }
        XCTAssertEqual(Distance.valueText(Distance.meters(miles: 0.7)), "0.7")
    }

    // MARK: - Presentation strings the redesigned surfaces read

    /// `timeText`, `dayText` and `spotsText` were added in UI revamp Phase 2b
    /// and live here, beside `rosterText` and `scheduledText()`, because the
    /// Home band and the Runs board both read them — a copy on either view
    /// model would let the two disagree about what time the same run is at.

    private func run(
        players: [String] = ["a"],
        maxPlayers: Int = 10,
        at scheduledTime: Date = Date()
    ) -> Game {
        Game(
            id: "game-1",
            hostId: "host",
            courtId: "court-a",
            scheduledTime: scheduledTime,
            isPublic: true,
            maxPlayers: maxPlayers,
            status: Game.status(playerCount: players.count, maxPlayers: maxPlayers),
            playerIds: players,
            queuedPlayerIds: [],
            createdAt: scheduledTime,
            updatedAt: scheduledTime,
            completedAt: nil
        )
    }

    // MARK: Day and time

    /// The band sets the day and the time apart; `scheduledText()` joins them.
    /// Both derive from `scheduledTime`, and this is what pins that they stay
    /// consistent — a run reading "Tonight" in the band and "Tomorrow" on its
    /// card would be worse than either being wrong.
    func testAnEveningRunTodayReadsAsTonight() {
        let calendar = Calendar.current
        let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date())!
        let evening = calendar.date(bySettingHour: 19, minute: 30, second: 0, of: morning)!
        XCTAssertEqual(run(at: evening).dayText(relativeTo: morning), "Tonight")
    }

    /// "Tonight · 11:15 AM" was on the device (2026-09-23). Before 5 PM a
    /// same-day run is "Today" — the word `scheduledText()` already used.
    func testAMorningRunTodayReadsAsToday() {
        let calendar = Calendar.current
        let early = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
        let lateMorning = calendar.date(bySettingHour: 11, minute: 15, second: 0, of: early)!
        let fiveOClock = calendar.date(bySettingHour: Game.eveningStartHour, minute: 0, second: 0, of: early)!

        XCTAssertEqual(run(at: lateMorning).dayText(relativeTo: early), "Today")
        XCTAssertEqual(run(at: fiveOClock).dayText(relativeTo: early), "Tonight")
    }

    func testTomorrowReadsAsTomorrow() {
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now)!
        XCTAssertEqual(run(at: tomorrow).dayText(relativeTo: now), "Tomorrow")
    }

    /// Past the two days a pickup run is usually organised within, the label
    /// is the date — the same call `scheduledText()` makes.
    func testFurtherOutFallsBackToTheDate() {
        let now = Date()
        let later = Calendar.current.date(byAdding: .day, value: 4, to: now)!
        let label = run(at: later).dayText(relativeTo: now)

        XCTAssertNotEqual(label, "Tonight")
        XCTAssertNotEqual(label, "Tomorrow")
        XCTAssertFalse(label.isEmpty)
    }

    /// The boundary is the calendar day, not elapsed hours: a run at 11pm
    /// tonight and one at 1am tomorrow are a different answer to "am I out
    /// tonight?", two hours apart.
    func testTheDayBoundaryIsTheCalendarDayNotElapsedHours() {
        let calendar = Calendar.current
        let lateTonight = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: Date())!
        let earlyTomorrow = calendar.date(byAdding: .hour, value: 2, to: lateTonight)!

        XCTAssertEqual(run(at: lateTonight).dayText(relativeTo: lateTonight), "Tonight")
        XCTAssertEqual(run(at: earlyTomorrow).dayText(relativeTo: lateTonight), "Tomorrow")
    }

    /// The time half carries no day, or the band would say it twice.
    func testTimeTextCarriesNoDay() {
        let text = run().timeText
        XCTAssertFalse(text.contains("Tonight"))
        XCTAssertFalse(text.contains("Today"))
        XCTAssertFalse(text.contains("·"))
    }

    // MARK: Spots left

    /// The redesign puts *spots left* where the capacity bar used to be: the
    /// decision is whether you can still get on, which is one number.
    func testSpotsLeftCountsDownFromCapacity() {
        XCTAssertEqual(run(players: ["a"], maxPlayers: 10).spotsText, "9 spots left")
    }

    func testTheLastSpotIsSingular() {
        let almostFull = run(players: Array(repeating: "p", count: 9), maxPlayers: 10)
        XCTAssertEqual(almostFull.spotsText, "1 spot left")
    }

    func testAFullRunSaysFullRatherThanZeroSpots() {
        let full = run(players: Array(repeating: "p", count: 10), maxPlayers: 10)
        XCTAssertEqual(full.spotsText, "Full")
    }

    /// `openSlots` clamps, so a hand-edited over-full roster reads as full
    /// rather than as a negative count.
    func testAnOverFullRosterStillReadsAsFull() {
        let overFull = run(players: Array(repeating: "p", count: 12), maxPlayers: 10)
        XCTAssertEqual(overFull.spotsText, "Full")
    }

    /// Spots and roster answer different questions and must not be confused
    /// for each other: one is "can I get on", the other is "who is on".
    func testSpotsAndRosterStayDifferentStatements() {
        let game = run(players: ["a", "b"], maxPlayers: 10)
        XCTAssertEqual(game.spotsText, "8 spots left")
        XCTAssertEqual(game.rosterText, "2 / 10 players")
    }
}
