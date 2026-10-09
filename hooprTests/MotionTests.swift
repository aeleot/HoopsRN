import XCTest
import SwiftUI
@testable import hoopr

/// The motion vocabulary's rules (UI revamp Phase 3): Reduce Motion is
/// honoured by every kind, durations suit a 120Hz display, and the haptics
/// fire on the changes a user caused — never on a screen rebuilding.
@MainActor
final class MotionTests: XCTestCase {

    // MARK: - Reduce Motion

    /// Every kind becomes the same short cross-fade — no spring, no travel.
    func testReduceMotionTurnsEveryKindIntoTheSameCrossFade() {
        let fade = Animation.easeInOut(duration: Motion.Duration.reduced)
        for kind in [Motion.Kind.move, .snap, .swap] {
            XCTAssertEqual(Motion.animation(kind, reduceMotion: true), fade, "\(kind)")
        }
    }

    /// And without it, each kind is its own spring.
    func testWithoutReduceMotionTheKindsAreDistinctSprings() {
        let move = Motion.animation(.move, reduceMotion: false)
        let snap = Motion.animation(.snap, reduceMotion: false)
        let swap = Motion.animation(.swap, reduceMotion: false)

        XCTAssertNotEqual(move, snap)
        XCTAssertNotEqual(snap, swap)
        XCTAssertNotEqual(move, .easeInOut(duration: Motion.Duration.reduced))
    }

    func testAPressedButtonOnlyDimsUnderReduceMotion() {
        XCTAssertTrue(Motion.pressScales(reduceMotion: false))
        XCTAssertFalse(Motion.pressScales(reduceMotion: true))
        XCTAssertLessThan(Motion.pressedOpacity, 1, "a pressed button must still show it's pressed")
    }

    // MARK: - Durations

    /// Short enough to feel immediate, long enough to be seen: nothing in the
    /// vocabulary delays a task. Exits are quicker than entrances, so what's
    /// leaving gets out of the way of what's arriving.
    func testDurationsStayShortAndExitsBeatEntrances() {
        XCTAssertLessThanOrEqual(Motion.Duration.enter, 0.35)
        XCTAssertLessThan(Motion.Duration.exit, Motion.Duration.enter)
        XCTAssertGreaterThanOrEqual(Motion.Duration.reduced, 0.1)
        XCTAssertLessThanOrEqual(Motion.Duration.reduced, 0.2)
    }

    // MARK: - The empty-state map's drift

    /// Under Reduce Motion the map rests on its centred frame — no wander.
    func testUnderReduceMotionTheMapHoldsStill() {
        for step in 0..<12 {
            let date = Date(timeIntervalSinceReferenceDate: Double(step) * 3.7)
            XCTAssertEqual(Motion.Drift.offset(at: date, reduceMotion: true), .zero)
        }
    }

    /// The loop closes: a period later the map is exactly where it was, so
    /// there is no seam to jump at.
    func testTheDriftLoopsWithoutASeam() {
        let date = Date(timeIntervalSinceReferenceDate: 1_234.5)
        let later = date.addingTimeInterval(Motion.Drift.period * 3)
        let now = Motion.Drift.offset(at: date, reduceMotion: false)
        let then = Motion.Drift.offset(at: later, reduceMotion: false)

        XCTAssertEqual(now.width, then.width, accuracy: 0.001)
        XCTAssertEqual(now.height, then.height, accuracy: 0.001)
    }

    /// The map is drawn `overscan` past its frame on every side, and the drift
    /// must never slide farther than that — or an edge of the map shows.
    func testTheDriftNeverUncoversTheMapsEdge() {
        var widest: CGFloat = 0
        for step in 0..<240 {
            let date = Date(timeIntervalSinceReferenceDate: Motion.Drift.period * Double(step) / 240)
            let offset = Motion.Drift.offset(at: date, reduceMotion: false)
            XCTAssertLessThan(abs(offset.width), Motion.Drift.overscan)
            XCTAssertLessThan(abs(offset.height), Motion.Drift.overscan)
            widest = max(widest, abs(offset.width))
        }
        XCTAssertGreaterThan(widest, Motion.Drift.amplitude * 0.95, "the drift should actually move")
    }

    /// Slow enough to be ambient, like the glow's — not something to watch.
    func testTheDriftIsSlow() {
        XCTAssertGreaterThanOrEqual(Motion.Drift.period, 20)
        XCTAssertLessThanOrEqual(Motion.Drift.period, 30)
    }

    // MARK: - The stats scoreboard

    /// Under Reduce Motion or VoiceOver the board doesn't rotate at all — every
    /// panel is shown at once instead.
    func testTheScoreboardHoldsStillUnderReduceMotionOrVoiceOver() {
        XCTAssertTrue(Motion.Scoreboard.isStatic(reduceMotion: true, voiceOver: false))
        XCTAssertTrue(Motion.Scoreboard.isStatic(reduceMotion: false, voiceOver: true))
        XCTAssertFalse(Motion.Scoreboard.isStatic(reduceMotion: false, voiceOver: false))
    }

    /// The next panel is due only when there's one to go to, the board isn't
    /// paused (WCAG 2.2.2's control), it's on screen and the app is in front —
    /// so the timer never runs for nobody.
    func testTheScoreboardAdvancesOnlyWhenSomeoneCanSeeItChange() {
        func advances(
            panels: Int = 3, paused: Bool = false, onScreen: Bool = true,
            active: Bool = true, reduceMotion: Bool = false, voiceOver: Bool = false
        ) -> Bool {
            Motion.Scoreboard.advances(
                panelCount: panels, isPaused: paused, isOnScreen: onScreen,
                isActive: active, reduceMotion: reduceMotion, voiceOver: voiceOver
            )
        }

        XCTAssertTrue(advances())
        XCTAssertFalse(advances(panels: 1), "nothing to rotate to")
        XCTAssertFalse(advances(paused: true), "paused")
        XCTAssertFalse(advances(onScreen: false), "scrolled away")
        XCTAssertFalse(advances(active: false), "app in the background")
        XCTAssertFalse(advances(reduceMotion: true), "Reduce Motion")
        XCTAssertFalse(advances(voiceOver: true), "VoiceOver")
    }

