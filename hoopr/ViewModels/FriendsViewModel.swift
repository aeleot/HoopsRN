import Combine
import Foundation

/// Backs the Friends tab, its inbox, and the player profile sheet: finding
/// people, the requests in flight either way, and the people already added.
///
/// Composes three services rather than extending any of them. `FriendService`
/// owns the edges and knows only uids; `UserProfileService` owns the names;
/// `CourtService` owns the bundled court dataset a home court is resolved
/// against. Joining them is a view-model job for the same reason the distance
/// filter lives in `LocalRunsViewModel` rather than in `GameService` — no
/// collection's service should learn about another's.
///
/// **Everything on this screen is keyed on a person, not on an edge.** A search
/// result has no friendship document yet, so a friendship ID can't identify a
/// row. The ID is derived from the pair with `Friendship.id(for:_:)` at the
/// moment a write needs one.
@MainActor
final class FriendsViewModel: ObservableObject {

    // MARK: - Types

    /// One person as this screen renders them: who they are, and where the
    /// signed-in user stands with them. The row stays actionable whether or not
    /// the name has resolved — the friendship is the real data, the profile is a
    /// decoration on it.
    struct Row: Identifiable, Equatable {
        let uid: String
        /// `nil` while the lookup is in flight, or when the account is gone.
        let profile: UserProfile?
        let relationship: Relationship

        var id: String { uid }

        /// Whether there's a name to render yet. Drives the skeleton, and is
        /// what keeps an unresolved row from claiming to be "Unknown player".
        var isResolved: Bool { profile != nil }

        var displayName: String {
            profile?.userName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }

        /// The name as it appears in a sentence — a confirmation dialog, an
        /// accessibility label — where an empty string would read as a bug.
        var nameForProse: String {
            displayName.isEmpty ? "this player" : displayName
        }

        /// `userName` is a *display* name, not a stored handle (see
        /// `UserProfile`), so the `@` form is a rendering of it — whitespace
        /// removed, because "@Elliot Aeleot" doesn't read as one thing. Same
        /// derivation `ProfileView.handle` applies to the signed-in user.
        var handle: String {
            let compact = displayName.filter { !$0.isWhitespace }
            return compact.isEmpty ? "" : "@" + compact
        }

        /// First letter of the display name, for the avatar. Empty selects the
        /// fallback glyph — for an unresolved lookup, or a name with no letters.
        var initial: String {
            guard let first = displayName.first(where: \.isLetter) else { return "" }
            return String(first).uppercased()
        }
    }

    /// Where the signed-in user stands with someone.
    ///
    /// Derived from the live edge map on every snapshot, never stored — storing
    /// "sent" on one person's copy and "received" on the other's is exactly the
    /// two-copies-that-can-drift shape the single-document schema exists to
    /// avoid. `Friendship.direction(for:)` is the single source of truth.
    enum Relationship: Equatable {
        /// No edge at all — the only state from which a request can be sent.
        case none
        /// They asked, and are waiting on the signed-in user.
        case incoming
        /// The signed-in user asked, and is waiting on them.
        case outgoing
        case friends
        /// The signed-in user themselves. Filtered out of search, so this is a
        /// guard rather than a state the UI is expected to render.
        case you
    }

    /// What a row's controls do. `decline`, `cancel` and `remove` are the same
    /// delete server-side; they stay distinct here so the wording — and the log
    /// line — match the situation.
    enum Action: Hashable {
        case add
        case accept
        case decline
        case cancel
        case remove

        /// Beside a name in a list row, where the surrounding context says who
        /// and what.
        var title: String {
            switch self {
            case .add:     "Add"
            case .accept:  "Accept"
            case .decline: "Decline"
            case .cancel:  "Cancel"
            case .remove:  "Remove"
            }
        }

        /// In an action bar, which has the width for the noun and needs it —
        /// a bare "Remove" under someone's profile doesn't say remove *what*.
        var longTitle: String {
            switch self {
            case .add:     "Add Friend"
            case .accept:  "Accept"
            case .decline: "Decline"
            case .cancel:  "Cancel Request"
            case .remove:  "Remove Friend"
            }
        }

