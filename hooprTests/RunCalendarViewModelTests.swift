import UIKit
import XCTest
@testable import hoopr

/// Pins the rules behind Home's run calendar: which days a month's grid has,
/// which of them are marked and by what, what each day says, how fetched runs
/// and the live listener are joined, how far back and forward the popup can
/// page, what VoiceOver says — and whether the tile fits beside the scoreboard.
///
/// All of it `nonisolated static` and pure, the shape `HomeViewModelTests` uses
/// for `rankHotCourts`: none of it needs a service or Firebase. The calendars
/// are built here rather than taken from the phone, so a Sunday-first and a
/// Monday-first week, and a zone that disagrees with UTC, are both under test
/// on whatever machine runs this.
final class RunCalendarViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private func makeCalendar(firstWeekday: Int = 1, zone: String = "America/New_York") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func date(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0,
        in calendar: Calendar
    ) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func run(
        _ id: String,
        at scheduledTime: Date,
        status: Game.Status = .open,
        host: String = "host",
        players: [String] = ["host"],
        court: String = "court-a"
    ) -> Game {
        Game(
            id: id,
            hostId: host,
            courtId: court,
            scheduledTime: scheduledTime,
            isPublic: false,
            maxPlayers: 10,
            status: status,
            playerIds: players,
            queuedPlayerIds: [],
            createdAt: scheduledTime,
            updatedAt: scheduledTime,
            completedAt: status == .completed ? scheduledTime : nil
        )
    }

    private func match(
        _ id: String,
        at scheduledTime: Date,
        status: SeasonGame.Status = .scheduled,
        result: String? = nil
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
            awaySquadName: "Hornets",
            courtId: "court-b",
            scheduledTime: scheduledTime,
            status: status,
            arrivedPlayerIds: [],
            homeReport: result,
            awayReport: result,
            homeScore: nil,
            awayScore: nil,
            result: result,
            cancelledBySquadId: nil,
            createdBy: "leader-away",
            createdAt: nil,
            updatedAt: nil,
            confirmedAt: nil
        )
    }

    private func squad() -> Squad {
        Squad(
            id: "squad-home", name: "Rim Reapers", nameLower: "rim reapers", leaderId: "leader-home",
            memberIds: ["leader-home"], format: .threeVThree, iconKey: "basketball.fill", colorKey: "teal",
            region: "durham", createdAt: nil, updatedAt: nil
        )
    }

    /// October 2026 as the popup would build it on the 5th, everything answered.
    private func october(
        runs: [Game] = [],
        games: [SeasonGame] = [],
        squadState: RunCalendarViewModel.SquadGamesState = .available,
        loadState: RunCalendarViewModel.LoadState = .loaded,
        hasFetched: Bool = false,
        liveLoaded: Bool = true,
        bounds: ClosedRange<Date>? = nil,
        now: Date? = nil
    ) -> RunCalendarViewModel.Page {
        let calendar = makeCalendar()
        let now = now ?? date(2026, 10, 5, in: calendar)
        let month = CalendarMonth(containing: date(2026, 10, 15, in: calendar), calendar: calendar)
        return RunCalendarViewModel.page(
            month: month, now: now, runs: runs, seasonGames: games, squad: squad(),
            squadState: squadState, loadState: loadState, hasFetched: hasFetched, liveLoaded: liveLoaded,
            bounds: bounds ?? RunCalendarViewModel.bounds(
                createdAt: nil, latestScheduledSquadGame: nil, now: now, calendar: calendar
            ),
            calendar: calendar
        )
    }

    // MARK: - The grid

    /// 28, 29, 30 and 31 days, and the days are exactly 1 through N in order.
    func testTheGridHoldsEveryDayOfTheMonth() {
        let calendar = makeCalendar()
        let months: [(year: Int, month: Int, days: Int)] = [
            (2026, 2, 28),  // February
            (2028, 2, 29),  // a leap February
            (2026, 4, 30),
            (2026, 10, 31),
        ]
        for m in months {
            let grid = RunCalendarViewModel.monthGrid(for: date(m.year, m.month, 15, in: calendar), calendar: calendar)
            XCTAssertEqual(grid.compactMap { $0 }, Array(1 ... m.days), "\(m.year)-\(m.month)")
        }
    }

    /// The blanks before the 1st are as many as the 1st is days past the
    /// calendar's first weekday: October 1, 2026 is a Thursday.
    func testLeadingBlanksFollowTheCalendarsFirstWeekday() {
        let sundayFirst = makeCalendar(firstWeekday: 1)
        let mondayFirst = makeCalendar(firstWeekday: 2)
        let october = date(2026, 10, 15, in: sundayFirst)

        func leadingBlanks(_ grid: [Int?]) -> Int { grid.prefix { $0 == nil }.count }

        XCTAssertEqual(leadingBlanks(RunCalendarViewModel.monthGrid(for: october, calendar: sundayFirst)), 4)
        XCTAssertEqual(leadingBlanks(RunCalendarViewModel.monthGrid(for: october, calendar: mondayFirst)), 3)

        // November 1, 2026 is a Sunday: no blanks one way, six the other.
        let november = date(2026, 11, 15, in: sundayFirst)
        XCTAssertEqual(leadingBlanks(RunCalendarViewModel.monthGrid(for: november, calendar: sundayFirst)), 0)
        XCTAssertEqual(leadingBlanks(RunCalendarViewModel.monthGrid(for: november, calendar: mondayFirst)), 6)
    }

    /// The weekday row starts where the grid does.
    func testTheWeekdayInitialsStartOnTheFirstWeekday() {
        XCTAssertEqual(
            RunCalendarViewModel.weekdayInitials(calendar: makeCalendar(firstWeekday: 1)),
            ["S", "M", "T", "W", "T", "F", "S"]
        )
        XCTAssertEqual(
            RunCalendarViewModel.weekdayInitials(calendar: makeCalendar(firstWeekday: 2)),
            ["M", "T", "W", "T", "F", "S", "S"]
        )
    }

    /// Seven to a row, the last row padded out — what the popup lays out.
    func testRowsAreSevenWideAndTheLastIsPadded() {
        // 4 blanks + 31 days = 35 cells: five full rows.
        let page = october()
        XCTAssertEqual(page.rows.count, 5)
        XCTAssertTrue(page.rows.allSatisfy { $0.count == 7 })
        XCTAssertEqual(page.rows.last?.compactMap { $0 }, [25, 26, 27, 28, 29, 30, 31])
    }

    // MARK: - Marks

    /// **A run at 23:30 local is on that local day**, even though in UTC it is
    /// already the next one — this is a picture of your own days.
    func testALateRunLandsOnItsLocalDay() {
        let calendar = makeCalendar()  // New York: 23:30 on the 7th is 03:30 UTC on the 8th
        let late = date(2026, 10, 7, 23, 30, in: calendar)
        XCTAssertEqual(makeCalendar(zone: "UTC").component(.day, from: late), 8, "the fixture is the point")

        let marks = RunCalendarViewModel.marks(
            runs: [run("late", at: late)], seasonGames: [], in: date(2026, 10, 1, in: calendar), calendar: calendar
        )
        XCTAssertEqual(marks.keys.sorted(), [7])
        XCTAssertEqual(marks[7]?.runCount, 1)
    }

    /// A run and a squad game on one day: both marks, on the one day.
    func testARunAndASquadGameOnOneDayGiveBothMarks() {
        let calendar = makeCalendar()
        let marks = RunCalendarViewModel.marks(
            runs: [run("run", at: date(2026, 10, 9, 18, in: calendar))],
            seasonGames: [match("game", at: date(2026, 10, 9, 20, in: calendar))],
            in: date(2026, 10, 1, in: calendar),
            calendar: calendar
        )
        XCTAssertEqual(marks, [9: RunCalendarViewModel.DayMark(runCount: 1, hasSquadGame: true)])
    }

    /// A day counts its runs.
    func testADayCountsItsRuns() {
        let calendar = makeCalendar()
        let marks = RunCalendarViewModel.marks(
            runs: [
                run("a", at: date(2026, 10, 9, 9, in: calendar)),
                run("b", at: date(2026, 10, 9, 19, in: calendar)),
            ],
            seasonGames: [], in: date(2026, 10, 1, in: calendar), calendar: calendar
        )
        XCTAssertEqual(marks, [9: RunCalendarViewModel.DayMark(runCount: 2, hasSquadGame: false)])
    }

    /// **A dot per run, up to three; three or more set the day on fire; a
    /// season game fills it with the squad's colour**, and outranks fire — the
    /// dots still count the runs.
    func testADaysZoneAndDotsFollowWhatIsOnIt() {
        typealias Mark = RunCalendarViewModel.DayMark

        XCTAssertEqual(Mark().dots, 0)
        XCTAssertEqual(Mark().zone, .plain)
        XCTAssertEqual(Mark(runCount: 1).dots, 1)
        XCTAssertEqual(Mark(runCount: 2).zone, .plain)
        XCTAssertEqual(Mark(runCount: 3).zone, .fire)
        XCTAssertEqual(Mark(runCount: 3).dots, 3)
        XCTAssertEqual(Mark(runCount: 7).dots, 3, "three at most")
        XCTAssertEqual(Mark(runCount: 7).zone, .fire)

        XCTAssertEqual(Mark(hasSquadGame: true).zone, .squad)
        XCTAssertEqual(Mark(runCount: 4, hasSquadGame: true).zone, .squad)
        XCTAssertEqual(Mark(runCount: 4, hasSquadGame: true).dots, 3)
    }

    /// A cancelled match is on nobody's calendar. Every other status is: it
    /// was, is, or was played.
    func testACancelledSquadGameGivesNoMark() {
        let calendar = makeCalendar()
        let day = date(2026, 10, 9, in: calendar)
        let month = date(2026, 10, 1, in: calendar)

        XCTAssertTrue(RunCalendarViewModel.marks(
            runs: [], seasonGames: [match("x", at: day, status: .cancelled)], in: month, calendar: calendar
        ).isEmpty)

        for status in [SeasonGame.Status.scheduled, .confirmed, .disputed] {
            XCTAssertEqual(
                RunCalendarViewModel.marks(
                    runs: [], seasonGames: [match("x", at: day, status: status)], in: month, calendar: calendar
                )[9]?.hasSquadGame, true, "\(status)"
            )
        }
    }

    /// A list that spans months can be handed in whole — the live listener's
    /// does. The 1st's first instant is in; the next month's is out.
    func testOnlyTheMonthsOwnRunsAreMarked() {
        let calendar = makeCalendar()
        let marks = RunCalendarViewModel.marks(
            runs: [
                run("before", at: date(2026, 9, 30, 23, 59, in: calendar)),
                run("first", at: date(2026, 10, 1, 0, 0, in: calendar)),
                run("next", at: date(2026, 11, 1, 0, 0, in: calendar)),
            ],
            seasonGames: [], in: date(2026, 10, 20, in: calendar), calendar: calendar
        )
        XCTAssertEqual(marks.keys.sorted(), [1])
    }

    // MARK: - What a day says

    /// The other squad in each game, by day, soonest first — never a
    /// cancelled one.
    func testEachDayKnowsWhoTheSquadPlays() {
        let calendar = makeCalendar()
        let opponents = RunCalendarViewModel.opponentsByDay(
            seasonGames: [
                match("late", at: date(2026, 10, 9, 20, in: calendar)),
                match("off", at: date(2026, 10, 12, in: calendar), status: .cancelled),
            ],
            squadId: "squad-home",
            in: date(2026, 10, 1, in: calendar),
            calendar: calendar
        )
        XCTAssertEqual(opponents, [9: ["Hornets"]])
    }

    /// The popup opens on today when today is in the month, otherwise on the
    /// first day with something on it, otherwise on the 1st.
    func testThePopupOpensOnTodayOrTheFirstDayWithSomethingOn() {
        let calendar = makeCalendar()
        let runs = [run("r", at: date(2026, 10, 12, in: calendar)), run("s", at: date(2026, 10, 20, in: calendar))]

        XCTAssertEqual(RunCalendarViewModel.defaultSelection(in: october(runs: runs)), 5)

        let november = date(2026, 11, 2, in: calendar)
        XCTAssertEqual(RunCalendarViewModel.defaultSelection(in: october(runs: runs, now: november)), 12)
        XCTAssertEqual(RunCalendarViewModel.defaultSelection(in: october(now: november)), 1)
    }

    // MARK: - What isn't an answer

    /// **Loading is not emptiness**: until the live listener, the month's fetch
    /// and the squad's games have all answered, nothing is marked.
    func testWhileAnythingLoadsTheMonthIsBare() {
        let calendar = makeCalendar()
        let runs = [run("r", at: date(2026, 10, 9, in: calendar))]

        for page in [
            october(runs: runs, liveLoaded: false),
            october(runs: runs, loadState: .loading),
            october(runs: runs, loadState: .idle),
            october(runs: runs, squadState: .loading),
        ] {
            XCTAssertTrue(page.isLoading)
            XCTAssertTrue(page.marks.isEmpty)
            XCTAssertNil(page.squadColorKey)
        }
    }

    /// A month fetched once this session keeps its marks while it is fetched
    /// again — opening the popup forces one — rather than drawing runs the
    /// view model already holds as emptiness for the round trip (2026-11-11).
    /// The first fetch of a month is still a load, whatever the live listener
    /// holds.
    func testARefetchOfAFetchedMonthKeepsItsMarks() {
        let calendar = makeCalendar()
        let runs = [run("r", at: date(2026, 10, 9, in: calendar))]

        let refreshing = october(runs: runs, loadState: .loading, hasFetched: true)
        XCTAssertFalse(refreshing.isLoading)
        XCTAssertEqual(refreshing.marks[9]?.runCount, 1)
        XCTAssertNotNil(refreshing.squadColorKey)

        let first = october(runs: runs, loadState: .loading, hasFetched: false)
        XCTAssertTrue(first.isLoading)
        XCTAssertTrue(first.marks.isEmpty)
    }

    /// Squad games that couldn't be read: no squad zones — and the
    /// popup says why, rather than drawing a month without them.
    func testUnavailableSquadGamesAreNeverDrawnAsNone() {
        let calendar = makeCalendar()
        let page = october(games: [match("g", at: date(2026, 10, 9, in: calendar))], squadState: .unavailable)

        XCTAssertNil(page.squadColorKey)
        XCTAssertTrue(page.marks.isEmpty)
        XCTAssertTrue(page.squadGamesFailed)
        XCTAssertFalse(october(squadState: .noSquad).squadGamesFailed, "no squad is not a failure")
    }

    /// A failed fetch says so in the popup's words, and still draws what the
    /// live listener holds.
    func testAFailedMonthSaysWhyAndKeepsWhatItHas() {
        let calendar = makeCalendar()
        let runs = [run("r", at: date(2026, 10, 9, in: calendar))]

        let offline = october(runs: runs, loadState: .failed(.network))
        XCTAssertEqual(offline.failure, "Couldn't load October. Check your connection.")
        XCTAssertFalse(offline.isLoading)
        XCTAssertEqual(offline.marks[9]?.runCount, 1)

        XCTAssertEqual(
            october(loadState: .failed(.permissionDenied)).failure,
            FailureText.rulesNotDeployed(loading: "this month")
        )
        XCTAssertNil(october().failure)
    }

    // MARK: - Paging

    func testPagingStopsAtTheBounds() {
        let calendar = makeCalendar()
        let october1 = date(2026, 10, 1, 0, 0, in: calendar)

        let open = october(bounds: date(2026, 6, 1, 0, 0, in: calendar) ... date(2026, 11, 1, 0, 0, in: calendar))
        XCTAssertTrue(open.canGoBack)
        XCTAssertTrue(open.canGoForward)

        let pinned = october(bounds: october1 ... october1)
        XCTAssertFalse(pinned.canGoBack)
        XCTAssertFalse(pinned.canGoForward)
    }

    func testBoundsGoBackToTheMonthYouJoined() {
        let calendar = makeCalendar()
        let bounds = RunCalendarViewModel.bounds(
            createdAt: date(2026, 6, 20, in: calendar), latestScheduledSquadGame: nil,
            now: date(2026, 10, 5, in: calendar), calendar: calendar
        )
        XCTAssertEqual(bounds.lowerBound, date(2026, 6, 1, 0, 0, in: calendar))
    }

    /// No `createdAt` on the profile yet: twelve months back from this one.
    func testWithoutACreationDateBoundsFallBackTwelveMonths() {
        let calendar = makeCalendar()
        let bounds = RunCalendarViewModel.bounds(
            createdAt: nil, latestScheduledSquadGame: nil, now: date(2026, 10, 5, in: calendar), calendar: calendar
        )
        XCTAssertEqual(bounds.lowerBound, date(2025, 10, 1, 0, 0, in: calendar))
    }

    /// Joined this month: nowhere to page back to. A creation date in the
    /// future — a skewed clock — can't push the lower bound past this month.
    func testTheLowerBoundNeverPassesThisMonth() {
        let calendar = makeCalendar()
        let now = date(2026, 10, 5, in: calendar)
        let thisMonth = date(2026, 10, 1, 0, 0, in: calendar)

        for created in [date(2026, 10, 2, in: calendar), date(2027, 3, 1, in: calendar)] {
            XCTAssertEqual(
                RunCalendarViewModel.bounds(createdAt: created, latestScheduledSquadGame: nil, now: now, calendar: calendar).lowerBound,
                thisMonth
            )
        }
    }

    /// Forward is next month — a run books at most 30 days out — unless a
    /// scheduled squad game is later than that.
    func testBoundsGoForwardToNextMonthOrTheLatestScheduledGame() {
        let calendar = makeCalendar()
        let now = date(2026, 10, 5, in: calendar)
        let november = date(2026, 11, 1, 0, 0, in: calendar)

        XCTAssertEqual(
            RunCalendarViewModel.bounds(createdAt: nil, latestScheduledSquadGame: nil, now: now, calendar: calendar).upperBound,
            november
        )
        XCTAssertEqual(
            RunCalendarViewModel.bounds(
                createdAt: nil, latestScheduledSquadGame: date(2026, 11, 20, in: calendar), now: now, calendar: calendar
            ).upperBound,
            november
        )
        XCTAssertEqual(
            RunCalendarViewModel.bounds(
                createdAt: nil, latestScheduledSquadGame: date(2027, 1, 14, in: calendar), now: now, calendar: calendar
            ).upperBound,
            date(2027, 1, 1, 0, 0, in: calendar)
        )
    }

    // MARK: - Joining fetched runs to the live listener

    /// Union by `id`, and **the live copy wins** — it is the newer one.
    func testMergeDedupesByIdAndTheLiveCopyWins() {
        let calendar = makeCalendar()
        let tipOff = date(2026, 10, 9, 18, in: calendar)
        let stale = run("same", at: tipOff, status: .open, players: ["host"])
        let fresh = run("same", at: tipOff, status: .full, players: ["host", "me"])
        let other = run("other", at: tipOff.addingTimeInterval(-86_400))

        let merged = RunCalendarViewModel.merged(fetched: [stale, other], live: [fresh])

        XCTAssertEqual(merged.map(\.id), ["other", "same"], "soonest first, one of each")
        XCTAssertEqual(merged.last?.status, .full)
        XCTAssertEqual(merged.last?.playerIds, ["host", "me"])
    }

    /// With `liveFrom`, a fetched run the listener should hold and doesn't is
    /// gone — you left it, or it was cancelled — and an older one stays,
    /// because the listener never covered it.
    func testARunTheLiveListenerNoLongerHoldsIsDropped() {
        let from = Date(timeIntervalSince1970: 1_800_000_000)
        let left = run("left", at: from.addingTimeInterval(3_600))
        let atTheEdge = run("edge", at: from)
        let played = run("played", at: from.addingTimeInterval(-3_600), status: .completed)

        XCTAssertEqual(
            RunCalendarViewModel.merged(fetched: [left, atTheEdge, played], live: [], liveFrom: from).map(\.id),
            ["played"]
        )
        // Without it, the same call is the plain union.
        XCTAssertEqual(
            RunCalendarViewModel.merged(fetched: [left, played], live: []).map(\.id),
            ["played", "left"]
        )
    }

    // MARK: - Whether the squad's games can be drawn

    /// **A month with no rings is only an answer once the squad has answered.**
    func testSquadGamesAreNeverDrawnFromAHalfKnownAnswer() {
        func state(
            hasSquad: Bool = true, squadsLoaded: Bool = true, squadsFailed: Bool = false,
            gamesLoaded: Bool = true, gamesFailed: Bool = false
        ) -> RunCalendarViewModel.SquadGamesState {
            RunCalendarViewModel.squadGamesState(
                hasSquad: hasSquad, squadsLoaded: squadsLoaded, squadsFailed: squadsFailed,
                gamesLoaded: gamesLoaded, gamesFailed: gamesFailed
            )
        }

        XCTAssertEqual(state(), .available)
        XCTAssertEqual(state(gamesLoaded: false), .loading)
        XCTAssertEqual(state(gamesFailed: true), .unavailable)
        XCTAssertEqual(state(gamesLoaded: false, gamesFailed: true), .unavailable)

        XCTAssertEqual(state(hasSquad: false), .noSquad)
        XCTAssertEqual(state(hasSquad: false, squadsLoaded: false), .loading)
        XCTAssertEqual(state(hasSquad: false, squadsLoaded: false, squadsFailed: true), .unavailable)
    }

    // MARK: - The tile

    /// This month in miniature — its rows, its marks, today — and the month in
    /// one sentence.
    func testTheTileShowsTheMonthAndSpeaksIt() {
        let calendar = makeCalendar()
        let now = date(2026, 10, 5, in: calendar)
        let page = october(
            runs: [run("r", at: date(2026, 10, 9, in: calendar))],
            games: [match("g", at: date(2026, 10, 12, in: calendar))]
        )
        let tile = RunCalendarViewModel.tile(for: page, now: now, hasAnyMark: true, calendar: calendar)

        XCTAssertEqual(tile.monthAbbreviation, "Oct")
        XCTAssertEqual(tile.today, 5)
        XCTAssertEqual(tile.rows, page.rows)
        XCTAssertEqual(tile.marks, page.marks)
        XCTAssertEqual(tile.squadColorKey, "teal")
        XCTAssertEqual(tile.spoken, "October: runs on 1 day, squad games on 1 day")
        XCTAssertTrue(tile.hasMarks)
    }

    /// Loading, it says so; with the squad's games unknown, it says nothing
    /// about them rather than "squad games on 0 days".
    func testTheTileNeverSpeaksAHalfKnownMonth() {
        let calendar = makeCalendar()
        let now = date(2026, 10, 5, in: calendar)
        let runs = [run("r", at: date(2026, 10, 9, in: calendar))]

        XCTAssertEqual(
            RunCalendarViewModel.tile(for: october(runs: runs, liveLoaded: false), now: now, hasAnyMark: false, calendar: calendar).spoken,
            "October: loading"
        )
        for state in [RunCalendarViewModel.SquadGamesState.noSquad, .unavailable] {
            XCTAssertEqual(
                RunCalendarViewModel.tile(for: october(runs: runs, squadState: state), now: now, hasAnyMark: true, calendar: calendar).spoken,
                "October: runs on 1 day",
                "\(state)"
            )
        }
    }

    // MARK: - What VoiceOver says

    func testSpokenMonth() {
        let calendar = makeCalendar()
        let now = date(2026, 10, 5, in: calendar)
        let october = CalendarMonth(containing: now, calendar: calendar)

        XCTAssertEqual(
            RunCalendarViewModel.spokenMonth(october, runDays: 3, squadGameDays: 2, now: now, calendar: calendar),
            "October: runs on 3 days, squad games on 2 days"
        )
        XCTAssertEqual(
            RunCalendarViewModel.spokenMonth(october, runDays: 0, squadGameDays: 0, now: now, calendar: calendar),
            "October: runs on 0 days, squad games on 0 days"
        )
        XCTAssertEqual(
            RunCalendarViewModel.spokenMonth(october, runDays: 2, squadGameDays: nil, now: now, calendar: calendar),
            "October: runs on 2 days"
        )
        let last = CalendarMonth(containing: date(2025, 10, 5, in: calendar), calendar: calendar)
        XCTAssertEqual(
            RunCalendarViewModel.spokenMonth(last, runDays: 1, squadGameDays: nil, now: now, calendar: calendar),
            "October 2025: runs on 1 day"
        )
    }

    func testSpokenDay() {
        let calendar = makeCalendar()
        let tuesday = date(2026, 10, 6, in: calendar)

        XCTAssertEqual(
            RunCalendarViewModel.spokenDay(tuesday, runCount: 1, squadOpponents: ["Hornets"], calendar: calendar),
            "Tuesday, October 6, 1 run, squad game against Hornets"
        )
        XCTAssertEqual(
            RunCalendarViewModel.spokenDay(tuesday, runCount: 2, squadOpponents: [], calendar: calendar),
            "Tuesday, October 6, 2 runs"
        )
        XCTAssertEqual(
            RunCalendarViewModel.spokenDay(tuesday, runCount: 0, squadOpponents: [], calendar: calendar),
            "Tuesday, October 6"
        )
    }

    /// Each day cell carries its own sentence, built from what it lists.
    func testEachDayCellSpeaksWhatItHolds() {
        let calendar = makeCalendar()
        let page = october(
            runs: [run("r", at: date(2026, 10, 9, 18, in: calendar))],
            games: [match("g", at: date(2026, 10, 9, 20, in: calendar))]
        )
        XCTAssertEqual(page.spokenDays[9], "Friday, October 9, 1 run, squad game against Hornets")
        XCTAssertEqual(page.spokenDays[10], "Saturday, October 10")
        XCTAssertEqual(page.dayTitles[9], "Friday, October 9")
    }

    // MARK: - The tile beside the scoreboard, and the popup's grid

    /// Every size, smallest to largest.
    private let ladder: [UIContentSizeCategory] = [
        .extraSmall, .small, .medium, .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
        .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge,
    ]

    /// **The tile is beside the board through the largest size where
    /// everything fits, and under it from the next on** — a prefix of the
    /// ladder, never a gap in it, so making text bigger never brings the tile
    /// back.
    func testTheTileIsBesideTheBoardThroughOneSizeAndUnderItFromTheNext() {
        let besides = ladder.map { HomeStatsLayout.isSideBySide(at: $0) }
        let firstUnder = besides.firstIndex(of: false) ?? besides.count

        XCTAssertTrue(besides[..<firstUnder].allSatisfy { $0 })
        XCTAssertTrue(besides[firstUnder...].allSatisfy { !$0 }, "contiguous: \(besides)")
        XCTAssertTrue(HomeStatsLayout.isSideBySide(at: .large))
        XCTAssertFalse(HomeStatsLayout.isSideBySide(at: .accessibilityExtraLarge))
    }

    /// The tile's seven squares and six gaps fill its screen exactly.
    func testTheTilesSquaresFillItsScreen() {
        let across = RunCalendarTileMetrics.square * 7 + RunCalendarTileMetrics.gap * 6
        XCTAssertEqual(across, StatsScoreboardMetrics.innerWidth(cardWidth: RunCalendarTileMetrics.width), accuracy: 0.01)
    }

    /// Three dots at their largest, and their gaps, fit inside a zone.
    func testThreeDotsFitAZoneAtTheirLargest() {
        let dots = CGFloat(RunCalendarViewModel.DayMark.maximumDots)
        let across = RunCalendarMetrics.maximumDotDiameter * dots + RunCalendarMetrics.dotSpacing * (dots - 1)
        XCTAssertLessThanOrEqual(across + 2, RunCalendarMetrics.zoneWidth())
    }

    /// A narrower phone has less to share, so the tile goes under no later.
    func testANarrowerPhoneMovesTheTileNoLater() {
        for category in ladder where !HomeStatsLayout.isSideBySide(at: category) {
            XCTAssertFalse(HomeStatsLayout.isSideBySide(at: category, contentWidth: 335), category.rawValue)
        }
    }

    /// **The popup's grid holds at every size**: every column a 44pt target,
    /// every day number inside its zone — which is why there is no list-shaped
    /// fallback for the accessibility sizes.
    func testThePopupsGridFitsAtEverySize() {
        XCTAssertGreaterThanOrEqual(RunCalendarMetrics.columnWidth(), RunCalendarMetrics.minimumTarget)
        for category in ladder {
            XCTAssertTrue(
                RunCalendarMetrics.fits(at: category),
                "\(category.rawValue): a day is \(RunCalendarMetrics.dayNumberWidth(at: category))pt in a \(RunCalendarMetrics.zoneWidth())pt zone"
            )
        }
    }

    /// The day numbers' cap bites only at the top two sizes: every size below
    /// sets the numbers at the type ramp's own size.
    func testTheDayNumberCapOnlyBitesAtTheLargestSizes() {
        for category in ladder.dropLast(2) {
            XCTAssertLessThanOrEqual(
                HooprFontMetrics.scaledSize(HooprTextRole.caption.size, at: category),
                RunCalendarMetrics.dayNumberMaximumSize, category.rawValue
            )
        }
        for category in ladder.suffix(2) {
            XCTAssertGreaterThan(
                HooprFontMetrics.scaledSize(HooprTextRole.caption.size, at: category),
                RunCalendarMetrics.dayNumberMaximumSize, category.rawValue
            )
        }
    }
}
