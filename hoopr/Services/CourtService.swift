	import Combine
import Foundation
import os

fileprivate let logger = Logger(subsystem: "com.hoopr", category: "CourtService")

/// Court geography ships with the app as a curated dataset rather than being
/// fetched at runtime: the map is populated instantly, works offline, and no
/// longer depends on a volunteer-run API that intermittently times out.
///
/// Live game state will layer on top of this, joined by court ID.
final class CourtService: ObservableObject {
    @Published private(set) var courts: [Court] = []
    @Published private(set) var loadError: String?

    private(set) var version = 0
    private(set) var attribution = ""

    init() {
        load()
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "courts", withExtension: "json") else {
            logger.error("courts.json missing from bundle")
            loadError = "Court data unavailable"
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let dataset = try JSONDecoder().decode(CourtDataset.self, from: data)
            courts = dataset.courts.sorted { $0.name < $1.name }
            version = dataset.version
            attribution = dataset.attribution
            logger.debug("Loaded \(self.courts.count) courts (dataset v\(dataset.version))")
        } catch {
            logger.error("Failed to decode courts.json: \(error.localizedDescription)")
            loadError = "Court data unavailable"
        }
    }
}
