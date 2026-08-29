import FirebaseFirestore
import XCTest
@testable import hoopr

/// Guards the contract between `Squad`/`SquadInvite` and the documents actually
/// stored in `squads` and `squadInvites`, and covers every pure helper the
/// create sheet and the rules both lean on.
///
/// The decoding half runs through `Firestore.Decoder` — the same decoder
/// `SquadService` uses — so a field rename in the console or in the model
/// breaks a test here rather than silently emptying the Seasons tab.
final class SquadTests: XCTestCase {

    private let decoder = Firestore.Decoder()

    // MARK: - Fixtures

    /// A stored `squads` document with every field populated. Written out
    /// longhand rather than encoded from the model, because the point is to
    /// pin the *wire* shape, not to prove `Codable` round-trips.
    private func squadDocument(
        overrides: [String: Any] = [:],
        removing keys: [String] = []
    ) -> [String: Any] {
        var document: [String: Any] = [
            "id": "sq_1",
            "name": "Rim Reapers",
            "nameLower": "rim reapers",
            "leaderId": "leader_1",
            "memberIds": ["leader_1", "member_2"],
            "format": "3v3",
            "iconKey": "flame.fill",
            "colorKey": "orange",
            "region": "Durham",
            "createdAt": Timestamp(date: Date(timeIntervalSince1970: 1_780_000_000)),
            "updatedAt": Timestamp(date: Date(timeIntervalSince1970: 1_780_000_015)),
        ]
        for key in keys { document.removeValue(forKey: key) }
        for (key, value) in overrides { document[key] = value }
        return document
    }

    private func squad(
        id: String = "sq_1",
        leaderId: String = "leader_1",
        memberIds: [String] = ["leader_1"],
        format: SquadFormat = .threeVThree
    ) -> Squad {
        Squad(
            id: id,
            name: "Rim Reapers",
            nameLower: "rim reapers",
            leaderId: leaderId,
            memberIds: memberIds,
            format: format,
            iconKey: Squad.defaultIconKey,
            colorKey: Squad.defaultColorKey,
            region: "Durham",
            createdAt: nil,
            updatedAt: nil
        )
    }

    // MARK: - Decoding

    func testDecodesStoredDocumentShape() throws {
        let decoded = try decoder.decode(Squad.self, from: squadDocument())

        XCTAssertEqual(decoded.id, "sq_1")
        XCTAssertEqual(decoded.name, "Rim Reapers")
        XCTAssertEqual(decoded.nameLower, "rim reapers")
        XCTAssertEqual(decoded.leaderId, "leader_1")
        XCTAssertEqual(decoded.memberIds, ["leader_1", "member_2"])
        XCTAssertEqual(decoded.format, .threeVThree)
        XCTAssertEqual(decoded.iconKey, "flame.fill")
        XCTAssertEqual(decoded.colorKey, "orange")
        XCTAssertEqual(decoded.region, "Durham")
        XCTAssertEqual(decoded.createdAt, Date(timeIntervalSince1970: 1_780_000_000))
        XCTAssertEqual(decoded.updatedAt, Date(timeIntervalSince1970: 1_780_000_015))
    }

    /// Server timestamps are write-only sentinels; a document read back before
    /// the server resolves them carries nulls, which must not crash decoding.
    /// This is the *normal* case for the leader who just created the squad —
    /// Firestore delivers their own write's snapshot before the server stamps
    /// it.
    func testDecodesPendingServerTimestamps() throws {
        let decoded = try decoder.decode(
            Squad.self,
            from: squadDocument(overrides: ["createdAt": NSNull(), "updatedAt": NSNull()])
        )

        XCTAssertNil(decoded.createdAt)
        XCTAssertNil(decoded.updatedAt)
    }

    /// The one the plan is explicit about: a document without `memberIds` must
    /// **fail** rather than default to `[]`. A silent default would render a
    /// squad with nobody on it, and would size the roster ceiling against a
    /// roster that isn't the stored one.
    func testMissingMemberIdsFailsToDecode() {
        XCTAssertThrowsError(
            try decoder.decode(Squad.self, from: squadDocument(removing: ["memberIds"]))
        )
    }

