import XCTest
@testable import hoopr

/// Keeps `firestore.rules` and the Swift constants it mirrors in step.
///
/// Several rules restate a value the client also owns — the roster bounds, the
/// scheduling window, the radius range, the name length, the derivation of
/// `status` from the roster, and on `squads` the name bounds, the roster
/// ceiling per format, the format allowlist and the crest allowlists. Nothing
/// connected the two copies, and a
/// divergence doesn't surface as a logic error: the server just refuses the
/// write, and the app reports `permission-denied`, which reads like an
/// undeployed ruleset. That's a bad afternoon.
///
/// So these tests parse the deployed rules file and assert it agrees with the
/// Swift side. **Change a bound in one place and this fails, naming both.**
///
/// What this is not: a rules evaluator. It doesn't prove the rules are correct,
/// only that the two copies of these shared constants still say the same thing.
/// Full rules coverage needs the Firebase emulator, which isn't wired up here.
///
/// The file is read from the source tree via `#filePath` rather than a test
/// bundle resource, so it checks the *real* `firestore.rules` — the one that
/// gets deployed — instead of a copy that could itself drift.
final class FirestoreRulesParityTests: XCTestCase {

    private static let rules: String = {
        let testFile = URL(fileURLWithPath: #filePath)
        let repositoryRoot = testFile
            .deletingLastPathComponent()   // hooprTests/
            .deletingLastPathComponent()   // repository root
        let rulesFile = repositoryRoot.appendingPathComponent("firestore.rules")

        guard let contents = try? String(contentsOf: rulesFile, encoding: .utf8) else {
            return ""
        }
        return contents
    }()

    private var rules: String { Self.rules }

    override func setUpWithError() throws {
        try XCTSkipIf(
            rules.isEmpty,
            "Couldn't read firestore.rules next to the source tree — parity is unverified."
        )
    }

    // MARK: - status

    /// The one duplicated *rule* rather than duplicated constant:
    /// `Game.status(playerCount:maxPlayers:)` in Swift, and the
    /// `statusMatchesRoster()` expression in the rules.
    ///
    /// Rather than string-matching the expression, this extracts its three
    /// moving parts — the comparison, and the status on each side of it —
    /// rebuilds the rule from them, and runs it against the same roster matrix
    /// as the Swift version. An edit that changes behaviour fails here even if
    /// it's written differently; an edit that only reformats doesn't.
    func testStatusRuleMatchesSwift() throws {
        let pattern = #"playerIds\.size\(\)\s*(>=|>|<=|<)\s*\S*?maxPlayers\s*\?\s*'(\w+)'\s*:\s*'(\w+)'"#
        let groups = try XCTUnwrap(
            firstMatch(pattern),
            "Couldn't find the status expression in firestore.rules. If statusMatchesRoster() was rewritten, update this pattern — don't delete the test."
        )

        let (comparison, whenTrue, whenFalse) = (groups[0], groups[1], groups[2])

        // Both branches have to name a status the model actually declares —
        // a typo'd 'ful' would otherwise reject every write at runtime.
        let trueStatus = try XCTUnwrap(
            Game.Status(rawValue: whenTrue), "Rules use unknown status '\(whenTrue)'"
        )
        let falseStatus = try XCTUnwrap(
            Game.Status(rawValue: whenFalse), "Rules use unknown status '\(whenFalse)'"
        )

        let compare = try XCTUnwrap(
            Self.comparators[comparison], "Unhandled comparison '\(comparison)'"
        )

        // Collected rather than asserted in the loop: a `>` / `>=` swap
        // disagrees on hundreds of rosters, and one clear failure naming the
        // first is worth more than a screen of identical ones.
        let disagreements = Game.maxPlayersRange.flatMap { maxPlayers in
            // Deliberately runs past `maxPlayers`: an over-full roster is
            // exactly where a `>` / `>=` divergence would hide.
            (0...(maxPlayers + 2)).compactMap { playerCount -> String? in
                let fromRules = compare(playerCount, maxPlayers) ? trueStatus : falseStatus
                let fromSwift = Game.status(playerCount: playerCount, maxPlayers: maxPlayers)

                guard fromRules != fromSwift else { return nil }
                return "\(playerCount)/\(maxPlayers): rules say '\(fromRules.rawValue)', Game.status says '\(fromSwift.rawValue)'"
            }
        }

        XCTAssertTrue(
            disagreements.isEmpty,
            """
            firestore.rules and Game.status disagree on \(disagreements.count) roster(s). \
            Rules read `playerIds.size() \(comparison) maxPlayers ? '\(whenTrue)' : '\(whenFalse)'`. \
            First: \(disagreements.first ?? "")
            """
        )
    }

    private static let comparators: [String: (Int, Int) -> Bool] = [
        ">=": { $0 >= $1 },
        ">":  { $0 > $1 },
        "<=": { $0 <= $1 },
        "<":  { $0 < $1 },
    ]

    // MARK: - Shared bounds

    func testRosterBoundsMatchSwift() throws {
        let lower = try number(#"maxPlayers\s*>=\s*(\d+)"#, "the create rule's minimum roster")
        let upper = try number(#"maxPlayers\s*<=\s*(\d+)"#, "the create rule's maximum roster")

        XCTAssertEqual(
            Int(lower), Game.maxPlayersRange.lowerBound,
            "firestore.rules allows >= \(Int(lower)) players; Game.maxPlayersRange starts at \(Game.maxPlayersRange.lowerBound)"
        )
        XCTAssertEqual(
            Int(upper), Game.maxPlayersRange.upperBound,
            "firestore.rules allows <= \(Int(upper)) players; Game.maxPlayersRange ends at \(Game.maxPlayersRange.upperBound)"
        )
    }

    func testSchedulingWindowMatchesSwift() throws {
        let days = try number(#"duration\.value\((\d+),\s*'d'\)"#, "the create rule's scheduling window")
        let seconds = days * 24 * 60 * 60

        XCTAssertEqual(
            seconds, Game.schedulingWindow,
            "firestore.rules caps scheduling at \(Int(days)) days; Game.schedulingWindow is \(Game.schedulingWindow / 86_400)"
        )
    }

    func testPreferredRadiusBoundsMatchSwift() throws {
        let lower = try number(#"preferredRadius\s*>=\s*([\d.]+)"#, "the update rule's minimum radius")
        let upper = try number(#"preferredRadius\s*<=\s*([\d.]+)"#, "the update rule's maximum radius")

        XCTAssertEqual(
            lower, UserProfile.preferredRadiusRange.lowerBound,
            "firestore.rules and UserProfile.preferredRadiusRange disagree on the minimum radius"
        )
        XCTAssertEqual(
            upper, UserProfile.preferredRadiusRange.upperBound,
            "firestore.rules and UserProfile.preferredRadiusRange disagree on the maximum radius"
        )
    }

    /// The rules cap `userName` in both the create and the update rule. Every
    /// occurrence has to match, so a change to one that misses the other is
    /// caught here rather than by a user with a long name.
    func testUserNameLengthMatchesSwift() throws {
        let lengths = allNumbers(#"userName\.size\(\)\s*<=\s*(\d+)"#)

        XCTAssertFalse(lengths.isEmpty, "Couldn't find a userName length cap in firestore.rules")

        for length in lengths {
            XCTAssertEqual(
                Int(length), UserProfile.maxUserNameLength,
                "firestore.rules caps userName at \(Int(length)); UserProfile.maxUserNameLength is \(UserProfile.maxUserNameLength)"
            )
        }
    }

    /// `Game.minimumLeadTime` has no numeric twin in the rules — the server
    /// checks `scheduledTime > request.time`. What matters is that the client
    /// stays clear of that boundary rather than racing it, which is the whole
    /// reason the constant exists.
    func testRulesRequireAFutureStartAndClientLeavesRoom() {
        XCTAssertTrue(
            rules.contains("scheduledTime > request.time"),
            "The create rule no longer requires a future start; Game.minimumLeadTime is built around it."
        )
        XCTAssertGreaterThan(
            Game.minimumLeadTime, 0,
            "A zero lead time races the server's scheduledTime > request.time check."
        )
    }

    // MARK: - Squads

    /// `Squad.nameLengthRange` in Swift, `isValidName()` in the rules.
    ///
    /// Scoped to that one function rather than matched against the whole file:
    /// `users` also caps a name, and a pattern loose enough to find this bound
    /// anywhere would happily assert the wrong collection's number.
    func testSquadNameBoundsMatchSwift() throws {
        let body = try functionBody("isValidName")
        let lower = try XCTUnwrap(
            numbers(#"name\.size\(\)\s*>=\s*(\d+)"#, in: body).first,
            "Couldn't find the minimum squad-name length in isValidName()"
        )
        let upper = try XCTUnwrap(
            numbers(#"name\.size\(\)\s*<=\s*(\d+)"#, in: body).first,
            "Couldn't find the maximum squad-name length in isValidName()"
        )

        XCTAssertEqual(
            Int(lower), Squad.nameLengthRange.lowerBound,
            "firestore.rules allows squad names of >= \(Int(lower)) characters; Squad.nameLengthRange starts at \(Squad.nameLengthRange.lowerBound)"
        )
        XCTAssertEqual(
            Int(upper), Squad.nameLengthRange.upperBound,
            "firestore.rules allows squad names of <= \(Int(upper)) characters; Squad.nameLengthRange ends at \(Squad.nameLengthRange.upperBound)"
        )
    }

    /// The format allowlist: `SquadFormat.available` in Swift,
    /// `isAllowedFormat()` in the rules.
    ///
    /// Compared as sets, because the rules' order is arbitrary while Swift's is
    /// the order the create sheet renders.
    func testFormatAllowlistMatchesSwift() throws {
        let allowed = Set(quotedStrings(in: try functionBody("isAllowedFormat")))
        let swiftSide = Set(SquadFormat.available.map(\.rawValue))

        XCTAssertFalse(allowed.isEmpty, "Couldn't find any format in isAllowedFormat()")
        XCTAssertEqual(
            allowed, swiftSide,
            "firestore.rules allows formats \(allowed.sorted()); SquadFormat.available is \(swiftSide.sorted())"
        )

        // Every string in the rules has to name a case the model declares, or
        // the allowlist admits a document nothing can decode.
        for raw in allowed {
            XCTAssertNotNil(
                SquadFormat(rawValue: raw),
                "firestore.rules allows format '\(raw)', which SquadFormat doesn't declare"
            )
        }
    }

    /// The roster ceiling per format: `SquadFormat.maxRoster` in Swift, the
    /// `maxRoster()` ternary chain in the rules.
    ///
    /// Rather than string-matching the expression, this pulls out every
    /// `format == 'x' ? n` pair and checks the *mapping*, the way
    /// `testStatusRuleMatchesSwift` rebuilds its rule from its parts — a
    /// reformat passes, a changed number doesn't.
    func testRosterCeilingPerFormatMatchesSwift() throws {
        let body = try functionBody("maxRoster")
        let pairs = try pairs(#"format\s*==\s*'([^']+)'\s*\?\s*(\d+)"#, in: body)

        XCTAssertFalse(pairs.isEmpty, "Couldn't find any format branch in maxRoster()")

        for (raw, ceiling) in pairs {
            let format = try XCTUnwrap(
                SquadFormat(rawValue: raw),
                "maxRoster() has a branch for format '\(raw)', which SquadFormat doesn't declare"
            )
            XCTAssertEqual(
                Int(ceiling), format.maxRoster,
                "firestore.rules caps a \(raw) roster at \(ceiling); SquadFormat.\(format).maxRoster is \(format.maxRoster)"
            )
        }

        // A format you can create must have a ceiling, or every join is
        // rejected against the fallback below.
        for format in SquadFormat.available {
            XCTAssertTrue(
                pairs.contains { $0.0 == format.rawValue },
                "SquadFormat.available includes \(format.rawValue), but maxRoster() in firestore.rules has no branch for it"
            )
        }

        // The fallback. A format the allowlist doesn't admit has to get zero
        // rather than a default — a non-zero fallback would size a roster
        // against a format this ruleset never agreed to.
        let fallback = try XCTUnwrap(
            numbers(#":\s*(\d+)\s*;"#, in: body).last,
            "Couldn't find maxRoster()'s fallback branch"
        )
        XCTAssertEqual(
            Int(fallback), 0,
            "maxRoster() falls back to \(Int(fallback)) for an unknown format; it has to be 0"
        )
    }

    /// The crest allowlists: `Squad.iconKeys` / `Squad.colorKeys` in Swift,
    /// `isAllowedIcon()` / `isAllowedColor()` in the rules.
    ///
    /// These are the widest of the mirrored values — twenty strings across two
    /// files — and the easiest to add to on one side only. A key missing from
    /// the rules is a crest that can be picked and never saved.
    func testCrestAllowlistsMatchSwift() throws {
        let icons = quotedStrings(in: try functionBody("isAllowedIcon"))
        let colors = quotedStrings(in: try functionBody("isAllowedColor"))

        XCTAssertFalse(icons.isEmpty, "Couldn't find any icon key in isAllowedIcon()")
        XCTAssertFalse(colors.isEmpty, "Couldn't find any colour key in isAllowedColor()")

        XCTAssertEqual(
            Set(icons), Set(Squad.iconKeys),
            """
            firestore.rules and Squad.iconKeys disagree. \
            Only in the rules: \(Set(icons).subtracting(Squad.iconKeys).sorted()). \
            Only in Swift: \(Set(Squad.iconKeys).subtracting(icons).sorted()).
            """
        )
        XCTAssertEqual(
            Set(colors), Set(Squad.colorKeys),
            """
            firestore.rules and Squad.colorKeys disagree. \
            Only in the rules: \(Set(colors).subtracting(Squad.colorKeys).sorted()). \
            Only in Swift: \(Set(Squad.colorKeys).subtracting(colors).sorted()).
            """
        )

        // Sets hide a repeat; the counts don't. A duplicated key in the rules
        // widens nothing and reads as agreement.
        XCTAssertEqual(icons.count, Set(icons).count, "isAllowedIcon() repeats a key")
        XCTAssertEqual(colors.count, Set(colors).count, "isAllowedColor() repeats a key")
    }

    /// The invite gate. `SquadInvite.id(for:_:)` builds `squadId_uid` in Swift,
    /// and the self-join rule rebuilds the same ID server-side to check the
    /// invite exists — if those two ever disagree, every join is refused and
    /// nothing says why.
    func testSelfJoinChecksTheInviteIdSwiftWouldBuild() {
        XCTAssertTrue(
            rules.contains("squadInvites/$(squadId + '_' + request.auth.uid)"),
            "The self-join rule no longer checks squadInvites/{squadId}_{uid}; SquadInvite.id(for:_:) is built around that shape."
        )
        XCTAssertEqual(
            SquadInvite.id(for: "SQUAD", "UID"), "SQUAD_UID",
            "SquadInvite.id(for:_:) no longer builds the ID the rules recompute."
        )
    }

    /// The friendship gate on an invite. The rules recompute the ordered pair
    /// ID with a ternary; Swift computes it with `Friendship.id(for:_:)`. Both
    /// orderings have to appear, or half the pairs silently fail the check
    /// depending on which uid sorts first.
    func testInviteFriendshipGateMatchesFriendshipId() throws {
        let body = try functionBody("friendshipId")

        XCTAssertTrue(
            body.contains("request.auth.uid + '_' + incoming().uid"),
            "friendshipId() no longer builds the caller-first ordering: \(body)"
        )
        XCTAssertTrue(
            body.contains("incoming().uid + '_' + request.auth.uid"),
            "friendshipId() no longer builds the invitee-first ordering: \(body)"
        )
        XCTAssertTrue(
            body.contains("request.auth.uid < incoming().uid"),
            "friendshipId() no longer picks the ordering lexicographically, which is what Friendship.id(for:_:) does: \(body)"
        )

        // And Swift still agrees about which side is which.
        XCTAssertEqual(Friendship.id(for: "aaa", "zzz"), "aaa_zzz")
        XCTAssertEqual(Friendship.id(for: "zzz", "aaa"), "aaa_zzz")
    }

    // MARK: - Match tickets

    /// **The three-places constant.** `MatchRules.staleClaim` governs the
    /// scanner, this rule's re-claim clause, and the waiting squad's UI, and
    /// the plan says so explicitly because a divergence here is invisible: a
    /// client would claim a ticket the server then refuses, and the user would
    /// see `permission-denied` on a perfectly reasonable action.
    func testStaleClaimWindowMatchesSwift() throws {
        let body = try functionBody("claimHasGoneStale")
        let seconds = try XCTUnwrap(
            numbers(#"duration\.value\((\d+),\s*'s'\)"#, in: body).first,
            "Couldn't find the stale-claim window in claimHasGoneStale()"
        )

        XCTAssertEqual(
            seconds, MatchRules.staleClaim,
            "firestore.rules lets a claim be retaken after \(Int(seconds))s; MatchRules.staleClaim is \(Int(MatchRules.staleClaim))s"
        )

        // The comparison has to be strictly greater-than, matching
        // `MatchTicket.isClaimable`. A `>=` here and a `>` there disagree on
        // exactly one second, which is the kind of divergence that shows up
        // once a week and never reproduces.
        XCTAssertTrue(
            body.contains("request.time > resource.data.claimedAt"),
            "claimHasGoneStale() no longer compares strictly; MatchTicket.isClaimable does: \(body)"
        )
    }

    /// `MatchTicket.courtCountRange` in Swift, `isValidCourtSelection()` in the
    /// rules.
    func testCourtCountBoundsMatchSwift() throws {
        let body = try functionBody("isValidCourtSelection")
        let lower = try XCTUnwrap(
            numbers(#"size\(\)\s*>=\s*(\d+)"#, in: body).first,
            "Couldn't find the minimum court count in isValidCourtSelection()"
        )
        let upper = try XCTUnwrap(
            numbers(#"size\(\)\s*<=\s*(\d+)"#, in: body).first,
            "Couldn't find the maximum court count in isValidCourtSelection()"
        )

        XCTAssertEqual(
            Int(lower), MatchTicket.courtCountRange.lowerBound,
            "firestore.rules requires >= \(Int(lower)) courts; MatchTicket.courtCountRange starts at \(MatchTicket.courtCountRange.lowerBound)"
        )
        XCTAssertEqual(
            Int(upper), MatchTicket.courtCountRange.upperBound,
            "firestore.rules allows <= \(Int(upper)) courts; MatchTicket.courtCountRange ends at \(MatchTicket.courtCountRange.upperBound)"
        )

        // The no-duplicates check, which `MatchTicket.validate` mirrors. Without
        // it a repeated court would skew the intersection the match rules take.
        XCTAssertTrue(
            body.contains("toSet().size()"),
            "isValidCourtSelection() no longer rejects duplicate courts; MatchTicket.validate does: \(body)"
        )
    }

    /// `MatchTicket.lifetimeRange` in Swift, `isValidLifetime()` in the rules.
    /// The two are written in different units on purpose — minutes and hours
    /// there, seconds here — so this converts rather than string-matching.
    func testTicketLifetimeBoundsMatchSwift() throws {
        let body = try functionBody("isValidLifetime")
        let minutes = try XCTUnwrap(
            numbers(#"duration\.value\((\d+),\s*'m'\)"#, in: body).first,
            "Couldn't find the minimum ticket lifetime in isValidLifetime()"
        )
        let hours = try XCTUnwrap(
            numbers(#"duration\.value\((\d+),\s*'h'\)"#, in: body).first,
            "Couldn't find the maximum ticket lifetime in isValidLifetime()"
        )

        XCTAssertEqual(
            minutes * 60, MatchTicket.lifetimeRange.lowerBound,
            "firestore.rules requires a ticket to live at least \(Int(minutes))m; MatchTicket.lifetimeRange starts at \(Int(MatchTicket.lifetimeRange.lowerBound / 60))m"
        )
        XCTAssertEqual(
            hours * 3_600, MatchTicket.lifetimeRange.upperBound,
            "firestore.rules caps a ticket at \(Int(hours))h; MatchTicket.lifetimeRange ends at \(Int(MatchTicket.lifetimeRange.upperBound / 3_600))h"
        )
    }

    /// Every ticket status the rules name has to be one the model declares. A
    /// typo'd `'opne'` would reject every queue attempt with no clue why.
    func testTicketStatusesInTheRulesAreDeclared() throws {
        let block = try matchBlock("matchTickets")
        let statuses = Set(strings(#"status\s*==\s*'(\w+)'"#, in: block))

        XCTAssertFalse(statuses.isEmpty, "Couldn't find any status comparison in the matchTickets rules")
        for raw in statuses {
            XCTAssertNotNil(
                MatchTicket.Status(rawValue: raw),
                "firestore.rules compares matchTickets status to '\(raw)', which MatchTicket.Status doesn't declare"
            )
        }
    }

    /// The claim is the one write in this app made by somebody who doesn't own
    /// the document, so the two things that authorize it are worth pinning
    /// literally: the caller must lead the *claiming* squad, and a squad can't
    /// take itself out of the pool.
    func testTheClaimRuleStillProvesLeadershipOfTheClaimingSquad() throws {
        let block = try matchBlock("matchTickets")

        XCTAssertTrue(
            block.contains("squads/$(incoming().claimedBy)"),
            "The claim rule no longer checks that the caller leads the squad named in claimedBy."
        )
        XCTAssertTrue(
            block.contains("incoming().claimedBy != squadId"),
            "The claim rule no longer stops a squad claiming its own ticket."
        )
    }

    /// The denormalized fields on a ticket are pinned to the squad document
    /// rather than trusted. `memberIds` is the one that matters: it's what the
    /// no-shared-players rule reads, so a client free to write its own copy
    /// could match against a squad it shares players with.
    func testTicketDenormalizedFieldsArePinnedToTheSquad() throws {
        let block = try matchBlock("matchTickets")

        for field in ["memberIds", "squadName", "format", "region"] {
            XCTAssertTrue(
                block.contains("incoming().\(field) == squad()."),
                "The matchTickets create rule no longer pins `\(field)` to the squad document."
            )
        }
    }

    // MARK: - Indexes

    /// The pool query is `region == · format == · status in · expiresAt >`, and
    /// Firestore needs a composite index for it. A missing one surfaces as
    /// `failed-precondition`, which the services map to `.indexRequired` — a
    /// clear error, but only after somebody hits it.
    func testThePoolQueryHasItsCompositeIndex() throws {
        let indexes = try Self.indexes()
        let pool = indexes.first { index in
            index["collectionGroup"] as? String == "matchTickets"
        }

        let fields = try XCTUnwrap(
            (pool?["fields"] as? [[String: Any]])?.compactMap { $0["fieldPath"] as? String },
            "firestore.indexes.json has no matchTickets index; the pool query needs one."
        )

        XCTAssertEqual(
            fields, ["region", "format", "status", "expiresAt"],
            "The matchTickets index doesn't match the pool query's shape."
        )
    }

    // MARK: - Parsing helpers

    private func firstMatch(_ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: rules,
                range: NSRange(rules.startIndex..., in: rules)
              ) else { return nil }

        return (1..<match.numberOfRanges).compactMap { index in
            Range(match.range(at: index), in: rules).map { String(rules[$0]) }
        }
    }

    private func allNumbers(_ pattern: String) -> [Double] {
        numbers(pattern, in: rules)
    }

    private func number(_ pattern: String, _ describing: String) throws -> Double {
        let values = allNumbers(pattern)
        return try XCTUnwrap(values.first, "Couldn't find \(describing) in firestore.rules")
    }

    /// The body of a named rules function, so a pattern can be scoped to the
    /// one place a value is defined instead of hunting the whole file.
    ///
    /// Several bounds appear in more than one collection — `users` caps a name
    /// and so does `squads` — and a pattern loose enough to find one anywhere
    /// will cheerfully assert the wrong one. These bodies contain no nested
    /// braces, which is what makes the non-greedy match safe.
    private func functionBody(_ name: String) throws -> String {
        let pattern = "function\\s+\(name)\\s*\\([^)]*\\)\\s*\\{([^}]*)\\}"
        let groups = try XCTUnwrap(
            firstMatch(pattern),
            "Couldn't find function \(name)() in firestore.rules. If it was renamed, update this test — don't delete it."
        )
        return groups[0]
    }

    /// Every single-quoted string in `text`, in order. Rules allowlists are
    /// written as `x in ['a', 'b']`, so this is how one is read back.
    private func quotedStrings(in text: String) -> [String] {
        strings(#"'([^']*)'"#, in: text)
    }

    private func numbers(_ pattern: String, in text: String) -> [Double] {
        strings(pattern, in: text).compactMap(Double.init)
    }

    /// Every match of a two-group pattern, as ordered pairs — how a
    /// `format == 'x' ? n` ternary chain is read back as a mapping.
    private func pairs(_ pattern: String, in text: String) throws -> [(String, String)] {
        let regex = try NSRegularExpression(pattern: pattern)
        return regex
            .matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { match in
                guard match.numberOfRanges >= 3,
                      let first = Range(match.range(at: 1), in: text),
                      let second = Range(match.range(at: 2), in: text) else { return nil }
                return (String(text[first]), String(text[second]))
            }
    }

    private func strings(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        return regex
            .matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { match in
                Range(match.range(at: 1), in: text).map { String(text[$0]) }
            }
    }

    /// The body of a `match /collection/{id} { ... }` block, so a pattern can be
    /// scoped to one collection. Brace-counted rather than regexed: these
    /// blocks nest, which is exactly what `functionBody`'s simpler match can't
    /// handle.
    private func matchBlock(_ collection: String) throws -> String {
        let needle = "match /\(collection)/"
        let start = try XCTUnwrap(
            rules.range(of: needle),
            "Couldn't find `match /\(collection)/...` in firestore.rules"
        )

        // The block's opening brace is the *last* one on the match line, not
        // the first after the path: `match /matchTickets/{squadId} {` opens a
        // brace for its path parameter first, and counting from that one
        // returns `{squadId}` and nothing else.
        let lineEnd = rules[start.lowerBound...].firstIndex(of: "\n") ?? rules.endIndex
        guard let open = rules[start.lowerBound..<lineEnd].lastIndex(of: "{") else {
            throw XCTSkip("Malformed match block for \(collection)")
        }

        var depth = 0
        var index = open
        while index < rules.endIndex {
            if rules[index] == "{" { depth += 1 }
            if rules[index] == "}" {
                depth -= 1
                if depth == 0 {
                    return String(rules[open...index])
                }
            }
            index = rules.index(after: index)
        }
        throw XCTSkip("Unbalanced braces in the \(collection) match block")
    }

    /// `firestore.indexes.json`, read from the source tree the same way the
    /// rules are — the deployed file, not a copy.
    private static func indexes() throws -> [[String: Any]] {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("firestore.indexes.json")

        let data = try Data(contentsOf: file)
        let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return parsed?["indexes"] as? [[String: Any]] ?? []
    }
}
