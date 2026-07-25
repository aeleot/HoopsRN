import Combine
import Foundation
import MapKit
import os

fileprivate let logger = Logger(subsystem: "com.hoopr", category: "CourtSearch")

class CourtSearchService: ObservableObject {
    @Published var courts: [Court] = []
    @Published var isSearching = false
    @Published var lastError: String?

    private var prefetchTask: Task<Void, Never>?
    private var loadedBox: BoundingBox? // Tracks the geographic region already loaded in memory
    private let cache = CourtCache()

    init() {
        // On startup, immediately load the most recent cached courts so markers appear without delay.
        // This avoids a blank map on app launch and prevents redundant API calls on subsequent opens.
        if let cached = cache.loadMostRecent() {
            logger.debug("Startup: loaded \(cached.courts.count) courts from cache")
            self.courts = cached.courts.sorted { $0.name < $1.name }
            self.loadedBox = cached.box
            writeDebugCourtsFile(self.courts)
        }
    }

    // Multiple Overpass API mirrors — try each in order if one rate-limits.
    private let overpassEndpoints: [URL] = [
        URL(string: "https://overpass-api.de/api/interpreter")!,
        URL(string: "https://overpass.kumi.systems/api/interpreter")!,
        URL(string: "https://overpass.private.coffee/api/interpreter")!,
    ]

    // Prefetch this many miles around the visible region.
    private static let prefetchRadiusMiles: Double = 15.0
    private static let milesPerLatDegree: Double = 69.0

    // Grid dimension for parallel fetching. 2x2 = 4 parallel requests.
    private static let gridSize = 2

    /// Ensures courts are loaded for the given visible region.
    /// Checks in-memory → disk cache → network in that order.
    func ensureCoverage(for visibleRegion: MKCoordinateRegion) {
        // 1. In-memory hit
        if let box = loadedBox, box.contains(visibleRegion) {
            print("[Hoopr] ✓ Cache HIT: Region covered by in-memory box")
            logger.debug("Region covered by in-memory box")
            return
        }

        print("[Hoopr] Checking disk cache for region...")
        // 2. Disk cache hit — load instantly, then refresh in background
        if let cached = cache.find(covering: visibleRegion) {
            print("[Hoopr] ✓ Cache HIT: Loaded \(cached.courts.count) courts from disk")
            logger.debug("Region covered by disk cache (\(cached.courts.count) courts)")
            self.loadedBox = cached.box
            self.courts = cached.courts.sorted { $0.name < $1.name }
            // Optionally refresh in background if cache is stale (>7 days)
            let age = Date().timeIntervalSince(cached.timestamp)
            let ageInDays = age / (24 * 60 * 60)
            print("[Hoopr] Cache age: \(String(format: "%.1f", ageInDays)) days")
            if age > 7 * 24 * 60 * 60 {
                print("[Hoopr] Cache is stale (>7 days), refreshing in background...")
                logger.debug("Cache is stale, refreshing in background")
                prefetch(centeredAt: visibleRegion.center, showSpinner: false)
            }
            return
        }

        // 3. Network fetch
        print("[Hoopr] ✗ Cache MISS: No coverage found, fetching from network...")
        logger.debug("No coverage found, fetching from network")
        prefetch(centeredAt: visibleRegion.center, showSpinner: true)
    }