    /// Every other required field earns the same treatment — a missing one is a
    /// drifted document, and `SquadService.decoded` skips it rather than
    /// letting it into a list half-formed.
    func testEveryRequiredFieldIsRequired() {
        for key in ["id", "name", "nameLower", "leaderId", "format", "iconKey", "colorKey", "region"] {
            XCTAssertThrowsError(
                try decoder.decode(Squad.self, from: squadDocument(removing: [key])),
                "A document without `\(key)` decoded anyway — it should have failed."
            )
        }
    }

    /// A format the model doesn't declare must fail loudly rather than decode
    /// into something arbitrary: the rules only ever store what's allowlisted,
    /// so a fourth value means the document was hand-edited.
    func testDecodesOnlyTheDeclaredFormats() {
        XCTAssertThrowsError(
            try decoder.decode(Squad.self, from: squadDocument(overrides: ["format": "7v7"]))
        )
    }

    /// Formats the schema carries but the rules don't allow yet still decode —
    /// they're declared cases. That's what makes enabling 5v5 an allowlist
    /// entry rather than a migration.
    func testDeclaredButUnavailableFormatStillDecodes() throws {
        let decoded = try decoder.decode(
            Squad.self,
            from: squadDocument(overrides: ["format": "5v5", "memberIds": ["leader_1"]])
        )

        XCTAssertEqual(decoded.format, .fiveVFive)
        XCTAssertFalse(decoded.format.isAvailable)
    }

    func testDecodesStoredInviteShape() throws {
        let created = Timestamp(date: Date(timeIntervalSince1970: 1_780_000_000))
        let document: [String: Any] = [
            "squadId": "sq_1",
            "uid": "invitee_9",
            "invitedBy": "leader_1",
            "createdAt": created,
        ]

        let invite = try decoder.decode(SquadInvite.self, from: document)

        XCTAssertEqual(invite.squadId, "sq_1")
        XCTAssertEqual(invite.uid, "invitee_9")
        XCTAssertEqual(invite.invitedBy, "leader_1")
        XCTAssertEqual(invite.createdAt, created.dateValue())
        XCTAssertEqual(invite.id, "sq_1_invitee_9")
    }

    /// `invitedBy` is what the read and delete rules use to recognize the
    /// sending side, so its absence has to be a decode failure rather than a
    /// row nobody can revoke.
    func testMissingInvitedByFailsToDecode() {
        let document: [String: Any] = [
            "squadId": "sq_1",
            "uid": "invitee_9",
        ]

        XCTAssertThrowsError(try decoder.decode(SquadInvite.self, from: document))
    }

    // MARK: - Invite identity

    /// The ID is derived from the pair, in role order. Unlike
    /// `Friendship.id(for:_:)` this must *not* sort — the create rule
    /// recomputes `squadId + '_' + uid` and refuses anything else.
    func testInviteIdIsOrderedByRoleNotLexicographically() {
        XCTAssertEqual(SquadInvite.id(for: "zzz", "aaa"), "zzz_aaa")
        XCTAssertEqual(SquadInvite.id(for: "aaa", "zzz"), "aaa_zzz")
    }

    func testInviteIdMatchesTheDerivedProperty() {
        let invite = SquadInvite(
            squadId: "sq_1", uid: "u_2", invitedBy: "leader_1", createdAt: nil
        )

        XCTAssertEqual(invite.id, SquadInvite.id(for: invite.squadId, invite.uid))
    }

    // MARK: - Name validation

    func testNameBoundsAreInclusive() {
        let shortest = String(repeating: "a", count: Squad.nameLengthRange.lowerBound)
        let longest = String(repeating: "a", count: Squad.nameLengthRange.upperBound)

        XCTAssertNil(Squad.validate(name: shortest))
        XCTAssertNil(Squad.validate(name: longest))
    }

