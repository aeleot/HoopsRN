import Combine
import CoreLocation
import Foundation

/// Backs the Home tab: what you're committed to, and where the action is.
///
/// Every *displayed* value here is derived from listeners the app already
/// keeps open for the map and the runs list — `GameService`'s game arrays,
/// the bundled court dataset, the profile snapshot, and the friend graph —
/// costing no extra Firestore read.
///
/// One write lives here too, and it's the exception to "just reshapes what's
/// already published": whenever `GameService.completedGames` delivers a new
/// snapshot, this recalculates participation stats and writes them back via
/// `UserProfileService.refreshStats`. `HomeViewModel` is where both services
/// are already held for the subscriptions below, so that's the trigger point
/// rather than a new dependency between the two services themselves.
/// Wraps the three profile fields the stats subscription cares about so
/// `.removeDuplicates()` has something `Equatable` to compare — bare Swift
/// tuples aren't.
private struct ProfileStats: Equatable {
    let count: Int
    let streak: Int
    let lastCompletedAt: Date?
}

@MainActor
final class HomeViewModel: ObservableObject {
    /// A court with today's game count, ready for the "Hot right now" list.
    struct HotCourt: Identifiable, Equatable {
        let court: Court
        let gameCount: Int

        var id: String { court.id }
    }

    /// A squad with its record — what the scoreboard's squad panel shows.
    nonisolated struct SquadStanding: Equatable {
        let squad: Squad
        let record: SeasonGame.Record
    }

    /// One panel of Home's stats scoreboard (`StatsScoreboard`).
    ///
    /// Words and numbers only: which symbol and which type size a panel takes
    /// is the view's, by `kind`.
    nonisolated struct ScoreboardStat: Identifiable, Equatable {
        enum Kind: Hashable {
            case thisWeek
            case squad
            case streak
            case total
            case lastRun
        }

        let kind: Kind
        let label: String
        let value: String
        /// Set beside the value, smaller — "runs", "wks". `nil` where the
        /// value says it all ("Sep 24", a record).
        let unit: String?
        /// What VoiceOver says. "3 wks" is read as letters; "3 week streak" isn't.
        let spoken: String
        /// The squad and its record, for the crest and the record's dash.
        /// Only on the squad panel.
        let standing: SquadStanding?

        var id: Kind { kind }
    }

    /// The soonest run you're on, with its court resolved.
    ///
    /// Reuses `LocalRunsViewModel.Listing` rather than declaring a parallel
    /// type: it already carries the court join and the distance formatting
    /// this needs, and a second struct with the same three fields would drift.
    @Published private(set) var nextRun: LocalRunsViewModel.Listing?

    /// "Tonight nearby": today's busiest courts, less the one the hero is
    /// already about (`excludingBookedCourt`).
    @Published private(set) var hotCourts: [HotCourt] = []

    /// The courts closest to you, nearest first — the dots on the map preview
    /// "Tonight nearby" draws when nothing is on anywhere today.
    ///
    /// **Not `hotCourts` with the counts dropped.** `rankHotCourts` ranks the
    /// whole dataset by how busy a court is, not how near, so a preview built
    /// from it would frame courts across the Triangle. This is the nearest
    /// `previewCourtLimit` to the same origin every other distance reads.
    @Published private(set) var nearestCourts: [Court] = []

    /// Where `nearestCourts` was measured from — the centre of the preview.
    /// Published beside it, from the same rebuild, so the dots and the "you
    /// are here" marker can never come from two different fixes.
    @Published private(set) var previewOrigin: CLLocationCoordinate2D = LocationService.homeLocation

    /// Friend requests waiting on you. Only incoming ones count — a request
    /// you sent isn't yours to answer.
    @Published private(set) var incomingRequestCount = 0

    /// The stored profile name, or a neutral fallback while the first snapshot
    /// is in flight. Matches the greeting the floating header used to carry.
    @Published private(set) var greetingName = "there"

