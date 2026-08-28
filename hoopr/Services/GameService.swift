import Combine
import FirebaseFirestore
import Foundation
import os

fileprivate let logger = Logger(subsystem: "com.hoopsrn", category: "GameService")

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

    /// A listener died and a re-attach is pending. Mirrors `supervisor` so the
    /// UI can offer "Try again" instead of leaving the user to guess whether
    /// an empty list is empty or broken.
    @Published private(set) var isRecovering = false

    /// True once either listener has delivered a snapshot successfully.
    ///
    /// Distinguishes "there are no runs today" from "Firestore hasn't answered
    /// yet", which `@Published`'s replay-on-subscribe otherwise makes
    /// indistinguishable: both read as an empty array. The map picks its
    /// opening segment on this rather than on `onAppear`, where the answer is
    /// always the empty one.
    ///
    /// Set only on the success path in `handle(_:error:listener:describing:)`,
    /// so a listener that failed never claims to have loaded.
    @Published private(set) var hasLoadedGames = false

    private enum Collection {
        static let games = "games"
    }

    /// Identifies each listener to `supervisor`, which tracks their health
    /// separately — one of these dying must not be cancelled out by the other
    /// one still working.
    private enum ListenerKey {
        static let queued = "queued"
        static let published = "public"
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

    /// Brings both listeners back after one of them dies. See
    /// `ListenerSupervisor` for why an error on a listener is always terminal.
    private let supervisor = ListenerSupervisor(subject: "games")

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

        // Weak: this service owns the supervisor, so a strong capture here
        // would be a cycle.
        supervisor.onRetry = { [weak self] in
            self?.attachListeners()
        }
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
        attachListeners()
    }

    /// Opens both listeners, replacing any already open.
    ///
    /// Also the retry path, so a re-attach after one listener dies replaces
    /// *both*. Supervising them separately would save one cheap re-attach and
    /// cost a second set of backoff state; a healthy listener re-attaching just
    /// re-delivers its snapshot from cache.
    private func attachListeners() {
        guard let uid = observedUID else { return }

        queuedListener?.remove()
        publicListener?.remove()

        // Recomputed per attach rather than captured once at sign-in, so a
        // listener re-attached hours later doesn't query yesterday's window.
        // `Game.isVisible(at:)` re-applies the same cutoff on every rebuild,
        // which is what actually retires a run mid-session.
        let cutoff = Timestamp(date: Game.visibilityCutoff())

        queuedListener = database
            .collection(Collection.games)
            .whereField(Field.playerIds, arrayContains: uid)
            .whereField(Field.scheduledTime, isGreaterThan: cutoff)
            .order(by: Field.scheduledTime)
            .limit(to: Limit.queued)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handle(
                        snapshot,
                        error: error,
                        listener: ListenerKey.queued,
                        describing: "your runs"
                    ) { service, games in
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
                    self?.handle(
                        snapshot,
                        error: error,
                        listener: ListenerKey.published,
                        describing: "nearby runs"
                    ) { service, games in
                        service.publicGames = games
                    }
                }
            }
    }

    private func stopObserving() {
        supervisor.cancel()
        isRecovering = false
        queuedListener?.remove()
        queuedListener = nil
        publicListener?.remove()
        publicListener = nil
        observedUID = nil
        queuedGames = []
        publicGames = []
        // Signing out discards the snapshots, so the next session has to wait
        // for its own before deciding anything.
        hasLoadedGames = false
        clearError()
    }

    /// Re-attaches now rather than waiting out the backoff. Backs the "Try
    /// again" button on the Local Runs error banner.
    func retry() {
        supervisor.retryNow()
    }

    private func handle(
        _ snapshot: QuerySnapshot?,
        error: Error?,
        listener: String,
        describing subject: String,
        assign: (GameService, [Game]) -> Void
    ) {
        if let error {
            // The listener is already gone — see `ListenerSupervisor`.
            supervisor.recordFailure(for: listener)
            isRecovering = true
            report(Self.mapped(error), whileDoing: "loading \(subject)", context: .load)
            return
        }

        supervisor.recordSuccess(for: listener)
        // Mirrors the supervisor rather than assuming this one snapshot ended
        // the outage — the *other* listener may still be down.
        isRecovering = supervisor.isRecovering

        assign(self, Self.decoded(snapshot))
        // After `assign`, and only on this path: a listener that errored
        // returned above, so an outage can never look like a loaded empty list.
        hasLoadedGames = true

        // Only once *both* listeners are healthy. Clearing on this snapshot
        // alone would wipe the banner explaining why the other list is empty.
        if errorIsFromLoad, !supervisor.isRecovering {
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
    ///
    /// - Returns: the new run's document ID, which is also its `Game.id` — the
    ///   create form needs it to show an invite link for a private run, and the
    ///   listener that will deliver the run itself arrives a round trip later.
    @discardableResult
    func createGame(
        courtId: String,
        scheduledTime: Date,
        isPublic: Bool,
        maxPlayers: Int
    ) async throws -> String {
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
            return reference.documentID
        } catch {
            let gameError = Self.mapped(error)
            report(gameError, whileDoing: "starting your run", context: .write)
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
            report(gameError, whileDoing: "canceling your run", context: .write)
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
            report(gameError, whileDoing: joining ? "joining the run" : "leaving the run", context: .write)
            throw gameError
        } catch {
            let gameError = Self.mapped(error)
            report(gameError, whileDoing: joining ? "joining the run" : "leaving the run", context: .write)
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

    private func report(_ error: GameError, whileDoing action: String, context: FailureContext) {
        logger.error(
            "Game error while \(action, privacy: .public): \(String(describing: error), privacy: .public)"
        )
        errorMessage = Self.message(for: error, whileDoing: action, context: context)
        errorIsFromLoad = context == .load
    }

    /// The user-facing sentence for a failure.
    ///
    /// `context` exists for exactly one case. Firestore returns the same
    /// `permission-denied` whether the ruleset was never deployed or the rules
    /// deliberately rejected what was asked, and the two can't be told apart
    /// from the error — but they can be told apart by *what failed*:
    ///
    /// - A **read** that's denied was one of two queries shaped to match the
    ///   read rule for any signed-in user. If that's refused, the rules the
    ///   server is running aren't the rules in this repo — a deployment
    ///   problem, and the listener is already being re-attached.
    /// - A **write** that's denied was checked client-side first (see
    ///   `Game.validate`), so the server rejected something the client thought
    ///   was legal: a stale roster, a run cancelled underneath it, or a genuine
    ///   authorization bug. Blaming deployment there would send you to the
    ///   wrong file, which is the whole reason this parameter exists.
    nonisolated static func message(
        for error: GameError,
        whileDoing action: String,
        context: FailureContext
    ) -> String {
        switch error {
        case .notSignedIn:      return FailureText.signedOut
        case .invalidCourt:     return "Pick a court for this run."
        case .invalidRoster:
            let range = Game.maxPlayersRange
            return "A run needs between \(range.lowerBound) and \(range.upperBound) players."
        case .scheduleTooSoon:  return "Pick a time at least 5 minutes from now."
        case .scheduleTooFar:   return "Runs can only be scheduled up to 30 days out."
        case .gameNotFound:     return "That run is no longer available."
        case .gameClosed:       return "That run isn't taking players right now."
        case .permissionDenied:
            switch context {
            case .load:
                return FailureText.rulesNotDeployed(loading: "runs")
            case .write:
                return "The server wouldn't accept that change. This run may have changed since it loaded."
            }
        case .indexRequired:
            return "This list needs a database index that's still being built."
        case .network:          return FailureText.network
        case .unknown:          return "Something went wrong while \(action)."
        }
    }

    /// Names what `FirestoreFailure` classified, in this collection's terms.
    ///
    /// Both list queries are composite (an equality or array-contains, plus a
    /// range and an order), so each needs an index — which is why
    /// `.indexRequired` is a case a run can actually hit, unlike on the profile
    /// document.
    private static func mapped(_ error: Error) -> GameError {
        if let gameError = error as? GameError { return gameError }

        switch FirestoreFailure.classify(error) {
        case .permissionDenied:         return .permissionDenied
        case .notFound:                 return .gameNotFound
        case .indexRequired:            return .indexRequired
        case .network:                  return .network
        case .unknown(let description): return .unknown(description)
        }
    }
}
