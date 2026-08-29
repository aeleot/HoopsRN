import Combine
import CoreLocation
import Foundation
import os

fileprivate let logger = Logger(subsystem: "com.hoopsrn", category: "MatchmakingViewModel")

/// Drives queueing, searching, and the match that comes out the other end —
/// screens 4, 5 and 6 of `context/plans/SEASONS.md` §5.
///
/// **This is where the claim → create → mark-matched sequence lives, and that
/// is a deliberate departure worth naming.** `ARCHITECTURE.md` puts
/// cross-collection *joins* in view models; this is a cross-collection write
/// *sequence*, which is more than a join. It lives here anyway because the
/// alternative is worse: `MatchmakingService` owns `matchTickets` and
/// `SeasonGameService` owns `seasonGames`, services in this app have no
/// references to each other, and nothing about this sequence needs them to.
/// One object that holds both and calls them in order costs a house-rule
/// asterisk. One service reaching into another would cost the house rule.
///
/// It also joins `CourtService` and `LocationService` in, which *is* the
/// ordinary kind of join — `MatchRules` needs a court lookup and a distance
/// anchor, and neither belongs to matchmaking.
@MainActor
final class MatchmakingViewModel: ObservableObject {

    // MARK: - Published state

    /// My squad's ticket, or `nil` when it isn't queued.
    @Published private(set) var ticket: MatchTicket?

    /// The match this squad is about to play, if there is one. Screen 6.
    @Published private(set) var nextGame: SeasonGame?

    /// The opponent's record, fetched once when a match appears. Decoration on
    /// the match card — a failed read shows 0–0 rather than taking the card
    /// down.
    @Published private(set) var opponentRecord: SeasonGame.Record?

