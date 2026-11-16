import Foundation

/// One person refusing to hear from another, stored at
/// `blocks/{blockerId}_{blockedId}`.
///
/// **Directional, so the ID is ordered by role, not sorted** — the way
/// `SquadInvite.id` is and `Friendship.id` isn't. A blocking B and B blocking
/// A are two facts and two documents. Deriving the ID from the pair is what
/// lets the `friendships` and `squadInvites` create rules refuse a blocked
/// sender with one `exists()`.
///
/// Private to the blocker: the rules let nobody else read it, so the blocked
/// person never learns of it from the app.
nonisolated struct Block: Identifiable, Sendable, Codable, Hashable {
    let blockerId: String
    let blockedId: String

    /// Server-assigned at creation. The document is immutable afterwards.
    let createdAt: Date?

    var id: String { Self.id(blocker: blockerId, blocked: blockedId) }

    /// The document ID. **Mirrored in `firestore.rules`**, which looks a block
    /// up at exactly this path from the other person's write.
    static func id(blocker: String, blocked: String) -> String {
        "\(blocker)_\(blocked)"
    }
}

/// A player flagging another player or a squad for review, stored at
/// `reports/{autoId}`.
///
/// **Write-only from the app.** There is no backend, so reports are read in
/// the Firebase console; the rules refuse every client read, the author's
/// included. This type is therefore only ever *sent*, never decoded.
nonisolated struct Report: Sendable, Equatable {
    /// MIRRORED IN `firestore.rules` — `isAllowedTargetType`.
    enum TargetType: String, Sendable, CaseIterable {
        case player
        case squad
    }

    /// MIRRORED IN `firestore.rules` — `isAllowedReason`.
    enum Reason: String, Sendable, CaseIterable, Identifiable {
        case offensiveName
        case harassment
        case spam
        case impersonation
        case other

        var id: String { rawValue }

        var title: String {
            switch self {
            case .offensiveName: "Offensive name"
            case .harassment:    "Harassment or abuse"
            case .spam:          "Spam"
            case .impersonation: "Pretending to be someone else"
            case .other:         "Something else"
            }
        }
    }

    /// Longest note the rules accept. MIRRORED IN `firestore.rules`.
    static let maxDetailsLength = 500

    let targetType: TargetType
    let targetId: String
    let reason: Reason

    /// As typed. `normalizedDetails` is what gets stored.
    let details: String

    /// The note as it will be stored: trimmed, and `nil` when there's nothing
    /// left — the rules want the field absent rather than empty.
    var normalizedDetails: String? {
        let trimmed = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Everything the client can check before sending, mirroring the create
    /// rule — a rules refusal would arrive as `permission-denied`, which says
    /// nothing useful about a note that ran long.
    func validate(reporterId: String) -> SafetyError? {
        guard !targetId.isEmpty else { return .missingTarget }
        guard targetId != reporterId else { return .cannotTargetSelf }
        // Unicode scalars, not characters: that is what the rules' `size()`
        // counts, so an emoji-heavy note can't pass here and fail there.
        if let note = normalizedDetails, note.unicodeScalars.count > Self.maxDetailsLength {
            return .detailsTooLong
        }
        return nil
    }
}

/// Domain-level failures for `blocks` and `reports`. `SafetyService`
/// translates Firestore's errors into these so no Firestore type escapes the
/// service layer, mirroring `FriendError`.
nonisolated enum SafetyError: Error, Equatable {
    case notSignedIn
    case missingTarget
    /// Blocking or reporting yourself. Caught client-side; the rules reject it
    /// too, but as `permission-denied`.
    case cannotTargetSelf
    case detailsTooLong
    case permissionDenied
    case network
    case unknown(String)
}

/// What blocking someone has to clear up besides writing the block, decided
/// without touching Firebase.
///
/// The block alone already stops anything *new* from that person — the rules
/// see to it. What it can't do is retract what was already there: an existing
/// friendship or pending request, and squad invites in either direction.
nonisolated enum BlockCleanup {
    struct Invites: Equatable, Sendable {
        /// Invites that person sent the blocker — declined.
        var toDecline: [String] = []
        /// Invites the blocker sent that person — revoked.
        var toRevoke: [String] = []
    }

    static func invites(
        blocking blockedUid: String,
        incoming: [SquadInvite],
        sent: [SquadInvite]
    ) -> Invites {
        Invites(
            toDecline: incoming.filter { $0.invitedBy == blockedUid }.map(\.id).sorted(),
            toRevoke: sent.filter { $0.uid == blockedUid }.map(\.id).sorted()
        )
    }
}
