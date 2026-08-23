import FirebaseFirestore
import Foundation

/// Firestore's error vocabulary, reduced to the cases this app distinguishes.
///
/// Both Firestore-backed services translate `NSError`s into their own domain
/// error — `GameError`, `UserProfileError` — so that no Firestore type escapes
/// the service layer. That part is deliberate and stays per-service: the
/// vocabulary a caller sees should describe *that* collection.
///
/// What isn't worth duplicating is the classification itself. Both services
/// carried their own copy of the same `FirestoreErrorDomain` guard and the same
/// code-to-case mapping, which meant a newly-handled Firestore code had to be
/// added in two files or the services would disagree about the same error.
/// Deciding *what went wrong* happens once, here; deciding *what to call it*
/// stays with each service.
///
/// `nonisolated` because the project defaults to `MainActor` isolation and this
/// is a pure classification over an `NSError` — it has no state and no reason
/// to be pinned to an actor.
nonisolated enum FirestoreFailure: Equatable {
    case permissionDenied
    case notFound
    /// `failed-precondition` — a composite index the query needs is missing or
    /// still building.
    case indexRequired
    case network
    case unknown(String)

    /// Classifies anything Firestore hands back. Errors from outside
    /// `FirestoreErrorDomain` fall through to `.unknown`, carrying their own
    /// description rather than being flattened to a generic message.
    static func classify(_ error: Error) -> FirestoreFailure {
        let nsError = error as NSError
        guard nsError.domain == FirestoreErrorDomain else {
            return .unknown(error.localizedDescription)
        }

        switch nsError.code {
        case FirestoreErrorCode.permissionDenied.rawValue:
            return .permissionDenied
        case FirestoreErrorCode.notFound.rawValue:
            return .notFound
        case FirestoreErrorCode.failedPrecondition.rawValue:
            return .indexRequired
        case FirestoreErrorCode.unavailable.rawValue,
             FirestoreErrorCode.deadlineExceeded.rawValue:
            return .network
        default:
            return .unknown(error.localizedDescription)
        }
    }
}
