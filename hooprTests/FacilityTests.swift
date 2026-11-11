import CoreLocation
import XCTest
@testable import hoopr

/// Guards the facility layer: the grouping of courts into the places players
/// actually travel to, and the invariants the bundled dataset has to hold for
/// that grouping to mean anything.
///
/// Worth pinning because the failure mode is silent and only visible in
/// production. OSM tags each playing surface as its own way, so Long Meadow Park
/// arrives as three courts 17m apart. Ungrouped, that's three overlapping map
/// pins and — the reason this layer exists — three separate queues at one
/// physical court, none able to see the others. Nothing throws, nothing logs;
/// two players standing on the same asphalt are just invisible to each other.
///
/// The dataset cases at the bottom run against the real `courts.json` through
/// `CourtService`, the same way `SquadViewModelTests` pins its region rule, so
/// regenerating the dataset can't quietly drop `facilityId` or renumber it into
/// collisions with court IDs.
final class FacilityTests: XCTestCase {

    private func court(
        _ id: String,
        name: String,
        facilityId: String? = nil,
        latitude: Double = 35.9940,
        longitude: Double = -78.8986,
        city: String = "Durham"
    ) -> Court {
        Court(
            id: id,
            name: name,
            latitude: latitude,
            longitude: longitude,
            address: "\(city), NC",
            city: city,
            access: .public,
            facilityId: facilityId
        )
    }

    // MARK: - Grouping

    func testGroupsCourtsSharingAFacilityId() {
        let facilities = Facility.group([
            court("c1", name: "Long Meadow Park Basketball Court #1", facilityId: "f1"),
            court("c2", name: "Long Meadow Park Basketball Court #2", facilityId: "f1"),
            court("c3", name: "Long Meadow Park Basketball Court #3", facilityId: "f1"),
            court("c4", name: "Walltown Park Basketball Court", facilityId: "f2"),
        ])

        XCTAssertEqual(facilities.count, 2)
        XCTAssertEqual(facilities[0].id, "f1")
        XCTAssertEqual(facilities[0].surfaceCount, 3)
        XCTAssertEqual(facilities[0].courtIds, ["c1", "c2", "c3"])
        XCTAssertEqual(facilities[1].surfaceCount, 1)
    }

    /// A court with no facility stated is its own facility — the property that
    /// lets every call site key on `facilityId` without a nil check.
    func testACourtWithoutAFacilityIsItsOwnFacility() {
        let solo = court("c1", name: "Somewhere Basketball Court")

        XCTAssertEqual(solo.facilityId, "c1")

        let facilities = Facility.group([solo])
        XCTAssertEqual(facilities.count, 1)
        XCTAssertEqual(facilities[0].id, "c1")
    }

    /// Input order is preserved because `CourtService` sorts by name and a map
    /// built from an unordered dictionary would reshuffle between rebuilds.
    func testGroupingPreservesInputOrder() {
        let facilities = Facility.group([
            court("c1", name: "Alpha Basketball Court", facilityId: "f-alpha"),
            court("c2", name: "Bravo Basketball Court", facilityId: "f-bravo"),
            court("c3", name: "Charlie Basketball Court", facilityId: "f-charlie"),
        ])

        XCTAssertEqual(facilities.map(\.id), ["f-alpha", "f-bravo", "f-charlie"])
    }

    // MARK: - Naming

    /// The primary is the shortest display name, which is what drops the "#1"
    /// that only existed because OSM split the court. Taking `courts.first`
    /// would reliably pick "#1" — a name telling the reader about a "#2" they
    /// can't see.
    func testPrimaryPrefersTheUnnumberedName() {
        let facility = Facility(id: "f1", courts: [
            court("c1", name: "Halifax Park Children's Outdoor Basketball Court", facilityId: "f1"),
            court("c2", name: "Halifax Park Outdoor Basketball Court", facilityId: "f1"),
        ])

        XCTAssertEqual(facility.primary.id, "c2")
    }

    func testDisplayNameDropsTheSurfaceNumber() {
        let facility = Facility(id: "f1", courts: [
            court("c1", name: "Long Meadow Park Basketball Court #1", facilityId: "f1"),
            court("c2", name: "Long Meadow Park Basketball Court #2", facilityId: "f1"),
        ])

        XCTAssertEqual(facility.displayName, "Long Meadow Park")
    }

