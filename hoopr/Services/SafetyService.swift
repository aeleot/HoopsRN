import Combine
import FirebaseFirestore
import Foundation
import os

fileprivate let logger = Logger(subsystem: "com.hoopsrn", category: "SafetyService")

/// Owns the `blocks` and `reports` collections — the safety tooling App Review
/// Guideline 1.2 asks of any app where strangers see each other's names.
///
/// **Two collections, one service**, the same departure from "one service, one
/// collection" that `SquadService` makes for `squadInvites`, and for the same
/// reason: a report has no listener, no state and no life of its own — it is
/// one write — so a service around it would be a class with a single method.
///
/// Follows `FriendService`: it owns its own subscription to `AuthService`, so
/// the blocks listener stays alive for the whole signed-in session. Firestore
/// types never escape this file.
///
/// **What a block does is mostly not here.** The refusal of a blocked person's
/// friend request or squad invite is in `firestore.rules`; removing the
/// friendship that was already there is `FriendsViewModel.block`, because it
/// crosses collections. This service only records the fact.
@MainActor
final class SafetyService: ObservableObject {
    /// Everyone the signed-in account has blocked, newest first.
    @Published private(set) var blocks: [Block] = []

    /// The same people as a set, for the "is this person blocked" lookups that
    /// search and the inbox make per row.
    @Published private(set) var blockedUids: Set<String> = []

    /// The blocks listener died and a re-attach is pending.
    @Published private(set) var isRecovering = false

    private enum Collection {
        static let blocks = "blocks"
        static let reports = "reports"
    }

    private enum ListenerKey {
        static let blocks = "blocks"
    }

    private enum Field {
        static let blockerId = "blockerId"
        static let blockedId = "blockedId"
        static let reporterId = "reporterId"
        static let targetType = "targetType"
        static let targetId = "targetId"
        static let reason = "reason"
        static let details = "details"
        static let createdAt = "createdAt"
    }

    /// Resolved lazily so the Firestore singleton is never touched before
    /// `FirebaseApp.configure()` has run.
    private lazy var database = Firestore.firestore()

    private var blocksListener: ListenerRegistration?
    private var observedUID: String?
    private var cancellables = Set<AnyCancellable>()

