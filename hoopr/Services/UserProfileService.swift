import Combine
import FirebaseFirestore
import Foundation
import os

fileprivate let logger = Logger(subsystem: "com.hoopsrn", category: "UserProfileService")

/// Domain-level profile failures. `UserProfileService` translates Firestore's
/// errors into these so no Firestore type escapes the service layer, mirroring
/// how `AuthService` handles `AuthError`.
enum UserProfileError: Error, Equatable {
    case notSignedIn
    case emptyUserName
    /// Longer than `UserProfile.maxUserNameLength`. Checked client-side because
    /// the rules cap it too, and a rules rejection arrives as
    /// `permission-denied` — a message that would send you looking for an
    /// undeployed ruleset rather than a long name.
    case userNameTooLong
    /// Security rules rejected the operation. Whether that means "the ruleset
    /// isn't deployed" or "you genuinely may not do this" depends on which side
    /// it came from — see `message(for:whileDoing:context:)`.
    case permissionDenied
    case network
    case decodingFailed(String)
    case unknown(String)
}

/// Owns the `users` collection — the app's first piece of app-owned data, as
/// opposed to the identity Firebase Auth already manages.
///
/// The only file that reads or writes user profiles in Firestore. It owns its
/// own subscription to `AuthService` so a single profile listener stays alive
/// for the whole signed-in session: the greeting in `MainTabView` and the
/// profile screen read the same published state instead of each opening their
/// own listener.
@MainActor
final class UserProfileService: ObservableObject {
    /// The signed-in user's profile. `nil` while signed out, while the first
    /// snapshot is still in flight, or before provisioning has completed.
    @Published private(set) var currentProfile: UserProfile?

    /// Human-readable description of the most recent failure, if any.
    @Published private(set) var errorMessage: String?

    /// The profile listener died and a re-attach is pending. Same exposure as
    /// `GameService.isRecovering`.
    @Published private(set) var isRecovering = false

    private enum Collection {
        static let users = "users"
    }

    /// Field names kept in one place so the write maps below can't drift from
    /// `UserProfile`'s coding keys.
    private enum Field {
        static let id = "id"
        static let userName = "userName"
        static let userNameLower = "userNameLower"
        static let homeCourtId = "homeCourtId"
        static let preferredRadius = "preferredRadius"
        static let favoriteCourtIds = "favoriteCourtIds"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
        static let completedGameCount = "completedGameCount"
        static let participationStreak = "participationStreak"
        static let lastCompletedAt = "lastCompletedAt"
    }

    /// Bounds on the one-shot lookups. Neither applies to the profile listener,
    /// which reads a single document by ID.
    private enum Limit {
        /// Firestore's ceiling on the number of values in an `in` filter.
        static let documentIdBatch = 30
        /// A picker of matches, not a directory — enough to find the person you
        /// meant, few enough to read.
        static let searchResults = 20
    }

    /// Resolved lazily so the Firestore singleton is never touched before
    /// `FirebaseApp.configure()` has run.
    private lazy var database = Firestore.firestore()

    private var profileListener: ListenerRegistration?
    /// The whole user rather than just the uid, because provisioning seeds a
    /// fallback name from the email and now runs on every re-attach, not only
    /// on the sign-in that first supplied it.
    private var observedUser: AuthenticatedUser?

    private var observedUID: String? { observedUser?.id }
    private var cancellables = Set<AnyCancellable>()

    /// Whether this session has already tried to write a missing
    /// `userNameLower` — see `backfillSearchKeyIfNeeded(for:)`. Reset per
    /// signed-in session, so a failure retries on the next sign-in rather than
    /// on every snapshot.
    private var didBackfillSearchKey = false

    /// Brings the profile listener back after a terminal error. Same exposure
    /// `GameService` has, and the same reason — see `ListenerSupervisor`.
    private let supervisor = ListenerSupervisor(subject: "profile")

    /// Only one listener here, so the supervisor's per-listener tracking has a
    /// single key.
    private static let listenerKey = "profile"

    init(authService: AuthService) {
        authService.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                self?.handleAuthChange(to: user)
            }
            .store(in: &cancellables)

