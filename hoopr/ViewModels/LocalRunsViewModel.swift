import Combine
import CoreLocation
import Foundation

/// Backs the Local Runs tab: the runs you're in, and the discoverable ones
/// within your preferred radius.
///
/// The distance filter lives here rather than in `GameService` because it's a
/// join across two sources — Firestore holds the run, the bundled dataset holds
/// the court's coordinates. Same division as `FindAMatchViewModel`, which does
/// its geo math over `CourtService` while the profile listener stays in
/// `UserProfileService`.
@MainActor
final class LocalRunsViewModel: ObservableObject {
    /// A run with its court resolved, ready to render. Distance is computed
    /// once per rebuild, never during scroll.
    /// `nonisolated` for the same reason `Action` below is: it's a plain value
    /// with no isolation to protect, and leaving it on the main actor would put
    /// `friendsHereText` and the rest of its derivations out of reach of a test.
    nonisolated struct Listing: Identifiable, Equatable {
        let game: Game
        /// `nil` when the stored `courtId` no longer matches a court in the
        /// bundled dataset — the run is still shown, since you're committed to
        /// it, but it can't be placed on the map.
        let court: Court?
        let distanceMeters: CLLocationDistance?
        /// Friends already on this run, confirmed or waitlisted. Resolved once
        /// per rebuild for the same reason `distanceMeters` is — never per row
        /// while the list scrolls.
        let friendIds: [String]

        /// `friendIds` defaults so `HomeViewModel`, which builds a `Listing` for
        /// its own read-only next-run card, doesn't have to answer a question
        /// that card never asks.
        init(
            game: Game,
            court: Court?,
            distanceMeters: CLLocationDistance?,
            friendIds: [String] = []
        ) {
            self.game = game
            self.court = court
            self.distanceMeters = distanceMeters
            self.friendIds = friendIds
        }

        var id: String { game.id }

        /// `displayName`, not `name`: every other surface in the app strips the
        /// dataset's "Basketball Court" boilerplate, and a card that didn't
        /// would disagree with the map row the run was started from.
        var courtName: String { court?.displayName ?? "Unknown court" }

        var distanceText: String? {
            distanceMeters.map(Distance.text)
        }

        /// `nil` rather than "0 friends", so the card renders nothing at all
        /// when none of yours are on a run — the same absent-not-empty shape
        /// `distanceText` takes.
        var friendsHereText: String? {
            switch friendIds.count {
            case 0:          nil
            case 1:          "1 friend here"
            case let count:  "\(count) friends here"
            }
        }
    }

    /// What the primary button on a card does, given who's looking at it.
    ///
    /// `nonisolated` because `action(for:currentUserId:)` is: a pure rule that
    /// returns an actor-isolated type can't actually be used from a nonisolated
    /// caller, which is the whole point of extracting it.
    nonisolated enum Action: Equatable {
        case join
        case joinWaitlist
        case leave
        case cancel
        /// The host of a run they can't leave, or a state with nothing to
        /// offer — the card renders a label instead of a button.
        case none

        var title: String {
            switch self {
            case .join:         "Join"
            case .joinWaitlist: "Join waitlist"
            case .leave:        "Leave"
            case .cancel:       "Cancel run"
            case .none:         ""
            }
        }

        /// Leaving and cancelling both take something away, so they read in
        /// the app's error colour rather than its brand one.
        var isDestructive: Bool {
            self == .leave || self == .cancel
        }
    }

    @Published private(set) var queued: [Listing] = []
    @Published private(set) var nearby: [Listing] = []
    @Published private(set) var errorMessage: String?

    /// A listener died and `GameService` is re-attaching it. Distinguishes a
    /// broken list from an empty one, and is what puts "Try again" on the
    /// banner — without it the automatic retry is invisible and the lists just
    /// look empty, which is how the original failure went unnoticed.
    @Published private(set) var isRecovering = false

