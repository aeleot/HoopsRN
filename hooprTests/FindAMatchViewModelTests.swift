import XCTest
@testable import hoopr

/// Guards `FindAMatchViewModel.gameCountsByCourt`, the join behind the map's
/// heat-coloured pins: how many games are scheduled at each court today, out
/// of the two arrays `GameService` already publishes.
final class FindAMatchViewModelTests: XCTestCase {

    private let today = Date(timeIntervalSince1970: 1_780_000_000)

    private func game(
        id: String,
        courtId: String,
        scheduledTime: Date,
        isPublic: Bool = true
    ) -> Game {
        Game(
            id: id,
            hostId: "host-uid",
            courtId: courtId,
            scheduledTime: scheduledTime,
            isPublic: isPublic,
            maxPlayers: 10,
            status: .open,
            playerIds: ["host-uid"],
            queuedPlayerIds: [],
            createdAt: scheduledTime,
            updatedAt: scheduledTime
        )
    }

    func testCountsGamesPerCourt() {
        let counts = FindAMatchViewModel.gameCountsByCourt(
            queued: [],
            published: [
                game(id: "1", courtId: "court-a", scheduledTime: today),
                game(id: "2", courtId: "court-a", scheduledTime: today.addingTimeInterval(3600)),
                game(id: "3", courtId: "court-b", scheduledTime: today),
            ],
            now: today
        )

        XCTAssertEqual(counts["court-a"], 2)
        XCTAssertEqual(counts["court-b"], 1)
    }

    /// The reason this is a join over *two* arrays rather than one: a public
    /// run the signed-in user also hosts or joined arrives on both
    /// `queuedGames` and `publicGames`. Without the dedup, every game a
    /// signed-in user is part of would double-count on their own map.
    func testTheSameGameOnBothListsCountsOnce() {
        let shared = game(id: "shared", courtId: "court-a", scheduledTime: today)

        let counts = FindAMatchViewModel.gameCountsByCourt(
            queued: [shared],
            published: [shared],
            now: today
        )

        XCTAssertEqual(counts["court-a"], 1)
    }

    /// "Today" is the calendar day, not a rolling 24 hours — a game 25 hours
    /// out doesn't count, and one from earlier today does even once its own
    /// tip-off has passed.
    func testOnlyGamesOnTheSameCalendarDayCount() {
        let counts = FindAMatchViewModel.gameCountsByCourt(
            queued: [],
            published: [
                game(id: "yesterday", courtId: "court-a", scheduledTime: today.addingTimeInterval(-90_000)),
                game(id: "tomorrow", courtId: "court-a", scheduledTime: today.addingTimeInterval(90_000)),
                game(id: "earlier-today", courtId: "court-a", scheduledTime: today.addingTimeInterval(-3600)),
            ],
            now: today
        )

        XCTAssertEqual(counts["court-a"], 1)
    }

    func testACourtWithNoGamesTodayIsAbsentRatherThanZero() {
        let counts = FindAMatchViewModel.gameCountsByCourt(queued: [], published: [], now: today)

        XCTAssertNil(counts["court-a"])
        XCTAssertTrue(counts.isEmpty)
    }

    /// A private run counts the same as a public one — the heat map only ever
    /// sees what the read rule already admits to this account (see the
    /// property's own doc comment), so there's no extra privacy question once
    /// a game has arrived in either array at all.
    func testPrivateGamesCountTheSameAsPublicOnes() {
        let counts = FindAMatchViewModel.gameCountsByCourt(
            queued: [game(id: "1", courtId: "court-a", scheduledTime: today, isPublic: false)],
            published: [],
            now: today
        )

        XCTAssertEqual(counts["court-a"], 1)
    }
}
