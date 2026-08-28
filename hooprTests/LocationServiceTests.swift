import XCTest
import CoreLocation
@testable import hoopr

/// Guards the one rule `LocationService` actually decides: whether a new fix is
/// far enough from the current anchor to be worth adopting.
///
/// It matters because the anchor is shared — the map's list, the detail card's
/// distance, Home's hot courts and the Local Runs radius all measure from it —
/// so a threshold that's too low churns four surfaces every time GPS jitters,
/// and one that's too high leaves every distance in the app quietly wrong.
final class LocationServiceTests: XCTestCase {

    private let durham = LocationService.defaultLocation

    /// *Approximately* `meters` north of `durham`.
    ///
    /// Deliberately approximate: a degree of latitude is ~110,960m on the
    /// WGS84 ellipsoid at this latitude, not the round 111,000 used here, so a
    /// point built for "exactly 100m" measures nearer 99.97m. Every assertion
    /// below is therefore anchored to the distance `Distance.between` actually
    /// reports rather than to the number passed in here.
    private func north(_ meters: CLLocationDistance) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: durham.latitude + meters / 111_000,
            longitude: durham.longitude
        )
    }

    func testAMoveShorterThanTheThresholdIsRejected() {
        XCTAssertFalse(LocationService.shouldAdopt(north(50), over: durham))
    }

    func testAMoveLongerThanTheThresholdIsAdopted() {
        XCTAssertTrue(LocationService.shouldAdopt(north(250), over: durham))
    }

    /// The comparison is `>=`, so a fix at or past the threshold counts. Both
    /// halves assert the measured distance first, so a failure here means the
    /// rule changed rather than the approximation above drifting.
    func testTheBoundaryIsInclusive() {
        let justPast = north(LocationService.significantMove + 5)
        XCTAssertGreaterThanOrEqual(
            Distance.between(durham, justPast),
            LocationService.significantMove
        )
        XCTAssertTrue(LocationService.shouldAdopt(justPast, over: durham))

        let justShort = north(LocationService.significantMove - 5)
        XCTAssertLessThan(
            Distance.between(durham, justShort),
            LocationService.significantMove
        )
        XCTAssertFalse(LocationService.shouldAdopt(justShort, over: durham))
    }

    func testTheSamePointIsNeverAdopted() {
        XCTAssertFalse(LocationService.shouldAdopt(durham, over: durham))
    }

    /// Distance is symmetric, so walking back should behave like walking out.
    func testTheRuleIsSymmetric() {
        let far = north(250)
        XCTAssertEqual(
            LocationService.shouldAdopt(far, over: durham),
            LocationService.shouldAdopt(durham, over: far)
        )
    }

    /// A sanity check on the constant itself: distances render to a tenth of a
    /// mile (~160m), so the threshold has to sit below that to be meaningful
    /// and above GPS jitter to be useful.
    func testTheThresholdIsBelowTheSmallestRenderedDistance() {
        XCTAssertLessThan(LocationService.significantMove, Distance.meters(miles: 0.1))
        XCTAssertGreaterThan(LocationService.significantMove, 0)
    }
}