    /// The radius the public list was actually built with, so the empty state
    /// can name the real number instead of restating a constant.
    @Published private(set) var radiusMiles = UserProfile.defaultPreferredRadius

    /// The run with a write in flight, if any. One at a time: the button that
    /// started it shows a spinner and every other card's button is disabled, so
    /// a double tap can't queue two conflicting transactions.
    ///
    /// Shared by the roster writes and by `complete(_:)`, which isn't one — a
    /// card's two host controls sit side by side after tip-off, and completing
    /// a run while its cancel is still in flight would race a write against a
    /// delete.
    @Published private(set) var pendingGameId: String?

    private let gameService: GameService
    private var cancellables = Set<AnyCancellable>()

    private var queuedGames: [Game] = []
    private var publicGames: [Game] = []
    private var courtsByID: [String: Court] = [:]
    /// The raw edges, not the uids they resolve to. Which uid is *the other
    /// one* depends on who's signed in, and that answer is read per rebuild
    /// rather than captured here — see `rebuild()`.
    private var friendships: [Friendship] = []

    init(
        gameService: GameService,
        courtService: CourtService,
        userProfileService: UserProfileService,
        friendService: FriendService
    ) {
        self.gameService = gameService

        // `sink` with a weak capture rather than `assign(to:on: self)`, which
        // would retain self through self's own cancellable set.
        gameService.$queuedGames
            .receive(on: DispatchQueue.main)
            .sink { [weak self] games in
                self?.queuedGames = games
                self?.rebuild()
            }
            .store(in: &cancellables)

        gameService.$publicGames
            .receive(on: DispatchQueue.main)
            .sink { [weak self] games in
                self?.publicGames = games
                self?.rebuild()
            }
            .store(in: &cancellables)

        // Indexed once per dataset load rather than searched per run: the
        // public list can hold a hundred runs, and a linear scan of 214 courts
        // for each of them is work with no purpose.
        courtService.$courts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] courts in
                self?.courtsByID = Dictionary(
                    courts.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                self?.rebuild()
            }
            .store(in: &cancellables)

        userProfileService.$currentProfile
            .preferredRadiusMiles
            .sink { [weak self] radius in
                self?.radiusMiles = radius
                self?.rebuild()
            }
            .store(in: &cancellables)

        // The cross-collection join `plans/FRIENDS.md` §4 puts here rather than
        // in either service: `GameService` holds the rosters, `FriendService`
        // holds the edges, and neither learns about the other. Live, so a
        // friend joining a run you're looking at updates the card without a
        // refresh.
        friendService.$friends
            .receive(on: DispatchQueue.main)
            .sink { [weak self] friendships in
                self?.friendships = friendships
                self?.rebuild()
            }
            .store(in: &cancellables)

