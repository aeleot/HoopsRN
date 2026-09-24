import Combine
import CoreLocation
import Foundation
import os

fileprivate let logger = Logger(subsystem: "com.hoopsrn", category: "MatchmakingViewModel")

/// Drives queueing, searching, and the match that comes out the other end —
/// the queue sheet and `MatchmakingCard`'s states.
///
/// **The claim → create → mark-matched sequence used to live here, and it had
/// to stop.** Three writes in order across two collections is not the same
/// thing as one atomic write, and the difference was the duplicate-match bug:
/// two squads that picked each other each won a claim on the *other's* ticket —
/// two different documents, so nothing serialized them — and each went on to
/// create a match. Both squads then saw two.
///
/// What this view model does now is *wire*, not sequence. It hands
/// `MatchmakingService` a way to commit a candidate, and the commit itself is
/// one transaction in `SeasonGameService.commitMatch`. That is still a
/// cross-collection concern resolved in a view model, which is what
/// `ARCHITECTURE.md` reserves this layer for — but it is a dependency now
/// rather than an ordering, and the ordering that used to be able to come apart
/// no longer exists.
///
/// It also joins `CourtService` and `LocationService` in, which *is* the
/// ordinary kind of join — `MatchRules` needs a court lookup and a distance
/// anchor, and neither belongs to matchmaking.
@MainActor
final class MatchmakingViewModel: ObservableObject {

    // MARK: - Published state

    /// My squad's ticket, or `nil` when it isn't queued.
    @Published private(set) var ticket: MatchTicket?

    /// The match this squad is about to play, if there is one.
    @Published private(set) var nextGame: SeasonGame?

    /// The opponent's record, fetched once when a match appears. Decoration on
    /// the match card — a failed read shows 0–0 rather than taking the card
    /// down.
    @Published private(set) var opponentRecord: SeasonGame.Record?

    /// The opponent squad, for their crest on the match card.
    ///
    /// A separate read because the crest keys aren't on the game document —
    /// names are denormalized so history survives a disbanded squad, the icon
    /// and colour are not. `nil` until the read lands, and on failure: a crest
    /// is decoration on a match card, and a failed read of a decoration must
    /// never take the card down.
    @Published private(set) var opponentSquad: Squad?

    /// How many other squads are queued in the same pool right now, shown while searching.
    @Published private(set) var poolCount = 0

    /// How long this squad has been searching.
    @Published private(set) var elapsed: TimeInterval = 0

    /// Whether relaxation has begun to bite — the "Widening the search" state.
    ///
    /// Read from `MatchRules.relaxation(for:now:)` rather than from a timer that
    /// happens to agree with it, so the copy is true *because* the standards
    /// really are widening.
    @Published private(set) var isWidening = false

    /// Contention has pushed the claim loop into its quiet poll. A "still
    /// looking" state, never an error banner.
    @Published private(set) var isStillLooking = false

    @Published private(set) var errorMessage: String?

    @Published private(set) var isRecovering = false

    /// A match exists that this squad also has another live match against. The
    /// duplicate the create-then-mark window can produce; a leader cancels one.
    @Published private(set) var duplicateGames: [SeasonGame] = []

    /// Which screen the matchmaking card is showing.
    enum Phase: Equatable {
        /// No ticket worth showing, and no match — "Find a match".
        case idle
        /// Queued and looking.
        case searching
        /// The ticket is spent and the match itself hasn't arrived on the games
        /// listener yet. Milliseconds, normally — the game and the tickets are
        /// written in one commit, but they reach this client on two listeners.
        /// A state of its own so the card doesn't blink through "Find a match"
        /// on its way to showing the match.
        ///
        /// **Bounded by `settlingGrace`.** Nothing re-evaluates `phase` once the
        /// ticket itself stops changing, so without a timeout a match that never
        /// arrives — `matchedGameId` pointing at a document this client can't
        /// see, say a hand-edited or otherwise corrupted ticket — left this state
        /// permanent: a spinner with no control on it. Past the grace period
        /// `phase` reads as `.idle` instead, which is what lets the leader queue
        /// again rather than stare at a screen that will never change.
        case settling
        /// Matched.
        case matched(SeasonGame)
    }

