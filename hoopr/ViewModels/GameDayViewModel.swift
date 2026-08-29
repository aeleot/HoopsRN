import Combine
import Foundation
import os

fileprivate let logger = Logger(subsystem: "com.hoopsrn", category: "GameDayViewModel")

/// Drives screen 7 — the countdown, both rosters, and live arrival.
///
/// A cross-collection join, per `ARCHITECTURE.md`: it resolves both squads'
/// rosters to names, which needs `SquadService` (mine, and — via
/// `fetchSquad(id:)` — the opponent's, who I'm not a member of) joined to
/// `UserProfileService`. Reuses `SquadViewModel.memberRows(for:profiles:)`
/// rather than re-deriving the leader-first sort a second time.
@MainActor
final class GameDayViewModel: ObservableObject {
    /// Kept live off `SeasonGameService`'s listener — a cancellation or an
    /// arrival from the other squad lands here without a second read.
    @Published private(set) var game: SeasonGame

    @Published private(set) var homeRoster: [SquadViewModel.MemberRow] = []
    @Published private(set) var awayRoster: [SquadViewModel.MemberRow] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var isMarkingArrived = false

    let mySquadId: String

    private let seasonGameService: SeasonGameService
    private let squadService: SquadService
    private let userProfileService: UserProfileService
    private let notificationService: NotificationService
    private let courtService: CourtService

    private var cancellables = Set<AnyCancellable>()

    init(
        game: SeasonGame,
        mySquadId: String,
        seasonGameService: SeasonGameService,
        squadService: SquadService,
        userProfileService: UserProfileService,
        notificationService: NotificationService,
        courtService: CourtService
    ) {
        self.game = game
        self.mySquadId = mySquadId
        self.seasonGameService = seasonGameService
        self.squadService = squadService
        self.userProfileService = userProfileService
        self.notificationService = notificationService
        self.courtService = courtService

        seasonGameService.$games
            .receive(on: DispatchQueue.main)
            .sink { [weak self] games in
                guard let self, let updated = games.first(where: { $0.id == game.id }) else { return }
                self.game = updated
            }
            .store(in: &cancellables)

        Task { await self.loadRosters() }
        Task { await notificationService.refreshAuthorizationStatus() }
    }

    // MARK: - Reads

    var isHome: Bool { game.isHome(mySquadId) }

    var myRoster: [SquadViewModel.MemberRow] { isHome ? homeRoster : awayRoster }
    var opponentRoster: [SquadViewModel.MemberRow] { isHome ? awayRoster : homeRoster }
    var opponentName: String { game.opponentName(of: mySquadId) ?? "Opponent" }

    var courtName: String {
        courtService.courts.first { $0.id == game.courtId }?.displayName ?? "Unknown court"
    }

    var canCancel: Bool {
        guard let uid = seasonGameService.currentUserId else { return false }
        return game.canCancel(uid: uid)
    }

    var hasArrived: Bool {
        guard let uid = seasonGameService.currentUserId else { return false }
        return game.hasArrived(uid)
    }

    /// Not an error state: a denial is a legitimate, permanent choice, stated
    /// once rather than nagged about. `nil` while the OS hasn't answered yet,
    /// which reads the same as "on" — nothing to warn about until it's
    /// actually a `.denied`.
    var notificationsAreDenied: Bool {
        notificationService.authorizationStatus == .denied
    }

    // MARK: - Actions

    func markArrived() async {
        guard !hasArrived, !isMarkingArrived else { return }
        isMarkingArrived = true
        defer { isMarkingArrived = false }

        do {
            try await seasonGameService.markArrived(gameId: game.id)
            errorMessage = nil
        } catch let error as SeasonGameError {
            // The caller isn't on either roster, or the state moved — never a
            // deployment problem on a write the client validated first.
            errorMessage = SeasonGameService.message(
                for: error,
                whileDoing: "marking your squad arrived",
                context: .write
            )
        } catch {
            errorMessage = "Something went wrong while marking your squad arrived."
        }
    }

    func cancel() async {
        do {
            try await seasonGameService.cancelGame(id: game.id, bySquadId: mySquadId)
        } catch {
            logger.error("Couldn't cancel from game day: \(String(describing: error), privacy: .public)")
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Rosters

    private func loadRosters() async {
        async let home = resolvedRoster(squadId: game.homeSquadId)
        async let away = resolvedRoster(squadId: game.awaySquadId)
        let (resolvedHome, resolvedAway) = await (home, away)
        homeRoster = resolvedHome
        awayRoster = resolvedAway
    }

    /// A squad's roster, resolved to names. `squadService.squad(id:)` covers
    /// the squad I'm on for free — its listener already holds it; the
    /// opponent isn't on that listener, so `fetchSquad(id:)` is the one-off
    /// read `squads` being world-readable exists to allow.
    private func resolvedRoster(squadId: String) async -> [SquadViewModel.MemberRow] {
        let squad: Squad?
        if let mine = squadService.squad(id: squadId) {
            squad = mine
        } else {
            squad = try? await squadService.fetchSquad(id: squadId)
        }

        guard let squad else { return [] }

        let profiles = (try? await userProfileService.profiles(for: squad.memberIds)) ?? []
        let byUid = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

        return SquadViewModel.memberRows(for: squad, profiles: byUid)
    }
}
