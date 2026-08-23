import FirebaseFirestore
import XCTest
@testable import hoopr

/// Guards the contract between `UserProfile` and the documents actually stored
/// in the `users` collection. These run through `Firestore.Decoder` — the same
/// decoder `UserProfileService` uses — so a field rename in the console or in
/// the model breaks a test here rather than silently emptying the profile UI.
final class UserProfileTests: XCTestCase {

    private let decoder = Firestore.Decoder()

    /// Mirrors the full stored document, including `homeCourtId` and the
    /// derived `userNameLower` search mirror.
    func testDecodesStoredDocumentShape() throws {
        let created = Timestamp(date: Date(timeIntervalSince1970: 1_780_000_000))
        let updated = Timestamp(date: Date(timeIntervalSince1970: 1_780_000_015))

        let document: [String: Any] = [
            "id": "test-user-000",
            "userName": "Test User",
            "userNameLower": "test user",
            "homeCourtId": "0000",
            "preferredRadius": 12,
            "createdAt": created,
            "updatedAt": updated,
        ]

        let profile = try decoder.decode(UserProfile.self, from: document)

        XCTAssertEqual(profile.id, "test-user-000")
        XCTAssertEqual(profile.userName, "Test User")
        XCTAssertEqual(profile.userNameLower, "test user")
        XCTAssertEqual(profile.homeCourtId, "0000")
        XCTAssertEqual(profile.preferredRadius, 12)
        XCTAssertEqual(profile.createdAt, created.dateValue())
        XCTAssertEqual(profile.updatedAt, updated.dateValue())
    }

    /// A profile that predates a field must still decode — `homeCourtId`,
    /// `preferredRadius` and `userNameLower` are all optional for that reason.
    func testDecodesMinimalDocument() throws {
        let document: [String: Any] = [
            "id": "uid-1",
            "userName": "Hooper",
        ]

        let profile = try decoder.decode(UserProfile.self, from: document)

        XCTAssertEqual(profile.id, "uid-1")
        XCTAssertEqual(profile.userName, "Hooper")
        XCTAssertNil(profile.userNameLower)
        XCTAssertNil(profile.homeCourtId)
        XCTAssertNil(profile.preferredRadius)
        XCTAssertNil(profile.createdAt)
        XCTAssertNil(profile.updatedAt)
    }

    /// Documents written before the email field was removed still carry one.
    /// Decoding must ignore it rather than failing — and the model must not
    /// resurface it, which is why there's no property to assert on.
    func testIgnoresALegacyEmailField() throws {
        let document: [String: Any] = [
            "id": "uid-1",
            "userName": "Hooper",
            "email": "someone@hoopr.edu",
        ]

        let profile = try decoder.decode(UserProfile.self, from: document)

        XCTAssertEqual(profile.id, "uid-1")
        XCTAssertEqual(profile.userName, "Hooper")
    }

    /// Firestore stores every number as a double, but a value entered as a
    /// whole number in the console comes back as an integer — it must still
    /// decode into `Double?`.
    func testDecodesIntegerRadius() throws {
        let document: [String: Any] = [
            "id": "uid-1",
            "userName": "Hooper",
            "preferredRadius": 25,
        ]

        let profile = try decoder.decode(UserProfile.self, from: document)

        XCTAssertEqual(profile.preferredRadius, 25)
    }

    /// The map searches with a real radius even before the user picks one, so
    /// the unset case has to resolve to the default rather than to zero.
    func testUnsetRadiusFallsBackToDefault() throws {
        let document: [String: Any] = [
            "id": "uid-1",
            "userName": "Hooper",
        ]

        let profile = try decoder.decode(UserProfile.self, from: document)

        XCTAssertEqual(profile.effectivePreferredRadius, UserProfile.defaultPreferredRadius)
    }

    /// A stored preference must win over the default.
    func testStoredRadiusOverridesDefault() throws {
        let document: [String: Any] = [
            "id": "uid-1",
            "userName": "Hooper",
            "preferredRadius": 30,
        ]

        let profile = try decoder.decode(UserProfile.self, from: document)

        XCTAssertEqual(profile.effectivePreferredRadius, 30)
    }

