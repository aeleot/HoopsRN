import Combine
import CoreLocation
import FirebaseFirestore
import Foundation
import os

fileprivate let logger = Logger(subsystem: "com.hoopsrn", category: "MatchmakingService")

/// Owns the `matchTickets` collection — the matchmaking pool, and the one
/// contested write in the app.
///
/// **There is no server.** `context/plans/SEASONS.md` §0.1: nothing can wake up,
/// look at a pool of waiting squads and pair them. So matchmaking is *pull with
/// a lock* — every queued client watches the same pool, and the winner of a
/// one-document race gets to create the match. This service is that client
/// side: the pool listener, the scan, the claim transaction, jitter and
/// backoff.
///
/// Follows `SquadService` and `GameService` structurally — its own `AuthService`
/// subscription, a `ListenerSupervisor`, per-document decoding, and no Firestore
/// type escaping this file.
///
/// **It depends on no other service.** The scan needs the court dataset and a
/// distance anchor, and both arrive as parameters to `startSearching` rather
/// than as injected services — the same move `SquadService.createSquad(region:)`
/// makes with a value derived from `CourtService` and `LocationService`.
@MainActor
final class MatchmakingService: ObservableObject {
    /// My squad's own ticket, watched as a single document.
    ///
    /// Separate from `pool` and not merely filtered out of it: the pool query
    /// is `status in ['open', 'claimed']`, so a ticket that reaches `matched`
    /// **leaves** the pool. Watching my own document is how a waiting squad
    /// learns it has been matched — `matchedGameId` lands on a document it can
    /// always read, which is the plan's §2.2 handoff.
    @Published private(set) var myTicket: MatchTicket?

    /// Every claimable ticket in my region and format, mine included — the
    /// rules reject self-matching, so filtering here would only duplicate that.
    @Published private(set) var pool: [MatchTicket] = []

    /// The claim we won, waiting for Phase 4 to turn it into a `seasonGames`
    /// document. Cleared by `stopSearching()`.
    @Published private(set) var wonClaim: MatchCandidate?

    @Published private(set) var errorMessage: String?

    /// A listener died and a re-attach is pending. **Not** the same thing as
    /// `isBackingOff` — see `ClaimPolicy.retryOwnership`.
    @Published private(set) var isRecovering = false

    /// True once the pool listener has delivered a snapshot successfully, so an
    /// empty pool can be told from an unanswered query.
    @Published private(set) var hasLoadedPool = false

    /// Contention has pushed the loop into its quiet poll. The searching screen
    /// says "still looking", not an error — losing races is what a healthy pool
    /// looks like from inside.
    @Published private(set) var isBackingOff = false

    private enum Collection {
        static let matchTickets = "matchTickets"
    }

    private enum ListenerKey {
        static let pool = "pool"
        static let mine = "mine"
    }

    /// Field names in one place so the write maps can't drift from
    /// `MatchTicket`'s coding keys, matching the other four services.
    ///
    /// There is deliberately no `updatedAt`: `matchTickets` doesn't carry one.
    /// `claimedAt` already is the ticket's "when did this change" stamp, the
    /// claim is the ticket's only mutation, and the rules' `affectedKeys()`
    /// allowlist on the claim is three fields wide. Adding one would mean
    /// widening that allowlist, which is the one place it should stay narrow.
    private enum Field {
        static let squadId = "squadId"
        static let leaderId = "leaderId"
        static let squadName = "squadName"
        static let memberIds = "memberIds"
        static let format = "format"
        static let region = "region"
        static let courtIds = "courtIds"
        static let windowStart = "windowStart"
        static let windowEnd = "windowEnd"
        static let wins = "wins"
        static let losses = "losses"
        static let status = "status"
        static let claimedBy = "claimedBy"
        static let claimedAt = "claimedAt"
        static let createdAt = "createdAt"
        static let expiresAt = "expiresAt"
    }

    /// How much of the pool is worth holding. A region's live pool is tens of
    /// tickets; this is a sanity limit, not pagination.
    private enum Limit {
        static let pool = 200
    }

