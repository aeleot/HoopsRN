import FirebaseFirestore
import XCTest
@testable import hoopr

/// The safety tooling App Review Guideline 1.2 asks for — the name filter,
/// reports and blocks — at the level that needs no Firebase: what a name is
/// refused for, what a report must look like before it is sent, and what
/// blocking someone has to clear up.
///
/// Whether the *server* refuses a blocked sender is
/// `firestore-tests/blocks.test.mjs`; this file can't see that and doesn't try.
final class SafetyTests: XCTestCase {

    // MARK: - NameFilter

    private let filter = NameFilter(terms: ["darn", "heck", "kkk"])

    func testAListedWordIsRefusedWhateverItsCase() {
        XCTAssertFalse(filter.isAllowed("darn"))
        XCTAssertFalse(filter.isAllowed("DARN"))
        XCTAssertFalse(filter.isAllowed("The Darn Squad"))
        XCTAssertFalse(filter.isAllowed("  heck  "))
    }

    /// The Scunthorpe problem, and the reason matching is by whole word: a
    /// filter that refuses real names gets switched off.
    func testAWordThatMerelyContainsATermIsAllowed() {
        XCTAssertTrue(filter.isAllowed("Darnell"))
        XCTAssertTrue(filter.isAllowed("Checkers"))
        XCTAssertTrue(filter.isAllowed("Heckman Hoops"))
    }

    func testPunctuationSeparatesWords() {
        XCTAssertFalse(filter.isAllowed("darn_squad"))
        XCTAssertFalse(filter.isAllowed("oh-heck!"))
        XCTAssertFalse(filter.isAllowed("@darn"))
    }

    func testAccentsAndDigitSwapsAreFoldedAway() {
        XCTAssertFalse(filter.isAllowed("dárn"))
        XCTAssertFalse(filter.isAllowed("d4rn"))
        XCTAssertFalse(filter.isAllowed("h3ck"))
    }

    func testATermSpelledOutLetterByLetterIsRefused() {
        XCTAssertFalse(filter.isAllowed("d.a.r.n"))
        XCTAssertFalse(filter.isAllowed("h e c k"))
        XCTAssertFalse(filter.isAllowed("K K K"))
    }

    /// Only runs of single letters are joined. Two ordinary words that happen
    /// to concatenate into a term are two ordinary words.
    func testOrdinaryWordsAreNotJoinedIntoATerm() {
        let joined = NameFilter(terms: ["grapes"])
        XCTAssertTrue(joined.isAllowed("Grape S Tars"))
        XCTAssertTrue(joined.isAllowed("Gra Pes"))
        XCTAssertEqual(NameFilter.spelledOutWords(from: ["a", "b", "team", "c", "d", "e"]), ["ab", "cde"])
        XCTAssertEqual(NameFilter.spelledOutWords(from: ["a", "team", "b"]), [])
    }

    func testAnEmptyListAllowsEverything() {
        XCTAssertTrue(NameFilter(terms: []).isAllowed("darn"))
    }

    func testParsingSkipsCommentsAndBlankLines() {
        let parsed = NameFilter.parse("# heading\n\ndarn\n  heck  \n# another\n")
        XCTAssertEqual(parsed, ["darn", "heck"])
    }

    /// **The one that matters.** A missing or empty resource makes the filter
    /// allow every name, silently — so the bundled list has to be shown to
    /// load, and to actually refuse something.
    func testTheBundledListLoadsAndRefusesProfanity() {
        XCTAssertGreaterThan(
            NameFilter.bundled.terms.count, 50,
            "blocked_terms.txt didn't load from the app bundle — every name is being allowed."
        )
        XCTAssertFalse(NameFilter.bundled.isAllowed("shit"))
        XCTAssertFalse(NameFilter.bundled.isAllowed("Sh1t Squad"))
    }

    /// Names the app itself produces, and names real people have.
    func testTheBundledListAllowsOrdinaryNames() {
        for name in ["Hooper 4821", "Rim Reapers", "Elliot", "Dick Vitale", "Marshawn Lynch",
                     "Scunthorpe United", "Cockburn", "Assists", "Classic Hoops", "Hancock Park"] {
            XCTAssertTrue(NameFilter.bundled.isAllowed(name), "\(name) should be allowed")
        }
    }

    // MARK: - The two validators

    func testADisplayNameWithAListedWordIsRefused() {
        XCTAssertEqual(UserProfile.validate(userName: "shit"), .userNameNotAllowed)
        XCTAssertNil(UserProfile.validate(userName: "Hooper 4821"))
    }

    func testASquadNameWithAListedWordIsRefused() {
        XCTAssertEqual(Squad.validate(name: "Shit Squad"), .nameNotAllowed)
        XCTAssertNil(Squad.validate(name: "Rim Reapers"))
    }