    /// Long enough to read a label and a number, short enough to come round.
    func testAScoreboardPanelHoldsLongEnoughToRead() {
        XCTAssertGreaterThanOrEqual(Motion.Scoreboard.dwell, 3)
        XCTAssertLessThanOrEqual(Motion.Scoreboard.dwell, 6)
    }

    // MARK: - The inbox bounce

    /// A new request bounces the tray; answering one doesn't, and nothing does
    /// under Reduce Motion.
    func testTheTrayBouncesOnlyWhenSomethingArrives() {
        XCTAssertTrue(Motion.bounces(from: 0, to: 1, reduceMotion: false))
        XCTAssertTrue(Motion.bounces(from: 2, to: 3, reduceMotion: false))
        XCTAssertFalse(Motion.bounces(from: 3, to: 2, reduceMotion: false))
        XCTAssertFalse(Motion.bounces(from: 2, to: 2, reduceMotion: false))
        XCTAssertFalse(Motion.bounces(from: 0, to: 1, reduceMotion: true))
    }

    // MARK: - Match found

    private let game: SeasonGame = {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return SeasonGame(
            id: "game-1",
            format: .threeVThree,
            region: "Durham",
            homeSquadId: "squad-theirs",
            awaySquadId: "squad-mine",
            squadIds: ["squad-theirs", "squad-mine"],
            homeLeaderId: "leader-theirs",
            awayLeaderId: "leader-mine",
            homeSquadName: "Court Vision",
            awaySquadName: "Rim Reapers",
            courtId: "court-1",
            scheduledTime: now.addingTimeInterval(3_600),
            status: .scheduled,
            arrivedPlayerIds: [],
            homeReport: nil,
            awayReport: nil,
            homeScore: nil,
            awayScore: nil,
            result: nil,
            cancelledBySquadId: nil,
            createdBy: "leader-mine",
            createdAt: now,
            updatedAt: nil,
            confirmedAt: nil
        )
    }()

    /// A search turning into a match is news, and felt.
    func testASearchTurningIntoAMatchIsASuccess() {
        XCTAssertEqual(MatchmakingCard.feedback(from: .searching, to: .matched(game)), .success)
        XCTAssertEqual(MatchmakingCard.feedback(from: .settling, to: .matched(game)), .success)
    }

    /// Opening the tab onto a match that already exists is the listeners
    /// arriving, not news — the rebuild Phase 3 rules out.
    func testOpeningOntoAnExistingMatchIsSilent() {
        XCTAssertNil(MatchmakingCard.feedback(from: .idle, to: .matched(game)))
    }

    /// The match document updating under a match that's already showing —
    /// arrivals, a report — isn't a second match found.
    func testAMatchUpdatingInPlaceIsSilent() {
        XCTAssertNil(MatchmakingCard.feedback(from: .matched(game), to: .matched(game)))
    }

    func testQueueingAndCancellingAreSilent() {
        XCTAssertNil(MatchmakingCard.feedback(from: .idle, to: .searching))
        XCTAssertNil(MatchmakingCard.feedback(from: .searching, to: .idle))
    }

    /// The transition is keyed on the kind of state, so a match's own fields
    /// changing never re-runs it.
    func testTheCardsTransitionKeyIgnoresTheMatchItCarries() {
        XCTAssertEqual(MatchmakingCard.kind(of: .matched(game)), .matched)
        XCTAssertEqual(MatchmakingCard.kind(of: .settling), .settling)
    }

    // MARK: - Runs

    func testGettingOnARunIsASuccessAndLeavingIsALightTap() {
        XCTAssertEqual(LocalRunsViewModel.ConfirmationKind.action(.join).feedback, .success)
        XCTAssertEqual(LocalRunsViewModel.ConfirmationKind.action(.joinWaitlist).feedback, .success)
        XCTAssertEqual(LocalRunsViewModel.ConfirmationKind.completed.feedback, .success)
        XCTAssertEqual(LocalRunsViewModel.ConfirmationKind.action(.leave).feedback, .impact(weight: .light))
        XCTAssertEqual(LocalRunsViewModel.ConfirmationKind.action(.cancel).feedback, .impact(weight: .light))
        XCTAssertNil(LocalRunsViewModel.ConfirmationKind.action(.none).feedback)
    }

    /// Two joins in a row are two confirmations: the serial is what makes the
    /// second a change.
    func testTheSameActionTwiceIsTwoConfirmations() {
        let first = LocalRunsViewModel.Confirmation(kind: .action(.join), serial: 1)
        let second = LocalRunsViewModel.Confirmation(kind: .action(.join), serial: 2)
        XCTAssertNotEqual(first, second)
    }

    // MARK: - Game day

    func testMarkingYourselfHereIsFeltOnlyOnTheChange() {
        XCTAssertEqual(GameDayView.arrivalFeedback(wasHere: false, isHere: true), .success)
        XCTAssertNil(GameDayView.arrivalFeedback(wasHere: true, isHere: true))
        XCTAssertNil(GameDayView.arrivalFeedback(wasHere: false, isHere: false))
    }
}