        gameService.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.errorMessage = message
            }
            .store(in: &cancellables)

        gameService.$isRecovering
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecovering in
                self?.isRecovering = isRecovering
            }
            .store(in: &cancellables)
    }

    // MARK: - Derivation

    private func rebuild(now: Date = Date()) {
        let origin = LocationService.homeLocation
        let radiusMeters = Distance.meters(miles: radiusMiles)
        // Read per rebuild rather than captured once, the same way
        // `HomeViewModel` reads the location anchor: a session that signs in
        // after this view model is built would otherwise resolve every
        // friendship against a nil uid and never recover.
        let friendUids = Self.friendUids(from: friendships, currentUserId: currentUserId)

        // The query's cutoff was fixed when its listener attached; re-applying
        // it here is what retires a run during a long-lived session.
        queued = queuedGames
            .filter { $0.isVisible(at: now) }
            .map { listing(for: $0, from: origin, friendUids: friendUids) }

        let joinedIDs = Set(queuedGames.map(\.id))

        nearby = publicGames
            .filter { game in
                // Runs already in the queued section don't repeat here.
                game.isVisible(at: now) && !joinedIDs.contains(game.id)
            }
            .map { listing(for: $0, from: origin, friendUids: friendUids) }
            .filter { listing in
                // A run whose court can't be resolved has no distance, so it
                // can't be shown to be in range — the opposite call from the
                // queued list, where you're already committed.
                guard let distance = listing.distanceMeters else { return false }
                return distance <= radiusMeters
            }
    }

    private func listing(
        for game: Game,
        from origin: CLLocationCoordinate2D,
        friendUids: Set<String>
    ) -> Listing {
        let court = courtsByID[game.courtId]
        return Listing(
            game: game,
            court: court,
            distanceMeters: court.map { Distance.between(origin, $0.coordinate) },
            friendIds: Self.friendIds(on: game, friendUids: friendUids)
        )
    }

    /// Who you're actually friends with, from the edges `FriendService`
    /// publishes.
    ///
    /// `nonisolated static` for the reason `action(for:currentUserId:)` is, and
    /// it earns it: a friendship stores *both* participants, so the obvious
    /// union of `uidA`/`uidB` includes you — and a run you're on would then
    /// count you as one of your own friends. Resolving each edge from your side
    /// is what avoids that, and it's only checkable at all because the rule is
    /// a free function over plain values.
    ///
    /// Signed out reads as no friends rather than trapping, matching
    /// `action(for:currentUserId:)`'s treatment of a nil uid.
    nonisolated static func friendUids(
        from friendships: [Friendship],
        currentUserId uid: String?
    ) -> Set<String> {
        guard let uid else { return [] }
        return Set(friendships.map { $0.otherUid(than: uid) })
    }

    /// Which of your friends are already on a run.
    ///
    /// **Both rosters**, because a friend on the waitlist is the same signal as
    /// a friend holding a spot — you'd be turning up to the same court either
    /// way. Sorted, so an identical rebuild can't reorder a name later phases
    /// may want to render.
    ///
    /// **This widens nothing.** It reads the roster of a run already on screen
    /// and already readable by this account. A friend's *private* run stays
    /// invisible — that needs an authorization design `plans/FRIENDS.md` §4
    /// defers, not a client-side cross-reference.
    nonisolated static func friendIds(on game: Game, friendUids: Set<String>) -> [String] {
        guard !friendUids.isEmpty else { return [] }
        return Set(game.playerIds + game.queuedPlayerIds)
            .intersection(friendUids)
            .sorted()
    }

    // MARK: - Actions

    var currentUserId: String? { gameService.currentUserId }

    func isHost(_ listing: Listing) -> Bool {
        listing.game.isHost(currentUserId)
    }

    func isWaitlisted(_ listing: Listing) -> Bool {
        listing.game.hasWaitlisted(currentUserId)
    }

    func action(for listing: Listing) -> Action {
        Self.action(for: listing.game, currentUserId: currentUserId)
    }

    /// What the primary button does, given who's looking at the run.
    ///
    /// `nonisolated static` and pure so the map's court card can resolve the
    /// same rule without a second copy — two screens offering different buttons
    /// for the same run would be a real bug, and the previous shape made that
    /// only avoidable by discipline. Being pure is also what finally makes it
    /// testable; `GAPS.md` listed it as uncovered.
    ///
    /// Order matters. Hosting outranks membership because a host is always on
    /// their own roster, so checking `hasPlayer` first would offer them "Leave"
    /// for a run only they can cancel.
    nonisolated static func action(for game: Game, currentUserId uid: String?) -> Action {
        if game.isHost(uid) { return .cancel }
        if game.hasPlayer(uid) || game.hasWaitlisted(uid) { return .leave }
        return game.isFull ? .joinWaitlist : .join
    }

    func canComplete(_ listing: Listing, now: Date = Date()) -> Bool {
        Self.canComplete(listing.game, currentUserId: currentUserId, now: now)
    }

    /// Whether the host may mark this run finished.
    ///
    /// **Not an `Action` case, deliberately.** `action(for:currentUserId:)`
    /// returns exactly one thing to offer, and a host already gets `.cancel`;
    /// after tip-off both have to be available at once, which one-of-N can't
    /// express. That function is also shared with `FindAMatchViewModel` for the
    /// map's court card, so a new case would change a second screen for a
    /// control only the Runs tab wants.
    ///
    /// Three conditions, and the rule enforces all three server-side too — this
    /// only decides whether to *show* the control:
    ///
    /// - **The host's alone.** Same shape as cancelling.
    /// - **Not before tip-off.** `>=` rather than `>`: a run is under way the
    ///   instant it starts, and there's nothing to gain from a minute's grace.
    ///   This is the one condition that isn't in the rule — nothing server-side
    ///   forbids completing a run early, and the streak maths reads
    ///   `completedAt`, not `scheduledTime`. It's a UI judgement, not a
    ///   guarantee.
    /// - **Not already completed**, which is what makes a double tap a no-op
    ///   locally instead of a write the rule refuses.
    ///
    /// **The roster isn't consulted.** There's no attendance concept in the
    /// schema, so a completion claims only that the run happened — a host who
    /// turned up alone may record it, and deliberately so. Adding a floor here
    /// would invent a guarantee the server doesn't make.
    ///
    /// `nonisolated static` and pure, like every other rule on this type: it's
    /// the only part of completion that can be tested at all, since nothing in
    /// this suite stands up a service.
    nonisolated static func canComplete(
        _ game: Game,
        currentUserId uid: String?,
        now: Date
    ) -> Bool {
        game.isHost(uid) && now >= game.scheduledTime && game.status != .completed
    }

    func perform(_ action: Action, on listing: Listing) async {
        guard pendingGameId == nil, action != .none else { return }

        pendingGameId = listing.id
        defer { pendingGameId = nil }

        do {
            switch action {
            case .join, .joinWaitlist:
                try await gameService.joinGame(id: listing.id)
            case .leave:
                try await gameService.leaveGame(id: listing.id)
            case .cancel:
                try await gameService.cancelGame(id: listing.id)
            case .none:
                break
            }
            // The listener re-emits the roster the server actually stored, so
            // there's nothing to apply optimistically here.
        } catch {
            // `GameService` already reported it; `errorMessage` is mirrored.
        }
    }

    /// Marks a run finished.
    ///
    /// Separate from `perform(_:on:)` because completion isn't an `Action` —
    /// see `canComplete(_:currentUserId:now:)` — but it shares `pendingGameId`
    /// with it on purpose: one write per card at a time, whichever kind, so
    /// completing can't race the cancel sitting next to it.
    ///
    /// The run disappears from both lists once the listener echoes the write:
    /// `Game.isVisible(at:)` excludes `completed`, so `rebuild()` drops it.
    /// That's the run moving to the Home stats card, not a deletion — which is
    /// what the confirmation dialog on the card is there to set up.
    func complete(_ listing: Listing) async {
        guard pendingGameId == nil else { return }

        pendingGameId = listing.id
        defer { pendingGameId = nil }

        do {
            try await gameService.completeGame(id: listing.id)
        } catch {
            // `GameService` already reported it; `errorMessage` is mirrored.
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    /// Re-attach now instead of waiting out the backoff.
    func retry() {
        gameService.retry()
    }

    // MARK: - Presentation helpers

    var queuedCountText: String {
        queued.count == 1 ? "1 run" : "\(queued.count) runs"
    }

    var nearbyCountText: String {
        nearby.count == 1 ? "1 run" : "\(nearby.count) runs"
    }

    var queuedEmptyText: String {
        "Join a public run below, or start your own from the Court Map."
    }

    var nearbyEmptyText: String {
        "No public runs within \(Int(radiusMiles)) miles. Start one from the Court Map."
    }
}
