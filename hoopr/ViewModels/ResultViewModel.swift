import Combine
import Foundation
import os

fileprivate let logger = Logger(subsystem: "com.hoopsrn", category: "ResultViewModel")

/// Drives screen 8 — "Who won?", and the waiting / confirmed / results-don't-
/// match state that follows.
///
/// A cross-collection join, per `ARCHITECTURE.md`: the match comes from
/// `SeasonGameService`, and both crests come from `SquadService` — the game
/// document denormalizes squad *names* so history survives a disbanded squad,
/// but not `iconKey`/`colorKey`, so the two buttons the whole screen is made of
/// need a second collection to draw.
@MainActor
final class ResultViewModel: ObservableObject {
    /// Kept live off `SeasonGameService`'s listener, which is how the *other*
    /// leader's report reaches this screen — the moment that turns "waiting on
    /// them" into confirmed or disputed without anybody refreshing anything.
    @Published private(set) var game: SeasonGame

    @Published private(set) var homeSquad: Squad?
    @Published private(set) var awaySquad: Squad?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isReporting = false

    let mySquadId: String

    private let seasonGameService: SeasonGameService
    private let squadService: SquadService

    private var cancellables = Set<AnyCancellable>()

    init(
        game: SeasonGame,
        mySquadId: String,
        seasonGameService: SeasonGameService,
        squadService: SquadService
    ) {
        self.game = game
        self.mySquadId = mySquadId
        self.seasonGameService = seasonGameService
        self.squadService = squadService

        seasonGameService.$games
            .receive(on: DispatchQueue.main)
            .sink { [weak self] games in
                guard let self, let updated = games.first(where: { $0.id == game.id }) else { return }
                self.game = updated
            }
            .store(in: &cancellables)

        Task { await self.loadSquads() }
    }

    // MARK: - Reads

    /// The three states screen 8 renders, derived from the two reports rather
    /// than from anything this screen chose.
    var outcome: SeasonGame.ReportOutcome { game.reportOutcome }

    var myReport: String? {
        guard let uid = seasonGameService.currentUserId else { return nil }
        return game.report(by: uid)
    }

    var opponentReport: String? {
        guard let uid = seasonGameService.currentUserId else { return nil }
        return game.opponentReport(by: uid)
    }

    /// Whether the signed-in user may report at all. False for everyone who
    /// isn't one of the two leaders, and for a match that is already settled —
    /// which is what keeps the screen from offering a button the rules refuse.
    var canReport: Bool {
        guard let uid = seasonGameService.currentUserId else { return false }
        return game.canReport(uid: uid, at: Date())
    }

    /// True for a leader whose match hasn't reached tip-off. Separate from
    /// `canReport` because it needs its own sentence: nothing is wrong, the
    /// game just hasn't been played.
    var isTooEarly: Bool {
        guard let uid = seasonGameService.currentUserId else { return false }
        return game.reportField(for: uid) != nil
            && game.isReportable
            && Date() < game.scheduledTime
    }

    /// Someone on a roster who doesn't lead it. They see the result, and see
    /// whose move it is, rather than a control that would be refused.
    var isLeader: Bool {
        guard let uid = seasonGameService.currentUserId else { return false }
        return game.reportField(for: uid) != nil
    }

    func squad(id: String) -> Squad? {
        id == game.homeSquadId ? homeSquad : awaySquad
    }

    func name(of squadId: String) -> String {
        game.name(of: squadId) ?? "That squad"
    }

    var myName: String { name(of: mySquadId) }
    var opponentName: String { game.opponentName(of: mySquadId) ?? "Your opponent" }

    // MARK: - Actions

    /// Records this leader's own report. The service decides — inside a
    /// transaction, against state it reads itself — whether this completes a
    /// matching pair.
    func report(winner winningSquadId: String, homeScore: Int?, awayScore: Int?) async {
        guard !isReporting else { return }
        isReporting = true
        defer { isReporting = false }

        do {
            let outcome = try await seasonGameService.reportResult(
                gameId: game.id,
                winningSquadId: winningSquadId,
                homeScore: homeScore,
                awayScore: awayScore
            )
            errorMessage = nil
            logger.notice("Reported a result; the match is now \(String(describing: outcome), privacy: .public)")
        } catch let error as SeasonGameError {
            // The state moved, or this caller isn't a leader of either squad.
            // Never a deployment problem on a write the client checked first.
            errorMessage = SeasonGameService.message(
                for: error,
                whileDoing: "recording the result",
                context: .write
            )
        } catch {
            errorMessage = "Something went wrong while recording the result."
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Crests

    /// Both squads, for the two buttons. `squadService.squad(id:)` covers the
    /// one I'm on for free — its listener already holds it — and the opponent
    /// takes the one-off read `squads` being world-readable exists to allow.
    private func loadSquads() async {
        async let home = resolvedSquad(id: game.homeSquadId)
        async let away = resolvedSquad(id: game.awaySquadId)
        let (resolvedHome, resolvedAway) = await (home, away)
        homeSquad = resolvedHome
        awaySquad = resolvedAway
    }

    private func resolvedSquad(id: String) async -> Squad? {
        if let mine = squadService.squad(id: id) { return mine }
        return try? await squadService.fetchSquad(id: id)
    }
}