    /// **A ticket is not a search.** This used to read any non-nil ticket as
    /// `.searching`, and nothing ever deletes a ticket once it is spent — it
    /// sits there `matched` until `expiresAt`, up to a day later. So the moment
    /// a match stopped being live, whether it was cancelled, confirmed, or
    /// simply aged past its window, the card fell back to a search that wasn't
    /// running, with a timer counting up from when the squad first queued. The
    /// only way out was "Cancel search", which cancelled nothing.
    ///
    /// A spent ticket now means one of two things, and they are told apart by
    /// whether the match it names has reached this client: still on its way, or
    /// already over.
    var phase: Phase {
        Self.phase(
            ticket: ticket,
            nextGame: nextGame,
            committedGame: committedGame,
            hasSettlingTimedOut: isSettlingTimedOut
        )
    }

    /// The card's state, as a pure function of the four things that decide it.
    ///
    /// `nonisolated static` for the reason `FriendsViewModel`'s helpers are:
    /// this is the decision most likely to break silently, it needs no Firebase,
    /// no main actor and no live service, and the failure it had was invisible
    /// from the code — a search that wasn't running, rendered because a ticket
    /// happened to be non-nil.
    ///
    /// - Parameters:
    ///   - ticket: this squad's ticket, spent or otherwise.
    ///   - nextGame: the soonest live match, if there is one.
    ///   - committedGame: the match a spent ticket names, once this client has
    ///     seen it. `nil` both while it is in flight and when there is no spent
    ///     ticket — the ticket is what tells those two apart.
    ///   - hasSettlingTimedOut: whether `settlingGrace` has elapsed without
    ///     `committedGame` resolving. Only consulted while it would otherwise
    ///     read `.settling` — see that case's own note for why it exists.
    nonisolated static func phase(
        ticket: MatchTicket?,
        nextGame: SeasonGame?,
        committedGame: SeasonGame?,
        hasSettlingTimedOut: Bool
    ) -> Phase {
        if let nextGame { return .matched(nextGame) }
        guard let ticket else { return .idle }
        if ticket.isSearching { return .searching }

        // The ticket is spent and no match is live. Either the match hasn't
        // arrived on the games listener yet, or it has and is over — played and
        // confirmed, cancelled, or aged past its window. Only the second reads
        // as `.idle` outright; reading both as "still searching" is the bug
        // this replaced.
        if committedGame != nil { return .idle }
        return hasSettlingTimedOut ? .idle : .settling
    }

    /// How long `.settling` waits for `committedGame` to resolve before
    /// `phase` gives up and reads as `.idle`.
    ///
    /// Generous next to the "milliseconds, normally" case this state exists
    /// for — two listeners on the same commit are not going to disagree by
    /// twenty seconds under any ordinary network condition. It exists only for
    /// the case that isn't ordinary: nothing re-evaluates `phase` once the
    /// ticket stops changing, so without a bound, a match that never arrives at
    /// all left `.settling` permanent.
    static let settlingGrace: TimeInterval = 20

    /// The match this squad's spent ticket was spent on, once the games
    /// listener has delivered it. `nil` while it is still in flight — and also
    /// when there is no spent ticket at all.
    @Published private(set) var committedGame: SeasonGame?

    /// Whether `settlingGrace` has elapsed while still waiting on the same
    /// `committedGame`. Reset the moment that wait is no longer live — the
    /// match arrives, the ticket changes, or a fresh wait begins for a
    /// different `matchedGameId`.
    @Published private(set) var isSettlingTimedOut = false

    /// Whether the leader may put this squad in the queue.
    ///
    /// **One live match at a time.** Queueing again before the current match is
    /// played, cancelled or aged out is what would put two matches in front of
    /// the same six people — the product-level form of the invariant the commit
    /// enforces on the server.
    var canQueue: Bool { isLeader && phase == .idle }

    // MARK: - Dependencies

    private let matchmakingService: MatchmakingService
    private let seasonGameService: SeasonGameService
    private let courtService: CourtService
    private let squadService: SquadService
    private let notificationService: NotificationService

    private var cancellables = Set<AnyCancellable>()
    private var tickTask: Task<Void, Never>?

    /// Counts down `settlingGrace` while waiting on a specific `matchedGameId`.
    /// Independent of `tickTask`, which only runs while searching — this has to
    /// keep going precisely when ticking has stopped, because a spent ticket is
    /// what starts the wait.
    private var settlingTask: Task<Void, Never>?

