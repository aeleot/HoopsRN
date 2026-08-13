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
    struct Listing: Identifiable, Equatable {
        let game: Game
        /// `nil` when the stored `courtId` no longer matches a court in the
        /// bundled dataset — the run is still shown, since you're committed to
        /// it, but it can't be placed on the map.
        let court: Court?
        let distanceMeters: CLLocationDistance?

        var id: String { game.id }

        var courtName: String { court?.name ?? "Unknown court" }

        var distanceText: String? {
            distanceMeters.map(Distance.text)
        }
    }

    /// What the primary button on a card does, given who's looking at it.
    enum Action: Equatable {
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

    /// The run with a roster write in flight, if any. One at a time: the
    /// button that started it shows a spinner and every other card's button is
    /// disabled, so a double tap can't queue two conflicting transactions.
    @Published private(set) var pendingGameId: String?

    private let gameService: GameService
    private var cancellables = Set<AnyCancellable>()

    private var queuedGames: [Game] = []
    private var publicGames: [Game] = []
    private var courtsByID: [String: Court] = [:]

    init(
        gameService: GameService,
        courtService: CourtService,
        userProfileService: UserProfileService
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
        // public list can hold a hundred runs, and a linear scan of 213 courts
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
            .map { $0?.effectivePreferredRadius ?? UserProfile.defaultPreferredRadius }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] radius in
                self?.radiusMiles = radius
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

        // The query's cutoff was fixed when its listener attached; re-applying
        // it here is what retires a run during a long-lived session.
        queued = queuedGames
            .filter { $0.isVisible(at: now) }
            .map { listing(for: $0, from: origin) }

        let joinedIDs = Set(queuedGames.map(\.id))

        nearby = publicGames
            .filter { game in
                // Runs already in the queued section don't repeat here.
                game.isVisible(at: now) && !joinedIDs.contains(game.id)
            }
            .map { listing(for: $0, from: origin) }
            .filter { listing in
                // A run whose court can't be resolved has no distance, so it
                // can't be shown to be in range — the opposite call from the
                // queued list, where you're already committed.
                guard let distance = listing.distanceMeters else { return false }
                return distance <= radiusMeters
            }
    }

    private func listing(for game: Game, from origin: CLLocationCoordinate2D) -> Listing {
        let court = courtsByID[game.courtId]
        return Listing(
            game: game,
            court: court,
            distanceMeters: court.map { Distance.between(origin, $0.coordinate) }
        )
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
        let game = listing.game
        let uid = currentUserId

        if game.isHost(uid) { return .cancel }
        if game.hasPlayer(uid) || game.hasWaitlisted(uid) { return .leave }
        return game.isFull ? .joinWaitlist : .join
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