    /// Length is reported first: "too short" is the more useful thing to say
    /// about a two-letter name, whatever the two letters are.
    func testLengthProblemsAreReportedBeforeTheFilter() {
        XCTAssertEqual(Squad.validate(name: "kk"), .nameTooShort)
        XCTAssertEqual(UserProfile.validate(userName: ""), .emptyUserName)
    }

    func testEveryRefusalHasItsOwnSentence() {
        let userMessage = UserProfileService.message(
            for: .userNameNotAllowed, whileDoing: "saving your name", context: .write
        )
        let squadMessage = SquadService.message(
            for: .nameNotAllowed, whileDoing: "creating that squad", context: .write
        )
        XCTAssertTrue(userMessage.contains("isn't allowed"))
        XCTAssertTrue(squadMessage.contains("isn't allowed"))
    }

    // MARK: - Block

    /// Blocker first, blocked second — never sorted. The rules look a block up
    /// at `{target}_{sender}` from the sender's write, so a sorted ID would be
    /// found for half of all pairs and missed for the other half.
    func testABlockIdIsOrderedByRoleNotSorted() {
        XCTAssertEqual(Block.id(blocker: "zed", blocked: "amy"), "zed_amy")
        XCTAssertEqual(Block.id(blocker: "amy", blocked: "zed"), "amy_zed")
        XCTAssertEqual(Block(blockerId: "zed", blockedId: "amy", createdAt: nil).id, "zed_amy")
    }

    func testABlockDecodesFromItsStoredShape() throws {
        let document: [String: Any] = [
            "blockerId": "me",
            "blockedId": "them",
            "createdAt": Timestamp(date: Date(timeIntervalSince1970: 1_790_000_000)),
        ]

        let block = try Firestore.Decoder().decode(Block.self, from: document)

        XCTAssertEqual(block.blockerId, "me")
        XCTAssertEqual(block.blockedId, "them")
        XCTAssertEqual(block.createdAt, Date(timeIntervalSince1970: 1_790_000_000))
    }

    /// A local write is delivered before the server stamps it.
    func testABlockDecodesWithoutItsTimestamp() throws {
        let block = try Firestore.Decoder().decode(
            Block.self, from: ["blockerId": "me", "blockedId": "them"]
        )
        XCTAssertNil(block.createdAt)
    }

    // MARK: - BlockCleanup

    private func invite(squad: String, to uid: String, from inviter: String) -> SquadInvite {
        SquadInvite(squadId: squad, uid: uid, invitedBy: inviter, createdAt: nil)
    }

    func testBlockingDeclinesTheirInvitesAndRevokesMine() {
        let incoming = [
            invite(squad: "s1", to: "me", from: "them"),
            invite(squad: "s2", to: "me", from: "someone-else"),
        ]
        let sent = [
            invite(squad: "mine", to: "them", from: "me"),
            invite(squad: "mine", to: "a-friend", from: "me"),
        ]

        let cleanup = BlockCleanup.invites(blocking: "them", incoming: incoming, sent: sent)

        XCTAssertEqual(cleanup.toDecline, ["s1_me"])
        XCTAssertEqual(cleanup.toRevoke, ["mine_them"])
    }

    func testBlockingSomeoneWithNoInvitesTouchesNothing() {
        let cleanup = BlockCleanup.invites(
            blocking: "them",
            incoming: [invite(squad: "s2", to: "me", from: "someone-else")],
            sent: [invite(squad: "mine", to: "a-friend", from: "me")]
        )
        XCTAssertEqual(cleanup, BlockCleanup.Invites())
    }

    // MARK: - Report

    private func report(target: String = "them", details: String = "") -> Report {
        Report(targetType: .player, targetId: target, reason: .harassment, details: details)
    }

    func testAnOrdinaryReportIsValid() {
        XCTAssertNil(report().validate(reporterId: "me"))
        XCTAssertNil(report(details: "Kept asking after I declined.").validate(reporterId: "me"))
    }

    func testYouCannotReportYourselfOrNothing() {
        XCTAssertEqual(report(target: "me").validate(reporterId: "me"), .cannotTargetSelf)
        XCTAssertEqual(report(target: "").validate(reporterId: "me"), .missingTarget)
    }

    /// The rules want `details` absent, never empty.
    func testABlankNoteIsStoredAsNoNote() {
        XCTAssertNil(report(details: "").normalizedDetails)
        XCTAssertNil(report(details: "  \n ").normalizedDetails)
        XCTAssertEqual(report(details: "  rude  ").normalizedDetails, "rude")
    }

    func testTheNoteIsBoundedAtTheRulesLimit() {
        let atLimit = String(repeating: "x", count: Report.maxDetailsLength)
        XCTAssertNil(report(details: atLimit).validate(reporterId: "me"))
        XCTAssertEqual(report(details: atLimit + "x").validate(reporterId: "me"), .detailsTooLong)
    }

