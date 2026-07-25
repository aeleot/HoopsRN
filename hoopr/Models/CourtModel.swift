import Foundation
import CoreLocation

struct Court: Identifiable, Sendable, Codable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let address: String
    let occupancyCount: Int?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
