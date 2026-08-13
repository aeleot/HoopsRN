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

    // MARK: - Distance

    func testDistanceFormatting() {
        // One decimal under ten miles, whole numbers above.
        XCTAssertEqual(Distance.text(Distance.meters(miles: 1.24)), "1.2 mi")
        XCTAssertEqual(Distance.text(Distance.meters(miles: 12.4)), "12 mi")
        XCTAssertEqual(Distance.miles(Distance.meters(miles: 5)), 5, accuracy: 0.0001)
    }
}