    /// Whether the signed-in user hosts `nextRun`, and whether they're only
    /// waitlisted on it, so the card badges it the same way `GameCard` does on
    /// the runs list rather than inventing a second vocabulary.
    @Published private(set) var isHostingNextRun = false
    @Published private(set) var isWaitlistedOnNextRun = false

    /// The one historical note on this screen — sourced from the profile
    /// snapshot, not computed here. All three default to the "no history yet"
    /// values (`0`/`0`/`"—"`) until the first `refreshStats` write lands, and
    /// reset to them again on sign-out.
    @Published private(set) var completedGameCount = 0
    @Published private(set) var participationStreak = 0
    @Published private(set) var lastCompletedText = "—"

    /// Completed runs in the current ISO week — the scoreboard's "Done this
    /// week".
    /// Off the same `completedGames` snapshot the stats are recalculated from,
    /// on the streak's calendar (`Game.completedThisWeek`).
    @Published private(set) var runsThisWeek = 0

    /// Your squad and its record, once the season's results have loaded — the
    /// scoreboard's one confirmed number. `nil` with no squad, and until the
    /// listener answers, so a "0–0" never flashes at a squad that has a record.
    @Published private(set) var squadStanding: SquadStanding?

    /// The scoreboard's panels, in the order they take turns. Empty for a
    /// brand-new account with no squad, which hides the scoreboard rather than
    /// showing it with all-zero values.
    @Published private(set) var scoreboardStats: [ScoreboardStat] = []

    /// Whether the games listener has delivered its first snapshot.
    ///
    /// **Without this the screen cannot tell "you have no run tonight" from
    /// "we haven't looked yet"**, and it showed the first while meaning the
    /// second for however long the listener took — the empty state's call to
    /// action flashing at a user who is, in fact, signed up for something.
    /// `GameService.hasLoadedGames` has carried the answer all along;
    /// `MapViewModel` already consumes it. This is the same value, not
    /// a new read.
    @Published private(set) var hasLoaded = false

    /// A listener failure, in the domain's words rather than Firebase's.
    ///
    /// Home had **no error state at all**: a dead listener rendered as an
    /// empty screen, which is the one reading this tab exists for and the one
    /// it must not get wrong silently. Republished from `GameService` rather
    /// than translated again here — the service owns the vocabulary.
    @Published private(set) var errorMessage: String?

    /// The supervisor is re-attaching a dropped listener. Distinguished from
    /// `errorMessage` because it is not a thing the user can act on, and a
    /// banner that cries wolf during a normal network blip trains them to
    /// ignore it.
    @Published private(set) var isRecovering = false

    /// The hero's two halves, split apart.
    ///
    /// `Game.scheduledText()` returns "Today · 6:30 PM" as one string, which
    /// was right when the card set it as a single 14pt line. The band sets the
    /// day as a label and the time as the screen's hero numeral, so they have
    /// to arrive separately — and both derive from the same `scheduledTime`,
    /// so the two can't disagree.
    ///
    /// Each of these is a thin wrapper over a `nonisolated static` function,
    /// for the reason the rest of this file is: the rule can then be tested
    /// without constructing a service or touching Firebase.
    var nextRunDayLabel: String {
        nextRun?.game.dayText() ?? "Tonight"
    }

    /// The time alone — "6:30 PM". The hero.
    var nextRunTimeText: String {
        nextRun?.game.timeText ?? "—"
    }

    /// Spots left, not "N / M players".
    ///
    /// The decision this screen supports is *can I still get on it* — one
    /// number, not a ratio to do arithmetic on. `rosterText` stays on
    /// `GameCard`, where the roster itself is the subject.
    var nextRunSpotsText: String? {
        nextRun?.game.spotsText
    }

    // MARK: - Hero text rules

    /// **The day, time and spots rules live on `Game`**, beside `rosterText`
    /// and `scheduledText()` — that is where this codebase already keeps a
    /// run's presentation strings, and putting a second copy here would mean
    /// `GameCard` and this band could drift into disagreeing about what "6:45"
    /// or "Tonight" means for the same run.

