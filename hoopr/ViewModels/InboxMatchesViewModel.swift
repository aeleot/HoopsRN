import Combine
import Foundation

/// Backs the inbox's Matches section: the season matches a notification could
/// have been about.
///
/// **Why the inbox shows matches at all** (2026-09-25). Every tapped
/// notification opens the inbox — the user's rule — and the only notifications
/// the app sends are a match's reminder, tip-off and recap
/// (`SeasonGameNotifications`). Before this section existed those taps landed
/// on friend requests, with nothing about the match they were for. Each row
/// opens the screen that answers it: game day for a match still to come, the
/// result screen for one waiting on your report.
///
/// Joins `SeasonGameService`'s games to `SquadService`'s squads (which side is
/// *mine*) and `CourtService`'s dataset (the court's name). The decision about
/// which matches belong here is the pure `rows(games:mySquadIds:uid:now:)`,
/// pinned by `InboxMatchesViewModelTests`.
@MainActor
final class InboxMatchesViewModel: ObservableObject {

    /// One match as the inbox lists it.
    nonisolated struct Row: Identifiable, Equatable, Sendable {
        nonisolated enum Kind: Equatable, Sendable {
            /// Still to come, or under way — opens game day.
            case upcoming
            /// Played, you lead a side, and you haven't reported — opens the
            /// result screen.
            case report
            /// Both leaders reported and disagree — opens the result screen.
            case disputed
        }

        let game: SeasonGame
        /// The user's side of it, which every destination screen needs.
        let mySquadId: String
        let kind: Kind

        var id: String { game.id }

        var opponentName: String {
            game.opponentName(of: mySquadId) ?? "your opponent"
        }
    }

    /// How long after tip-off an unreported match stays in the inbox. **An
    /// inbox choice, not a rule** — `firestore.rules` accepts a report at any
    /// time after tip-off. A week matches how long a confirmed win still
    /// celebrates (`ResultViewModel`), and stops a match nobody reported from
    /// sitting at the top of the inbox for the rest of the season.
    nonisolated static let reportWindow: TimeInterval = 7 * 24 * 60 * 60

    @Published private(set) var rows: [Row] = []

    private var games: [SeasonGame] = []
    private var mySquadIds: [String] = []
    private var courtsById: [String: Court] = [:]

    private let seasonGameService: SeasonGameService
    private var cancellables = Set<AnyCancellable>()

    init(
        seasonGameService: SeasonGameService,
        squadService: SquadService,
        courtService: CourtService
    ) {
        self.seasonGameService = seasonGameService

        seasonGameService.$games
            .receive(on: DispatchQueue.main)
            .sink { [weak self] games in
                self?.games = games
                self?.rebuild()
            }
            .store(in: &cancellables)

        squadService.$squads
            .receive(on: DispatchQueue.main)
            .sink { [weak self] squads in
                self?.mySquadIds = squads.map(\.id)
                self?.rebuild()
            }
            .store(in: &cancellables)

        courtService.$courts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] courts in
                self?.courtsById = Dictionary(courts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                self?.rebuild()
            }
            .store(in: &cancellables)
    }

    private func rebuild() {
        rows = Self.rows(
            games: games,
            mySquadIds: mySquadIds,
            uid: seasonGameService.currentUserId,
            now: Date()
        )
    }

    // MARK: - Which matches

    /// The matches worth a row, answers first.
    ///
    /// - A match **waiting on your report** — you lead a side, it's reportable,
    ///   the recap prompt's delay has passed (`SeasonGame.reportingDelay`, the
    ///   T+90 the notification fires at) and you haven't reported — or one
    ///   **disputed**, whenever that happened. Within `reportWindow` of
    ///   tip-off. Checked first, so from T+90 a leader is sent to the result
    ///   rather than to game day.
    /// - Otherwise a match **still upcoming** (`SeasonGame.isUpcoming`, which
    ///   runs to three hours after tip-off, like game day itself).
    ///
    /// A report you've already made, on a match the other leader hasn't, is
    /// waiting on them, not you, so it isn't listed. Nor is a cancelled or
    /// confirmed match.
    ///
    /// Answers first, then soonest tip-off first.
    nonisolated static func rows(
        games: [SeasonGame],
        mySquadIds: [String],
        uid: String?,
        now: Date
    ) -> [Row] {
        let mine = Set(mySquadIds)

        let rows: [Row] = games.compactMap { game in
            guard let mySquadId = game.squadIds.first(where: mine.contains) else { return nil }

            if let uid, game.reportField(for: uid) != nil, game.isReportable,
               now < game.scheduledTime.addingTimeInterval(reportWindow) {
                if game.status == .disputed {
                    return Row(game: game, mySquadId: mySquadId, kind: .disputed)
                }
                if game.report(by: uid) == nil,
                   now >= game.scheduledTime.addingTimeInterval(SeasonGame.reportingDelay) {
                    return Row(game: game, mySquadId: mySquadId, kind: .report)
                }
            }

            if game.isUpcoming(at: now) {
                return Row(game: game, mySquadId: mySquadId, kind: .upcoming)
            }
            return nil
        }

        return rows.sorted { lhs, rhs in
            let lhsAnswer = lhs.kind != .upcoming
            let rhsAnswer = rhs.kind != .upcoming
            if lhsAnswer != rhsAnswer { return lhsAnswer }
            return lhs.game.scheduledTime < rhs.game.scheduledTime
        }
    }

    // MARK: - Copy

    /// "Tonight · 7:00 PM · East End Park" for a match to come; what's asked of
    /// you for one waiting on a report. The day and time are `Game`'s, so a
    /// match reads the same as a run.
    func detail(for row: Row, now: Date = Date()) -> String {
        switch row.kind {
        case .upcoming:
            let court = courtsById[row.game.courtId]?.displayName ?? "Court TBD"
            let day = Game.dayText(for: row.game.scheduledTime, relativeTo: now)
            let time = Game.timeText(for: row.game.scheduledTime)
            return "\(day) · \(time) · \(court)"
        case .report:
            return "How'd it go? Report the result"
        case .disputed:
            return "Results don't match. Report again"
        }
    }
}
