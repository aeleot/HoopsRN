import Combine
import FirebaseFirestore
import Foundation
import os

fileprivate let logger = Logger(subsystem: "com.hoopsrn", category: "FriendService")

/// Owns the `friendships` collection — the social graph, and the second piece
/// of shared, multi-user state after `games`.
///
/// Follows `UserProfileService` and `GameService`: it owns its own subscription
/// to `AuthService`, so its listeners stay alive for the whole signed-in
/// session rather than dying with whichever screen happened to open them.
/// Firestore types never escape this file.
///
/// **Names are not this service's business.** A friendship document carries
/// only uids; resolving them to profiles is `UserProfileService.profiles(for:)`,
/// which keeps "one service, one collection" literal.
@MainActor
final class FriendService: ObservableObject {
    /// Accepted friendships, most recently changed first.
    @Published private(set) var friends: [Friendship] = []

    /// Pending requests waiting on the signed-in user's answer.
    @Published private(set) var incomingRequests: [Friendship] = []

    /// Pending requests the signed-in user sent and can still cancel.
    @Published private(set) var outgoingRequests: [Friendship] = []

    @Published private(set) var errorMessage: String?

    /// A listener died and a re-attach is pending. Same exposure `GameService`
    /// has, and for the same reason — an empty list otherwise looks identical
    /// whether you have no friends or the query is broken.
    @Published private(set) var isRecovering = false

    private enum Collection {
        static let friendships = "friendships"
    }

    /// Identifies each listener to `supervisor`, which tracks their health
    /// separately — one of these dying must not be cancelled out by the other
    /// one still working.
    private enum ListenerKey {
        static let uidA = "uidA"
        static let uidB = "uidB"
    }

    /// Field names in one place so the write maps can't drift from
    /// `Friendship`'s coding keys, matching the other two services.
    ///
    /// There's deliberately no `id`: the document ID is derived from the pair
    /// and the rules' key allowlist rejects a document that carries one.
    private enum Field {
        static let uidA = "uidA"
        static let uidB = "uidB"
        static let requestedBy = "requestedBy"
        static let status = "status"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
    }

    /// Resolved lazily so the Firestore singleton is never touched before
    /// `FirebaseApp.configure()` has run.
    private lazy var database = Firestore.firestore()

    private var uidAListener: ListenerRegistration?
    private var uidBListener: ListenerRegistration?
    private var observedUID: String?
    private var cancellables = Set<AnyCancellable>()

    /// The two half-streams, kept separately so a snapshot from one doesn't
    /// discard what the other last delivered. Merged into the three published
    /// lists on every snapshot.
    private var edgesWhereFirst: [Friendship] = []
    private var edgesWhereSecond: [Friendship] = []

    /// Brings both listeners back after one of them dies. See
    /// `ListenerSupervisor` for why an error on a listener is always terminal.
    private let supervisor = ListenerSupervisor(subject: "friends")

    /// Whether `errorMessage` came from a listener rather than from something
    /// the user just did — the same distinction `GameService` draws, and for
    /// the same reason: two listeners are open and the other participant's
    /// actions produce snapshots on their own, so clearing the banner on any
    /// success would wipe "couldn't send that request" milliseconds after it
    /// appeared.
    private var errorIsFromLoad = false

    /// The signed-in user, exposed so view models can ask a `Friendship` which
    /// way it points without reaching back into `AuthService`.
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
        uidAListener?.remove()
        uidBListener?.remove()
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
    /// **Two queries, not one.** Which side of the pair you are depends on a
    /// lexicographic comparison with the *other* person's uid, so half your
    /// friendships store you in `uidA` and half in `uidB`. Firestore can't
    /// express "uidA == me OR uidB == me" in a single query, so both run and
    /// are merged below. No document can satisfy both — `uidA != uidB` is
    /// enforced by the create rule — so the merge is a concatenation, not a
    /// deduplication.
    ///
    /// Also the retry path, so a re-attach after one listener dies replaces
    /// both, matching `GameService`.
    private func attachListeners() {
        guard let uid = observedUID else { return }

        uidAListener?.remove()
        uidBListener?.remove()

        uidAListener = database
            .collection(Collection.friendships)
            .whereField(Field.uidA, isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handle(snapshot, error: error, listener: ListenerKey.uidA) { service, edges in
                        service.edgesWhereFirst = edges
                    }
                }
            }