    /// How many courts the hot list shows. Three fits above the fold beside
    /// the other cards; the ranking below is written to take any limit.
    static let hotCourtLimit = 3

    /// How many courts the empty state's map preview frames. Enough to read
    /// as "courts around you" rather than a single pin, few enough that the
    /// frame stays a neighbourhood at the 1.5km floor.
    static let previewCourtLimit = 5

    /// What the "Tonight nearby" section shows.
    nonisolated enum NearbySection: Equatable {
        /// The listener hasn't answered yet.
        case loading
        /// The listener failed or is re-attaching, and there is nothing to
        /// show from before it did. An empty list here means "couldn't look",
        /// not "nothing's on", so it must not draw the empty state.
        case unavailable
        /// Nothing scheduled anywhere today — the map preview.
        case preview
        /// The busiest courts today.
        case list
    }

    var nearbySection: NearbySection {
        Self.nearbySection(
            hasLoaded: hasLoaded,
            hasHotCourts: !hotCourts.isEmpty,
            hasError: errorMessage != nil,
            isRecovering: isRecovering
        )
    }

    // MARK: - Dependencies

    private let courtService: CourtService
    private let gameService: GameService
    private let userProfileService: UserProfileService
    private let seasonGameService: SeasonGameService
    private var cancellables = Set<AnyCancellable>()

    /// Where distances are measured from, read from the same seam as every
    /// other distance in the app.
    ///
    /// Computed per read rather than captured at init: the anchor follows the
    /// device now, and a stored copy would freeze Home at Durham while the
    /// map's distances moved — two screens disagreeing about how far away the
    /// same court is.
    private var searchOrigin: CLLocationCoordinate2D { LocationService.homeLocation }

    private var currentUserId: String?

