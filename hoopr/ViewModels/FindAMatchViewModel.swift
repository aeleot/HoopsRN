import Combine
import CoreLocation
import Foundation
import MapKit

/// A court paired with its distance from the user, computed once when the list
/// is built so the view never does geo math while scrolling.
struct NearbyCourt: Identifiable, Equatable {
    let court: Court
    let distanceMeters: CLLocationDistance

    var id: String { court.id }

    var distanceText: String { Distance.text(distanceMeters) }
}

final class FindAMatchViewModel: ObservableObject {
    /// Which list the sheet is showing. Nearby is geographic; the other two are
    /// membership lists that ignore the search radius entirely.
    enum ListTab: String, CaseIterable, Identifiable {
        case nearby
        case favorites
        case recent

        var id: String { rawValue }

        var title: String {
            switch self {
            case .nearby:    "NEARBY"
            case .favorites: "FAVORITES"
            case .recent:    "RECENT"
            }
        }
    }

    // MARK: - Published state

    /// Courts drawn on the map — every court that passes the active filters,
    /// regardless of distance.
    @Published private(set) var courts: [Court] = []

    /// The rows currently in the sheet, already filtered and ordered for
    /// `selectedTab`.
    @Published private(set) var listedCourts: [NearbyCourt] = []

    @Published var selectedTab: ListTab = .nearby {
        didSet { rebuild() }
    }

    @Published private(set) var activeFilters: Set<CourtFilter> = []

    @Published private(set) var favoriteCourtIds: Set<String> = []

    /// The radius the nearby list was actually built with — the profile's
    /// preference, or the default while signed out or before the first
    /// snapshot lands. Published so the empty state can name the real number
    /// rather than restating a constant that may not be the one in force.
    @Published private(set) var radiusMiles: Double = UserProfile.defaultPreferredRadius

    // MARK: - Tuning

    /// The user's default location, hardcoded to Durham, NC until the profile
    /// owns it. Anchors the initial region and the recenter button.
    static var homeLocation: CLLocationCoordinate2D { LocationService.homeLocation }

    let initialRegion = MKCoordinateRegion(
        center: FindAMatchViewModel.homeLocation,
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    // MARK: - Dependencies

    private let courtService: CourtService
    private let locationService: LocationService
    private let userProfileService: UserProfileService
    private let recentCourtsStore: RecentCourtsStore
    private var cancellables = Set<AnyCancellable>()

    /// Where distances are measured from. Fixed for the life of the view
    /// model: panning the map changes what you're looking at, not where you
    /// are. It reads `homeLocation` like every other distance in the app, so
    /// pointing that at the device moves this with it.
    private let searchOrigin: CLLocationCoordinate2D
    private var recentCourtIds: [String] = []

    init(
        courtService: CourtService,
        locationService: LocationService,
        userProfileService: UserProfileService,
        recentCourtsStore: RecentCourtsStore
    ) {
        self.courtService = courtService
        self.locationService = locationService
        self.userProfileService = userProfileService
        self.recentCourtsStore = recentCourtsStore
        self.searchOrigin = Self.homeLocation

        courtService.$courts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuild() }
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

    /// The recenter button always returns to the user's default location. We
    /// still ask for permission on the first tap so MapKit can draw the blue
    /// user dot, but no longer make the user answer before the map moves.
    func recenterTarget() -> CLLocationCoordinate2D {
        if locationService.authorizationStatus == .notDetermined {
            locationService.requestLocationPermission()
        }
        return Self.homeLocation
    }

    // MARK: - Derivation

    private func rebuild() {
        let filtered = courtService.courts.filter { court in
            activeFilters.allSatisfy { $0.matches(court) }
        }
        courts = filtered

        let ranked = Self.ranked(courts: filtered, from: searchOrigin)

        switch selectedTab {
        case .nearby:
            let radiusMeters = Distance.meters(miles: radiusMiles)
            listedCourts = ranked.filter { $0.distanceMeters <= radiusMeters }

        case .favorites:
            listedCourts = ranked.filter { favoriteCourtIds.contains($0.court.id) }

        case .recent:
            // Recency order, not distance order — that's the whole point of
            // the tab. Filters still apply, so a court can drop out.
            let byID = Dictionary(uniqueKeysWithValues: ranked.map { ($0.court.id, $0) })
            listedCourts = recentCourtIds.compactMap { byID[$0] }
        }
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

    var listCountLabel: String {
        let count = listedCourts.count
        switch selectedTab {
        case .nearby:
            return count == 1 ? "1 court nearby" : "\(count) courts nearby"
        case .favorites:
            return count == 1 ? "1 favorite" : "\(count) favorites"
        case .recent:
            return count == 1 ? "1 recent court" : "\(count) recent courts"
        }
    }

    var emptyStateTitle: String {
        switch selectedTab {
        case .nearby:    "No courts within \(Int(radiusMiles)) miles"
        case .favorites: "No favorites yet"
        case .recent:    "No recent courts"
        }
    }

    var emptyStateDetail: String? {
        switch selectedTab {
        case .nearby:
            return activeFilters.isEmpty
                ? "Pan the map and tap Search here."
                : "Try removing a filter."
        case .favorites:
            return "Tap the star on any court to save it here."
        case .recent:
            return "Courts you open will show up here."
        }
    }
}
