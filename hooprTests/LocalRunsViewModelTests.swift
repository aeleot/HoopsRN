import XCTest
@testable import hoopr

/// Guards which button a run offers, given who's looking at it.
///
/// Newly testable: the rule used to read `currentUserId` off the view model, so
/// covering it meant standing up a `GameService` and Firebase. `GAPS.md` listed
/// it as uncovered. It's now a pure static shared by the Runs tab and the map's
/// court card — which is the other reason it's worth pinning, since two screens
/// offering different buttons for the same run would be a real bug.
final class LocalRunsViewModelTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_780_000_000)
    private let host = "host-uid"
    private let player = "player-uid"
    private let stranger = "stranger-uid"

    private func game(
        players: [String],
        waitlisted: [String] = [],
        maxPlayers: Int = 10
    ) -> Game {
        Game(
            id: "game-1",
            hostId: host,
            courtId: "court-a",
            scheduledTime: now,
            isPublic: true,
            maxPlayers: maxPlayers,
            status: Game.status(playerCount: players.count, maxPlayers: maxPlayers),
            playerIds: players,
            queuedPlayerIds: waitlisted,
            createdAt: now,
            updatedAt: now,
            completedAt: nil
        )
    }

    /// A host is always on their own roster, so checking membership before
    /// hosting would offer them "Leave" for a run only they can cancel.
    func testTheHostIsOfferedCancelNotLeave() {
        let run = game(players: [host, player])
        XCTAssertEqual(LocalRunsViewModel.action(for: run, currentUserId: host), .cancel)
    }

    func testAConfirmedPlayerIsOfferedLeave() {
        let run = game(players: [host, player])
        XCTAssertEqual(LocalRunsViewModel.action(for: run, currentUserId: player), .leave)
    }

    /// Leaving a waitlist is still leaving — the button must not read "Join
    /// waitlist" for someone already on it.
    func testAWaitlistedPlayerIsOfferedLeave() {
        let run = game(players: Array(repeating: "other", count: 10), waitlisted: [player])
        XCTAssertEqual(LocalRunsViewModel.action(for: run, currentUserId: player), .leave)
    }

    func testAnOutsiderIsOfferedJoinWhenThereIsRoom() {
        let run = game(players: [host])
        XCTAssertEqual(LocalRunsViewModel.action(for: run, currentUserId: stranger), .join)
    }

    func testAnOutsiderIsOfferedTheWaitlistWhenFull() {
        let run = game(players: (0..<10).map { "player-\($0)" })
        XCTAssertTrue(run.isFull)
        XCTAssertEqual(LocalRunsViewModel.action(for: run, currentUserId: stranger), .joinWaitlist)
    }

    /// Signed out, everything reads as an outsider's view rather than trapping.
    func testASignedOutViewerIsTreatedAsAnOutsider() {
        XCTAssertEqual(LocalRunsViewModel.action(for: game(players: [host]), currentUserId: nil), .join)

        let full = game(players: (0..<10).map { "player-\($0)" })
        XCTAssertEqual(LocalRunsViewModel.action(for: full, currentUserId: nil), .joinWaitlist)
    }

    // MARK: - Action semantics

    /// Both of these take something away, so they read in the app's error
    /// colour rather than its brand one. The court card relies on this to pick
    /// a button style.
    func testOnlyLeaveAndCancelAreDestructive() {
        XCTAssertTrue(LocalRunsViewModel.Action.leave.isDestructive)
        XCTAssertTrue(LocalRunsViewModel.Action.cancel.isDestructive)
        XCTAssertFalse(LocalRunsViewModel.Action.join.isDestructive)
        XCTAssertFalse(LocalRunsViewModel.Action.joinWaitlist.isDestructive)
        XCTAssertFalse(LocalRunsViewModel.Action.none.isDestructive)
    }

    /// `.none` renders no button at all, so an empty title is what the views
    /// branch on.
    func testOnlyNoneHasAnEmptyTitle() {
        XCTAssertTrue(LocalRunsViewModel.Action.none.title.isEmpty)
        for action in [
            LocalRunsViewModel.Action.join,
            .joinWaitlist,
            .leave,
            .cancel,
        ] {
            XCTAssertFalse(action.title.isEmpty, "\(action) needs a label")
        }
    }
}
