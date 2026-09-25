import Combine
import Foundation
import UserNotifications
import os

fileprivate let logger = Logger(subsystem: "com.hoopsrn", category: "NotificationService")

/// Owns `UserNotifications` — the only file in the app that imports it, the
/// same vendor-boundary treatment Firebase gets in `Services/`.
///
/// **Executes a plan and decides nothing.** Every decision about *what* to
/// schedule, *when*, and with *what copy* lives in `SeasonGameNotifications`,
/// a pure function with its own test suite. This class asks for permission,
/// removes the identifiers a plan is about to (re)schedule, and adds the
/// requests — three verbs, none of them a judgment call.
///
/// No `AuthService` subscription: local notifications aren't tied to a
/// Firestore session, and `UNUserNotificationCenter.current()` is already a
/// process-wide singleton, so this class holds no state worth per-user
/// teardown.
///
/// **It is also the center's delegate, and every tap opens the inbox**
/// (2026-09-25, at the user's request: "all app notifications should go
/// directly to the inbox"). Before this there was no delegate at all, so a
/// tapped notification opened the app on whatever screen it was last left on.
/// The delegate has to be in place before launch finishes or a tap that
/// *launches* the app is never delivered — which is why `hooprApp.init()`
/// builds this eagerly rather than leaving it to `StateObject`'s deferred
/// initializer.
@MainActor
final class NotificationService: NSObject, ObservableObject {
    /// The OS's permission decision, translated out of `UNAuthorizationStatus`
    /// so that type stays inside this file — the same treatment a Firestore
    /// type gets everywhere else in `Services/`. `.provisional` and
    /// `.ephemeral` fold into `.authorized`: both let a request succeed, and
    /// nothing here treats them differently.
    enum Status: Equatable {
        case notDetermined
        case authorized
        case denied
    }

    /// The OS's own answer, refreshed on demand. `nil` until the first check.
    ///
    /// Read by the game-day screen to decide whether to say a reminder won't
    /// arrive. Never written to prompt a second time — see `requestIfNeeded()`.
    @Published private(set) var authorizationStatus: Status?

    /// Set when a notification is tapped; `MainTabView` presents the inbox
    /// and hands it back through `consumeInboxRequest()`.
    ///
    /// A value held until consumed rather than an event fired and forgotten,
    /// because a tap that launches the app arrives before there is a tab
    /// interface to present anything — the app is still restoring its session.
    /// Whenever `MainTabView` appears, the request is waiting for it. A `UUID`
    /// rather than a `Bool`, so two taps in a row are two requests (the map's
    /// trigger pattern — see `MAP_LAYER.md`).
    @Published private(set) var inboxRequest: UUID?

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        Task { await refreshAuthorizationStatus() }
    }

    /// Clears a request the shell has acted on, so it isn't presented twice.
    func consumeInboxRequest() {
        inboxRequest = nil
    }

    /// Asks the OS for permission, **once**.
    ///
    /// The permission moment is match-found — the first instant a
    /// notification is worth anything, and the first moment the user has just
    /// gained something, which is the only leverage a prompt ever has. Calling
    /// this again after the user has answered does not re-show the system
    /// dialog; `UNUserNotificationCenter` only ever asks once per install, and
    /// every call after that just hands back the standing decision. That is
    /// what makes "never asks again" true without this class tracking
    /// anything about *why* — the OS already refuses to nag on our behalf.
    @discardableResult
    func requestIfNeeded() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            // Not surfaced as an error state — see the game-day screen. A
            // denial and a request that threw look identical to the user:
            // no reminder arrives, stated once, never nagged about again.
            logger.error("Notification authorization request failed: \(error.localizedDescription, privacy: .public)")
            await refreshAuthorizationStatus()
            return false
        }
    }

    func refreshAuthorizationStatus() async {
        let raw = await center.notificationSettings().authorizationStatus
        authorizationStatus = Self.mapped(raw)
    }

    private static func mapped(_ raw: UNAuthorizationStatus) -> Status {
        switch raw {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    /// Replaces every notification for a game with exactly what `planned`
    /// describes.
    ///
    /// **Remove before add, and remove the full identifier set, not just the
    /// planned one.** A planned list can be shorter than three — a game
    /// already past its reminder window plans only a tip-off and a recap —
    /// and if only the *planned* identifiers were removed, a stale reminder
    /// from an earlier call would survive untouched and still fire. Removing
    /// `SeasonGameNotifications.allIdentifiers(for:)` first is what makes a
    /// shrinking plan actually shrink what's scheduled.
    ///
    /// A scheduling failure is logged and swallowed: a missing reminder must
    /// never block the screen that shows the game, and there is nothing a
    /// user can do about a single failed `add` beyond what denying permission
    /// already covers.
    func apply(_ planned: [SeasonGameNotifications.Planned], for gameId: String) async {
        let staleIdentifiers = SeasonGameNotifications.allIdentifiers(for: gameId)
        center.removePendingNotificationRequests(withIdentifiers: staleIdentifiers)

        guard !planned.isEmpty else { return }

        guard await requestIfNeeded() else {
            logger.debug("Notifications not authorized; nothing scheduled for \(gameId, privacy: .public)")
            return
        }

        for item in planned {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default

            let interval = max(1, item.fireDate.timeIntervalSinceNow)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(
                identifier: item.identifier,
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
            } catch {
                logger.error(
                    "Couldn't schedule \(item.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Clears every notification a game could have, regardless of what was
    /// last planned. Called on cancel — a called-off match should remind
    /// nobody of anything.
    func cancelAll(for gameId: String) {
        center.removePendingNotificationRequests(
            withIdentifiers: SeasonGameNotifications.allIdentifiers(for: gameId)
        )
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {
    /// Any notification the app posted, tapped — or opened from Notification
    /// Center, or used to launch the app — routes to the inbox. Deliberately
    /// not keyed on the request's identifier: "every notification goes to the
    /// inbox" is the rule, so a kind added later gets it without a branch here.
    ///
    /// Only the default action (a tap) counts. Swiping a notification away
    /// reports `UNNotificationDismissActionIdentifier` — and only to a
    /// category that opts in, which none here do — and that is someone saying
    /// "not now", not "take me there".
    ///
    /// **The completion-handler form, not the `async` one — and that is
    /// load-bearing.** The `async` form crashed the app on the first tap
    /// (seen on the simulator, 2026-09-25): Swift runs the method off the main
    /// thread and then calls UIKit's completion handler from there, and UIKit
    /// asserts it is called on the main thread (`SIGABRT` in
    /// `_performBlockAfterCATransactionCommitSynchronizes:`). So the handler is
    /// called here, on the main actor, after the request is recorded.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let isTap = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        Task { @MainActor in
            if isTap {
                self.requestInbox()
            }
            completionHandler()
        }
    }

    /// A notification that fires while the app is open is shown as a banner
    /// (and kept in Notification Center) rather than dropped. Without this
    /// the system discards it: a tip-off reminder that fired while you had
    /// the app open to check the court simply never appeared. Tapping the
    /// banner comes back through `didReceive`, so it opens the inbox like any
    /// other tap.
    ///
    /// No `.badge`: the app never sets an icon badge, so there is nothing to
    /// update.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    private func requestInbox() {
        inboxRequest = UUID()
    }
}
