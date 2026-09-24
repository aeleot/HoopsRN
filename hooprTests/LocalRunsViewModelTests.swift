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
        maxPlayers: Int = 10,
        status: Game.Status? = nil,
        completedAt: Date? = nil
    ) -> Game {
        Game(
            id: "game-1",
            hostId: host,
            courtId: "court-a",
            scheduledTime: now,
            isPublic: true,
            maxPlayers: maxPlayers,
            // Derived from the roster unless a test is pinning a status the
            // roster can't produce — `completed` is written by the host, not
            // computed, so it has to be passed in.
            status: status ?? Game.status(playerCount: players.count, maxPlayers: maxPlayers),
            playerIds: players,
            queuedPlayerIds: waitlisted,
            createdAt: now,
            updatedAt: now,
            completedAt: completedAt
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

    // MARK: - Marking a run complete

    /// Completion is a separate affordance from `action(for:)`, not a case of
    /// it: after tip-off the host has both this and "Cancel run", and an
    /// enum that returns one thing can't offer two. These pin the rule that
    /// decides whether the control is drawn at all — the ruleset enforces the
    /// same thing server-side, so a false positive here is a rejected write
    /// rather than an unauthorized one.

    func testTheHostCanCompleteARunThatHasStarted() {
        let run = game(players: [host, player])
        XCTAssertTrue(
            LocalRunsViewModel.canComplete(run, currentUserId: host, now: now.addingTimeInterval(60))
        )
    }

    /// Tip-off is the boundary, and it's inclusive — a run is under way the
    /// instant it starts.
    func testTheHostCannotCompleteARunBeforeItStarts() {
        let run = game(players: [host, player])

        XCTAssertFalse(
            LocalRunsViewModel.canComplete(run, currentUserId: host, now: now.addingTimeInterval(-60))
        )
        XCTAssertTrue(
            LocalRunsViewModel.canComplete(run, currentUserId: host, now: now)
        )
    }

    /// Host-only, the same shape as cancelling — and signed out reads as an
    /// outsider rather than trapping, matching `action(for:currentUserId:)`.
    func testOnlyTheHostCanCompleteARun() {
        let run = game(players: [host, player])
        let started = now.addingTimeInterval(60)

        XCTAssertFalse(LocalRunsViewModel.canComplete(run, currentUserId: player, now: started))
        XCTAssertFalse(LocalRunsViewModel.canComplete(run, currentUserId: stranger, now: started))
        XCTAssertFalse(LocalRunsViewModel.canComplete(run, currentUserId: nil, now: started))
    }

    /// There is no un-complete path — the update rule refuses a document that
    /// is already `completed` — so the second tap has to be stopped here, or
    /// it's a write the server rejects with `permission-denied`.
    func testACompletedRunCannotBeCompletedAgain() {
        let run = game(
            players: [host, player],
            status: .completed,
            completedAt: now.addingTimeInterval(30)
        )
        XCTAssertFalse(
            LocalRunsViewModel.canComplete(run, currentUserId: host, now: now.addingTimeInterval(60))
        )
    }

    /// A run nobody joined is still a run that happened. There's no attendance
    /// concept in the schema — `completed` claims only that — so the host of an
    /// empty run may record it, deliberately. A roster floor here would invent a
    /// guarantee the ruleset doesn't make.
    func testAHostWhoTurnedUpAloneCanStillCompleteTheRun() {
        let run = game(players: [host])
        XCTAssertTrue(
            LocalRunsViewModel.canComplete(run, currentUserId: host, now: now.addingTimeInterval(60))
        )
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

    // MARK: - The timeline

    /// The board merges the two listeners into one list ordered by tip-off.
    /// Phase 2b replaced *Queued Games* / *Public Games* with this, so the
    /// merge now carries what the section split used to say.

    private func listing(
        id: String,
        players: [String] = ["a"],
        minutesFromNow: Double
    ) -> LocalRunsViewModel.Listing {
        let game = Game(
            id: id,
            hostId: host,
            courtId: "court-a",
            scheduledTime: now.addingTimeInterval(minutesFromNow * 60),
            isPublic: true,
            maxPlayers: 10,
            status: Game.status(playerCount: players.count, maxPlayers: 10),
            playerIds: players,
            queuedPlayerIds: [],
            createdAt: now,
            updatedAt: now,
            completedAt: nil
        )
        return LocalRunsViewModel.Listing(game: game, court: nil, distanceMeters: nil)
    }

    func testTheBoardIsOrderedBySoonestTipOff() {
        let entries = LocalRunsViewModel.timeline(
            queued: [listing(id: "late", minutesFromNow: 180)],
            nearby: [listing(id: "soon", minutesFromNow: 30), listing(id: "mid", minutesFromNow: 90)]
        )

        XCTAssertEqual(entries.map(\.id), ["soon", "mid", "late"])
    }

    /// **The one that matters.** A run you host publicly arrives on *both*
    /// listeners, so the same game is in both arrays. `queued` is walked
    /// first, so the survivor is the entry marked as yours — walk `nearby`
    /// first and your own run renders as a stranger's, offering "Join" on a
    /// run you are already on.
    func testARunOnBothListsSurvivesOnceAndStaysYours() {
        let mine = listing(id: "shared", minutesFromNow: 60)

        let entries = LocalRunsViewModel.timeline(queued: [mine], nearby: [mine])

        XCTAssertEqual(entries.count, 1, "the same run must not appear twice")
        XCTAssertTrue(entries[0].isYours)
    }

    func testRunsYouAreNotOnAreNotMarkedYours() {
        let entries = LocalRunsViewModel.timeline(
            queued: [listing(id: "mine", minutesFromNow: 10)],
            nearby: [listing(id: "theirs", minutesFromNow: 20)]
        )

        XCTAssertEqual(entries.first(where: { $0.id == "mine" })?.isYours, true)
        XCTAssertEqual(entries.first(where: { $0.id == "theirs" })?.isYours, false)
    }

    /// Ties break on id, not on array order: two runs at the same tip-off
    /// would otherwise swap places between rebuilds while showing identical
    /// times — the same reason `rankHotCourts` breaks ties on name.
    func testRunsAtTheSameTimeHaveAStableOrder() {
        let a = listing(id: "aaa", minutesFromNow: 60)
        let b = listing(id: "bbb", minutesFromNow: 60)

        XCTAssertEqual(
            LocalRunsViewModel.timeline(queued: [], nearby: [b, a]).map(\.id),
            LocalRunsViewModel.timeline(queued: [], nearby: [a, b]).map(\.id),
            "the same two runs in a different input order must render the same way"
        )
    }

    func testAnEmptyBoardIsEmptyRatherThanCrashing() {
        XCTAssertTrue(LocalRunsViewModel.timeline(queued: [], nearby: []).isEmpty)
    }

    // MARK: - The week strip and the day sections

    /// Pinned to UTC so the day boundary doesn't move with the machine's zone.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func utcDate(day: Int, hour: Int, minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }

    /// Wednesday 23 September 2026, 6 PM UTC.
    private var wednesday: Date { utcDate(day: 23, hour: 18) }

    private func entry(_ id: String, at date: Date, yours: Bool = false) -> LocalRunsViewModel.TimelineEntry {
        let minutes = date.timeIntervalSince(now) / 60
        return LocalRunsViewModel.TimelineEntry(listing: listing(id: id, minutesFromNow: minutes), isYours: yours)
    }

    /// Seven days from today, each counting its runs and yours.
    func testTheStripCountsEachDaysRunsAndYours() {
        let timeline = [
            entry("a", at: utcDate(day: 23, hour: 19), yours: true),
            entry("b", at: utcDate(day: 23, hour: 20)),
            entry("c", at: utcDate(day: 25, hour: 18), yours: true),
        ]

        let strip = LocalRunsViewModel.weekStrip(timeline: timeline, now: wednesday, calendar: utc)

        XCTAssertEqual(strip.count, 7)
        XCTAssertEqual(strip[0].day, utcDate(day: 23, hour: 0))
        XCTAssertEqual(strip.map(\.total), [2, 0, 1, 0, 0, 0, 0])
        XCTAssertEqual(strip.map(\.yours), [1, 0, 1, 0, 0, 0, 0])
    }

    /// Last night's run, still listed inside the grace window, is on today's
    /// column — the strip has no yesterday, and the run is still on the board.
    func testLastNightsRunCountsTowardToday() {
        let strip = LocalRunsViewModel.weekStrip(
            timeline: [entry("late", at: utcDate(day: 22, hour: 23, minute: 30))],
            now: utcDate(day: 23, hour: 0, minute: 30),
            calendar: utc
        )
        XCTAssertEqual(strip[0].total, 1)
    }

    /// Runs past the strip's last day are counted as "later", not dropped.
    func testRunsAfterTheWeekAreLater() {
        let timeline = [
            entry("in", at: utcDate(day: 29, hour: 23)),
            entry("out", at: utcDate(day: 30, hour: 9)),
            entry("way-out", at: utcDate(day: 30, hour: 18)),
        ]
        XCTAssertEqual(LocalRunsViewModel.laterCount(timeline: timeline, now: wednesday, calendar: utc), 2)
        XCTAssertEqual(
            LocalRunsViewModel.weekStrip(timeline: timeline, now: wednesday, calendar: utc).last?.total, 1
        )
    }

    /// One heading per day, in the timeline's own order.
    func testTheBoardGroupsUnderOneHeadingPerDay() {
        let timeline = [
            entry("a", at: utcDate(day: 23, hour: 19)),
            entry("b", at: utcDate(day: 23, hour: 21)),
            entry("c", at: utcDate(day: 24, hour: 18)),
        ]
        let sections = LocalRunsViewModel.sections(timeline: timeline, now: wednesday, calendar: utc)

        XCTAssertEqual(sections.map(\.day), [utcDate(day: 23, hour: 0), utcDate(day: 24, hour: 0)])
        XCTAssertEqual(sections.map { $0.entries.map(\.id) }, [["a", "b"], ["c"]])
    }

    func testLastNightsRunFilesUnderToday() {
        let sections = LocalRunsViewModel.sections(
            timeline: [
                entry("late", at: utcDate(day: 22, hour: 23, minute: 30)),
                entry("tonight", at: utcDate(day: 23, hour: 19)),
            ],
            now: utcDate(day: 23, hour: 0, minute: 30),
            calendar: utc
        )
        XCTAssertEqual(sections.count, 1, "yesterday's run and today's share today's heading")
    }

    func testAnEmptyBoardHasNoSections() {
        XCTAssertTrue(LocalRunsViewModel.sections(timeline: [], now: wednesday, calendar: utc).isEmpty)
    }

    /// "Today", "Tomorrow", the weekday within the week, the date beyond it.
    func testHeadingsSayTheDayTheWayAPlayerWould() {
        let title = { (day: Int) in
            LocalRunsViewModel.sectionTitle(for: self.utcDate(day: day, hour: 0), now: self.wednesday, calendar: self.utc)
        }
        XCTAssertEqual(title(23), "Today")
        XCTAssertEqual(title(24), "Tomorrow")
        XCTAssertFalse(["Today", "Tomorrow"].contains(title(26)))
        XCTAssertFalse(title(26).contains("Sep"), "within the week, the weekday alone")
        XCTAssertTrue(title(30).contains("30"), "beyond the week, the date")
    }

    // MARK: - What VoiceOver says for a day

    func testADayWithRunsSaysHowManyAndYours() {
        let day = LocalRunsViewModel.DaySummary(day: wednesday, total: 3, yours: 2)
        XCTAssertTrue(RunsWeekStrip.spoken(day, isToday: true).hasPrefix("Today, "))
        XCTAssertTrue(RunsWeekStrip.spoken(day, isToday: true).hasSuffix("3 runs, you're in 2"))
    }

    func testAnEmptyDaySaysSo() {
        let day = LocalRunsViewModel.DaySummary(day: wednesday, total: 0, yours: 0)
        XCTAssertTrue(RunsWeekStrip.spoken(day, isToday: false).hasSuffix("no runs"))
    }
}
