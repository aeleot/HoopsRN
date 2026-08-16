import Foundation

/// A friendship — or a request to become one — between two players, stored at
/// `friendships/{uidA}_{uidB}` where `uidA < uidB`.
///
/// **One document per pair, not one per person.** Tying the document ID to the
/// lexicographically ordered pair is what makes a relationship structurally
/// singular: without it, A could create `A_B` while B independently created
/// `B_A` for the same friendship, and the two copies would drift.
///
/// Deliberately free of Firebase types, like `Game` and `UserProfile`:
/// `FriendService` owns all encoding and writes explicit field maps so server
/// timestamps stay server-assigned. Don't hand this struct to `setData(from:)`.
struct Friendship: Identifiable, Sendable, Codable, Hashable {
    /// Only two values are ever stored. Declining, cancelling, and unfriending
    /// all *delete* the document instead of adding a third status, matching the
    /// absence-never-null convention `games` and `users` already follow.
    enum Status: String, Sendable, Codable {
        case pending
        case accepted
    }

    /// Lexicographically first of the pair.
    let uidA: String

    /// Lexicographically second.
    let uidB: String

    /// Who sent the request. Distinct from the pair order, which is arbitrary —
    /// this is the single source of truth for which side is waiting on which.
    let requestedBy: String

    let status: Status

    /// Server-assigned at creation, immutable afterwards.
    let createdAt: Date?

    /// Server-assigned, refreshed on the one legal transition.
    let updatedAt: Date?
}

extension Friendship {
    /// `"{uidA}_{uidB}"` — the Firestore document ID.
    ///
    /// **Computed, not stored**, which is where this departs from `Game.id`.
    /// `games` mirrors its Firestore-generated ID into a field because there's
    /// nothing else to recover it from; a friendship's ID is *derived* from the
    /// pair, and the create rule's `idMatchesPair()` refuses any document whose
    /// ID doesn't equal exactly this — so a stored copy could only ever agree
    /// or be rejected. It's also not in the rules' key allowlist, so writing
    /// one would fail `hasOnly`.
    var id: String { "\(uidA)_\(uidB)" }

    /// What this edge looks like from `uid`'s side.
    ///
    /// Computed rather than stored: storing "sent" on one person's copy and
    /// "received" on the other's is exactly the two-copies-that-can-drift shape
    /// the single-document schema exists to avoid.
    enum Direction {
        /// `uid` asked, and is waiting on the other participant.
        case sent
        /// The other participant asked, and is waiting on `uid`.
        case received
        /// Accepted — no longer directional.
        case mutual
    }

    func direction(for uid: String) -> Direction {
        guard status == .pending else { return .mutual }
        return requestedBy == uid ? .sent : .received
    }

    /// The document ID for a pair, in either argument order.
    ///
    /// Firebase uids are ASCII alphanumeric, so Swift's `<` and the rules
    /// language's `<` agree on the ordering — which is what lets the rules
    /// recompute this same ID server-side and reject a client that picked a
    /// different one.
    static func id(for uid1: String, _ uid2: String) -> String {
        uid1 < uid2 ? "\(uid1)_\(uid2)" : "\(uid2)_\(uid1)"
    }

    func otherUid(than uid: String) -> String {
        uid == uidA ? uidB : uidA
    }
}

/// Domain-level failures for the `friendships` collection. `FriendService`
/// translates Firestore's errors into these so no Firestore type escapes the
/// service layer, mirroring `GameError` and `UserProfileError`.
enum FriendError: Error, Equatable {
    case notSignedIn
    /// The uid being friended is the signed-in user's own. Caught client-side;
    /// the rules reject it too, but as `permission-denied`.
    case cannotFriendSelf
    /// The edge was deleted between reading it and acting on it — the other
    /// person cancelled or declined while the row was on screen.
    case requestNotFound
    /// Security rules rejected the operation. Whether that means "the ruleset
    /// isn't deployed" or "you genuinely may not do this" depends on which side
    /// it came from — see `FriendService.message(for:whileDoing:context:)`.
    case permissionDenied
    /// Firestore's `failed-precondition`. Declared for parity with `GameError`;
    /// both friendship listeners are single-field equality filters with no
    /// ordering, so nothing here needs a composite index — see the plan's §7.
    case indexRequired
    case network
    case unknown(String)
}
