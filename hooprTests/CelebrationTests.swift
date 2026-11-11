import SwiftUI
import XCTest
@testable import hoopr

/// UI revamp Phase 5: a confirmed win celebrates **once**, and busy courts glow
/// — both built in, with no package. What matters about each is a rule rather
/// than a picture: when the confetti may fire, that it can never be seen
/// appearing out of nowhere or be cut off mid-air, and that the glow is one
/// curve on both screens that holds still under Reduce Motion.
@MainActor
final class CelebrationTests: XCTestCase {

    // MARK: - Fixtures

    private let now = Date(timeIntervalSince1970: 1_756_000_000)
    private let mine = "squad-home"
    private let theirs = "squad-away"

    private func game(
        id: String = "game-1",
        homeReport: String? = nil,
        awayReport: String? = nil,
        confirmedAgo: TimeInterval? = nil
    ) -> SeasonGame {
        SeasonGame(
            id: id,
            format: .threeVThree,
            region: "Durham",
            homeSquadId: mine,
            awaySquadId: theirs,
            squadIds: [mine, theirs],
            homeLeaderId: "leader-home",
            awayLeaderId: "leader-away",
            homeSquadName: "Rim Reapers",
            awaySquadName: "Court Vision",
            courtId: "court-1",
            scheduledTime: now.addingTimeInterval(-7200),
            status: .scheduled,
            arrivedPlayerIds: [],
            homeReport: homeReport,
            awayReport: awayReport,
            homeScore: nil,
            awayScore: nil,
            result: nil,
            cancelledBySquadId: nil,
            createdBy: "leader-away",
            createdAt: nil,
            updatedAt: nil,
            confirmedAt: confirmedAgo.map { now.addingTimeInterval(-$0) }
        )
    }

    private func celebrates(_ game: SeasonGame, alreadyCelebrated: Bool = false) -> Bool {
        ResultViewModel.shouldCelebrate(
            game: game, mySquadId: mine, alreadyCelebrated: alreadyCelebrated, now: now
        )
    }

    // MARK: - When a win is celebrated

    func testYourConfirmedWinIsCelebrated() {
        XCTAssertTrue(celebrates(game(homeReport: mine, awayReport: mine, confirmedAgo: 60)))
    }

    /// The server stamps `confirmedAt` after the write that confirms it, so the
    /// snapshot the second reporter sees first carries `nil` — which is the
    /// freshest win there is, and the very moment worth celebrating.
    func testAWinWhoseTimestampHasNotResolvedIsCelebrated() {
        XCTAssertTrue(celebrates(game(homeReport: mine, awayReport: mine, confirmedAgo: nil)))
    }

    /// Confetti at the losing side would read as mockery.
    func testALossIsNotCelebrated() {
        XCTAssertFalse(celebrates(game(homeReport: theirs, awayReport: theirs, confirmedAgo: 60)))
    }

    /// A dispute counts for nobody (`gaps/SEASONS.md`), and one report settles
    /// nothing — even one naming you.
    func testNothingUnconfirmedIsCelebrated() {
        XCTAssertFalse(celebrates(game(homeReport: mine, awayReport: theirs)))
        XCTAssertFalse(celebrates(game(homeReport: mine, awayReport: nil)))
        XCTAssertFalse(celebrates(game()))
    }

    /// **Once.** Reopening the result, or the listener re-emitting the game,
    /// must not fire it again — the prompt's "must not fire on re-render".
    func testAWinIsCelebratedOnlyOnce() {
        XCTAssertFalse(celebrates(game(homeReport: mine, awayReport: mine, confirmedAgo: 60), alreadyCelebrated: true))
    }

    /// A new phone opening last month's result is browsing history, not
    /// hearing news.
    func testAnOldWinIsNotCelebrated() {
        let window = ResultViewModel.celebrationWindow

        XCTAssertTrue(celebrates(game(homeReport: mine, awayReport: mine, confirmedAgo: window - 60)))
        XCTAssertFalse(celebrates(game(homeReport: mine, awayReport: mine, confirmedAgo: window + 60)))
    }

    // MARK: - Remembering what was celebrated

    private func scratchDefaults() -> UserDefaults {
        let name = "CelebrationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testTheStoreRemembersAWinAcrossInstances() {
        let defaults = scratchDefaults()

        CelebratedWinsStore(defaults: defaults).record("game-1")

        let reopened = CelebratedWinsStore(defaults: defaults)
        XCTAssertTrue(reopened.contains("game-1"))
        XCTAssertFalse(reopened.contains("game-2"))
    }

