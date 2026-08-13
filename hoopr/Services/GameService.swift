import Combine
import FirebaseFirestore
import Foundation
import os

fileprivate let logger = Logger(subsystem: "com.hoopr", category: "GameService")

/// Owns the `games` collection — scheduled runs, and the first shared,
/// multi-user state in the app.
///
/// Follows `UserProfileService` closely, which is the house pattern for a
/// Firestore-backed service: it owns its own subscription to `AuthService`, so
/// one pair of listeners stays alive for the whole signed-in session rather
/// than being torn down every time the Local Runs tab is unmounted by a tab
/// switch. Firestore types never escape this file.
@MainActor
final class GameService: ObservableObject {
    /// Runs the signed-in user is confirmed in, host included, soonest first.
    @Published private(set) var queuedGames: [Game] = []

    /// Every discoverable upcoming run, soonest first. **Not** filtered by
    /// distance: courts live in the bundled dataset, not in Firestore, so the
    /// radius filter is a client-side join — see `LocalRunsViewModel`.
    @Published private(set) var publicGames: [Game] = []

    @Published private(set) var errorMessage: String?

    private enum Collection {
        static let games = "games"
    }

    /// Field names in one place so the write maps can't drift from `Game`'s
    /// coding keys, matching `UserProfileService`.
    private enum Field {
        static let id = "id"
        static let hostId = "hostId"
        static let courtId = "courtId"
        static let scheduledTime = "scheduledTime"
        static let isPublic = "isPublic"
        static let maxPlayers = "maxPlayers"
        static let status = "status"
        static let playerIds = "playerIds"
        static let queuedPlayerIds = "queuedPlayerIds"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
    }

    /// Caps on how much of each list is worth holding in memory. Both queries
    /// are ordered by `scheduledTime`, so a cap trims the far future rather
    /// than dropping something imminent.
    private enum Limit {
        static let queued = 50
        static let published = 100
    }

    /// Resolved lazily so the Firestore singleton is never touched before
    /// `FirebaseApp.configure()` has run.
    private lazy var database = Firestore.firestore()

    private var queuedListener: ListenerRegistration?
    private var publicListener: ListenerRegistration?
    private var observedUID: String?
    private var cancellables = Set<AnyCancellable>()

    /// Whether `errorMessage` came from a listener rather than from something
    /// the user just did.
    ///
    /// Only a load error is cleared by a later successful snapshot. An action's
    /// failure has to survive one: two listeners are open, and other people's
    /// joins produce snapshots continuously, so clearing on any success would
    /// wipe "couldn't join that run" off the screen milliseconds after it
    /// appeared.
    private var errorIsFromLoad = false

    /// The signed-in user, exposed so view models can tell "my run" from
    /// "someone else's" without reaching back into `AuthService`.
    var currentUserId: String? { observedUID }

