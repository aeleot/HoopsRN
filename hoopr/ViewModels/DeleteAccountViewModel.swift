import Combine
import Foundation

/// Deletes the signed-in account and everything that names it (App Review
/// Guideline 5.1.1(v)). Built only while `DeleteAccountSheet` is up.
///
/// **A cross-collection job, so it lives in a view model** like every other
/// join in the app: no service knows about another, and this is the one place
/// that has to walk all of them. What each step does is decided by
/// `AccountDeletionPlan`, which is pure and tested; this class only runs the
/// plan against the services, in order.
///
/// **The order is the design.** Each step needs something a later step
/// destroys:
///
/// 1. *Re-authenticate.* Firebase refuses to delete on an old session, and
///    discovering that at step 6 would leave an account with no data and no way
///    to finish. It is also what stops an unlocked phone being enough.
/// 2. *Season play.* A squad cancels its scheduled match and withdraws its
///    ticket **while it still exists** — only its leader may do either — and is
///    then disbanded (led) or left (joined). Then invites, both directions.
/// 3. *Runs.* Cancel the ones hosted, leave the rest.
/// 4. *Friends.* Every edge and request, then the account's own block list.
/// 5. *Profile.* Last of the Firestore writes, because everything above is
///    authorised by rules that only need the uid, not the profile.
/// 6. *The Auth account.* `AuthService` then publishes `nil`, which returns
///    the app to the login screen and triggers `SessionCleanup` — reminders and
///    on-device history go with the account.
///
/// **Every step is safe to repeat**, so a failure partway — a dropped
/// connection, usually — is finished by tapping Delete again: each step
/// re-reads what is left and does only that.
@MainActor
final class DeleteAccountViewModel: ObservableObject {
    @Published var password = ""
    @Published var confirmation = ""

    @Published private(set) var isDeleting = false

    /// What is happening right now, for the button's label. `nil` when idle.
    @Published private(set) var progress: String?
    @Published private(set) var errorMessage: String?

    /// The address being deleted, shown so there is no doubt which account
    /// this is. Read once: it can't change while the sheet is up.
    let email: String?

    private let authService: AuthService
    private let userProfileService: UserProfileService
    private let gameService: GameService
    private let friendService: FriendService
    private let squadService: SquadService
    private let matchmakingService: MatchmakingService
    private let seasonGameService: SeasonGameService
    private let safetyService: SafetyService

    init(
        authService: AuthService,
        userProfileService: UserProfileService,
        gameService: GameService,
        friendService: FriendService,
        squadService: SquadService,
        matchmakingService: MatchmakingService,
        seasonGameService: SeasonGameService,
        safetyService: SafetyService
    ) {
        self.authService = authService
        self.userProfileService = userProfileService
        self.gameService = gameService
        self.friendService = friendService
        self.squadService = squadService
        self.matchmakingService = matchmakingService
        self.seasonGameService = seasonGameService
        self.safetyService = safetyService
        self.email = authService.currentUser?.email
    }

    var canDelete: Bool {
        Self.canDelete(password: password, confirmation: confirmation, isDeleting: isDeleting)
    }

    nonisolated static func canDelete(password: String, confirmation: String, isDeleting: Bool) -> Bool {
        !isDeleting && !password.isEmpty && AccountDeletionPlan.isConfirmed(confirmation)
    }

    /// Squads the account leads, by name — what the sheet warns will be
    /// disbanded for everyone on them.
    var ledSquadNames: [String] {
        guard let uid = authService.currentUser?.id else { return [] }
        return squadService.squads.filter { $0.leaderId == uid }.map(\.name)
    }

    /// Runs the whole deletion. On success the account is gone and the app is
    /// already on its way to the login screen; there is nothing to dismiss.
    func delete() async {
        guard canDelete, let uid = authService.currentUser?.id else { return }

        isDeleting = true
        errorMessage = nil
        defer {
            isDeleting = false
            progress = nil
        }

        do {
            progress = "Checking your password…"
            try await authService.reauthenticate(password: password)

            progress = "Leaving your squads…"
            let steps = AccountDeletionPlan.squadSteps(
                uid: uid,
                squads: squadService.squads,
                seasonGames: seasonGameService.games
            )
            for step in steps {
                try await run(step)
            }
            try await squadService.deleteEveryInvite()

            progress = "Leaving your runs…"
            try await gameService.leaveEveryRun()

            progress = "Removing your friends list…"
            try await friendService.deleteEveryEdge()
            // The account's own block list. Reports it filed stay: no client
            // may delete one, and they are the moderation record.
            try await safetyService.deleteEveryBlock()

            progress = "Deleting your account…"
            try await userProfileService.deleteProfile()
            try await authService.deleteAccount()
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func run(_ step: AccountDeletionPlan.SquadStep) async throws {
        switch step {
        case .cancelMatch(let gameId, let squadId):
            try await seasonGameService.cancelGame(id: gameId, bySquadId: squadId)
        case .withdrawTicket(let squadId):
            try await matchmakingService.withdrawTicketIfPresent(squadId: squadId)
        case .disband(let squadId):
            try await squadService.disbandSquad(id: squadId)
        case .leave(let squadId):
            try await squadService.leaveSquad(id: squadId)
        }
    }

    // MARK: - Wording

    nonisolated static let wrongPassword = "That password isn't right."

    /// Said after any failure past the password check. It has to be true
    /// whichever step failed, so it promises only what every step guarantees:
    /// nothing is half-broken, and Delete resumes.
    nonisolated static let interrupted =
        "We couldn't finish deleting your account. Nothing is stuck. Tap Delete to pick up where it stopped."

    nonisolated static func message(for error: Error) -> String {
        if let authError = error as? AuthError {
            switch authError {
            case .wrongCredentials:    return wrongPassword
            case .network:             return FailureText.network
            case .tooManyRequests:     return "Too many attempts. Try again in a few minutes."
            case .userDisabled:        return FailureText.accountDisabled
            case .requiresRecentLogin: return "Enter your password again, then tap Delete."
            default:                   return interrupted
            }
        }

        let isNetwork: Bool
        switch error {
        case let error as GameError:        isNetwork = error == .network
        case let error as FriendError:      isNetwork = error == .network
        case let error as SquadError:       isNetwork = error == .network
        case let error as MatchTicketError: isNetwork = error == .network
        case let error as SeasonGameError:  isNetwork = error == .network
        case let error as UserProfileError: isNetwork = error == .network
        case let error as SafetyError:      isNetwork = error == .network
        default:                            isNetwork = false
        }

        return isNetwork ? "\(FailureText.network) \(interrupted)" : interrupted
    }
}