    /// Regression: a `preferredRadius` of `0` — what a field added by hand in
    /// the Firebase console is seeded with — is a valid `Double`, so a plain
    /// `?? default` let it through and filtered every court out of the nearby
    /// list. Out-of-range values must fall back like an absent one.
    func testZeroRadiusFallsBackToDefault() throws {
        let document: [String: Any] = [
            "id": "uid-1",
            "userName": "Hooper",
            "preferredRadius": 0,
        ]

        let profile = try decoder.decode(UserProfile.self, from: document)

        XCTAssertEqual(profile.effectivePreferredRadius, UserProfile.defaultPreferredRadius)
    }

    /// The same guard has to hold at both ends, and for a value the rules
    /// would never have accepted in the first place.
    func testOutOfRangeRadiiFallBackToDefault() {
        for stored in [-1, 0, 0.5, 51, 10_000] as [Double] {
            XCTAssertEqual(
                UserProfile.validRadius(stored),
                UserProfile.defaultPreferredRadius,
                "\(stored) is outside the allowed range and should fall back"
            )
        }
    }

    /// The bounds themselves are usable — an off-by-one in `validRadius`
    /// would otherwise silently reset anyone sitting at exactly 1 or 50.
    func testRangeBoundsAreAccepted() {
        let range = UserProfile.preferredRadiusRange
        XCTAssertEqual(UserProfile.validRadius(range.lowerBound), range.lowerBound)
        XCTAssertEqual(UserProfile.validRadius(range.upperBound), range.upperBound)
    }

    /// The slider's bounds and the ones `firestore.rules` enforces have to
    /// agree — a mismatch turns an in-range save into a `permission-denied`.
    func testDefaultRadiusIsInsideTheAllowedRange() {
        XCTAssertTrue(
            UserProfile.preferredRadiusRange.contains(UserProfile.defaultPreferredRadius)
        )
    }

    /// `userName` is the one field the UI depends on, so its absence must be a
    /// loud decode failure rather than a silently blank profile.
    func testMissingUserNameFailsToDecode() {
        let document: [String: Any] = [
            "id": "uid-1",
            "homeCourtId": "0000",
        ]

        XCTAssertThrowsError(try decoder.decode(UserProfile.self, from: document))
    }

    /// Server timestamps are write-only sentinels; a document read back before
    /// the server resolves them carries nulls, which must not crash decoding.
    func testDecodesPendingServerTimestamps() throws {
        let document: [String: Any] = [
            "id": "uid-1",
            "userName": "Hooper",
            "createdAt": NSNull(),
            "updatedAt": NSNull(),
        ]

        let profile = try decoder.decode(UserProfile.self, from: document)

        XCTAssertNil(profile.createdAt)
        XCTAssertNil(profile.updatedAt)
    }

    // MARK: - Name validation

    /// Mirrors the `userName` conditions in the create and update rules. The
    /// length bound is the one that used to be enforced *only* server-side,
    /// where it surfaced as `permission-denied` — see
    /// `FirestoreRulesParityTests`, which pins the two copies together.

    func testAcceptsAnOrdinaryName() {
        XCTAssertNil(UserProfile.validate(userName: "aeleot11"))
    }

    func testRejectsABlankName() {
        XCTAssertEqual(UserProfile.validate(userName: ""), .emptyUserName)
        XCTAssertEqual(UserProfile.validate(userName: "   "), .emptyUserName)
        XCTAssertEqual(UserProfile.validate(userName: "\n\t "), .emptyUserName)
    }

    func testAcceptsANameAtTheLimit() {
        let name = String(repeating: "a", count: UserProfile.maxUserNameLength)

        XCTAssertNil(UserProfile.validate(userName: name))
    }

    func testRejectsANameOverTheLimit() {
        let name = String(repeating: "a", count: UserProfile.maxUserNameLength + 1)

        XCTAssertEqual(UserProfile.validate(userName: name), .userNameTooLong)
    }

    /// Length is measured after trimming, matching what actually gets written —
    /// otherwise a name padded with spaces would be rejected for a length the
    /// server never sees.
    func testMeasuresLengthAfterTrimming() {
        let name = "  " + String(repeating: "a", count: UserProfile.maxUserNameLength) + "  "

        XCTAssertNil(UserProfile.validate(userName: name))
    }
}
