import Combine
import CoreLocation
import Foundation
import MapKit

/// A court paired with its distance from the user, computed once when the list
/// is built so the view never does geo math while scrolling.
nonisolated struct NearbyCourt: Identifiable, Equatable {
    let court: Court
    let distanceMeters: CLLocationDistance

    var id: String { court.id }

    var distanceText: String { Distance.text(distanceMeters) }
}

/// A court with today's runs attached, for the **Now** segment.
///
/// Parallel to `NearbyCourt` rather than an extension of it. `NearbyCourt` is a
/// pure court-and-distance pairing that `CourtRow` and two other segments
/// depend on; bolting an always-empty `[Game]` onto it would put a nullable
/// concept into a type whose whole job is a distance.
nonisolated struct ActiveCourt: Identifiable, Equatable {
    let court: Court
    let distanceMeters: CLLocationDistance
    /// Today's runs here, soonest first. **Never empty** — a court with nothing
    /// on isn't in this list at all, which is what lets `leadGame` be
    /// non-optional.
    let games: [Game]

    var id: String { court.id }

    var distanceText: String { Distance.text(distanceMeters) }

    /// The run this row is about: the one underway if there is one, and the
    /// next to tip off otherwise. Safe to subscript because `games` is never
    /// empty — see its note.
    var leadGame: Game { games[0] }

    /// e.g. "+1 more today", or `nil` when the lead game is the only one.
    var additionalGamesText: String? {
        let extra = games.count - 1
        guard extra > 0 else { return nil }
        return "+\(extra) more today"
    }
}

final class FindAMatchViewModel: ObservableObject {
    /// Which list the sheet is showing.
    ///
    /// `Recent` used to be the third segment. It moved to the search field's
    /// empty state — the standard iOS home for recents — which freed the slot
    /// for `now` without adding a control.
    enum ListTab: String, CaseIterable, Identifiable {
        /// Courts with a run on today, soonest first. The tab's reason to
        /// exist: the map answers "is anyone playing", and this is that answer
        /// in list form.
        case now
        /// Every court inside the profile's radius, nearest first.
        case nearby
        /// Favourites. Was `favorites`; renamed for the segment's width budget,
        /// not its meaning.
        case saved

        var id: String { rawValue }

        var title: String {
            switch self {
            case .now:    "Now"
            case .nearby: "Nearby"
            case .saved:  "Saved"
            }
        }
    }

    // MARK: - Published state

    /// Courts drawn on the map — every court that passes the active filters,
    /// regardless of distance.
    @Published private(set) var courts: [Court] = []

    /// The rows in the sheet for the `.nearby` and `.saved` segments, already
    /// filtered and ordered. Empty while `.now` is showing — that segment
    /// renders `activeCourts` instead.
    @Published private(set) var listedCourts: [NearbyCourt] = []

    /// The rows in the sheet for the `.now` segment.
    @Published private(set) var activeCourts: [ActiveCourt] = []

    /// Courts opened recently, most recent first.
    ///
    /// Published for the search field's empty state, which is where Recent
    /// lives now that it isn't a segment.
    @Published private(set) var recentCourts: [Court] = []

    @Published var selectedTab: ListTab = .now {
        didSet { rebuild() }
    }

    /// What's typed in the map's search field.
    ///
    /// **Not debounced.** `FriendsViewModel` debounces because every keystroke
    /// there is a Firestore query; this is `localizedCaseInsensitiveContains`
    /// over 214 rows already in memory, and the home-court picker has run it
    /// undebounced on every keystroke since it shipped. A delay here would just
    /// be the results list visibly lagging the caret.
    @Published var searchQuery: String = "" {
        didSet {
            guard searchQuery != oldValue else { return }
            rebuildSearchResults()
        }
    }

    /// Courts matching `searchQuery`, empty while the query is blank.
    @Published private(set) var searchResults: [Court] = []

    @Published private(set) var activeFilters: Set<CourtFilter> = []

    @Published private(set) var favoriteCourtIds: Set<String> = []

    /// The radius the nearby list was actually built with — the profile's
    /// preference, or the default while signed out or before the first
    /// snapshot lands. Published so the empty state can name the real number
    /// rather than restating a constant that may not be the one in force.
    @Published private(set) var radiusMiles: Double = UserProfile.defaultPreferredRadius

