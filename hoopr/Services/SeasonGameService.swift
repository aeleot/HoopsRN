import Combine
import CoreLocation
import FirebaseFirestore
import Foundation
import os

fileprivate let logger = Logger(subsystem: "com.hoopsrn", category: "SeasonGameService")

/// Owns the `seasonGames` collection — scheduled squad-vs-squad matches, and
/// the documents a squad's record is derived from.
///
/// **Why this is its own service rather than part of `SquadService`.**
/// `SquadService` already owns two collections, and the justification given
/// there is that a `squadInvite` "has no independent existence": it is created
/// against a squad, consumed by a write to that same squad, and deleted in the
/// same breath. A `seasonGame` is the opposite on every count — it outlives both
/// tickets, it has its own listener with its own query shape, it is the thing a
/// record is computed from, and it survives into Phase 6 long after the squads
/// that made it may have disbanded. One service per collection is the house
/// rule, and this collection earns it.
///
/// **The commit that makes a match *is* here, and it writes `matchTickets`.**
/// A view model used to sequence claim → create → mark-matched across the two
/// services, which was a write *sequence* in a place the house rules reserve
/// for joins — and, worse, was not atomic, so two squads that picked each other
/// both committed and both squads got two live matches. Making it one
/// transaction means one object has to write both collections; `commitMatch`
/// explains why that object is this one.
@MainActor
final class SeasonGameService: ObservableObject {
    /// Every match either of the observed squads is in, soonest first.
    ///
    /// Not windowed to the future: the same listener feeds game day *and* the
    /// history the record is derived from, and a query that dropped finished
    /// matches would make a squad's record silently reset itself.
    @Published private(set) var games: [SeasonGame] = []

    @Published private(set) var errorMessage: String?

    @Published private(set) var isRecovering = false

    /// True once the listener has delivered a snapshot successfully, so "no
    /// matches yet" can be told from "Firestore hasn't answered".
    @Published private(set) var hasLoadedGames = false

    private enum Collection {
        static let seasonGames = "seasonGames"
        /// Not this service's collection. `commitMatch` writes it because the
        /// commit is atomic across both — see that method's note.
        static let matchTickets = "matchTickets"
    }

    private enum ListenerKey {
        static let games = "seasonGames"
    }

    /// Field names in one place so the write maps can't drift from
    /// `SeasonGame`'s coding keys, matching the other five services.
    private enum Field {
        static let id = "id"
        static let format = "format"
        static let region = "region"
        static let homeSquadId = "homeSquadId"
        static let awaySquadId = "awaySquadId"
        static let squadIds = "squadIds"
        static let homeLeaderId = "homeLeaderId"
        static let awayLeaderId = "awayLeaderId"
        static let homeSquadName = "homeSquadName"
        static let awaySquadName = "awaySquadName"
        static let courtId = "courtId"
        static let scheduledTime = "scheduledTime"
        static let status = "status"
        static let arrivedPlayerIds = "arrivedPlayerIds"
        static let cancelledBySquadId = "cancelledBySquadId"
        static let homeReport = "homeReport"
        static let awayReport = "awayReport"
        static let homeScore = "homeScore"
        static let awayScore = "awayScore"
        static let result = "result"
        static let createdBy = "createdBy"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let confirmedAt = "confirmedAt"
    }

    /// Carried out of the report transaction as a raw string, because
    /// `runTransaction` hands back `Any?` — `GameService.mutateRoster`'s idiom.
    private enum ReportTransaction: String {
        case missing
        case notLeader
        case settled
        case notPlayed
        case unknownWinner
        case awaitingReport
        case disputed
        case confirmed

        init(_ outcome: SeasonGame.ReportOutcome) {
            switch outcome {
            case .awaitingReport: self = .awaitingReport
            case .disputed:       self = .disputed
            case .confirmed:      self = .confirmed
            }
        }
    }

    private enum Limit {
        static let games = 200

        /// Firestore's ceiling on `array-contains-any`. A person on more squads
        /// than this sees matches for the first ten — which is a limit worth
        /// naming rather than a silent truncation, because the eleventh squad's
        /// matches would simply never appear.
        static let observedSquads = 10
    }

    private lazy var database = Firestore.firestore()

    private var gamesListener: ListenerRegistration?
    private var observedUID: String?
    private var observedSquadIds: [String] = []
    private var cancellables = Set<AnyCancellable>()