    /// Resolved lazily so the Firestore singleton is never touched before
    /// `FirebaseApp.configure()` has run.
    private lazy var database = Firestore.firestore()

    private var poolListener: ListenerRegistration?
    private var myTicketListener: ListenerRegistration?
    private var observedUID: String?
    private var cancellables = Set<AnyCancellable>()

    /// What `startSearching` was told to search for. Held rather than passed
    /// through every call because the pool listener re-attaches on its own
    /// schedule and has to be able to rebuild the same query.
    private var search: Search?

    /// The scan/claim task. At most one, ever — a second would race the first
    /// for the same candidate, which is the one thing this service exists to
    /// avoid doing to other people.
    private var scanTask: Task<Void, Never>?

    /// Consecutive claim attempts since the last back-off or success. Reset
    /// when the back-off elapses, so a poll that finds a quieter pool starts
    /// from a clean count.
    private var attempt = 0

    /// Brings the pool listener back after it dies. **Network health only** —
    /// contention is `ClaimPolicy`'s, and merging the two breaks both. See
    /// `ClaimPolicy.retryOwnership`.
    private let supervisor = ListenerSupervisor(subject: "matchmaking")

    private var errorIsFromLoad = false

    var currentUserId: String? { observedUID }

    /// Everything the pool query and the scan need, captured when searching
    /// starts.
    private struct Search {
        let squadId: String
        let region: String
        let format: SquadFormat
        /// The bundled dataset, keyed by ID. A value, not `CourtService` —
        /// services in this app have no dependencies on each other.
        let courts: [String: Court]
        /// `LocationService.homeLocation`, like every other distance in the app.
        let anchor: CLLocationCoordinate2D
    }

    init(authService: AuthService) {
        authService.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                self?.handleAuthChange(to: user)
            }
            .store(in: &cancellables)