        uidBListener = database
            .collection(Collection.friendships)
            .whereField(Field.uidB, isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handle(snapshot, error: error, listener: ListenerKey.uidB) { service, edges in
                        service.edgesWhereSecond = edges
                    }
                }
            }
    }

    private func stopObserving() {
        supervisor.cancel()
        isRecovering = false
        uidAListener?.remove()
        uidAListener = nil
        uidBListener?.remove()
        uidBListener = nil
        observedUID = nil
        edgesWhereFirst = []
        edgesWhereSecond = []
        friends = []
        incomingRequests = []
        outgoingRequests = []
        clearError()
    }

    /// Re-attaches now rather than waiting out the backoff.
    func retry() {
        supervisor.retryNow()
    }

    private func handle(
        _ snapshot: QuerySnapshot?,
        error: Error?,
        listener: String,
        assign: (FriendService, [Friendship]) -> Void
    ) {
        if let error {
            // The listener is already gone — see `ListenerSupervisor`.
            supervisor.recordFailure(for: listener)
            isRecovering = true
            report(Self.mapped(error), whileDoing: "loading your friends", context: .load)
            return
        }

        supervisor.recordSuccess(for: listener)
        // Mirrors the supervisor rather than assuming this one snapshot ended
        // the outage — the *other* listener may still be down.
        isRecovering = supervisor.isRecovering

        assign(self, Self.decoded(snapshot))
        rebuildLists()

        // Only once *both* listeners are healthy: clearing on this snapshot
        // alone would wipe the banner explaining why half the list is missing.
        if errorIsFromLoad, !supervisor.isRecovering {
            clearError()
        }
    }

    /// Decodes per document rather than per snapshot, matching
    /// `GameService.decoded`: one row that drifted from the model shouldn't
    /// blank a whole list.
    private static func decoded(_ snapshot: QuerySnapshot?) -> [Friendship] {
        guard let snapshot else { return [] }

        return snapshot.documents.compactMap { document in
            do {
                return try document.data(as: Friendship.self)
            } catch {
                logger.error(
                    "Skipping friendship \(document.documentID, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }
    }

    /// Splits the merged stream into the three lists the UI actually shows.
    ///
    /// `requestedBy` is what makes a pending edge directional — there is no
    /// stored "sent"/"received", precisely so the two sides can't disagree.
    private func rebuildLists() {
        guard let uid = observedUID else { return }

        let all = edgesWhereFirst + edgesWhereSecond
        let pending = all.filter { $0.status == .pending }

        friends = all
            .filter { $0.status == .accepted }
            .sorted { Self.sortDate($0.updatedAt) > Self.sortDate($1.updatedAt) }

        // Newest first, by when the request was made rather than when it last
        // changed — a pending edge's `updatedAt` never moves.
        incomingRequests = pending
            .filter { $0.requestedBy != uid }
            .sorted { Self.sortDate($0.createdAt) > Self.sortDate($1.createdAt) }

        outgoingRequests = pending
            .filter { $0.requestedBy == uid }
            .sorted { Self.sortDate($0.createdAt) > Self.sortDate($1.createdAt) }
    }

    /// Sorts an unresolved server timestamp to the **top**, not the bottom.
    ///
    /// Firestore delivers a local write's snapshot immediately, before the
    /// server has stamped it, so `nil` here means "written seconds ago" — the
    /// newest thing in the list. Treating it as `.distantPast` would drop the
    /// row the user just created to the bottom and then jump it back up when
    /// the server acknowledged.
    private static func sortDate(_ date: Date?) -> Date {
        date ?? .distantFuture
    }

    // MARK: - Writes

    /// Sends a friend request to `otherUid`.
    ///
    /// Handles the simultaneous-request collision: if the other person asked
    /// first and their request hasn't been answered yet, the create is refused
    /// by the update rule (its `requestedBy` doesn't match what's stored), and
    /// that refusal is turned into an *accept* rather than an error. Asking
    /// someone who has already asked you is, in substance, saying yes.
    func sendRequest(to otherUid: String) async throws {
        guard let uid = observedUID else { throw FriendError.notSignedIn }

        // Checked here as well as in the rules: the rules reject it as
        // `permission-denied`, which reads like an undeployed ruleset rather
        // than a self-directed request.
        guard otherUid != uid else { throw FriendError.cannotFriendSelf }

        let id = Friendship.id(for: uid, otherUid)
        let reference = database.collection(Collection.friendships).document(id)
        let pair = [uid, otherUid].sorted()

        let fields: [String: Any] = [
            Field.uidA: pair[0],
            Field.uidB: pair[1],
            Field.requestedBy: uid,
            Field.status: Friendship.Status.pending.rawValue,
            Field.createdAt: FieldValue.serverTimestamp(),
            Field.updatedAt: FieldValue.serverTimestamp(),
        ]

        do {
            try await reference.setData(fields)
            clearError()
            logger.debug("Sent a friend request")
        } catch {
            let friendError = Self.mapped(error)

            // Only a rules refusal can be the collision — a create against an
            // existing document falls through to the tighter update allowlist,
            // which rejects it. Anything else is a real failure.
            if friendError == .permissionDenied,
               let existing = await existingEdge(at: reference),
               try await resolve(existing, requestedFrom: otherUid) {
                return
            }

            report(friendError, whileDoing: "sending that request", context: .write)
            throw friendError
        }
    }

    /// Accepts a pending request. Only the participant who *didn't* send it may
    /// call this — the requester spent their one move creating the document,
    /// which the update rule enforces server-side.
    func acceptRequest(_ friendshipId: String) async throws {
        try await update(
            friendshipId,
            to: .accepted,
            whileDoing: "accepting that request"
        )
    }

    /// Refuses a request someone sent you. Deletes the edge.
    func declineRequest(_ friendshipId: String) async throws {
        try await deleteEdge(friendshipId, whileDoing: "declining that request")
    }

    /// Withdraws a request you sent. Deletes the edge.
    func cancelRequest(_ friendshipId: String) async throws {
        try await deleteEdge(friendshipId, whileDoing: "canceling that request")
    }

    /// Ends an accepted friendship. Deletes the edge.
    func removeFriend(_ friendshipId: String) async throws {
        try await deleteEdge(friendshipId, whileDoing: "removing that friend")
    }

    /// The single delete path behind decline, cancel, and unfriend.
    ///
    /// All three are one operation server-side — either participant may remove
    /// the edge — and are separate methods only so call sites and logs stay
    /// honest about which situation they're in.
    private func deleteEdge(_ friendshipId: String, whileDoing action: String) async throws {
        guard observedUID != nil else { throw FriendError.notSignedIn }

        do {
            try await database.collection(Collection.friendships).document(friendshipId).delete()
            clearError()
        } catch {
            let friendError = Self.mapped(error)
            report(friendError, whileDoing: action, context: .write)
            throw friendError
        }
    }

    /// The one legal transition: `pending` → `accepted`.
    private func update(
        _ friendshipId: String,
        to status: Friendship.Status,
        whileDoing action: String
    ) async throws {
        guard observedUID != nil else { throw FriendError.notSignedIn }

        do {
            try await database.collection(Collection.friendships).document(friendshipId).updateData([
                Field.status: status.rawValue,
                Field.updatedAt: FieldValue.serverTimestamp(),
            ])
            clearError()
        } catch {
            let friendError = Self.mapped(error)
            report(friendError, whileDoing: action, context: .write)
            throw friendError
        }
    }

    /// Reads back an edge whose create was refused, to tell a collision from a
    /// genuine rejection.
    ///
    /// Silent on failure by design: if the read is refused too, the ruleset
    /// isn't deployed (or this isn't our document), and the caller should
    /// surface the original write error rather than this one.
    private func existingEdge(at reference: DocumentReference) async -> Friendship? {
        do {
            let snapshot = try await reference.getDocument()
            guard snapshot.exists else { return nil }
            return try snapshot.data(as: Friendship.self)
        } catch {
            logger.debug("Couldn't read back the refused friendship: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Decides what a refused `sendRequest` actually meant, given the document
    /// that was already there.
    ///
    /// The document read back is necessarily about this same pair — the create
    /// rule ties the ID to `uidA_uidB` — so there are only three possibilities,
    /// and none of them is an error worth showing.
    ///
    /// - Returns: `true` when the situation is resolved and the caller should
    ///   report success; `false` when the refusal was real and should surface.
    private func resolve(_ existing: Friendship, requestedFrom otherUid: String) async throws -> Bool {
        switch existing.status {
        case .pending where existing.requestedBy == otherUid:
            // They asked first. Answering is what the user meant by asking.
            logger.debug("Request collided with an incoming one; accepting instead")
            try await acceptRequest(existing.id)
            return true
        case .pending, .accepted:
            // Already sent, or already friends — a duplicate tap from a stale
            // screen. Nothing to write and nothing to complain about.
            clearError()
            return true
        }
    }

    // MARK: - Helpers

    /// Clears the banner and forgets where it came from, so a later snapshot
    /// can't resurrect stale provenance.
    private func clearError() {
        errorMessage = nil
        errorIsFromLoad = false
    }

    private func report(_ error: FriendError, whileDoing action: String, context: FailureContext) {
        logger.error(
            "Friend error while \(action, privacy: .public): \(String(describing: error), privacy: .public)"
        )
        errorMessage = Self.message(for: error, whileDoing: action, context: context)
        errorIsFromLoad = context == .load
    }

    /// The user-facing sentence for a failure.
    ///
    /// `context` disambiguates `permission-denied`, which Firestore returns
    /// both for "the ruleset was never deployed" and for "the rules rejected
    /// this" — but the read rule here is narrower than `users`' or `games`',
    /// so the reasoning differs from theirs even though the conclusion doesn't:
    ///
    /// - A friendship is readable only by its two participants, so "any signed-
    ///   in user may read" isn't the argument. The argument is that both
    ///   listeners filter on the caller's own uid, so they never *ask* for a
    ///   document the caller isn't a participant of — a denied read is a
    ///   document we were entitled to, refused, which means the server isn't
    ///   running the rules in this repo.
    /// - A denied **write** was checked client-side first, so it's the server
    ///   rejecting something the client believed was legal: the edge changed
    ///   underneath the screen, or a genuine authorization bug.
    nonisolated static func message(
        for error: FriendError,
        whileDoing action: String,
        context: FailureContext
    ) -> String {
        switch error {
        case .notSignedIn:       return FailureText.signedOut
        case .cannotFriendSelf:  return "You can't add yourself."
        case .requestNotFound:   return "That request is no longer there."
        case .permissionDenied:
            switch context {
            case .load:
                return FailureText.rulesNotDeployed(loading: "your friends")
            case .write:
                return "The server wouldn't accept that change. This may have changed since it loaded."
            }
        case .indexRequired:
            return "This list needs a database index that's still being built."
        case .network:           return FailureText.network
        case .unknown:           return "Something went wrong while \(action)."
        }
    }

    /// Names what `FirestoreFailure` classified, in this collection's terms.
    ///
    /// `notFound` is a real case here, unlike on the profile document: an edge
    /// can be deleted by the other participant while its row is on screen, so
    /// an accept or a decline can arrive after there's nothing left to act on.
    private static func mapped(_ error: Error) -> FriendError {
        if let friendError = error as? FriendError { return friendError }

        switch FirestoreFailure.classify(error) {
        case .permissionDenied:         return .permissionDenied
        case .notFound:                 return .requestNotFound
        case .indexRequired:            return .indexRequired
        case .network:                  return .network
        case .unknown(let description): return .unknown(description)
        }
    }
}
