import Combine
import Foundation

/// Backs `InviteJoinSheet`: one run, opened from an invite link, and the one
/// thing to do about it.
///
/// Built per presentation, like `CreateGameViewModel`. It joins `GameService`
/// (the run) to `CourtService` (where it is) — a cross-collection join, so it
/// lives here rather than in either service.
///
/// **Joining goes through `GameService.joinGame(id:)`**, the same self-join
/// write the Runs board and the map's court card use. There is no second join
/// path into `games`: an invite changes how you *find* a run, not how you get
/// on it.
@MainActor
final class InviteJoinViewModel: ObservableObject {
    /// Where the link landed. The states a link can reach, named by what the
    /// sheet has to say about each rather than by the data that produces them.
    enum Phase: Equatable {
        case loading
        case loaded(Game)
        /// No such run: cancelled, or a link that never named one.
        case missing
        /// The read failed — offline, or the rules on the server refused it.
        case failed(String)
    }

    /// What a loaded run means to the person holding the link.
    ///
    /// `nonisolated` so `landing(for:currentUserId:now:)` — the rule that
    /// decides it — is a pure function a test can call directly, the same
    /// treatment `LocalRunsViewModel.Action` gets.
    nonisolated enum Landing: Equatable {
        /// Room on the roster.
        case join
        /// Full, so what's on offer is the waitlist.
        case waitlist
        case hosting
        case onRoster
        case onWaitlist
        /// Completed by its host, or past `Game.visibilityGrace` — gone from
        /// every list, and not worth joining even though the rule would allow
        /// it for a run nobody completed.
        case over

        /// The roster write this landing offers, if any — `LocalRunsViewModel`'s
        /// own `Action`, so the button reads exactly as it does on the board.
        var action: LocalRunsViewModel.Action? {
            switch self {
            case .join:     .join
            case .waitlist: .joinWaitlist
            case .hosting, .onRoster, .onWaitlist, .over: nil
            }
        }
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var isJoining = false
    /// A join the server refused, said inline under the button. Cleared by the
    /// next attempt.
    @Published private(set) var joinError: String?
    /// Bumped by every join the server accepted, for the success haptic. Never
    /// by a load: arriving on a run you're already on isn't a confirmation.
    @Published private(set) var joinCount = 0

    let gameId: String
    private let gameService: GameService
    private let courtService: CourtService

    init(gameId: String, gameService: GameService, courtService: CourtService) {
        self.gameId = gameId
        self.gameService = gameService
        self.courtService = courtService
    }

    // MARK: - Reading the run

    /// Reads the run. Re-runnable, which is what "Try again" calls.
    ///
    /// `quietly` keeps the run already on screen while re-reading it after a
    /// join, so the sheet doesn't flash back to a spinner — only a run that
    /// has since vanished replaces it.
    func load(quietly: Bool = false) async {
        if !quietly { phase = .loading }

        do {
            if let game = try await gameService.fetchGame(id: gameId) {
                phase = .loaded(game)
            } else {
                phase = .missing
            }
        } catch let error as GameError {
            // A quiet reload that fails keeps what's on screen: the run was
            // readable a moment ago, and the join's own outcome is already said.
            guard !quietly else { return }
            phase = .failed(Self.loadMessage(for: error))
        } catch {
            guard !quietly else { return }
            phase = .failed(Self.loadMessage(for: .unknown(error.localizedDescription)))
        }
    }

    /// The sentence for a run that couldn't be read.
    ///
    /// `GameService.message(for:whileDoing:context:)` with `.load`, so a
    /// refused read says "rules probably not deployed" — which, for this read,
    /// is exactly right: the `get`/`list` split only exists in a ruleset that
    /// has been deployed since 2026-10-08, and the one before it refuses every
    /// stranger. `gameNotFound` never reaches here; a missing run is `.missing`.
    nonisolated static func loadMessage(for error: GameError) -> String {
        // The service's `.load` sentence names "runs" — its listeners' subject.
        // This read is one run, under a heading that already says "invite".
        if error == .permissionDenied {
            return FailureText.rulesNotDeployed(loading: "this run")
        }
        return GameService.message(for: error, whileDoing: "opening this invite", context: .load)
    }

    // MARK: - What it means

    var landing: Landing? {
        guard case .loaded(let game) = phase else { return nil }
        return Self.landing(for: game, currentUserId: gameService.currentUserId, now: Date())
    }

    /// What a run means to `uid`, at `now`.
    ///
    /// **Over outranks everything**, the host included: a run that has
    /// wrapped up has nothing to offer anyone, and "This is your run" over a
    /// game from yesterday would read as if it were still on. Past that, the
    /// order is `LocalRunsViewModel.action(for:currentUserId:)`'s — hosting
    /// before membership, because a host is always on their own roster.
    ///
    /// `isVisible(at:)` is the board's own test for "still listed", so a run
    /// leaves the invite sheet's joinable states at the same instant it leaves
    /// the Runs tab.
    nonisolated static func landing(for game: Game, currentUserId uid: String?, now: Date) -> Landing {
        if !game.isVisible(at: now) { return .over }
        if game.isHost(uid) { return .hosting }
        if game.hasPlayer(uid) { return .onRoster }
        if game.hasWaitlisted(uid) { return .onWaitlist }
        return game.isFull ? .waitlist : .join
    }

    // MARK: - Joining

    /// Joins the run — a seat if there is one, the waitlist if not.
    ///
    /// Re-reads afterwards **whatever happened**: on success that turns the
    /// sheet into "You're on this run" from the server's own copy rather than
    /// an optimistic guess; on failure it shows *why* — the run filled, was
    /// completed, or was called off while the sheet was open.
    func join() async {
        guard !isJoining, landing?.action != nil else { return }

        isJoining = true
        joinError = nil
        defer { isJoining = false }

        do {
            try await gameService.joinGame(id: gameId)
            joinCount += 1
        } catch let error as GameError {
            joinError = GameService.message(for: error, whileDoing: "joining the run", context: .write)
        } catch {
            joinError = GameService.message(
                for: .unknown(error.localizedDescription),
                whileDoing: "joining the run",
                context: .write
            )
        }

        await load(quietly: true)
    }

    // MARK: - What the sheet says

    /// A heading and the sentence under it.
    nonisolated struct Copy: Equatable {
        let title: String
        let message: String?
    }

    /// **Each one is a claim the app has to keep**, so each is pinned by
    /// `InviteJoinTests`. Two are load-bearing:
    ///
    /// - **The waitlist never promotes** — the update rule forbids writing
    ///   another player's uid (`gaps/GAMES.md`), so both waitlist states say
    ///   so, in `Game.waitlistCaveat` — the board's own words. A waitlist
    ///   offered as a queue would be the one place this sheet over-promised.
    /// - **Hosting says the link is the key.** Anyone holding it can open the
    ///   run and join — that is the authorization model the `get`/`list` split
    ///   chose — and the person handing it out should know.
    nonisolated static func copy(for landing: Landing) -> Copy {
        switch landing {
        case .join:
            Copy(title: "You're invited", message: "Join and you're on the roster.")
        case .waitlist:
            Copy(
                title: "This run is full",
                message: "You can join the waitlist. \(Game.waitlistCaveat)"
            )
        case .hosting:
            Copy(
                title: "This is your run",
                message: "Anyone you send this link to can open it and join."
            )
        case .onRoster:
            Copy(title: "You're on this run", message: "It's on your Runs tab.")
        case .onWaitlist:
            Copy(title: "You're on the waitlist", message: Game.waitlistCaveat)
        case .over:
            Copy(
                title: "This run is over",
                message: "It's wrapped up and off the board. Ask the host about the next one."
            )
        }
    }

    /// A link to a run that isn't there. Cancelled is by far the likeliest
    /// reason; a link cut short in transit is the other.
    nonisolated static let missingCopy = Copy(
        title: "This run was called off",
        message: "The host cancelled it, or the link is incomplete."
    )

    // MARK: - Presentation

    private var court: Court? {
        guard case .loaded(let game) = phase else { return nil }
        return courtService.courts.first { $0.id == game.courtId }
    }

    /// `displayName`, the same as every other surface. A stale court ID still
    /// shows the run — "Unknown court", as the board does.
    var courtName: String { court?.displayName ?? "Unknown court" }

    var city: String? {
        guard let city = court?.city, !city.isEmpty else { return nil }
        return city
    }

    /// From `LocationService.homeLocation`, the one anchor every distance in
    /// the app is measured from.
    var distanceText: String? {
        court.map { Distance.text(Distance.between(LocationService.homeLocation, $0.coordinate)) }
    }
}
