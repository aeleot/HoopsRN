import Foundation
import os

#if canImport(UIKit)
import UIKit
#endif

fileprivate let logger = Logger(subsystem: "com.hoopr", category: "ListenerSupervisor")

/// Which side of a service an error came from. Both Firestore services report
/// the same `permission-denied` for a rejected read and a rejected write, and
/// the two mean very different things — see `GameService.message(for:_:)`.
enum FailureContext {
    /// A snapshot listener, or any other read.
    case load
    /// A write the user just asked for.
    case write
}

/// Brings a dead Firestore listener back.
///
/// **A snapshot listener that hands an error to its callback is already gone.**
/// The SDK retries transient failures itself and never surfaces them; by the
/// time an error reaches the closure, it has given up and torn the listener
/// down. Nothing re-attaches it — which is why a `permission-denied` from an
/// undeployed ruleset, or a `failed-precondition` from an index still building,
/// used to leave a list permanently empty until the app was relaunched.
///
/// That's also why there's no classification of "retryable" errors here: every
/// error a listener reports is terminal for that listener, so every one is
/// worth re-attaching after.
///
/// Owned by the service whose listeners it re-attaches. Retries escalate and
/// then repeat rather than giving up, because the failures this exists for do
/// heal on their own — an index finishes building, a ruleset gets deployed —
/// and the whole point is that recovery shouldn't need a relaunch.
@MainActor
final class ListenerSupervisor {
    /// Escalating, then flat. The last value repeats forever: a re-attach is
    /// one cheap call, and five minutes between tries costs nothing next to a
    /// list that stays broken.
    nonisolated static let delays: [TimeInterval] = [2, 5, 15, 30, 60, 300]

    /// Re-attaches the listeners.
    ///
    /// Set by the owning service with a **weak** capture. The service owns this
    /// object, so a strong capture here closes the loop — the same cycle
    /// `RootViewModel` and the view models avoid.
    var onRetry: (() -> Void)?

    /// A listener has failed and a re-attach is pending or in flight. Services
    /// mirror this so the UI can say so rather than showing an empty list with
    /// no explanation.
    private(set) var isRecovering = false

    /// Which listeners are currently down, by key.
    ///
    /// Tracked per listener rather than as one flag because `GameService` runs
    /// two of them. If the public-runs listener dies while the queued-runs one
    /// keeps delivering snapshots, a single flag would let the healthy
    /// listener's success cancel the dead one's re-attach — leaving exactly the
    /// permanently-empty list this class exists to prevent. Recovery is only
    /// over when every listener that failed has reported back.
    private var failedListeners: Set<String> = []

    /// Consecutive re-attach rounds since the last full recovery. Indexes
    /// `delays`.
    private var attempt = 0

    private var retryTask: Task<Void, Never>?
    private var foregroundObserver: NSObjectProtocol?

    /// Describes the owner in logs — "games", "profile".
    private let subject: String

    init(subject: String) {
        self.subject = subject
        observeForeground()
    }

    deinit {
        retryTask?.cancel()
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
    }

    // MARK: - Signals from the owning service

    /// The listener called `listener` reported an error, so it's dead.
    /// Schedules a re-attach.
    ///
    /// A second failure while a re-attach is already pending is recorded but
    /// doesn't reschedule: one round brings every listener back, so counting
    /// two simultaneous deaths as two rounds would escalate the delay twice as
    /// fast as the outage warrants.
    func recordFailure(for listener: String) {
        failedListeners.insert(listener)
        isRecovering = true

        guard retryTask == nil else { return }

        let delay = Self.delay(forAttempt: attempt)
        attempt += 1

        logger.notice(
            "\(self.subject, privacy: .public)/\(listener, privacy: .public) listener died; re-attaching in \(delay, privacy: .public)s (round \(self.attempt, privacy: .public))"
        )

        schedule(after: delay)
    }

    /// A snapshot landed on `listener`. Recovery is only complete — and the
    /// backoff only resets — once every listener that failed has come back.
    func recordSuccess(for listener: String) {
        guard failedListeners.remove(listener) != nil else { return }
        guard failedListeners.isEmpty else {
            logger.notice(
                "\(self.subject, privacy: .public)/\(listener, privacy: .public) listener recovered; \(self.failedListeners.count, privacy: .public) still down"
            )
            return
        }

        logger.notice("\(self.subject, privacy: .public) listeners recovered")
        clear()
    }

    /// The listeners were torn down deliberately — sign-out, or a new session.
    /// Stops any pending re-attach so it can't resurrect a listener for the
    /// user who just left.
    func cancel() {
        clear()
    }

    /// Re-attach now instead of waiting out the backoff. Backs the "Try again"
    /// button and the foreground hook.
    ///
    /// Deliberately does *not* reset `attempt`: if this attempt fails too, the
    /// delay should keep escalating rather than dropping back to two seconds
    /// every time the app is opened.
    func retryNow() {
        guard isRecovering else { return }

        retryTask?.cancel()
        retryTask = nil
        onRetry?()
    }

    // MARK: - Scheduling

    /// The delay before the re-attach following `attempt` prior failures.
    /// Pure and `static` so the schedule is testable without waiting it out.
    nonisolated static func delay(forAttempt attempt: Int) -> TimeInterval {
        delays[min(max(attempt, 0), delays.count - 1)]
    }

    private func schedule(after delay: TimeInterval) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }

            // Cleared before the re-attach, not after: a listener that fails
            // again synchronously must be able to schedule the next round.
            self?.retryTask = nil
            self?.onRetry?()
        }
    }

    private func clear() {
        retryTask?.cancel()
        retryTask = nil
        failedListeners.removeAll()
        attempt = 0
        isRecovering = false
    }

    /// Returning to the foreground is the one moment worth jumping the queue.
    /// A backgrounded app's sleeping retry doesn't fire on time, and coming
    /// back is also when the user is most likely to be looking at the empty
    /// list this is trying to fill.
    private func observeForeground() {
        #if canImport(UIKit)
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.retryNow()
            }
        }
        #endif
    }
}
