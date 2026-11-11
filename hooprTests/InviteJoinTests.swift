import XCTest
@testable import hoopr

/// The receiving half of an invite link: parsing the URL, holding it until the
/// shell can show it, deciding what the run means to whoever opened it, and
/// what the sheet says about each of those.
///
/// Everything here is a pure rule or a plain object — the read itself needs a
/// live Firestore, and is covered from the other side by
/// `firestore-tests/games.test.mjs` (a stranger's `get` of a private run, and
/// the transaction an invitee joins with).
@MainActor
final class InviteJoinTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let host = "host-uid"
    private let player = "player-uid"
    private let stranger = "stranger-uid"

    private func url(_ string: String) -> URL {
        URL(string: string)!
    }

    // MARK: - Parsing the link

    /// The minter and the parser are two halves of one format; a link the app
    /// sends has to be a link the app opens.
    func testALinkTheAppMintsParsesBackToItsRun() {
        for id in ["5FQxT2mKpLwd0aZbYc19", "game-001", "a b?c", "x.y~z"] {
            let link = url(InviteLink.text(forGameId: id))
            XCTAssertEqual(InviteLink.gameId(from: link), id, "round trip of \(id)")
        }
    }

    /// Harmless variations a messaging app or a person might introduce.
    func testTheSchemeAndHostAreCaseInsensitiveAndATrailingSlashIsForgiven() {
        XCTAssertEqual(InviteLink.gameId(from: url("HOOPSRN://Game/abc123")), "abc123")
        XCTAssertEqual(InviteLink.gameId(from: url("hoopsrn://game/abc123/")), "abc123")
    }

    func testAnotherSchemeOrHostIsNotAnInvite() {
        XCTAssertNil(InviteLink.gameId(from: url("https://game/abc123")))
        XCTAssertNil(InviteLink.gameId(from: url("hoopr://game/abc123")))
        XCTAssertNil(InviteLink.gameId(from: url("hoopsrn://squad/abc123")))
        XCTAssertNil(InviteLink.gameId(from: url("hoopsrn:game/abc123")))
    }

    /// `Firestore.document(_:)` traps on an ID that would make a collection
    /// path, so a link naming one must stop at the parser — including when the
    /// separator arrives percent-encoded and only appears once decoded.
    func testALinkThatWouldNameSomethingOtherThanOneRunIsRefused() {
        XCTAssertNil(InviteLink.gameId(from: url("hoopsrn://game/")))
        XCTAssertNil(InviteLink.gameId(from: url("hoopsrn://game")))
        XCTAssertNil(InviteLink.gameId(from: url("hoopsrn://game/abc/def")))
        XCTAssertNil(InviteLink.gameId(from: url("hoopsrn://game/abc%2Fdef")))
        XCTAssertNil(InviteLink.gameId(from: url(InviteLink.text(forGameId: "a b/c?d"))))
    }

    func testFirestoresOwnDocumentIdRulesAreEnforced() {
        XCTAssertTrue(InviteLink.isWellFormed(gameId: "abc123"))
        XCTAssertFalse(InviteLink.isWellFormed(gameId: ""))
        XCTAssertFalse(InviteLink.isWellFormed(gameId: "."))
        XCTAssertFalse(InviteLink.isWellFormed(gameId: ".."))
        XCTAssertFalse(InviteLink.isWellFormed(gameId: "__name__"))
        XCTAssertFalse(InviteLink.isWellFormed(gameId: "a/b"))
        XCTAssertFalse(InviteLink.isWellFormed(gameId: String(repeating: "a", count: 1_501)))
        XCTAssertNil(InviteLink.gameId(from: url("hoopsrn://game/__name__")))
        XCTAssertNil(InviteLink.gameId(from: url("hoopsrn://game/..")))
    }

    /// The scheme the code mints is the one the built app registers. Read from
    /// the test host's own `Info.plist`, so a scheme renamed on one side alone
    /// — the `hoopr` vs `hoopsrn` mix-up `gaps/GAMES.md` warned about — fails
    /// here rather than on someone's phone.
    func testTheAppRegistersTheSchemeItMints() throws {
        let types = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]],
            "No CFBundleURLTypes in the app's Info.plist"
        )
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertTrue(schemes.contains(InviteLink.scheme), "registered: \(schemes)")
    }

    // MARK: - Holding the link

    func testAnOpenedInviteWaitsUntilConsumed() {
        let router = InviteRouter()

        XCTAssertTrue(router.open(url("hoopsrn://game/abc123")))
        XCTAssertEqual(router.pending?.gameId, "abc123")

        router.consume()
        XCTAssertNil(router.pending)
    }

    /// A URL that isn't an invite leaves nothing behind — and doesn't clobber
    /// one that is still waiting for the shell.
    func testAUrlThatIsNotAnInviteIsDropped() {
        let router = InviteRouter()
        XCTAssertFalse(router.open(url("hoopsrn://squad/abc123")))
        XCTAssertNil(router.pending)

        router.open(url("hoopsrn://game/abc123"))
        router.open(url("https://example.com"))
        XCTAssertEqual(router.pending?.gameId, "abc123")
    }

    /// The same link twice is two presentations, not one ignored repeat.
    func testTheSameLinkTwiceIsTwoRequests() {
        let router = InviteRouter()
        router.open(url("hoopsrn://game/abc123"))
        let first = router.pending

        router.open(url("hoopsrn://game/abc123"))
        XCTAssertNotEqual(router.pending, first)
        XCTAssertEqual(router.pending?.gameId, first?.gameId)
    }

    // MARK: - Where the link landed

    private func game(
        players: [String],
        waitlisted: [String] = [],
        maxPlayers: Int = 10,
        isPublic: Bool = false,
        scheduledTime: Date? = nil,
        status: Game.Status? = nil
    ) -> Game {
        Game(
            id: "game-1",
            hostId: host,
            courtId: "court-a",
            scheduledTime: scheduledTime ?? now.addingTimeInterval(60 * 60),
            isPublic: isPublic,
            maxPlayers: maxPlayers,
            status: status ?? Game.status(playerCount: players.count, maxPlayers: maxPlayers),
            playerIds: players,
            queuedPlayerIds: waitlisted,
            createdAt: now,
            updatedAt: now,
            completedAt: nil
        )
    }

    private func landing(_ game: Game, for uid: String?, at date: Date? = nil) -> InviteJoinViewModel.Landing {
        InviteJoinViewModel.landing(for: game, currentUserId: uid, now: date ?? now)
    }

    func testAStrangerWithRoomIsOfferedTheBoardsJoin() {
        let run = game(players: [host])
        XCTAssertEqual(landing(run, for: stranger), .join)
        XCTAssertEqual(InviteJoinViewModel.Landing.join.action, .join)
        XCTAssertEqual(InviteJoinViewModel.Landing.join.action?.title, "Join")
    }

    func testAFullRunOffersTheWaitlist() {
        let run = game(players: (0..<10).map { "p\($0)" })
        XCTAssertEqual(landing(run, for: stranger), .waitlist)
        XCTAssertEqual(InviteJoinViewModel.Landing.waitlist.action, .joinWaitlist)
    }

    /// The invite and the board must agree on which join a stranger is offered
    /// — they write through the same path, so they should name it the same.
    func testTheJoinOfferedAgreesWithTheBoard() {
        for run in [game(players: [host]), game(players: (0..<10).map { "p\($0)" })] {
            XCTAssertEqual(
                landing(run, for: stranger).action,
                LocalRunsViewModel.action(for: run, currentUserId: stranger)
            )
        }
    }

    func testAPlayerAlreadyOnItIsToldSoAndOfferedNoWrite() {
        let run = game(players: [host, player])
        XCTAssertEqual(landing(run, for: player), .onRoster)
        XCTAssertNil(InviteJoinViewModel.Landing.onRoster.action)
    }

    func testAWaitlistedPlayerIsToldTheyAreWaitlisted() {
        let run = game(players: (0..<10).map { "p\($0)" }, waitlisted: [player])
        XCTAssertEqual(landing(run, for: player), .onWaitlist)
        XCTAssertNil(InviteJoinViewModel.Landing.onWaitlist.action)
    }

    /// A host is always on their own roster; hosting has to win, or a host
    /// opening their own link reads "You're on this run".
    func testTheHostOpeningTheirOwnLinkIsTheHost() {
        XCTAssertEqual(landing(game(players: [host]), for: host), .hosting)
        XCTAssertNil(InviteJoinViewModel.Landing.hosting.action)
    }

    /// Past `visibilityGrace` the run has left every list, and the invite
    /// stops offering it at the same instant — for its host too.
    func testARunPastItsGraceIsOverForEveryone() {
        let tipOff = now.addingTimeInterval(-Game.visibilityGrace)
        let run = game(players: [host], scheduledTime: tipOff)

        for uid in [stranger, host, nil] {
            XCTAssertEqual(landing(run, for: uid), .over)
        }
        XCTAssertNil(InviteJoinViewModel.Landing.over.action)

        // A second inside the grace it's still a run you can get on.
        let underway = game(players: [host], scheduledTime: tipOff.addingTimeInterval(1))
        XCTAssertEqual(landing(underway, for: stranger), .join)
    }

    /// Completed is over too, even before its tip-off has aged out — the rule
    /// refuses a roster write to a completed run, so offering one would fail.
    func testACompletedRunIsOver() {
        let run = game(players: [host, player], status: .completed)
        XCTAssertEqual(landing(run, for: stranger), .over)
        XCTAssertEqual(landing(run, for: player), .over)
    }

    // MARK: - What the sheet says

    /// The waitlist never promotes, and both waitlist states have to say so —
    /// in the board's own words, not a second phrasing of the same limit.
    func testBothWaitlistStatesSayTheWaitlistDoesNotMove() {
        for landing in [InviteJoinViewModel.Landing.waitlist, .onWaitlist] {
            let message = InviteJoinViewModel.copy(for: landing).message ?? ""
            XCTAssertTrue(message.contains(Game.waitlistCaveat), "\(landing): \(message)")
        }
    }

    /// The host is handing out a key, and is told so.
    func testTheHostIsToldAnyoneWithTheLinkCanJoin() {
        let message = InviteJoinViewModel.copy(for: .hosting).message ?? ""
        XCTAssertTrue(message.contains("Anyone"), message)
        XCTAssertTrue(message.contains("join"), message)
    }

    /// Every state has a heading of its own — none impersonates another.
    func testEveryStateSaysSomethingDifferent() {
        let landings: [InviteJoinViewModel.Landing] = [.join, .waitlist, .hosting, .onRoster, .onWaitlist, .over]
        let titles = landings.map { InviteJoinViewModel.copy(for: $0).title } + [InviteJoinViewModel.missingCopy.title]
        XCTAssertEqual(Set(titles).count, titles.count, "\(titles)")
    }

    /// A refused read names the deployment, because for this read that is the
    /// cause: the ruleset before the `get`/`list` split refuses every stranger.
    func testARefusedReadPointsAtTheRules() {
        let message = InviteJoinViewModel.loadMessage(for: .permissionDenied)
        XCTAssertTrue(message.contains("rules"), message)
        XCTAssertTrue(message.hasPrefix("Can't load this run"), message)
        XCTAssertEqual(InviteJoinViewModel.loadMessage(for: .network), FailureText.network)
    }
}
