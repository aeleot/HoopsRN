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

    /// Miles, US-style: one decimal under 10 mi, whole numbers above.
    var distanceText: String {
        let miles = distanceMeters / FindAMatchViewModel.metersPerMile
        return miles < 10
            ? String(format: "%.1f mi", miles)
            : String(format: "%.0f mi", miles)
    }
}

final class FindAMatchViewModel: ObservableObject {
    @Published private(set) var courts: [Court] = []

    /// Courts within `radiusMiles` of the user, nearest first.
    @Published private(set) var nearbyCourts: [NearbyCourt] = []

    /// The radius the list was actually built with — the profile's preference,
    /// or the default while signed out or before the first snapshot lands.
    /// Published so the empty state can name the real number rather than
    /// restating a constant that may not be the one in force.
    @Published private(set) var radiusMiles: Double = UserProfile.defaultPreferredRadius

    static let metersPerMile: Double = 1609.344

    /// The user's default location, hardcoded to Durham, NC until the profile
    /// owns it. Anchors the initial region, every list distance, and the
    /// recenter button, so all three agree.
    static var homeLocation: CLLocationCoordinate2D { LocationService.defaultLocation }

    let initialRegion = MKCoordinateRegion(
        center: FindAMatchViewModel.homeLocation,
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )

    private let courtService: CourtService
    private let locationService: LocationService
    private var cancellables = Set<AnyCancellable>()

    init(
        courtService: CourtService,
        locationService: LocationService,
        userProfileService: UserProfileService
    ) {
        self.courtService = courtService
        self.locationService = locationService

        courtService.$courts
            .receive(on: DispatchQueue.main)
            .assign(to: \.courts, on: self)
            .store(in: &cancellables)

        // The list depends on two independent inputs — the dataset and the
        // saved radius — so it rebuilds when either moves. Editing the radius
        // in the profile reflows this list without a reload.
        //
        // Distances are still measured from the hardcoded home location; swap
        // `homeLocation` for a profile-owned one and this pipeline follows.
        let radius = userProfileService.$currentProfile
            .map { $0?.effectivePreferredRadius ?? UserProfile.defaultPreferredRadius }
            .removeDuplicates()

        radius
            .receive(on: DispatchQueue.main)
            .assign(to: \.radiusMiles, on: self)
            .store(in: &cancellables)

        courtService.$courts
            .combineLatest(radius)
            .map { courts, radiusMiles in
                Self.nearby(courts: courts, to: Self.homeLocation, radiusMiles: radiusMiles)
            }
            .receive(on: DispatchQueue.main)
            .assign(to: \.nearbyCourts, on: self)
            .store(in: &cancellables)
    }

    private static func nearby(
        courts: [Court],
        to origin: CLLocationCoordinate2D,
        radiusMiles: Double
    ) -> [NearbyCourt] {
        let from = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let radiusMeters = radiusMiles * metersPerMile

        return courts
            .map { court in
                let to = CLLocation(latitude: court.latitude, longitude: court.longitude)
                return NearbyCourt(court: court, distanceMeters: from.distance(from: to))
            }
            .filter { $0.distanceMeters <= radiusMeters }
            .sorted { $0.distanceMeters < $1.distanceMeters }
    }

    /// The recenter button always returns to the user's default location. We
    /// still ask for permission on the first tap so MapKit can draw the blue
    /// user dot, but no longer make the user answer before the map moves.
    func recenterTarget() -> CLLocationCoordinate2D {
        if locationService.authorizationStatus == .notDetermined {
            locationService.requestLocationPermission()
        }
        return Self.homeLocation
    }

    func select(_ court: Court) {
        // Court detail and game creation will hang off this.
    }
}