    /// Counted the way the rules count — by scalar. One family emoji is seven
    /// scalars and one character; counting characters would let a note through
    /// here that the server then refuses as `permission-denied`.
    func testTheNoteIsCountedInScalarsLikeTheRules() {
        let family = "👨‍👩‍👧‍👦"
        XCTAssertEqual(family.count, 1)
        let note = String(repeating: family, count: 100)
        XCTAssertGreaterThan(note.unicodeScalars.count, Report.maxDetailsLength)
        XCTAssertEqual(report(details: note).validate(reporterId: "me"), .detailsTooLong)
    }

    // MARK: - ReportViewModel

    func testAReportNeedsAReasonAndNothingElse() {
        XCTAssertFalse(ReportViewModel.canSubmit(reason: nil, details: "", isSubmitting: false))
        XCTAssertTrue(ReportViewModel.canSubmit(reason: .spam, details: "", isSubmitting: false))
        XCTAssertFalse(ReportViewModel.canSubmit(reason: .spam, details: "", isSubmitting: true))
    }

    func testAnOverlongNoteBlocksSendingAndSaysWhy() {
        let long = String(repeating: "x", count: Report.maxDetailsLength + 1)
        XCTAssertFalse(ReportViewModel.canSubmit(reason: .spam, details: long, isSubmitting: false))
        XCTAssertNotNil(ReportViewModel.detailsHint(for: long))
        XCTAssertNil(ReportViewModel.detailsHint(for: "short"))
    }

    /// Impersonation is about a person.
    func testASquadIsNotOfferedImpersonation() {
        XCTAssertEqual(ReportViewModel.reasons(for: .player), Report.Reason.allCases)
        XCTAssertFalse(ReportViewModel.reasons(for: .squad).contains(.impersonation))
        XCTAssertTrue(ReportViewModel.reasons(for: .squad).contains(.offensiveName))
    }

    func testEveryReasonHasATitle() {
        let titles = Report.Reason.allCases.map(\.title)
        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertFalse(titles.contains(where: \.isEmpty))
    }

    // MARK: - Wording

    func testEverySafetyFailureHasASentence() {
        let errors: [SafetyError] = [
            .notSignedIn, .missingTarget, .cannotTargetSelf, .detailsTooLong,
            .permissionDenied, .network, .unknown("x"),
        ]
        for error in errors {
            XCTAssertFalse(SafetyService.message(for: error, whileDoing: "doing that").isEmpty)
        }
    }

    /// A refused request with no edge behind it is what being blocked looks
    /// like from the other side. It must not say "blocked".
    func testABlockedSendersMessageDoesNotRevealTheBlock() {
        let message = FriendService.message(
            for: .requestRefused, whileDoing: "sending that request", context: .write
        )
        XCTAssertFalse(message.localizedCaseInsensitiveContains("block"))
        XCTAssertTrue(message.contains("isn't accepting requests"))
    }

    func testTheBlockConfirmationMentionsTheFriendshipOnlyWhenThereIsOne() {
        XCTAssertTrue(PlayerProfileSheet.blockConsequences(isFriend: true).contains("friends lists"))
        XCTAssertFalse(PlayerProfileSheet.blockConsequences(isFriend: false).contains("friends lists"))
        XCTAssertTrue(PlayerProfileSheet.blockConsequences(isFriend: false).contains("won't be told"))
    }

    // MARK: - FriendsViewModel

    func testBlockedPlayersAreHiddenAndOrderIsKept() {
        XCTAssertEqual(
            FriendsViewModel.visible(["a", "b", "c", "d"], hiding: ["b", "d"]),
            ["a", "c"]
        )
        XCTAssertEqual(FriendsViewModel.visible(["a", "b"], hiding: []), ["a", "b"])
    }

    /// A block wins over whatever edge is still there: the friendship's delete
    /// may not have landed yet, and the row should already read as blocked.
    func testABlockOutranksAnExistingFriendship() {
        let edge = Friendship(
            uidA: "aaa", uidB: "bbb", requestedBy: "aaa",
            status: .accepted, createdAt: nil, updatedAt: nil
        )

        XCTAssertEqual(
            FriendsViewModel.relationship(with: "bbb", in: ["bbb": edge], viewedBy: "aaa", blocked: ["bbb"]),
            .blocked
        )
        XCTAssertEqual(
            FriendsViewModel.relationship(with: "bbb", in: ["bbb": edge], viewedBy: "aaa", blocked: []),
            .friends
        )
        // Never yourself, whatever the set says.
        XCTAssertEqual(
            FriendsViewModel.relationship(with: "aaa", in: [:], viewedBy: "aaa", blocked: ["aaa"]),
            .you
        )
    }

    func testUnblockIsNotDrawnAsDestructive() {
        XCTAssertFalse(FriendsViewModel.Action.unblock.isDestructive)
        XCTAssertTrue(FriendsViewModel.Action.remove.isDestructive)
        XCTAssertTrue(FriendsViewModel.Action.decline.isDestructive)
        XCTAssertFalse(FriendsViewModel.Action.add.isDestructive)
    }
}
