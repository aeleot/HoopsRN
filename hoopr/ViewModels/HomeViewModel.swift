import Combine
import CoreLocation
import Foundation

/// Backs the Home tab: what you're committed to, and where the action is.
///
/// **Reads nothing new.** Every value here is derived from listeners the app
/// already keeps open for the map and the runs list — `GameService`'s two game
/// arrays, the bundled court dataset, the profile snapshot, and the friend
/// graph. Home costs no extra Firestore read and needs no rules change, which
/// is the whole reason it can ship before any history work exists.
///
/// What it deliberately does *not* show is anything historical. Nothing in the
/// app records that a run happened — `Game.status` never reaches `.completed`
/// and both game listeners are windowed to the future — so "runs this week"
/// and a streak have no source yet and are not faked here.
@MainActor
final class HomeViewModel: ObservableObject {
    /// A court with today's game count, ready for the "Hot right now" list.
    struct HotCourt: Identifiable, Equatable {
        let court: Court
        let gameCount: Int

        var id: String { court.id }
    }

    /// The soonest run you're on, with its court resolved.
    ///
    /// Reuses `LocalRunsViewModel.Listing` rather than declaring a parallel
    /// type: it already carries the court join and the distance formatting
    /// this needs, and a second struct with the same three fields would drift.
    @Published private(set) var nextRun: LocalRunsViewModel.Listing?

    @Published private(set) var hotCourts: [HotCourt] = []

    /// Friend requests waiting on you. Only incoming ones count — a request
    /// you sent isn't yours to answer.
    @Published private(set) var incomingRequestCount = 0

    /// The stored profile name, or a neutral fallback while the first snapshot
    /// is in flight. Matches the greeting the floating header used to carry.
    @Published private(set) var greetingName = "there"

    /// Whether the signed-in user hosts `nextRun`, and whether they're only
    /// waitlisted on it, so the card badges it the same way `GameCard` does on
    /// the runs list rather than inventing a second vocabulary.
    @Published private(set) var isHostingNextRun = false
    @Published private(set) var isWaitlistedOnNextRun = false

    /// How many courts the hot list shows. Three fits above the fold beside
    /// the other cards; the ranking below is written to take any limit.
    static let hotCourtLimit = 3

    // MARK: - Dependencies

    private let courtService: CourtService
    private let gameService: GameService
    private var cancellables = Set<AnyCancellable>()

    /// Where distances are measured from, read from the same seam as every
    /// other distance in the app.
    ///
    /// Computed per read rather than captured at init: the anchor follows the
    /// device now, and a stored copy would freeze Home at Durham while the
    /// map's distances moved — two screens disagreeing about how far away the
    /// same court is.
    private var searchOrigin: CLLocationCoordinate2D { LocationService.homeLocation }

    private var currentUserId: String?

    init(
        authService: AuthService,
        courtService: CourtService,
        gameService: GameService,
        userProfileService: UserProfileService,
        friendService: FriendService
    ) {
        self.courtService = courtService
        self.gameService = gameService

        authService.$currentUser
            .map(\.?.id)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] uid in
                self?.currentUserId = uid
                self?.rebuildNextRun()
            }
            .store(in: &cancellables)

        userProfileService.$currentProfile
            .map { $0?.userName ?? "there" }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] name in self?.greetingName = name }
            .store(in: &cancellables)

        friendService.$incomingRequests
            .map(\.count)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] count in self?.incomingRequestCount = count }
            .store(in: &cancellables)

        // The court dataset feeds both derived lists — the hot list needs the
        // court behind each id, and the next run needs its court resolved for
        // a name and a distance.
        courtService.$courts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildNextRun()
                self?.rebuildHotCourts()
            }
            .store(in: &cancellables)

        // Two listeners, not one: a run you host publicly arrives on both, so
        // the count below dedupes by id rather than concatenating.
        gameService.$queuedGames
            .combineLatest(gameService.$publicGames)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] queued, published in
                self?.rebuildNextRun(queued: queued)
                self?.rebuildHotCourts(queued: queued, published: published)
            }
            .store(in: &cancellables)
    }

    // MARK: - Ranking

    /// Today's busiest courts, most games first.
    ///
    /// `nonisolated static` and pure so the ranking can be tested without
    /// constructing a service or touching Firebase — the same shape
    /// `FindAMatchViewModel.gameCountsByCourt` and `Game.validate` already use.
    ///
    /// Ties break on `displayName`, not on dictionary order: a `[String: Int]`
    /// has no stable iteration order, so without a second key the list would
    /// reshuffle itself between rebuilds while showing identical numbers.
    /// Courts absent from `counts` have nothing scheduled and are dropped
    /// rather than rendered as a zero — a hot list of cold courts is noise.
    nonisolated static func rankHotCourts(
        counts: [String: Int],
        courts: [Court],
        limit: Int
    ) -> [HotCourt] {
        guard limit > 0 else { return [] }

        return courts
            .compactMap { court in
                guard let count = counts[court.id], count > 0 else { return nil }
                return HotCourt(court: court, gameCount: count)
            }
            .sorted { lhs, rhs in
                lhs.gameCount == rhs.gameCount
                    ? lhs.court.displayName < rhs.court.displayName
                    : lhs.gameCount > rhs.gameCount
            }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: - Rebuilds

    private func rebuildHotCourts(
        queued: [Game]? = nil,
        published: [Game]? = nil
    ) {
        let counts = FindAMatchViewModel.gameCountsByCourt(
            queued: queued ?? gameService.queuedGames,
            published: published ?? gameService.publicGames
        )

        hotCourts = Self.rankHotCourts(
            counts: counts,
            courts: courtService.courts,
            limit: Self.hotCourtLimit
        )
    }

    /// `queuedGames` arrives sorted soonest-first and is already windowed to
    /// drop anything more than three hours past its start, so the first
    /// element is the run to show. A run that started an hour ago is still the
    /// one you're at, which is why this doesn't skip past it to the next one.
    private func rebuildNextRun(queued: [Game]? = nil) {
        let games = queued ?? gameService.queuedGames

        guard let game = games.first else {
            nextRun = nil
            isHostingNextRun = false
            isWaitlistedOnNextRun = false
            return
        }

        let court = courtService.courts.first { $0.id == game.courtId }

        nextRun = LocalRunsViewModel.Listing(
            game: game,
            court: court,
            distanceMeters: court.map { Distance.between(searchOrigin, $0.coordinate) }
        )
        isHostingNextRun = game.isHost(currentUserId)
        isWaitlistedOnNextRun = game.hasWaitlisted(currentUserId)
    }
}
