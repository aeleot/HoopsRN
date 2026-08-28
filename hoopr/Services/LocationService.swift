import Combine
import Foundation
import CoreLocation

final class LocationService: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// The device's most recent accepted fix, or `nil` until one lands.
    ///
    /// Published separately from `homeLocation` so a view model can react to a
    /// fix *arriving* — moving the map to it once — rather than only reading
    /// wherever the anchor happens to point.
    @Published private(set) var coordinate: CLLocationCoordinate2D?

    private let manager = CLLocationManager()

    /// Downtown Durham, NC — the fallback centre used whenever we have no fix.
    static let defaultLocation = CLLocationCoordinate2D(latitude: 35.9940, longitude: -78.8986)

    /// How far the device has to move before a new fix replaces the anchor.
    ///
    /// Distances in this app are rendered to a tenth of a mile (~160m), so
    /// re-sorting every list for a 20m drift would churn the UI to say the same
    /// thing. The first fix is always adopted regardless — see `adopt(_:)`.
    nonisolated static let significantMove: CLLocationDistance = 100

    /// Where the app measures "near you" from.
    ///
    /// Every distance in the app reads this: the map's initial region, the
    /// nearby-courts list, the recenter target, Home's hot list, and the Local
    /// Runs radius filter. Keeping it as one anchor is what stops two screens
    /// disagreeing about how far away the same court is.
    ///
    /// Backed by mutable state rather than a constant now that it follows the
    /// device. That state is main-actor isolated along with the rest of this
    /// module (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), so the compiler —
    /// not a convention — is what guarantees the write in `adopt(_:)` can't
    /// race a read on another thread.
    static var homeLocation: CLLocationCoordinate2D { lastKnownLocation }

    private(set) static var lastKnownLocation = defaultLocation

    override init() {
        super.init()
        manager.delegate = self
        // Hundred-metre accuracy, not best. This feeds distances rendered in
        // tenths of a mile and a map that opens at a ~5mi span; GPS-grade
        // precision would cost battery to produce digits nothing displays.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 200
        authorizationStatus = manager.authorizationStatus
    }

    func requestLocationPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdatingLocation() {
        manager.startUpdatingLocation()
    }

    /// Whether `new` is far enough from `old` to be worth adopting.
    ///
    /// Pure and static so the threshold is testable without standing up a
    /// `CLLocationManager` or faking a delegate callback — the same shape
    /// `Game.status(playerCount:maxPlayers:)` uses for its own rule.
    nonisolated static func shouldAdopt(
        _ new: CLLocationCoordinate2D,
        over old: CLLocationCoordinate2D
    ) -> Bool {
        Distance.between(old, new) >= significantMove
    }

    /// Takes a fix if it's the first one or the device has actually moved.
    private func adopt(_ fix: CLLocationCoordinate2D) {
        if let coordinate, !Self.shouldAdopt(fix, over: coordinate) { return }

        coordinate = fix
        Self.lastKnownLocation = fix
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.startUpdatingLocation()
            default:
                break
            }
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let fix = locations.last else { return }
        // Decomposed into two `Double`s rather than hopping the coordinate
        // itself, so nothing here depends on a CoreLocation struct's
        // `Sendable` conformance.
        let latitude = fix.coordinate.latitude
        let longitude = fix.coordinate.longitude

        Task { @MainActor in
            self.adopt(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Fail silently — every distance falls back to `defaultLocation`, so
        // the map and both lists stay functional without a fix.
    }
}
