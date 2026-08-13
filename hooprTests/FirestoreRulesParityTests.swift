import XCTest
@testable import hoopr

/// Keeps `firestore.rules` and the Swift constants it mirrors in step.
///
/// Several rules restate a value the client also owns — the roster bounds, the
/// scheduling window, the radius range, the name length, and the derivation of
/// `status` from the roster. Nothing connected the two copies, and a
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
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        return regex
            .matches(in: rules, range: NSRange(rules.startIndex..., in: rules))
            .compactMap { match in
                Range(match.range(at: 1), in: rules)
                    .flatMap { Double(rules[$0]) }
            }
    }

    private func number(_ pattern: String, _ describing: String) throws -> Double {
        let values = allNumbers(pattern)
        return try XCTUnwrap(values.first, "Couldn't find \(describing) in firestore.rules")
    }
}
