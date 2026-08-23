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
            loadError = nil
            logger.debug("Loaded \(self.courts.count) courts (dataset v\(dataset.version))")
        } catch {
            logger.error("Failed to decode courts.json: \(error.localizedDescription)")
            loadError = "Court data couldn't be read."
        }
    }
}
