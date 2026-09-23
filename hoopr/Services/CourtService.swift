import Combine
import Foundation
import os

fileprivate let logger = Logger(subsystem: "com.hoopsrn", category: "CourtService")

/// Court geography ships with the app as a curated dataset rather than being
/// fetched at runtime: the map is populated instantly, works offline, and no
/// longer depends on a volunteer-run API that intermittently times out.
///
/// Live game state will layer on top of this, joined by court ID.
///
/// A load failure leaves `courts` empty **and publishes `loadError`**. Both
/// matter: without the error, a missing or undecodable `courts.json` renders
/// as a map with no pins and a list reading "no courts within 5 miles" — which
/// is indistinguishable from a genuinely empty result, and is how a broken
/// bundle would ship unnoticed. There is still no retry: the dataset is in the
/// app bundle, so a failure here is a build problem, not a transient one.
final class CourtService: ObservableObject {
    @Published private(set) var courts: [Court] = []

    /// `courts` grouped into the places players actually travel to.
    ///
    /// Derived once at load rather than on demand: it's read on every map rebuild
    /// and the dataset never changes after `init`. Published alongside `courts`
    /// rather than replacing it — plenty of callers still want a single surface
    /// (a run happens on one court, not across a park), so both are the truth at
    /// different grains.
    @Published private(set) var facilities: [Facility] = []

    /// `facilityId` for a given court ID, for joining anything keyed on a court
    /// back up to its facility — `Game.courtId` above all.
    private(set) var facilityIdsByCourtId: [String: String] = [:]

    /// `facilities` indexed by ID. Held rather than searched because the map's
    /// court card asks for a facility on every render, and a linear scan of 191
    /// facilities per frame is a scroll hitch waiting to happen.
    private(set) var facilitiesById: [String: Facility] = [:]

    /// Set when the bundled dataset couldn't be read. `nil` on success.
    @Published private(set) var loadError: String?

    init() {
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "courts", withExtension: "json") else {
            logger.error("courts.json missing from bundle")
            loadError = "Court data is missing from this build."
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let dataset = try JSONDecoder().decode(CourtDataset.self, from: data)
            courts = dataset.courts.sorted { $0.name < $1.name }
            facilities = Facility.group(courts)
            facilityIdsByCourtId = Dictionary(
                courts.map { ($0.id, $0.facilityId) },
                uniquingKeysWith: { first, _ in first }
            )
            facilitiesById = Dictionary(
                facilities.map { ($0.id, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            loadError = nil
            logger.debug(
                """
                Loaded \(self.courts.count) courts in \
                \(self.facilities.count) facilities (dataset v\(dataset.version))
                """
            )
        } catch {
            logger.error("Failed to decode courts.json: \(error.localizedDescription)")
            loadError = "Court data couldn't be read."
        }
    }
}
