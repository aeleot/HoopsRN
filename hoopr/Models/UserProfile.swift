import Foundation

/// A player's app-owned profile, stored at `users/{uid}`.
///
/// Firebase Auth owns *identity* (uid, email); this owns everything other
/// players will eventually see — starting with a real name instead of a guess
/// derived from an email address.
///
/// Deliberately free of Firebase types, like `Court` and `AuthenticatedUser`.
/// `UserProfileService` owns all encoding: it writes explicit field maps so
/// server timestamps stay server-assigned and `createdAt` is never clobbered
/// by a later update. Don't hand this struct to `setData(from:)`.
struct UserProfile: Identifiable, Sendable, Codable, Hashable {
    /// Firebase Auth uid. Also the Firestore document ID, so a profile is
    /// addressable without a query.
    let id: String

    /// Editable, and not unique — despite the name, this is a display name,
    /// not a handle. Nothing enforces uniqueness on it.
    var userName: String

    /// Denormalized from Auth for display only. Never a lookup key.
    var email: String?

    /// Reserved for a future "home court" preference. Read but never written
    /// yet — no UI sets it.
    var homeCourtId: String?

    /// Server-assigned at creation, immutable afterwards.
    let createdAt: Date?

    /// Server-assigned, refreshed on every write.
    let updatedAt: Date?
}
