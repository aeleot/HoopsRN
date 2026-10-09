import Combine
import Foundation
import UIKit

/// A calendar month, as a value: what the month popup is presented on, and
/// what the cache is keyed by.
nonisolated struct CalendarMonth: Identifiable, Hashable, Sendable {
    /// The first instant of the month, in the calendar it was made with.
    let start: Date

    var id: Date { start }

    init(containing date: Date, calendar: Calendar = .current) {
        start = calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// The month as a half-open range: a run at exactly `end` belongs to the
    /// next month.
    func interval(calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .month, for: start) ?? DateInterval(start: start, duration: 0)
    }

    func adding(months: Int, calendar: Calendar = .current) -> CalendarMonth {
        CalendarMonth(containing: calendar.date(byAdding: .month, value: months, to: start) ?? start, calendar: calendar)
    }
}

/// Backs Home's run calendar: the tile beside the scoreboard, and the month
/// popup it opens — how many runs you are on each day of a month, and which
/// days your squad has a season game.
///
/// **Two sources, one picture.** A *run* is a `games` document you are on
/// (`playerIds` contains you — a waitlisted run is not one you are on, and gets
/// no mark). The live listener behind `GameService.queuedGames` is windowed to
/// the future, so earlier days of this month, and every past month, come from
/// `GameService.runs(in:)`, one month at a time, cached for the session. A
/// *season game* is read off `SeasonGameService.games`, which the shell keeps
/// open for the whole session — no read of its own.
///
/// **The join happens here, not in a service**, like Home's and the map's:
/// runs, season games and squads know nothing of each other.
///
/// **Days bucket on `Calendar.current`, by `scheduledTime`**: a run at 11:30 PM
/// local is on that local day. Deliberately not the streak's UTC ISO week,
/// which has to agree across devices; this is a picture of your own days.
///
/// Every rule is a `nonisolated static` function, pure and tested without a
/// service, like `HomeViewModel.rankHotCourts`.
@MainActor
final class RunCalendarViewModel: ObservableObject {
    /// One day's marks: how many runs you are on, and whether your squad
    /// plays — drawn as the day's zone and dots.
    nonisolated struct DayMark: Equatable, Sendable {
        /// What a day's square is filled with.
        nonisolated enum Zone: Equatable, Sendable {
            /// The screen's own unlit square: nothing on, or a run or two.
            case plain
            /// Three or more runs: red and orange, a day on fire.
            case fire
            /// A season game: your squad's colour. Outranks fire — a match is the
            /// rarer and the bigger thing, and the dots still count the runs.
            case squad
        }

        /// One dot per run, up to this many.
        static let maximumDots = 3
        /// Runs it takes to set a day on fire.
        static let fireRuns = 3

        var runCount = 0
        var hasSquadGame = false

        var dots: Int { min(runCount, Self.maximumDots) }

        var zone: Zone {
            if hasSquadGame { return .squad }
            return runCount >= Self.fireRuns ? .fire : .plain
        }
    }

    /// Whether your squad's games can be drawn at all.
    nonisolated enum SquadGamesState: Equatable, Sendable {
        /// No squad: no squad zones, and no squad copy.
        case noSquad
        /// Something hasn't answered yet. A month with no squad zones is not an
        /// answer to "does my squad play this month".
        case loading
        /// A listener failed or is re-attaching. Never drawn as "no games".
        case unavailable
        case available
    }

