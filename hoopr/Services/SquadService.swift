import Combine
import FirebaseFirestore
import Foundation
import os

fileprivate let logger = Logger(subsystem: "com.hoopsrn", category: "SquadService")

/// Owns the `squads` and `squadInvites` collections — the teams that queue for
/// season matches, and the standing offers that let someone join one.
///
/// Follows `FriendService` closely, which is the house pattern for a Firestore-
/// backed service: it owns its own subscription to `AuthService`, so its
/// listeners stay alive for the whole signed-in session rather than dying with
/// whichever screen happened to open them. Firestore types never escape this
/// file.
///
/// **Two collections, one service, and that's deliberate** — it's the one place
/// this departs from "one service, one collection". A `squadInvite` has no
/// independent existence: it is created against a squad, consumed by a write to
/// that same squad, and deleted in the same breath. Splitting it out would put
/// the two halves of a single transaction in two objects that, by house rule,
/// aren't allowed to depend on each other.
///
/// **Names are not this service's business.** A squad carries uids; resolving
/// them to profiles is `UserProfileService.profiles(for:)`, and joining invites
/// to the friends list for the invite picker is `SquadViewModel`'s job — a
/// cross-collection join, so it lives in a view model.
@MainActor
final class SquadService: ObservableObject {
    /// Squads the signed-in user is on, leader or member, most recently
    /// changed first.
    @Published private(set) var squads: [Squad] = []

    /// Invites waiting on the signed-in user's answer, newest first.
    @Published private(set) var incomingInvites: [SquadInvite] = []

    /// Invites the signed-in user sent as a leader and can still revoke.
    /// Feeds the invite picker, which excludes anyone already asked.
    @Published private(set) var sentInvites: [SquadInvite] = []

    @Published private(set) var errorMessage: String?

    /// A listener died and a re-attach is pending. Same exposure the other two
    /// services have, and for the same reason — an empty list otherwise looks
    /// identical whether you have no squads or the query is broken.
    @Published private(set) var isRecovering = false

    /// True once the squads listener has delivered a snapshot successfully.
    ///
    /// Distinguishes "you're not on a squad" from "Firestore hasn't answered
    /// yet", which `@Published`'s replay-on-subscribe otherwise makes
    /// indistinguishable: both read as an empty array. The Seasons tab picks
    /// between its hero empty state and a spinner on this.
    @Published private(set) var hasLoadedSquads = false

    private enum Collection {
        static let squads = "squads"
        static let squadInvites = "squadInvites"
    }

    /// Identifies each listener to `supervisor`, which tracks their health
    /// separately — one of these dying must not be cancelled out by another
    /// still working.
    private enum ListenerKey {
        static let squads = "squads"
        static let incomingInvites = "incomingInvites"
        static let sentInvites = "sentInvites"
    }

    /// Field names in one place so the write maps can't drift from `Squad`'s
    /// and `SquadInvite`'s coding keys, matching the other three services.
    ///
    /// There's deliberately no `id` under `invite`: an invite's document ID is
    /// derived from its own content and the rules' key allowlist rejects a
    /// document that carries one, exactly as on `friendships`.
    private enum Field {
        static let id = "id"
        static let name = "name"
        static let nameLower = "nameLower"
        static let leaderId = "leaderId"
        static let memberIds = "memberIds"
        static let format = "format"
        static let iconKey = "iconKey"
        static let colorKey = "colorKey"
        static let region = "region"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"

        static let squadId = "squadId"
        static let uid = "uid"
        static let invitedBy = "invitedBy"
    }

    /// Caps on how much of each list is worth holding in memory. A person is
    /// on a handful of squads and has a handful of invites; these are sanity
    /// limits, not pagination.
    private enum Limit {
        static let squads = 20
        static let invites = 100
    }

    /// Resolved lazily so the Firestore singleton is never touched before
    /// `FirebaseApp.configure()` has run.
    private lazy var database = Firestore.firestore()