        /// Everything that takes something away reads in the app's error
        /// colour, matching `LocalRunsViewModel.Action.isDestructive`.
        var isDestructive: Bool {
            self != .add && self != .accept
        }
    }

    /// What the results area is showing. An enum rather than a pair of booleans
    /// because "searching with stale results still on screen" and "searched, no
    /// matches" are different screens, and a `isSearching`/`results.isEmpty`
    /// combination can't tell them apart.
    ///
    /// Carries **uids**, not rows: a result's relationship changes the instant
    /// the user taps Add, so rows are re-derived from live state on read rather
    /// than frozen at the moment the query returned.
    enum SearchState: Equatable {
        case idle
        case searching
        case results([String])
        case empty
        case failed(String)
    }

    // MARK: - Published state

    /// Bound to the search field. Debounced into `searchState` below.
    @Published var searchQuery = ""

    @Published private(set) var searchState: SearchState = .idle

    @Published private(set) var friends: [Row] = []
    @Published private(set) var incomingRequests: [Row] = []
    @Published private(set) var outgoingRequests: [Row] = []

    @Published private(set) var errorMessage: String?

    /// A listener died and `FriendService` is re-attaching it. Distinguishes a
    /// broken list from an empty one — without it, a friends list that failed to
    /// load is indistinguishable from having no friends.
    @Published private(set) var isRecovering = false

    /// The person with a write in flight, if any. One at a time: the acting row
    /// spins and every other row's controls go inert, mirroring
    /// `LocalRunsViewModel.pendingGameId`. Keyed on the person rather than the
    /// friendship because a search result has no friendship yet.
    @Published private(set) var pendingUid: String?

    /// Names already resolved, kept across rebuilds so answering a request
    /// doesn't re-fetch every profile on the screen.
    ///
    /// Published so an open profile sheet re-renders when a name lands under it.
    @Published private(set) var profilesByUid: [String: UserProfile] = [:]

    /// Mirrored from `CourtService` so a home court can be named. The dataset is
    /// bundled and loaded synchronously, so this is effectively constant.
    @Published private(set) var courts: [Court] = []

    // MARK: - Dependencies

    private let friendService: FriendService
    private let userProfileService: UserProfileService
    private var cancellables = Set<AnyCancellable>()

    private var incoming: [Friendship] = []
    private var outgoing: [Friendship] = []
    private var accepted: [Friendship] = []

    /// Every edge the signed-in user is on, keyed by the *other* participant —
    /// the lookup `relationship(with:)` needs, rebuilt on every snapshot.
    private var edgesByUid: [String: Friendship] = [:]

    /// The in-flight name lookup, cancelled when a newer one supersedes it.
    private var resolveTask: Task<Void, Never>?

    /// The in-flight search, cancelled when the query moves on.
    private var searchTask: Task<Void, Never>?

    // MARK: - Tuning

    private enum Limit {
        /// Matches `UserProfileService`'s own result cap: a picker of matches,
        /// not a directory.
        static let searchResults = 20

        /// Long enough that typing a name doesn't fire a query per keystroke,
        /// short enough that the list doesn't feel stalled behind the keyboard.
        static let searchDebounce = 300

        /// Firebase uids are 28-character alphanumeric strings today. The range
        /// is deliberately loose on both sides — this only decides whether to
        /// *also* try an exact lookup, and an over-eager guess costs one
        /// document read while an under-eager one loses the feature.
        static let userIdLength = 20...128
    }

    // MARK: - Init

