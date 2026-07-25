import Foundation
import MapKit
import os

fileprivate let cacheLogger = Logger(subsystem: "com.hoopr", category: "CourtCache")

struct BoundingBox: Codable, Sendable {
    let south: Double
    let north: Double
    let west: Double
    let east: Double

    func contains(_ region: MKCoordinateRegion) -> Bool {
        let regionSouth = region.center.latitude - region.span.latitudeDelta / 2
        let regionNorth = region.center.latitude + region.span.latitudeDelta / 2
        let regionWest = region.center.longitude - region.span.longitudeDelta / 2
        let regionEast = region.center.longitude + region.span.longitudeDelta / 2
        return south <= regionSouth
            && north >= regionNorth
            && west <= regionWest
            && east >= regionEast
    }

    func subdivide(gridSize: Int) -> [BoundingBox] {
        let latStep = (north - south) / Double(gridSize)
        let lonStep = (east - west) / Double(gridSize)

        var boxes: [BoundingBox] = []
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                boxes.append(BoundingBox(
                    south: south + Double(row) * latStep,
                    north: south + Double(row + 1) * latStep,
                    west: west + Double(col) * lonStep,
                    east: west + Double(col + 1) * lonStep
                ))
            }
        }
        return boxes
    }
}

struct CachedRegion: Codable, Sendable {
    let box: BoundingBox
    let courts: [Court]
    let timestamp: Date
}

/// Manages persistent local cache of court data on disk.
/// Cached regions are stored in the app's Documents directory.
final class CourtCache {
    private let fileURL: URL
    private var regions: [CachedRegion] = []
    private let maxRegions = 10
    private let cacheExpirationDays: TimeInterval = 30

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("court_cache.json")
        load()
    }

    func loadMostRecent() -> CachedRegion? {
        let now = Date()
        let maxAge = cacheExpirationDays * 24 * 60 * 60
        return regions
            .filter { now.timeIntervalSince($0.timestamp) < maxAge }
            .max(by: { $0.timestamp < $1.timestamp })
    }

    /// Returns the most recent non-expired cached region that fully contains the given map region.
    func find(covering region: MKCoordinateRegion) -> CachedRegion? {
        let now = Date()
        let maxAge = cacheExpirationDays * 24 * 60 * 60
        return regions
            .filter { $0.box.contains(region) }
            .filter { now.timeIntervalSince($0.timestamp) < maxAge }
            .max(by: { $0.timestamp < $1.timestamp })
    }

    /// Saves a new cached region to disk, keeping only the N most recent.
    func save(box: BoundingBox, courts: [Court]) {
        let cached = CachedRegion(box: box, courts: courts, timestamp: Date())
        regions.append(cached)

        // Keep only the most recent N regions
        if regions.count > maxRegions {
            regions = Array(regions.sorted { $0.timestamp > $1.timestamp }.prefix(maxRegions))
        }

        persist()
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cacheLogger.debug("No cache file exists yet")
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            regions = try JSONDecoder().decode([CachedRegion].self, from: data)
            cacheLogger.debug("Loaded \(self.regions.count) cached regions from disk")
        } catch {
            cacheLogger.error("Failed to load cache: \(error.localizedDescription)")
            regions = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(regions)
            try data.write(to: fileURL, options: .atomic)
            cacheLogger.debug("Saved \(self.regions.count) regions to disk (\(data.count) bytes)")
        } catch {
            cacheLogger.error("Failed to save cache: \(error.localizedDescription)")
        }
    }

    /// Clears all cached regions (for debugging/testing).
    func clear() {
        regions = []
        try? FileManager.default.removeItem(at: fileURL)
    }
}
