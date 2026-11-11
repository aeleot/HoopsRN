import Foundation

/// What the claim transaction decided, and what the scan loop does next.
///
/// **Split out of `MatchmakingService` on purpose.** Every test in this suite
/// targets a `nonisolated static` pure function; no test instantiates a
/// service. So the parts of the claim loop that can be *wrong* — whether a lost
/// race is shown to the user, how many times contention is retried before
/// backing off, how long the jitter is — are decisions here, and
/// `MatchmakingService` merely carries them out. A method that both decides and
/// schedules is, in this project, untestable.
///
/// It handles the two ways a claim fails before any write: contention and a
/// stale pool.
nonisolated enum ClaimOutcome: String, Sendable, Equatable, CaseIterable {
    /// The ticket is ours. Phase 4 turns this into a `seasonGames` document.
    case claimed

    /// Somebody else got there first, or the ticket moved on between the pool
    /// snapshot and the transaction's own read.
    ///
    /// **Expected, not exceptional.** Every queued client sees every new ticket
    /// at once, so losing is the common case in a healthy pool.
    case lost

    /// The ticket was deleted — its leader left the queue — between the
    /// snapshot and the read.
    case missing

    /// The write reached the server and the rules refused it. Distinct from
    /// `lost`: losing is our own in-transaction guard firing, this is the
    /// server's. Both are quiet, and the difference is only visible in logs.
    case refused

    /// The transaction never completed — network, or a transient Firestore
    /// error.
    case failed
}

/// How the scan loop behaves between claims.
///
/// Every constant here is contention tuning, not network tuning. See
/// `retryOwnership` for why that distinction is load-bearing enough to be
/// documented rather than assumed.
nonisolated enum ClaimPolicy {
    /// How many times contention is retried before the loop goes quiet.
    ///
    /// Three. Past that the pool is either genuinely contested
    /// or we are ranking a candidate everybody else ranks first too, and either
    /// way hammering it makes both worse.
    static let maximumAttempts = 3

    /// The quiet poll the loop falls back to once `maximumAttempts` is spent.
    ///
    /// A poll rather than a stop: the pool listener still fires on every
    /// change, but after this much contention the useful signal is time
    /// passing — relaxation widening our own criteria — rather than the next
    /// snapshot.
    static let backOffInterval: TimeInterval = 15

    /// A randomized pause before claiming, so six clients seeing the same new
    /// ticket in the same instant don't all transact in the same instant.
    ///
    /// The cheapest of the thundering-herd mitigations and the only one that helps before
    /// the race rather than after it. At the scale this feature will actually
    /// see it is insurance, not a hot path.
    static let jitter: ClosedRange<TimeInterval> = 0.5...3.0

    /// What the loop does after `outcome`, having already made `attempt`
    /// attempts (1 for the first).
    static func next(after outcome: ClaimOutcome, attempt: Int) -> Step {
        switch outcome {
        case .claimed:
            return .stop
        case .lost, .missing, .refused:
            // Re-scan rather than blindly trying the next candidate: the pool
            // that ranked this one is now known to be stale, so the second-best
            // entry in it is a guess about a snapshot we've just been told is
            // wrong.
            return attempt >= maximumAttempts ? .backOff(backOffInterval) : .rescan
        case .failed:
            // A transaction that never reached the server says nothing about
            // the pool. Backing off is right, and it is the *claim's* back-off,
            // not the listener's — see `retryOwnership`.
            return .backOff(backOffInterval)
        }
    }

    /// Whether the user is told.
    ///
    /// **Only `failed` is ever surfaced, and even then quietly.** Losing a race
    /// is invisible by design: it happens on a document the user never asked
    /// about, it costs them nothing, and the loop is already looking again by
    /// the time a banner could render. A message here would turn the ordinary
    /// operation of a healthy pool into a stream of errors.
    static func isUserFacing(_ outcome: ClaimOutcome) -> Bool {
        outcome == .failed
    }

    /// Whether the search is over.
    static func isTerminal(_ outcome: ClaimOutcome) -> Bool {
        outcome == .claimed
    }

    /// A pause inside `jitter`. Injectable so a test can pin it.
    static func jitterDelay(
        using generator: inout some RandomNumberGenerator
    ) -> TimeInterval {
        TimeInterval.random(in: jitter, using: &generator)
    }

    /// What happens next after a claim attempt.
    enum Step: Equatable, Sendable {
        /// Rank the pool again and try the new top candidate.
        case rescan
        /// Go quiet for this long, then rank again.
        case backOff(TimeInterval)
        /// Stop searching — we have a match.
        case stop
    }

    /// **Which retry belongs to whom**, stated because the next reader will try
    /// to merge them.
    ///
    /// - `ListenerSupervisor` owns retries for the **pool listener**. Its
    ///   subject is network health: a snapshot listener that reports an error
    ///   is already dead, and nothing re-attaches it. Its backoff escalates to
    ///   five minutes and repeats forever, because the failures it exists for —
    ///   an index still building, a ruleset not yet deployed — heal on their own
    ///   and shouldn't need a relaunch.
    /// - `ClaimPolicy` owns retries for the **claim**. Its subject is
    ///   contention: the listener is perfectly healthy, the snapshot arrived,
    ///   and another squad simply got there first.
    ///
    /// Merging them breaks both. A lost race would escalate the listener's
    /// backoff — so a busy pool would end up polling every five minutes, which
    /// is the opposite of what contention calls for — and the listener's
    /// recovery would be reported as a search that is "still looking" when it
    /// is actually broken. `isRecovering` and the quiet back-off state have to
    /// stay two different things because they are two different problems.
    static let retryOwnership = """
        ListenerSupervisor: network health, pool listener, escalating to 5m.
        ClaimPolicy: contention, the claim itself, 3 attempts then a 15s poll.
        """
}