    init(
        friendService: FriendService,
        userProfileService: UserProfileService,
        courtService: CourtService
    ) {
        self.friendService = friendService
        self.userProfileService = userProfileService

        // `sink` with a weak capture rather than `assign(to:on: self)`, which
        // would retain self through self's own cancellable set.
        friendService.$incomingRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] requests in
                self?.incoming = requests
                self?.rebuild()
            }
            .store(in: &cancellables)

        friendService.$outgoingRequests
            .receive(on: DispatchQueue.main)
            .sink { [weak self] requests in
                self?.outgoing = requests
                self?.rebuild()
            }
            .store(in: &cancellables)

        friendService.$friends
            .receive(on: DispatchQueue.main)
            .sink { [weak self] friends in
                self?.accepted = friends
                self?.rebuild()
            }
            .store(in: &cancellables)

        friendService.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.errorMessage = message
            }
            .store(in: &cancellables)

        friendService.$isRecovering
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecovering in
                self?.isRecovering = isRecovering
            }
            .store(in: &cancellables)

        courtService.$courts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] courts in
                self?.courts = courts
            }
            .store(in: &cancellables)

        // Undebounced, and only for the two transitions that must be instant:
        // emptying the field restores the friends list immediately rather than
        // sitting on stale results for the debounce interval, and the first
        // keystroke shows the spinner rather than a blank area. Neither issues a
        // query — that's the debounced sink below.
        $searchQuery
            .removeDuplicates()
            .sink { [weak self] query in
                self?.reactToQueryEdit(query)
            }
            .store(in: &cancellables)

        // Debounced so a five-letter name is one query rather than five. The
        // query itself is re-derived from scratch each time, so a keystroke
        // never merges with a stale in-flight result.
        $searchQuery
            .removeDuplicates()
            .debounce(
                for: .milliseconds(Limit.searchDebounce),
                scheduler: DispatchQueue.main
            )
            .sink { [weak self] query in
                self?.runSearch(query)
            }
            .store(in: &cancellables)
    }

    deinit {
        resolveTask?.cancel()
        searchTask?.cancel()
    }

    // MARK: - Derivation

    private func rebuild() {
        guard let uid = friendService.currentUserId else {
            edgesByUid = [:]
            incomingRequests = []
            outgoingRequests = []
            friends = []
            return
        }

        edgesByUid = Dictionary(
            (incoming + outgoing + accepted).map { ($0.otherUid(than: uid), $0) },
            // A pair can only have one document — the ordered-pair ID guarantees
            // it — so a collision here would mean two edges decoded for the same
            // person. Keeping the first is arbitrary but stable.
            uniquingKeysWith: { first, _ in first }
        )

        rebuildRows()
        resolveMissingProfiles()
    }

    /// Re-derives the three lists against the current caches without kicking off
    /// another lookup — see the recursion note on `resolveMissingProfiles`.
    private func rebuildRows() {
        guard let uid = friendService.currentUserId else { return }

        incomingRequests = incoming.map { row(for: $0.otherUid(than: uid)) }
        outgoingRequests = outgoing.map { row(for: $0.otherUid(than: uid)) }
        friends = accepted.map { row(for: $0.otherUid(than: uid)) }
    }

    /// One person's row, built from the live caches. Also the profile sheet's
    /// entry point: it holds a uid and reads through this on every render, so a
    /// name arriving or a relationship changing under an open sheet lands there
    /// without the sheet holding a copy that could go stale.
    func row(for uid: String) -> Row {
        Row(
            uid: uid,
            profile: profilesByUid[uid],
            relationship: relationship(with: uid)
        )
    }

    /// Where the signed-in user stands with `uid`, against the live edge map.
    func relationship(with uid: String) -> Relationship {
        guard let ownUid = friendService.currentUserId else { return .none }
        return Self.relationship(with: uid, in: edgesByUid, viewedBy: ownUid)
    }

    /// The rows for the current search results, re-derived on read.
    ///
    /// Computed rather than stored so a result's button updates the moment its
    /// relationship changes — tapping Add on a result has to turn it into
    /// "Requested" without re-running the query.
    var searchRows: [Row] {
        guard case .results(let uids) = searchState else { return [] }
        return uids.map { row(for: $0) }
    }

    /// Fetches the names this screen doesn't have yet.
    ///
    /// One batch across all three lists, and only for uids missing from the
    /// cache, so a new request costs one lookup rather than a re-fetch of
    /// everyone. A failure is deliberately silent: the rows are already usable
    /// without a name, and the uid stays missing from the cache, so the next
    /// snapshot retries it on its own. Putting a transient name failure in the
    /// error banner would push the friendship's own errors off the screen.
    private func resolveMissingProfiles() {
        let shown = incomingRequests + outgoingRequests + friends
        let missing = Set(shown.map(\.uid)).subtracting(profilesByUid.keys)
        guard !missing.isEmpty else { return }

        let service = userProfileService
        resolveTask?.cancel()
        resolveTask = Task { [weak self] in
            guard let resolved = try? await service.profiles(for: Array(missing)) else {
                return
            }
            guard !Task.isCancelled else { return }

            guard let self else { return }
            for profile in resolved {
                self.profilesByUid[profile.id] = profile
            }
            // Re-derives the rows against the now-populated cache. Safe from
            // recursion: every uid just resolved is in the cache, so a rebuild's
            // own `resolveMissingProfiles` finds nothing missing — unless a
            // profile genuinely doesn't exist, which is why the fetch is only
            // ever kicked off by a snapshot, never by itself.
            self.rebuildRows()
        }
    }

    /// Fills in one profile the batch lookup never covered — a player whose
    /// profile document is gone, or whose lookup failed while the sheet was
    /// opening. Called by the profile sheet on appear so it heals itself rather
    /// than sitting on a skeleton.
    func loadProfileIfNeeded(for uid: String) async {
        guard profilesByUid[uid] == nil else { return }
        guard let profile = try? await userProfileService.profile(uid: uid) else { return }

        profilesByUid[profile.id] = profile
        rebuildRows()
    }

    // MARK: - Search

    /// Whether the results area has taken over from the friends list.
    ///
    /// Derived from `searchState` rather than from the raw text, so emptying the
    /// field flips it back in the same frame — `reactToQueryEdit` is what keeps
    /// the two in step without waiting out the debounce.
    var isSearchActive: Bool { searchState != .idle }

    /// The half of the search that can't wait for the debounce: clearing the
    /// field, and the very first keystroke.
    ///
    /// Never issues a query. Refining an existing query deliberately leaves the
    /// current results on screen while the new ones load — replacing them with a
    /// spinner on every keystroke reads as flicker, not as progress.
    private func reactToQueryEdit(_ raw: String) {
        if UserProfile.searchKey(raw).isEmpty {
            searchTask?.cancel()
            searchState = .idle
        } else if searchState == .idle {
            searchState = .searching
        }
    }

    /// Runs the query behind the search field, or clears the results area when
    /// there's nothing worth asking the server.
    ///
    /// Two searches run for one query: a prefix range over `userNameLower`, and
    /// — only when the text is shaped like a user ID — a direct document read.
    /// Running both rather than routing between them removes the failure mode
    /// where the heuristic guesses wrong and the user gets nothing; the cost is
    /// one extra document read on uid-shaped input, and a display name is never
    /// uid-shaped, so ordinary typing never pays for it.
    private func runSearch(_ raw: String) {
        searchTask?.cancel()

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = UserProfile.searchKey(raw)

        // An empty field is "no query yet", not "everyone" — mirroring
        // `UserProfileService.searchProfiles`, which returns nothing for a blank
        // prefix rather than the first 20 accounts in the database.
        guard !key.isEmpty else {
            searchState = .idle
            return
        }

        // Two independent decisions, because the two lookups answer to
        // different bounds. Nothing stored can match a *name* prefix longer
        // than the longest name the rules accept, so that query is skipped —
        // but a document ID is under no such bound, so an over-long string can
        // still be a perfectly legal ID. Gating both on the name limit would
        // make any ID longer than 50 characters silently unsearchable.
        let namePrefix = key.count <= UserProfile.maxUserNameLength ? trimmed : nil
        let idCandidate = Self.looksLikeUserId(trimmed) ? trimmed : nil

        // Neither lookup has anything to ask: answered without a round trip.
        guard namePrefix != nil || idCandidate != nil else {
            searchState = .empty
            return
        }

        if case .results = searchState {
            // Refining a query leaves the current results on screen while the
            // new ones load. Swapping them for a spinner on every keystroke
            // reads as flicker, not as progress — which is the same call
            // `reactToQueryEdit` makes for the undebounced half.
        } else {
            searchState = .searching
        }

        let service = userProfileService
        let ownUid = friendService.currentUserId

        searchTask = Task { [weak self] in
            async let exact = Self.exactProfile(for: idCandidate, using: service)
            async let byName = Self.namedProfiles(matching: namePrefix, using: service)

            // Awaited first and non-throwing, so the name query's failure path
            // below never leaves this child task dangling.
            let exactMatch = await exact

            let namedMatches: [UserProfile]
            do {
                namedMatches = try await byName
            } catch {
                guard !Task.isCancelled, let self else { return }
                self.searchState = .failed(Self.searchFailureText(for: error))
                return
            }

            guard !Task.isCancelled, let self else { return }

            let merged = Self.merged(
                exact: exactMatch,
                byName: namedMatches,
                excluding: ownUid,
                limit: Limit.searchResults
            )

            // Cached so opening one of these profiles is instant, and so a
            // person who later sends a request already has a name on their row.
            for profile in merged {
                self.profilesByUid[profile.id] = profile
            }

            self.searchState = merged.isEmpty ? .empty : .results(merged.map(\.id))
        }
    }

    /// The exact-ID lookup, or `nil` when the text isn't uid-shaped.
    ///
    /// Swallows its own failures: a broken ID lookup must not fail a search that
    /// the name query answered perfectly well, and "no such account" is an
    /// ordinary answer here rather than an error.
    private nonisolated static func exactProfile(
        for uid: String?,
        using service: UserProfileService
    ) async -> UserProfile? {
        guard let uid else { return nil }
        return try? await service.profile(uid: uid)
    }

    /// The name prefix search, or nothing when the typed text is too long to
    /// match any stored name.
    ///
    /// Unlike `exactProfile` this one throws: a failed name query is the one
    /// that reaches the user as `.failed`, because it's the search they meant.
    private nonisolated static func namedProfiles(
        matching prefix: String?,
        using service: UserProfileService
    ) async throws -> [UserProfile] {
        guard let prefix else { return [] }
        return try await service.searchProfiles(matching: prefix)
    }

    func clearSearch() {
        searchQuery = ""
        searchTask?.cancel()
        searchState = .idle
    }

    // MARK: - Pure helpers
    //
    // Extracted as statics because they hold the logic most likely to break and
    // need neither Firebase nor a main actor to exercise — see
    // `hooprTests/FriendsViewModelTests.swift`.

    /// Whether typed text should *also* be tried as an exact user ID.
    ///
    /// Firebase uids are ASCII alphanumeric strings, 28 characters in practice.
    /// Display names in that shape essentially don't occur, and the two searches
    /// run together anyway, so a false positive costs one document read and a
    /// false negative costs nothing the name query wouldn't already have found.
    nonisolated static func looksLikeUserId(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Limit.userIdLength.contains(text.count) else { return false }
        return text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    /// Merges the two result streams into one ranked list.
    ///
    /// An exact ID match ranks first — it's the only unambiguous answer on the
    /// screen. Duplicates collapse by uid (the same person can satisfy both
    /// queries), and the signed-in user is dropped: `FriendService.sendRequest`
    /// rejects a self-request anyway, but offering the button at all is a dead
    /// end the list shouldn't render.
    nonisolated static func merged(
        exact: UserProfile?,
        byName: [UserProfile],
        excluding ownUid: String?,
        limit: Int
    ) -> [UserProfile] {
        var seen = Set<String>()
        if let ownUid { seen.insert(ownUid) }

        var ranked: [UserProfile] = []
        for profile in ([exact].compactMap { $0 } + byName) {
            guard ranked.count < limit else { break }
            guard seen.insert(profile.id).inserted else { continue }
            ranked.append(profile)
        }
        return ranked
    }

    /// Where `uid` stands relative to `viewedBy`, given every edge that user is
    /// on. Direction comes from `Friendship.direction(for:)` rather than from
    /// which side of the pair someone landed on, which is lexicographic and
    /// arbitrary.
    nonisolated static func relationship(
        with uid: String,
        in edges: [String: Friendship],
        viewedBy ownUid: String
    ) -> Relationship {
        guard uid != ownUid else { return .you }
        guard let edge = edges[uid] else { return .none }

        switch edge.direction(for: ownUid) {
        case .mutual:   return .friends
        case .sent:     return .outgoing
        case .received: return .incoming
        }
    }

    // MARK: - Actions

    /// The controls a relationship offers, in display order.
    func actions(for relationship: Relationship) -> [Action] {
        switch relationship {
        case .none:     [.add]
        case .incoming: [.accept, .decline]
        case .outgoing: [.cancel]
        case .friends:  [.remove]
        case .you:      []
        }
    }

    /// Performs `action` against `uid`.
    ///
    /// The friendship ID is recomputed from the pair rather than carried on the
    /// row: it's derived, and the create rule refuses any document whose ID
    /// isn't exactly this, so there's nothing a stored copy could add.
    func perform(_ action: Action, on uid: String) async {
        guard pendingUid == nil else { return }
        guard let ownUid = friendService.currentUserId else { return }

        pendingUid = uid
        defer { pendingUid = nil }

        let friendshipId = Friendship.id(for: ownUid, uid)

        do {
            switch action {
            case .add:     try await friendService.sendRequest(to: uid)
            case .accept:  try await friendService.acceptRequest(friendshipId)
            case .decline: try await friendService.declineRequest(friendshipId)
            case .cancel:  try await friendService.cancelRequest(friendshipId)
            case .remove:  try await friendService.removeFriend(friendshipId)
            }
            // The listeners re-emit what the server actually stored, so there's
            // nothing to apply optimistically here.
        } catch {
            // `FriendService` already reported it; `errorMessage` is mirrored.
        }
    }

    /// Whether `uid`'s controls should be inert because someone else's write is
    /// in flight.
    func isBlocked(_ uid: String) -> Bool {
        pendingUid != nil && pendingUid != uid
    }

    func dismissError() {
        errorMessage = nil
    }

    /// Re-attach now instead of waiting out the backoff.
    func retry() {
        friendService.retry()
    }

    // MARK: - Home court

    /// The court a profile calls home, or `nil` when none is set — or when the
    /// stored ID is no longer in the bundled dataset, which `homeCourtName`
    /// reports rather than hiding. Same resolution `ProfileViewModel` applies to
    /// the signed-in user's own profile.
    private func homeCourt(for profile: UserProfile) -> Court? {
        guard let homeCourtId = profile.homeCourtId else { return nil }
        return courts.first { $0.id == homeCourtId }
    }

    func homeCourtName(for profile: UserProfile) -> String? {
        guard profile.homeCourtId != nil else { return nil }
        return homeCourt(for: profile)?.displayName ?? "Unknown court"
    }

    func homeCourtCity(for profile: UserProfile) -> String? {
        homeCourt(for: profile)?.city
    }

    // MARK: - Presentation helpers

    /// Drives the inbox badge and the tab-bar dot. Only *incoming* requests
    /// count — a request you sent isn't waiting on you.
    var unansweredCount: Int { incomingRequests.count }

    var hasUnanswered: Bool { unansweredCount > 0 }

    /// Kept to two glyphs so it fits the badge at every Dynamic Type size.
    var badgeText: String {
        unansweredCount > 9 ? "9+" : "\(unansweredCount)"
    }

    var friendsCountText: String {
        friends.count == 1 ? "1 friend" : "\(friends.count) friends"
    }

    var friendsEmptyText: String {
        "No friends yet. Search above by name or user ID to find people you play with."
    }

    var requestsEmptyText: String {
        "No requests waiting on you."
    }

    var sentEmptyText: String {
        "You haven't asked anyone yet."
    }

    var inboxEmptyText: String {
        "Nothing here yet. Friend requests land in your inbox."
    }

    func searchEmptyText(for query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return "No players match “\(trimmed)”."
    }

    /// A search failure gets its own sentence rather than `FriendService`'s
    /// banner: this one is about the `users` collection, and the banner belongs
    /// to the friendship listeners.
    private nonisolated static func searchFailureText(for error: Error) -> String {
        guard let profileError = error as? UserProfileError else {
            return "Couldn't search right now. Try again."
        }
        return UserProfileService.message(
            for: profileError,
            whileDoing: "searching for players",
            context: .load
        )
    }
}
