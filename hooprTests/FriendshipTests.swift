import FirebaseFirestore
import XCTest
@testable import hoopr

/// Guards the contract between `Friendship` and the documents actually stored
/// in the `friendships` collection. These run through `Firestore.Decoder` — the
/// same decoder `FriendService` uses — so a field rename in the console or in
/// the model breaks a test here rather than silently emptying the friends list.
final class FriendshipTests: XCTestCase {

    private let decoder = Firestore.Decoder()

    /// The full stored shape. Note what *isn't* in it: there's no `id` field.
    /// The rules' key allowlist rejects one, so `Friendship.id` is derived from
    /// the pair rather than mirrored out of the document the way `Game.id` is.
    func testDecodesStoredDocumentShape() throws {
        let created = Timestamp(date: Date(timeIntervalSince1970: 1_780_000_000))
        let updated = Timestamp(date: Date(timeIntervalSince1970: 1_780_000_015))

        let document: [String: Any] = [
            "uidA": "aaa111",
            "uidB": "bbb222",
            "requestedBy": "bbb222",
            "status": "accepted",
            "createdAt": created,
            "updatedAt": updated,
        ]

        let friendship = try decoder.decode(Friendship.self, from: document)

        XCTAssertEqual(friendship.uidA, "aaa111")
        XCTAssertEqual(friendship.uidB, "bbb222")
        XCTAssertEqual(friendship.requestedBy, "bbb222")
        XCTAssertEqual(friendship.status, .accepted)
        XCTAssertEqual(friendship.createdAt, created.dateValue())
        XCTAssertEqual(friendship.updatedAt, updated.dateValue())
        XCTAssertEqual(friendship.id, "aaa111_bbb222")
    }

    /// Server timestamps are write-only sentinels; a document read back before
    /// the server resolves them carries nulls, which must not crash decoding.
    /// This is the *normal* case for the person who just sent a request —
    /// Firestore delivers their own write's snapshot before the server stamps
    /// it.
    func testDecodesPendingServerTimestamps() throws {
        let document: [String: Any] = [
            "uidA": "aaa111",
            "uidB": "bbb222",
            "requestedBy": "aaa111",
            "status": "pending",
            "createdAt": NSNull(),
            "updatedAt": NSNull(),
        ]

        let friendship = try decoder.decode(Friendship.self, from: document)

        XCTAssertEqual(friendship.status, .pending)
        XCTAssertNil(friendship.createdAt)
        XCTAssertNil(friendship.updatedAt)
    }

    /// A status the model doesn't declare must fail loudly rather than decode
    /// into something arbitrary — the rules only ever store these two, so a
    /// third value means the document was hand-edited.
    func testDecodesOnlyTheDeclaredStatuses() {
        let document: [String: Any] = [
            "uidA": "aaa111",
            "uidB": "bbb222",
            "requestedBy": "aaa111",
            "status": "declined",
        ]

        XCTAssertThrowsError(try decoder.decode(Friendship.self, from: document))
    }

    /// `requestedBy` is what makes a pending edge directional. Without it there
    /// is no way to tell a sent request from a received one, so its absence has
    /// to be a decode failure rather than a row that renders the wrong buttons.
    func testMissingRequestedByFailsToDecode() {
        let document: [String: Any] = [
            "uidA": "aaa111",
            "uidB": "bbb222",
            "status": "pending",
        ]

        XCTAssertThrowsError(try decoder.decode(Friendship.self, from: document))
    }

    // MARK: - Document ID

    /// The whole point of the ordered pair: both people compute the same ID, so
    /// there is structurally only one document for a given friendship.
    func testIdIsOrderIndependent() {
        XCTAssertEqual(Friendship.id(for: "b", "a"), Friendship.id(for: "a", "b"))
        XCTAssertEqual(Friendship.id(for: "b", "a"), "a_b")
    }

    /// The derived `id` has to agree with the ID the rules recompute from the
    /// same two fields, or a write would land at a document nobody reads.
    func testDerivedIdMatchesTheIdHelper() {
        let friendship = Friendship(
            uidA: "aaa111",
            uidB: "bbb222",
            requestedBy: "aaa111",
            status: .pending,
            createdAt: nil,
            updatedAt: nil
        )

        XCTAssertEqual(friendship.id, Friendship.id(for: "bbb222", "aaa111"))
    }

    func testOtherUidReturnsTheOtherParticipant() {
        let friendship = Friendship(
            uidA: "aaa111",
            uidB: "bbb222",
            requestedBy: "aaa111",
            status: .accepted,
            createdAt: nil,
            updatedAt: nil
        )

        XCTAssertEqual(friendship.otherUid(than: "aaa111"), "bbb222")
        XCTAssertEqual(friendship.otherUid(than: "bbb222"), "aaa111")
    }

    // MARK: - Direction

    /// Direction is read off `requestedBy`, never off which side of the pair
    /// you happen to be — the pair order is lexicographic and arbitrary, so
    /// both `requestedBy` cases have to be checked from both sides.

    func testPendingRequestFromUidAIsSentForThemAndReceivedForTheOther() {
        let friendship = pending(requestedBy: "aaa111")

        XCTAssertEqual(friendship.direction(for: "aaa111"), .sent)
        XCTAssertEqual(friendship.direction(for: "bbb222"), .received)
    }

    func testPendingRequestFromUidBIsSentForThemAndReceivedForTheOther() {
        let friendship = pending(requestedBy: "bbb222")

        XCTAssertEqual(friendship.direction(for: "bbb222"), .sent)
        XCTAssertEqual(friendship.direction(for: "aaa111"), .received)
    }

    /// Once accepted, the edge stops being directional for either participant —
    /// `requestedBy` stays stored, but it no longer describes anything the UI
    /// should act on.
    func testAcceptedIsMutualForBothParticipantsWhoeverAsked() {
        for requester in ["aaa111", "bbb222"] {
            let friendship = Friendship(
                uidA: "aaa111",
                uidB: "bbb222",
                requestedBy: requester,
                status: .accepted,
                createdAt: nil,
                updatedAt: nil
            )

            XCTAssertEqual(friendship.direction(for: "aaa111"), .mutual)
            XCTAssertEqual(friendship.direction(for: "bbb222"), .mutual)
        }
    }

    private func pending(requestedBy: String) -> Friendship {
        Friendship(
            uidA: "aaa111",
            uidB: "bbb222",
            requestedBy: requestedBy,
            status: .pending,
            createdAt: nil,
            updatedAt: nil
        )
    }
}