    /// A name whose only content is a number keeps it — stripping would leave
    /// nothing, the same fallback `Court.displayName` makes.
    func testDisplayNameSurvivesANameThatIsOnlyANumber() {
        let facility = Facility(id: "f1", courts: [
            court("c1", name: "Apex Basketball Court #7", facilityId: "f1"),
        ])

        XCTAssertEqual(facility.displayName, "Apex")
    }

    func testSurfaceCountTextIsSilentForASingleCourt() {
        let solo = Facility(id: "f1", courts: [
            court("c1", name: "Walltown Park Basketball Court", facilityId: "f1"),
        ])
        XCTAssertNil(solo.surfaceCountText)

        let park = Facility(id: "f2", courts: [
            court("c2", name: "Long Meadow Park Basketball Court #1", facilityId: "f2"),
            court("c3", name: "Long Meadow Park Basketball Court #2", facilityId: "f2"),
        ])
        XCTAssertEqual(park.surfaceCountText, "2 courts")
    }

    // MARK: - Geometry

    /// The pin sits at the centre of the surfaces, not on the primary. With
    /// three courts in a row the primary is an end one, and a pin on the end
    /// reads as pointing at that surface rather than at the park.
    func testCoordinateIsTheCentreOfItsSurfaces() {
        let facility = Facility(id: "f1", courts: [
            court("c1", name: "A Basketball Court", facilityId: "f1",
                  latitude: 36.0, longitude: -78.0),
            court("c2", name: "B Basketball Court", facilityId: "f1",
                  latitude: 36.2, longitude: -78.4),
        ])

        XCTAssertEqual(facility.coordinate.latitude, 36.1, accuracy: 0.000001)
        XCTAssertEqual(facility.coordinate.longitude, -78.2, accuracy: 0.000001)
    }

    /// Davis Drive Elementary School really does ship as one court in Cary and
    /// one in Morrisville — nearest-centroid assignment straddling a municipal
    /// line. Grouping them at least makes the app show one answer rather than
    /// two, and the primary's is the only defensible pick.
    func testCityComesFromThePrimaryWhenSurfacesDisagree() {
        let facility = Facility(id: "f1", courts: [
            court("c1", name: "Davis Drive Elementary School Basketball Court",
                  facilityId: "f1", city: "Cary"),
            court("c2", name: "Davis Drive Elementary School Basketball Court #2",
                  facilityId: "f1", city: "Morrisville"),
        ])

        XCTAssertEqual(facility.city, "Cary")
        XCTAssertEqual(facility.city, facility.primary.city)
    }

    // MARK: - The bundled dataset

    func testEveryBundledCourtHasAFacility() throws {
        let courts = CourtService().courts
        try XCTSkipIf(courts.isEmpty, "bundled courts.json failed to load")

        for court in courts {
            XCTAssertFalse(
                court.facilityId.isEmpty,
                "\(court.name) has an empty facilityId"
            )
        }
    }

    /// A facility ID must never be mistakable for a court ID. `assign_facilities.py`
    /// namespaces them under `facility/` for exactly this reason — a value in the
    /// wrong field should be obviously wrong rather than merely wrong, and a
    /// collision would make a court look up its own games as if it were a park.
    func testNoFacilityIdCollidesWithACourtId() throws {
        let courts = CourtService().courts
        try XCTSkipIf(courts.isEmpty, "bundled courts.json failed to load")

        let courtIds = Set(courts.map(\.id))
        let facilityIds = Set(courts.map(\.facilityId))

        XCTAssertTrue(
            courtIds.isDisjoint(with: facilityIds),
            "facility IDs overlap court IDs: \(courtIds.intersection(facilityIds))"
        )
    }

    /// The dataset genuinely contains multi-surface facilities, so the grouping
    /// above isn't being proved against a file where every facility happens to
    /// hold one court. If this fails, either `assign_facilities.py` stopped
    /// grouping or the dataset lost its split parks — both worth knowing.
    func testTheBundledDatasetGroupsSomeCourts() throws {
        let service = CourtService()
        try XCTSkipIf(service.courts.isEmpty, "bundled courts.json failed to load")

        let facilities = service.facilities
        XCTAssertLessThan(
            facilities.count,
            service.courts.count,
            "no court in the dataset shares a facility with another"
        )
        XCTAssertTrue(
            facilities.contains { $0.surfaceCount > 1 },
            "expected at least one facility with more than one surface"
        )
        // Every court is accounted for exactly once.
        XCTAssertEqual(
            facilities.reduce(0) { $0 + $1.surfaceCount },
            service.courts.count
        )
    }