        // Weak: this service owns the supervisor.
        supervisor.onRetry = { [weak self] in
            self?.attachListener()
        }
    }

    deinit {
        profileListener?.remove()
    }

    // MARK: - Session wiring

    private func handleAuthChange(to user: AuthenticatedUser?) {
        guard let user else {
            stopObserving()
            return
        }

        // Firebase re-emits the same user on token refresh; don't churn the
        // listener when nothing actually changed.
        guard user.id != observedUID else { return }

        startObserving(user)
    }

    private func startObserving(_ user: AuthenticatedUser) {
        observedUser = user
        currentProfile = nil
        errorMessage = nil
        didBackfillSearchKey = false
        attachListener()
    }

    /// Opens the profile listener, replacing one already open, and provisions
    /// the document if it's missing.
    ///
    /// Also the retry path. Provisioning re-runs on a retry deliberately: if
    /// the *first* attempt was refused because the ruleset wasn't deployed, a
    /// re-attached listener alone would leave the account permanently without a
    /// profile document. It's idempotent — one read, then a write only when
    /// there's nothing there.
    private func attachListener() {
        guard let user = observedUser else { return }

        profileListener?.remove()
        profileListener = database
            .collection(Collection.users)
            .document(user.id)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handleSnapshot(snapshot, error: error)
                }
            }

        Task { await provisionProfileIfNeeded(for: user) }
    }

    private func stopObserving() {
        supervisor.cancel()
        isRecovering = false
        profileListener?.remove()
        profileListener = nil
        observedUser = nil
        currentProfile = nil
        errorMessage = nil
        didBackfillSearchKey = false
    }

    /// Re-attaches now rather than waiting out the backoff.
    func retry() {
        supervisor.retryNow()
    }

    private func handleSnapshot(_ snapshot: DocumentSnapshot?, error: Error?) {
        if let error {
            // The listener is already gone — see `ListenerSupervisor`.
            supervisor.recordFailure(for: Self.listenerKey)
            isRecovering = true
            report(Self.mapped(error), whileDoing: "loading your profile", context: .load)
            return
        }

        supervisor.recordSuccess(for: Self.listenerKey)
        isRecovering = supervisor.isRecovering

        guard let snapshot, snapshot.exists else {
            // Not an error: provisioning may still be in flight.
            currentProfile = nil
            return
        }

        do {
            let profile = try snapshot.data(as: UserProfile.self)
            currentProfile = profile
            errorMessage = nil
            backfillSearchKeyIfNeeded(for: profile)
        } catch {
            report(
                .decodingFailed(error.localizedDescription),
                whileDoing: "reading your profile",
                context: .load
            )
        }
    }

    /// Writes `userNameLower` onto a profile provisioned before player search
    /// existed.
    ///
    /// Without this, an account created before that field shipped is **invisible
    /// to name search forever** — the prefix range has nothing to match, so its
    /// owner simply can't be found by anyone typing their name. Waiting for them
    /// to happen to edit their display name is not a migration.
    ///
    /// It has to run here, on the *owner's* own client, because the rules only
    /// ever let an account write its own document: nobody can backfill anyone
    /// else, so every account heals itself the next time its owner opens the
    /// app. That also makes this the whole migration — there's no server-side
    /// backfill on the Spark plan.
    ///
    /// Idempotent and self-terminating: the write produces a snapshot whose
    /// `userNameLower` is set, so the guard below stops it. `didBackfillSearchKey`
    /// covers the other direction — one failed attempt per session, rather than a
    /// write retried on every snapshot.
    private func backfillSearchKeyIfNeeded(for profile: UserProfile) {
        guard profile.userNameLower == nil, !didBackfillSearchKey else { return }
        didBackfillSearchKey = true

        Task { [weak self] in
            await self?.writeSearchKey(for: profile)
        }
    }

    /// Silent on failure by design: the user didn't ask for this and there's
    /// nothing for them to do about it. It retries on the next sign-in.
    private func writeSearchKey(for profile: UserProfile) async {
        do {
            try await database.collection(Collection.users).document(profile.id).updateData([
                Field.userNameLower: UserProfile.searchKey(profile.userName),
                Field.updatedAt: FieldValue.serverTimestamp(),
            ])
            logger.debug("Backfilled the search key on a pre-search profile")
        } catch {
            logger.error(
                "Couldn't backfill the search key: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Writes

    /// Creates the profile document only if it's missing. Idempotent, so it's
    /// safe to run on every sign-in.
    private func provisionProfileIfNeeded(for user: AuthenticatedUser) async {
        let reference = database.collection(Collection.users).document(user.id)

        do {
            let snapshot = try await reference.getDocument()
            guard !snapshot.exists else { return }

            // The email is deliberately **not** stored, only read from Auth to
            // seed a first name. `users` documents are readable by any
            // signed-in user — that's what makes name resolution and player
            // search work — and Firestore has no field-level read ACLs, so
            // anything kept here is effectively visible to every other player.
            // Auth already owns the address, and nothing in the app ever needed
            // the copy: the profile screen's Email row reads
            // `AuthService.currentUser`.
            let name = Self.fallbackUserName(for: user)
            let fields: [String: Any] = [
                Field.id: user.id,
                Field.userName: name,
                // Derived, never independently supplied — see `searchKey`.
                Field.userNameLower: UserProfile.searchKey(name),
                Field.createdAt: FieldValue.serverTimestamp(),
                Field.updatedAt: FieldValue.serverTimestamp(),
            ]

            try await reference.setData(fields)
            logger.debug("Provisioned profile document for signed-in user")
        } catch {
            report(Self.mapped(error), whileDoing: "setting up your profile", context: .write)
        }
    }

    /// Updates only `userName`, its search mirror, and `updatedAt`, leaving
    /// `id` and `createdAt` untouched — the mutability contract the security
    /// rules enforce server-side.
    func updateUserName(_ rawName: String) async throws {
        // Rejected here rather than reshaped, matching `GameService.createGame`
        // — and checked at all because the rules cap the length too, so an
        // over-long name would otherwise come back as `permission-denied`.
        if let invalid = UserProfile.validate(userName: rawName) {
            throw invalid
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uid = observedUID else { throw UserProfileError.notSignedIn }

        do {
            try await database.collection(Collection.users).document(uid).updateData([
                Field.userName: name,
                // Written in the same update as `userName`, never separately:
                // the two drifting apart would make a profile unsearchable
                // under the name it actually displays.
                Field.userNameLower: UserProfile.searchKey(name),
                Field.updatedAt: FieldValue.serverTimestamp(),
            ])
            errorMessage = nil
        } catch {
            let profileError = Self.mapped(error)
            report(profileError, whileDoing: "saving your name", context: .write)
            throw profileError
        }
    }

    /// Sets or clears the user's home court. Passing `nil` deletes the field
    /// rather than storing an explicit null, matching how provisioning omits
    /// an absent email.
    ///
    /// `courtId` is a `Court.id` from the bundled dataset. Courts aren't in
    /// Firestore, so there's no reference to validate against server-side —
    /// the picker only ever offers real courts.
    func updateHomeCourt(courtId: String?) async throws {
        guard let uid = observedUID else { throw UserProfileError.notSignedIn }

        do {
            try await database.collection(Collection.users).document(uid).updateData([
                Field.homeCourtId: courtId ?? FieldValue.delete(),
                Field.updatedAt: FieldValue.serverTimestamp(),
            ])
            errorMessage = nil
        } catch {
            let profileError = Self.mapped(error)
            report(profileError, whileDoing: "saving your home court", context: .write)
            throw profileError
        }
    }

    /// Sets how far out the nearby-courts list reaches, in miles.
    ///
    /// Clamped to `UserProfile.preferredRadiusRange` before the write: the
    /// rules reject anything outside it, and a rules rejection surfaces as
    /// "permission denied" — a message that would send you looking for an
    /// undeployed ruleset rather than an out-of-range slider.
    func updatePreferredRadius(_ radius: Double) async throws {
        guard let uid = observedUID else { throw UserProfileError.notSignedIn }

        let range = UserProfile.preferredRadiusRange
        let clamped = min(max(radius, range.lowerBound), range.upperBound)

        do {
            try await database.collection(Collection.users).document(uid).updateData([
                Field.preferredRadius: clamped,
                Field.updatedAt: FieldValue.serverTimestamp(),
            ])
            errorMessage = nil
        } catch {
            let profileError = Self.mapped(error)
            report(profileError, whileDoing: "saving your preferred radius", context: .write)
            throw profileError
        }
    }

    /// Stars or unstars a court.
    ///
    /// Uses `arrayUnion`/`arrayRemove` rather than reading the array and
    /// writing it back: the server merges the change, so two devices toggling
    /// different courts at once can't clobber each other.
    func setFavorite(courtId: String, isFavorite: Bool) async throws {
        guard let uid = observedUID else { throw UserProfileError.notSignedIn }

        do {
            try await database.collection(Collection.users).document(uid).updateData([
                Field.favoriteCourtIds: isFavorite
                    ? FieldValue.arrayUnion([courtId])
                    : FieldValue.arrayRemove([courtId]),
                Field.updatedAt: FieldValue.serverTimestamp(),
            ])
            errorMessage = nil
        } catch {
            let profileError = Self.mapped(error)
            report(profileError, whileDoing: "saving your favorites", context: .write)
            throw profileError
        }
    }

    /// Recalculates participation stats from the signed-in user's completed
    /// games and writes them back to the profile — the single place that
    /// computes or writes `completedGameCount`/`participationStreak`/
    /// `lastCompletedAt`. `HomeViewModel` calls this whenever
    /// `GameService.completedGames` delivers a new snapshot.
    ///
    /// `completedGames` is expected sorted `completedAt` descending, matching
    /// how `GameService` queries them, so `lastCompletedAt` is simply its
    /// first element.
    ///
    /// Silent on failure, like `writeSearchKey`: nothing the user did
    /// triggered this write, so there's no action for an error banner to ask
    /// them to retry — it just runs again on the next snapshot.
    func refreshStats(for userId: String, using completedGames: [Game]) async throws {
        do {
            try await database.collection(Collection.users).document(userId).updateData([
                Field.completedGameCount: completedGames.count,
                Field.participationStreak: Game.calculateStreak(from: completedGames),
                Field.lastCompletedAt: completedGames.first?.completedAt.map(Timestamp.init(date:))
                    ?? FieldValue.delete(),
                Field.updatedAt: FieldValue.serverTimestamp(),
            ])
        } catch {
            let profileError = Self.mapped(error)
            logger.error(
                "Couldn't refresh stats: \(error.localizedDescription, privacy: .public)"
            )
            throw profileError
        }
    }

    // MARK: - Lookups

    /// Resolves other people's profiles by uid.
    ///
    /// This is where "one service, one collection" is paid for: `friendships`
    /// documents carry only uids — never denormalized names, the same way a
    /// `Game` never denormalizes its court name — so `FriendService` hands its
    /// uids here rather than importing anything about `users` itself.
    ///
    /// One-shot rather than a listener: live-updating other players' names
    /// while a screen sits open isn't worth a second listener on this
    /// collection, and callers re-run this whenever their uid set changes.
    ///
    /// Missing uids are simply absent from the result — a profile deleted out
    /// from under a friendship isn't an error worth failing the whole batch
    /// for. Unlike the write paths, a failure here throws *without* touching
    /// `errorMessage`: that banner belongs to the signed-in user's own profile,
    /// and a friend-lookup failure surfacing there would appear on the profile
    /// screen for something that happened on another tab.
    func profiles(for uids: [String]) async throws -> [UserProfile] {
        guard !uids.isEmpty else { return [] }

        let unique = Array(Set(uids))

        do {
            var resolved: [UserProfile] = []
            // `in` takes at most 30 values per query, so a longer friends list
            // becomes several queries.
            for start in stride(from: 0, to: unique.count, by: Limit.documentIdBatch) {
                let end = min(start + Limit.documentIdBatch, unique.count)
                let snapshot = try await database
                    .collection(Collection.users)
                    .whereField(FieldPath.documentID(), in: Array(unique[start..<end]))
                    .getDocuments()
                resolved.append(contentsOf: Self.decoded(snapshot))
            }
            return resolved
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Case-insensitive prefix search over display names.
    ///
    /// A single-field range filter on `userNameLower`, which Firestore
    /// auto-indexes — no `firestore.indexes.json` entry. `\u{f8ff}` is the
    /// upper end of the private-use block, so it sorts above any character a
    /// name realistically ends with, making the pair of bounds a prefix match.
    ///
    /// A blank prefix returns nothing rather than the first 20 accounts in the
    /// database: an empty search field is "no query yet", not "everyone".
    ///
    /// Profiles written before `userNameLower` existed have no value to match
    /// and are invisible here until their owner next saves a name.
    func searchProfiles(matching rawPrefix: String) async throws -> [UserProfile] {
        let prefix = UserProfile.searchKey(rawPrefix)
        guard !prefix.isEmpty else { return [] }

        do {
            let snapshot = try await database
                .collection(Collection.users)
                .whereField(Field.userNameLower, isGreaterThanOrEqualTo: prefix)
                .whereField(Field.userNameLower, isLessThan: prefix + "\u{f8ff}")
                .limit(to: Limit.searchResults)
                .getDocuments()
            return Self.decoded(snapshot)
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Exact lookup by uid — the "search by ID" path, and cheaper than the name
    /// one: `users` documents are keyed by uid, so this is a direct read rather
    /// than a query.
    ///
    /// - Returns: `nil` when no such account exists, which is an ordinary
    ///   answer to "is this ID real" rather than a failure.
    func profile(uid: String) async throws -> UserProfile? {
        let id = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }

        let snapshot: DocumentSnapshot
        do {
            snapshot = try await database.collection(Collection.users).document(id).getDocument()
        } catch {
            throw Self.mapped(error)
        }

        guard snapshot.exists else { return nil }

        // Decoded outside the fetch's `catch` so a malformed document reports
        // as `decodingFailed` rather than being flattened into `.unknown` by a
        // classifier that only understands Firestore's own errors.
        do {
            return try snapshot.data(as: UserProfile.self)
        } catch {
            throw UserProfileError.decodingFailed(error.localizedDescription)
        }
    }

    /// Decodes per document rather than per snapshot, matching
    /// `GameService.decoded`: one profile that drifted from the model shouldn't
    /// blank a whole result list. The skipped document is logged so it stays
    /// discoverable.
    private static func decoded(_ snapshot: QuerySnapshot?) -> [UserProfile] {
        guard let snapshot else { return [] }

        return snapshot.documents.compactMap { document in
            do {
                return try document.data(as: UserProfile.self)
            } catch {
                logger.error(
                    "Skipping profile \(document.documentID, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }
    }

    // MARK: - Helpers

    /// Seed name for a brand-new profile. Same email local-part heuristic the
    /// greeting used to apply inline, now applied once at provisioning time so
    /// the value is stored rather than re-derived on every render.
    private static func fallbackUserName(for user: AuthenticatedUser) -> String {
        guard let localPart = user.email?.split(separator: "@").first,
              !localPart.isEmpty else {
            return "Hooper"
        }
        return String(localPart)
    }

    private func report(
        _ error: UserProfileError,
        whileDoing action: String,
        context: FailureContext
    ) {
        logger.error("Profile error while \(action, privacy: .public): \(String(describing: error), privacy: .public)")
        errorMessage = Self.message(for: error, whileDoing: action, context: context)
    }

    /// Mirrors `GameService.message(for:whileDoing:context:)`, including why
    /// `permission-denied` reads differently on a read than on a write: the
    /// profile listener asks for the caller's own document, which the read rule
    /// grants any signed-in user, so a refusal there points at the deployed
    /// ruleset rather than at anything the user did.
    nonisolated static func message(
        for error: UserProfileError,
        whileDoing action: String,
        context: FailureContext
    ) -> String {
        switch error {
        case .notSignedIn:        return FailureText.signedOut
        case .emptyUserName:      return "Your name can't be blank."
        case .userNameTooLong:
            return "Your name can't be longer than \(UserProfile.maxUserNameLength) characters."
        case .permissionDenied:
            switch context {
            case .load:
                return FailureText.rulesNotDeployed(loading: "your profile")
            case .write:
                return "The server wouldn't accept that change."
            }
        case .network:            return FailureText.network
        case .decodingFailed:     return "Your profile is stored in an unexpected format."
        case .unknown:            return "Something went wrong while \(action)."
        }
    }

    /// Names what `FirestoreFailure` classified, in this collection's terms.
    ///
    /// `notFound` and `indexRequired` have no profile-specific meaning: the
    /// document is addressed by uid rather than queried, so there's no
    /// composite index to be missing, and an absent document is handled by
    /// provisioning rather than treated as an error. Both stay `.unknown`,
    /// as they did before this classification was shared.
    private static func mapped(_ error: Error) -> UserProfileError {
        switch FirestoreFailure.classify(error) {
        case .permissionDenied:
            return .permissionDenied
        case .network:
            return .network
        case .notFound, .indexRequired, .unknown:
            return .unknown(error.localizedDescription)
        }
    }
}