    private func prefetch(centeredAt center: CLLocationCoordinate2D, showSpinner: Bool) {
        // Cancel any in-flight fetch so rapid map pans don't pile up requests.
        prefetchTask?.cancel()

        let latDelta = Self.prefetchRadiusMiles / Self.milesPerLatDegree
        // Longitude degrees vary by latitude (cosine effect). At the equator, 1° lon ≈ 69 miles.
        // At higher latitudes, 1° lon becomes shorter. This scales the fetch box to maintain ~15 miles width.
        let cosLat = cos(center.latitude * .pi / 180)
        let lonDelta = Self.prefetchRadiusMiles / (Self.milesPerLatDegree * max(cosLat, 0.01))

        let bbox = BoundingBox(
            south: center.latitude - latDelta,
            north: center.latitude + latDelta,
            west: center.longitude - lonDelta,
            east: center.longitude + lonDelta
        )

        print("[Hoopr] Network request started: Prefetching ~15-mile radius around (\(center.latitude), \(center.longitude))")
        logger.debug("Prefetching ~15-mile radius around \(center.latitude), \(center.longitude)")

        prefetchTask = Task {
            if showSpinner {
                await MainActor.run {
                    isSearching = true
                    lastError = nil
                }
            }

            let fetched = await fetchCourtsInParallel(bbox: bbox)
            print("[Hoopr] Network request completed: Fetched \(fetched.count) courts")
            logger.debug("Fetched \(fetched.count) courts")

            if Task.isCancelled { return }

            let sorted = fetched.sorted { $0.name < $1.name }

            // Save to disk cache (only if we got real data, not just fallback bundle)
            if !sorted.isEmpty {
                print("[Hoopr] Saving \(sorted.count) courts to disk cache...")
                cache.save(box: bbox, courts: sorted)
            }

            await MainActor.run {
                self.loadedBox = bbox
                self.courts = sorted
                self.isSearching = false
                if sorted.isEmpty {
                    self.lastError = "No courts found in this area"
                    print("[Hoopr] ✗ No courts found in this area")
                } else {
                    print("[Hoopr] ✓ Displaying \(sorted.count) courts on map")
                    self.writeDebugCourtsFile(sorted)
                }
            }
        }
    }

    /// Splits the bounding box into a grid and fetches each cell in parallel.
    /// Partial failures return what we got — better to show most courts than none.
    private func fetchCourtsInParallel(bbox: BoundingBox) async -> [Court] {
        let subBoxes = bbox.subdivide(gridSize: Self.gridSize)
        logger.debug("Subdividing into \(subBoxes.count) cells")

        let allResults: [[Court]] = await withTaskGroup(of: [Court].self) { group in
            for (index, subBox) in subBoxes.enumerated() {
                group.addTask { [weak self] in
                    guard let self else { return [] }
                    do {
                        let courts = try await self.fetchCourts(bbox: subBox)
                        logger.debug("Cell \(index): fetched \(courts.count) courts")
                        return courts
                    } catch {
                        logger.warning("Cell \(index) failed: \(error.localizedDescription)")
                        return []
                    }
                }
            }

            var results: [[Court]] = []
            for await courts in group {
                results.append(courts)
            }
            return results
        }

        // Merge and dedupe by rounded coordinate (court.id is "%.5f,%.5f" of lat,lon).
        // This handles duplicate courts returned by different grid cells or API mirrors.
        var seen = Set<String>()
        var merged: [Court] = []
        for batch in allResults {
            for court in batch where seen.insert(court.id).inserted {
                merged.append(court)
            }
        }
        logger.debug("Merged to \(merged.count) unique courts")

        // If all API calls failed, use bundled fallback data as a graceful degradation.
        // Ensures app remains functional even when Overpass API is rate-limited or down.
        if merged.isEmpty {
            logger.debug("API failed, loading bundled fallback data")
            let fallback = loadBundledCourts()
            return fallback.filter { court in
                bbox.south <= court.latitude && court.latitude <= bbox.north &&
                bbox.west <= court.longitude && court.longitude <= bbox.east
            }
        }

        return merged
    }

    // MARK: - Debug Helper

    /// Writes the current courts array to a JSON file in Documents for inspection.
    /// This is a temporary development aid to visualize cached/fetched court data.
    /// File location: ~/Documents/courts_debug.json (accessible via Xcode Device Organizer).
    /// Called on startup (from cached data) and after API fetches (fresh data).
    private func writeDebugCourtsFile(_ courts: [Court]) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let debugFileURL = docs.appendingPathComponent("courts_debug.json")

