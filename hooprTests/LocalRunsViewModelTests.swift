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

    // MARK: - Friends on a run

    private func friendship(
        _ uid1: String,
        _ uid2: String,
        status: Friendship.Status = .accepted
    ) -> Friendship {
        let pair = [uid1, uid2].sorted()
        return Friendship(
            uidA: pair[0],
            uidB: pair[1],
            requestedBy: uid1,
            status: status,
            createdAt: now,
            updatedAt: now
        )
    }

    /// The bug the resolution exists to avoid: a friendship stores both
    /// participants, so a naive union of `uidA`/`uidB` would make you your own
    /// friend — and every run you're on would count you in its badge.
    func testYourOwnUidIsNeverAFriendUid() {
        let edges = [friendship(player, "friend-a"), friendship(player, "friend-b")]
        let uids = LocalRunsViewModel.friendUids(from: edges, currentUserId: player)

        XCTAssertEqual(uids, ["friend-a", "friend-b"])
        XCTAssertFalse(uids.contains(player))
    }

    /// Resolving works from either side of the stored pair — the case a naive
    /// `uidA == me` implementation gets wrong for half of all friendships.
    func testAnEdgeResolvesFromWhicheverSideYouAreOn() {
        let edge = friendship("aaa-uid", "zzz-uid")

        XCTAssertEqual(
            LocalRunsViewModel.friendUids(from: [edge], currentUserId: "aaa-uid"),
            ["zzz-uid"]
        )
        XCTAssertEqual(
            LocalRunsViewModel.friendUids(from: [edge], currentUserId: "zzz-uid"),
            ["aaa-uid"]
        )
    }

    func testSignedOutHasNoFriendUids() {
        let edges = [friendship(player, "friend-a")]
        XCTAssertTrue(LocalRunsViewModel.friendUids(from: edges, currentUserId: nil).isEmpty)
    }

    func testAFriendOnTheRosterIsCounted() {
        let run = game(players: [host, "friend-a", stranger])
        XCTAssertEqual(
            LocalRunsViewModel.friendIds(on: run, friendUids: ["friend-a", "friend-b"]),
            ["friend-a"]
        )
    }

    /// A friend waiting for a spot is the same signal as one holding it —
    /// you'd be turning up to the same court either way.
    func testAFriendOnTheWaitlistIsCounted() {
        let run = game(
            players: Array(repeating: "other", count: 10),
            waitlisted: ["friend-a"]
        )
        XCTAssertEqual(
            LocalRunsViewModel.friendIds(on: run, friendUids: ["friend-a"]),
            ["friend-a"]
        )
    }

    func testStrangersOnTheRosterAreNotCounted() {
        let run = game(players: [host, stranger])
        XCTAssertTrue(LocalRunsViewModel.friendIds(on: run, friendUids: ["friend-a"]).isEmpty)
    }

    func testNoFriendsAtAllIsEmptyRatherThanEveryone() {
        let run = game(players: [host, player, stranger])
        XCTAssertTrue(LocalRunsViewModel.friendIds(on: run, friendUids: []).isEmpty)
    }

    /// Sorted, so an identical rebuild can't reorder the names a later phase
    /// may render — and deduped, since the union spans two rosters.
    func testTheResultIsSortedAndDeduped() {
        let run = game(players: ["friend-c", "friend-a"], waitlisted: ["friend-a", "friend-b"])
        XCTAssertEqual(
            LocalRunsViewModel.friendIds(on: run, friendUids: ["friend-a", "friend-b", "friend-c"]),
            ["friend-a", "friend-b", "friend-c"]
        )
    }

    // MARK: - The badge's own copy

    func testFriendsHereTextIsAbsentRatherThanZero() {
        let listing = LocalRunsViewModel.Listing(
            game: game(players: [host]),
            court: nil,
            distanceMeters: nil
        )
        XCTAssertNil(listing.friendsHereText)
    }

    func testFriendsHereTextIsSingularForOne() {
        let listing = LocalRunsViewModel.Listing(
            game: game(players: [host, "friend-a"]),
            court: nil,
            distanceMeters: nil,
            friendIds: ["friend-a"]
        )
        XCTAssertEqual(listing.friendsHereText, "1 friend here")
    }

    func testFriendsHereTextIsPluralForMore() {
        let listing = LocalRunsViewModel.Listing(
            game: game(players: [host, "friend-a", "friend-b"]),
            court: nil,
            distanceMeters: nil,
            friendIds: ["friend-a", "friend-b"]
        )
        XCTAssertEqual(listing.friendsHereText, "2 friends here")
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
