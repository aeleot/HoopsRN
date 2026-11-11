import Combine
import Foundation
import os

fileprivate let logger = Logger(subsystem: "com.hoopsrn", category: "InviteRouter")

/// Holds an opened invite link until the shell is ready to show it.
///
/// `hooprApp` hands every incoming URL here through `.onOpenURL`; `MainTabView`
/// presents `InviteJoinSheet` for the request and hands it back through
/// `consume()`. **A value held until consumed, not an event fired and
/// forgotten** — `NotificationService.inboxRequest`'s shape, for the same
/// reason: a link that *launches* the app arrives before there is a tab
/// interface to present anything, and a link opened while signed out arrives
/// before there will be one at all. `RootView` shows the login screen, the
/// request waits here, and the moment `MainTabView` appears after sign-in
/// `@Published`'s replay hands it over. That is the whole of "stashing the
/// pending game across a cold start and a sign-in" — in memory, because a
/// link the user abandoned by quitting mid-login is not one to resurrect on
/// some later launch.
///
/// No `AuthService` subscription and no Firebase: this only parses a URL and
/// remembers the answer. `GameService.fetchGame(id:)` is what reads the run.
@MainActor
final class InviteRouter: ObservableObject {
    /// One opened link. Fresh `id` per open, so the same link tapped twice is
    /// two presentations rather than a no-op — the map's trigger pattern
    /// (`MAP_LAYER.md`), and what lets this double as `sheet(item:)`'s item.
    struct Request: Identifiable, Equatable {
        let id = UUID()
        let gameId: String
    }

    @Published private(set) var pending: Request?

    /// Takes any URL the app was asked to open.
    ///
    /// - Returns: whether it was an invite. Anything else is logged and
    ///   dropped — `hoopsrn://` is the only scheme registered, so a miss is a
    ///   malformed or hand-edited link, and there is nothing to show for it.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let gameId = InviteLink.gameId(from: url) else {
            logger.notice("Ignoring a URL that isn't an invite: \(url.absoluteString, privacy: .private)")
            return false
        }
        pending = Request(gameId: gameId)
        return true
    }

    /// Clears a request the shell has acted on, so it isn't presented twice.
    func consume() {
        pending = nil
    }
}