    func testNameOutsideTheBoundsIsRejected() {
        let tooShort = String(repeating: "a", count: Squad.nameLengthRange.lowerBound - 1)
        let tooLong = String(repeating: "a", count: Squad.nameLengthRange.upperBound + 1)

        XCTAssertEqual(Squad.validate(name: tooShort), .nameTooShort)
        XCTAssertEqual(Squad.validate(name: tooLong), .nameTooLong)
    }

    /// Validation and storage have to agree on what the name *is*, or a name
    /// that passes the client is rejected by the server as too long.
    func testNameIsMeasuredAfterTrimming() {
        XCTAssertEqual(Squad.validate(name: "   ab   "), .nameTooShort)
        XCTAssertNil(Squad.validate(name: "  Rim Reapers  "))
        XCTAssertEqual(Squad.normalizedName("  Rim Reapers  "), "Rim Reapers")
    }

    func testEmptyNameIsTooShortRatherThanUnknown() {
        XCTAssertEqual(Squad.validate(name: ""), .nameTooShort)
        XCTAssertEqual(Squad.validate(name: "      "), .nameTooShort)
    }

    /// `nameLower` is the search key, and it's built the same way
    /// `UserProfile.searchKey` builds its own — one convention, two
    /// collections.
    func testSearchKeyTrimsAndLowercases() {
        XCTAssertEqual(Squad.searchKey("  Rim REAPERS "), "rim reapers")
        XCTAssertEqual(Squad.searchKey("Rim Reapers"), UserProfile.searchKey("Rim Reapers"))
    }

    // MARK: - Full validation

    func testValidSquadPassesEveryCheck() {
        XCTAssertNil(
            Squad.validate(
                name: "Rim Reapers",
                format: .threeVThree,
                iconKey: Squad.defaultIconKey,
                colorKey: Squad.defaultColorKey,
                region: "Durham"
            )
        )
    }

    /// Each failure in isolation, so a reordering of the guards can't hide one
    /// behind another.
    func testEachInvalidFieldIsReportedOnItsOwn() {
        XCTAssertEqual(
            Squad.validate(
                name: "no", format: .threeVThree,
                iconKey: Squad.defaultIconKey, colorKey: Squad.defaultColorKey, region: "Durham"
            ),
            .nameTooShort
        )
        XCTAssertEqual(
            Squad.validate(
                name: "Rim Reapers", format: .fiveVFive,
                iconKey: Squad.defaultIconKey, colorKey: Squad.defaultColorKey, region: "Durham"
            ),
            .unsupportedFormat
        )
        XCTAssertEqual(
            Squad.validate(
                name: "Rim Reapers", format: .threeVThree,
                iconKey: "skull.fill", colorKey: Squad.defaultColorKey, region: "Durham"
            ),
            .unknownIcon
        )
        XCTAssertEqual(
            Squad.validate(
                name: "Rim Reapers", format: .threeVThree,
                iconKey: Squad.defaultIconKey, colorKey: "chartreuse", region: "Durham"
            ),
            .unknownColor
        )
        XCTAssertEqual(
            Squad.validate(
                name: "Rim Reapers", format: .threeVThree,
                iconKey: Squad.defaultIconKey, colorKey: Squad.defaultColorKey, region: "   "
            ),
            .missingRegion
        )
    }

    /// A region is never defaulted. A wrong one silently partitions the
    /// matchmaking pool into groups that can never see each other — a failure
    /// with no error message, which is the worst kind.
    func testEmptyRegionIsRejectedRatherThanDefaulted() {
        XCTAssertEqual(
            Squad.validate(
                name: "Rim Reapers", format: .threeVThree,
                iconKey: Squad.defaultIconKey, colorKey: Squad.defaultColorKey, region: ""
            ),
            .missingRegion
        )
    }

    // MARK: - Allowlists

    func testDefaultsAreThemselvesAllowed() {
        XCTAssertTrue(Squad.iconKeys.contains(Squad.defaultIconKey))
        XCTAssertTrue(Squad.colorKeys.contains(Squad.defaultColorKey))
    }