    /// Set when the bundled court dataset failed to load, so the empty state
    /// can say *why* the list is empty. Without it an unreadable bundle is
    /// indistinguishable from "no courts near you" — the same list, the same
    /// wording, and nothing to act on.
    @Published private(set) var datasetError: String?

    /// The first device fix, published exactly once.
    ///
    /// `MapView` reads `initialRegion` only in `makeUIView`, so a fix that
    /// lands after the map exists has no other route onto it. `MapTab` watches
    /// this and turns it into a single `RecenterTrigger`. Later fixes
    /// deliberately don't republish: a map that re-centres itself while you're
    /// panning is worse than one that opened in the wrong place.
    @Published private(set) var initialFix: CLLocationCoordinate2D?

    /// Today's runs at each court, keyed by `Court.id`, soonest first.
    ///
    /// Built from `gameService.queuedGames` and `.publicGames` — the same two
    /// listeners `LocalRunsViewModel` already reads — rather than a new query.
    /// That's not just cheaper, it's the only thing that keeps this private:
    /// those two arrays are exactly what the read rule already lets this
    /// account see (public runs, plus runs it's personally on), so nothing
    /// derived from them can reveal a private run this account isn't part of.
    /// The union is deduplicated by `Game.id` first — a public run the
    /// signed-in user is also on would otherwise arrive in both arrays and be
    /// counted, and listed, twice.
    ///
    /// This replaced a stored count map. Holding the games rather than their
    /// tally is what lets the sheet show *when* a run is and whether it has
    /// room, instead of reducing all of that to a pin colour.
    @Published private(set) var gamesByCourtID: [String: [Game]] = [:]

    /// How many games are scheduled **today** at each court. Feeds the map's
    /// pins via `CourtHeat` and their numeric badges.
    ///
    /// Derived rather than stored alongside `gamesByCourtID`, so the two can't
    /// drift out of step.
    var gameCountByCourtID: [String: Int] { gamesByCourtID.mapValues(\.count) }

    // MARK: - Tuning

    /// The app-wide anchor, which now follows the device — see
    /// `LocationService.homeLocation`.
    static var homeLocation: CLLocationCoordinate2D { LocationService.homeLocation }

    /// Where the map opens before any fix has landed.
    ///
    /// Read once, in `MapView.makeUIView`, so it can't carry a later fix. That
    /// is what `initialFix` is for: a fix arriving after the map exists reaches
    /// it as a `RecenterTrigger`, which routes through `biasedNorth(_:)` like
    /// every other region change.
    let initialRegion = MKCoordinateRegion(
        center: FindAMatchViewModel.homeLocation,
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    // MARK: - Dependencies

    private let courtService: CourtService
    private let locationService: LocationService
    private let userProfileService: UserProfileService
    private let gameService: GameService
    private let recentCourtsStore: RecentCourtsStore
    private var cancellables = Set<AnyCancellable>()

    /// Where distances are measured from.
    ///
    /// Follows the device rather than being fixed for the life of the view
    /// model, but still isn't the map's centre: panning changes what you're
    /// looking at, not where you are. Seeded from `homeLocation` so the first
    /// list is built against Durham rather than nothing, then replaced when a
    /// fix arrives.
    private var searchOrigin: CLLocationCoordinate2D
    private var recentCourtIds: [String] = []

    /// Whether the opening segment has been decided — see
    /// `chooseInitialTabIfNeeded()`.
    private var hasChosenInitialTab = false

    init(
        courtService: CourtService,
        locationService: LocationService,
        userProfileService: UserProfileService,
        gameService: GameService,
        recentCourtsStore: RecentCourtsStore
    ) {
        self.courtService = courtService
        self.locationService = locationService
        self.userProfileService = userProfileService
        self.gameService = gameService
        self.recentCourtsStore = recentCourtsStore
        self.searchOrigin = Self.homeLocation

        // The device fix moves the origin every distance is measured from, so
        // the whole list reflows when one lands. `initialFix` is set only the
        // first time — see its note.
        locationService.$coordinate
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] fix in
                guard let self else { return }
                self.searchOrigin = fix
                if self.initialFix == nil { self.initialFix = fix }
                self.rebuild()
            }
            .store(in: &cancellables)

