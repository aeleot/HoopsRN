import Combine
import CoreLocation
import FirebaseFirestore
import Foundation
import os

fileprivate let logger = Logger(subsystem: "com.hoopsrn", category: "MatchmakingService")

/// Owns the `matchTickets` collection — the matchmaking pool, and the search
/// loop that runs against it.
///
/// **There is no server.** `context/plans/SEASONS.md` §0.1: nothing can wake up,
/// look at a pool of waiting squads and pair them. So matchmaking is *pull with
/// a lock* — every queued client watches the same pool, and the winner of a
/// contested transaction gets the match. This service is the pull: the pool
/// listener, the scan, the ranking, jitter and backoff.
///
/// **It does not write the match itself.** The commit that turns a chosen
/// candidate into a match spends two tickets and creates a `seasonGames`
/// document in one transaction, so it spans two collections and cannot belong
/// to either service alone; it lives in `SeasonGameService.commitMatch` and
/// reaches this loop through `commitMatch`, which `MatchmakingViewModel` wires
/// up. What stays here is everything about *choosing*, which is this
/// collection's own business — and the `ClaimPolicy` loop stays whole rather
/// than being split across two objects.
///
/// Follows `SquadService` and `GameService` structurally — its own `AuthService`
/// subscription, a `ListenerSupervisor`, per-document decoding, and no Firestore
/// type escaping this file.
///
/// **It depends on no other service.** The scan needs the court dataset and a
/// distance anchor, and both arrive as parameters to `startSearching` rather
/// than as injected services — the same move `SquadService.createSquad(region:)`
/// makes with a value derived from `CourtService` and `LocationService`.
/// Turns a chosen candidate into a real match, and reports how it went.
///
/// **A closure rather than a service reference, because the write it performs
/// belongs to neither service.** Committing a match spends both squads'
/// tickets and creates the `seasonGames` document in one transaction — it has
/// to be one transaction, or two squads that pick each other both commit — so
/// it spans two collections at once. `MatchmakingService` owns `matchTickets`,
/// `SeasonGameService` owns `seasonGames`, and services in this app hold no
/// references to each other. `MatchmakingViewModel` supplies this, which is the
/// same cross-collection wiring the house rules already put in view models.
///
/// Passing the courts and the anchor through means the commit can re-rank the
/// pair against the tickets as its own transaction reads them, rather than
/// trusting a candidate chosen against a snapshot that may be seconds old.
typealias MatchCommitting = @MainActor (
    _ candidate: MatchCandidate,
    _ mine: MatchTicket,
    _ courts: [String: Court],
    _ anchor: CLLocationCoordinate2D
) async -> ClaimOutcome

@MainActor
final class MatchmakingService: ObservableObject {
    /// My squad's own ticket, watched as a single document.
    ///
    /// Separate from `pool` and not merely filtered out of it: the pool query
    /// is `status == 'open'`, so a ticket spent on a match **leaves** the pool.
    /// Watching my own document is how this service knows whether it is still
    /// searching at all — it is what drives the pool listener up and down.
    @Published private(set) var myTicket: MatchTicket?

    /// Every claimable ticket in my region and format, mine included — the
    /// rules reject self-matching, so filtering here would only duplicate that.
    @Published private(set) var pool: [MatchTicket] = []

    /// Commits a chosen candidate as a real match, atomically, and says how it
    /// went. Supplied by `MatchmakingViewModel`; see the type's own note.
    ///
    /// Optional rather than required in `init` so this service keeps its "no
    /// dependency on any other service" shape — the wiring is the view model's,
    /// the same way `supervisor.onRetry` is this object's.
    var commitMatch: MatchCommitting?

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

