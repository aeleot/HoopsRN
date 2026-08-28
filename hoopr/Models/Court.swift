import Foundation
import CoreLocation

nonisolated struct Court: Identifiable, Sendable, Codable, Hashable {
    /// How reachable a court actually is. OSM rarely tags apartment and hotel
    /// courts as private, so this is derived when the dataset is built.
    enum Access: String, Sendable, Codable {
        case `public`
        case school
        case restricted
    }

    /// Stable UUID minted when the dataset is built — deliberately not derived
    /// from coordinates, so correcting a court's position never orphans the
    /// games, ratings, or check-ins that reference it.
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let address: String
    let city: String
    let hoops: Int?
    let surface: String?
    let isLit: Bool?
    let isCovered: Bool?
    let access: Access

    /// OSM provenance, kept so a future extract can match existing records
    /// instead of minting duplicate courts.
    let osmType: String?
    let osmId: Int64?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// `name` with the dataset's boilerplate removed.
    ///
    /// Every court in the OSM extract is named `<Place> Basketball Court`, so
    /// the words carry no information in an app where *everything* is a
    /// basketball court — they just push real names onto a second and third
    /// line. "Long Meadow Park Basketball Court #2" reads as "Long Meadow Park
    /// #2". Falls back to the stored name when stripping would leave nothing,
    /// which is the case for a court named only after its type.
    var displayName: String {
        let stripped = name
            .replacingOccurrences(
                of: "basketball court",
                with: " ",
                options: [.caseInsensitive]
            )
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")

        return stripped.isEmpty ? name : stripped
    }
}

/// Versioned envelope around the bundled dataset. The version lets a future
/// CDN-hosted copy be compared against the bundled one without parsing courts.
nonisolated struct CourtDataset: Sendable, Codable {
    let version: Int
    let generated: String
    let attribution: String
    let cities: [String]
    let courts: [Court]
}
