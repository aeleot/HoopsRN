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
    /// Where a ticket is in its short life. **Two states, and the second is
    /// terminal.**
    ///
    /// There was a third, `claimed`, and removing it is the substance of the
    /// duplicate-match fix rather than tidying after it. `claimed` existed
    /// because a match used to be made in two steps — claim a ticket, then
    /// write the game — and it named the gap between them. A gap is a state two
    /// clients can disagree about: two squads that claimed *each other* wrote to
    /// two different documents, so nothing serialized them, both claims won, and
    /// both clients went on to create a game. Both squads then saw two live
    /// matches.
    ///
    /// A match is now one transaction that reads both tickets and writes both
    /// tickets and the game together, so there is no instant at which a ticket
    /// is spoken for but not spent. With no gap there is nothing for `claimed`
    /// to name — and with it goes the ninety-second stale-claim recovery, which
    /// existed only to clean up after a claimer who died inside that gap.
    enum Status: String, Sendable, Codable {
        /// In the pool, and claimable by anyone the rules admit.
        case open
        /// Spent on a match. Terminal: the rules permit `open` -> `matched` and
        /// nothing else, which is what makes "a squad is in at most one live
        /// match" true on the server rather than only in the client.
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

    /// The squad that took this ticket out of the pool, on the home ticket
    /// only — the away squad spends its own, so nobody claimed it.
    ///
    /// Written in the same commit as `matched`, not before it. The name
    /// survives the two-step design it was born in and still says the right
    /// thing: who claimed this ticket.
    let claimedBy: String?

    /// Server-assigned when the match was committed, and pinned to
    /// `request.time` in the rules so it can't be backdated. This document's
    /// only change stamp — `matchTickets` deliberately carries no `updatedAt`.
    let claimedAt: Date?

    /// The match this ticket was spent on. **Both tickets carry it, and they
    /// carry the same value** — which is the sense in which one match now
    /// refers back to both squads rather than each squad holding its own.
    ///
    /// No longer the handoff it used to be. A waiting squad used to learn it
    /// had been matched by watching this field, because the game landed after
    /// its ticket did; now they land together, and `seasonGames`' own
    /// `array-contains` listener tells both squads directly. What it is for
    /// today is proof: each ticket's rule checks the game named here really
    /// exists after the commit and really casts this squad in this role, which
    /// is what stops a ticket being marked matched by anything other than a
    /// write that is genuinely making that match.
    let matchedGameId: String?

    /// Server-assigned. Ticket age is what drives relaxation.
    let createdAt: Date?

    /// Client-supplied, rules-bounded, and queried against — an expired ticket
    /// leaves the pool without anything having to delete it.
    let expiresAt: Date
}

// MARK: - Stored field names

nonisolated extension MatchTicket {
    /// The document's field names, **next to the coding keys they have to
    /// agree with**.
    ///
    /// Every other collection keeps these in a `private enum Field` inside its
    /// own service, for the stated reason that a write map must not drift from
    /// the model's coding keys. `matchTickets` has two writers in different
    /// files — `MatchmakingService` owns the collection, and
    /// `SeasonGameService.commitMatch` spends both tickets inside the one
    /// transaction that also creates the match — so a private copy in each
    /// would be exactly the drift the pattern exists to prevent. Hoisting them
    /// here serves that intent rather than bending it: there is still one copy,
    /// and it now sits beside the thing it must match.
    enum Field {
        static let squadId = "squadId"
        static let leaderId = "leaderId"
        static let squadName = "squadName"
        static let memberIds = "memberIds"
        static let format = "format"
        static let region = "region"
        static let courtIds = "courtIds"
        static let windowStart = "windowStart"
        static let windowEnd = "windowEnd"
        static let wins = "wins"
        static let losses = "losses"
        static let status = "status"
        static let claimedBy = "claimedBy"
        static let claimedAt = "claimedAt"
        static let matchedGameId = "matchedGameId"
        static let createdAt = "createdAt"
        static let expiresAt = "expiresAt"
    }
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

    /// Whether this ticket may still be spent on a match at `now`.
    ///
    /// Asked of both sides of a candidate pair: of *theirs*, because a spent
    /// ticket is not in the pool, and of *mine*, because a squad that has
    /// already matched must not take anyone else out of it.
    ///
    /// `now` is unused today and kept in the signature deliberately: expiry is
    /// the caller's own check in `MatchRules.candidate`, and dropping the
    /// parameter would invite the next reader to fold expiry in here, where the
    /// two checks would then be made in two places that could drift.
    func isClaimable(at now: Date) -> Bool {
        status == .open
    }

    /// Whether this ticket still represents a live search — the one question
    /// the matchmaking card's "searching" state should ever ask of a ticket.
    ///
    /// A spent ticket outlives its match: nothing deletes it, and it ages out
    /// on `expiresAt` up to a day later. Reading *any* ticket as "still
    /// looking" is what left a squad staring at a search spinner, with a timer
    /// counting up from when they queued, after their match had already been
    /// played and confirmed.
    var isSearching: Bool { status == .open }

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
    /// The squad already has a live match. One live match at a time: queueing
    /// again before it is played, cancelled or aged out is what would put two
    /// in front of the same six people.
    case matchAlreadyScheduled
    /// The ticket was matched or expired between the pool snapshot and the
    /// commit. Expected, not exceptional.
    case claimLost
    case ticketNotFound
    case permissionDenied
    case indexRequired
    case network
    case unknown(String)
}
