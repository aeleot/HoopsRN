import XCTest
@testable import hoopr

/// Covers the three decisions the Friends tab makes that aren't a matter of
/// layout: whether typed text is worth trying as a user ID, how the two search
/// streams merge, and where the signed-in user stands with someone.
///
/// All three are `nonisolated static` on `FriendsViewModel` precisely so they
/// can be exercised here — none of them needs Firebase, a main actor, or a live
/// service, and they're the parts most likely to break silently (a bad merge
/// shows up as a missing search result, not as a crash).
final class FriendsViewModelTests: XCTestCase {

    // MARK: - looksLikeUserId

    /// The real shape: Firebase uids are 28-character ASCII alphanumeric
    /// strings. This is the case that has to work, because it's the one the
    /// "copy your user ID" affordance on the profile screen produces.
    func testRecognizesAFirebaseShapedUserId() {
        XCTAssertTrue(FriendsViewModel.looksLikeUserId("A1b2C3d4E5f6G7h8I9j0K1l2M3n4"))
    }

    /// Surrounding whitespace comes free with a paste, and must not stop the ID
    /// path from running.
    func testTrimsWhitespaceBeforeJudging() {
        XCTAssertTrue(FriendsViewModel.looksLikeUserId("  A1b2C3d4E5f6G7h8I9j0K1l2M3n4\n"))
    }

    /// Display names are short. Treating one as an ID would cost a pointless
    /// document read on every keystroke.
    func testRejectsOrdinaryNames() {
        XCTAssertFalse(FriendsViewModel.looksLikeUserId("jordan"))
        XCTAssertFalse(FriendsViewModel.looksLikeUserId(""))
        XCTAssertFalse(FriendsViewModel.looksLikeUserId("   "))
    }

    /// Long enough to pass the length test, but not an ID: a uid has no spaces,
    /// no punctuation, and no non-ASCII letters.
    func testRejectsLongTextThatIsntAlphanumeric() {
        XCTAssertFalse(FriendsViewModel.looksLikeUserId("Jordan Ellis From The Park"))
        XCTAssertFalse(FriendsViewModel.looksLikeUserId("A1b2C3d4-E5f6-G7h8-I9j0K1l2M"))
        XCTAssertFalse(FriendsViewModel.looksLikeUserId("A1b2C3d4_E5f6_G7h8_I9j0K1l2M"))
        XCTAssertFalse(FriendsViewModel.looksLikeUserId("ünïcödeünïcödeünïcödeünïcöde"))
    }

    /// A string long enough to look like an ID but pasted from something else
    /// entirely still only costs one read — the point of the loose upper bound
    /// is that a false positive is cheap. Past it, nothing is tried.
    func testRejectsAbsurdlyLongText() {
        XCTAssertFalse(FriendsViewModel.looksLikeUserId(String(repeating: "a", count: 500)))
    }

    // MARK: - merged

    /// An exact ID match is the only unambiguous answer on the screen, so it
    /// ranks above every name match.
    func testExactMatchRanksFirst() {
        let merged = FriendsViewModel.merged(
            exact: profile(id: "exact", name: "Zoe"),
            byName: [profile(id: "name1", name: "Alice")],
            excluding: nil,
            limit: 20
        )

        XCTAssertEqual(merged.map(\.id), ["exact", "name1"])
    }

    /// The same person can satisfy both queries — searching a uid that also
    /// happens to prefix-match a name. They must appear once.
    func testCollapsesTheSamePersonFoundTwice() {
        let duplicate = profile(id: "same", name: "Sam")

        let merged = FriendsViewModel.merged(
            exact: duplicate,
            byName: [duplicate, profile(id: "other", name: "Sammy")],
            excluding: nil,
            limit: 20
        )

        XCTAssertEqual(merged.map(\.id), ["same", "other"])
    }

    /// You can't friend yourself — `FriendService.sendRequest` rejects it, and
    /// the rules reject it — so offering the row at all is a dead end.
    func testDropsTheSignedInUser() {
        let merged = FriendsViewModel.merged(
            exact: nil,
            byName: [profile(id: "me", name: "Me"), profile(id: "them", name: "Them")],
            excluding: "me",
            limit: 20
        )

        XCTAssertEqual(merged.map(\.id), ["them"])
    }

    /// Excluding yourself must not consume one of the result slots — a limit of
    /// two should still return two other people.
    func testExclusionDoesNotEatAResultSlot() {
        let merged = FriendsViewModel.merged(
            exact: nil,
            byName: [
                profile(id: "me", name: "Me"),
                profile(id: "a", name: "A"),
                profile(id: "b", name: "B"),
            ],
            excluding: "me",
            limit: 2
        )

        XCTAssertEqual(merged.map(\.id), ["a", "b"])
    }

    func testHonorsTheLimit() {
        let many = (0..<50).map { profile(id: "u\($0)", name: "User \($0)") }

        XCTAssertEqual(
            FriendsViewModel.merged(exact: nil, byName: many, excluding: nil, limit: 20).count,
            20
        )
    }

    func testEmptyInputProducesNoResults() {
        XCTAssertTrue(
            FriendsViewModel.merged(exact: nil, byName: [], excluding: nil, limit: 20).isEmpty
        )
    }

    // MARK: - relationship

    func testNoEdgeIsNoRelationship() {
        XCTAssertEqual(
            FriendsViewModel.relationship(with: "them", in: [:], viewedBy: "me"),
            FriendsViewModel.Relationship.none
        )
    }

    func testOwnUidIsYou() {
        XCTAssertEqual(
            FriendsViewModel.relationship(with: "me", in: [:], viewedBy: "me"),
            FriendsViewModel.Relationship.you
        )
    }

