import FirebaseFirestore
import XCTest
@testable import hoopr

/// Guards the contract between `UserProfile` and the documents actually stored
/// in the `users` collection. These run through `Firestore.Decoder` — the same
/// decoder `UserProfileService` uses — so a field rename in the console or in
/// the model breaks a test here rather than silently emptying the profile UI.
final class UserProfileTests: XCTestCase {

    private let decoder = Firestore.Decoder()

    /// Mirrors the seed document created by hand in the Firebase console,
    /// including `homeCourtId`, which the app reads but never writes.
    func testDecodesStoredDocumentShape() throws {
        let created = Timestamp(date: Date(timeIntervalSince1970: 1_780_000_000))
        let updated = Timestamp(date: Date(timeIntervalSince1970: 1_780_000_015))

        let document: [String: Any] = [
            "id": "test-user-000",
            "userName": "Test User",
            "email": "testuser@hoopr.edu",
            "homeCourtId": "0000",
            "createdAt": created,
            "updatedAt": updated,
        ]

        let profile = try decoder.decode(UserProfile.self, from: document)

        XCTAssertEqual(profile.id, "test-user-000")
        XCTAssertEqual(profile.userName, "Test User")
        XCTAssertEqual(profile.email, "testuser@hoopr.edu")
        XCTAssertEqual(profile.homeCourtId, "0000")
        XCTAssertEqual(profile.createdAt, created.dateValue())
        XCTAssertEqual(profile.updatedAt, updated.dateValue())
    }

    /// A freshly provisioned profile omits `email` when Auth has none, and
    /// never sets `homeCourtId`. Both must stay optional.
    func testDecodesMinimalDocument() throws {
        let document: [String: Any] = [
            "id": "uid-1",
            "userName": "Hooper",
        ]

        let profile = try decoder.decode(UserProfile.self, from: document)

        XCTAssertEqual(profile.id, "uid-1")
        XCTAssertEqual(profile.userName, "Hooper")
        XCTAssertNil(profile.email)
        XCTAssertNil(profile.homeCourtId)
        XCTAssertNil(profile.createdAt)
        XCTAssertNil(profile.updatedAt)
    }

    /// `userName` is the one field the UI depends on, so its absence must be a
    /// loud decode failure rather than a silently blank profile.
    func testMissingUserNameFailsToDecode() {
        let document: [String: Any] = [
            "id": "uid-1",
            "email": "someone@hoopr.edu",
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
}
