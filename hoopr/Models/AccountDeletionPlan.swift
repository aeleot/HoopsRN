import Foundation

/// What deleting an account has to do to the documents it appears on, decided
/// without touching Firebase — `DeleteAccountViewModel` executes it, and
/// `AccountDeletionPlanTests` holds it.
///
/// **Everything here is a write the rules already let the owner make.** The
/// app is on the Spark plan, so there is no Cloud Function to clean up after
/// an account; the client does it, in an order where each step still has the
/// authority it needs (a squad can't cancel its match once it's disbanded).
///
/// **What deliberately survives** an account's deletion:
/// - `seasonGames`. They refuse deletes outright — a deletable match is a
///   forgeable record — and already carry both squads' names, so the other
///   squad's history still reads correctly.
/// - Completed runs. The roster rule only admits a change to a live run, so a
///   uid can't be taken off a run that has finished, and deleting a completed
///   run the account hosted would take it out of every other player's history
///   and streak. What stays is an opaque uid that no longer resolves to a
///   profile, a name or an address.
nonisolated enum AccountDeletionPlan {

    // MARK: - Season play

    enum SquadStep: Equatable, Sendable {
        /// Call off a scheduled match, as this squad. Before `disband`, or the
        /// other squad is left "Waiting on…" a report that can never come.
        case cancelMatch(gameId: String, squadId: String)
        /// Take the squad's ticket out of the matchmaking pool, if it has one.
        case withdrawTicket(squadId: String)
        case disband(squadId: String)
        case leave(squadId: String)
    }

    /// The steps for every squad `uid` is on, in the order they must run.
    ///
    /// A squad the account **leads** is disbanded — the leader can't leave,
    /// and a squad whose leader no longer exists can't be edited, queued or
    /// disbanded by anyone. A squad it is merely **on** is left, and nothing
    /// else about that squad changes: its matches are its leader's to keep.
    static func squadSteps(
        uid: String,
        squads: [Squad],
        seasonGames: [SeasonGame]
    ) -> [SquadStep] {
        squads
            .filter { $0.memberIds.contains(uid) }
            .sorted { $0.id < $1.id }
            .flatMap { squad -> [SquadStep] in
                guard squad.leaderId == uid else {
                    return [.leave(squadId: squad.id)]
                }

                let cancels = seasonGames
                    .filter { $0.status == .scheduled && $0.squadIds.contains(squad.id) }
                    .sorted { $0.id < $1.id }
                    .map { SquadStep.cancelMatch(gameId: $0.id, squadId: squad.id) }

                return cancels + [.withdrawTicket(squadId: squad.id), .disband(squadId: squad.id)]
            }
    }

    // MARK: - Runs

    enum RunAction: Equatable, Sendable {
        /// The account hosts it: delete it, which is how a host cancels.
        case cancel
        /// The account is on the roster or the waitlist: take itself off.
        case leave
        /// Finished, or not something the rules let this account change.
        case keep
    }

    /// What to do with one run the account appears on.
    ///
    /// `status` is the stored string rather than `Game.Status`, so a run whose
    /// document no longer decodes is still cleaned up rather than skipped.
    static func runAction(hostId: String, status: String, uid: String) -> RunAction {
        if hostId == uid {
            // A host can delete at any status; a completed run is kept for the
            // other players' history (see the type's doc comment).
            return status == Game.Status.completed.rawValue ? .keep : .cancel
        }

        // The roster rule: `resource.data.status in ['open', 'full']`.
        let takesRosterChanges = [Game.Status.open.rawValue, Game.Status.full.rawValue]
        return takesRosterChanges.contains(status) ? .leave : .keep
    }

    // MARK: - The confirmation

    /// What has to be typed before the button arms.
    static let confirmationWord = "DELETE"

    /// Forgiving about case and stray spaces — the point is that deleting
    /// can't happen by a slip of the thumb, not that it's a spelling test.
    static func isConfirmed(_ typed: String) -> Bool {
        typed.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == confirmationWord
    }
}