    /// Bounded, oldest forgotten first — and a repeat doesn't take two slots.
    func testTheStoreKeepsTheMostRecentWins() {
        let store = CelebratedWinsStore(defaults: scratchDefaults())

        for index in 0...CelebratedWinsStore.maxEntries {
            store.record("game-\(index)")
        }
        store.record("game-\(CelebratedWinsStore.maxEntries)")

        XCTAssertFalse(store.contains("game-0"), "the oldest should have been forgotten")
        XCTAssertTrue(store.contains("game-1"))
        XCTAssertTrue(store.contains("game-\(CelebratedWinsStore.maxEntries)"))
    }

    // MARK: - The confetti

    private let screen = CGSize(width: 402, height: 874)

    func testTheSameSeedAlwaysFallsTheSameWay() {
        XCTAssertEqual(Confetti.pieces(count: 20, seed: 7), Confetti.pieces(count: 20, seed: 7))
        XCTAssertNotEqual(Confetti.pieces(count: 20, seed: 7), Confetti.pieces(count: 20, seed: 8))
        XCTAssertEqual(Confetti.pieces(count: Confetti.count, seed: 1).count, Confetti.count)
    }

    /// A game ID gives the same seed on every launch — which `hashValue`
    /// wouldn't — and different games differ.
    func testASeedIsStableForAGame() {
        XCTAssertEqual(Confetti.seed(for: "game-1"), Confetti.seed(for: "game-1"))
        XCTAssertNotEqual(Confetti.seed(for: "game-1"), Confetti.seed(for: "game-2"))
    }

    /// **Nothing appears in mid-air.** Every piece starts wholly above the top
    /// edge, so the burst enters the screen rather than popping into it.
    func testEveryPieceStartsAboveTheScreen() {
        for piece in Confetti.pieces(count: Confetti.count, seed: 99) {
            let frame = Confetti.frame(of: piece, at: 0, in: screen)!
            let reach = hypot(piece.width, piece.height) / 2
            XCTAssertLessThan(frame.position.y + reach, 0, "\(piece) starts on screen")
        }
    }

    /// Fully there until the fade, and fully gone by the end — so nothing is
    /// cut off at `duration`.
    func testPiecesFadeOutRatherThanVanishing() {
        let piece = Confetti.pieces(count: 1, seed: 3)[0]

        XCTAssertEqual(Confetti.frame(of: piece, at: 0.5, in: screen)!.opacity, 1)
        XCTAssertEqual(
            Confetti.frame(of: piece, at: Confetti.duration - Confetti.fadeOut, in: screen)!.opacity,
            1,
            accuracy: 0.0001
        )

        let last = Confetti.frame(of: piece, at: Confetti.duration - 0.001, in: screen)!
        XCTAssertLessThan(last.opacity, 0.01)
    }

    func testABurstDrawsNothingBeforeItStartsOrAfterItEnds() {
        let piece = Confetti.pieces(count: 1, seed: 3)[0]

        XCTAssertNil(Confetti.frame(of: piece, at: -0.1, in: screen))
        XCTAssertNil(Confetti.frame(of: piece, at: Confetti.duration, in: screen))
        XCTAssertNil(Confetti.frame(of: piece, at: Confetti.duration + 5, in: screen))
    }

    /// It has to *fall past* the result — through the band, where "You won"
    /// is — rather than streak off in a blink or hang at the top.
    func testTheBurstFallsThroughTheBandWhileItIsStillVisible() {
        let pieces = Confetti.pieces(count: Confetti.count, seed: 11)
        let fadeStart = Confetti.duration - Confetti.fadeOut
        let depths = pieces.compactMap { Confetti.frame(of: $0, at: fadeStart, in: screen)?.position.y }

        let median = depths.sorted()[depths.count / 2]
        XCTAssertGreaterThan(median, 300, "the burst should have reached the band's text by the fade")
        XCTAssertLessThan(median, screen.height * 1.2, "the burst fell too fast to read")
    }

    /// The flutter narrows a piece but never to nothing, which would draw a
    /// degenerate transform.
    func testAFlutteringPieceNeverTurnsFullyEdgeOn() {
        for piece in Confetti.pieces(count: 10, seed: 5) {
            for step in 0..<26 {
                let frame = Confetti.frame(of: piece, at: Double(step) * 0.1, in: screen)!
                XCTAssertGreaterThanOrEqual(abs(frame.flip), 0.1)
                XCTAssertLessThanOrEqual(abs(frame.flip), 1)
            }
        }
    }

