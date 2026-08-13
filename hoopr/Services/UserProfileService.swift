import Combine
import FirebaseFirestore
import Foundation
import os

fileprivate let logger = Logger(subsystem: "com.hoopr", category: "UserProfileService")

/// Domain-level profile failures. `UserProfileService` translates Firestore's
/// errors into these so no Firestore type escapes the service layer, mirroring
/// how `AuthService` handles `AuthError`.
enum UserProfileError: Error, Equatable {
    case notSignedIn
    case emptyUserName
    /// Security rules rejected the operation — usually rules not yet deployed.
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

    private enum Collection {
        static let users = "users"
    }

    /// Field names kept in one place so the write maps below can't drift from
    /// `UserProfile`'s coding keys.
    private enum Field {
        static let id = "id"
        static let userName = "userName"
        static let email = "email"
        static let homeCourtId = "homeCourtId"
        static let preferredRadius = "preferredRadius"
        static let createdAt = "createdAt"
        static let updatedAt = "updatedAt"
    }

    /// Resolved lazily so the Firestore singleton is never touched before
    /// `FirebaseApp.configure()` has run.
    private lazy var database = Firestore.firestore()

    private var profileListener: ListenerRegistration?
    private var observedUID: String?
    private var cancellables = Set<AnyCancellable>()

    init(authService: AuthService) {
        authService.$currentUser
            .receive(on: DispatchQueue.main)
            .sink { [weak self] user in
                self?.handleAuthChange(to: user)
            }
            .store(in: &cancellables)
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
        profileListener?.remove()
        observedUID = user.id
        currentProfile = nil
        errorMessage = nil

        profileListener = database
            .collection(Collection.users)
            .document(user.id)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    self?.handleSnapshot(snapshot, error: error)
                }
            }

        // Accounts created before profiles existed have no document, so
        // provision one rather than leaving the user permanently nameless.
        Task { await provisionProfileIfNeeded(for: user) }
    }

    private func stopObserving() {
        profileListener?.remove()
        profileListener = nil
        observedUID = nil
        currentProfile = nil
        errorMessage = nil
    }

    private func handleSnapshot(_ snapshot: DocumentSnapshot?, error: Error?) {
        if let error {
            report(Self.mapped(error), whileDoing: "loading your profile")
            return
        }

        guard let snapshot, snapshot.exists else {
            // Not an error: provisioning may still be in flight.
            currentProfile = nil
            return
        }

        do {
            currentProfile = try snapshot.data(as: UserProfile.self)
            errorMessage = nil
        } catch {
            report(.decodingFailed(error.localizedDescription), whileDoing: "reading your profile")
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

            var fields: [String: Any] = [
                Field.id: user.id,
                Field.userName: Self.fallbackUserName(for: user),
                Field.createdAt: FieldValue.serverTimestamp(),
                Field.updatedAt: FieldValue.serverTimestamp(),
            ]
            // Omit rather than writing an explicit null.
            if let email = user.email {
                fields[Field.email] = email
            }

            try await reference.setData(fields)
            logger.debug("Provisioned profile document for signed-in user")
        } catch {
            report(Self.mapped(error), whileDoing: "setting up your profile")
        }
    }

    /// Updates only `userName` and `updatedAt`, leaving `id` and `createdAt`
    /// untouched — the mutability contract the security rules enforce
    /// server-side.
    func updateUserName(_ rawName: String) async throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw UserProfileError.emptyUserName }
        guard let uid = observedUID else { throw UserProfileError.notSignedIn }

        do {
            try await database.collection(Collection.users).document(uid).updateData([
                Field.userName: name,
                Field.updatedAt: FieldValue.serverTimestamp(),
            ])
            errorMessage = nil
        } catch {
            let profileError = Self.mapped(error)
            report(profileError, whileDoing: "saving your name")
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
            report(profileError, whileDoing: "saving your home court")
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
            report(profileError, whileDoing: "saving your preferred radius")
            throw profileError
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

    private func report(_ error: UserProfileError, whileDoing action: String) {
        logger.error("Profile error while \(action, privacy: .public): \(String(describing: error), privacy: .public)")
        errorMessage = Self.message(for: error, whileDoing: action)
    }

    private static func message(for error: UserProfileError, whileDoing action: String) -> String {
        switch error {
        case .notSignedIn:        return "You're signed out."
        case .emptyUserName:      return "Your name can't be blank."
        case .permissionDenied:   return "Not allowed to access profiles yet. Check the Firestore security rules."
        case .network:            return "Can't reach the network. Check your connection."
        case .decodingFailed:     return "Your profile is stored in an unexpected format."
        case .unknown:            return "Something went wrong while \(action)."
        }
    }

    private static func mapped(_ error: Error) -> UserProfileError {
        let nsError = error as NSError
        guard nsError.domain == FirestoreErrorDomain else {
            return .unknown(error.localizedDescription)
        }

        switch nsError.code {
        case FirestoreErrorCode.permissionDenied.rawValue:
            return .permissionDenied
        case FirestoreErrorCode.unavailable.rawValue,
             FirestoreErrorCode.deadlineExceeded.rawValue:
            return .network
        default:
            return .unknown(error.localizedDescription)
        }
    }
}