    /// Field names live on `MatchTicket` rather than in a private enum here,
    /// because `SeasonGameService.commitMatch` writes these same documents
    /// inside the transaction that creates a match. See `MatchTicket.Field`.
    ///
    /// There is deliberately no `updatedAt`: `matchTickets` doesn't carry one.
    /// `claimedAt` already is the ticket's "when did this change" stamp, the
    /// commit is the ticket's only mutation, and the rules' `affectedKeys()`
    /// allowlist is four fields wide. Adding one would mean widening that
    /// allowlist, which is the one place it should stay narrow.
    private typealias Field = MatchTicket.Field

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
        clearError()
    }

    /// Stops *looking* without forgetting what we were looking for.
    ///
    /// **This is what "cancel the search when a match is made" means here.**
    /// The pool listener is a live query over every open ticket in the region;
    /// once this squad's own ticket is spent there is nothing it can tell us,
    /// and a scan that kept running could only pick a candidate the rules would
    /// refuse. The `myTicket` listener stays attached, because a spent ticket
    /// becoming a fresh one is exactly how the search starts again.
    ///
    /// Reached from both sides of a match and needs no coordination between
    /// them: the squad that committed and the squad that was claimed both see
    /// their own ticket turn `matched` on their own listener.
    private func concludeSearch() {
        scanTask?.cancel()
        scanTask = nil
        poolListener?.remove()
        poolListener = nil
        supervisor.recordSuccess(for: ListenerKey.pool)
        attempt = 0
        isBackingOff = false
        hasLoadedPool = false
        pool = []
    }

    /// Brings the pool listener up while this squad is searching and takes it
    /// down when it isn't, off a single source of truth: our own ticket.
    ///
    /// Every transition runs through here — queueing, matching, leaving,
    /// expiring — so there is one answer to "should we be watching the pool"
    /// rather than one per caller.
    private func syncPoolListener() {
        guard let search, myTicket?.isSearching == true else {
            if poolListener != nil { concludeSearch() }
            return
        }

        guard poolListener == nil else { return }
        attachPoolListener(for: search)
    }

    /// Re-attaches now rather than waiting out the backoff.
    func retry() {
        supervisor.retryNow()
    }

    /// Opens the ticket listener, and lets it decide about the pool. Also the
    /// supervisor's retry path, matching the other services.
    ///
    /// The pool listener is deliberately *not* opened here unconditionally:
    /// whether we should be watching the pool is a question about our own
    /// ticket, and `syncPoolListener` is the one place that answers it. On a
    /// cold attach `myTicket` is still nil, so the pool comes up a beat later
    /// when the first ticket snapshot lands — which is the right order anyway,
    /// since a scan needs our own ticket before it can rank anything.
    private func attachListeners() {
        guard let search else { return }

        poolListener?.remove()
        poolListener = nil
        myTicketListener?.remove()

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

    /// The pool query.
    ///
    /// **`status == 'open'`, not `in ['open', 'claimed']`.** There is no
    /// `claimed` any more: a ticket is in the pool or it is spent on a match,
    /// and the transaction that spends it leaves no state in between for a
    /// scanner to have to recover. The composite index this uses — region,
    /// format, status, expiresAt — is unchanged, since an equality filter and
    /// an `in` filter on the same field read the same index.
    private func attachPoolListener(for search: Search) {
        // Recomputed per attach rather than captured once, so a listener
        // re-attached minutes later doesn't filter on a stale instant.
        let now = Timestamp(date: Date())

        poolListener = database
            .collection(Collection.matchTickets)
            .whereField(Field.region, isEqualTo: search.region)
            .whereField(Field.format, isEqualTo: search.format.rawValue)
            .whereField(Field.status, isEqualTo: MatchTicket.Status.open.rawValue)
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

        // Our own ticket may have just been spent — by us, or by the squad
        // that claimed it — so decide whether we should still be watching the
        // pool at all before deciding whether to scan it.
        syncPoolListener()

        // Every snapshot is a reason to look again: a new ticket, a match
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
        guard search != nil, scanTask == nil else { return }

        scanTask = Task { [weak self] in
            await self?.scan()
            self?.scanTask = nil
        }
    }

    private func scan() async {
        guard let search, let commit = commitMatch else { return }
        guard let mine = myTicket else { return }

        // My own ticket has to still be in play. A ticket is spent exactly
        // once, so if mine is already spent I am in a match and must not take
        // anyone else out of the pool — that is how a squad double-books
        // itself. Re-read on every pass rather than trusted from the last one,
        // because the answer changes underneath us.
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
        guard !Task.isCancelled else { return }

        // **Re-read after the sleep, not only before it.** The jitter is up to
        // three seconds, and the whole point of it is that somebody else is
        // acting in that interval — including, in a two-squad pool, the squad
        // we are about to claim, claiming us. Checking staleness before a
        // deliberate pause and not after made the pause itself the window: a
        // client could watch its own ticket be spent and commit anyway.
        guard let fresh = myTicket, fresh.isClaimable(at: Date()) else { return }

        attempt += 1
        let outcome = await commit(candidate, fresh, search.courts, search.anchor)

        switch ClaimPolicy.next(after: outcome, attempt: attempt) {
        case .stop:
            attempt = 0
            isBackingOff = false
            // The ticket listener concludes the search on its own the moment it
            // sees our ticket spent; doing it here too means the pool query is
            // down before the round trip, rather than a beat after it.
            concludeSearch()
            logger.notice("Committed a match against \(candidate.ticket.squadId, privacy: .public)")

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
            guard !Task.isCancelled else { return }
            attempt = 0
            await scan()
        }
    }

    // MARK: - The commit

    // **The contested write used to live here, and moving it is the fix.**
    //
    // It was a transaction against one document: the other squad's ticket. That
    // rested on Firestore serializing contested writes to a *single* document,
    // which it does — and which turned out to be the wrong guarantee. Two
    // squads claiming each other write to two *different* tickets, so nothing
    // serializes them, both win, and both go on to create a match. With two
    // squads in a pool that is the ordinary path, not a rare one, and it is
    // what put two live matches in front of both squads.
    //
    // The commit now reads and writes *both* tickets and the game in one
    // transaction, so the two mutual attempts finally share a read set and
    // exactly one lands. That write spans two collections, so it lives in
    // `SeasonGameService.commitMatch` and arrives here as `commitMatch`.
    //
    // **What hasn't changed is why losing is quiet.** Every loser re-reads a
    // ticket that is already spent and fails the same guard it always did. The
    // pool is shared, every client sees every ticket, and being second is the
    // ordinary experience of a healthy pool — the user asked to be matched, not
    // to win this particular race, and the search is already looking again.
    // `ClaimPolicy.isUserFacing` keeps that quiet, and it is a pure function so
    // the quietness stays tested.

    // MARK: - Writes

    /// Removes this squad's ticket if it has already been spent on a match, so
    /// a fresh one can be written at the same document ID.
    ///
    /// An `open` ticket is left alone and reported as `alreadyQueued`: the squad
    /// really is in the pool, and silently replacing a live offer would move the
    /// window and courts out from under a claimer mid-race.
    private func clearSpentTicket(for squadId: String) async throws {
        let reference = database.collection(Collection.matchTickets).document(squadId)

        do {
            let snapshot = try await reference.getDocument()
            guard snapshot.exists else { return }

            if let existing = try? snapshot.data(as: MatchTicket.self), existing.isSearching {
                throw MatchTicketError.alreadyQueued
            }

            try await reference.delete()
        } catch let error as MatchTicketError {
            throw error
        } catch {
            let ticketError = Self.mapped(error)
            report(ticketError, whileDoing: "joining the queue", context: .write)
            throw ticketError
        }
    }

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

        // **A spent ticket has to be cleared before a new one can be written.**
        // The document ID is the squad ID, so this write is a create against a
        // fixed path — and once a ticket has been spent on a match, nothing
        // removes it. It sits there `matched` until `expiresAt`, which is up to
        // a day, and a `setData` over it is an *update* as far as the rules are
        // concerned. The update paths only permit `open` -> `matched`, so the
        // squad would be refused every time it tried to queue again, for hours,
        // with "the server wouldn't accept that" and nothing to act on.
        //
        // A leader may always delete their own ticket, so the fix needs no new
        // permission: clear the spent one, then create. Read first rather than
        // deleting blind, because a delete on a document that isn't there has
        // no `resource` for the rule to read and fails as an error.
        try await clearSpentTicket(for: squad.id)

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

    // **`markMatched` and `releaseWonClaim` used to live here, and both were
    // repairs to a window that no longer exists.**
    //
    // `markMatched` had two callers for one reason: a client could die after
    // writing the game and before closing the tickets, leaving a ticket that
    // went stale with its match already made — so a third squad re-claimed it
    // and created a second match against a squad that already had one. Each
    // squad closing its own ticket off its own `seasonGames` listener was the
    // fix that needed no new permission.
    //
    // `releaseWonClaim` was the other half: a claim won but never turned into a
    // game froze the search, because the won claim was the loop's only "stop
    // looking" signal and nothing else cleared it.
    //
    // Both are gone because the gap they sat in is gone. The game and both
    // tickets land in one commit, so there is no instant at which one exists
    // without the others, and nothing to reconcile afterwards.

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
        case .matchAlreadyScheduled:
            return "Your squad already has a match scheduled."
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
