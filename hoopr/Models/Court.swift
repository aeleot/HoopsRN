import Foundation
import CoreLocation

struct Court: Identifiable, Sendable, Codable, Hashable {
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
}

/// Versioned envelope around the bundled dataset. The version lets a future
/// CDN-hosted copy be compared against the bundled one without parsing courts.
struct CourtDataset: Sendable, Codable {
    let version: Int
    let generated: String
    let attribution: String
    let cities: [String]
    let courts: [Court]
}
