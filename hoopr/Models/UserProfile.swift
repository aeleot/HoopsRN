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

    /// How far out the nearby-courts list reaches, in miles. Absent until the
    /// user sets one — read `effectivePreferredRadius` rather than this, so the
    /// unset case resolves to the default in one place.
    var preferredRadius: Double?

    /// Courts the player has starred. Stored inline rather than as a
    /// subcollection so favourites ride along with the profile listener that's
    /// already open — no second listener, no extra document reads. Optional
    /// because profiles provisioned before favourites existed omit the field.
    ///
    /// Arrays stop being the right shape in the thousands; favourites won't
    /// get there.
    var favoriteCourtIds: [String]?

    /// Server-assigned at creation, immutable afterwards.
    let createdAt: Date?

    /// Server-assigned, refreshed on every write.
    let updatedAt: Date?
}

extension UserProfile {
    /// Applied when no preference is stored — provisioning doesn't write one,
    /// matching how `homeCourtId` stays absent until it's set.
    static let defaultPreferredRadius: Double = 5

    /// The bounds the profile slider offers. `firestore.rules` enforces the
    /// same range server-side; changing one without the other turns an
    /// out-of-range save into a `permission-denied`.
    static let preferredRadiusRange: ClosedRange<Double> = 1...50

    /// The radius to actually search with.
    ///
    /// Falls back to the default for anything outside `preferredRadiusRange`,
    /// not just for an absent value — a stored `0` is the dangerous case,
    /// because it's a perfectly good `Double` that silently empties the nearby
    /// list. Nothing in Firestore validates existing rows, so a field added by
    /// hand in the console arrives here as whatever it was seeded with.
    var effectivePreferredRadius: Double {
        Self.validRadius(preferredRadius)
    }

    /// Coerces a stored value into a usable radius. Shared with the profile
    /// editor so the slider never opens on a value it can't represent.
    static func validRadius(_ stored: Double?) -> Double {
        guard let stored, preferredRadiusRange.contains(stored) else {
            return defaultPreferredRadius
        }
        return stored
    }

    /// Whole miles — the slider steps by 1, so there's never a fraction to show.
    static func radiusText(_ miles: Double) -> String {
        String(format: "%.0f mi", miles)
    }
}
