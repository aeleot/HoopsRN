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

    /// Courts within `nearbyRadiusMiles` of the user, nearest first.
    @Published private(set) var nearbyCourts: [NearbyCourt] = []

    /// How far out the nearby list reaches. Tune here — nothing else hardcodes it.
    static let nearbyRadiusMiles: Double = 5
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

    init(courtService: CourtService, locationService: LocationService) {
        self.courtService = courtService
        self.locationService = locationService

        courtService.$courts
            .receive(on: DispatchQueue.main)
            .assign(to: \.courts, on: self)
            .store(in: &cancellables)

        // Distances are measured from the hardcoded home location, not the
        // device's. Swap `homeLocation` for the profile's saved location and
        // this pipeline starts tracking it without further changes.
        courtService.$courts
            .map { Self.nearby(courts: $0, to: Self.homeLocation) }
            .receive(on: DispatchQueue.main)
            .assign(to: \.nearbyCourts, on: self)
            .store(in: &cancellables)
    }

    private static func nearby(
        courts: [Court],
        to origin: CLLocationCoordinate2D
    ) -> [NearbyCourt] {
        let from = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let radiusMeters = nearbyRadiusMiles * metersPerMile

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
