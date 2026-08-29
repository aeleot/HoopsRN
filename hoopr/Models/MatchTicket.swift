import Foundation

/// A squad's standing offer to play, stored at `matchTickets/{squadId}`.
///
/// **The document ID is the squad ID**, which structurally enforces one live
/// ticket per squad — the same trick `friendships/{pair}` uses. There is no
/// duplicate-entry logic to write because there is nowhere to put a second row.
///
/// Several fields are denormalized copies of things that live elsewhere:
/// `squadName` for the pool UI, `memberIds` so the no-shared-players rule needs
/// no extra read, and `wins`/`losses` for opponent ranking. **None of them is
/// the record of truth.** A squad's real W-L is a query over confirmed
/// `seasonGames` (plan §1.1); these are display-and-scoring copies a client
/// wrote about itself, and treating them as anything more would reintroduce the
/// forgeable counter the schema deliberately avoids.
///
/// Deliberately free of Firebase types, like every other model here.
nonisolated struct MatchTicket: Identifiable, Sendable, Codable, Hashable {
    /// Where a ticket is in its short life.
    ///
    /// `claimed` is not terminal: a claim that never becomes a game goes stale
    /// after `MatchRules.staleClaim` and the ticket returns to the pool. That
    /// recovery is what makes the two-step claim-then-create design safe
    /// without `getAfter()` — see the plan's §2.3.
    enum Status: String, Sendable, Codable {
        case open
        case claimed
        case matched
    }

    /// Mirrors the document ID.
    let squadId: String

    /// The only account that may create or edit this ticket.
    let leaderId: String

    /// Denormalized for the pool UI, so listing the pool doesn't need a read
    /// per squad.
    let squadName: String

    /// Denormalized so the no-shared-players rule is arithmetic on two tickets
    /// rather than two more document reads. **The single most important field
    /// for correctness** — see `MatchRules`.
    let memberIds: [String]

    /// Equality filter on the pool query.
    let format: SquadFormat

    /// Equality filter on the pool query. `Court.city` today; see `Squad.region`
    /// for its successor.
    let region: String

    /// The squad's acceptable courts, 1–8, **ordered by preference**. The order
    /// is load-bearing: it's how both clients agree on which court a match
    /// lands at without negotiating.
    let courtIds: [String]

    /// When they can play. Client-supplied and bounded server-side.
    let windowStart: Date
    let windowEnd: Date

    /// Denormalized at queue time for opponent ranking. Display and scoring
    /// only — never the record of truth.
    let wins: Int
    let losses: Int

    let status: Status

    /// The squad that won the claim race. Set only by the claim transaction.
    let claimedBy: String?

    /// Server-assigned when the claim landed. Drives stale-claim recovery, and
    /// pinned to `request.time` in the rules so a claim can't be backdated to
    /// look fresh forever.
    let claimedAt: Date?

    /// The handoff to the waiting squad: the `seasonGames` document its
    /// opponent created. A waiting squad learns it has been matched by watching
    /// this field on a document it can always read.
    let matchedGameId: String?

    /// Server-assigned. Ticket age is what drives relaxation.
    let createdAt: Date?

    /// Client-supplied, rules-bounded, and queried against — an expired ticket
    /// leaves the pool without anything having to delete it.
    let expiresAt: Date
}

// MARK: - Identity

nonisolated extension MatchTicket {
    /// The document ID, which *is* the squad ID.
    ///
    /// Computed rather than stored, like `Friendship.id`: the create rule ties
    /// the document to `matchTickets/{squadId}` and refuses anything else, so a
    /// stored copy could only ever agree or be rejected.
    var id: String { squadId }
}

// MARK: - Rules of a ticket

