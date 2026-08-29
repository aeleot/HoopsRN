import Combine
import CoreLocation
import Foundation

/// Backs the Seasons tab: the squads you're on, the invites waiting on you,
/// and the friends you can still add to a squad you lead.
///
/// Composes three services rather than extending any of them. `SquadService`
/// owns the squads and the invites and knows only uids; `FriendService` owns
/// who you're allowed to invite; `UserProfileService` owns the names. Joining
/// them is a view-model job for the same reason the distance filter lives in
/// `LocalRunsViewModel` — no collection's service should learn about
/// another's, and the invite picker is precisely a `squadInvites`-to-
/// `friendships` join.
///
/// `CourtService` is here for one thing: deriving a new squad's `region` from
/// the leader's nearest court. That's the second join, and it's the one with
/// consequences — a wrong region silently partitions the matchmaking pool, so
/// it's a pure static below rather than something computed inline at the write.
@MainActor
final class SquadViewModel: ObservableObject {

    // MARK: - Types

    /// One member as the roster renders them. The row stays useful whether or
    /// not the name has resolved — membership is the real data, the profile is
    /// a decoration on it, exactly as in `FriendsViewModel.Row`.
    nonisolated struct MemberRow: Identifiable, Equatable {
        let uid: String
        /// `nil` while the lookup is in flight, or when the account is gone.
        let profile: UserProfile?
        let isLeader: Bool

        var id: String { uid }

        var isResolved: Bool { profile != nil }

        var displayName: String {
            profile?.userName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        /// The name as it appears in a sentence, where an empty string would
        /// read as a bug.
        var nameForProse: String {
            displayName.isEmpty ? "this player" : displayName
        }

        /// First letter of the display name, for the avatar. Empty selects the
        /// fallback glyph.
        var initial: String {
            guard let first = displayName.first(where: \.isLetter) else { return "" }
            return String(first).uppercased()
        }
    }

    /// An invite addressed to the signed-in user, with the squad it names
    /// resolved.
    ///
    /// The squad is fetched rather than listened to: the squads listener only
    /// carries squads you're already on, and an invite by definition names one
    /// you aren't. `squad` stays `nil` while that read is in flight, and also
    /// when the squad was disbanded after the invite was sent — a real race,
    /// and the reason the row renders a name-or-placeholder rather than
    /// assuming one landed.
    nonisolated struct IncomingInvite: Identifiable, Equatable {
        let invite: SquadInvite
        let squad: Squad?

        var id: String { invite.id }

        var squadName: String { squad?.name ?? "A squad" }
    }

    // MARK: - Published state

    /// Squads the signed-in user is on, most recently changed first.
    @Published private(set) var squads: [Squad] = []

    /// Invites waiting on the signed-in user's answer, newest first.
    @Published private(set) var incomingInvites: [IncomingInvite] = []

    @Published private(set) var errorMessage: String?

    /// A listener died and `SquadService` is re-attaching it. Distinguishes a
    /// broken list from an empty one — without it, a squad list that failed to
    /// load is indistinguishable from having no squad.
    @Published private(set) var isRecovering = false

    /// True once the squads listener has answered at least once. The tab picks
    /// between its hero empty state and a spinner on this.
    @Published private(set) var hasLoaded = false

    /// The squad or invite with a write in flight, if any. One at a time: the
    /// acting control spins and every other one goes inert, mirroring
    /// `LocalRunsViewModel.pendingGameId`.
    @Published private(set) var pendingId: String?

    /// Names already resolved, kept across rebuilds so accepting an invite
    /// doesn't re-fetch every roster on the screen.
    @Published private(set) var profilesByUid: [String: UserProfile] = [:]

    // MARK: - Dependencies

    private let squadService: SquadService
    private let friendService: FriendService
    private let userProfileService: UserProfileService
    private let courtService: CourtService
    private var cancellables = Set<AnyCancellable>()

    /// Accepted friendships, kept for the invite picker's join.
    private var friends: [Friendship] = []

    /// Invites the signed-in user has sent, so the picker can leave out people
    /// already asked.
    private var sentInvites: [SquadInvite] = []

    private var rawIncomingInvites: [SquadInvite] = []

    /// Squads named by an incoming invite, fetched once each and cached.
    /// Keyed by squad ID.
    private var invitingSquads: [String: Squad] = [:]

    /// Squad IDs whose fetch is in flight, so a rebuild storm doesn't fire the
    /// same read four times.
    private var fetchingSquadIds: Set<String> = []

    private var resolveTask: Task<Void, Never>?

    var currentUserId: String? { squadService.currentUserId }

    // MARK: - Init

    init(
        squadService: SquadService,
        friendService: FriendService,
        userProfileService: UserProfileService,
        courtService: CourtService
    ) {
        self.squadService = squadService
        self.friendService = friendService
        self.userProfileService = userProfileService
        self.courtService = courtService

        // `sink` with a weak capture rather than `assign(to:on: self)`, which
        // would retain self through self's own cancellable set.
        squadService.$squads
            .receive(on: DispatchQueue.main)
            .sink { [weak self] squads in
                self?.squads = squads
                self?.resolveNames()
            }
            .store(in: &cancellables)

        squadService.$incomingInvites
            .receive(on: DispatchQueue.main)
            .sink { [weak self] invites in
                self?.rawIncomingInvites = invites
                self?.rebuildInvites()
            }
            .store(in: &cancellables)

        squadService.$sentInvites
            .receive(on: DispatchQueue.main)
            .sink { [weak self] invites in
                self?.sentInvites = invites
            }
            .store(in: &cancellables)

        squadService.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.errorMessage = message
            }
            .store(in: &cancellables)

        squadService.$isRecovering
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecovering in
                self?.isRecovering = isRecovering
            }
            .store(in: &cancellables)