        do {
            let data = try JSONEncoder().encode(courts)
            try data.write(to: debugFileURL, options: .atomic)
            logger.debug("Wrote \(courts.count) courts to debug file: \(debugFileURL.path)")
        } catch {
            logger.error("Failed to write debug courts file: \(error.localizedDescription)")
        }
    }

    private func loadBundledCourts() -> [Court] {
        guard let url = Bundle.main.url(forResource: "courts", withExtension: "json") else {
            logger.error("Failed to locate bundled courts.json")
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([FallbackCourt].self, from: data)
            logger.debug("Loaded \(decoded.count) bundled courts")
            return decoded.map { Court(
                id: $0.id,
                name: $0.name,
                latitude: $0.latitude,
                longitude: $0.longitude,
                address: $0.address,
                occupancyCount: nil
            ) }
        } catch {
            logger.error("Failed to decode bundled courts: \(error.localizedDescription)")
            return []
        }
    }

    private func fetchCourts(bbox: BoundingBox) async throws -> [Court] {
        let bboxString = "\(bbox.south),\(bbox.west),\(bbox.north),\(bbox.east)"
        let query = """
        [out:json][timeout:15];
        (
          node["sport"="basketball"](\(bboxString));
          way["sport"="basketball"](\(bboxString));
        );
        out center tags;
        """

        var lastError: Error?
        var data: Data?

        for (index, endpoint) in overpassEndpoints.enumerated() {
            if Task.isCancelled { throw CancellationError() }

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("Hoopr iOS App", forHTTPHeaderField: "User-Agent")
            request.httpBody = "data=\(query)".data(using: .utf8)
            request.timeoutInterval = 15

            do {
                let (fetchedData, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   (200...299).contains(httpResponse.statusCode) {
                    logger.debug("Endpoint \(index) succeeded: \(fetchedData.count) bytes")
                    data = fetchedData
                    break
                }
                lastError = URLError(.badServerResponse)
                logger.warning("Endpoint \(index) returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            } catch {
                lastError = error
                logger.warning("Endpoint \(index) failed: \(error.localizedDescription)")
                continue
            }
        }

        guard let data else {
            let err = lastError ?? URLError(.cannotConnectToHost)
            logger.error("All endpoints failed: \(err.localizedDescription)")
            throw err
        }

        // Decode on a background task so JSON parsing doesn't block the network call.
        return try await Task.detached(priority: .userInitiated) {
            let decoded = try JSONDecoder().decode(OverpassResponse.self, from: data)
            var courts: [Court] = []
            var seen = Set<String>()

            for element in decoded.elements {
                let lat: Double
                let lon: Double

                if let elLat = element.lat, let elLon = element.lon {
                    lat = elLat
                    lon = elLon
                } else if let center = element.center {
                    lat = center.lat
                    lon = center.lon
                } else {
                    continue
                }

                // Coordinates rounded to 5 decimals (~1 meter precision) as a stable court ID.
                // This handles cases where the same court is represented twice in OSM with tiny coordinate variations.
                let id = String(format: "%.5f,%.5f", lat, lon)
                guard !seen.contains(id) else { continue }
                seen.insert(id)

                let tags = element.tags ?? [:]
                let name = tags["name"]
                    ?? tags["official_name"]
                    ?? tags["operator"]
                    ?? "Basketball Court"

                let address = [
                    tags["addr:housenumber"],
                    tags["addr:street"],
                    tags["addr:city"],
                ]
                .compactMap { $0 }
                .joined(separator: " ")

                courts.append(Court(
                    id: id,
                    name: name,
                    latitude: lat,
                    longitude: lon,
                    address: address,
                    occupancyCount: nil
                ))
            }

            return courts
        }.value
    }
}

// MARK: - Fallback court data

private struct FallbackCourt: Decodable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let address: String
}

// MARK: - Overpass API response types

private struct OverpassResponse: Decodable {
    let elements: [OverpassElement]
}

private struct OverpassElement: Decodable {
    let type: String
    let id: Int64
    let lat: Double?
    let lon: Double?
    let center: OverpassCenter?
    let tags: [String: String]?
}

private struct OverpassCenter: Decodable {
    let lat: Double
    let lon: Double
}