    /// Which `matchedGameId` `settlingTask` is timing, so a snapshot that
    /// re-confirms the same wait doesn't restart the clock, and a wait for a
    /// *different* match — a fresh queue-and-match cycle — does.
    private var settlingGameId: String?

    /// The squad this view model is currently speaking for.
    private var squad: Squad?

    /// Matches already handed to `NotificationService` this session, so a
    /// snapshot that fires for an unrelated reason — an opponent arriving,
    /// say — doesn't re-request authorization and re-add the same three
    /// requests on every tick. Scheduling *is* idempotent either way; this is
    /// just what keeps it from being called needlessly often.
    private var notifiedGameIds: Set<String> = []

    /// The bundled dataset keyed by ID, rebuilt when courts load. `MatchRules`
    /// wants a dictionary and `CourtService` publishes an array.
    private var courtsById: [String: Court] = [:]

    init(
        matchmakingService: MatchmakingService,
        seasonGameService: SeasonGameService,
        courtService: CourtService,
        squadService: SquadService,
        notificationService: NotificationService
    ) {
        self.matchmakingService = matchmakingService
        self.seasonGameService = seasonGameService
        self.courtService = courtService
        self.squadService = squadService
        self.notificationService = notificationService

        courtService.$courts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] courts in
                self?.courtsById = Dictionary(uniqueKeysWithValues: courts.map { ($0.id, $0) })
            }
            .store(in: &cancellables)

        matchmakingService.$myTicket
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ticket in
                self?.ticket = ticket
                self?.refreshSearchState()
            }
            .store(in: &cancellables)

        matchmakingService.$pool
            .receive(on: DispatchQueue.main)
            .sink { [weak self] pool in
                guard let self else { return }
                // Everybody else in the pool, not including us.
                self.poolCount = pool.filter { $0.squadId != self.squad?.id }.count
            }
            .store(in: &cancellables)

        matchmakingService.$isBackingOff
            .receive(on: DispatchQueue.main)
            .sink { [weak self] backingOff in
                self?.isStillLooking = backingOff
            }
            .store(in: &cancellables)

        // **The cross-collection wiring, and the whole of it.** The scan loop
        // stays in `MatchmakingService`, the commit stays in
        // `SeasonGameService`, and this is the one line that lets the first
        // reach the second without the two services referring to each other.
        //
        // Weak, because the service is held strongly here and a strong capture
        // would be a cycle. A commit that arrives after this view model is gone
        // reports `.failed`, which the loop backs off from — the correct answer
        // when there is nobody left to show a match to.
        matchmakingService.commitMatch = { [weak self] candidate, mine, courts, anchor in
            guard let self, let squad = self.squad else { return .failed }

            return await self.seasonGameService.commitMatch(
                candidate: candidate,
                mine: mine,
                // The *live* squad name, not the ticket's copy. `squadName` is
                // denormalized at queue time with no refresh path, and the
                // create rule pins it to `squads/{id}.name` — so a leader who
                // renames the squad mid-queue would have every commit refused.
                awaySquadName: squad.name,
                courts: courts,
                anchor: anchor
            )
        }

        seasonGameService.$games
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshGames()
            }
            .store(in: &cancellables)

        Publishers.Merge(
            matchmakingService.$errorMessage,
            seasonGameService.$errorMessage
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] message in
            // A nil from one service must not wipe the other's banner.
            if let message { self?.errorMessage = message }
        }
        .store(in: &cancellables)

        Publishers.CombineLatest(
            matchmakingService.$isRecovering,
            seasonGameService.$isRecovering
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] matchmaking, games in
            self?.isRecovering = matchmaking || games
        }
        .store(in: &cancellables)
    }

    deinit {
        tickTask?.cancel()
        settlingTask?.cancel()
    }

    // MARK: - Lifecycle

    /// Points this view model at a squad and starts the pool listener.
    ///
    /// The `seasonGames` listener is **not** started here. It watches every
    /// squad the user is on rather than just this one, which is the tab's
    /// business to know — squad detail's history reads off the same listener for a
    /// squad this view model isn't pointed at.
    func start(squad: Squad) {
        self.squad = squad

        matchmakingService.startSearching(
            squadId: squad.id,
            region: squad.region,
            format: squad.format,
            courts: courtsById,
            anchor: LocationService.homeLocation
        )

        startTicking()
        refreshGames()
    }

    func stop() {
        stopTicking()
    }

    /// A one-second tick, alive only while searching.
    ///
    /// Elapsed time and the widening state both move on their own without any
    /// snapshot arriving, and the searching state shows both. Cancelled the moment the
    /// search ends, so nothing is ticking behind a match card.
    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run { self?.refreshSearchState() }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Cancels the clock. Called by `refreshSearchState` the first tick after
    /// the ticket stops being a live search, so the timer's own loop is what
    /// ends it — a match landing doesn't have to remember to.

    private func refreshSearchState() {
        refreshCommittedGame()

        // **Only a live search has an elapsed time.** A spent ticket keeps its
        // `createdAt`, so reading `age` off one meant the "searching" card's
        // clock kept climbing long after the match had been played — which is
        // what made the stale card look like a search that would not stop.
        guard let ticket, ticket.isSearching else {
            elapsed = 0
            isWidening = false
            stopTicking()
            return
        }

        let now = Date()
        elapsed = ticket.age(at: now)
        // The copy says the standards are widening because they are.
        isWidening = MatchRules.relaxation(for: ticket, now: now) > 0
    }

    private func stopTicking() {
        tickTask?.cancel()
        tickTask = nil
    }

    private func refreshGames() {
        guard let squad else { return }

        nextGame = seasonGameService.nextGame(for: squad.id)
        duplicateGames = seasonGameService.duplicateGames(for: squad.id)
        refreshCommittedGame()

        if let nextGame {
            Task { await loadOpponent(for: nextGame, mySquadId: squad.id) }
            scheduleNotificationsIfNeeded(for: nextGame, mySquadId: squad.id)
        } else {
            opponentRecord = nil
            opponentSquad = nil
        }

        cancelNotificationsForCancelledMatches(squadId: squad.id)
    }

    /// Resolves the match a spent ticket points at, if this client has seen it.
    ///
    /// **The `matchedGameId` back-reference is what makes this answerable.**
    /// Both tickets carry the same one, written in the same commit as the match
    /// itself, so "has the match this squad was matched into arrived yet"
    /// is a lookup rather than a guess about timing.
    private func refreshCommittedGame() {
        guard let ticket, !ticket.isSearching, let gameId = ticket.matchedGameId else {
            committedGame = nil
            cancelSettlingTimeout()
            return
        }

        committedGame = seasonGameService.games.first { $0.id == gameId }

        if committedGame != nil {
            cancelSettlingTimeout()
        } else {
            scheduleSettlingTimeoutIfNeeded(for: gameId)
        }
    }

    /// Starts the `settlingGrace` countdown for `gameId`, unless it is already
    /// running for that same one.
    ///
    /// **Keyed to the game, not just "are we waiting."** `refreshCommittedGame`
    /// is called far more often than a wait actually begins — every tick while
    /// searching, every unrelated `seasonGames` snapshot — and re-arming the
    /// timer on each of those calls would mean it never fires. Keying it to
    /// `gameId` also means a second match, queued and won after the first
    /// settled or timed out, gets its own clock rather than inheriting one that
    /// was already most of the way to expiring.
    private func scheduleSettlingTimeoutIfNeeded(for gameId: String) {
        guard settlingGameId != gameId else { return }

        settlingTask?.cancel()
        settlingGameId = gameId
        isSettlingTimedOut = false

        settlingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.settlingGrace))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.isSettlingTimedOut = true }
        }
    }

    /// Ends any running wait. Called the moment it stops being live — the match
    /// arrives, the ticket changes, or the squad leaves the queue — so a timer
    /// from a wait that's already over can never fire late and flip
    /// `isSettlingTimedOut` back on for a phase that has moved past it.
    private func cancelSettlingTimeout() {
        settlingTask?.cancel()
        settlingTask = nil
        settlingGameId = nil
        isSettlingTimedOut = false
    }

    /// The opponent's record and crest, for the match card.
    ///
    /// Two reads rather than one because they come from different collections,
    /// and both are decoration: neither failing may take the card down. The
    /// squad read is the same one-off `squads` being world-readable exists to
    /// allow, and `GameDayViewModel` and `ResultViewModel` resolve an opponent
    /// the same way.
    private func loadOpponent(for game: SeasonGame, mySquadId: String) async {
        guard let opponentId = game.opponentSquadId(of: mySquadId) else { return }

        async let record = seasonGameService.fetchRecord(for: opponentId)
        async let squad = squadService.fetchSquad(id: opponentId)

        opponentRecord = await record
        opponentSquad = try? await squad
    }

    // MARK: - Notifications

    /// The permission moment: match found, not launch and not the game-day
    /// screen. It's the first instant a notification is worth anything and
    /// the first instant the user has just gained something — the only
    /// leverage a permission prompt ever has.
    ///
    /// Every decision about *what* to schedule is `SeasonGameNotifications`'s;
    /// this only resolves the two strings the pure function needs but has no
    /// way to look up itself, and hands the result to the service.
    private func scheduleNotificationsIfNeeded(for game: SeasonGame, mySquadId: String) {
        guard game.status == .scheduled, !notifiedGameIds.contains(game.id) else { return }
        notifiedGameIds.insert(game.id)

        let opponentName = game.opponentName(of: mySquadId) ?? "your opponent"
        let courtName = courtsById[game.courtId]?.displayName ?? "the court"

        Task { [notificationService] in
            let planned = SeasonGameNotifications.plan(
                for: game,
                opponentName: opponentName,
                courtName: courtName
            )
            await notificationService.apply(planned, for: game.id)
        }
    }

    /// A match this client scheduled notifications for may since have been
    /// called off by either leader. A cancelled match should remind nobody of
    /// anything, so its three identifiers are cleared the same session the
    /// cancellation is seen.
    private func cancelNotificationsForCancelledMatches(squadId: String) {
        for game in seasonGameService.games(for: squadId) where game.status == .cancelled {
            guard notifiedGameIds.remove(game.id) != nil else { continue }
            notificationService.cancelAll(for: game.id)
        }
    }

    // **The claim → create → mark sequence used to be finalized here**, in a
    // `finalize(claim:)` that wrote a game and then marked two tickets, with a
    // re-entrancy guard and a release path for a won claim that never became a
    // game. All of it was scaffolding around three writes that could come
    // apart. They are one transaction now — see `SeasonGameService.commitMatch`
    // — so there is no sequence left to hold together, no partial state to
    // release, and nothing for a second emission to run twice.

    // MARK: - Actions

    /// Puts the squad in the queue. The queue sheet's Save.
    ///
    /// `wins`/`losses` are **derived here**, from confirmed matches, rather than
    /// read off the squad — `squads` deliberately has no such field. The query
    /// returns nothing until Phase 6 confirms anything, which is correct: an
    /// unplayed squad reads as 0.5, not as a squad that loses everything.
    func queue(
        courtIds: [String],
        windowStart: Date,
        windowEnd: Date,
        expiresAt: Date
    ) async throws {
        guard let squad else { throw MatchTicketError.notSignedIn }

        // One live match at a time. Checked against the *match* rather than the
        // ticket, because the ticket is the wrong source of truth for this: it
        // is spent the instant a match is made and stays that way long after
        // the match is over, while the match itself is what the squad actually
        // has on.
        guard nextGame == nil else { throw MatchTicketError.matchAlreadyScheduled }

        let record = seasonGameService.record(for: squad.id)

        try await matchmakingService.queue(
            squad,
            courtIds: courtIds,
            windowStart: windowStart,
            windowEnd: windowEnd,
            expiresAt: expiresAt,
            wins: record.wins,
            losses: record.losses
        )

        matchmakingService.startSearching(
            squadId: squad.id,
            region: squad.region,
            format: squad.format,
            courts: courtsById,
            anchor: LocationService.homeLocation
        )
        startTicking()
    }

    /// Leaves the queue. The searching state's cancel.
    func leaveQueue() async {
        guard let squad else { return }
        do {
            try await matchmakingService.leaveQueue(squadId: squad.id)
        } catch {
            logger.error("Couldn't leave the queue: \(String(describing: error), privacy: .public)")
        }
    }

    /// Calls a match off. The match card's leader control.
    func cancel(game: SeasonGame) async {
        guard let squad, let uid = matchmakingService.currentUserId,
              game.canCancel(uid: uid) else { return }

        do {
            try await seasonGameService.cancelGame(id: game.id, bySquadId: squad.id)
        } catch {
            logger.error("Couldn't cancel the match: \(String(describing: error), privacy: .public)")
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    func retry() {
        matchmakingService.retry()
        seasonGameService.retry()
    }

    // MARK: - The queue sheet's defaults

    /// The three courts nearest the anchor, which is what the queue sheet
    /// pre-selects so the common case is two taps.
    func nearestCourtIds(limit: Int = 3) -> [String] {
        Array(sortedByDistance(courtService.courts.map(\.id)).prefix(limit))
    }

    /// Any set of court IDs, nearest-first. The general form `nearestCourtIds`
    /// truncates to — pulled out so a court found through search still lands
    /// in the same preference order a court found by proximity would, since
    /// `MatchRules.court(forHome:guest:...)` reads that order to decide which
    /// mutually-acceptable court a match actually lands at.
    func sortedByDistance(_ courtIds: some Sequence<String>) -> [String] {
        let anchor = LocationService.homeLocation
        return courtIds
            .compactMap { id in courtsById[id].map { (id, Distance.between(anchor, $0.coordinate)) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Courts matching a typed query, name ahead of city — same ranking
    /// `MapTab`'s search uses. The queue sheet only offers the nearest few by
    /// default; this is the escape hatch to the other 200-odd, so a squad that
    /// wants a specific court across town isn't limited to what's nearby.
    func searchCourts(matching query: String) -> [Court] {
        CourtSearch.matches(courtService.courts, query: query)
    }

    func court(id: String) -> Court? { courtsById[id] }

    func courtName(id: String) -> String {
        courtsById[id]?.displayName ?? "Unknown court"
    }

    /// Whether the signed-in user leads the squad, and so may queue or cancel.
    var isLeader: Bool {
        guard let squad, let uid = matchmakingService.currentUserId else { return false }
        return squad.leaderId == uid
    }

    var myRecord: SeasonGame.Record {
        guard let squad else { return SeasonGame.Record(wins: 0, losses: 0) }
        return seasonGameService.record(for: squad.id)
    }

    var myForm: [SeasonGame.Outcome] {
        guard let squad else { return [] }
        return seasonGameService.form(for: squad.id)
    }
}

// MARK: - Time windows

/// The queue sheet's time chips. The sheet offers three, and the common case is
/// tapping one.
///
/// Pure and `now`-injectable so the arithmetic is testable — the windows are
/// wall-clock ranges relative to "tonight" and "tomorrow evening", which is
/// exactly the sort of thing that quietly breaks across a day boundary.
nonisolated enum QueueWindow: String, CaseIterable, Identifiable, Sendable {
    case tonight
    case tomorrowEvening
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tonight:         return "Tonight"
        case .tomorrowEvening: return "Tomorrow evening"
        case .custom:          return "Custom"
        }
    }

    /// The window this chip means, or `nil` for `.custom`, which the sheet
    /// collects by hand.
    ///
    /// "Tonight" runs from now (or 5pm, whichever is later) to 10pm — and
    /// returns `nil` once there is no longer room for a game before then, so the
    /// chip disables itself rather than offering a window the rules would
    /// refuse.
    func window(
        format: SquadFormat,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (start: Date, end: Date)? {
        switch self {
        case .custom:
            return nil

        case .tonight:
            guard let fivePM = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now),
                  let tenPM = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: now)
            else { return nil }

            let start = max(now, fivePM)
            guard tenPM.timeIntervalSince(start) >= format.duration else { return nil }
            return (start, tenPM)

        case .tomorrowEvening:
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
                  let start = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: tomorrow),
                  let end = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: tomorrow)
            else { return nil }
            return (start, end)
        }
    }

    /// How long a ticket for this window should live: until the window closes,
    /// clamped into `MatchTicket.lifetimeRange`.
    ///
    /// Clamped rather than validated-and-rejected, because the user never chose
    /// this number — they chose a window, and the expiry is derived from it. The
    /// bound they *did* choose is checked by `MatchTicket.validate`.
    static func expiry(
        forWindowEnd end: Date,
        now: Date = Date()
    ) -> Date {
        let lifetime = min(
            max(end.timeIntervalSince(now), MatchTicket.lifetimeRange.lowerBound),
            MatchTicket.lifetimeRange.upperBound
        )
        return now.addingTimeInterval(lifetime)
    }
}
