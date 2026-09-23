import CoreLocation
import Foundation

/// One place a player travels to, and the surfaces they'll find when they get
/// there.
///
/// `Court` is a playing surface; this is the destination. The distinction only
/// exists because OSM tags each surface as its own way, so one park arrives in
/// the dataset as several courts — Long Meadow Park as three records 17m apart.
///
/// Two things went wrong without this type. On the map, three pins drew on top of
/// each other. In the queue, three *separate queues* existed at one physical
/// court, none able to see the others, because everything that asks "who's
/// playing here" keys on `Game.courtId`. A player standing on the court could be
/// two metres from someone queued for the same run and invisible to them.
///
/// Built by `CourtService` from the dataset's `facilityId`, never constructed by
/// hand outside tests.
nonisolated struct Facility: Identifiable, Equatable, Sendable {
    /// The dataset's `facilityId`, shared by every court in `courts`.
    let id: String

    /// The surfaces here, in dataset order. **Never empty** — a facility exists
    /// because a court referenced it, which is what lets `primary` be
    /// non-optional.
    let courts: [Court]

    /// The court that speaks for the facility: the one whose name a player would
    /// recognise.
    ///
    /// Picked as the shortest display name, then alphabetically, which lands on
    /// the un-numbered name when the group is "Walltown Park #1 / #2" and is
    /// stable when it isn't. Sorting rather than taking `courts.first` matters
    /// because dataset order is name order, so `first` would reliably pick "#1"
    /// — a name that tells the reader there's a "#2" they can't see.
    var primary: Court {
        courts.min {
            ($0.displayName.count, $0.displayName) < ($1.displayName.count, $1.displayName)
        } ?? courts[0]
    }

    /// What to draw on a pin or a row. Strips the surface number that only
    /// existed because OSM split the court.
    var displayName: String {
        primary.displayName
            .replacingOccurrences(of: #"\s*#\d+$"#, with: "", options: .regularExpression)
    }

    var surfaceCount: Int { courts.count }

    /// "3 courts", or `nil` for a facility with a single surface — where the
    /// count is noise, because one court is what a reader already assumes.
    var surfaceCountText: String? {
        surfaceCount > 1 ? "\(surfaceCount) courts" : nil
    }

    /// The centre of the facility, for the one pin that replaces several.
    ///
    /// Mean of the surfaces rather than `primary.coordinate`: with three courts
    /// in a row, the primary is an end one, and a pin on the end reads as
    /// pointing at that surface rather than at the park.
    var coordinate: CLLocationCoordinate2D {
        let count = Double(courts.count)
        return CLLocationCoordinate2D(
            latitude: courts.reduce(0) { $0 + $1.latitude } / count,
            longitude: courts.reduce(0) { $0 + $1.longitude } / count
        )
    }

    /// Every court ID here, for joining against anything keyed on `courtId`.
    var courtIds: [String] { courts.map(\.id) }

    /// The city the facility is in.
    ///
    /// Takes the primary's, and where surfaces disagree that is the *only*
    /// defensible pick rather than a majority vote — the dataset assigns city by
    /// nearest centroid, so a facility straddling the line has genuinely
    /// conflicting records. Davis Drive Elementary School ships as one court in
    /// Cary and one in Morrisville. Grouping them at least makes the app show
    /// one answer instead of two.
    var city: String { primary.city }

    /// Groups courts into facilities, preserving the input's ordering.
    ///
    /// Order is load-bearing: `CourtService` sorts courts by name, and a map or
    /// list built from an unordered dictionary would reshuffle between rebuilds.
    static func group(_ courts: [Court]) -> [Facility] {
        var order: [String] = []
        var byId: [String: [Court]] = [:]
        for court in courts {
            if byId[court.facilityId] == nil { order.append(court.facilityId) }
            byId[court.facilityId, default: []].append(court)
        }
        return order.map { Facility(id: $0, courts: byId[$0] ?? []) }
    }
}
