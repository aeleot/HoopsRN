import XCTest
@testable import hoopr

/// Guards `FindAMatchViewModel`'s court-to-games join and the count derived
/// from it — what backs the map's pins, their numeric badges, and the Now
/// segment — out of the two arrays `GameService` already publishes.
///
/// The `gameCountsByCourt` cases below predate `gamesByCourt` and are
/// deliberately left **unchanged**: the count is now computed on top of the
/// join, so these passing untouched is the evidence that reimplementing it
/// preserved the dedup-by-id and calendar-day rules exactly.
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
            updatedAt: scheduledTime,
            completedAt: nil
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

    // MARK: - The join itself

    func testGroupsGamesByCourtSoonestFirst() {
        let late = game(id: "late", courtId: "court-a", scheduledTime: today.addingTimeInterval(7200))
        let early = game(id: "early", courtId: "court-a", scheduledTime: today)

        let byCourt = FindAMatchViewModel.gamesByCourt(
            queued: [],
            published: [late, early],
            now: today
        )

        XCTAssertEqual(byCourt["court-a"]?.map(\.id), ["early", "late"])
    }

    /// Two runs at the same minute have to order deterministically, or the row
    /// reshuffles between rebuilds that produced identical data — which reads
    /// as the list glitching rather than updating.
    func testGamesAtTheSameInstantOrderStablyById() {
        let b = game(id: "b", courtId: "court-a", scheduledTime: today)
        let a = game(id: "a", courtId: "court-a", scheduledTime: today)

        let first = FindAMatchViewModel.gamesByCourt(queued: [], published: [b, a], now: today)
        let second = FindAMatchViewModel.gamesByCourt(queued: [], published: [a, b], now: today)

        XCTAssertEqual(first["court-a"]?.map(\.id), ["a", "b"])
        XCTAssertEqual(second["court-a"]?.map(\.id), ["a", "b"])
    }

    func testTheJoinDedupesByIdLikeTheCountDoes() {
        let shared = game(id: "shared", courtId: "court-a", scheduledTime: today)

        let byCourt = FindAMatchViewModel.gamesByCourt(
            queued: [shared],
            published: [shared],
            now: today
        )

        XCTAssertEqual(byCourt["court-a"]?.count, 1)
    }

    func testTheJoinDropsGamesFromOtherCalendarDays() {
        let byCourt = FindAMatchViewModel.gamesByCourt(
            queued: [],
            published: [
                game(id: "today", courtId: "court-a", scheduledTime: today),
                game(id: "tomorrow", courtId: "court-a", scheduledTime: today.addingTimeInterval(86_400)),
            ],
            now: today
        )

        XCTAssertEqual(byCourt["court-a"]?.map(\.id), ["today"])
    }

    /// Absent, not an empty array — a court with nothing on shouldn't occupy a
    /// key that every consumer then has to check for emptiness.
    func testACourtWithNoGamesIsAbsentFromTheJoin() {
        let byCourt = FindAMatchViewModel.gamesByCourt(
            queued: [],
            published: [game(id: "1", courtId: "court-a", scheduledTime: today)],
            now: today
        )

        XCTAssertNil(byCourt["court-b"])
    }

    /// The count is derived from the join, so they can't disagree. This pins
    /// that relationship rather than trusting it.
    func testTheCountMatchesTheJoinItWasDerivedFrom() {
        let games = [
            game(id: "1", courtId: "court-a", scheduledTime: today),
            game(id: "2", courtId: "court-a", scheduledTime: today.addingTimeInterval(3600)),
            game(id: "3", courtId: "court-b", scheduledTime: today),
        ]

        let byCourt = FindAMatchViewModel.gamesByCourt(queued: [], published: games, now: today)
        let counts = FindAMatchViewModel.gameCountsByCourt(queued: [], published: games, now: today)

        XCTAssertEqual(counts, byCourt.mapValues(\.count))
    }

    // MARK: - The Now segment

    private func nearby(_ courtId: String, meters: Double, name: String? = nil) -> NearbyCourt {
        NearbyCourt(
            court: Court(
                id: courtId,
                name: name ?? courtId,
                latitude: 35.9940,
                longitude: -78.8986,
                address: "Durham, NC",
                city: "Durham",
                hoops: nil,
                surface: nil,
                isLit: nil,
                isCovered: nil,
                access: .public,
                osmType: nil,
                osmId: nil
            ),
            distanceMeters: meters
        )
    }

    func testActiveCourtsAreOrderedBySoonestRun() {
        let ranked = [nearby("court-a", meters: 5_000), nearby("court-b", meters: 100)]
        let byCourt = [
            "court-a": [game(id: "a", courtId: "court-a", scheduledTime: today.addingTimeInterval(600))],
            "court-b": [game(id: "b", courtId: "court-b", scheduledTime: today.addingTimeInterval(3600))],
        ]

        let active = FindAMatchViewModel.rankActive(
            gamesByCourtID: byCourt,
            among: ranked,
            now: today
        )

        // Sooner wins even though court-b is fifty times closer.
        XCTAssertEqual(active.map(\.id), ["court-a", "court-b"])
    }

    func testTiesBreakOnDistanceThenName() {
        let ranked = [
            nearby("far", meters: 9_000, name: "Alpha"),
            nearby("near", meters: 100, name: "Zulu"),
        ]
        let byCourt = [
            "far": [game(id: "1", courtId: "far", scheduledTime: today)],
            "near": [game(id: "2", courtId: "near", scheduledTime: today)],
        ]

        let active = FindAMatchViewModel.rankActive(
            gamesByCourtID: byCourt,
            among: ranked,
            now: today
        )

        XCTAssertEqual(active.map(\.id), ["near", "far"])
    }

    /// The join buckets by calendar day because the *pins* want it. This
    /// segment asks "can I still walk into something", which is a different
    /// question — a run that finished hours ago is not an answer to it.
    func testARunThatHasAgedOutIsExcludedEvenThoughItIsStillToday() {
        let ranked = [nearby("court-a", meters: 100)]
        // Four hours before `now`, past `Game.visibilityGrace` of three.
        let stale = game(
            id: "stale",
            courtId: "court-a",
            scheduledTime: today.addingTimeInterval(-4 * 3600)
        )

        let active = FindAMatchViewModel.rankActive(
            gamesByCourtID: ["court-a": [stale]],
            among: ranked,
            now: today
        )

        XCTAssertTrue(active.isEmpty)
        // ...but the join still counts it, because the court *was* busy today.
        let counts = FindAMatchViewModel.gameCountsByCourt(
            queued: [],
            published: [stale],
            now: today
        )
        XCTAssertEqual(counts["court-a"], 1)
    }

    /// A run already underway is still the one you would walk to.
    func testARunUnderwayIsStillListed() {
        let ranked = [nearby("court-a", meters: 100)]
        let underway = game(
            id: "underway",
            courtId: "court-a",
            scheduledTime: today.addingTimeInterval(-1800)
        )

        let active = FindAMatchViewModel.rankActive(
            gamesByCourtID: ["court-a": [underway]],
            among: ranked,
            now: today
        )

        XCTAssertEqual(active.map(\.id), ["court-a"])
    }

    func testCourtsWithNoRunsAreAbsentRatherThanEmpty() {
        let ranked = [nearby("court-a", meters: 100), nearby("court-b", meters: 200)]

        let active = FindAMatchViewModel.rankActive(
            gamesByCourtID: ["court-a": [game(id: "1", courtId: "court-a", scheduledTime: today)]],
            among: ranked,
            now: today
        )

        XCTAssertEqual(active.map(\.id), ["court-a"])
    }

    /// `leadGame` force-indexes `games[0]`, which is only safe because a court
    /// with nothing visible never becomes an `ActiveCourt` at all.
    func testEveryActiveCourtHasAtLeastOneGame() {
        let ranked = [nearby("court-a", meters: 100)]
        let active = FindAMatchViewModel.rankActive(
            gamesByCourtID: [
                "court-a": [
                    game(id: "1", courtId: "court-a", scheduledTime: today.addingTimeInterval(3600)),
                    game(id: "2", courtId: "court-a", scheduledTime: today.addingTimeInterval(7200)),
                ]
            ],
            among: ranked,
            now: today
        )

        XCTAssertEqual(active.first?.games.count, 2)
        XCTAssertEqual(active.first?.leadGame.id, "1")
        XCTAssertEqual(active.first?.additionalGamesText, "+1 more today")
    }

    func testASingleRunHasNoAdditionalGamesText() {
        let ranked = [nearby("court-a", meters: 100)]
        let active = FindAMatchViewModel.rankActive(
            gamesByCourtID: ["court-a": [game(id: "1", courtId: "court-a", scheduledTime: today)]],
            among: ranked,
            now: today
        )

        XCTAssertNil(active.first?.additionalGamesText)
    }
}
