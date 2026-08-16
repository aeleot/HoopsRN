import Combine
import Foundation

/// Backs the "Start Run" form.
///
/// Only collects what a person actually decides: when, who can see it, and how
/// many can play. The court comes from wherever the form was opened, and
/// everything else the schema stores — host, status, rosters, timestamps — is
/// derived by `GameService` on the write path.
@MainActor
final class CreateGameViewModel: ObservableObject {
    @Published var scheduledTime: Date
    @Published var isPublic = true
    @Published var maxPlayers = Game.defaultMaxPlayers

    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    /// Set once a **private** run is written, which turns the form into its
    /// confirmation step. Public runs leave this `nil` and the sheet dismisses
    /// straight away — there's nothing to hand out.
    ///
    /// It's shown here rather than only on the run's card because this is the
    /// one moment the host is certain to be looking: they just chose to hide
    /// the run, and the link is the whole of how anyone else reaches it.
    @Published private(set) var inviteLink: String?

    let court: Court

    private let gameService: GameService

    init(court: Court, gameService: GameService) {
        self.court = court
        self.gameService = gameService
        self.scheduledTime = Self.defaultTipOff()
    }

    // MARK: - Bounds

    /// The window `firestore.rules` enforces, so the picker can't offer a date
    /// the server will reject.
    var scheduleRange: ClosedRange<Date> {
        let now = Date()
        return now.addingTimeInterval(Game.minimumLeadTime)
            ... now.addingTimeInterval(Game.schedulingWindow)
    }

    var canDecreasePlayers: Bool {
        !isSaving && maxPlayers > Game.maxPlayersRange.lowerBound
    }

    var canIncreasePlayers: Bool {
        !isSaving && maxPlayers < Game.maxPlayersRange.upperBound
    }

    func adjustPlayers(by delta: Int) {
        maxPlayers = Game.validMaxPlayers(maxPlayers + delta)
    }

    /// Names the format when the roster happens to be an even side, which is
    /// how people actually describe a run. Silent otherwise rather than
    /// inventing a label for 7.
    var formatText: String? {
        guard maxPlayers.isMultiple(of: 2) else { return nil }
        let perSide = maxPlayers / 2
        return "\(perSide)-on-\(perSide)"
    }

    var visibilityCaption: String {
        isPublic
            ? "Anyone searching near this court can find and join your run."
            : "Hidden from search. You'll get a link to share with the players you want in."
    }

    /// The one check the form runs, shared with the write path — the button
    /// and the service can't disagree about what a valid run is.
    private var validationError: GameError? {
        Game.validate(
            courtId: court.id,
            scheduledTime: scheduledTime,
            maxPlayers: maxPlayers
        )
    }

    var canSave: Bool {
        !isSaving && validationError == nil
    }

    /// Names the problem in place rather than leaving Create greyed out with no
    /// explanation — which happens on its own if the form sits open long enough
    /// for the picked time to arrive.
    var validationHint: String? {
        validationError.map {
            GameService.message(for: $0, whileDoing: "starting your run", context: .write)
        }
    }

    // MARK: - Saving

    /// - Returns: `true` once the run is written. The new run arrives in the
    ///   Local Runs tab on the listener that's already open, so a public run
    ///   has nothing left to show and the caller dismisses. A private one sets
    ///   `inviteLink` first — the caller checks it before dismissing.
    func create() async -> Bool {
        guard !isSaving, inviteLink == nil else { return false }
        if let invalid = validationError {
            errorMessage = GameService.message(for: invalid, whileDoing: "starting your run", context: .write)
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let gameId = try await gameService.createGame(
                courtId: court.id,
                scheduledTime: scheduledTime,
                isPublic: isPublic,
                maxPlayers: maxPlayers
            )
            errorMessage = nil
            if !isPublic {
                inviteLink = InviteLink.text(forGameId: gameId)
            }
            return true
        } catch {
            errorMessage = Self.message(for: error)
            return false
        }
    }

    /// An hour out, rounded up to the next quarter hour — close enough to be
    /// the answer for a spontaneous run, tidy enough not to read as a
    /// timestamp.
    private static func defaultTipOff(from now: Date = Date()) -> Date {
        let target = now.addingTimeInterval(60 * 60)
        let quarterHour: TimeInterval = 15 * 60
        let rounded = (target.timeIntervalSinceReferenceDate / quarterHour).rounded(.up) * quarterHour
        return Date(timeIntervalSinceReferenceDate: rounded)
    }

    private static func message(for error: Error) -> String {
        guard let gameError = error as? GameError else {
            return error.localizedDescription
        }
        return GameService.message(for: gameError, whileDoing: "starting your run", context: .write)
    }
}