    private let supervisor = ListenerSupervisor(subject: "seasonGames")

    private var errorIsFromLoad = false

    var currentUserId: String? { observedUID }

    init(authService: AuthService) {
        authService.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                self?.handleAuthChange(to: user)
            }
            .store(in: &cancellables)

        supervisor.onRetry = { [weak self] in
            self?.attachListener()
        }
    }

    deinit {
        gamesListener?.remove()
    }

    // MARK: - Session wiring

    private func handleAuthChange(to user: AuthenticatedUser?) {
        guard let user else {
            stopObserving()
            observedUID = nil
            return
        }

        guard user.id != observedUID else { return }

        stopObserving()
        observedUID = user.id
    }

    /// Watches every match these squads are in.
    ///
    /// Driven by a view model rather than by a `SquadService` subscription,
    /// because knowing which squads are mine is `squads`' business and services
    /// here don't depend on each other.
    func observe(squadIds: [String]) {
        guard observedUID != nil else { return }

        let wanted = Array(squadIds.prefix(Limit.observedSquads))
        guard wanted != observedSquadIds else { return }

        if wanted.isEmpty {
            stopObserving()
            return
        }

        observedSquadIds = wanted
        attachListener()
    }

    func stopObserving() {
        supervisor.cancel()
        gamesListener?.remove()
        gamesListener = nil
        observedSquadIds = []
        games = []
        hasLoadedGames = false
        isRecovering = false
        clearError()
    }

    func retry() {
        supervisor.retryNow()
    }

    /// The one listener. `array-contains-any` rather than `array-contains` so a
    /// person on two squads gets both without two listeners — the composite
    /// index `(squadIds CONTAINS, scheduledTime ASC)` serves either form.
    private func attachListener() {
        guard !observedSquadIds.isEmpty else { return }

        gamesListener?.remove()

        gamesListener = database
            .collection(Collection.seasonGames)
            .whereField(Field.squadIds, arrayContainsAny: observedSquadIds)
            .order(by: Field.scheduledTime)
            .limit(to: Limit.games)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handle(snapshot, error: error)
                }
            }
    }

    private func handle(_ snapshot: QuerySnapshot?, error: Error?) {
        if let error {
            supervisor.recordFailure(for: ListenerKey.games)
            isRecovering = true
            report(Self.mapped(error), whileDoing: "loading your matches", context: .load)
            return
        }

        supervisor.recordSuccess(for: ListenerKey.games)
        isRecovering = supervisor.isRecovering

        games = Self.decoded(snapshot)
        hasLoadedGames = true

        if errorIsFromLoad, !supervisor.isRecovering {
            clearError()
        }
    }

    /// Decodes per document rather than per snapshot, matching
    /// `GameService.decoded`. One drifted row must not blank game day.
    private static func decoded(_ snapshot: QuerySnapshot?) -> [SeasonGame] {
        guard let snapshot else { return [] }

        return snapshot.documents.compactMap { document in
            do {
                return try document.data(as: SeasonGame.self)
            } catch {
                logger.error(
                    "Skipping season game \(document.documentID, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }
    }

    // MARK: - Reads

    /// Every match this squad is in, soonest first.
    func games(for squadId: String) -> [SeasonGame] {
        games.filter { $0.includes(squadId: squadId) }
    }

    /// The next scheduled match for a squad, if there is one.
    ///
    /// **The earliest-created one wins when there are two.** The window between
    /// a game being written and both tickets being marked `matched` can produce
    /// a duplicate — a third squad re-claims a stale ticket whose game already
    /// exists. Rules can't query, so this isn't prevented server-side; it is
    /// rendered deterministically and a leader cancels the other.
    func nextGame(for squadId: String, at now: Date = Date()) -> SeasonGame? {
        games
            .filter { $0.includes(squadId: squadId) && $0.isUpcoming(at: now) }
            .min { lhs, rhs in
                if lhs.scheduledTime != rhs.scheduledTime {
                    return lhs.scheduledTime < rhs.scheduledTime
                }
                // Same tip-off: the earliest-created one is the real match.
                // `createdAt` is nil for a write whose server timestamp hasn't
                // resolved, which means "seconds ago" — the newer of the two.
                return (lhs.createdAt ?? .distantFuture) < (rhs.createdAt ?? .distantFuture)
            }
    }

    /// Whether a squad has more than one live match — the duplicate the window
    /// above can produce. Worth surfacing to a leader, and worth logging: if it
    /// happens more than rarely, the jitter or the stale window is wrong.
    func duplicateGames(for squadId: String, at now: Date = Date()) -> [SeasonGame] {
        let live = games.filter { $0.includes(squadId: squadId) && $0.isUpcoming(at: now) }
        guard live.count > 1, let keeper = nextGame(for: squadId, at: now) else { return [] }

        logger.notice(
            "Squad \(squadId, privacy: .public) has \(live.count, privacy: .public) live matches"
        )
        return live.filter { $0.id != keeper.id }
    }

    /// A squad's record from the matches this listener already holds.
    ///
    /// Only correct for a squad being observed. An opponent's record needs
    /// `fetchRecord(for:)`, which is a query rather than a filter.
    func record(for squadId: String) -> SeasonGame.Record {
        SeasonGame.record(for: squadId, in: games)
    }

    func form(for squadId: String, limit: Int = 5) -> [SeasonGame.Outcome] {
        SeasonGame.form(for: squadId, in: games, limit: limit)
    }

    /// A one-off read of **another** squad's record.
    ///
    /// The plan's §1.1 cost, paid deliberately: a record is derived rather than
    /// stored, so showing an opponent's takes one query. Legal because
    /// `seasonGames` is readable by any signed-in account.
    ///
    /// Returns an unplayed record rather than throwing when the query fails —
    /// an opponent's record is decoration on a match card, and a failed read of
    /// it must not take down the card.
    func fetchRecord(for squadId: String) async -> SeasonGame.Record {
        guard observedUID != nil else { return SeasonGame.Record(wins: 0, losses: 0) }

        do {
            let snapshot = try await database
                .collection(Collection.seasonGames)
                .whereField(Field.squadIds, arrayContains: squadId)
                .whereField(Field.status, isEqualTo: SeasonGame.Status.confirmed.rawValue)
                .limit(to: Limit.games)
                .getDocuments()

            return SeasonGame.record(for: squadId, in: Self.decoded(snapshot))
        } catch {
            logger.error(
                "Couldn't read squad \(squadId, privacy: .public)'s record: \(error.localizedDescription, privacy: .public)"
            )
            return SeasonGame.Record(wins: 0, losses: 0)
        }
    }

    // MARK: - Writes

    /// **The one contested write in the feature**: spends both squads' tickets
    /// and creates the match, in a single transaction.
    ///
    /// ## Why this is one commit and not three
    ///
    /// It used to be three: claim the opponent's ticket, create the game, then
    /// mark both tickets matched. Each step was sound on its own, and the whole
    /// was not. The claim's guarantee was Firestore serializing contested
    /// writes to a **single document** — true, and the wrong guarantee for the
    /// problem. Two squads that pick each other claim two *different* tickets,
    /// so nothing serializes them: both claims win, both clients create a game,
    /// and both squads end up looking at two live matches against each other.
    /// In a pool with two squads in it, that is not an edge case — it is what
    /// normally happens, and it is the bug this method exists to kill.
    ///
    /// Reading **both** tickets and writing both tickets and the game together
    /// is the fix, and it is the same guarantee as before applied to the pair
    /// that actually needs it. Two mutual commits now share a read set, so
    /// Firestore's optimistic concurrency does exactly what it always did:
    /// exactly one lands, and the other is retried onto a ticket that is
    /// already spent, where the guard below turns it into a quiet `.lost`.
    ///
    /// Three windows close with it, not one:
    /// - two squads matching each other twice, which is the reported bug;
    /// - a claimer dying between the claim and the game, which the old design
    ///   recovered from with a ninety-second stale-claim window that no longer
    ///   needs to exist;
    /// - a claimer dying between the game and the tickets, which used to leave
    ///   a spent ticket looking claimable and let a third squad re-match a
    ///   squad that already had a game.
    ///
    /// ## Why it lives here
    ///
    /// It doesn't belong to either collection's service, and this is the less
    /// bad of two homes rather than a clean fit. `SeasonGameService` owns
    /// `seasonGames`, `MatchmakingService` owns `matchTickets`, and the house
    /// rule is one service per collection. An atomic write across both has to
    /// break that somewhere. It breaks it here because the game is the durable
    /// thing — the document a record is derived from, the one that outlives both
    /// tickets — and the ticket writes are bookkeeping that must not come apart
    /// from it. The four ticket field names it needs come from
    /// `MatchTicket.Field`, so there is still exactly one copy of them.
    ///
    /// ## Re-ranking inside the transaction is not redundant
    ///
    /// The candidate was chosen against a pool snapshot that is at best
    /// milliseconds old. A ticket's pool fields are immutable, so most of
    /// `MatchRules` could not have changed — but a ticket can be deleted and
    /// re-created at the same document ID, which is exactly what a leader who
    /// leaves the queue and re-queues with a different roster, window or court
    /// list does. Re-ranking against the version this transaction itself read is
    /// the only view guaranteed current at the moment of the write, and the
    /// court and tip-off written below come from *that* ranking rather than the
    /// stale one.
    ///
    /// - Returns: a `ClaimOutcome` rather than throwing, because losing is the
    ///   ordinary experience of a healthy pool and the caller's `ClaimPolicy`
    ///   loop is written in these terms. Only `.failed` ever reaches the user.
    func commitMatch(
        candidate: MatchCandidate,
        mine: MatchTicket,
        awaySquadName: String,
        courts: [String: Court],
        anchor: CLLocationCoordinate2D
    ) async -> ClaimOutcome {
        guard let uid = observedUID else { return .failed }
        guard mine.leaderId == uid else { return .refused }

        let tickets = database.collection(Collection.matchTickets)
        let homeReference = tickets.document(candidate.ticket.squadId)
        let awayReference = tickets.document(mine.squadId)
        // Generated outside the closure: a transaction body may be retried, and
        // an ID minted inside would differ on every attempt.
        let gameReference = database.collection(Collection.seasonGames).document()
        let gameId = gameReference.documentID

        do {
            let outcome = try await database.runTransaction { transaction, errorPointer in
                // Every read before every write — Firestore requires it, and
                // reading both tickets is what puts both in the read set and so
                // makes two mutual commits contend.
                let homeSnapshot: DocumentSnapshot
                let awaySnapshot: DocumentSnapshot
                do {
                    homeSnapshot = try transaction.getDocument(homeReference)
                    awaySnapshot = try transaction.getDocument(awayReference)
                } catch let fetchError as NSError {
                    // Setting the pointer makes `runTransaction` throw, so the
                    // value returned here is never inspected.
                    errorPointer?.pointee = fetchError
                    return nil
                }

                guard homeSnapshot.exists, awaySnapshot.exists,
                      let home = try? homeSnapshot.data(as: MatchTicket.self),
                      let away = try? awaySnapshot.data(as: MatchTicket.self)
                else {
                    return ClaimOutcome.missing.rawValue
                }

                // Our own ticket has to still be ours and still be unspent. The
                // second half is the one the whole transaction turns on: on a
                // retry after losing a mutual race, this is what has changed.
                guard away.leaderId == uid else { return ClaimOutcome.refused.rawValue }
                guard away.isClaimable(at: Date()) else { return ClaimOutcome.lost.rawValue }

                // Same pure function as the scan, against the documents this
                // write will actually land on.
                guard let fresh = MatchRules.candidate(
                    for: away,
                    against: home,
                    courts: courts,
                    anchor: anchor,
                    now: Date()
                ) else {
                    return ClaimOutcome.lost.rawValue
                }

                if SeasonGame.validate(
                    homeTicket: home,
                    awayTicket: away,
                    courtId: fresh.courtId,
                    scheduledTime: fresh.scheduledTime
                ) != nil {
                    return ClaimOutcome.lost.rawValue
                }

                transaction.setData(
                    Self.newMatchFields(
                        id: gameId,
                        home: home,
                        away: away,
                        awaySquadName: awaySquadName,
                        courtId: fresh.courtId,
                        scheduledTime: fresh.scheduledTime,
                        createdBy: uid
                    ),
                    forDocument: gameReference
                )

                // The home ticket, taken out of the pool by us.
                transaction.updateData(
                    [
                        MatchTicket.Field.status: MatchTicket.Status.matched.rawValue,
                        MatchTicket.Field.claimedBy: away.squadId,
                        // Pinned, not requested — the rules assert
                        // `claimedAt == request.time` rather than trusting it.
                        MatchTicket.Field.claimedAt: FieldValue.serverTimestamp(),
                        MatchTicket.Field.matchedGameId: gameId,
                    ],
                    forDocument: homeReference
                )

                // Our own, spent in the same breath. Without this a squad could
                // take an opponent out of the pool while staying in it, and
                // match somebody else a moment later.
                transaction.updateData(
                    [
                        MatchTicket.Field.status: MatchTicket.Status.matched.rawValue,
                        MatchTicket.Field.matchedGameId: gameId,
                    ],
                    forDocument: awayReference
                )

                return ClaimOutcome.claimed.rawValue
            }

            let decided = ClaimOutcome(rawValue: outcome as? String ?? "") ?? .failed
            if decided == .claimed {
                clearError()
                logger.notice("Committed a match at court \(candidate.courtId, privacy: .public)")
            } else {
                logger.debug(
                    "Commit against \(candidate.ticket.squadId, privacy: .public) ended as \(decided.rawValue, privacy: .public)"
                )
            }
            return decided
        } catch {
            let gameError = Self.mapped(error)

            // A refusal is the server's copy of the guards above firing — a
            // ticket moved between our read and the commit. Quiet, like losing,
            // and distinguished only so the logs stay honest about which side
            // rejected it.
            if gameError == .permissionDenied {
                logger.debug(
                    "Commit against \(candidate.ticket.squadId, privacy: .public) was refused by the rules"
                )
                return .refused
            }

            report(gameError, whileDoing: "setting up your match", context: .write)
            return .failed
        }
    }

    /// The new match document, as a field map.
    ///
    /// Pulled out of the transaction body so the shape of a `seasonGame` stays
    /// readable as one thing, and so a retried transaction rebuilds exactly the
    /// same document. Everything here is verified server-side against the two
    /// tickets — the court against the home list, the time against both windows,
    /// the names and leaders against `squads`.
    private static func newMatchFields(
        id: String,
        home: MatchTicket,
        away: MatchTicket,
        awaySquadName: String,
        courtId: String,
        scheduledTime: Date,
        createdBy uid: String
    ) -> [String: Any] {
        [
            Field.id: id,
            Field.format: home.format.rawValue,
            Field.region: home.region,
            Field.homeSquadId: home.squadId,
            Field.awaySquadId: away.squadId,
            // Order is load-bearing: the create rule asserts this array equals
            // [homeSquadId, awaySquadId] exactly, so the other order is a
            // `permission-denied` with no obvious cause.
            Field.squadIds: SeasonGame.squadIds(home: home.squadId, away: away.squadId),
            Field.homeLeaderId: home.leaderId,
            Field.awayLeaderId: uid,
            Field.homeSquadName: home.squadName,
            Field.awaySquadName: awaySquadName,
            Field.courtId: courtId,
            Field.scheduledTime: Timestamp(date: scheduledTime),
            Field.status: SeasonGame.Status.scheduled.rawValue,
            Field.arrivedPlayerIds: [String](),
            Field.createdBy: uid,
            Field.createdAt: FieldValue.serverTimestamp(),
            Field.updatedAt: FieldValue.serverTimestamp(),
        ]
    }

    /// Calls a match off. Either leader, as their own squad, enforced
    /// server-side.
    ///
    /// An update rather than a delete: a cancelled match is still history both
    /// squads should see, and `seasonGames` refuses deletes outright because a
    /// deletable match is a forgeable record.
    func cancelGame(id gameId: String, bySquadId squadId: String) async throws {
        guard observedUID != nil else { throw SeasonGameError.notSignedIn }

        do {
            try await database
                .collection(Collection.seasonGames)
                .document(gameId)
                .updateData([
                    Field.status: SeasonGame.Status.cancelled.rawValue,
                    Field.cancelledBySquadId: squadId,
                    Field.updatedAt: FieldValue.serverTimestamp(),
                ])
            clearError()
        } catch {
            let gameError = Self.mapped(error)
            report(gameError, whileDoing: "cancelling the match", context: .write)
            throw gameError
        }
    }

    /// Marks the signed-in user's own squad as arrived. Screen 7's "We're
    /// here."
    ///
    /// Self-add only, enforced server-side: the diff is exactly the caller's
    /// own uid, added, and never removed — there is no "un-arrive". Both
    /// squads read the same array off the same listener, which is the moment
    /// a squad sees they're first to the court.
    ///
    /// - Returns: `true` when the write changed something; `false` when the
    ///   caller had already arrived, so the caller can stay quiet rather than
    ///   reporting a failure.
    @discardableResult
    func markArrived(gameId: String) async throws -> Bool {
        guard let uid = observedUID else { throw SeasonGameError.notSignedIn }
        guard let existing = games.first(where: { $0.id == gameId }) else {
            throw SeasonGameError.gameNotFound
        }
        guard !existing.hasArrived(uid) else { return false }

        do {
            try await database
                .collection(Collection.seasonGames)
                .document(gameId)
                .updateData([
                    Field.arrivedPlayerIds: FieldValue.arrayUnion([uid]),
                ])
            clearError()
            return true
        } catch {
            let gameError = Self.mapped(error)
            report(gameError, whileDoing: "marking your squad arrived", context: .write)
            throw gameError
        }
    }

    /// Records this leader's own report of who won — screen 8's two crest
    /// buttons — and, when it completes a matching pair, confirms the match in
    /// the same commit.
    ///
    /// **A transaction, and the race is the whole reason.** A plain
    /// `updateData` writing only the caller's own field leaves a real hole:
    /// two leaders reporting within moments of each other each read "no report
    /// yet" from their own client's cache, each write only their own field, and
    /// neither write ever runs the do-these-agree check against the state that
    /// actually landed. Both reports end up stored, `result` never gets set, and
    /// nothing fails to say so. A transaction reads the document at commit time
    /// and retries against the winner's committed state, so the second report
    /// always sees the first — the same way every other contested
    /// single-document write here is handled. See `GameService.mutateRoster`
    /// for the shape, and `MatchmakingService`'s claim for the precedent.
    ///
    /// The standing reports are read **inside** the transaction rather than off
    /// this service's listener, which is the difference the whole method exists
    /// for: the listener's copy can be seconds stale, and the transaction's own
    /// read is the only view guaranteed current.
    ///
    /// - Returns: what the match reads as once the write lands — awaiting the
    ///   other leader, disputed, or confirmed.
    @discardableResult
    func reportResult(
        gameId: String,
        winningSquadId: String,
        homeScore: Int? = nil,
        awayScore: Int? = nil
    ) async throws -> SeasonGame.ReportOutcome {
        guard let uid = observedUID else { throw SeasonGameError.notSignedIn }

        let reference = database.collection(Collection.seasonGames).document(gameId)

        do {
            let raw = try await database.runTransaction { transaction, errorPointer in
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(reference)
                } catch let fetchError as NSError {
                    // Setting the pointer makes `runTransaction` throw, so the
                    // value returned here is never inspected.
                    errorPointer?.pointee = fetchError
                    return nil
                }

                guard let data = snapshot.data(),
                      let homeSquadId = data[Field.homeSquadId] as? String,
                      let awaySquadId = data[Field.awaySquadId] as? String,
                      let homeLeaderId = data[Field.homeLeaderId] as? String,
                      let awayLeaderId = data[Field.awayLeaderId] as? String,
                      let rawStatus = data[Field.status] as? String,
                      let status = SeasonGame.Status(rawValue: rawStatus),
                      let scheduledTime = (data[Field.scheduledTime] as? Timestamp)?.dateValue()
                else {
                    return ReportTransaction.missing.rawValue
                }

                let field: SeasonGame.ReportField
                if uid == homeLeaderId {
                    field = .home
                } else if uid == awayLeaderId {
                    field = .away
                } else {
                    return ReportTransaction.notLeader.rawValue
                }

                // The same three preconditions the rule checks, against the
                // state the rule will see rather than the one the screen was
                // drawn from.
                guard status == .scheduled || status == .disputed else {
                    return ReportTransaction.settled.rawValue
                }
                guard Date() >= scheduledTime else {
                    return ReportTransaction.notPlayed.rawValue
                }
                guard winningSquadId == homeSquadId || winningSquadId == awaySquadId else {
                    return ReportTransaction.unknownWinner.rawValue
                }

                let write = SeasonGame.reportWrite(
                    field: field,
                    winner: winningSquadId,
                    homeScore: homeScore,
                    awayScore: awayScore,
                    standingHomeReport: data[Field.homeReport] as? String,
                    standingAwayReport: data[Field.awayReport] as? String
                )

                var fields: [String: Any] = [
                    field.rawValue: winningSquadId,
                    // Derived from the two reports, never chosen — the rules
                    // recompute it from the same pair and refuse anything else.
                    Field.status: write.status.rawValue,
                    Field.updatedAt: FieldValue.serverTimestamp(),
                ]

                if let result = write.result {
                    fields[Field.result] = result
                    fields[Field.confirmedAt] = FieldValue.serverTimestamp()
                }
                if let homeScore { fields[Field.homeScore] = homeScore }
                if let awayScore { fields[Field.awayScore] = awayScore }

                transaction.updateData(fields, forDocument: reference)

                return ReportTransaction(write.outcome).rawValue
            }

            switch ReportTransaction(rawValue: raw as? String ?? "") {
            case .missing:       throw SeasonGameError.gameNotFound
            case .notLeader:     throw SeasonGameError.notLeader
            case .settled:       throw SeasonGameError.notScheduled
            case .notPlayed:     throw SeasonGameError.notPlayed
            case .unknownWinner: throw SeasonGameError.unknownWinner
            case .disputed:
                clearError()
                return .disputed
            case .confirmed:
                clearError()
                logger.notice("Match \(gameId, privacy: .public) confirmed by both leaders")
                return .confirmed(winningSquadId)
            case .awaitingReport, .none:
                clearError()
                return .awaitingReport
            }
        } catch let gameError as SeasonGameError {
            report(gameError, whileDoing: "recording the result", context: .write)
            throw gameError
        } catch {
            let gameError = Self.mapped(error)
            report(gameError, whileDoing: "recording the result", context: .write)
            throw gameError
        }
    }

    // MARK: - Helpers

    private func clearError() {
        errorMessage = nil
        errorIsFromLoad = false
    }

    private func report(_ error: SeasonGameError, whileDoing action: String, context: FailureContext) {
        logger.error(
            "Season game error while \(action, privacy: .public): \(String(describing: error), privacy: .public)"
        )
        errorMessage = Self.message(for: error, whileDoing: action, context: context)
        errorIsFromLoad = context == .load
    }

    /// The user-facing sentence for a failure.
    ///
    /// `context` disambiguates `permission-denied`, as on every other service.
    /// The listener asks only for matches the read rule already admits — any
    /// signed-in account may read `seasonGames` — so a denied **read** means the
    /// server isn't running this repo's rules. A denied **write** was validated
    /// against the home ticket client-side first, so it is the state having
    /// moved: the claim went stale, or somebody cancelled underneath the
    /// screen. Never blamed on deployment.
    nonisolated static func message(
        for error: SeasonGameError,
        whileDoing action: String,
        context: FailureContext
    ) -> String {
        switch error {
        case .notSignedIn:
            return FailureText.signedOut
        case .sameSquad, .sharedPlayer:
            return "A squad can't play itself."
        case .formatMismatch, .regionMismatch:
            return "Those squads aren't in the same queue."
        case .courtNotOffered:
            return "That court isn't one the other squad offered."
        case .timeOutsideWindow:
            return "That time is outside the other squad's window."
        case .scheduleTooSoon:
            return "Pick a tip-off at least 5 minutes from now."
        case .claimExpired:
            return "That match slipped away. Still looking."
        case .gameNotFound:
            return "That match is no longer there."
        case .notLeader:
            return "Only a squad's leader can do that."
        case .notScheduled:
            return "That match has already been settled."
        case .notPlayed:
            return "You can record the result once the game has started."
        case .unknownWinner:
            return "That squad isn't in this match."
        case .permissionDenied:
            switch context {
            case .load:
                return FailureText.rulesNotDeployed(loading: "your matches")
            case .write:
                return "The server wouldn't accept that. This match may have changed since it loaded."
            }
        case .indexRequired:
            return "Your matches need a database index that's still being built."
        case .network:
            return FailureText.network
        case .unknown:
            return "Something went wrong while \(action)."
        }
    }

    /// Names what `FirestoreFailure` classified, in this collection's terms.
    ///
    /// The listener is composite (an array-contains-any plus an order), so
    /// `.indexRequired` is a case a match list can genuinely hit.
    private static func mapped(_ error: Error) -> SeasonGameError {
        if let gameError = error as? SeasonGameError { return gameError }

        switch FirestoreFailure.classify(error) {
        case .permissionDenied:         return .permissionDenied
        case .notFound:                 return .gameNotFound
        case .indexRequired:            return .indexRequired
        case .network:                  return .network
        case .unknown(let description): return .unknown(description)
        }
    }
}
