import FirebaseFirestore
import XCTest
@testable import hoopr

/// Covers the three pieces of shared failure handling both Firestore services
/// use: the re-attach schedule in `ListenerSupervisor`, the read/write split in
/// the error messages, and the `NSError` classification in `FirestoreFailure`.
///
/// None of them needs a live Firestore. The backoff is a pure function of the
/// attempt count, the messages are a pure function of the error and its
/// context, and the classification is a pure function of an `NSError` — which
/// is exactly why all three were written that way.
final class ServiceFailureTests: XCTestCase {

    // MARK: - Backoff

    func testBackoffEscalatesThenHolds() {
        let schedule = (0..<8).map { ListenerSupervisor.delay(forAttempt: $0) }

        // Strictly increasing until it reaches the cap.
        let escalating = Array(schedule.prefix(ListenerSupervisor.delays.count))
        XCTAssertEqual(escalating, ListenerSupervisor.delays)
        XCTAssertEqual(escalating, escalating.sorted())

        // And then flat, forever — the failures this exists for (a building
        // index, an undeployed ruleset) heal on their own, so giving up would
        // put us back where we started: a dead list until relaunch.
        let cap = try? XCTUnwrap(ListenerSupervisor.delays.last)
        XCTAssertEqual(schedule[6], cap)
        XCTAssertEqual(schedule[7], cap)
        XCTAssertEqual(ListenerSupervisor.delay(forAttempt: 500), cap)
    }

    func testBackoffStartsShort() {
        // The first retry has to be quick: a listener that dies during a normal
        // session should come back before the user notices the list is stale.
        XCTAssertLessThanOrEqual(ListenerSupervisor.delay(forAttempt: 0), 5)
    }

    func testBackoffToleratesAnOutOfRangeAttempt() {
        // Defensive: the attempt counter indexes a fixed array.
        XCTAssertEqual(
            ListenerSupervisor.delay(forAttempt: -1),
            ListenerSupervisor.delays.first
        )
    }

    // MARK: - Per-listener recovery

    /// The subtle one. `GameService` runs two listeners through one supervisor,
    /// and the public-runs listener can die while the queued-runs one keeps
    /// delivering snapshots — other people join runs constantly. If a healthy
    /// listener's success ended recovery, it would cancel the dead one's
    /// re-attach and leave that list permanently empty: the exact failure this
    /// whole mechanism exists to stop, reintroduced through the back door.
    @MainActor
    func testHealthyListenerDoesNotEndAnotherListenersRecovery() {
        let supervisor = ListenerSupervisor(subject: "test")

        supervisor.recordFailure(for: "public")
        XCTAssertTrue(supervisor.isRecovering)

        // The listener that never failed keeps reporting in.
        supervisor.recordSuccess(for: "queued")
        XCTAssertTrue(
            supervisor.isRecovering,
            "A snapshot from a listener that never failed must not end recovery"
        )

        supervisor.recordSuccess(for: "public")
        XCTAssertFalse(supervisor.isRecovering)
    }

    @MainActor
    func testRecoveryEndsOnlyWhenEveryFailedListenerIsBack() {
        let supervisor = ListenerSupervisor(subject: "test")

        supervisor.recordFailure(for: "queued")
        supervisor.recordFailure(for: "public")

        supervisor.recordSuccess(for: "queued")
        XCTAssertTrue(supervisor.isRecovering, "One of two back isn't recovered")

        supervisor.recordSuccess(for: "public")
        XCTAssertFalse(supervisor.isRecovering)
    }

    @MainActor
    func testCancelEndsRecovery() {
        let supervisor = ListenerSupervisor(subject: "test")

        supervisor.recordFailure(for: "queued")
        XCTAssertTrue(supervisor.isRecovering)

        // Sign-out tears the listeners down; a pending re-attach must not
        // resurrect them for the user who just left.
        supervisor.cancel()
        XCTAssertFalse(supervisor.isRecovering)
    }

    @MainActor
    func testRetryNowDoesNothingWhenHealthy() {
        let supervisor = ListenerSupervisor(subject: "test")
        let attempts = Counter()
        supervisor.onRetry = { attempts.value += 1 }

        supervisor.retryNow()

        XCTAssertEqual(attempts.value, 0, "Nothing is broken, so nothing should re-attach")
    }

    @MainActor
    func testRetryNowReattachesWhileRecovering() {
        let supervisor = ListenerSupervisor(subject: "test")
        let attempts = Counter()
        supervisor.onRetry = { attempts.value += 1 }

        supervisor.recordFailure(for: "queued")
        supervisor.retryNow()

        XCTAssertEqual(attempts.value, 1)
    }

    /// Boxed so the escaping `onRetry` closure mutates one shared value.
    @MainActor
    private final class Counter {
        var value = 0
    }

    // MARK: - Read vs write messaging