    // MARK: - The glow

    /// Busy means the top two tiers, and the same on the map and Home.
    func testOnlyBusyCourtsGlow() {
        XCTAssertFalse(CourtHeat.glows(forGameCount: 0))
        XCTAssertFalse(CourtHeat.glows(forGameCount: CourtHeat.glowsFrom - 1))
        XCTAssertTrue(CourtHeat.glows(forGameCount: CourtHeat.glowsFrom))
        XCTAssertTrue(CourtHeat.glows(forGameCount: 12))
        XCTAssertLessThanOrEqual(CourtHeat.glowsFrom, CourtHeat.maxTier, "a court at the top of the ramp must glow")
    }

    /// Under Reduce Motion the halo holds still — the same frame at every
    /// moment, visible, and never moving.
    func testUnderReduceMotionTheGlowHoldsStill() {
        let first = Motion.Glow.frame(at: 0, reduceMotion: true)
        for step in 1...20 {
            XCTAssertEqual(Motion.Glow.frame(at: Double(step) * 0.17, reduceMotion: true), first)
        }
        XCTAssertGreaterThan(first.opacity, 0)
        XCTAssertGreaterThan(first.scale, 1)
    }

    /// A ping leaves the dot at its full colour and fades to nothing as it
    /// swells — then starts again, so the end of one cycle is the start of the
    /// next and the loop has no seam.
    func testAPingSwellsAndFadesThenRepeats() {
        let start = Motion.Glow.frame(at: 0, reduceMotion: false)
        let late = Motion.Glow.frame(at: Motion.Glow.period * 0.999, reduceMotion: false)

        XCTAssertEqual(start.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(start.opacity, Motion.Glow.peakOpacity, accuracy: 0.0001)
        XCTAssertEqual(late.scale, Motion.Glow.peakScale, accuracy: 0.01)
        XCTAssertLessThan(late.opacity, 0.001)

        for offset in [0.1, 0.7, 1.3] {
            assertSameFrame(
                Motion.Glow.frame(at: offset, reduceMotion: false),
                Motion.Glow.frame(at: offset + Motion.Glow.period * 3, reduceMotion: false)
            )
        }
    }

    private func assertSameFrame(
        _ lhs: Motion.Glow.Frame,
        _ rhs: Motion.Glow.Frame,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.scale, rhs.scale, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(lhs.opacity, rhs.opacity, accuracy: 0.0001, file: file, line: line)
    }

    /// The halo is never smaller than the dot it sits behind, so it can't be
    /// mistaken for the dot shrinking.
    func testTheHaloNeverShrinksBelowTheDot() {
        for step in 0...40 {
            let frame = Motion.Glow.frame(at: Motion.Glow.period * Double(step) / 40, reduceMotion: false)
            XCTAssertGreaterThanOrEqual(frame.scale, 1)
            XCTAssertLessThanOrEqual(frame.scale, Motion.Glow.peakScale)
        }
    }

    /// **The map and Home draw one curve.** The pin's keyframes are the SwiftUI
    /// halo's frames, sampled — not a timing function that approximates them.
    func testTheMapsKeyframesAreTheSameCurve() {
        let samples = Motion.Glow.samples(count: 24)

        XCTAssertEqual(samples.count, 25, "both ends are included")
        // The last sample is the cycle's end, which the clock reads as the
        // next cycle's start — checked on its own below.
        for (index, sample) in samples.enumerated() where index < 24 {
            let elapsed = Motion.Glow.period * Double(index) / 24
            assertSameFrame(sample, Motion.Glow.frame(at: elapsed, reduceMotion: false))
        }
        XCTAssertEqual(samples.last!.opacity, 0, accuracy: 0.0001)
    }

    /// The phase comes off the clock, so two halos started at different moments
    /// still pulse together.
    func testThePhaseIsReadOffTheClock() {
        let date = Date(timeIntervalSinceReferenceDate: 1_000_000.75)
        XCTAssertEqual(Motion.Glow.phase(at: date), 0.75, accuracy: 0.0001)

        let later = date.addingTimeInterval(Motion.Glow.period * 5)
        XCTAssertEqual(Motion.Glow.phase(at: later), Motion.Glow.phase(at: date), accuracy: 0.0001)
    }
}
