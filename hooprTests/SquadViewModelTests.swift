import CoreLocation
import XCTest
@testable import hoopr

/// Covers the three decisions the Seasons tab makes that aren't a matter of
/// layout: who's left to invite, what order a roster reads in, and which
/// matchmaking pool a new squad lands in.
///
/// All three are `nonisolated static` on `SquadViewModel` precisely so they can
/// be exercised here — none needs Firebase, a main actor, or a live service,
/// and they're the parts most likely to break silently. A bad invite join shows
/// up as a friend who can't be added, not as a crash; a bad region shows up as
/// a squad that never matches anyone, with no error anywhere.
final class SquadViewModelTests: XCTestCase {

    // MARK: - Fixtures

    private let ownUid = "me"

    private func squad(
        id: String = "sq_1",
        leaderId: String = "me",
        memberIds: [String] = ["me"],
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

    /// An accepted friendship between `ownUid` and `other`, with the pair in
    /// the lexicographic order the document actually stores.
    private func friendship(
        with other: String,
        status: Friendship.Status = .accepted
    ) -> Friendship {
        let pair = [ownUid, other].sorted()
        return Friendship(
            uidA: pair[0],
            uidB: pair[1],
            requestedBy: ownUid,
            status: status,
            createdAt: nil,
            updatedAt: nil
        )
    }

    private func invite(_ uid: String, to squadId: String = "sq_1") -> SquadInvite {
        SquadInvite(squadId: squadId, uid: uid, invitedBy: ownUid, createdAt: nil)
    }

    private func profile(_ uid: String, named name: String) -> UserProfile {
        UserProfile(
            id: uid,
            userName: name,
            userNameLower: UserProfile.searchKey(name),
            homeCourtId: nil,
            preferredRadius: nil,
            favoriteCourtIds: nil,
            createdAt: nil,
            updatedAt: nil,
            completedGameCount: nil,
            participationStreak: nil,
            lastCompletedAt: nil
        )
    }

    private func court(
        id: String,
        city: String,
        latitude: Double,
        longitude: Double
    ) -> Court {
        Court(
            id: id,
            name: "\(city) Basketball Court",
            latitude: latitude,
            longitude: longitude,
            address: "1 Main St",
            city: city,
            hoops: 2,
            surface: "asphalt",
            isLit: nil,
            isCovered: nil,
            access: .public,
            osmType: nil,
            osmId: nil
        )
    }

    // MARK: - The invite picker

    /// **The join this class exists for.** Three friends, one of them already
    /// on the squad, offers exactly two — and the signed-in user, who is always
    /// their own squad's leader, is never among them.
    func testOffersFriendsWhoAreNotAlreadyOnTheSquad() {
        let team = squad(memberIds: ["me", "b"])
        let friends = [friendship(with: "a"), friendship(with: "b"), friendship(with: "c")]

        let invitable = SquadViewModel.invitableUids(
            friends: friends, squad: team, alreadyInvited: [], viewedBy: ownUid
        )

        XCTAssertEqual(Set(invitable), ["a", "c"])
        XCTAssertEqual(invitable.count, 2)
        XCTAssertFalse(invitable.contains(ownUid))
    }

    /// Someone already asked isn't offered again. The invite document ID is
    /// derived from the pair, so a second invite writes the same document and
    /// the rules refuse it — offering the button would be a dead end.
    func testExcludesPeopleWhoAlreadyHaveAnInvite() {
        let team = squad(memberIds: ["me"])
        let friends = [friendship(with: "a"), friendship(with: "b")]

        let invitable = SquadViewModel.invitableUids(
            friends: friends, squad: team, alreadyInvited: [invite("a")], viewedBy: ownUid
        )

        XCTAssertEqual(invitable, ["b"])
    }

    /// Invites are scoped to their own squad. An outstanding invite to *another*
    /// squad says nothing about this one, and filtering on it would quietly
    /// shrink the picker as a leader ran more than one team.
    func testAnInviteToAnotherSquadDoesNotExcludeAnyone() {
        let team = squad(id: "sq_1", memberIds: ["me"])
        let friends = [friendship(with: "a")]

        let invitable = SquadViewModel.invitableUids(
            friends: friends,
            squad: team,
            alreadyInvited: [invite("a", to: "sq_2")],
            viewedBy: ownUid
        )

        XCTAssertEqual(invitable, ["a"])
    }

    /// A pending friend request isn't a friendship. The rules require an
    /// *accepted* edge before an invite can be created, so offering one here
    /// would produce a refused write.
    func testOnlyAcceptedFriendshipsAreInvitable() {
        let team = squad(memberIds: ["me"])
        let friends = [
            friendship(with: "a", status: .pending),
            friendship(with: "b", status: .accepted),
        ]

        let invitable = SquadViewModel.invitableUids(
            friends: friends, squad: team, alreadyInvited: [], viewedBy: ownUid
        )

        XCTAssertEqual(invitable, ["b"])
    }

    /// `FriendService` merges two half-streams, and while no document satisfies
    /// both, a duplicate reaching this join must not render the same person
    /// twice.
    func testDuplicateFriendshipsCollapse() {
        let team = squad(memberIds: ["me"])
        let friends = [friendship(with: "a"), friendship(with: "a")]

        XCTAssertEqual(
            SquadViewModel.invitableUids(
                friends: friends, squad: team, alreadyInvited: [], viewedBy: ownUid
            ),
            ["a"]
        )
    }

    func testNoFriendsMeansNobodyToInvite() {
        XCTAssertTrue(
            SquadViewModel.invitableUids(
                friends: [], squad: squad(), alreadyInvited: [], viewedBy: ownUid
            ).isEmpty
        )
    }

    /// A full squad still computes a list — fullness is the *screen's* answer,
    /// not this function's. Keeping the two separate is what lets the card say
    /// "roster full" instead of the ambiguous "nobody to invite".
    func testFullnessIsNotThisFunctionsConcern() {
        let full = squad(memberIds: ["me", "b", "c", "d", "e", "f"])

        XCTAssertTrue(full.isFull)
        XCTAssertEqual(
            SquadViewModel.invitableUids(
                friends: [friendship(with: "z")], squad: full, alreadyInvited: [], viewedBy: ownUid
            ),
            ["z"]
        )
    }

    // MARK: - Roster order

    /// The leader is always first, then everyone else alphabetically. `memberIds`
    /// is stored in join order, which is arbitrary — without this the roster
    /// would reshuffle itself every time somebody joined or left.
    func testRosterPutsTheLeaderFirstThenSortsByName() {
        let team = squad(leaderId: "leader", memberIds: ["zoe", "leader", "adam"])
        let profiles = [
            "leader": profile("leader", named: "Morgan"),
            "zoe": profile("zoe", named: "Zoe"),
            "adam": profile("adam", named: "Adam"),
        ]

        let rows = SquadViewModel.memberRows(for: team, profiles: profiles)

        XCTAssertEqual(rows.map(\.uid), ["leader", "adam", "zoe"])
        XCTAssertTrue(rows[0].isLeader)
        XCTAssertFalse(rows[1].isLeader)
    }

    /// A row whose profile hasn't landed sorts to the end rather than to the
    /// top under an empty name — otherwise the roster visibly reorders itself
    /// as each lookup resolves.
    func testUnresolvedMembersSortToTheEnd() {
        let team = squad(leaderId: "leader", memberIds: ["leader", "mystery", "adam"])
        let profiles = [
            "leader": profile("leader", named: "Morgan"),
            "adam": profile("adam", named: "Adam"),
        ]

        let rows = SquadViewModel.memberRows(for: team, profiles: profiles)

        XCTAssertEqual(rows.map(\.uid), ["leader", "adam", "mystery"])
        XCTAssertFalse(rows.last?.isResolved ?? true)
    }

    /// Sorting is case-insensitive: "adam" and "Adam" are the same name, and a
    /// case-sensitive comparison would file every lowercase name after every
    /// uppercase one.
    func testNameSortIgnoresCase() {
        let team = squad(leaderId: "leader", memberIds: ["leader", "b", "a"])
        let profiles = [
            "leader": profile("leader", named: "Morgan"),
            "b": profile("b", named: "bea"),
            "a": profile("a", named: "Casey"),
        ]

        XCTAssertEqual(
            SquadViewModel.memberRows(for: team, profiles: profiles).map(\.uid),
            ["leader", "b", "a"]
        )
    }

    func testALeaderAloneIsTheWholeRoster() {
        let rows = SquadViewModel.memberRows(for: squad(memberIds: ["me"]), profiles: [:])

        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].isLeader)
    }

    // MARK: - Region

    private let durham = CLLocationCoordinate2D(latitude: 35.9940, longitude: -78.8986)

    func testRegionIsTheNearestCourtsCity() {
        let courts = [
            court(id: "far", city: "Raleigh", latitude: 35.7796, longitude: -78.6382),
            court(id: "near", city: "Durham", latitude: 35.9950, longitude: -78.8990),
        ]

        XCTAssertEqual(SquadViewModel.region(near: durham, in: courts), "Durham")
    }

    /// Order in the dataset must not decide the answer — the courts are sorted
    /// by name when they're loaded, which has nothing to do with distance.
    func testNearestWinsRegardlessOfDatasetOrder() {
        let near = court(id: "near", city: "Durham", latitude: 35.9950, longitude: -78.8990)
        let far = court(id: "far", city: "Raleigh", latitude: 35.7796, longitude: -78.6382)

        XCTAssertEqual(SquadViewModel.region(near: durham, in: [near, far]), "Durham")
        XCTAssertEqual(SquadViewModel.region(near: durham, in: [far, near]), "Durham")
    }

    /// **No fallback, ever.** A guessed region partitions the matchmaking pool
    /// into groups that can never see each other, and nothing anywhere reports
    /// it — so an empty dataset has to produce `nil` and stop a squad from
    /// being created.
    func testNoCourtsMeansNoRegion() {
        XCTAssertNil(SquadViewModel.region(near: durham, in: []))
    }

    /// The same reasoning for a court whose `city` is blank. The dataset has no
    /// such row today — the Phase 0 gate confirmed all 214 carry a city — but a
    /// regenerated dataset could, and it must fail closed.
    func testABlankCityIsNoRegionRatherThanAnEmptyOne() {
        let blank = court(id: "blank", city: "   ", latitude: 35.9950, longitude: -78.8990)

        XCTAssertNil(SquadViewModel.region(near: durham, in: [blank]))
    }

    func testRegionIsTrimmed() {
        let padded = court(id: "padded", city: "  Durham  ", latitude: 35.9950, longitude: -78.8990)

        XCTAssertEqual(SquadViewModel.region(near: durham, in: [padded]), "Durham")
    }

    /// The real dataset, not a fixture: every court in the bundle has to name a
    /// usable region, because `Court.city` *is* the pool key. This is the Phase
    /// 0 gate, kept as a test so regenerating `courts.json` can't quietly
    /// reopen it.
    func testEveryBundledCourtNamesAUsableRegion() throws {
        let courts = CourtService().courts
        try XCTSkipIf(courts.isEmpty, "Court dataset didn't load in the test bundle.")

        let blank = courts.filter {
            $0.city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        XCTAssertTrue(
            blank.isEmpty,
            "\(blank.count) court(s) have no city, so squads created near them would have no matchmaking pool: \(blank.prefix(3).map(\.id))"
        )

        // Casing has to be consistent too: `region` is compared with `==` in
        // the pool query, so "durham" and "Durham" are two pools that can never
        // see each other.
        let cities = Set(courts.map(\.city))
        let caseInsensitive = Set(cities.map { $0.lowercased() })
        XCTAssertEqual(
            cities.count, caseInsensitive.count,
            "Two courts spell the same city differently, which would split one matchmaking pool in two: \(cities.sorted())"
        )
    }
}