    /// The whole point of `FailureContext`. Firestore returns one
    /// `permission-denied` for "the ruleset isn't deployed" and for "the rules
    /// rejected this specific write", and the error can't tell them apart —
    /// but the side it came from can. A denied read points at deployment; a
    /// denied write must not, or a real authorization bug reads as a
    /// deployment problem and sends you to the wrong file.
    func testPermissionDeniedReadsDifferentlyOnReadAndWrite() {
        let load = GameService.message(
            for: .permissionDenied, whileDoing: "loading your runs", context: .load
        )
        let write = GameService.message(
            for: .permissionDenied, whileDoing: "joining the run", context: .write
        )

        XCTAssertNotEqual(load, write)
        XCTAssertTrue(
            load.lowercased().contains("rules"),
            "A denied read should still point at the deployed ruleset: \(load)"
        )
        XCTAssertFalse(
            write.lowercased().contains("rules"),
            "A denied write must not blame the ruleset — it's the likeliest thing to be a genuine rejection: \(write)"
        )
    }

    func testProfilePermissionDeniedMakesTheSameDistinction() {
        let load = UserProfileService.message(
            for: .permissionDenied, whileDoing: "loading your profile", context: .load
        )
        let write = UserProfileService.message(
            for: .permissionDenied, whileDoing: "saving your name", context: .write
        )

        XCTAssertNotEqual(load, write)
        XCTAssertTrue(load.lowercased().contains("rules"))
        XCTAssertFalse(write.lowercased().contains("rules"))
    }

    /// Every other case says the same thing either way — the context exists for
    /// `permissionDenied` alone, and shouldn't quietly start changing the rest.
    func testContextOnlyAffectsPermissionDenied() {
        let errors: [GameError] = [
            .notSignedIn, .invalidCourt, .invalidRoster, .scheduleTooSoon,
            .scheduleTooFar, .gameNotFound, .gameClosed, .indexRequired,
            .network, .unknown("boom"),
        ]

        for error in errors {
            XCTAssertEqual(
                GameService.message(for: error, whileDoing: "doing a thing", context: .load),
                GameService.message(for: error, whileDoing: "doing a thing", context: .write),
                "\(error) shouldn't read differently by context"
            )
        }
    }

    /// The failure actually observed in the wild: a composite index still
    /// building tore both Local Runs listeners down, and the only trace was a
    /// line in the log. It now has its own error and its own sentence.
    func testIndexRequiredSaysSoRatherThanFallingBackToUnknown() {
        let message = GameService.message(
            for: .indexRequired, whileDoing: "loading nearby runs", context: .load
        )

        XCTAssertTrue(
            message.lowercased().contains("index"),
            "A missing index should name itself: \(message)"
        )
        XCTAssertNotEqual(
            message,
            GameService.message(for: .unknown(""), whileDoing: "loading nearby runs", context: .load)
        )
    }

    // MARK: - Firestore error classification

    /// Both services used to carry their own copy of this mapping, so each
    /// could start disagreeing with the other about the same `NSError`. Now
    /// there's one classifier — which makes it worth pinning, because a wrong
    /// answer here is what decides whether the user is told to check their
    /// connection or to deploy the rules.

    private func firestoreError(_ code: Int) -> NSError {
        NSError(domain: FirestoreErrorDomain, code: code)
    }

    func testClassifiesTheCodesTheServicesActOn() {
        XCTAssertEqual(
            FirestoreFailure.classify(firestoreError(FirestoreErrorCode.permissionDenied.rawValue)),
            .permissionDenied
        )
        XCTAssertEqual(
            FirestoreFailure.classify(firestoreError(FirestoreErrorCode.notFound.rawValue)),
            .notFound
        )
        XCTAssertEqual(
            FirestoreFailure.classify(firestoreError(FirestoreErrorCode.failedPrecondition.rawValue)),
            .indexRequired,
            "failed-precondition is what a missing or still-building composite index looks like"
        )
        XCTAssertEqual(
            FirestoreFailure.classify(firestoreError(FirestoreErrorCode.unavailable.rawValue)),
            .network
        )
        XCTAssertEqual(
            FirestoreFailure.classify(firestoreError(FirestoreErrorCode.deadlineExceeded.rawValue)),
            .network
        )
    }

    /// An unrecognised Firestore code must not be silently folded into one of
    /// the cases above — it falls through carrying its own description.
    func testUnrecognisedFirestoreCodeFallsThroughToUnknown() {
        let error = firestoreError(FirestoreErrorCode.dataLoss.rawValue)

        guard case .unknown = FirestoreFailure.classify(error) else {
            return XCTFail("An unhandled Firestore code should classify as .unknown")
        }
    }

    /// Errors from outside Firestore reach these services too — a decode
    /// failure, say. They must not be read as Firestore codes: the numbering
    /// spaces are unrelated, so matching on the code alone would classify an
    /// arbitrary error as whatever Firestore uses that number for.
    func testNonFirestoreErrorIsNeverReadAsAFirestoreCode() {
        // Code 7 is `permissionDenied` in Firestore's domain.
        let impostor = NSError(
            domain: "com.hoopr.something.else",
            code: FirestoreErrorCode.permissionDenied.rawValue
        )

        guard case .unknown = FirestoreFailure.classify(impostor) else {
            return XCTFail("A foreign domain must not be classified by Firestore's code numbering")
        }
    }
}