    init(authService: AuthService) {
        authService.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                self?.handleAuthChange(to: user)
            }
            .store(in: &cancellables)
    }

    deinit {
        queuedListener?.remove()
        publicListener?.remove()
    }

    // MARK: - Session wiring

    private func handleAuthChange(to user: AuthenticatedUser?) {
        guard let user else {
            stopObserving()
            return
        }

        // Firebase re-emits the same user on token refresh; don't churn the
        // listeners when nothing actually changed.
        guard user.id != observedUID else { return }

        startObserving(user)
    }

    private func startObserving(_ user: AuthenticatedUser) {
        stopObserving()
        observedUID = user.id

        // Evaluated once, when the listeners attach. `Game.isVisible(at:)`
        // re-applies the same cutoff on every rebuild, which is what actually
        // retires a run during a long-lived session.
        let cutoff = Timestamp(date: Game.visibilityCutoff())

        queuedListener = database
            .collection(Collection.games)
            .whereField(Field.playerIds, arrayContains: user.id)
            .whereField(Field.scheduledTime, isGreaterThan: cutoff)
            .order(by: Field.scheduledTime)
            .limit(to: Limit.queued)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handle(snapshot, error: error, describing: "your runs") { service, games in
                        service.queuedGames = games
                    }
                }
            }

        publicListener = database
            .collection(Collection.games)
            .whereField(Field.isPublic, isEqualTo: true)
            .whereField(Field.scheduledTime, isGreaterThan: cutoff)
            .order(by: Field.scheduledTime)
            .limit(to: Limit.published)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handle(snapshot, error: error, describing: "nearby runs") { service, games in
                        service.publicGames = games
                    }
                }
            }
    }

    private func stopObserving() {
        queuedListener?.remove()
        queuedListener = nil
        publicListener?.remove()
        publicListener = nil
        observedUID = nil
        queuedGames = []
        publicGames = []
        clearError()
    }

    private func handle(
        _ snapshot: QuerySnapshot?,
        error: Error?,
        describing subject: String,
        assign: (GameService, [Game]) -> Void
    ) {
        if let error {
            report(Self.mapped(error), whileDoing: "loading \(subject)", fromLoad: true)
            return
        }

        assign(self, Self.decoded(snapshot))

        if errorIsFromLoad {
            clearError()
        }
    }

    /// Decodes per document rather than per snapshot: one row that drifted
    /// from the model shouldn't blank a whole list. The skipped document is
    /// logged so it's still discoverable.
    private static func decoded(_ snapshot: QuerySnapshot?) -> [Game] {
        guard let snapshot else { return [] }

        return snapshot.documents.compactMap { document in
            do {
                return try document.data(as: Game.self)
            } catch {
                logger.error(
                    "Skipping game \(document.documentID, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }
    }

    // MARK: - Writes

    /// Creates a run with the host as its first confirmed player.
    ///
    /// Everything the schema doesn't take from the organizer — `hostId`,
    /// `status`, the two rosters, and both timestamps — is derived here, so the
    /// creation form only ever collects the four fields a person can actually
    /// decide.
    func createGame(
        courtId: String,
        scheduledTime: Date,
        isPublic: Bool,
        maxPlayers: Int
    ) async throws {
        guard let uid = observedUID else { throw GameError.notSignedIn }

        // Rejected, not reshaped: silently clamping a bad roster size would
        // store something the organizer never chose.
        if let invalid = Game.validate(
            courtId: courtId,
            scheduledTime: scheduledTime,
            maxPlayers: maxPlayers
        ) {
            throw invalid
        }

        let roster = maxPlayers
        let reference = database.collection(Collection.games).document()

        let fields: [String: Any] = [
            Field.id: reference.documentID,
            Field.hostId: uid,
            Field.courtId: courtId,
            Field.scheduledTime: Timestamp(date: scheduledTime),
            Field.isPublic: isPublic,
            Field.maxPlayers: roster,
            Field.status: Game.status(playerCount: 1, maxPlayers: roster).rawValue,
            Field.playerIds: [uid],
            Field.queuedPlayerIds: [String](),
            Field.createdAt: FieldValue.serverTimestamp(),
            Field.updatedAt: FieldValue.serverTimestamp(),
        ]

        do {
            try await reference.setData(fields)
            clearError()
            logger.debug("Created run at court \(courtId, privacy: .public)")
        } catch {
            let gameError = Self.mapped(error)
            report(gameError, whileDoing: "starting your run")
            throw gameError
        }
    }

    /// Adds the signed-in user to a run — to the roster if there's room, to the
    /// waitlist if there isn't.
    ///
    /// Runs in a transaction rather than through `arrayUnion`: capacity has to
    /// be checked and `status` recomputed against the *same* read, or two
    /// players joining the last slot at once would both succeed and leave the
    /// roster over `maxPlayers` with a stale `open`.
    @discardableResult
    func joinGame(id gameId: String) async throws -> Bool {
        try await mutateRoster(gameId: gameId, joining: true)
    }

    /// Removes the signed-in user from a run's roster or waitlist.
    ///
    /// A freed slot is **not** handed to the first waitlisted player. Doing so
    /// would mean writing another user's uid into `playerIds`, which the update
    /// rule deliberately forbids — promotion needs either a host action or a
    /// Cloud Function, and neither exists yet.
    @discardableResult
    func leaveGame(id gameId: String) async throws -> Bool {
        try await mutateRoster(gameId: gameId, joining: false)
    }

    /// Deletes a run. Host only, enforced server-side.
    func cancelGame(id gameId: String) async throws {
        guard observedUID != nil else { throw GameError.notSignedIn }

        do {
            try await database.collection(Collection.games).document(gameId).delete()
            clearError()
        } catch {
            let gameError = Self.mapped(error)
            report(gameError, whileDoing: "canceling your run")
            throw gameError
        }
    }

    /// The single roster-mutating path. Both directions need the same
    /// read-modify-write under a transaction, and folding them together keeps
    /// the status recomputation in exactly one place.
    ///
    /// - Returns: `true` when the write changed something; `false` when the
    ///   user was already in the requested state, so the caller can stay quiet
    ///   instead of reporting a failure.
    private func mutateRoster(gameId: String, joining: Bool) async throws -> Bool {
        guard let uid = observedUID else { throw GameError.notSignedIn }

        let reference = database.collection(Collection.games).document(gameId)

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

                guard let data = snapshot.data(),
                      let maxPlayers = data[Field.maxPlayers] as? Int,
                      let hostId = data[Field.hostId] as? String,
                      var playerIds = data[Field.playerIds] as? [String],
                      var queuedPlayerIds = data[Field.queuedPlayerIds] as? [String] else {
                    return RosterOutcome.missing.rawValue
                }

                if joining {
                    guard !playerIds.contains(uid), !queuedPlayerIds.contains(uid) else {
                        return RosterOutcome.unchanged.rawValue
                    }
                    // A seat if there's one, the waitlist behind it if not.
                    if playerIds.count < maxPlayers {
                        playerIds.append(uid)
                    } else {
                        queuedPlayerIds.append(uid)
                    }
                } else {
                    // The host is structurally locked in — the rules require
                    // `hostId` to stay on the roster, so leaving would fail
                    // server-side. Cancelling is the host's exit.
                    guard hostId != uid else { return RosterOutcome.hostLocked.rawValue }
                    guard playerIds.contains(uid) || queuedPlayerIds.contains(uid) else {
                        return RosterOutcome.unchanged.rawValue
                    }
                    playerIds.removeAll { $0 == uid }
                    queuedPlayerIds.removeAll { $0 == uid }
                }

                transaction.updateData(
                    [
                        Field.playerIds: playerIds,
                        Field.queuedPlayerIds: queuedPlayerIds,
                        Field.status: Game.status(
                            playerCount: playerIds.count,
                            maxPlayers: maxPlayers
                        ).rawValue,
                        Field.updatedAt: FieldValue.serverTimestamp(),
                    ],
                    forDocument: reference
                )

                return RosterOutcome.changed.rawValue
            }

            clearError()

            switch RosterOutcome(rawValue: outcome as? String ?? "") {
            case .missing:
                throw GameError.gameNotFound
            case .hostLocked:
                throw GameError.gameClosed
            case .unchanged:
                return false
            default:
                return true
            }
        } catch let gameError as GameError {
            report(gameError, whileDoing: joining ? "joining the run" : "leaving the run")
            throw gameError
        } catch {
            let gameError = Self.mapped(error)
            report(gameError, whileDoing: joining ? "joining the run" : "leaving the run")
            throw gameError
        }
    }

    /// What a roster transaction decided. Carried out of the transaction block
    /// as its raw value because `runTransaction` hands back `Any?` — cleaner
    /// than boxing a domain error into an `NSError` just to unbox it again.
    private enum RosterOutcome: String {
        /// The rosters were rewritten — joined, waitlisted, or left.
        case changed
        /// Already in the requested state; nothing was written.
        case unchanged
        case missing
        /// The host tried to leave their own run. Cancelling is their exit.
        case hostLocked
    }

    // MARK: - Helpers

    /// Clears the banner and forgets where it came from, so a later snapshot
    /// can't resurrect stale provenance.
    private func clearError() {
        errorMessage = nil
        errorIsFromLoad = false
    }

    private func report(_ error: GameError, whileDoing action: String, fromLoad: Bool = false) {
        logger.error(
            "Game error while \(action, privacy: .public): \(String(describing: error), privacy: .public)"
        )
        errorMessage = Self.message(for: error, whileDoing: action)
        errorIsFromLoad = fromLoad
    }

    static func message(for error: GameError, whileDoing action: String) -> String {
        switch error {
        case .notSignedIn:      return "You're signed out."
        case .invalidCourt:     return "Pick a court for this run."
        case .invalidRoster:
            let range = Game.maxPlayersRange
            return "A run needs between \(range.lowerBound) and \(range.upperBound) players."
        case .scheduleTooSoon:  return "Pick a time at least 5 minutes from now."
        case .scheduleTooFar:   return "Runs can only be scheduled up to 30 days out."
        case .gameNotFound:     return "That run is no longer available."
        case .gameClosed:       return "That run isn't taking players right now."
        case .permissionDenied: return "Not allowed to access runs yet. Check the Firestore security rules."
        case .network:          return "Can't reach the network. Check your connection."
        case .unknown:          return "Something went wrong while \(action)."
        }
    }

    private static func mapped(_ error: Error) -> GameError {
        if let gameError = error as? GameError { return gameError }

        let nsError = error as NSError
        guard nsError.domain == FirestoreErrorDomain else {
            return .unknown(error.localizedDescription)
        }

        switch nsError.code {
        case FirestoreErrorCode.permissionDenied.rawValue:
            return .permissionDenied
        case FirestoreErrorCode.notFound.rawValue:
            return .gameNotFound
        case FirestoreErrorCode.unavailable.rawValue,
             FirestoreErrorCode.deadlineExceeded.rawValue:
            return .network
        default:
            return .unknown(error.localizedDescription)
        }
    }
}