    private var squadsListener: ListenerRegistration?
    private var incomingInvitesListener: ListenerRegistration?
    private var sentInvitesListener: ListenerRegistration?
    private var observedUID: String?
    private var cancellables = Set<AnyCancellable>()

    /// Brings the listeners back after one of them dies. See
    /// `ListenerSupervisor` for why an error on a listener is always terminal.
    private let supervisor = ListenerSupervisor(subject: "squads")

    /// Whether `errorMessage` came from a listener rather than from something
    /// the user just did — the same distinction the other services draw, and
    /// for the same reason: three listeners are open and other people's
    /// actions produce snapshots on their own, so clearing the banner on any
    /// success would wipe "couldn't send that invite" milliseconds after it
    /// appeared.
    private var errorIsFromLoad = false

    /// The signed-in user, exposed so view models can ask whether a squad is
    /// theirs to lead without reaching back into `AuthService`.
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
        squadsListener?.remove()
        incomingInvitesListener?.remove()
        sentInvitesListener?.remove()
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

    /// Opens all three listeners, replacing any already open. Also the retry
    /// path, so a re-attach after one dies replaces them all, matching
    /// `GameService` and `FriendService`.
    ///
    /// **None of these needs a composite index.** Each is a single equality or
    /// `array-contains` filter with no ordering — sorting happens client-side
    /// in `rebuildLists`, on lists that are a handful of rows long. That's the
    /// same trade `FriendService` makes, and the reason `firestore.indexes.json`
    /// is untouched by this collection.
    private func attachListeners() {
        guard let uid = observedUID else { return }

        squadsListener?.remove()
        incomingInvitesListener?.remove()
        sentInvitesListener?.remove()

        squadsListener = database
            .collection(Collection.squads)
            .whereField(Field.memberIds, arrayContains: uid)
            .limit(to: Limit.squads)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handle(
                        snapshot,
                        error: error,
                        listener: ListenerKey.squads,
                        describing: "your squads"
                    ) { service in
                        service.squads = Self.decoded(snapshot, as: Squad.self)
                            .sorted { Self.sortDate($0.updatedAt) > Self.sortDate($1.updatedAt) }
                        service.hasLoadedSquads = true
                    }
                }
            }

        incomingInvitesListener = database
            .collection(Collection.squadInvites)
            .whereField(Field.uid, isEqualTo: uid)
            .limit(to: Limit.invites)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handle(
                        snapshot,
                        error: error,
                        listener: ListenerKey.incomingInvites,
                        describing: "your squad invites"
                    ) { service in
                        service.incomingInvites = Self.decoded(snapshot, as: SquadInvite.self)
                            .sorted { Self.sortDate($0.createdAt) > Self.sortDate($1.createdAt) }
                    }
                }
            }

        sentInvitesListener = database
            .collection(Collection.squadInvites)
            .whereField(Field.invitedBy, isEqualTo: uid)
            .limit(to: Limit.invites)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handle(
                        snapshot,
                        error: error,
                        listener: ListenerKey.sentInvites,
                        describing: "your squad invites"
                    ) { service in
                        service.sentInvites = Self.decoded(snapshot, as: SquadInvite.self)
                            .sorted { Self.sortDate($0.createdAt) > Self.sortDate($1.createdAt) }
                    }
                }
            }
    }

    private func stopObserving() {
        supervisor.cancel()
        isRecovering = false
        squadsListener?.remove()
        squadsListener = nil
        incomingInvitesListener?.remove()
        incomingInvitesListener = nil
        sentInvitesListener?.remove()
        sentInvitesListener = nil
        observedUID = nil
        squads = []
        incomingInvites = []
        sentInvites = []
        hasLoadedSquads = false
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
        describing subject: String,
        assign: (SquadService) -> Void
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
        // the outage — another listener may still be down.
        isRecovering = supervisor.isRecovering

        assign(self)

        // Only once *every* listener is healthy: clearing on this snapshot
        // alone would wipe the banner explaining why half the screen is empty.
        if errorIsFromLoad, !supervisor.isRecovering {
            clearError()
        }
    }

    /// Decodes per document rather than per snapshot, matching
    /// `GameService.decoded`: one row that drifted from the model shouldn't
    /// blank a whole list.
    private static func decoded<T: Decodable>(_ snapshot: QuerySnapshot?, as type: T.Type) -> [T] {
        guard let snapshot else { return [] }

        return snapshot.documents.compactMap { document in
            do {
                return try document.data(as: T.self)
            } catch {
                logger.error(
                    "Skipping \(String(describing: type), privacy: .public) \(document.documentID, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }
    }

    /// Sorts an unresolved server timestamp to the **top**, not the bottom.
    ///
    /// Firestore delivers a local write's snapshot immediately, before the
    /// server has stamped it, so `nil` here means "written seconds ago" — the
    /// newest thing in the list. The same reasoning as `FriendService.sortDate`.
    private static func sortDate(_ date: Date?) -> Date {
        date ?? .distantFuture
    }

    // MARK: - Reads

    /// The squad with this ID from the loaded list, if the signed-in user is
    /// on it. Not a fetch — the listener already holds every squad this user
    /// belongs to, and a detail screen shouldn't open a second read for a
    /// document it's already watching.
    func squad(id: String) -> Squad? {
        squads.first { $0.id == id }
    }

    /// Invites already sent for `squadId`, so the picker can leave those
    /// people out rather than offering an invite that would be refused.
    func pendingInvites(for squadId: String) -> [SquadInvite] {
        sentInvites.filter { $0.squadId == squadId }
    }

    /// A one-off read of a squad the signed-in user is **not** on.
    ///
    /// The listener only carries squads you're a member of, and an invite
    /// names one you aren't — so "Rim Reapers invited you" needs a read the
    /// listener can't provide. Legal because `squads` is readable by any
    /// signed-in account, which is the same reason an opponent can render your
    /// crest; see the read rule's comment.
    ///
    /// Returns `nil` for a squad that was disbanded between the invite landing
    /// and this call, which is a real race — the invite outlives the squad by
    /// however long it takes the leader's delete to reach the invitee.
    func fetchSquad(id squadId: String) async throws -> Squad? {
        guard observedUID != nil else { throw SquadError.notSignedIn }

        do {
            let snapshot = try await database
                .collection(Collection.squads)
                .document(squadId)
                .getDocument()
            guard snapshot.exists else { return nil }
            return try snapshot.data(as: Squad.self)
        } catch let decodingError as DecodingError {
            // A drifted document, not a failed read. Skipped rather than
            // surfaced, matching `decoded(_:as:)` — one bad row shouldn't take
            // a screen down.
            logger.error(
                "Skipping squad \(squadId, privacy: .public): \(decodingError.localizedDescription, privacy: .public)"
            )
            return nil
        } catch {
            throw Self.mapped(error)
        }
    }

    // MARK: - Writes

    /// Creates a squad with the signed-in user as its leader and only member.
    ///
    /// Everyone else arrives through `acceptInvite` — a squad can't be created
    /// with a roster, because that would mean writing other people's uids.
    ///
    /// - Parameter region: the matchmaking pool key, `Court.city` of the
    ///   leader's nearest court. Passed in rather than derived here: deriving
    ///   it needs `CourtService` and `LocationService`, and services in this
    ///   app don't depend on each other.
    /// - Returns: the new squad's document ID.
    @discardableResult
    func createSquad(
        name rawName: String,
        format: SquadFormat,
        iconKey: String,
        colorKey: String,
        region: String
    ) async throws -> String {
        guard let uid = observedUID else { throw SquadError.notSignedIn }

        try requireNoOtherSquad(whileDoing: "creating your squad")

        let name = Squad.normalizedName(rawName)

        // Rejected, not reshaped: silently truncating a too-long name would
        // store something the leader never chose.
        if let invalid = Squad.validate(
            name: name,
            format: format,
            iconKey: iconKey,
            colorKey: colorKey,
            region: region
        ) {
            throw invalid
        }

        let reference = database.collection(Collection.squads).document()

        let fields: [String: Any] = [
            Field.id: reference.documentID,
            Field.name: name,
            Field.nameLower: Squad.searchKey(name),
            Field.leaderId: uid,
            Field.memberIds: [uid],
            Field.format: format.rawValue,
            Field.iconKey: iconKey,
            Field.colorKey: colorKey,
            Field.region: region,
            Field.createdAt: FieldValue.serverTimestamp(),
            Field.updatedAt: FieldValue.serverTimestamp(),
        ]

        do {
            try await reference.setData(fields)
            clearError()
            logger.debug("Created a squad in region \(region, privacy: .public)")
            return reference.documentID
        } catch {
            let squadError = Self.mapped(error)
            report(squadError, whileDoing: "creating your squad", context: .write)
            throw squadError
        }
    }

    /// Renames a squad and restyles its crest. Leader only, enforced
    /// server-side by a rule that can't touch `memberIds` at all.
    func editSquad(
        id squadId: String,
        name rawName: String,
        iconKey: String,
        colorKey: String
    ) async throws {
        guard observedUID != nil else { throw SquadError.notSignedIn }

        let name = Squad.normalizedName(rawName)

        if let invalid = Squad.validate(name: name) { throw invalid }
        guard Squad.iconKeys.contains(iconKey) else { throw SquadError.unknownIcon }
        guard Squad.colorKeys.contains(colorKey) else { throw SquadError.unknownColor }

        do {
            try await database.collection(Collection.squads).document(squadId).updateData([
                Field.name: name,
                Field.nameLower: Squad.searchKey(name),
                Field.iconKey: iconKey,
                Field.colorKey: colorKey,
                Field.updatedAt: FieldValue.serverTimestamp(),
            ])
            clearError()
        } catch {
            let squadError = Self.mapped(error)
            report(squadError, whileDoing: "saving your squad", context: .write)
            throw squadError
        }
    }

    /// Disbands a squad. Leader only, enforced server-side.
    ///
    /// The leader's exit, the same way cancelling is a `games` host's — the
    /// self-leave rule refuses a leader precisely so there's one answer to
    /// "what happens to the squad when the person who made it goes."
    func disbandSquad(id squadId: String) async throws {
        guard observedUID != nil else { throw SquadError.notSignedIn }

        do {
            try await database.collection(Collection.squads).document(squadId).delete()
            clearError()
        } catch {
            let squadError = Self.mapped(error)
            report(squadError, whileDoing: "disbanding your squad", context: .write)
            throw squadError
        }
    }

    /// Invites `otherUid` to `squadId`. Leader only, and only someone the
    /// leader is already friends with — both enforced server-side.
    ///
    /// A second invite to the same person writes the same document ID, which
    /// the rules refuse because the document already exists. That refusal is
    /// read back and treated as success rather than surfaced, the same move
    /// `FriendService.sendRequest` makes for a colliding request: a duplicate
    /// tap from a stale screen isn't a failure.
    func invite(_ otherUid: String, to squadId: String) async throws {
        guard let uid = observedUID else { throw SquadError.notSignedIn }
        guard otherUid != uid else { throw SquadError.cannotInviteSelf }

        let id = SquadInvite.id(for: squadId, otherUid)
        let reference = database.collection(Collection.squadInvites).document(id)

        let fields: [String: Any] = [
            Field.squadId: squadId,
            Field.uid: otherUid,
            Field.invitedBy: uid,
            Field.createdAt: FieldValue.serverTimestamp(),
        ]

        do {
            try await reference.setData(fields)
            clearError()
            logger.debug("Invited a friend to a squad")
        } catch {
            let squadError = Self.mapped(error)

            // Only a rules refusal can be the duplicate — a create against an
            // existing document falls through to `allow update: if false`,
            // which rejects it. Anything else is a real failure.
            if squadError == .permissionDenied, await inviteExists(at: reference) {
                clearError()
                logger.debug("Invite already sent; nothing to write")
                return
            }

            report(squadError, whileDoing: "sending that invite", context: .write)
            throw squadError
        }
    }

    /// Reads back an invite whose create was refused, to tell a duplicate from
    /// a genuine rejection.
    ///
    /// Silent on failure by design: if the read is refused too, the ruleset
    /// isn't deployed (or this isn't our invite), and the caller should surface
    /// the original write error rather than this one.
    private func inviteExists(at reference: DocumentReference) async -> Bool {
        do {
            return try await reference.getDocument().exists
        } catch {
            logger.debug("Couldn't read back the refused invite: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Withdraws an invite you sent. Deletes the document.
    func revokeInvite(_ inviteId: String) async throws {
        try await deleteInvite(inviteId, whileDoing: "revoking that invite")
    }

    /// Refuses an invite someone sent you. Deletes the document.
    func declineInvite(_ inviteId: String) async throws {
        try await deleteInvite(inviteId, whileDoing: "declining that invite")
    }

    /// Joins the squad an invite names, then consumes the invite.
    ///
    /// The two writes are deliberately **not** atomic. The join is the one that
    /// matters and it's the one under a transaction; the delete is bookkeeping,
    /// and a leftover invite grants nothing the caller doesn't already have —
    /// they're a member. So a failed delete is logged and swallowed rather than
    /// undoing a join that succeeded.
    ///
    /// Refused while the caller is on a *different* squad — see
    /// `Squad.membershipBlock`. The invite is left where it is, so leaving that
    /// squad and accepting again works. An invite to the squad they're already
    /// on isn't refused: that's a leftover from a join whose cleanup failed,
    /// and consuming it is exactly what the `false` return below is for.
    ///
    /// - Returns: `true` when the roster changed; `false` when the caller was
    ///   already a member, so the caller can stay quiet instead of reporting a
    ///   failure.
    @discardableResult
    func acceptInvite(_ invite: SquadInvite) async throws -> Bool {
        try requireNoOtherSquad(joining: invite.squadId, whileDoing: "joining the squad")

        let joined = try await mutateRoster(squadId: invite.squadId, joining: true)

        do {
            try await database.collection(Collection.squadInvites).document(invite.id).delete()
        } catch {
            logger.error(
                "Joined the squad but couldn't clear the invite: \(error.localizedDescription, privacy: .public)"
            )
        }

        return joined
    }

    /// Leaves a squad. Refused for the leader — disbanding is their exit.
    @discardableResult
    func leaveSquad(id squadId: String) async throws -> Bool {
        try await mutateRoster(squadId: squadId, joining: false)
    }

    /// The single delete path behind revoke and decline.
    ///
    /// Both are one operation server-side — either participant may remove the
    /// document — and are separate methods only so call sites and logs stay
    /// honest about which situation they're in, exactly as on `friendships`.
    private func deleteInvite(_ inviteId: String, whileDoing action: String) async throws {
        guard observedUID != nil else { throw SquadError.notSignedIn }

        do {
            try await database.collection(Collection.squadInvites).document(inviteId).delete()
            clearError()
        } catch {
            let squadError = Self.mapped(error)
            report(squadError, whileDoing: action, context: .write)
            throw squadError
        }
    }

    /// The single roster-mutating path, joining and leaving both.
    ///
    /// Runs in a transaction rather than through `arrayUnion`/`arrayRemove`:
    /// capacity has to be checked against the *same* read that writes the
    /// roster, or two people accepting the last seat at once would both
    /// succeed and leave the squad over `format.maxRoster` — where the rules
    /// would then refuse every subsequent write, wedging the document. The
    /// shape is `GameService.mutateRoster`'s.
    ///
    /// - Returns: `true` when the write changed something; `false` when the
    ///   caller was already in the requested state.
    private func mutateRoster(squadId: String, joining: Bool) async throws -> Bool {
        guard let uid = observedUID else { throw SquadError.notSignedIn }

        let reference = database.collection(Collection.squads).document(squadId)

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
                      let leaderId = data[Field.leaderId] as? String,
                      let storedFormat = data[Field.format] as? String,
                      var memberIds = data[Field.memberIds] as? [String] else {
                    return RosterOutcome.missing.rawValue
                }

                // A format the app doesn't declare can't be sized, and the
                // rules give it a ceiling of zero — so this fails loudly here
                // rather than writing a roster against a guessed bound.
                guard let format = SquadFormat(rawValue: storedFormat) else {
                    return RosterOutcome.unknownFormat.rawValue
                }

                if joining {
                    guard !memberIds.contains(uid) else {
                        return RosterOutcome.unchanged.rawValue
                    }
                    guard memberIds.count < format.maxRoster else {
                        return RosterOutcome.full.rawValue
                    }
                    memberIds.append(uid)
                } else {
                    // The leader is structurally locked in — the rules require
                    // `leaderId` to stay on the roster, so leaving would fail
                    // server-side. Disbanding is their exit.
                    guard leaderId != uid else {
                        return RosterOutcome.leaderLocked.rawValue
                    }
                    guard memberIds.contains(uid) else {
                        return RosterOutcome.unchanged.rawValue
                    }
                    memberIds.removeAll { $0 == uid }
                }

                transaction.updateData(
                    [
                        Field.memberIds: memberIds,
                        Field.updatedAt: FieldValue.serverTimestamp(),
                    ],
                    forDocument: reference
                )

                return RosterOutcome.changed.rawValue
            }

            clearError()

            switch RosterOutcome(rawValue: outcome as? String ?? "") {
            case .missing:
                throw SquadError.squadNotFound
            case .unknownFormat:
                throw SquadError.unsupportedFormat
            case .full:
                throw SquadError.squadFull
            case .leaderLocked:
                throw SquadError.leaderCannotLeave
            case .unchanged:
                return false
            default:
                return true
            }
        } catch let squadError as SquadError {
            report(squadError, whileDoing: joining ? "joining the squad" : "leaving the squad", context: .write)
            throw squadError
        } catch {
            let squadError = Self.mapped(error)
            report(squadError, whileDoing: joining ? "joining the squad" : "leaving the squad", context: .write)
            throw squadError
        }
    }

    /// What a roster transaction decided. Carried out of the transaction block
    /// as its raw value because `runTransaction` hands back `Any?` — cleaner
    /// than boxing a domain error into an `NSError` just to unbox it again.
    private enum RosterOutcome: String {
        /// The roster was rewritten — joined or left.
        case changed
        /// Already in the requested state; nothing was written.
        case unchanged
        /// The squad was disbanded out from under the caller.
        case missing
        /// The stored `format` isn't one this build declares.
        case unknownFormat
        /// The roster is at `format.maxRoster`.
        case full
        /// The leader tried to leave their own squad. Disbanding is their exit.
        case leaderLocked
    }

    // MARK: - Helpers

    /// Enforces one squad per person on the two paths that put someone on one:
    /// creating and accepting an invite. The rule itself is
    /// `Squad.membershipBlock`, which the view model also asks so the UI stops
    /// offering what this would refuse.
    ///
    /// Reported as well as thrown — the inbox has no banner of its own, so this
    /// is a backstop for the race the UI can't see (an accept sent while a
    /// snapshot that changes the answer is in flight), and the Seasons tab's
    /// banner is where it lands.
    ///
    /// **Not a server guarantee.** See `Squad.membershipBlock`.
    private func requireNoOtherSquad(joining squadId: String? = nil, whileDoing action: String) throws {
        guard let blocked = Squad.membershipBlock(
            among: squads,
            haveLoaded: hasLoadedSquads,
            viewedBy: observedUID,
            joining: squadId
        ) else { return }

        report(blocked, whileDoing: action, context: .write)
        throw blocked
    }

    /// Clears the banner and forgets where it came from, so a later snapshot
    /// can't resurrect stale provenance.
    private func clearError() {
        errorMessage = nil
        errorIsFromLoad = false
    }

    private func report(_ error: SquadError, whileDoing action: String, context: FailureContext) {
        logger.error(
            "Squad error while \(action, privacy: .public): \(String(describing: error), privacy: .public)"
        )
        errorMessage = Self.message(for: error, whileDoing: action, context: context)
        errorIsFromLoad = context == .load
    }

    /// The user-facing sentence for a failure.
    ///
    /// `context` disambiguates `permission-denied`, which Firestore returns
    /// both for "the ruleset was never deployed" and for "the rules rejected
    /// this":
    ///
    /// - Every listener here filters on the caller's own uid — `memberIds`
    ///   array-contains, `uid ==`, `invitedBy ==` — and the read rules admit
    ///   exactly those documents, so a denied **read** is a document we were
    ///   entitled to, refused. That means the server isn't running the rules in
    ///   this repo.
    /// - A denied **write** was validated client-side first, so it's the server
    ///   rejecting something the client believed was legal: the squad changed
    ///   underneath the screen, an invite was revoked, or a genuine
    ///   authorization bug. Never blamed on deployment — that sends the reader
    ///   to the wrong file.
    nonisolated static func message(
        for error: SquadError,
        whileDoing action: String,
        context: FailureContext
    ) -> String {
        switch error {
        case .notSignedIn:
            return FailureText.signedOut
        case .nameTooShort:
            return "Squad names need at least \(Squad.nameLengthRange.lowerBound) characters."
        case .nameTooLong:
            return "Squad names can be at most \(Squad.nameLengthRange.upperBound) characters."
        case .unsupportedFormat:
            return "That format isn't playable yet."
        case .unknownIcon, .unknownColor:
            return "Pick a crest from the list."
        case .missingRegion:
            return "We couldn't work out which city to queue you in. Set a home court first."
        case .squadNotFound:
            return "That squad is no longer there."
        case .inviteNotFound:
            return "That invite is no longer there."
        case .squadFull:
            return "That squad is full."
        case .alreadyMember:
            return "You're already on that squad."
        case .alreadyOnASquad(let name, let isLeader):
            // Also the line under a Join the inbox won't offer, so it has to
            // read as an explanation there, not only as a failure.
            return isLeader
                ? "You lead \(name). Disband it to join or start another squad."
                : "You're on \(name). Leave it to join or start another squad."
        case .squadsNotLoaded:
            return "Still loading your squads. Try again in a moment."
        case .leaderCannotLeave:
            return "You lead this squad — disband it instead of leaving."
        case .notLeader:
            return "Only the squad's leader can do that."
        case .cannotInviteSelf:
            return "You're already on this squad."
        case .permissionDenied:
            switch context {
            case .load:
                return FailureText.rulesNotDeployed(loading: "your squads")
            case .write:
                return "The server wouldn't accept that change. This may have changed since it loaded."
            }
        case .indexRequired:
            return "This list needs a database index that's still being built."
        case .network:
            return FailureText.network
        case .unknown:
            return "Something went wrong while \(action)."
        }
    }

    /// Names what `FirestoreFailure` classified, in this collection's terms.
    ///
    /// `notFound` maps to `squadNotFound`: a squad can be disbanded by its
    /// leader while its row is on screen, so a join or a leave can arrive after
    /// there's nothing left to act on. An invite that vanished surfaces the
    /// same way — the delete is idempotent, so it doesn't reach here.
    private static func mapped(_ error: Error) -> SquadError {
        if let squadError = error as? SquadError { return squadError }

        switch FirestoreFailure.classify(error) {
        case .permissionDenied:         return .permissionDenied
        case .notFound:                 return .squadNotFound
        case .indexRequired:            return .indexRequired
        case .network:                  return .network
        case .unknown(let description): return .unknown(description)
        }
    }
}
