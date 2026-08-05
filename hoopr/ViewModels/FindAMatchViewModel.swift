import Combine
import CoreLocation
import Foundation
import MapKit

final class FindAMatchViewModel: ObservableObject {
    @Published private(set) var courts: [Court] = []

    let initialRegion = MKCoordinateRegion(
        center: LocationService.defaultLocation,
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
    }

    /// Where the map should recenter, or `nil` when we've instead had to ask for
    /// permission and should wait for the user to answer.
    func recenterTarget() -> CLLocationCoordinate2D? {
        if locationService.authorizationStatus == .notDetermined {
            locationService.requestLocationPermission()
            return nil
        }
        return locationService.userLocation ?? LocationService.defaultLocation
    }

    func select(_ court: Court) {
        // Court detail and game creation will hang off this.
    }
}