    /// Direction is read off `requestedBy`, never off which side of the pair you
    /// happen to be — the pair order is lexicographic and arbitrary. So both
    /// sides of the same document are checked, mirroring how `FriendshipTests`
    /// covers `Friendship.direction(for:)`.
    func testPendingRequestIsOutgoingForTheAskerAndIncomingForTheOther() {
        let edge = friendship(requestedBy: "aaa", status: .pending)

        XCTAssertEqual(
            FriendsViewModel.relationship(with: "bbb", in: ["bbb": edge], viewedBy: "aaa"),
            .outgoing
        )
        XCTAssertEqual(
            FriendsViewModel.relationship(with: "aaa", in: ["aaa": edge], viewedBy: "bbb"),
            .incoming
        )
    }

    /// The same, with the request coming from the *second* uid of the pair —
    /// which is the case a naive `uidA == me` implementation would get wrong.
    func testDirectionFollowsRequestedByNotPairOrder() {
        let edge = friendship(requestedBy: "bbb", status: .pending)

        XCTAssertEqual(
            FriendsViewModel.relationship(with: "aaa", in: ["aaa": edge], viewedBy: "bbb"),
            .outgoing
        )
        XCTAssertEqual(
            FriendsViewModel.relationship(with: "bbb", in: ["bbb": edge], viewedBy: "aaa"),
            .incoming
        )
    }

    /// Once accepted the edge stops being directional, whoever asked.
    func testAcceptedIsFriendsForBothSides() {
        for requester in ["aaa", "bbb"] {
            let edge = friendship(requestedBy: requester, status: .accepted)

            XCTAssertEqual(
                FriendsViewModel.relationship(with: "bbb", in: ["bbb": edge], viewedBy: "aaa"),
                .friends
            )
            XCTAssertEqual(
                FriendsViewModel.relationship(with: "aaa", in: ["aaa": edge], viewedBy: "bbb"),
                .friends
            )
        }
    }

    // MARK: - recentlyAccepted

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// The inbox's "accepted your request" card is for requests *you* sent:
    /// accepting someone else's request isn't news to you.
    func testOnlyRequestsYouSentCountAsAccepted() {
        let mine = acceptedEdge(uidB: "bbb", requestedBy: "aaa", acceptedAgo: 60)
        let theirs = acceptedEdge(uidB: "ccc", requestedBy: "ccc", acceptedAgo: 60)

        let result = FriendsViewModel.recentlyAccepted([mine, theirs], by: "aaa", dismissed: [], now: now)

        XCTAssertEqual(result.map(\.id), [mine.id])
    }

    /// A week, then it ages out on its own — the inbox isn't a friends list.
    func testAcceptancesAgeOutAfterTheWindow() {
        let fresh = acceptedEdge(uidB: "bbb", requestedBy: "aaa", acceptedAgo: FriendsViewModel.acceptanceWindow - 60)
        let stale = acceptedEdge(uidB: "ccc", requestedBy: "aaa", acceptedAgo: FriendsViewModel.acceptanceWindow + 60)

        let result = FriendsViewModel.recentlyAccepted([fresh, stale], by: "aaa", dismissed: [], now: now)

        XCTAssertEqual(result.map(\.id), [fresh.id])
    }

    func testDismissedAcceptancesStayGone() {
        let edge = acceptedEdge(uidB: "bbb", requestedBy: "aaa", acceptedAgo: 60)

        let result = FriendsViewModel.recentlyAccepted([edge], by: "aaa", dismissed: [edge.id], now: now)

        XCTAssertTrue(result.isEmpty)
    }

    /// Newest first; an unacknowledged write (`nil`) is the newest of all.
    func testAcceptancesAreNewestFirst() {
        let older = acceptedEdge(uidB: "bbb", requestedBy: "aaa", acceptedAgo: 3_600)
        let newer = acceptedEdge(uidB: "ccc", requestedBy: "aaa", acceptedAgo: 60)
        let pendingWrite = Friendship(
            uidA: "aaa", uidB: "ddd", requestedBy: "aaa", status: .accepted,
            createdAt: nil, updatedAt: nil
        )

        let result = FriendsViewModel.recentlyAccepted(
            [older, pendingWrite, newer], by: "aaa", dismissed: [], now: now
        )

        XCTAssertEqual(result.map(\.id), [pendingWrite.id, newer.id, older.id])
    }

    func testDismissalsPersistNewestFirstAndCapped() {
        let suite = "InboxDismissalsStoreTests"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = InboxDismissalsStore(defaults: defaults)

        for index in 0...InboxDismissalsStore.maxEntries {
            store.record("edge\(index)")
        }

        XCTAssertEqual(store.keys.count, InboxDismissalsStore.maxEntries)
        XCTAssertTrue(store.keys.contains("edge\(InboxDismissalsStore.maxEntries)"))
        XCTAssertFalse(store.keys.contains("edge0"))
    }

    private func acceptedEdge(uidB: String, requestedBy: String, acceptedAgo: TimeInterval) -> Friendship {
        Friendship(
            uidA: "aaa",
            uidB: uidB,
            requestedBy: requestedBy,
            status: .accepted,
            createdAt: now.addingTimeInterval(-acceptedAgo - 60),
            updatedAt: now.addingTimeInterval(-acceptedAgo)
        )
    }

    // MARK: - Fixtures

    private func profile(id: String, name: String) -> UserProfile {
        UserProfile(
            id: id,
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

    private func friendship(
        requestedBy: String,
        status: Friendship.Status
    ) -> Friendship {
        Friendship(
            uidA: "aaa",
            uidB: "bbb",
            requestedBy: requestedBy,
            status: status,
            createdAt: nil,
            updatedAt: nil
        )
    }
}
