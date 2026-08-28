import XCTest
@testable import hoopr

/// Guards the map's filter chips, which became *activity* predicates when the
/// tab was rebuilt around "find a game right now".
///
/// The property that matters most here is totality: every case has to return a
/// sensible answer for a court with nothing scheduled. The amenity filters
/// these replaced failed exactly that — an absent OSM tag was a third state,
/// and treating it as "no" is what let one tap empty the map.
final class CourtFilterTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_780_000_000)

    private func court(access: Court.Access = .public) -> Court {
        Court(
            id: "court-a",
            name: "Long Meadow Park Basketball Court",
            latitude: 35.9940,
            longitude: -78.8986,
            address: "Durham, NC",
            city: "Durham",
            hoops: nil,
            surface: nil,
            isLit: nil,
            isCovered: nil,
            access: access,
            osmType: nil,
            osmId: nil
        )
    }

    private func game(id: String = "g", players: Int, maxPlayers: Int = 10) -> Game {
        Game(
            id: id,
            hostId: "host-uid",
            courtId: "court-a",
            scheduledTime: now,
            isPublic: true,
            maxPlayers: maxPlayers,
            status: Game.status(playerCount: players, maxPlayers: maxPlayers),
            playerIds: (0..<players).map { "player-\($0)" },
            queuedPlayerIds: [],
            createdAt: now,
            updatedAt: now
        )
    }

    // MARK: - Totality

    /// Every case, against a court with nothing on. None may trap, and none may
    /// claim activity that isn't there.
    func testEveryCaseIsTotalAgainstAQuietCourt() {
        for filter in CourtFilter.allCases {
            let matched = filter.matches(court(), activity: .quiet)
            switch filter {
            case .gamesToday, .openSpots:
                XCTAssertFalse(matched, "\(filter) should not match a quiet court")
            case .openToAll:
                XCTAssertTrue(matched, "\(filter) reads the court, not its activity")
            }
        }
    }

    func testQuietIsTheSameAsAnEmptyGameList() {
        XCTAssertEqual(CourtActivity.quiet, CourtActivity(games: []))
        XCTAssertFalse(CourtActivity.quiet.hasGameToday)
        XCTAssertFalse(CourtActivity.quiet.hasOpenSpot)
    }

    // MARK: - gamesToday

    func testGamesTodayMatchesAnyScheduledRun() {
        let full = CourtActivity(games: [game(players: 10)])
        // Full still counts as activity — the chip asks whether anything is on
        // here, not whether you can join it.
        XCTAssertTrue(CourtFilter.gamesToday.matches(court(), activity: full))
    }

    // MARK: - openSpots

    func testOpenSpotsRequiresRoom() {
        let full = CourtActivity(games: [game(players: 10)])
        XCTAssertFalse(CourtFilter.openSpots.matches(court(), activity: full))

        let room = CourtActivity(games: [game(players: 7)])
        XCTAssertTrue(CourtFilter.openSpots.matches(court(), activity: room))
    }

    /// One joinable run among several full ones is still a court worth showing.
    func testOpenSpotsMatchesWhenAnySingleRunHasRoom() {
        let mixed = CourtActivity(games: [
            game(id: "full", players: 10),
            game(id: "room", players: 4),
        ])
        XCTAssertTrue(CourtFilter.openSpots.matches(court(), activity: mixed))
    }

    /// `Game.openSlots` clamps at zero, so a hand-edited over-full roster reads
    /// as closed rather than going negative and looking joinable.
    func testAnOverfullRosterReadsAsClosed() {
        let overfull = CourtActivity(games: [game(players: 12, maxPlayers: 10)])
        XCTAssertFalse(overfull.hasOpenSpot)
        XCTAssertFalse(CourtFilter.openSpots.matches(court(), activity: overfull))
    }

    /// Selecting both chips is the same as selecting `openSpots` alone. Not a
    /// special case to remove — just a consequence worth pinning so nobody
    /// "fixes" it later.
    func testOpenSpotsImpliesGamesToday() {
        let room = CourtActivity(games: [game(players: 4)])
        XCTAssertTrue(CourtFilter.openSpots.matches(court(), activity: room))
        XCTAssertTrue(CourtFilter.gamesToday.matches(court(), activity: room))
    }

    // MARK: - openToAll

    func testOpenToAllReadsAccessAndIgnoresActivity() {
        let busy = CourtActivity(games: [game(players: 4)])

        XCTAssertTrue(CourtFilter.openToAll.matches(court(access: .public), activity: .quiet))
        XCTAssertTrue(CourtFilter.openToAll.matches(court(access: .public), activity: busy))
        XCTAssertFalse(CourtFilter.openToAll.matches(court(access: .school), activity: busy))
        XCTAssertFalse(CourtFilter.openToAll.matches(court(access: .restricted), activity: busy))
    }

    // MARK: - Vocabulary

    /// "Public" is already how `Game.visibilityText` describes a *run's*
    /// visibility, and those cards sit a row below this chip. Same word, two
    /// meanings, one screen is the collision this label exists to avoid.
    func testTheAccessChipDoesNotReuseTheWordPublic() {
        XCTAssertFalse(CourtFilter.openToAll.label.localizedCaseInsensitiveContains("public"))
    }

    func testEveryCaseHasADistinctLabelAndSymbol() {
        let labels = Set(CourtFilter.allCases.map(\.label))
        let symbols = Set(CourtFilter.allCases.map(\.symbolName))
        XCTAssertEqual(labels.count, CourtFilter.allCases.count)
        XCTAssertEqual(symbols.count, CourtFilter.allCases.count)
    }
}