        squadService.$hasLoadedSquads
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasLoaded in
                self?.hasLoaded = hasLoaded
            }
            .store(in: &cancellables)

        friendService.$friends
            .receive(on: DispatchQueue.main)
            .sink { [weak self] friends in
                self?.friends = friends
                self?.resolveNames()
            }
            .store(in: &cancellables)
    }

    deinit {
        resolveTask?.cancel()
    }

    // MARK: - Reads

    /// The squad this tab treats as "yours" when there's exactly one place to
    /// land. Squad home renders it; with none, the hero empty state does.
    var primarySquad: Squad? { squads.first }

    func squad(id: String) -> Squad? {
        squads.first { $0.id == id }
    }

    /// The roster, leader first.
    func members(of squad: Squad) -> [MemberRow] {
        Self.memberRows(for: squad, profiles: profilesByUid)
    }

    /// The friends the signed-in user can still invite to `squad`, as rows.
    ///
    /// Empty is a legitimate answer with two different meanings — no friends
    /// yet, or everyone already asked — which is why the view distinguishes
    /// them from `friends.isEmpty` rather than from this list alone.
    func invitableFriends(for squad: Squad) -> [MemberRow] {
        guard let ownUid = currentUserId else { return [] }

        let uids = Self.invitableUids(
            friends: friends,
            squad: squad,
            alreadyInvited: sentInvites,
            viewedBy: ownUid
        )

        return uids.map { uid in
            MemberRow(uid: uid, profile: profilesByUid[uid], isLeader: false)
        }
        .sorted { Self.sortKey($0) < Self.sortKey($1) }
    }

    /// Whether the leader has any friends at all, which is what separates
    /// "invite someone" from "add friends first".
    var hasFriends: Bool { !friends.isEmpty }

    /// Invites already sent for this squad and not yet answered, newest first.
    /// Rendered above the picker so a leader can see — and revoke — what's
    /// outstanding rather than wondering why someone isn't offered.
    func pendingInvites(for squad: Squad) -> [SquadInvite] {
        sentInvites.filter { $0.squadId == squad.id }
    }

    /// The region a squad created right now would be queued in, or `nil` when
    /// no court is in range to name one.
    var regionForNewSquad: String? {
        Self.region(near: LocationService.homeLocation, in: courtService.courts)
    }

    func isBlocked(_ id: String) -> Bool {
        pendingId != nil && pendingId != id
    }

    func dismissError() {
        errorMessage = nil
    }

    func retry() {
        squadService.retry()
    }

    // MARK: - Pure joins

    /// Who's left to invite: your accepted friends, minus everyone already on
    /// the squad, minus everyone already asked, minus yourself.
    ///
    /// `nonisolated static` and pure so the join can be tested without
    /// constructing a service — the same shape `HomeViewModel.rankHotCourts`
    /// and `FriendsViewModel.merged` use. This is the join that makes the whole
    /// class a view model rather than a method on `SquadService`.
    ///
    /// Self-exclusion is not redundant with the member check. The leader is
    /// always on their own squad so the member filter already covers them
    /// today — but `SquadService.invite` and the rules both refuse a
    /// self-invite independently, and a picker that offered one would be a dead
    /// end the moment either of those changes.
    nonisolated static func invitableUids(
        friends: [Friendship],
        squad: Squad,
        alreadyInvited: [SquadInvite],
        viewedBy ownUid: String
    ) -> [String] {
        let invited = Set(
            alreadyInvited
                .filter { $0.squadId == squad.id }
                .map(\.uid)
        )
        let members = Set(squad.memberIds)

        var seen = Set<String>()
        return friends
            .filter { $0.status == .accepted }
            .map { $0.otherUid(than: ownUid) }
            .filter { uid in
                guard uid != ownUid else { return false }
                guard !members.contains(uid) else { return false }
                guard !invited.contains(uid) else { return false }
                return seen.insert(uid).inserted
            }
    }

    /// The roster in display order: the leader first, then everyone else by
    /// resolved name, then unresolved rows.
    ///
    /// Sorted rather than left in stored order because `memberIds` is written
    /// by whoever joined last — an arbitrary order that would reshuffle the
    /// roster every time someone joined or left.
    nonisolated static func memberRows(
        for squad: Squad,
        profiles: [String: UserProfile]
    ) -> [MemberRow] {
        squad.memberIds
            .map { uid in
                MemberRow(
                    uid: uid,
                    profile: profiles[uid],
                    isLeader: uid == squad.leaderId
                )
            }
            .sorted { lhs, rhs in
                if lhs.isLeader != rhs.isLeader { return lhs.isLeader }
                return sortKey(lhs) < sortKey(rhs)
            }
    }

    /// Resolved names sort alphabetically; unresolved ones sort to the end
    /// under their uid, so a row whose profile hasn't landed doesn't jump to
    /// the top of the list as an empty string.
    private nonisolated static func sortKey(_ row: MemberRow) -> String {
        let name = row.displayName.lowercased()
        return name.isEmpty ? "\u{10FFFF}\(row.uid)" : name
    }

    /// The matchmaking pool key for a squad created at `anchor`: the `city` of
    /// the nearest court in the bundled dataset.
    ///
    /// `Court.city` is the region key for v1 — the dataset is six Triangle
    /// cities and every court carries one. `plans/SCALE_UP.md` S1.1 defines a
    /// real region key for multi-city delivery; when it ships this returns that
    /// instead and the pool query is unchanged.
    ///
    /// Returns `nil` rather than a fallback when there's nothing to name a
    /// region from. **A guessed region is worse than none**: it partitions the
    /// matchmaking pool into groups that can never see each other, with no
    /// error anywhere to explain why nobody ever matches.
    nonisolated static func region(
        near anchor: CLLocationCoordinate2D,
        in courts: [Court]
    ) -> String? {
        let nearest = courts.min { lhs, rhs in
            Distance.between(anchor, lhs.coordinate) < Distance.between(anchor, rhs.coordinate)
        }

        guard let city = nearest?.city.trimmingCharacters(in: .whitespacesAndNewlines),
              !city.isEmpty else { return nil }
        return city
    }

    // MARK: - Writes

    /// Creates a squad and returns its ID, or `nil` when the write failed.
    ///
    /// The region is derived here rather than taken from the caller, because
    /// there's exactly one right answer and a screen shouldn't be able to pass
    /// a different one.
    func createSquad(
        name: String,
        format: SquadFormat,
        iconKey: String,
        colorKey: String
    ) async -> String? {
        guard pendingId == nil else { return nil }
        guard let region = regionForNewSquad else {
            errorMessage = SquadService.message(
                for: .missingRegion, whileDoing: "creating your squad", context: .write
            )
            return nil
        }

        pendingId = Self.creatingId
        defer { pendingId = nil }

        do {
            return try await squadService.createSquad(
                name: name,
                format: format,
                iconKey: iconKey,
                colorKey: colorKey,
                region: region
            )
        } catch {
            // `SquadService` already reported it; `errorMessage` is mirrored.
            return nil
        }
    }

    func editSquad(
        _ squad: Squad,
        name: String,
        iconKey: String,
        colorKey: String
    ) async {
        await perform(squad.id) {
            try await self.squadService.editSquad(
                id: squad.id, name: name, iconKey: iconKey, colorKey: colorKey
            )
        }
    }

    func invite(_ uid: String, to squad: Squad) async {
        await perform(uid) {
            try await self.squadService.invite(uid, to: squad.id)
        }
    }

    func revokeInvite(_ invite: SquadInvite) async {
        await perform(invite.uid) {
            try await self.squadService.revokeInvite(invite.id)
        }
    }

    func acceptInvite(_ invite: SquadInvite) async {
        await perform(invite.id) {
            try await self.squadService.acceptInvite(invite)
        }
    }

    func declineInvite(_ invite: SquadInvite) async {
        await perform(invite.id) {
            try await self.squadService.declineInvite(invite.id)
        }
    }

    func leave(_ squad: Squad) async {
        await perform(squad.id) {
            try await self.squadService.leaveSquad(id: squad.id)
        }
    }

    func disband(_ squad: Squad) async {
        await perform(squad.id) {
            try await self.squadService.disbandSquad(id: squad.id)
        }
    }

    /// The one-write-at-a-time wrapper every action above shares. Failures are
    /// swallowed here because `SquadService` has already worded them into
    /// `errorMessage`, which this mirrors.
    private func perform(_ id: String, _ write: @escaping () async throws -> Void) async {
        guard pendingId == nil else { return }

        pendingId = id
        defer { pendingId = nil }

        do {
            try await write()
        } catch {
            // Reported by the service; nothing to add.
        }
    }

    /// Stands in for a squad ID while one is being created — there isn't a real
    /// one to key the spinner on until the write returns.
    static let creatingId = "squad.creating"

    // MARK: - Name resolution

    /// Fetches the profiles for every uid on screen — rosters and invitable
    /// friends both — in one batched call, skipping anyone already resolved.
    private func resolveNames() {
        var wanted = Set(squads.flatMap(\.memberIds))
        if let ownUid = currentUserId {
            wanted.formUnion(friends.map { $0.otherUid(than: ownUid) })
        }

        let missing = wanted.subtracting(profilesByUid.keys)
        guard !missing.isEmpty else { return }

        resolveTask?.cancel()
        resolveTask = Task { [weak self] in
            guard let self else { return }
            guard let resolved = try? await self.userProfileService.profiles(for: Array(missing)) else {
                return
            }
            guard !Task.isCancelled else { return }

            for profile in resolved {
                self.profilesByUid[profile.id] = profile
            }
            self.rebuildInvites()
        }
    }

    /// Pairs each incoming invite with the squad it names, fetching squads not
    /// already cached.
    private func rebuildInvites() {
        incomingInvites = rawIncomingInvites.map { invite in
            IncomingInvite(invite: invite, squad: invitingSquads[invite.squadId])
        }

        for invite in rawIncomingInvites
        where invitingSquads[invite.squadId] == nil && !fetchingSquadIds.contains(invite.squadId) {
            fetchInvitingSquad(invite.squadId)
        }
    }

    private func fetchInvitingSquad(_ squadId: String) {
        fetchingSquadIds.insert(squadId)

        Task { [weak self] in
            guard let self else { return }
            defer { self.fetchingSquadIds.remove(squadId) }

            guard let squad = try? await self.squadService.fetchSquad(id: squadId) else { return }
            self.invitingSquads[squadId] = squad
            self.rebuildInvites()
        }
    }
}