        // Weak: this service owns the supervisor, so a strong capture here
        // would be a cycle.
        supervisor.onRetry = { [weak self] in
            self?.attachListeners()
        }
    }

    deinit {
        poolListener?.remove()
        myTicketListener?.remove()
    }

    // MARK: - Session wiring

    private func handleAuthChange(to user: AuthenticatedUser?) {
        guard let user else {
            stopSearching()
            observedUID = nil
            return
        }

        guard user.id != observedUID else { return }

        stopSearching()
        observedUID = user.id
    }

    // MARK: - Searching

    /// Starts watching the pool for `squadId` and claiming the best candidate
    /// that appears.
    ///
    /// - Parameters:
    ///   - courts: the bundled dataset keyed by ID, for distances.
    ///   - anchor: `LocationService.homeLocation`. Passed in for the same
    ///     reason `region` is passed to `SquadService.createSquad` — deriving it
    ///     needs two other services, and services here don't depend on each
    ///     other.
    func startSearching(
        squadId: String,
        region: String,
        format: SquadFormat,
        courts: [String: Court],
        anchor: CLLocationCoordinate2D
    ) {
        guard observedUID != nil else { return }

        // A restart for the same squad would tear down a healthy listener and
        // re-run the scan for a candidate already being claimed.
        if let search, search.squadId == squadId, search.region == region, search.format == format {
            return
        }

        stopSearching()
        search = Search(
            squadId: squadId,
            region: region,
            format: format,
            courts: courts,
            anchor: anchor
        )
        attachListeners()
    }

    /// Stops searching and forgets everything about it. Called on sign-out, on
    /// leaving the queue, and once a claim is won and handed to Phase 4.
    func stopSearching() {
        supervisor.cancel()
        scanTask?.cancel()
        scanTask = nil
        poolListener?.remove()
        poolListener = nil
        myTicketListener?.remove()
        myTicketListener = nil
        search = nil
        attempt = 0
        isRecovering = false
        isBackingOff = false
        hasLoadedPool = false
        pool = []
        myTicket = nil
        wonClaim = nil
        clearError()
    }

    /// Re-attaches now rather than waiting out the backoff.
    func retry() {
        supervisor.retryNow()
    }

    /// Opens both listeners, replacing any already open. Also the supervisor's
    /// retry path, matching the other services.
    ///
    /// **`status in ['open', 'claimed']`, not `== 'open'`.** A query filtered to
    /// open alone would hide every stale claim from the scanner, which would
    /// make the plan's §2.3 recovery unreachable — and nothing would report it,
    /// because a ticket wedged by a claimer that crashed simply never appears.
    /// The composite index for this query already exists.
    private func attachListeners() {
        guard let search else { return }

        poolListener?.remove()
        myTicketListener?.remove()

        // Recomputed per attach rather than captured once, so a listener
        // re-attached minutes later doesn't filter on a stale instant.
        let now = Timestamp(date: Date())

        poolListener = database
            .collection(Collection.matchTickets)
            .whereField(Field.region, isEqualTo: search.region)
            .whereField(Field.format, isEqualTo: search.format.rawValue)
            .whereField(
                Field.status,
                in: [MatchTicket.Status.open.rawValue, MatchTicket.Status.claimed.rawValue]
            )
            .whereField(Field.expiresAt, isGreaterThan: now)
            .limit(to: Limit.pool)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handle(error: error, listener: ListenerKey.pool, describing: "the pool") {
                        service in
                        service.pool = Self.decoded(snapshot)
                        service.hasLoadedPool = true
                    }
                }
            }

        myTicketListener = database
            .collection(Collection.matchTickets)
            .document(search.squadId)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handle(error: error, listener: ListenerKey.mine, describing: "your queue") {
                        service in
                        service.myTicket = Self.decoded(snapshot)
                    }
                }
            }
    }

    private func handle(
        error: Error?,
        listener: String,
        describing subject: String,
        assign: (MatchmakingService) -> Void
    ) {
        if let error {
            // The listener is already gone — see `ListenerSupervisor`.
            supervisor.recordFailure(for: listener)
            isRecovering = true
            report(Self.mapped(error), whileDoing: "loading \(subject)", context: .load)
            return
        }

        supervisor.recordSuccess(for: listener)
        isRecovering = supervisor.isRecovering

        assign(self)

        if errorIsFromLoad, !supervisor.isRecovering {
            clearError()
        }

        // Every snapshot is a reason to look again: a new ticket, a claim
        // landing, or my own ticket ageing into a wider relaxation.
        scheduleScan()
    }

    /// Decodes per document rather than per snapshot, matching
    /// `GameService.decoded`: one drifted row shouldn't blank the pool.
    private static func decoded(_ snapshot: QuerySnapshot?) -> [MatchTicket] {
        guard let snapshot else { return [] }

        return snapshot.documents.compactMap { document in
            do {
                return try document.data(as: MatchTicket.self)
            } catch {
                logger.error(
                    "Skipping ticket \(document.documentID, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }
    }

    private static func decoded(_ snapshot: DocumentSnapshot?) -> MatchTicket? {
        guard let snapshot, snapshot.exists else { return nil }

        do {
            return try snapshot.data(as: MatchTicket.self)
        } catch {
            logger.error(
                "Skipping ticket \(snapshot.documentID, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    // MARK: - The scan

    /// Ranks the pool and claims the top candidate, once.
    ///
    /// At most one of these runs: a second would race the first for the same
    /// ticket, and burning a transaction against ourselves is the one form of
    /// contention entirely within our own control.
    private func scheduleScan() {
        guard search != nil, wonClaim == nil, scanTask == nil else { return }

        scanTask = Task { [weak self] in
            await self?.scan()
            self?.scanTask = nil
        }
    }

    private func scan() async {
        guard let search, wonClaim == nil else { return }
        guard let mine = myTicket else { return }

        // My own ticket has to still be in play. If somebody has just claimed
        // *me* I'm about to be matched and must not claim anyone else — that is
        // how a squad double-books itself.
        guard mine.isClaimable(at: Date()) else { return }

        let candidates = MatchRules.rank(
            for: mine,
            against: pool,
            courts: search.courts,
            anchor: search.anchor,
            now: Date()
        )

        guard let candidate = candidates.first else {
            // An empty pool isn't a failure and isn't a back-off. The listener
            // will say when that changes, and relaxation widens the criteria on
            // its own as my ticket ages.
            isBackingOff = false
            return
        }

        // Jitter before the claim, not after: six clients seeing the same new
        // ticket in the same instant is exactly the thundering herd §2.5
        // describes, and spreading the transactions is the only mitigation that
        // works *before* the race rather than after it.
        var generator = SystemRandomNumberGenerator()
        let delay = ClaimPolicy.jitterDelay(using: &generator)
        try? await Task.sleep(for: .seconds(delay))
        guard !Task.isCancelled, wonClaim == nil else { return }

        attempt += 1
        let outcome = await claim(candidate, mine: mine, search: search)

        switch ClaimPolicy.next(after: outcome, attempt: attempt) {
        case .stop:
            attempt = 0
            isBackingOff = false
            wonClaim = candidate
            logger.notice("Won a claim on ticket \(candidate.ticket.squadId, privacy: .public)")

        case .rescan:
            isBackingOff = false
            // Re-rank rather than taking the next candidate: the pool that
            // ranked this one is now known to be stale, so its runner-up is a
            // guess about a snapshot we have just been told is wrong.
            await scan()

        case .backOff(let interval):
            isBackingOff = true
            logger.debug("Backing off for \(interval, privacy: .public)s after \(self.attempt, privacy: .public) attempts")
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled, wonClaim == nil else { return }
            attempt = 0
            await scan()
        }
    }

    // MARK: - The claim

    /// **The one contested write in the feature.** A transaction against a
    /// single document: the other squad's ticket.
    ///
    /// What it reads: that ticket, and only that ticket. What it re-checks:
    /// every hard rule, against the version the transaction itself read.
    ///
    /// **Re-checking inside is not redundant with the scan outside.** The scan
    /// ran against a pool snapshot that is at best milliseconds old and at
    /// worst seconds — a listener snapshot is a push of what *was* true. In
    /// between, the ticket may have been claimed by somebody faster, expired,
    /// had its window narrowed, or been re-queued by a leader who left and came
    /// back with a different roster. The transaction's own read is the only
    /// view of the ticket guaranteed current at the moment of the write, and
    /// Firestore's guarantee is precisely that: if this document changes before
    /// the commit, the whole transaction is retried against the new value.
    /// Checking outside and writing inside would be checking a value we are not
    /// writing against.
    ///
    /// **What happens to each loser, and why it is not an error.** Firestore
    /// serializes contested single-document transactions, so exactly one
    /// claimer commits. Everyone else either has their transaction retried —
    /// where it re-reads a now-`claimed` ticket and the guard below returns
    /// `.lost` — or is refused by the rules for the same reason. Neither is a
    /// failure of anything: the pool is shared, every client sees every ticket,
    /// and being second is the ordinary experience of a healthy pool. The user
    /// asked to be matched, not to win this particular race, and their search
    /// is already looking at the next candidate. `ClaimPolicy.isUserFacing`
    /// keeps that quiet, and it is a pure function so the quietness is tested.
    private func claim(
        _ candidate: MatchCandidate,
        mine: MatchTicket,
        search: Search
    ) async -> ClaimOutcome {
        let reference = database
            .collection(Collection.matchTickets)
            .document(candidate.ticket.squadId)
        let claimingSquadId = search.squadId
        let courts = search.courts
        let anchor = search.anchor

        do {
            let outcome = try await database.runTransaction { transaction, errorPointer in
                let snapshot: DocumentSnapshot
                do {
                    snapshot = try transaction.getDocument(reference)
                } catch let fetchError as NSError {
                    // Setting the pointer makes `runTransaction` throw, so the
                    // value returned here is never inspected.
                    errorPointer?.pointee = fetchError
                    return nil
                }

                guard snapshot.exists, let fresh = try? snapshot.data(as: MatchTicket.self) else {
                    return ClaimOutcome.missing.rawValue
                }

                // The re-check. Same pure function as the scan, against the
                // document this write will actually land on.
                guard MatchRules.candidate(
                    for: mine,
                    against: fresh,
                    courts: courts,
                    anchor: anchor,
                    now: Date()
                ) != nil else {
                    return ClaimOutcome.lost.rawValue
                }

                transaction.updateData(
                    [
                        Field.status: MatchTicket.Status.claimed.rawValue,
                        Field.claimedBy: claimingSquadId,
                        // Pinned, not requested. A claim a client could
                        // backdate would look fresh forever and wedge the
                        // ticket — which is why the rules assert
                        // `claimedAt == request.time` rather than trusting it.
                        Field.claimedAt: FieldValue.serverTimestamp(),
                    ],
                    forDocument: reference
                )

                return ClaimOutcome.claimed.rawValue
            }

            let decided = ClaimOutcome(rawValue: outcome as? String ?? "") ?? .failed
            if decided != .claimed {
                logger.debug("Claim on \(candidate.ticket.squadId, privacy: .public) ended as \(decided.rawValue, privacy: .public)")
            }
            return decided
        } catch {
            let ticketError = Self.mapped(error)

            // A refusal here is the server's copy of the guard above firing —
            // the ticket moved between our read and the commit. Quiet, like
            // losing, and distinguished only so the logs stay honest about
            // which side rejected it.
            if ticketError == .permissionDenied {
                logger.debug("Claim on \(candidate.ticket.squadId, privacy: .public) was refused by the rules")
                return .refused
            }

            report(ticketError, whileDoing: "looking for a match", context: .write)
            return .failed
        }
    }

    // MARK: - Writes

    /// Puts a squad in the pool.
    ///
    /// Every denormalized field is pinned to the `squads` document by the create
    /// rule, so the values passed here are checked rather than trusted — most
    /// importantly `memberIds`, which is what the no-shared-players rule reads.
    ///
    /// - Parameters:
    ///   - wins/losses: the squad's record, **derived by the caller** from
    ///     confirmed `seasonGames` (plan §1.1) rather than stored on the squad.
    ///     Zero until Phase 6 confirms anything, which is correct rather than
    ///     merely tolerable — `MatchTicket.winPercentage` reads an unplayed
    ///     squad as 0.5, not as a squad that loses everything.
    func queue(
        _ squad: Squad,
        courtIds: [String],
        windowStart: Date,
        windowEnd: Date,
        expiresAt: Date,
        wins: Int = 0,
        losses: Int = 0
    ) async throws {
        guard let uid = observedUID else { throw MatchTicketError.notSignedIn }
        guard squad.leaderId == uid else { throw MatchTicketError.notLeader }

        // Rejected, not reshaped, and checked against the same bounds the
        // create rule enforces — the shape `Game.validate` and `Squad.validate`
        // already use.
        if let invalid = MatchTicket.validate(
            courtIds: courtIds,
            windowStart: windowStart,
            windowEnd: windowEnd,
            expiresAt: expiresAt,
            format: squad.format
        ) {
            throw invalid
        }

        let fields: [String: Any] = [
            Field.squadId: squad.id,
            Field.leaderId: uid,
            Field.squadName: squad.name,
            Field.memberIds: squad.memberIds,
            Field.format: squad.format.rawValue,
            Field.region: squad.region,
            Field.courtIds: courtIds,
            Field.windowStart: Timestamp(date: windowStart),
            Field.windowEnd: Timestamp(date: windowEnd),
            Field.wins: wins,
            Field.losses: losses,
            // A ticket enters the pool open. `claimedBy`, `claimedAt` and
            // `matchedGameId` are absent — absence, never null — and only the
            // claim may introduce the first two.
            Field.status: MatchTicket.Status.open.rawValue,
            Field.createdAt: FieldValue.serverTimestamp(),
            Field.expiresAt: Timestamp(date: expiresAt),
        ]

        do {
            try await database
                .collection(Collection.matchTickets)
                .document(squad.id)
                .setData(fields)
            clearError()
            logger.debug("Queued a squad in region \(squad.region, privacy: .public)")
        } catch {
            let ticketError = Self.mapped(error)
            report(ticketError, whileDoing: "joining the queue", context: .write)
            throw ticketError
        }
    }

    /// Leaves the queue. The leader's alone, enforced server-side.
    ///
    /// A delete rather than a status: absence, never null, the same move
    /// `friendships` makes. An abandoned ticket also ages out on `expiresAt`
    /// without anyone having to remove it.
    func leaveQueue(squadId: String) async throws {
        guard observedUID != nil else { throw MatchTicketError.notSignedIn }

        do {
            try await database
                .collection(Collection.matchTickets)
                .document(squadId)
                .delete()
            stopSearching()
        } catch {
            let ticketError = Self.mapped(error)
            report(ticketError, whileDoing: "leaving the queue", context: .write)
            throw ticketError
        }
    }

    // MARK: - Helpers

    private func clearError() {
        errorMessage = nil
        errorIsFromLoad = false
    }

    private func report(_ error: MatchTicketError, whileDoing action: String, context: FailureContext) {
        logger.error(
            "Matchmaking error while \(action, privacy: .public): \(String(describing: error), privacy: .public)"
        )
        errorMessage = Self.message(for: error, whileDoing: action, context: context)
        errorIsFromLoad = context == .load
    }

    /// The user-facing sentence for a failure.
    ///
    /// `context` disambiguates `permission-denied`, which Firestore returns both
    /// for "the ruleset was never deployed" and for "the rules rejected this".
    /// The pool query asks only for documents the read rule already admits — any
    /// signed-in account may read `matchTickets` — so a denied **read** means
    /// the server isn't running this repo's rules. A denied **write** was
    /// validated client-side first, so it is the server rejecting something the
    /// client believed was legal. Never blamed on deployment: that sends the
    /// reader to the wrong file.
    ///
    /// `claimLost` has no sentence at all, because it never reaches a banner —
    /// see `ClaimPolicy.isUserFacing`.
    nonisolated static func message(
        for error: MatchTicketError,
        whileDoing action: String,
        context: FailureContext
    ) -> String {
        switch error {
        case .notSignedIn:
            return FailureText.signedOut
        case .invalidCourtSelection:
            let range = MatchTicket.courtCountRange
            return "Pick between \(range.lowerBound) and \(range.upperBound) courts."
        case .duplicateCourts:
            return "That court is already on your list."
        case .invalidWindow, .windowTooShort:
            return "Your window needs to be long enough to hold a game."
        case .windowInThePast:
            return "Pick a window that hasn't already passed."
        case .windowTooFar:
            return "You can only queue for games up to 30 days out."
        case .expiryTooSoon:
            return "A queue entry has to last at least 15 minutes."
        case .expiryTooFar:
            return "A queue entry can last at most 24 hours."
        case .notLeader:
            return "Only the squad's leader can queue it."
        case .alreadyQueued:
            return "This squad is already in the queue."
        case .claimLost, .ticketNotFound:
            return "That match was taken. Still looking."
        case .permissionDenied:
            switch context {
            case .load:
                return FailureText.rulesNotDeployed(loading: "the queue")
            case .write:
                return "The server wouldn't accept that. The queue may have changed since it loaded."
            }
        case .indexRequired:
            return "The queue needs a database index that's still being built."
        case .network:
            return FailureText.network
        case .unknown:
            return "Something went wrong while \(action)."
        }
    }

    private static func mapped(_ error: Error) -> MatchTicketError {
        if let ticketError = error as? MatchTicketError { return ticketError }

        switch FirestoreFailure.classify(error) {
        case .permissionDenied:         return .permissionDenied
        case .notFound:                 return .ticketNotFound
        case .indexRequired:            return .indexRequired
        case .network:                  return .network
        case .unknown(let description): return .unknown(description)
        }
    }
}
