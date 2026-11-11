import CoreGraphics

/// The latitude-span fraction that centres a target in the uncovered map.
nonisolated enum MapFraming {
    static let fallbackNorthBias = 0.12

    static func northBias(sheetHeight: CGFloat, mapHeight: CGFloat) -> Double {
        guard mapHeight.isFinite, mapHeight > 0, sheetHeight.isFinite else {
            return fallbackNorthBias
        }
        let coverage = min(max(sheetHeight, 0), mapHeight)
        return Double(coverage / 2 / mapHeight)
    }
}