    /// How many other squads are queued in the same pool right now. Screen 5.
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
        /// No ticket, no match — "Find a match".
        case idle
        /// Queued and looking. Screen 5.
        case searching
        /// Matched. Screen 6.
        case matched(SeasonGame)
    }

    var phase: Phase {
        if let nextGame { return .matched(nextGame) }
        return ticket == nil ? .idle : .searching
    }

    // MARK: - Dependencies

    private let matchmakingService: MatchmakingService
    private let seasonGameService: SeasonGameService
    private let courtService: CourtService
    private let squadService: SquadService

    private var cancellables = Set<AnyCancellable>()
    private var tickTask: Task<Void, Never>?

    /// The squad this view model is currently speaking for.
    private var squad: Squad?

    /// Guards the claim → create → mark sequence so a second `wonClaim` emission
    /// can't run it twice for the same claim.
    private var isFinalizingClaim = false

    /// The bundled dataset keyed by ID, rebuilt when courts load. `MatchRules`
    /// wants a dictionary and `CourtService` publishes an array.
    private var courtsById: [String: Court] = [:]

    init(
        matchmakingService: MatchmakingService,
        seasonGameService: SeasonGameService,
        courtService: CourtService,
        squadService: SquadService
    ) {
        self.matchmakingService = matchmakingService
        self.seasonGameService = seasonGameService
        self.courtService = courtService
        self.squadService = squadService

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

        // The claim → create → mark sequence starts here.
        matchmakingService.$wonClaim
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] candidate in
                Task { await self?.finalize(claim: candidate) }
            }
            .store(in: &cancellables)

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
    }

    // MARK: - Lifecycle

    /// Points this view model at a squad and starts both listeners.
    func start(squad: Squad) {
        self.squad = squad

        seasonGameService.observe(squadIds: [squad.id])
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
        tickTask?.cancel()
        tickTask = nil
    }

    /// A one-second tick, alive only while searching.
    ///
    /// Elapsed time and the widening state both move on their own without any
    /// snapshot arriving, and screen 5 shows both. Cancelled the moment the
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

    private func refreshSearchState() {
        guard let ticket else {
            elapsed = 0
            isWidening = false
            return
        }

        let now = Date()
        elapsed = ticket.age(at: now)
        // The copy says the standards are widening because they are.
        isWidening = MatchRules.relaxation(for: ticket, now: now) > 0
    }

    private func refreshGames() {
        guard let squad else { return }

        nextGame = seasonGameService.nextGame(for: squad.id)
        duplicateGames = seasonGameService.duplicateGames(for: squad.id)

        if let nextGame {
            // The window-closing write. If a game exists for my squad and my own
            // ticket is still `claimed`, the squad that made the match may have
            // died before marking it — so I mark my own, which I am always
            // allowed to do. Costs one refused write in the common case, where
            // the away leader already did it.
            if let ticket, ticket.status == .claimed {
                Task { [matchmakingService] in
                    await matchmakingService.markMatched(squadId: squad.id, gameId: nextGame.id)
                }
            }

            Task { await loadOpponentRecord(for: nextGame, mySquadId: squad.id) }
        } else {
            opponentRecord = nil
        }
    }

    private func loadOpponentRecord(for game: SeasonGame, mySquadId: String) async {
        guard let opponentId = game.opponentSquadId(of: mySquadId) else { return }
        opponentRecord = await seasonGameService.fetchRecord(for: opponentId)
    }

    // MARK: - The claim → create → mark sequence

    /// Turns a won claim into a scheduled match, then takes both tickets out of
    /// the pool.
    ///
    /// The order is load-bearing. The game is written **first**, because it is
    /// the durable thing and the tickets are bookkeeping: if this client dies
    /// after the game and before the tickets, the game still exists and both
    /// squads' own clients close their own tickets off their `seasonGames`
    /// listeners. Marking first and dying would take two squads out of the pool
    /// with nothing to show them.
    private func finalize(claim candidate: MatchCandidate) async {
        guard let squad, let awayTicket = ticket, !isFinalizingClaim else { return }
        isFinalizingClaim = true
        defer { isFinalizingClaim = false }

        let homeTicket = candidate.ticket

        do {
            let gameId = try await seasonGameService.createGame(
                homeTicket: homeTicket,
                awayTicket: awayTicket,
                homeSquadName: homeTicket.squadName,
                awaySquadName: squad.name,
                courtId: candidate.courtId,
                scheduledTime: candidate.scheduledTime
            )

            // Bookkeeping, and deliberately not awaited as a unit: each write is
            // independently useful and independently recoverable.
            await matchmakingService.markMatched(squadId: homeTicket.squadId, gameId: gameId)
            await matchmakingService.markMatched(squadId: squad.id, gameId: gameId)

            logger.notice("Finalized a match against \(homeTicket.squadId, privacy: .public)")
        } catch {
            // The claim was won and the game was refused — the state moved
            // underneath us, most likely a stale claim somebody else recovered.
            // The ticket stays in the pool and the search continues; the
            // service's own error reporting decides whether this is worth
            // saying.
            logger.error(
                "Won a claim but couldn't create the match: \(String(describing: error), privacy: .public)"
            )
        }
    }

    // MARK: - Actions

    /// Puts the squad in the queue. Screen 4's Save.
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

    /// Leaves the queue. Screen 5's cancel.
    func leaveQueue() async {
        guard let squad else { return }
        do {
            try await matchmakingService.leaveQueue(squadId: squad.id)
        } catch {
            logger.error("Couldn't leave the queue: \(String(describing: error), privacy: .public)")
        }
    }

    /// Calls a match off. Screen 6's leader control.
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

    // MARK: - Screen 4's defaults

    /// The three courts nearest the anchor, which is what the queue sheet
    /// pre-selects so the common case is two taps.
    func nearestCourtIds(limit: Int = 3) -> [String] {
        let anchor = LocationService.homeLocation
        return courtService.courts
            .map { ($0.id, Distance.between(anchor, $0.coordinate)) }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
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

/// The queue sheet's time chips. Screen 4 offers three, and the common case is
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