    /// A duplicate would render two identical cells in the picker grid and, in
    /// the rules, silently widen nothing — harmless but wrong, and the kind of
    /// thing a hand-maintained list grows.
    func testAllowlistsHaveNoDuplicates() {
        XCTAssertEqual(Set(Squad.iconKeys).count, Squad.iconKeys.count)
        XCTAssertEqual(Set(Squad.colorKeys).count, Squad.colorKeys.count)
    }

    func testAllowlistsAreNotEmpty() {
        XCTAssertFalse(Squad.iconKeys.isEmpty)
        XCTAssertFalse(Squad.colorKeys.isEmpty)
    }

    // MARK: - Format

    func testRosterCeilingIsASidePlusSubstitutes() {
        XCTAssertEqual(SquadFormat.oneVOne.maxRoster, 2)
        XCTAssertEqual(SquadFormat.threeVThree.maxRoster, 6)
        XCTAssertEqual(SquadFormat.fiveVFive.maxRoster, 10)
    }

    func testOnlyThreeOnThreeIsPlayableToday() {
        XCTAssertEqual(SquadFormat.available, [.threeVThree])
        XCTAssertTrue(SquadFormat.threeVThree.isAvailable)
        XCTAssertFalse(SquadFormat.oneVOne.isAvailable)
        XCTAssertFalse(SquadFormat.fiveVFive.isAvailable)
    }

    /// Every declared format is a real allowlist candidate: the raw value is
    /// what the rules compare against, so a typo here is a `permission-denied`
    /// nobody can explain.
    func testFormatRawValuesAreTheWireStrings() {
        XCTAssertEqual(SquadFormat.allCases.map(\.rawValue), ["1v1", "3v3", "5v5"])
    }

    // MARK: - Roster helpers

    func testIsFullTracksTheFormatCeiling() {
        let roster = (1...6).map { "u\($0)" }

        XCTAssertFalse(squad(memberIds: Array(roster.prefix(5))).isFull)
        XCTAssertTrue(squad(memberIds: roster).isFull)
    }

    func testOpenSlotsNeverGoNegative() {
        // A hand-edited document could over-fill the roster; the UI still has
        // to render a number.
        let overFull = squad(memberIds: (1...9).map { "u\($0)" })

        XCTAssertEqual(overFull.openSlots, 0)
        XCTAssertTrue(overFull.isFull)
    }

    func testOpenSlotsCountsDownFromTheCeiling() {
        XCTAssertEqual(squad(memberIds: ["leader_1"]).openSlots, 5)
        XCTAssertEqual(squad(memberIds: ["leader_1", "b", "c"]).openSlots, 3)
    }

    func testRosterTextReadsAgainstTheFormatCeiling() {
        XCTAssertEqual(squad(memberIds: ["leader_1", "b"]).rosterText, "2 / 6 players")
    }

    func testLeadershipAndMembership() {
        let team = squad(memberIds: ["leader_1", "member_2"])

        XCTAssertTrue(team.isLeader("leader_1"))
        XCTAssertFalse(team.isLeader("member_2"))
        XCTAssertTrue(team.hasMember("member_2"))
        XCTAssertFalse(team.hasMember("stranger"))
    }

    /// A signed-out caller has no uid, and `nil` must read as "not you" rather
    /// than crashing or matching — the same shape `Game.isHost` uses.
    func testNilUserIsNeitherLeaderNorMember() {
        let team = squad(memberIds: ["leader_1", "member_2"])

        XCTAssertFalse(team.isLeader(nil))
        XCTAssertFalse(team.hasMember(nil))
        XCTAssertFalse(team.canLeave(nil))
    }

    /// The leader's exit is disbanding, not leaving — the self-leave rule
    /// refuses them server-side, and the client has to agree or the button
    /// produces a `permission-denied` nobody can act on.
    func testLeaderCannotLeaveButMembersCan() {
        let team = squad(memberIds: ["leader_1", "member_2"])

        XCTAssertFalse(team.canLeave("leader_1"))
        XCTAssertTrue(team.canLeave("member_2"))
        XCTAssertFalse(team.canLeave("stranger"))
    }
}
