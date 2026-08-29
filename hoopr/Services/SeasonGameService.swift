import Combine
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
/// **The claim → create → mark-matched sequence is not here.** It spans two
/// collections, and the two services that own them have no reference to each
/// other. A view model holding both sequences it — which puts a write
/// *sequence* in a view model where the precedent is joins only, and is still
/// the better trade: the alternative is one service reaching into another,
/// which nothing in this design needs.
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
        static let result = "result"
        static let createdBy = "createdBy"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
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

    /// Turns a won claim into a scheduled match.
    ///
    /// Everything here is verified server-side against the **home** ticket — the
    /// court against its `courtIds`, the time against its window, and the whole
    /// write against its `claimedBy`. `SeasonGame.validate` mirrors those checks
    /// client-side first, which is what makes a `permission-denied` here mean
    /// "the state moved" rather than "the rules aren't deployed".
    ///
    /// - Returns: the new match's document ID, which both tickets then carry as
    ///   `matchedGameId`.
    @discardableResult
    func createGame(
        homeTicket: MatchTicket,
        awayTicket: MatchTicket,
        homeSquadName: String,
        awaySquadName: String,
        courtId: String,
        scheduledTime: Date
    ) async throws -> String {
        guard let uid = observedUID else { throw SeasonGameError.notSignedIn }
        guard awayTicket.leaderId == uid else { throw SeasonGameError.notLeader }

        if let invalid = SeasonGame.validate(
            homeTicket: homeTicket,
            awayTicket: awayTicket,
            courtId: courtId,
            scheduledTime: scheduledTime
        ) {
            throw invalid
        }

        let reference = database.collection(Collection.seasonGames).document()

        let fields: [String: Any] = [
            Field.id: reference.documentID,
            Field.format: homeTicket.format.rawValue,
            Field.region: homeTicket.region,
            Field.homeSquadId: homeTicket.squadId,
            Field.awaySquadId: awayTicket.squadId,
            // Order is load-bearing: the create rule asserts this array equals
            // [homeSquadId, awaySquadId] exactly, so the other order is a
            // `permission-denied` with no obvious cause.
            Field.squadIds: SeasonGame.squadIds(
                home: homeTicket.squadId,
                away: awayTicket.squadId
            ),
            Field.homeLeaderId: homeTicket.leaderId,
            Field.awayLeaderId: uid,
            Field.homeSquadName: homeSquadName,
            Field.awaySquadName: awaySquadName,
            Field.courtId: courtId,
            Field.scheduledTime: Timestamp(date: scheduledTime),
            Field.status: SeasonGame.Status.scheduled.rawValue,
            Field.arrivedPlayerIds: [String](),
            Field.createdBy: uid,
            Field.createdAt: FieldValue.serverTimestamp(),
            Field.updatedAt: FieldValue.serverTimestamp(),
        ]

        do {
            try await reference.setData(fields)
            clearError()
            logger.notice("Created a season game at court \(courtId, privacy: .public)")
            return reference.documentID
        } catch {
            let gameError = Self.mapped(error)
            report(gameError, whileDoing: "setting up your match", context: .write)
            throw gameError
        }
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