    private let supervisor = ListenerSupervisor(subject: "blocked players")

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
        blocksListener?.remove()
    }

    // MARK: - Session wiring

    private func handleAuthChange(to user: AuthenticatedUser?) {
        guard let user else {
            stopObserving()
            return
        }

        guard user.id != observedUID else { return }

        stopObserving()
        observedUID = user.id
        attachListener()
    }

    /// One equality filter on the caller's own uid, so it never asks for a
    /// document the read rule doesn't already admit — and needs no composite
    /// index. Sorted here rather than in the query for the same reason.
    private func attachListener() {
        guard let uid = observedUID else { return }

        blocksListener?.remove()
        blocksListener = database
            .collection(Collection.blocks)
            .whereField(Field.blockerId, isEqualTo: uid)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handle(snapshot, error: error)
                }
            }
    }

    private func stopObserving() {
        supervisor.cancel()
        isRecovering = false
        blocksListener?.remove()
        blocksListener = nil
        observedUID = nil
        blocks = []
        blockedUids = []
    }

    private func handle(_ snapshot: QuerySnapshot?, error: Error?) {
        if let error {
            // The listener is already gone — see `ListenerSupervisor`. Nothing
            // is published as an error: a block list that failed to load hides
            // nobody, which is the safe direction, and the rules still refuse
            // a blocked sender whether or not this client knows about it.
            logger.error("Blocks listener failed: \(error.localizedDescription, privacy: .public)")
            supervisor.recordFailure(for: ListenerKey.blocks)
            isRecovering = true
            return
        }

        supervisor.recordSuccess(for: ListenerKey.blocks)
        isRecovering = supervisor.isRecovering

        let decoded: [Block] = (snapshot?.documents ?? []).compactMap { document in
            do {
                return try document.data(as: Block.self)
            } catch {
                logger.error(
                    "Skipping block \(document.documentID, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }

        // An unacknowledged local write has no `createdAt` yet and is the
        // newest thing here, so it sorts to the top — `FriendService.sortDate`.
        blocks = decoded.sorted {
            ($0.createdAt ?? .distantFuture) > ($1.createdAt ?? .distantFuture)
        }
        blockedUids = Set(decoded.map(\.blockedId))
    }

    // MARK: - Blocks

    /// Blocks `otherUid`. Safe to call for someone already blocked: the write
    /// lands on the same document ID and is refused as an update, which is
    /// read here as "already done".
    ///
    /// - Throws: `SafetyError`, never a Firestore type.
    func block(_ otherUid: String) async throws {
        guard let uid = observedUID else { throw SafetyError.notSignedIn }
        guard otherUid != uid else { throw SafetyError.cannotTargetSelf }
        guard !blockedUids.contains(otherUid) else { return }

        let reference = database
            .collection(Collection.blocks)
            .document(Block.id(blocker: uid, blocked: otherUid))

        do {
            try await reference.setData([
                Field.blockerId: uid,
                Field.blockedId: otherUid,
                Field.createdAt: FieldValue.serverTimestamp(),
            ])
        } catch {
            let safetyError = Self.mapped(error)

            // A refused write against a document that is already there is a
            // second tap from a stale screen, not a failure.
            if safetyError == .permissionDenied,
               let existing = try? await reference.getDocument(),
               existing.exists {
                return
            }
            throw safetyError
        }
    }

    /// Lifts a block. Deleting one that is already gone succeeds.
    func unblock(_ otherUid: String) async throws {
        guard let uid = observedUID else { throw SafetyError.notSignedIn }

        do {
            try await database
                .collection(Collection.blocks)
                .document(Block.id(blocker: uid, blocked: otherUid))
                .delete()
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Deletes every block the signed-in account has made — the blocks step of
    /// account deletion. Reads the query rather than the published list so it
    /// doesn't depend on the listener having delivered. Safe to run twice.
    ///
    /// Blocks *other* people have made against this account stay: they aren't
    /// this account's to delete, and all they name is a uid that no longer
    /// resolves to anyone.
    func deleteEveryBlock() async throws {
        guard let uid = observedUID else { throw SafetyError.notSignedIn }

        do {
            let mine = try await database
                .collection(Collection.blocks)
                .whereField(Field.blockerId, isEqualTo: uid)
                .getDocuments()

            for document in mine.documents {
                try await document.reference.delete()
            }
        } catch {
            throw Self.mapped(error)
        }
    }

    // MARK: - Reports

    /// Files a report. There is nothing to read back and nothing published:
    /// the rules refuse every client read of `reports`.
    ///
    /// - Throws: `SafetyError`, never a Firestore type.
    func submit(_ report: Report) async throws {
        guard let uid = observedUID else { throw SafetyError.notSignedIn }
        if let problem = report.validate(reporterId: uid) { throw problem }

        var fields: [String: Any] = [
            Field.reporterId: uid,
            Field.targetType: report.targetType.rawValue,
            Field.targetId: report.targetId,
            Field.reason: report.reason.rawValue,
            Field.createdAt: FieldValue.serverTimestamp(),
        ]
        // Absent, never empty — the rules refuse an empty string.
        if let details = report.normalizedDetails {
            fields[Field.details] = details
        }

        do {
            try await database.collection(Collection.reports).document().setData(fields)
            logger.debug("Filed a report")
        } catch {
            throw Self.mapped(error)
        }
    }

    // MARK: - Helpers

    /// The user-facing sentence for a failure.
    ///
    /// `permission-denied` on these writes is never the user's doing — every
    /// condition the rules check is checked here first — so it points at the
    /// deployed ruleset, the same reading `FailureText.rulesNotDeployed` gives
    /// a refused read.
    nonisolated static func message(for error: SafetyError, whileDoing action: String) -> String {
        switch error {
        case .notSignedIn:      return FailureText.signedOut
        case .missingTarget:    return "There's nothing here to report."
        case .cannotTargetSelf: return "You can't do that to your own account."
        case .detailsTooLong:
            return "Keep the note under \(Report.maxDetailsLength) characters."
        case .permissionDenied:
            return "The server wouldn't accept that. The Firestore security rules are probably not deployed."
        case .network:          return FailureText.network
        case .unknown:          return "Something went wrong while \(action)."
        }
    }

    private static func mapped(_ error: Error) -> SafetyError {
        if let safetyError = error as? SafetyError { return safetyError }

        switch FirestoreFailure.classify(error) {
        case .permissionDenied:         return .permissionDenied
        case .network:                  return .network
        // Neither write reads first, and neither query needs an index.
        case .notFound, .indexRequired: return .unknown("unexpected")
        case .unknown(let description): return .unknown(description)
        }
    }
}
