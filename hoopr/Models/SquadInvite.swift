import Foundation

/// A leader's standing offer for one person to join one squad, stored at
/// `squadInvites/{squadId}_{uid}`.
///
/// **Structurally identical to `friendships`: one document per pair, with the
/// ID derived from its own content**, so a duplicate invite is impossible
/// rather than merely deduplicated — a second invite to the same person writes
/// the same document ID, which the create rule refuses because the document
/// already exists.
///
/// The asymmetry is the point. The leader creates the invite; the invitee
/// accepts it by adding **themselves** to `squads/{id}.memberIds`, which is
/// the only reason a squad can gain a member at all without anyone writing
/// somebody else's uid. Declining, revoking, and consuming an accepted invite
/// are all `delete` — the same absence-never-null move `friendships` makes
/// with decline/cancel/unfriend, and the reason there's no `status` field.
///
/// Deliberately free of Firebase types, like `Friendship`: `SquadService` owns
/// all encoding and writes explicit field maps so `createdAt` stays
/// server-assigned.
nonisolated struct SquadInvite: Identifiable, Sendable, Codable, Hashable {
    let squadId: String

    /// The invitee.
    let uid: String

    /// The leader who sent it, `== request.auth.uid` at create. Also what the
    /// read and delete rules use to recognize the sending side, which is why
    /// there's no `get()` against `squads` on either path.
    let invitedBy: String

    /// Server-assigned at creation. The document is immutable afterwards —
    /// `allow update: if false` — so there's no `updatedAt` twin.
    let createdAt: Date?
}

nonisolated extension SquadInvite {
    /// `"{squadId}_{uid}"` — the Firestore document ID.
    ///
    /// **Computed, not stored**, exactly as on `Friendship`: the ID is derived
    /// from the document's own content, the create rule recomputes it
    /// server-side and refuses anything else, and it isn't in the rules' key
    /// allowlist so writing one would fail `hasOnly`.
    var id: String { Self.id(for: squadId, uid) }

    /// The document ID for a (squad, invitee) pair.
    ///
    /// Where this departs from `Friendship.id(for:_:)`: that one *sorts* its
    /// two arguments, because a friendship is symmetric and either participant
    /// could name it first. An invite is not symmetric — one argument is a
    /// squad and the other is a person — so the order is fixed by role, and
    /// sorting would produce an ID the create rule rejects. The shape is the
    /// same; the ordering can't be.
    ///
    /// Firestore document IDs and Firebase uids are both ASCII alphanumeric,
    /// so `_` is unambiguous as a separator here for the same reason it is on
    /// `friendships`.
    static func id(for squadId: String, _ uid: String) -> String {
        "\(squadId)_\(uid)"
    }
}