    /// Where a month's fetch stands.
    nonisolated enum LoadState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(GameError)
    }

    /// The tile beside the scoreboard: this month in miniature — a lit square
    /// for every day with something on — and what VoiceOver says about it.
    nonisolated struct Tile: Equatable, Sendable {
        /// "Oct" — uppercased by the type role, never by the string.
        let monthAbbreviation: String
        /// This month's rows of seven, `nil` for a blank.
        let rows: [[Int?]]
        let marks: [Int: DayMark]
        let today: Int
        /// Set only while your squad's games are known.
        let squadColorKey: String?
        let spoken: String
        /// Whether anything in the loaded range is marked — what decides if
        /// Home shows the calendar for someone with no stats.
        let hasMarks: Bool
    }

    /// One month as the popup draws it.
    nonisolated struct Page: Equatable, Sendable {
        let month: CalendarMonth
        /// "October", or "October 2025" in another year.
        let title: String
        /// Seven, from the calendar's first weekday.
        let weekdayInitials: [String]
        /// `nil` is a leading blank; otherwise the day of the month.
        let grid: [Int?]
        let marks: [Int: DayMark]
        /// "Tuesday, October 7" — the popup's footer for the selected day.
        let dayTitles: [Int: String]
        /// Each day cell's VoiceOver label.
        let spokenDays: [Int: String]
        /// The day of the month it is today, when today is in this month.
        let today: Int?
        /// Your squad's colour, which fills a game day's zone. Set only when your
        /// squad's games are known, so a zone is never coloured from a
        /// half-known answer.
        let squadColorKey: String?
        /// Something hasn't answered: the grid draws bare.
        let isLoading: Bool
        /// The month's fetch failed, in the words the popup shows.
        let failure: String?
        /// Your squad's games couldn't be read, so the month has no squad zones.
        let squadGamesFailed: Bool
        let canGoBack: Bool
        let canGoForward: Bool

        /// The grid in rows of seven, the last padded out with blanks.
        var rows: [[Int?]] { RunCalendarViewModel.rows(of: grid) }
    }

    @Published private(set) var tile: Tile
    /// The month the popup is showing.
    @Published private(set) var page: Page

    // MARK: - Dependencies

    private let gameService: GameService
    private let seasonGameService: SeasonGameService
    private let squadService: SquadService
    private let userProfileService: UserProfileService
    private var cancellables = Set<AnyCancellable>()

    // MARK: - State

    /// Fetched runs by month start, kept for the session. A past month is
    /// final once fetched; the current one is refetched each time the popup
    /// opens, and every month is merged with the live listener
    /// (`merged(fetched:live:liveFrom:)`).
    private var fetched: [Date: [Game]] = [:]
    private var loadStates: [Date: LoadState] = [:]
    private var shownMonth = CalendarMonth(containing: Date())

    init(
        gameService: GameService,
        seasonGameService: SeasonGameService,
        squadService: SquadService,
        userProfileService: UserProfileService
    ) {
        self.gameService = gameService
        self.seasonGameService = seasonGameService
        self.squadService = squadService
        self.userProfileService = userProfileService

        let now = Date()
        let month = CalendarMonth(containing: now)
        let page = Self.page(
            month: month, now: now, runs: [], seasonGames: [], squad: nil, squadState: .loading,
            loadState: .idle, liveLoaded: false,
            bounds: month.start ... month.start
        )
        self.page = page
        tile = Self.tile(for: page, now: now, hasAnyMark: false)

        // Everything that can change the picture. Each hops to the next main
        // turn first: a `@Published` sink fires in `willSet`, before the
        // property holds the new value, and `rebuild()` reads the properties.
        rebuildOn(gameService.$queuedGames)
        rebuildOn(gameService.$hasLoadedGames)
        rebuildOn(seasonGameService.$games)
        rebuildOn(seasonGameService.$hasLoadedGames)
        rebuildOn(seasonGameService.$errorMessage)
        rebuildOn(seasonGameService.$isRecovering)
        rebuildOn(squadService.$squads)
        rebuildOn(squadService.$hasLoadedSquads)
        rebuildOn(squadService.$errorMessage)

        // A different account is a different calendar: forget the last one's
        // months. The profile is what carries the uid here — and `createdAt`,
        // the calendar's first month — and it arrives after `GameService` has
        // attached, so the first fetch can't be early.
        userProfileService.$currentProfile
            .map { $0?.id }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] uid in
                guard let self else { return }
                fetched = [:]
                loadStates = [:]
                shownMonth = CalendarMonth(containing: Date())
                rebuild()
                if uid != nil { loadInBackground(shownMonth) }
            }
            .store(in: &cancellables)
        rebuildOn(userProfileService.$currentProfile)

        // The first answer from the live listener, and an outage ending, are
        // the moments a failed or not-yet-attempted fetch is worth trying again.
        gameService.$hasLoadedGames
            .removeDuplicates()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.loadInBackground(CalendarMonth(containing: Date())) }
            .store(in: &cancellables)

        gameService.$isRecovering
            .removeDuplicates()
            .filter { !$0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.loadInBackground(CalendarMonth(containing: Date())) }
            .store(in: &cancellables)

        // Midnight, a month turning over, a time-zone change — delivered after
        // the fact if the app was in the background for it. No timer.
        NotificationCenter.default
            .publisher(for: UIApplication.significantTimeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuild()
                self?.loadInBackground(CalendarMonth(containing: Date()))
            }
            .store(in: &cancellables)
    }

    private func rebuildOn<P: Publisher>(_ publisher: P) where P.Failure == Never {
        publisher
            .map { _ in () }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
    }

    // MARK: - The popup

    /// Opens on this month, refetched: it is the one month that can change
    /// under you. Returns it, for the popup's presentation.
    func open() -> CalendarMonth {
        let month = CalendarMonth(containing: Date())
        shownMonth = month
        rebuild()
        loadInBackground(month, force: true)
        return month
    }

    /// Pages by `offset` months, inside the bounds. A month already fetched
    /// this session is served from the cache.
    func showMonth(offset: Int) {
        guard offset < 0 ? page.canGoBack : page.canGoForward else { return }
        shownMonth = shownMonth.adding(months: offset)
        rebuild()
        loadInBackground(shownMonth)
    }

    func retry() {
        loadInBackground(shownMonth, force: true)
    }

    // MARK: - Loading a month

    private func loadInBackground(_ month: CalendarMonth, force: Bool = false) {
        Task { [weak self] in await self?.load(month, force: force) }
    }

    /// Fetches `month` unless it is already here.
    ///
    /// A failure is kept for the popup to show, and never becomes a banner:
    /// nothing here writes `GameService.errorMessage`, which belongs to the
    /// live listeners.
    private func load(_ month: CalendarMonth, force: Bool) async {
        let key = month.start
        let state = loadStates[key] ?? .idle
        if state == .loading { return }
        if state == .loaded, !force { return }

        let uid = gameService.currentUserId
        loadStates[key] = .loading
        rebuild()

        do {
            let runs = try await gameService.runs(in: month.interval())
            // Signed out, or into another account, while it was in flight.
            guard gameService.currentUserId == uid else { return }
            fetched[key] = runs
            loadStates[key] = .loaded
        } catch GameError.notSignedIn {
            // Nobody to ask yet; the next sign-in tries again.
            loadStates[key] = .idle
        } catch let error as GameError {
            loadStates[key] = .failed(error)
        } catch {
            loadStates[key] = .failed(.unknown(error.localizedDescription))
        }
        rebuild()
    }

    // MARK: - Rebuilding

    private func rebuild() {
        let now = Date()
        let current = CalendarMonth(containing: now)

        let squad = squadService.squads.first
        let squadState = Self.squadGamesState(
            hasSquad: squad != nil,
            squadsLoaded: squadService.hasLoadedSquads,
            squadsFailed: squadService.errorMessage != nil,
            gamesLoaded: seasonGameService.hasLoadedGames,
            gamesFailed: seasonGameService.errorMessage != nil || seasonGameService.isRecovering
        )

        // One squad per person is enforced by the app only, so the filter is
        // the squad's own and not an assumption about what the listener holds.
        let seasonGames: [SeasonGame] = {
            guard squadState == .available, let squad else { return [] }
            return seasonGameService.games.filter { $0.squadIds.contains(squad.id) }
        }()

        // Only once the live listener has answered: until then an empty
        // `queuedGames` would read as "every upcoming run was cancelled".
        let live = gameService.queuedGames
        let liveFrom = gameService.hasLoadedGames ? Game.visibilityCutoff(from: now) : nil

        let bounds = Self.bounds(
            createdAt: userProfileService.currentProfile?.createdAt,
            latestScheduledSquadGame: seasonGames.filter { $0.status == .scheduled }.map(\.scheduledTime).max(),
            now: now
        )

        func buildPage(for month: CalendarMonth) -> Page {
            Self.page(
                month: month, now: now,
                runs: Self.merged(fetched: fetched[month.start] ?? [], live: live, liveFrom: liveFrom),
                seasonGames: seasonGames, squad: squad, squadState: squadState,
                loadState: loadStates[month.start] ?? .idle,
                liveLoaded: gameService.hasLoadedGames, bounds: bounds
            )
        }

        let currentPage = buildPage(for: current)
        let shownPage = shownMonth == current ? currentPage : buildPage(for: shownMonth)

        let everyRun = fetched.values.flatMap { $0 } + live
        let hasAnyMark = !everyRun.isEmpty || seasonGames.contains { $0.status != .cancelled }
        let nextTile = Self.tile(for: currentPage, now: now, hasAnyMark: hasAnyMark)

        if nextTile != tile { tile = nextTile }
        if shownPage != page { page = shownPage }
    }

    // MARK: - Building a month

    /// Everything the popup draws for `month`, from plain values.
    ///
    /// **Loading is not emptiness.** While the live listener, the month's
    /// fetch or the squad's games haven't answered, the grid draws bare — a
    /// half-loaded month would be an answer, and the wrong one. A **failed**
    /// fetch still draws what the live listener holds, with the failure beside
    /// it to say the month is incomplete.
    nonisolated static func page(
        month: CalendarMonth,
        now: Date,
        runs: [Game],
        seasonGames: [SeasonGame],
        squad: Squad?,
        squadState: SquadGamesState,
        loadState: LoadState,
        liveLoaded: Bool,
        bounds: ClosedRange<Date>,
        calendar: Calendar = .current
    ) -> Page {
        let isLoading = !liveLoaded || loadState == .idle || loadState == .loading || squadState == .loading
        let failure: String? = {
            guard case .failed(let error) = loadState else { return nil }
            return failureText(for: error, month: month, now: now, calendar: calendar)
        }()

        let games = squadState == .available ? seasonGames : []
        let dayMarks = isLoading ? [:] : marks(runs: runs, seasonGames: games, in: month.start, calendar: calendar)
        let opponents = isLoading || squad == nil
            ? [:]
            : opponentsByDay(seasonGames: games, squadId: squad?.id ?? "", in: month.start, calendar: calendar)

        let grid = monthGrid(for: month.start, calendar: calendar)
        var dayTitles: [Int: String] = [:]
        var spokenDays: [Int: String] = [:]
        for day in grid.compactMap({ $0 }) {
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: month.start) else { continue }
            dayTitles[day] = spokenDay(date, runCount: 0, squadOpponents: [], calendar: calendar)
            spokenDays[day] = spokenDay(
                date,
                runCount: dayMarks[day]?.runCount ?? 0,
                squadOpponents: opponents[day] ?? [],
                calendar: calendar
            )
        }

        let interval = month.interval(calendar: calendar)
        let today = now >= interval.start && now < interval.end ? calendar.component(.day, from: now) : nil
        let drawsSquad = squadState == .available && !isLoading

        return Page(
            month: month,
            title: monthName(month, now: now, calendar: calendar),
            weekdayInitials: weekdayInitials(calendar: calendar),
            grid: grid,
            marks: dayMarks,
            dayTitles: dayTitles,
            spokenDays: spokenDays,
            today: today,
            squadColorKey: drawsSquad ? squad?.colorKey : nil,
            isLoading: isLoading,
            failure: failure,
            squadGamesFailed: squadState == .unavailable,
            canGoBack: month.start > bounds.lowerBound,
            canGoForward: month.start < bounds.upperBound
        )
    }

    /// The tile, from the current month's page: its days and marks, and the
    /// month in one sentence for VoiceOver.
    nonisolated static func tile(
        for page: Page,
        now: Date,
        hasAnyMark: Bool,
        calendar: Calendar = .current
    ) -> Tile {
        let formatter = makeFormatter(calendar: calendar)
        formatter.setLocalizedDateFormatFromTemplate("LLL")

        let spoken: String
        if page.isLoading {
            spoken = "\(monthName(page.month, now: now, calendar: calendar)): loading"
        } else {
            spoken = spokenMonth(
                page.month,
                runDays: page.marks.values.filter { $0.runCount > 0 }.count,
                squadGameDays: page.squadColorKey == nil ? nil : page.marks.values.filter(\.hasSquadGame).count,
                now: now,
                calendar: calendar
            )
        }

        return Tile(
            monthAbbreviation: formatter.string(from: now),
            rows: page.rows,
            marks: page.marks,
            today: calendar.component(.day, from: now),
            squadColorKey: page.squadColorKey,
            spoken: spoken,
            hasMarks: hasAnyMark
        )
    }

    /// The day the popup opens on: today when it is in the month, otherwise
    /// the first day with something on it, otherwise the 1st.
    nonisolated static func defaultSelection(in page: Page) -> Int {
        page.today ?? page.marks.keys.min() ?? 1
    }

    // MARK: - Pure rules

    /// The month's days laid out for a seven-column grid: `nil` for each blank
    /// before the 1st — as many as the 1st is days past the calendar's first
    /// weekday — then 1 through 28, 29, 30 or 31.
    nonisolated static func monthGrid(for month: Date, calendar: Calendar = .current) -> [Int?] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let days = calendar.range(of: .day, in: .month, for: month)?.count
        else { return [] }

        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        return Array(repeating: nil, count: leading) + (1 ... days).map { Optional($0) }
    }

    /// A grid in rows of seven, the last padded out with blanks.
    nonisolated static func rows(of grid: [Int?]) -> [[Int?]] {
        stride(from: 0, to: grid.count, by: 7).map { start in
            var row = Array(grid[start ..< min(start + 7, grid.count)])
            while row.count < 7 { row.append(nil) }
            return row
        }
    }

    /// "S M T W T F S", from the calendar's first weekday.
    nonisolated static func weekdayInitials(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// How many runs each day of `month` has, and which have a season game.
    ///
    /// Anything outside the month is ignored, so a list that spans months — the
    /// live listener's does — can be handed in whole. A **cancelled** match is
    /// not on anyone's calendar; every other status is (`scheduled`, and the
    /// two a result can leave it in).
    nonisolated static func marks(
        runs: [Game],
        seasonGames: [SeasonGame],
        in month: Date,
        calendar: Calendar = .current
    ) -> [Int: DayMark] {
        var marks: [Int: DayMark] = [:]
        for run in runs {
            if let day = day(of: run.scheduledTime, in: month, calendar: calendar) {
                marks[day, default: DayMark()].runCount += 1
            }
        }
        for game in seasonGames where game.status != .cancelled {
            if let day = day(of: game.scheduledTime, in: month, calendar: calendar) {
                marks[day, default: DayMark()].hasSquadGame = true
            }
        }
        return marks
    }

    /// The other squad in each of your squad's games, by day of `month`,
    /// soonest first — what a day cell tells VoiceOver it holds. A cancelled
    /// match is on nobody's calendar.
    nonisolated static func opponentsByDay(
        seasonGames: [SeasonGame],
        squadId: String,
        in month: Date,
        calendar: Calendar = .current
    ) -> [Int: [String]] {
        var opponents: [Int: [String]] = [:]
        for game in seasonGames.sorted(by: { $0.scheduledTime < $1.scheduledTime }) where game.status != .cancelled {
            guard let day = day(of: game.scheduledTime, in: month, calendar: calendar),
                  let name = game.opponentName(of: squadId)
            else { continue }
            opponents[day, default: []].append(name)
        }
        return opponents
    }

    /// The day of `month` that `date` falls on, or `nil` outside it.
    /// `DateInterval.contains` includes its end — the next month's first
    /// instant — so the check is written out.
    private nonisolated static func day(of date: Date, in month: Date, calendar: Calendar) -> Int? {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              date >= interval.start, date < interval.end
        else { return nil }
        return calendar.component(.day, from: date)
    }

    /// The runs to draw: what was fetched, and what the live listener holds.
    /// Union by `id`, and **the live copy wins** — it is newer than whatever was
    /// fetched, which is how a run joined a minute ago appears without a refetch.
    ///
    /// `liveFrom` is the start of what the live listener covers. With it, a
    /// fetched run at or after that moment which the listener *doesn't* hold is
    /// gone — you left it, or its host cancelled it — and is dropped, instead of
    /// keeping its dot until the next fetch. Without it this is a plain union.
    nonisolated static func merged(fetched: [Game], live: [Game], liveFrom: Date? = nil) -> [Game] {
        let liveIDs = Set(live.map(\.id))
        let kept = fetched.filter { game in
            if liveIDs.contains(game.id) { return false }
            if let liveFrom, game.scheduledTime >= liveFrom { return false }
            return true
        }
        return (kept + live).sorted { lhs, rhs in
            lhs.scheduledTime == rhs.scheduledTime ? lhs.id < rhs.id : lhs.scheduledTime < rhs.scheduledTime
        }
    }

    /// The first and last month the calendar can show — as month starts.
    ///
    /// Back to the month you joined (`createdAt`), or twelve months before this
    /// one when the profile doesn't say; never later than this month. Forward
    /// to the later of next month and the month of your squad's last scheduled
    /// game: runs can only be booked 30 days ahead, so next month is as far as
    /// a run goes, and a season game can be further out.
    nonisolated static func bounds(
        createdAt: Date?,
        latestScheduledSquadGame: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> ClosedRange<Date> {
        let current = CalendarMonth(containing: now, calendar: calendar).start

        let earliest: Date
        if let createdAt {
            earliest = min(CalendarMonth(containing: createdAt, calendar: calendar).start, current)
        } else {
            earliest = calendar.date(byAdding: .month, value: -12, to: current) ?? current
        }

        let next = calendar.date(byAdding: .month, value: 1, to: current) ?? current
        var latest = next
        if let latestScheduledSquadGame {
            latest = max(next, CalendarMonth(containing: latestScheduledSquadGame, calendar: calendar).start)
        }
        return earliest ... latest
    }

    /// Whether your squad's games can be drawn, from what has answered.
    ///
    /// Order matters: a squad that is known is judged by the games listener;
    /// no squad is known only once the squads listener has answered, and until
    /// then — or if it never can — that is not "no squad".
    nonisolated static func squadGamesState(
        hasSquad: Bool,
        squadsLoaded: Bool,
        squadsFailed: Bool,
        gamesLoaded: Bool,
        gamesFailed: Bool
    ) -> SquadGamesState {
        if hasSquad {
            if gamesFailed { return .unavailable }
            return gamesLoaded ? .available : .loading
        }
        if squadsLoaded { return .noSquad }
        return squadsFailed ? .unavailable : .loading
    }

    /// What the popup says when a month's fetch fails. A denied **read** means
    /// the deployed rules aren't this repo's (`FailureText`); anything else is
    /// most likely the connection.
    nonisolated static func failureText(
        for error: GameError,
        month: CalendarMonth,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        switch error {
        case .permissionDenied:
            return FailureText.rulesNotDeployed(loading: "this month")
        case .indexRequired:
            return GameService.message(for: error, whileDoing: "loading this month", context: .load)
        default:
            return "Couldn't load \(monthName(month, now: now, calendar: calendar)). Check your connection."
        }
    }

    // MARK: - Spoken text

    /// "October: runs on 3 days, squad games on 1 day". The squad clause is
    /// left out when `squadGameDays` is `nil` — no squad, or its games aren't
    /// known — because "squad games on 0 days" would claim an answer. A month
    /// in another year than `now` carries its year.
    nonisolated static func spokenMonth(
        _ month: CalendarMonth,
        runDays: Int,
        squadGameDays: Int?,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        var text = "\(monthName(month, now: now, calendar: calendar)): runs on \(countText(runDays, "day"))"
        if let squadGameDays {
            text += ", squad games on \(countText(squadGameDays, "day"))"
        }
        return text
    }

    /// "Tuesday, October 7, 1 run, squad game against Hornets". A day with
    /// nothing on it is just its date.
    nonisolated static func spokenDay(
        _ date: Date,
        runCount: Int,
        squadOpponents: [String],
        calendar: Calendar = .current
    ) -> String {
        let formatter = makeFormatter(calendar: calendar)
        formatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")

        var parts = [formatter.string(from: date)]
        if runCount > 0 { parts.append(countText(runCount, "run")) }
        parts += squadOpponents.map { "squad game against \($0)" }
        return parts.joined(separator: ", ")
    }

    /// "October", or "October 2025" when it isn't `now`'s year.
    nonisolated static func monthName(_ month: CalendarMonth, now: Date, calendar: Calendar = .current) -> String {
        let sameYear = calendar.component(.year, from: month.start) == calendar.component(.year, from: now)
        let formatter = makeFormatter(calendar: calendar)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "LLLL" : "LLLLy")
        return formatter.string(from: month.start)
    }

    /// "1 day", "3 days" — the old stats card once said "1 wks".
    private nonisolated static func countText(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }

    /// In the calendar's own locale and zone, so a test's calendar and the
    /// phone's both format what they bucket.
    private nonisolated static func makeFormatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.timeZone = calendar.timeZone
        return formatter
    }
}