nonisolated extension MatchTicket {
    /// How many courts a squad may offer. One is a squad that will only play at
    /// its home court; eight is where a preference list stops being a
    /// preference. Mirrored in `firestore.rules`.
    static let courtCountRange: ClosedRange<Int> = 1...8

    /// How long a ticket may live. Below the floor a ticket expires before
    /// anyone can see it; above the ceiling the pool fills with squads who
    /// queued yesterday and went home. Mirrored in `firestore.rules`.
    static let lifetimeRange: ClosedRange<TimeInterval> = (15 * 60)...(24 * 60 * 60)

    /// The window a squad offers has to be long enough to hold the game, and
    /// no further out than a run can be scheduled — the same ceiling
    /// `Game.schedulingWindow` puts on a pickup run, reused so the two can't
    /// disagree about how far ahead the app plans.
    static var maximumWindowLead: TimeInterval { Game.schedulingWindow }

    /// The share of games won, or `0.5` for a squad that hasn't played.
    ///
    /// An unplayed squad sits at the midpoint rather than at zero: treating "no
    /// record" as "loses everything" would rank every new squad against the
    /// worst opponents in the pool, which is the opposite of what a fresh
    /// squad needs.
    var winPercentage: Double {
        let played = wins + losses
        guard played > 0 else { return 0.5 }
        return Double(wins) / Double(played)
    }

    var isUnplayed: Bool { wins + losses == 0 }

    func isExpired(at now: Date) -> Bool {
        expiresAt <= now
    }

    /// Whether another squad may claim this ticket at `now`.
    ///
    /// **`staleClaim` is enforced in three places that must agree**: here (the
    /// scanner), in the rules' re-claim clause, and in the waiting squad's own
    /// UI, which reverts to "searching" rather than showing a match that never
    /// arrived. A claimer that crashed between winning the claim and writing
    /// the game costs the pool 90 seconds and nothing else.
    func isClaimable(at now: Date) -> Bool {
        switch status {
        case .open:
            return true
        case .claimed:
            guard let claimedAt else {
                // A `claimed` ticket whose server timestamp hasn't resolved was
                // written seconds ago, so it is emphatically not stale.
                return false
            }
            return now.timeIntervalSince(claimedAt) > MatchRules.staleClaim
        case .matched:
            return false
        }
    }

    /// How long this ticket has been waiting. Never negative, even if a client
    /// clock disagrees with the server's.
    func age(at now: Date) -> TimeInterval {
        guard let createdAt else { return 0 }
        return max(0, now.timeIntervalSince(createdAt))
    }

    /// The stretch of time both squads can play, or `nil` when there isn't one.
    ///
    /// All of this is arithmetic on absolute `Date` values, which is what makes
    /// a window spanning midnight — or a daylight-saving boundary — a
    /// non-event: neither changes the number of seconds between two instants.
    func overlap(with other: MatchTicket) -> DateInterval? {
        let start = max(windowStart, other.windowStart)
        let end = min(windowEnd, other.windowEnd)
        guard start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Whether the two squads share a player. **A person cannot play
    /// themselves**, and this is the rule most likely to be quietly dropped —
    /// which is exactly why `memberIds` is denormalized onto the ticket rather
    /// than fetched.
    func sharesPlayer(with other: MatchTicket) -> Bool {
        !Set(memberIds).isDisjoint(with: Set(other.memberIds))
    }

    /// Everything about a proposed ticket the client can check before writing
    /// it, mirroring the create rule one condition at a time — the shape
    /// `Game.validate` and `Squad.validate` already use.
    ///
    /// - Returns: the first problem found, or `nil` when the ticket is valid.
    static func validate(
        courtIds: [String],
        windowStart: Date,
        windowEnd: Date,
        expiresAt: Date,
        format: SquadFormat,
        now: Date = Date()
    ) -> MatchTicketError? {
        guard courtCountRange.contains(courtIds.count) else { return .invalidCourtSelection }
        guard Set(courtIds).count == courtIds.count else { return .duplicateCourts }
        guard windowStart < windowEnd else { return .invalidWindow }
        guard windowEnd.timeIntervalSince(windowStart) >= format.duration else {
            return .windowTooShort
        }
        guard windowEnd > now else { return .windowInThePast }
        guard windowStart <= now.addingTimeInterval(maximumWindowLead) else {
            return .windowTooFar
        }

        let lifetime = expiresAt.timeIntervalSince(now)
        guard lifetime >= lifetimeRange.lowerBound else { return .expiryTooSoon }
        guard lifetime <= lifetimeRange.upperBound else { return .expiryTooFar }

        return nil
    }
}

/// Domain-level failures for the `matchTickets` collection.
///
/// Separate from `SquadError` because the two describe different objects: a
/// squad is durable and a ticket is ephemeral, and folding them together would
/// give the create sheet a vocabulary full of queueing states it can't reach.
nonisolated enum MatchTicketError: Error, Equatable {
    case notSignedIn
    /// Fewer than one court, or more than `courtCountRange.upperBound`.
    case invalidCourtSelection
    /// The same court listed twice — a preference order can't rank a court
    /// against itself, and the rules reject it.
    case duplicateCourts
    /// `windowEnd` is not after `windowStart`.
    case invalidWindow
    /// The window is shorter than the format's game.
    case windowTooShort
    case windowInThePast
    case windowTooFar
    case expiryTooSoon
    case expiryTooFar
    /// Only the squad's leader may queue it.
    case notLeader
    /// The squad already has a live ticket — structurally impossible to
    /// duplicate, since the document ID is the squad ID, so this is the
    /// client's name for "you're already queued".
    case alreadyQueued
    /// The ticket was claimed, matched, or expired between the pool snapshot
    /// and the claim. Expected, not exceptional.
    case claimLost
    case ticketNotFound
    case permissionDenied
    case indexRequired
    case network
    case unknown(String)
}
