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

    /// The place a player travels to, which is not always this court.
    ///
    /// OSM tags each playing surface as its own way, so one park arrives as
    /// several courts: Long Meadow Park is three records 17m apart. Left
    /// ungrouped that is three overlapping pins on the map and — far worse —
    /// three separate queues at one physical court, none able to see the others,
    /// because `Game.courtId` and `MatchTicket.courtIds` key on the court.
    ///
    /// **Every court has one, and a court on its own is a facility of one.**
    /// There is no optionality to forget: `gamesByFacility` can key on this for
    /// every court without a special case.
    ///
    /// Derived, and deliberately carrying no durability obligation — nothing in
    /// Firestore references it. Games keep storing `courtId`; the facility is
    /// purely how the client *groups* them at read time. That's what separates
    /// it from `id`, which `tools/courts_common.py` keeps stable across rebuilds
    /// precisely because stored documents point at it. A facility ID can be
    /// re-minted whenever the grouping improves.
    let facilityId: String

    /// OSM provenance, kept so a future extract can match existing records
    /// instead of minting duplicate courts.
    let osmType: String?
    let osmId: Int64?

    /// `facilityId` defaults to `id` — a court with no grouping stated is its own
    /// facility. Written out rather than synthesized so that default exists:
    /// Swift's memberwise init can't carry one, and without it every call site
    /// that builds a `Court` would have to name a facility it doesn't care about.
    init(
        id: String,
        name: String,
        latitude: Double,
        longitude: Double,
        address: String,
        city: String,
        hoops: Int? = nil,
        surface: String? = nil,
        isLit: Bool? = nil,
        isCovered: Bool? = nil,
        access: Access,
        facilityId: String? = nil,
        osmType: String? = nil,
        osmId: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.address = address
        self.city = city
        self.hoops = hoops
        self.surface = surface
        self.isLit = isLit
        self.isCovered = isCovered
        self.access = access
        self.facilityId = facilityId ?? id
        self.osmType = osmType
        self.osmId = osmId
    }

    /// Decodes a dataset that predates `facilityId` by treating each court as its
    /// own facility.
    ///
    /// The bundled file is v2 and always carries the field, so this path is for a
    /// **hosted** dataset — the case `CourtDataset.version` exists for. Making it
    /// a decode *failure* instead would take the whole dataset down over a field
    /// whose absence has an obvious correct reading, and a failure here is
    /// indistinguishable to the user from having no courts at all.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        address = try container.decode(String.self, forKey: .address)
        city = try container.decode(String.self, forKey: .city)
        hoops = try container.decodeIfPresent(Int.self, forKey: .hoops)
        surface = try container.decodeIfPresent(String.self, forKey: .surface)
        isLit = try container.decodeIfPresent(Bool.self, forKey: .isLit)
        isCovered = try container.decodeIfPresent(Bool.self, forKey: .isCovered)
        access = try container.decode(Access.self, forKey: .access)
        facilityId = try container.decodeIfPresent(String.self, forKey: .facilityId) ?? id
        osmType = try container.decodeIfPresent(String.self, forKey: .osmType)
        osmId = try container.decodeIfPresent(Int64.self, forKey: .osmId)
    }

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