        courtService.$courts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)

        courtService.$loadError
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in self?.datasetError = message }
            .store(in: &cancellables)

        // The nearby list depends on the saved radius as well as the dataset
        // and filters, so it rebuilds when the radius moves. Editing the
        // radius in the profile reflows this list without a reload.
        //
        // Distances are still measured from the hardcoded home location; swap
        // `homeLocation` for a profile-owned one and this pipeline follows.
        userProfileService.$currentProfile
            .preferredRadiusMiles
            .sink { [weak self] radius in
                self?.radiusMiles = radius
                self?.rebuild()
            }
            .store(in: &cancellables)

        // Favourites arrive on the profile listener that `UserProfileService`
        // already keeps open, so starring a court costs no extra read.
        userProfileService.$currentProfile
            .map { Set($0?.favoriteCourtIds ?? []) }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ids in
                self?.favoriteCourtIds = ids
                self?.rebuild()
            }
            .store(in: &cancellables)

        recentCourtsStore.$recentCourtIds
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ids in
                self?.recentCourtIds = ids
                self?.rebuild()
            }
            .store(in: &cancellables)

        // Two listeners, not one: a game hosted publicly by the signed-in user
        // arrives on both, which is exactly why `rebuildGameCounts` dedupes by
        // id rather than just concatenating the two arrays.
        gameService.$queuedGames
            .combineLatest(gameService.$publicGames)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] queued, published in
                self?.rebuildGameCounts(queued: queued, published: published)
            }
            .store(in: &cancellables)

        // Watched directly rather than inferred from the arrays above, so the
        // opening segment doesn't depend on the order two publishers happen to
        // fire in. `rebuild()` ends by calling `chooseInitialTabIfNeeded()`.
        gameService.$hasLoadedGames
            .removeDuplicates()
            .filter { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
    }

    // MARK: - Filters

    func toggle(_ filter: CourtFilter) {
        if activeFilters.contains(filter) {
            activeFilters.remove(filter)
        } else {
            activeFilters.insert(filter)
        }
        rebuild()
    }

    func isActive(_ filter: CourtFilter) -> Bool {
        activeFilters.contains(filter)
    }

    // MARK: - Favourites and recents

    func isFavorite(_ court: Court) -> Bool {
        favoriteCourtIds.contains(court.id)
    }

    /// Optimistic: the star flips immediately and Firestore catches up. If the
    /// write fails the profile listener re-emits the server's truth and the
    /// star reverts on its own.
    func toggleFavorite(_ court: Court) {
        let shouldFavorite = !isFavorite(court)
        if shouldFavorite {
            favoriteCourtIds.insert(court.id)
        } else {
            favoriteCourtIds.remove(court.id)
        }
        rebuild()

        Task { [userProfileService] in
            try? await userProfileService.setFavorite(
                courtId: court.id,
                isFavorite: shouldFavorite
            )
        }
    }

    func select(_ court: Court) {
        recentCourtsStore.record(courtId: court.id)
    }

    // MARK: - Map

    /// Where the recenter button sends the map: the device, once there's a
    /// fix, and Durham until then.
    ///
    /// Still doesn't block on the permission prompt. Asking and then waiting
    /// for an answer would leave the map motionless under a finger that just
    /// tapped a button, so the first tap moves the map to whatever anchor is
    /// current and the fix — if the user grants it — arrives through
    /// `$coordinate` a moment later.
    func recenterTarget() -> CLLocationCoordinate2D {
        switch locationService.authorizationStatus {
        case .notDetermined:
            locationService.requestLocationPermission()
        case .authorizedWhenInUse, .authorizedAlways:
            // Already granted, but updates stop when the app is backgrounded;
            // this is what restarts them for a session that never saw an
            // authorization *change* to trigger the delegate.
            locationService.startUpdatingLocation()
        default:
            break
        }
        return searchOrigin
    }

    /// Distance to an arbitrary court, measured from the same origin the list
    /// uses. The detail card needs this and holds a bare `Court` — both of its
    /// entry points (a map pin and a list row) converge on the card, and the
    /// pin never had a `NearbyCourt` to carry the precomputed figure.
    ///
    /// Safe to call per render: it's one `CLLocation.distance(from:)`, not the
    /// whole-dataset sort that `ranked(courts:from:)` does.
    func distanceText(for court: Court) -> String {
        let from = CLLocation(
            latitude: searchOrigin.latitude,
            longitude: searchOrigin.longitude
        )
        let to = CLLocation(latitude: court.latitude, longitude: court.longitude)
        return Distance.text(from.distance(from: to))
    }

    // MARK: - Derivation

    private func rebuildGameCounts(queued: [Game], published: [Game]) {
        gamesByCourtID = Self.gamesByCourt(queued: queued, published: published)
        rebuild()
    }

    /// Buckets today's games by court. "Today" is the calendar day at `now`,
    /// the same convention `Game.scheduledText` uses for its own "Today" —
    /// not a rolling 24 hours, so the heat map resets at midnight rather than
    /// drifting.
    ///
    /// Deliberately **not** filtered by `Game.isVisible(at:)` or by status: a
    /// full run or one that tipped off two hours ago still happened at that
    /// court today, and the heat map is answering "how busy was/is this court
    /// today", not "what can I still join". `GameService`'s own query cutoff
    /// (`Game.visibilityCutoff`) already drops anything more than three hours
    /// past its start, so nothing from yesterday leaks in regardless.
    ///
    /// The **Now** segment asks the other question and filters this result on
    /// `isVisible(at:)` separately — see `rankActive`. Two questions, two
    /// predicates, one join.
    ///
    /// `nonisolated static` and pure — `queued`/`published` passed in rather
    /// than read off `self` — so `FindAMatchViewModelTests` can pin the
    /// dedup-by-id and day-boundary rules without constructing a `GameService`
    /// or touching Firebase, the same shape `Game.status(playerCount:maxPlayers:)`
    /// and `Game.validate` already use for their own pure rules.
    nonisolated static func gamesByCourt(
        queued: [Game],
        published: [Game],
        now: Date = Date()
    ) -> [String: [Game]] {
        var seen = Set<String>()
        var byCourt: [String: [Game]] = [:]

        for game in queued + published {
            guard seen.insert(game.id).inserted else { continue }
            guard Calendar.current.isDate(game.scheduledTime, inSameDayAs: now) else { continue }
            byCourt[game.courtId, default: []].append(game)
        }

        // Sorted on `id` after `scheduledTime`: two runs at the same minute
        // would otherwise land in whatever order the dictionary happened to
        // iterate, and a row that reshuffles between identical rebuilds reads
        // as broken.
        return byCourt.mapValues { games in
            games.sorted {
                ($0.scheduledTime, $0.id) < ($1.scheduledTime, $1.id)
            }
        }
    }

    /// Today's game counts per court.
    ///
    /// Reimplemented on top of `gamesByCourt` rather than counting separately,
    /// so the tally and the list it summarises can never disagree.
    nonisolated static func gameCountsByCourt(
        queued: [Game],
        published: [Game],
        now: Date = Date()
    ) -> [String: Int] {
        gamesByCourt(queued: queued, published: published, now: now)
            .mapValues(\.count)
    }

    private func rebuild() {
        let filtered = courtService.courts.filter { court in
            let activity = CourtActivity(games: gamesByCourtID[court.id] ?? [])
            return activeFilters.allSatisfy { $0.matches(court, activity: activity) }
        }
        courts = filtered

        let ranked = Self.ranked(courts: filtered, from: searchOrigin)
        let byID = Dictionary(uniqueKeysWithValues: ranked.map { ($0.court.id, $0) })

        // Recency order, not distance order. Filters still apply, so a court
        // can drop out of it.
        recentCourts = recentCourtIds.compactMap { byID[$0]?.court }

        activeCourts = Self.rankActive(
            gamesByCourtID: gamesByCourtID,
            among: ranked
        )

        switch selectedTab {
        case .now:
            // The `.now` segment renders `activeCourts`; keeping this empty
            // stops a stale court list surviving underneath it.
            listedCourts = []

        case .nearby:
            let radiusMeters = Distance.meters(miles: radiusMiles)
            listedCourts = ranked.filter { $0.distanceMeters <= radiusMeters }

        case .saved:
            listedCourts = ranked.filter { favoriteCourtIds.contains($0.court.id) }
        }

        chooseInitialTabIfNeeded()
    }

    /// Courts with a run worth walking to right now, soonest first.
    ///
    /// **Filters on `Game.isVisible(at:)` rather than the calendar day the join
    /// buckets by.** The join is deliberately day-scoped because the *pins*
    /// want it — a run that finished still means the court was busy today. This
    /// segment asks the other question, and the day rule answers it wrongly at
    /// both ends: at 11pm it would list a 9am run that's long over, and at
    /// 12:05am it would list nothing despite a 12:30 tip-off.
    ///
    /// Sorted on three keys. `scheduledTime` is the one that matters;
    /// `distanceMeters` and then `displayName` break its ties, because
    /// `gamesByCourtID` is a dictionary with no stable iteration order and a
    /// list that reshuffles between identical rebuilds reads as broken.
    ///
    /// Pure and static, taking the already-ranked courts so it neither repeats
    /// the geo math nor needs an origin of its own.
    nonisolated static func rankActive(
        gamesByCourtID: [String: [Game]],
        among ranked: [NearbyCourt],
        now: Date = Date()
    ) -> [ActiveCourt] {
        ranked
            .compactMap { nearby -> ActiveCourt? in
                let live = (gamesByCourtID[nearby.court.id] ?? [])
                    .filter { $0.isVisible(at: now) }
                guard !live.isEmpty else { return nil }

                return ActiveCourt(
                    court: nearby.court,
                    distanceMeters: nearby.distanceMeters,
                    games: live
                )
            }
            .sorted { first, second in
                if first.leadGame.scheduledTime != second.leadGame.scheduledTime {
                    return first.leadGame.scheduledTime < second.leadGame.scheduledTime
                }
                if first.distanceMeters != second.distanceMeters {
                    return first.distanceMeters < second.distanceMeters
                }
                return first.court.displayName < second.court.displayName
            }
    }

    /// Opens on `.now` when there's something on, and `.nearby` when there
    /// isn't.
    ///
    /// Decided **once**, on the first snapshot that actually came from
    /// Firestore. Not on `onAppear`: `@Published` replays its current value to
    /// a new subscriber, so the first thing every consumer sees is an empty
    /// array whether or not anything has loaded — an appear-time check would
    /// resolve to `.nearby` every single launch, which is the exact failure
    /// this tab was rebuilt to end.
    ///
    /// Not reactive either. A segment that swaps under the user's thumb the
    /// moment someone books a run is worse than one that opened on the wrong
    /// tab.
    private func chooseInitialTabIfNeeded() {
        guard !hasChosenInitialTab, gameService.hasLoadedGames else { return }
        hasChosenInitialTab = true

        // Only overrides the default. If the user has already picked a segment
        // themselves, their choice stands.
        guard activeCourts.isEmpty, selectedTab == .now else { return }

        // A plain assignment, even though this runs *from* `rebuild()` and
        // `selectedTab`'s `didSet` calls `rebuild()` again. `hasChosenInitialTab`
        // is set above, so the nested call returns at the guard — the recursion
        // is one level deep and terminates. Going around the property to avoid
        // it would skip the `@Published` emission the sheet needs.
        selectedTab = .nearby
    }

    private static func ranked(
        courts: [Court],
        from origin: CLLocationCoordinate2D
    ) -> [NearbyCourt] {
        let from = CLLocation(latitude: origin.latitude, longitude: origin.longitude)

        return courts
            .map { court in
                let to = CLLocation(latitude: court.latitude, longitude: court.longitude)
                return NearbyCourt(court: court, distanceMeters: from.distance(from: to))
            }
            .sorted { $0.distanceMeters < $1.distanceMeters }
    }

    // MARK: - Presentation helpers

    /// Whether the segment currently on screen has nothing to show.
    ///
    /// `.now` reads a different array from the other two, so "is this list
    /// empty" is a question the view shouldn't have to ask two different ways.
    var isCurrentListEmpty: Bool {
        selectedTab == .now ? activeCourts.isEmpty : listedCourts.isEmpty
    }

    var listCountLabel: String {
        switch selectedTab {
        case .now:
            let runs = activeCourts.reduce(0) { $0 + $1.games.count }
            return runs == 1 ? "1 run on today" : "\(runs) runs on today"
        case .nearby:
            let count = listedCourts.count
            return count == 1 ? "1 court nearby" : "\(count) courts nearby"
        case .saved:
            let count = listedCourts.count
            return count == 1 ? "1 saved court" : "\(count) saved courts"
        }
    }

    /// A dataset failure outranks every per-segment message: with no courts
    /// loaded *every* segment is empty, and "No saved courts yet" would be a
    /// true sentence that sends the reader to fix the wrong thing.
    var emptyStateTitle: String {
        if datasetError != nil { return "Court data unavailable" }

        switch selectedTab {
        case .now:    return "Nothing on today"
        case .nearby: return "No courts within \(Int(radiusMiles)) miles"
        case .saved:  return "No saved courts yet"
        }
    }

    var emptyStateDetail: String? {
        if let datasetError {
            // Names the build rather than the network: the dataset ships in the
            // app bundle, so there is nothing for the reader to retry.
            return "\(datasetError) Reinstalling the app is the only fix."
        }

        switch selectedTab {
        case .now:
            // Deliberately not an apology. With no runs booked this is the
            // most common state the tab has, and the only lever the UI has on
            // that cold start is to make starting one the obvious next move.
            return activeFilters.isEmpty
                ? "Be the first — start a run at a court near you."
                : "Try removing a filter."
        case .nearby:
            // Names the radius actually in force rather than pointing at a
            // "Search here" button the map has never had. `radiusMiles` is
            // published for exactly this — see its note.
            return activeFilters.isEmpty
                ? "Nothing within \(UserProfile.radiusText(radiusMiles)). Widen your radius in your profile."
                : "Try removing a filter."
        case .saved:
            return "Tap the star on any court to save it here."
        }
    }

    // MARK: - Runs at a court

    /// Today's runs at `court` that are still worth showing, soonest first.
    ///
    /// Same `isVisible(at:)` cutoff the Now segment uses, for the same reason:
    /// a run that finished two hours ago belongs in the pin's colour, not in a
    /// card offering you a button to join it.
    func gamesToday(at court: Court, now: Date = Date()) -> [Game] {
        (gamesByCourtID[court.id] ?? []).filter { $0.isVisible(at: now) }
    }

    /// What the primary button on a run row does. Shares
    /// `LocalRunsViewModel`'s rule rather than restating it — the Runs tab and
    /// the map must never offer different buttons for the same run.
    func action(for game: Game) -> LocalRunsViewModel.Action {
        LocalRunsViewModel.action(for: game, currentUserId: gameService.currentUserId)
    }

    /// The run with a roster write in flight, if any. One at a time, matching
    /// `LocalRunsViewModel`: the button that started it shows a spinner and
    /// every other one is disabled, so a double tap can't queue two conflicting
    /// transactions.
    @Published private(set) var pendingGameId: String?

    func perform(_ action: LocalRunsViewModel.Action, on game: Game) async {
        guard pendingGameId == nil, action != .none else { return }

        pendingGameId = game.id
        defer { pendingGameId = nil }

        do {
            switch action {
            case .join, .joinWaitlist:
                try await gameService.joinGame(id: game.id)
            case .leave:
                try await gameService.leaveGame(id: game.id)
            case .cancel:
                try await gameService.cancelGame(id: game.id)
            case .none:
                break
            }
            // The listener re-emits the roster the server actually stored, so
            // there's nothing to apply optimistically here.
        } catch {
            // `GameService` already reported it.
        }
    }

    // MARK: - Search

    /// Whether the user has actually typed something worth searching for.
    var hasSearchQuery: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Header for the search pane: the result count, or "Recent" for the
    /// courts shown before anything is typed.
    var searchHeaderLabel: String {
        guard hasSearchQuery else { return "Recent" }
        let count = searchResults.count
        return count == 1 ? "1 court matches" : "\(count) courts match"
    }

    func clearSearch() {
        searchQuery = ""
    }

    private func rebuildSearchResults() {
        searchResults = CourtSearch.matches(courtService.courts, query: searchQuery)
    }

    /// The court the Now segment's empty-state button starts a run at: the
    /// nearest one that passes the active filters.
    ///
    /// `nil` only when the filters or the dataset have left nothing at all, in
    /// which case the button has nowhere to send the user and isn't shown.
    var nearestCourtForNewRun: Court? {
        listedCourts.first?.court ?? Self.ranked(
            courts: courts,
            from: searchOrigin
        ).first?.court
    }
}
