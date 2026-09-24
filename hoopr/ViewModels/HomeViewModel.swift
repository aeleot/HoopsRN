import Combine
import CoreLocation
import Foundation

/// Backs the Home tab: what you're committed to, and where the action is.
///
/// Every *displayed* value here is derived from listeners the app already
/// keeps open for the map and the runs list — `GameService`'s game arrays,
/// the bundled court dataset, the profile snapshot, and the friend graph —
/// costing no extra Firestore read.
///
/// One write lives here too, and it's the exception to "just reshapes what's
/// already published": whenever `GameService.completedGames` delivers a new
/// snapshot, this recalculates participation stats and writes them back via
/// `UserProfileService.refreshStats`. `HomeViewModel` is where both services
/// are already held for the subscriptions below, so that's the trigger point
/// rather than a new dependency between the two services themselves.
/// Wraps the three profile fields the stats subscription cares about so
/// `.removeDuplicates()` has something `Equatable` to compare — bare Swift
/// tuples aren't.
private struct ProfileStats: Equatable {
    let count: Int
    let streak: Int
    let lastCompletedAt: Date?
}

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

    /// The one historical note on this screen — sourced from the profile
    /// snapshot, not computed here. All three default to the "no history yet"
    /// values (`0`/`0`/`"—"`) until the first `refreshStats` write lands, and
    /// reset to them again on sign-out.
    @Published private(set) var completedGameCount = 0
    @Published private(set) var participationStreak = 0
    @Published private(set) var lastCompletedText = "—"

    /// Hides the stats card entirely for a brand-new account rather than
    /// showing it with all-zero values.
    var hasStats: Bool { completedGameCount > 0 }

    /// Whether the games listener has delivered its first snapshot.
    ///
    /// **Without this the screen cannot tell "you have no run tonight" from
    /// "we haven't looked yet"**, and it showed the first while meaning the
    /// second for however long the listener took — the empty state's call to
    /// action flashing at a user who is, in fact, signed up for something.
    /// `GameService.hasLoadedGames` has carried the answer all along;
    /// `MapViewModel` already consumes it. This is the same value, not
    /// a new read.
    @Published private(set) var hasLoaded = false

    /// A listener failure, in the domain's words rather than Firebase's.
    ///
    /// Home had **no error state at all**: a dead listener rendered as an
    /// empty screen, which is the one reading this tab exists for and the one
    /// it must not get wrong silently. Republished from `GameService` rather
    /// than translated again here — the service owns the vocabulary.
    @Published private(set) var errorMessage: String?

    /// The supervisor is re-attaching a dropped listener. Distinguished from
    /// `errorMessage` because it is not a thing the user can act on, and a
    /// banner that cries wolf during a normal network blip trains them to
    /// ignore it.
    @Published private(set) var isRecovering = false

    /// The hero's two halves, split apart.
    ///
    /// `Game.scheduledText()` returns "Today · 6:30 PM" as one string, which
    /// was right when the card set it as a single 14pt line. The band sets the
    /// day as a label and the time as the screen's hero numeral, so they have
    /// to arrive separately — and both derive from the same `scheduledTime`,
    /// so the two can't disagree.
    ///
    /// Each of these is a thin wrapper over a `nonisolated static` function,
    /// for the reason the rest of this file is: the rule can then be tested
    /// without constructing a service or touching Firebase.
    var nextRunDayLabel: String {
        nextRun?.game.dayText() ?? "Tonight"
    }

    /// The time alone — "6:30 PM". The hero.
    var nextRunTimeText: String {
        nextRun?.game.timeText ?? "—"
    }

    /// Spots left, not "N / M players".
    ///
    /// The decision this screen supports is *can I still get on it* — one
    /// number, not a ratio to do arithmetic on. `rosterText` stays on
    /// `GameCard`, where the roster itself is the subject.
    var nextRunSpotsText: String? {
        nextRun?.game.spotsText
    }

    // MARK: - Hero text rules

    /// **The day, time and spots rules live on `Game`**, beside `rosterText`
    /// and `scheduledText()` — that is where this codebase already keeps a
    /// run's presentation strings, and putting a second copy here would mean
    /// `GameCard` and this band could drift into disagreeing about what "6:45"
    /// or "Tonight" means for the same run.

    /// How many courts the hot list shows. Three fits above the fold beside
    /// the other cards; the ranking below is written to take any limit.
    static let hotCourtLimit = 3

    // MARK: - Dependencies

    private let courtService: CourtService
    private let gameService: GameService
    private let userProfileService: UserProfileService
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
        self.userProfileService = userProfileService

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

        // Its own subscription rather than folded into the greeting sink
        // above — stats are a separate concern. The `?? 0`/`nil` defaults
        // are load-bearing: they cover both a pre-`refreshStats` profile
        // (the Int fields are optional until that first write) and a
        // sign-out, which sets `currentProfile` to `nil` and must reset
        // this card to the same "no history" defaults rather than holding
        // onto the previous account's numbers for a frame.
        userProfileService.$currentProfile
            .map { profile in
                ProfileStats(
                    count: profile?.completedGameCount ?? 0,
                    streak: profile?.participationStreak ?? 0,
                    lastCompletedAt: profile?.lastCompletedAt
                )
            }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] stats in
                self?.completedGameCount = stats.count
                self?.participationStreak = stats.streak
                self?.lastCompletedText = Self.lastCompletedText(for: stats.lastCompletedAt)
            }
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

        // Loading, failure and recovery, republished as-is. None of the three
        // is derived here: the service is what knows, and a second opinion
        // would be a second thing to keep in step.
        gameService.$hasLoadedGames
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasLoaded in self?.hasLoaded = hasLoaded }
            .store(in: &cancellables)

        gameService.$errorMessage
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in self?.errorMessage = message }
            .store(in: &cancellables)

        gameService.$isRecovering
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecovering in self?.isRecovering = isRecovering }
            .store(in: &cancellables)

        // The one write in this file — see the type doc comment. Guarded on
        // a non-empty snapshot so a brand-new account with zero completions
        // never issues a write; `refreshStats` only has meaningful lazy-init
        // work to do once there's at least one completed run.
        gameService.$completedGames
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completedGames in
                guard let self, let uid = self.gameService.currentUserId, !completedGames.isEmpty else {
                    return
                }
                Task {
                    try? await self.userProfileService.refreshStats(for: uid, using: completedGames)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Choosing the next run

    /// The soonest run you're on that is still worth showing.
    ///
    /// **Filtered by `isVisible(at:)`, which this used not to be — and the
    /// gap only mattered once the redesign made this run the screen's hero.**
    /// The queued listener selects by roster and time window, not by status
    /// (`GameService`), so a run the host has marked complete stays in
    /// `queuedGames` for the rest of `Game.visibilityGrace`. The Runs tab and
    /// the map's court card both drop it with `isVisible(at:)`. Home took
    /// `queuedGames.first` as it came, so for up to four hours after a run was
    /// recorded as over, the biggest thing on the app's first screen announced
    /// it as tonight's — with its spots left and a way in. Seen in the live app
    /// on 2026-09-22 with the map saying "No runs here today" about the same
    /// court.
    ///
    /// The listener delivers runs soonest-first, so the first visible one is
    /// the answer. `nonisolated static` so the rule can be tested without a
    /// service, like `rankHotCourts` below.
    nonisolated static func nextRun(from games: [Game], at now: Date = Date()) -> Game? {
        games.first { $0.isVisible(at: now) }
    }

    // MARK: - Ranking

    /// Today's busiest courts, most games first.
    ///
    /// `nonisolated static` and pure so the ranking can be tested without
    /// constructing a service or touching Firebase — the same shape
    /// `MapViewModel.gameCountsByCourt` and `Game.validate` already use.
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

    // MARK: - Formatting

    /// The stats card's "Last" column. `nonisolated static` and pure, same
    /// shape as `rankHotCourts` above, so it's testable without constructing
    /// a service.
    ///
    /// Uses `Calendar.current`, not the UTC/ISO-8601 calendar
    /// `Game.calculateStreak` buckets weeks with — that one has to agree
    /// across devices for a server-trusted count; this is displaying a single
    /// date to the person looking at their own phone, the same reasoning
    /// `Game.scheduledText(relativeTo:)` already uses `Calendar.current` for.
    ///
    /// Deliberately drops the year (`"MMMd"`) — a completion from last year
    /// still reads as e.g. "Aug 15". A simplification, not an oversight.
    nonisolated static func lastCompletedText(for date: Date?, relativeTo now: Date = Date()) -> String {
        guard let date else { return "—" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return lastCompletedDateFormatter.string(from: date)
    }

    private static let lastCompletedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter
    }()

    // MARK: - Rebuilds

    private func rebuildHotCourts(
        queued: [Game]? = nil,
        published: [Game]? = nil
    ) {
        let counts = MapViewModel.gameCountsByCourt(
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
        guard let game = Self.nextRun(from: queued ?? gameService.queuedGames) else {
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
