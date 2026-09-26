import XCTest
@testable import hoopr

final class MapFramingTests: XCTestCase {
    func testTargetIsCentredInTheUncoveredMap() {
        for mapHeight: CGFloat in [300, 520, 730] {
            for coverage: CGFloat in [0, 100, 240] {
                let bias = MapFraming.northBias(sheetHeight: coverage, mapHeight: mapHeight)
                let targetY = mapHeight * (0.5 - bias)
                XCTAssertEqual(targetY, (mapHeight - coverage) / 2, accuracy: 0.001)
            }
        }
    }

    func testTheCollapsedSheetHasNoBias() {
        XCTAssertEqual(MapFraming.northBias(sheetHeight: 0, mapHeight: 600), 0)
        XCTAssertEqual(MapFraming.northBias(sheetHeight: -40, mapHeight: 600), 0)
    }

    func testCoverageCannotPushTheTargetBeyondTheMap() {
        XCTAssertEqual(MapFraming.northBias(sheetHeight: 600, mapHeight: 600), 0.5)
        XCTAssertEqual(MapFraming.northBias(sheetHeight: 900, mapHeight: 600), 0.5)
    }

    func testUnmeasuredGeometryKeepsThePreviousFallback() {
        for height: CGFloat in [0, -1, .nan, .infinity] {
            XCTAssertEqual(MapFraming.northBias(sheetHeight: 200, mapHeight: height), 0.12)
        }
        XCTAssertEqual(MapFraming.northBias(sheetHeight: .nan, mapHeight: 600), 0.12)
    }
}
