import CoreLocation

/// Distance conversion and formatting, in one place.
///
/// The nearby-courts list and the local-runs list both measure from the same
/// origin and render the same "1.2 mi" string; without this they'd each carry
/// their own copy of the conversion factor and the format rule.
nonisolated enum Distance {
    static let metersPerMile: CLLocationDistance = 1_609.344

    static func miles(_ meters: CLLocationDistance) -> Double {
        meters / metersPerMile
    }

    static func meters(miles: Double) -> CLLocationDistance {
        miles * metersPerMile
    }

    /// Miles, US-style: one decimal under 10 mi, whole numbers above — a tenth
    /// of a mile stops being meaningful once you're driving there.
    static func text(_ meters: CLLocationDistance) -> String {
        let miles = Self.miles(meters)
        return miles < 10
            ? String(format: "%.1f mi", miles)
            : String(format: "%.0f mi", miles)
    }

    static func between(
        _ from: CLLocationCoordinate2D,
        _ to: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }
}