    init(
        authService: AuthService,
        courtService: CourtService,
        locationService: LocationService,
        gameService: GameService,
        userProfileService: UserProfileService,
        friendService: FriendService,
        squadService: SquadService,
        seasonGameService: SeasonGameService
    ) {
        self.courtService = courtService
        self.gameService = gameService
        self.userProfileService = userProfileService
        self.seasonGameService = seasonGameService

        authService.$currentUser
            .map(\.?.id)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] uid in
                self?.currentUserId = uid
                self?.rebuildNextRun()
            }
            .store(in: &cancellables)

        userProfileService.$currentProfile
            .map { $0?.userName ?? "there" }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in self?.greetingName = name }
            .store(in: &cancellables)

        // Its own subscription rather than folded into the greeting sink
        // above — stats are a separate concern. The `?? 0`/`nil` defaults
        // are load-bearing: they cover both a pre-`refreshStats` profile
        // (the Int fields are optional until that first write) and a
        // sign-out, which sets `currentProfile` to `nil` and must reset
        // this card to the same "no history" defaults rather than holding
        // onto the previous account's numbers for a frame.
        userProfileService.$currentProfile
            .map { profile in
                ProfileStats(
                    count: profile?.completedGameCount ?? 0,
                    streak: profile?.participationStreak ?? 0,
                    lastCompletedAt: profile?.lastCompletedAt
                )
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                self?.completedGameCount = stats.count
                self?.participationStreak = stats.streak
                self?.lastCompletedText = Self.lastCompletedText(for: stats.lastCompletedAt)
                self?.rebuildScoreboard()
            }
            .store(in: &cancellables)

        // The squad panel. One squad per person (app-enforced), so the first.
        // Read off the `seasonGames` listener the shell keeps pointed at your
        // squads for the whole session — no read of Home's own.
        squadService.$squads
            .map(\.first)
            .combineLatest(seasonGameService.$games, seasonGameService.$hasLoadedGames)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] squad, games, hasLoaded in
                guard let self else { return }
                let standing = hasLoaded
                    ? squad.map { SquadStanding(squad: $0, record: SeasonGame.record(for: $0.id, in: games)) }
                    : nil
                if standing != self.squadStanding {
                    self.squadStanding = standing
                    self.rebuildScoreboard()
                }
            }
            .store(in: &cancellables)

        friendService.$incomingRequests
            .map(\.count)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in self?.incomingRequestCount = count }
            .store(in: &cancellables)

        // A device fix moves the origin every distance here is measured from
        // — the hero's "1.2 mi" and the preview's dots and puck — so both
        // rebuild when one lands, as the map's list does. Until 2026-11-11
        // nothing here listened for it: they were rebuilt only by game and
        // court snapshots, which land before the first fix on a cold launch,
        // so the preview sat on downtown Durham until some run anywhere in
        // the dataset changed.
        locationService.$coordinate
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildNextRun()
                self?.rebuildNearestCourts()
            }
            .store(in: &cancellables)

        // The court dataset feeds both derived lists — the hot list needs the
        // court behind each id, and the next run needs its court resolved for
        // a name and a distance.
        courtService.$courts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildNextRun()
                self?.rebuildHotCourts()
                self?.rebuildNearestCourts()
            }
            .store(in: &cancellables)

        // Two listeners, not one: a run you host publicly arrives on both, so
        // the count below dedupes by id rather than concatenating.
        gameService.$queuedGames
            .combineLatest(gameService.$publicGames)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] queued, published in
                self?.rebuildNextRun(queued: queued)
                self?.rebuildHotCourts(queued: queued, published: published)
            }
            .store(in: &cancellables)

        // Loading, failure and recovery, republished as-is. None of the three
        // is derived here: the service is what knows, and a second opinion
        // would be a second thing to keep in step.
        gameService.$hasLoadedGames
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasLoaded in self?.hasLoaded = hasLoaded }
            .store(in: &cancellables)

        gameService.$errorMessage
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in self?.errorMessage = message }
            .store(in: &cancellables)

        gameService.$isRecovering
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecovering in self?.isRecovering = isRecovering }
            .store(in: &cancellables)

        // The one write in this file — see the type doc comment. Guarded on
        // a non-empty snapshot so a brand-new account with zero completions
        // never issues a write; `refreshStats` only has meaningful lazy-init
        // work to do once there's at least one completed run.
        gameService.$completedGames
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completedGames in
                guard let self else { return }
                let thisWeek = Game.completedThisWeek(in: completedGames)
                if thisWeek != self.runsThisWeek {
                    self.runsThisWeek = thisWeek
                    self.rebuildScoreboard()
                }
                guard let uid = self.gameService.currentUserId, !completedGames.isEmpty else {
                    return
                }
                Task {
                    try? await self.userProfileService.refreshStats(for: uid, using: completedGames)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Choosing the next run

    /// The soonest run you're on that is still worth showing.
    ///
    /// **Filtered by `isVisible(at:)`, which this used not to be — and the
    /// gap only mattered once the redesign made this run the screen's hero.**
    /// The queued listener selects by roster and time window, not by status
    /// (`GameService`), so a run the host has marked complete stays in
    /// `queuedGames` for the rest of `Game.visibilityGrace`. The Runs tab and
    /// the map's court card both drop it with `isVisible(at:)`. Home took
    /// `queuedGames.first` as it came, so for up to four hours after a run was
    /// recorded as over, the biggest thing on the app's first screen announced
    /// it as tonight's — with its spots left and a way in. Seen in the live app
    /// on 2026-09-22 with the map saying "No runs here today" about the same
    /// court.
    ///
    /// The listener delivers runs soonest-first, so the first visible one is
    /// the answer. `nonisolated static` so the rule can be tested without a
    /// service, like `rankHotCourts` below.
    nonisolated static func nextRun(from games: [Game], at now: Date = Date()) -> Game? {
        games.first { $0.isVisible(at: now) }
    }

    // MARK: - Ranking

    /// Today's busiest courts, most games first.
    ///
    /// `nonisolated static` and pure so the ranking can be tested without
    /// constructing a service or touching Firebase — the same shape
    /// `MapViewModel.gameCountsByFacility` and `Game.validate` already use.
    ///
    /// Ties break on `displayName`, not on dictionary order: a `[String: Int]`
    /// has no stable iteration order, so without a second key the list would
    /// reshuffle itself between rebuilds while showing identical numbers.
    /// Courts absent from `counts` have nothing scheduled and are dropped
    /// rather than rendered as a zero — a hot list of cold courts is noise.
    ///
    /// **`counts` is keyed by `facilityId`** and a facility appears at most once.
    /// Both matter: the counts come from `gameCountsByFacility`, and a park whose
    /// surfaces OSM split in three would otherwise fill the whole list with one
    /// destination repeated, each row showing the same tally. The first court of
    /// a facility wins, and `courts` arrives name-sorted, so that's the same
    /// representative every rebuild.
    nonisolated static func rankHotCourts(
        counts: [String: Int],
        courts: [Court],
        limit: Int
    ) -> [HotCourt] {
        guard limit > 0 else { return [] }

        var claimed = Set<String>()
        return courts
            .compactMap { court -> HotCourt? in
                guard let count = counts[court.facilityId], count > 0 else { return nil }
                guard claimed.insert(court.facilityId).inserted else { return nil }
                return HotCourt(court: court, gameCount: count)
            }
            .sorted { lhs, rhs in
                lhs.gameCount == rhs.gameCount
                    ? lhs.court.displayName < rhs.court.displayName
                    : lhs.gameCount > rhs.gameCount
            }
            .prefix(limit)
            .map { $0 }
    }

    /// "Tonight nearby" without the court the hero is already about.
    ///
    /// **The design critique's repeat (2026-10-09).** Home's hero said
    /// "Tonight 5:45 PM, Long Meadow Park #1", and the list under it led with
    /// Long Meadow Park #1, "1 today" — the same run, told twice. When the
    /// booked run is today, the court whose *only* run today is that one is
    /// dropped. A court with other runs today stays: those are news.
    ///
    /// - **Its count is what says "only".** `gameCount` is today's visible runs
    ///   at the court (`MapViewModel.gamesByFacility`), read from the same
    ///   `queuedGames` the hero is chosen from, with the same `isVisible(at:)`
    ///   rule — so a booked run that is today is always one of them, and a
    ///   count of 1 is the booked run alone.
    /// - **Not today, nothing dropped.** "Tonight nearby" is about today; a
    ///   hero reading "Tomorrow" repeats nothing in it.
    /// - **Never empty because of this.** If the booked court was the whole
    ///   list, the list stays as it was: an empty list switches the section to
    ///   its map preview, "Nothing on nearby yet", which would say the opposite
    ///   of what is true.
    ///
    /// `ranked` comes from `rankHotCourts` with room for one more than `limit`,
    /// so a dropped court is backfilled by the next busiest rather than leaving
    /// the list a row short. `nonisolated static` and pure, like the ranking.
    ///
    /// Matched by **facility**, not court: a hot row stands for every surface
    /// at one park, so a run booked on Long Meadow's court 2 is the row headed
    /// by court 1. `facilityIdsByCourtId` is `CourtService`'s; a court missing
    /// from it is its own facility, as everywhere else.
    nonisolated static func excludingBookedCourt(
        from ranked: [HotCourt],
        bookedRun: Game?,
        limit: Int,
        facilityIdsByCourtId: [String: String] = [:],
        now: Date = Date()
    ) -> [HotCourt] {
        guard limit > 0 else { return [] }
        guard let bookedRun,
              Calendar.current.isDate(bookedRun.scheduledTime, inSameDayAs: now)
        else {
            return Array(ranked.prefix(limit))
        }

        let bookedFacilityId = facilityIdsByCourtId[bookedRun.courtId] ?? bookedRun.courtId
        let others = ranked.filter { hot in
            !(hot.court.facilityId == bookedFacilityId && hot.gameCount == 1)
        }
        return Array((others.isEmpty ? ranked : others).prefix(limit))
    }

    /// The `limit` courts closest to `origin`, nearest first.
    ///
    /// The same shape and the same tie-break as `rankHotCourts`: ties break on
    /// `displayName`, so two courts at one distance — two hoops at the same
    /// park — can't swap places between rebuilds and move the preview's dots.
    /// Distances are `Distance.between`, the conversion every other distance
    /// in the app uses.
    nonisolated static func nearestCourts(
        to origin: CLLocationCoordinate2D,
        in courts: [Court],
        limit: Int
    ) -> [Court] {
        guard limit > 0 else { return [] }

        let measured = courts.map { court -> (court: Court, meters: CLLocationDistance) in
            (court, Distance.between(origin, court.coordinate))
        }
        let ordered = measured.sorted { lhs, rhs -> Bool in
            guard lhs.meters == rhs.meters else { return lhs.meters < rhs.meters }
            return lhs.court.displayName < rhs.court.displayName
        }
        return ordered.prefix(limit).map(\.court)
    }

    /// Which state "Tonight nearby" is in. `nonisolated static` and pure, like
    /// the ranking above, so the rule is tested without a service.
    ///
    /// **A failure outranks emptiness.** With the listener down, an empty
    /// list is an absence of an answer, and the preview — "Nothing on nearby
    /// yet" — would state one. A list already on screen stays: it is stale,
    /// not wrong, and the banner above says so.
    nonisolated static func nearbySection(
        hasLoaded: Bool,
        hasHotCourts: Bool,
        hasError: Bool,
        isRecovering: Bool
    ) -> NearbySection {
        if hasError || isRecovering {
            return hasHotCourts ? .list : .unavailable
        }
        guard hasLoaded else { return .loading }
        return hasHotCourts ? .list : .preview
    }

    // MARK: - The scoreboard

    /// The scoreboard's panels, in the order they take turns: this week, your
    /// squad, the streak, the total, the last run.
    ///
    /// **The run panels need a run.** With nothing completed, all four would be
    /// zeros and a dash, so they are left out — the rule the stats card had —
    /// and a squad's record is shown alone. With neither, nothing: Home hides
    /// the scoreboard. `nonisolated static` and pure, like the rankings.
    nonisolated static func scoreboardStats(
        completedCount: Int,
        runsThisWeek: Int,
        streak: Int,
        lastCompletedText: String,
        squadStanding: SquadStanding?
    ) -> [ScoreboardStat] {
        var stats: [ScoreboardStat] = []
        let hasRuns = completedCount > 0

        // **"Done this week", not "This week"** (design critique, 2026-10-09).
        // The count is completed runs only, so beside a hero reading "Hosting
        // tonight" a bare "This week · 0 runs" read as a contradiction. The
        // label says what is counted; the count is unchanged. "Finished this
        // week" was the first choice and is 140pt at the default size, where
        // the panel beside the calendar tile has 119pt for it.
        if hasRuns {
            stats.append(ScoreboardStat(
                kind: .thisWeek,
                label: "Done this week",
                value: "\(runsThisWeek)",
                unit: runsThisWeek == 1 ? "run" : "runs",
                spoken: runsThisWeek == 1 ? "1 run done this week" : "\(runsThisWeek) runs done this week",
                standing: nil
            ))
        }

        if let squadStanding {
            let record = squadStanding.record
            stats.append(ScoreboardStat(
                kind: .squad,
                label: squadStanding.squad.name,
                value: record.displayText,
                unit: nil,
                spoken: "\(squadStanding.squad.name), "
                    + SquadRecordLine.spokenRecord(wins: record.wins, losses: record.losses),
                standing: squadStanding
            ))
        }

        if hasRuns {
            stats.append(contentsOf: [
                ScoreboardStat(
                    kind: .streak,
                    label: "Streak",
                    value: "\(streak)",
                    unit: streak == 1 ? "wk" : "wks",
                    spoken: streak == 1 ? "1 week streak" : "\(streak) week streak",
                    standing: nil
                ),
                ScoreboardStat(
                    kind: .total,
                    label: "Total",
                    value: "\(completedCount)",
                    unit: completedCount == 1 ? "run" : "runs",
                    spoken: completedCount == 1 ? "1 run in all" : "\(completedCount) runs in all",
                    standing: nil
                ),
                ScoreboardStat(
                    kind: .lastRun,
                    label: "Last run",
                    value: lastCompletedText,
                    unit: nil,
                    spoken: "last run \(lastCompletedText.lowercased())",
                    standing: nil
                ),
            ])
        }

        return stats
    }

    private func rebuildScoreboard() {
        let stats = Self.scoreboardStats(
            completedCount: completedGameCount,
            runsThisWeek: runsThisWeek,
            streak: participationStreak,
            lastCompletedText: lastCompletedText,
            squadStanding: squadStanding
        )
        if stats != scoreboardStats {
            scoreboardStats = stats
        }
    }

    // MARK: - Formatting

    /// The stats card's "Last" column. `nonisolated static` and pure, same
    /// shape as `rankHotCourts` above, so it's testable without constructing
    /// a service.
    ///
    /// Uses `Calendar.current`, not the UTC/ISO-8601 calendar
    /// `Game.calculateStreak` buckets weeks with — that one has to agree
    /// across devices for a server-trusted count; this is displaying a single
    /// date to the person looking at their own phone, the same reasoning
    /// `Game.scheduledText(relativeTo:)` already uses `Calendar.current` for.
    ///
    /// Deliberately drops the year (`"MMMd"`) — a completion from last year
    /// still reads as e.g. "Aug 15". A simplification, not an oversight.
    nonisolated static func lastCompletedText(for date: Date?, relativeTo now: Date = Date()) -> String {
        guard let date else { return "—" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return lastCompletedDateFormatter.string(from: date)
    }

    private static let lastCompletedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    // MARK: - Rebuilds

    private func rebuildHotCourts(
        queued: [Game]? = nil,
        published: [Game]? = nil
    ) {
        let counts = MapViewModel.gameCountsByFacility(
            queued: queued ?? gameService.queuedGames,
            published: published ?? gameService.publicGames,
            facilityIdsByCourtId: courtService.facilityIdsByCourtId
        )

        // One spare, for the booked court to be dropped from without leaving
        // the list a row short. Reads `nextRun`, so every caller rebuilds that
        // first.
        let ranked = Self.rankHotCourts(
            counts: counts,
            courts: courtService.courts,
            limit: Self.hotCourtLimit + 1
        )
        hotCourts = Self.excludingBookedCourt(
            from: ranked,
            bookedRun: nextRun?.game,
            limit: Self.hotCourtLimit,
            facilityIdsByCourtId: courtService.facilityIdsByCourtId
        )
    }

    /// Rebuilt when the dataset loads and when a fix moves the origin — the
    /// only two things it reads — and published only when it changes, so an
    /// unchanged preview never hands the map behind it a new value to redraw.
    private func rebuildNearestCourts() {
        let origin = searchOrigin
        let nearest = Self.nearestCourts(
            to: origin,
            in: courtService.courts,
            limit: Self.previewCourtLimit
        )

        if nearest != nearestCourts {
            nearestCourts = nearest
        }
        if origin.latitude != previewOrigin.latitude || origin.longitude != previewOrigin.longitude {
            previewOrigin = origin
        }
    }

    /// `queuedGames` arrives sorted soonest-first and is already windowed to
    /// drop anything more than three hours past its start, so the first
    /// element is the run to show. A run that started an hour ago is still the
    /// one you're at, which is why this doesn't skip past it to the next one.
    private func rebuildNextRun(queued: [Game]? = nil) {
        guard let game = Self.nextRun(from: queued ?? gameService.queuedGames) else {
            nextRun = nil
            isHostingNextRun = false
            isWaitlistedOnNextRun = false
            return
        }

        let court = courtService.courts.first { $0.id == game.courtId }

        nextRun = LocalRunsViewModel.Listing(
            game: game,
            court: court,
            distanceMeters: court.map { Distance.between(searchOrigin, $0.coordinate) }
        )
        isHostingNextRun = game.isHost(currentUserId)
        isWaitlistedOnNextRun = game.hasWaitlisted(currentUserId)
    }
}