    // MARK: - Amenity honesty

    /// **No court may claim lights it hasn't been verified to have.**
    ///
    /// Decided 2026-09-22. Durham and Wake publish lighting at *park* level, and
    /// applying it would lift `isLit` coverage from 9.8% to roughly 40% — which is
    /// exactly why `tools/enrich_courts.py` refuses to: a park's lights may be on
    /// its ballfield, and a court shown as lit that is dark at 7pm costs a player
    /// a wasted trip. A court that admits it doesn't know costs them nothing.
    ///
    /// So every `isLit == true` in the bundle has to come from a **court-level**
    /// source or an on-site check. This asserts the dataset side of that rule;
    /// `tools/audit_courts.py` asserts it again over `provenance` on every run.
    ///
    /// The count is deliberately *not* pinned — it should grow as courts are
    /// verified in person. Only the sourcing rule is fixed.
    func testNoCourtClaimsLightsWithoutACourtLevelSource() throws {
        let url = try XCTUnwrap(
            Bundle(for: CourtService.self).url(forResource: "courts", withExtension: "json"),
            "courts.json missing from the test bundle"
        )
        let raw = try JSONSerialization.jsonObject(
            with: try Data(contentsOf: url)
        ) as? [String: Any]
        let courts = try XCTUnwrap(raw?["courts"] as? [[String: Any]])

        // Sources entitled to assert an amenity — everything whose *grain* is a
        // single playing surface. `osm` qualifies (one way per court) and is the
        // tier most likely to be stale, which is why it's flagged for on-site
        // confirmation in `tools/verify_worklist.json` rather than excluded here.
        // Park-level sources are absent on purpose. Keep in step with
        // `audit_courts.py`.
        let trusted: Set<String> = ["raleigh_courts", "verified-onsite", "osm"]

        for court in courts {
            guard court["isLit"] as? Bool == true else { continue }
            let provenance = court["provenance"] as? [String: String] ?? [:]
            let source = provenance["isLit"]
            XCTAssertNotNil(
                source,
                "\(court["name"] ?? "?") claims isLit=true with no provenance"
            )
            if let source {
                XCTAssertTrue(
                    trusted.contains(source),
                    "\(court["name"] ?? "?") claims isLit=true from '\(source)', "
                        + "which is park-level — lights may be on the ballfield"
                )
            }
        }
    }

    /// The same rule for the other two amenities official data can set.
    func testAmenitiesOnlyComeFromCourtLevelSources() throws {
        let url = try XCTUnwrap(
            Bundle(for: CourtService.self).url(forResource: "courts", withExtension: "json")
        )
        let raw = try JSONSerialization.jsonObject(
            with: try Data(contentsOf: url)
        ) as? [String: Any]
        let courts = try XCTUnwrap(raw?["courts"] as? [[String: Any]])
        let trusted: Set<String> = ["raleigh_courts", "verified-onsite", "osm"]

        for court in courts {
            let provenance = court["provenance"] as? [String: String] ?? [:]
            for field in ["isLit", "isCovered", "surface", "hoops"] {
                guard let source = provenance[field] else { continue }
                XCTAssertTrue(
                    trusted.contains(source),
                    "\(court["name"] ?? "?") took \(field) from park-level '\(source)'"
                )
            }
        }
    }

    /// An address, unlike an amenity, is safe to take from a park: a court inside
    /// a park's boundary really is at that park's street address. Pinned because
    /// the dataset shipped with all 214 addresses reading "<City>, NC" — a field
    /// that was 100% populated and carried nothing.
    func testSomeCourtsHaveARealStreetAddress() throws {
        let courts = CourtService().courts
        try XCTSkipIf(courts.isEmpty, "bundled courts.json failed to load")

        let withStreetNumber = courts.filter {
            $0.address.range(of: #"^\d+\s"#, options: .regularExpression) != nil
        }
        XCTAssertGreaterThan(
            withStreetNumber.count, 50,
            "expected official data to have supplied real addresses"
        )
    }

    func testFacilityLookupCoversEveryCourt() throws {
        let service = CourtService()
        try XCTSkipIf(service.courts.isEmpty, "bundled courts.json failed to load")

        for court in service.courts {
            XCTAssertEqual(
                service.facilityIdsByCourtId[court.id],
                court.facilityId,
                "\(court.name) is missing from facilityIdsByCourtId"
            )
        }
    }
}
