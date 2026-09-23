import Combine
import CoreLocation
import Foundation

/// Backs the Local Runs tab: the runs you're in, and the discoverable ones
/// within your preferred radius.
///
/// The distance filter lives here rather than in `GameService` because it's a
/// join across two sources — Firestore holds the run, the bundled dataset holds
/// the court's coordinates. Same division as `FindAMatchViewModel`, which does
/// its geo math over `CourtService` while the profile listener stays in
/// `UserProfileService`.
@MainActor
final class LocalRunsViewModel: ObservableObject {
    /// A run with its court resolved, ready to render. Distance is computed
    /// once per rebuild, never during scroll.
    /// `nonisolated` for the same reason `Action` below is: it's a plain value
    /// with no isolation to protect, and leaving it on the main actor would put
    /// `friendsHereText` and the rest of its derivations out of reach of a test.
    nonisolated struct Listing: Identifiable, Equatable {
        let game: Game
        /// `nil` when the stored `courtId` no longer matches a court in the
        /// bundled dataset — the run is still shown, since you're committed to
        /// it, but it can't be placed on the map.
        let court: Court?
        let distanceMeters: CLLocationDistance?
        /// Friends already on this run, confirmed or waitlisted. Resolved once
        /// per rebuild for the same reason `distanceMeters` is — never per row
        /// while the list scrolls.
        let friendIds: [String]

        /// `friendIds` defaults so `HomeViewModel`, which builds a `Listing` for
        /// its own read-only next-run card, doesn't have to answer a question
        /// that card never asks.
        init(
            game: Game,
            court: Court?,
            distanceMeters: CLLocationDistance?,
            friendIds: [String] = []
        ) {
            self.game = game
            self.court = court
            self.distanceMeters = distanceMeters
            self.friendIds = friendIds
        }

        var id: String { game.id }

        /// `displayName`, not `name`: every other surface in the app strips the
        /// dataset's "Basketball Court" boilerplate, and a card that didn't
        /// would disagree with the map row the run was started from.
        var courtName: String { court?.displayName ?? "Unknown court" }

        var distanceText: String? {
            distanceMeters.map(Distance.text)
        }

        /// `nil` rather than "0 friends", so the card renders nothing at all
        /// when none of yours are on a run — the same absent-not-empty shape
        /// `distanceText` takes.
        var friendsHereText: String? {
            switch friendIds.count {
            case 0:          nil
            case 1:          "1 friend here"
            case let count:  "\(count) friends here"
            }
        }
    }

    /// What the primary button on a card does, given who's looking at it.
    ///
    /// `nonisolated` because `action(for:currentUserId:)` is: a pure rule that
    /// returns an actor-isolated type can't actually be used from a nonisolated
    /// caller, which is the whole point of extracting it.
    nonisolated enum Action: Equatable {
        case join
        case joinWaitlist
        case leave
        case cancel
        /// The host of a run they can't leave, or a state with nothing to
        /// offer — the card renders a label instead of a button.
        case none

        var title: String {
            switch self {
            case .join:         "Join"
            case .joinWaitlist: "Join waitlist"
            case .leave:        "Leave"
            case .cancel:       "Cancel run"
            case .none:         ""
            }
        }

        /// Leaving and cancelling both take something away, so they read in
        /// the app's error colour rather than its brand one.
        var isDestructive: Bool {
            self == .leave || self == .cancel
        }
    }

    @Published private(set) var queued: [Listing] = []
    @Published private(set) var nearby: [Listing] = []
    @Published private(set) var errorMessage: String?

    /// A listener died and `GameService` is re-attaching it. Distinguishes a
    /// broken list from an empty one, and is what puts "Try again" on the
    /// banner — without it the automatic retry is invisible and the lists just
    /// look empty, which is how the original failure went unnoticed.
    @Published private(set) var isRecovering = false

    /// Whether the games listener has delivered its first snapshot.
    ///
    /// The screen shows one merged timeline now, and an empty timeline has two
    /// very different meanings: *nobody is playing tonight* and *we haven't
    /// looked yet*. `GameService` has carried the answer all along and this
    /// republishes it — the same value `FindAMatchViewModel` already consumes,
    /// not a new read.
    @Published private(set) var hasLoaded = false

    /// The radius the public list was actually built with, so the empty state
    /// can name the real number instead of restating a constant.
    @Published private(set) var radiusMiles = UserProfile.defaultPreferredRadius

    /// The run with a write in flight, if any. One at a time: the button that
    /// started it shows a spinner and every other card's button is disabled, so
    /// a double tap can't queue two conflicting transactions.
    ///
    /// Shared by the roster writes and by `complete(_:)`, which isn't one — a
    /// card's two host controls sit side by side after tip-off, and completing
    /// a run while its cancel is still in flight would race a write against a
    /// delete.
    @Published private(set) var pendingGameId: String?

    private let gameService: GameService
    private var cancellables = Set<AnyCancellable>()

    private var queuedGames: [Game] = []
    private var publicGames: [Game] = []
    private var courtsByID: [String: Court] = [:]
    /// The raw edges, not the uids they resolve to. Which uid is *the other
    /// one* depends on who's signed in, and that answer is read per rebuild
    /// rather than captured here — see `rebuild()`.
    private var friendships: [Friendship] = []

    init(
        gameService: GameService,
        courtService: CourtService,
        userProfileService: UserProfileService,
        friendService: FriendService
    ) {
        self.gameService = gameService

        // `sink` with a weak capture rather than `assign(to:on: self)`, which
        // would retain self through self's own cancellable set.
        gameService.$queuedGames
            .receive(on: DispatchQueue.main)
            .sink { [weak self] games in
                self?.queuedGames = games
                self?.rebuild()
            }
            .store(in: &cancellables)

        gameService.$publicGames
            .receive(on: DispatchQueue.main)
            .sink { [weak self] games in
                self?.publicGames = games
                self?.rebuild()
            }
            .store(in: &cancellables)

        // Indexed once per dataset load rather than searched per run: the
        // public list can hold a hundred runs, and a linear scan of 214 courts
        // for each of them is work with no purpose.
        courtService.$courts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] courts in
                self?.courtsByID = Dictionary(
                    courts.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
                self?.rebuild()
            }
            .store(in: &cancellables)

        userProfileService.$currentProfile
            .preferredRadiusMiles
            .sink { [weak self] radius in
                self?.radiusMiles = radius
                self?.rebuild()
            }
            .store(in: &cancellables)

        // The cross-collection join `plans/FRIENDS.md` §4 puts here rather than
        // in either service: `GameService` holds the rosters, `FriendService`
        // holds the edges, and neither learns about the other. Live, so a
        // friend joining a run you're looking at updates the card without a
        // refresh.
        friendService.$friends
            .receive(on: DispatchQueue.main)
            .sink { [weak self] friendships in
                self?.friendships = friendships
                self?.rebuild()
            }
            .store(in: &cancellables)

        gameService.$errorMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.errorMessage = message
            }
            .store(in: &cancellables)

        gameService.$isRecovering
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecovering in
                self?.isRecovering = isRecovering
            }
            .store(in: &cancellables)

        gameService.$hasLoadedGames
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] hasLoaded in
                self?.hasLoaded = hasLoaded
            }
            .store(in: &cancellables)
    }

    // MARK: - Derivation

    private func rebuild(now: Date = Date()) {
        let origin = LocationService.homeLocation
        let radiusMeters = Distance.meters(miles: radiusMiles)
        // Read per rebuild rather than captured once, the same way
        // `HomeViewModel` reads the location anchor: a session that signs in
        // after this view model is built would otherwise resolve every
        // friendship against a nil uid and never recover.
        let friendUids = Self.friendUids(from: friendships, currentUserId: currentUserId)

        // The query's cutoff was fixed when its listener attached; re-applying
        // it here is what retires a run during a long-lived session.
        queued = queuedGames
            .filter { $0.isVisible(at: now) }
            .map { listing(for: $0, from: origin, friendUids: friendUids) }

        let joinedIDs = Set(queuedGames.map(\.id))

        nearby = publicGames
            .filter { game in
                // Runs already in the queued section don't repeat here.
                game.isVisible(at: now) && !joinedIDs.contains(game.id)
            }
            .map { listing(for: $0, from: origin, friendUids: friendUids) }
            .filter { listing in
                // A run whose court can't be resolved has no distance, so it
                // can't be shown to be in range — the opposite call from the
                // queued list, where you're already committed.
                guard let distance = listing.distanceMeters else { return false }
                return distance <= radiusMeters
            }
    }

    private func listing(
        for game: Game,
        from origin: CLLocationCoordinate2D,
        friendUids: Set<String>
    ) -> Listing {
        let court = courtsByID[game.courtId]
        return Listing(
            game: game,
            court: court,
            distanceMeters: court.map { Distance.between(origin, $0.coordinate) },
            friendIds: Self.friendIds(on: game, friendUids: friendUids)
        )
    }

    /// Who you're actually friends with, from the edges `FriendService`
    /// publishes.
    ///
    /// `nonisolated static` for the reason `action(for:currentUserId:)` is, and
    /// it earns it: a friendship stores *both* participants, so the obvious
    /// union of `uidA`/`uidB` includes you — and a run you're on would then
    /// count you as one of your own friends. Resolving each edge from your side
    /// is what avoids that, and it's only checkable at all because the rule is
    /// a free function over plain values.
    ///
    /// Signed out reads as no friends rather than trapping, matching
    /// `action(for:currentUserId:)`'s treatment of a nil uid.
    nonisolated static func friendUids(
        from friendships: [Friendship],
        currentUserId uid: String?
    ) -> Set<String> {
        guard let uid else { return [] }
        return Set(friendships.map { $0.otherUid(than: uid) })
    }

    /// Which of your friends are already on a run.
    ///
    /// **Both rosters**, because a friend on the waitlist is the same signal as
    /// a friend holding a spot — you'd be turning up to the same court either
    /// way. Sorted, so an identical rebuild can't reorder a name later phases
    /// may want to render.
    ///
    /// **This widens nothing.** It reads the roster of a run already on screen
    /// and already readable by this account. A friend's *private* run stays
    /// invisible — that needs an authorization design `plans/FRIENDS.md` §4
    /// defers, not a client-side cross-reference.
    nonisolated static func friendIds(on game: Game, friendUids: Set<String>) -> [String] {
        guard !friendUids.isEmpty else { return [] }
        return Set(game.playerIds + game.queuedPlayerIds)
            .intersection(friendUids)
            .sorted()
    }

    // MARK: - Actions

    var currentUserId: String? { gameService.currentUserId }

    func isHost(_ listing: Listing) -> Bool {
        listing.game.isHost(currentUserId)
    }

    func isWaitlisted(_ listing: Listing) -> Bool {
        listing.game.hasWaitlisted(currentUserId)
    }

    func action(for listing: Listing) -> Action {
        Self.action(for: listing.game, currentUserId: currentUserId)
    }

    /// What the primary button does, given who's looking at the run.
    ///
    /// `nonisolated static` and pure so the map's court card can resolve the
    /// same rule without a second copy — two screens offering different buttons
    /// for the same run would be a real bug, and the previous shape made that
    /// only avoidable by discipline. Being pure is also what finally makes it
    /// testable; `GAPS.md` listed it as uncovered.
    ///
    /// Order matters. Hosting outranks membership because a host is always on
    /// their own roster, so checking `hasPlayer` first would offer them "Leave"
    /// for a run only they can cancel.
    nonisolated static func action(for game: Game, currentUserId uid: String?) -> Action {
        if game.isHost(uid) { return .cancel }
        if game.hasPlayer(uid) || game.hasWaitlisted(uid) { return .leave }
        return game.isFull ? .joinWaitlist : .join
    }

    func canComplete(_ listing: Listing, now: Date = Date()) -> Bool {
        Self.canComplete(listing.game, currentUserId: currentUserId, now: now)
    }

    /// Whether the host may mark this run finished.
    ///
    /// **Not an `Action` case, deliberately.** `action(for:currentUserId:)`
    /// returns exactly one thing to offer, and a host already gets `.cancel`;
    /// after tip-off both have to be available at once, which one-of-N can't
    /// express. That function is also shared with `FindAMatchViewModel` for the
    /// map's court card, so a new case would change a second screen for a
    /// control only the Runs tab wants.
    ///
    /// Three conditions, and the rule enforces all three server-side too — this
    /// only decides whether to *show* the control:
    ///
    /// - **The host's alone.** Same shape as cancelling.
    /// - **Not before tip-off.** `>=` rather than `>`: a run is under way the
    ///   instant it starts, and there's nothing to gain from a minute's grace.
    ///   This is the one condition that isn't in the rule — nothing server-side
    ///   forbids completing a run early, and the streak maths reads
    ///   `completedAt`, not `scheduledTime`. It's a UI judgement, not a
    ///   guarantee.
    /// - **Not already completed**, which is what makes a double tap a no-op
    ///   locally instead of a write the rule refuses.
    ///
    /// **The roster isn't consulted.** There's no attendance concept in the
    /// schema, so a completion claims only that the run happened — a host who
    /// turned up alone may record it, and deliberately so. Adding a floor here
    /// would invent a guarantee the server doesn't make.
    ///
    /// `nonisolated static` and pure, like every other rule on this type: it's
    /// the only part of completion that can be tested at all, since nothing in
    /// this suite stands up a service.
    nonisolated static func canComplete(
        _ game: Game,
        currentUserId uid: String?,
        now: Date
    ) -> Bool {
        game.isHost(uid) && now >= game.scheduledTime && game.status != .completed
    }

    func perform(_ action: Action, on listing: Listing) async {
        guard pendingGameId == nil, action != .none else { return }

        pendingGameId = listing.id
        defer { pendingGameId = nil }

        do {
            switch action {
            case .join, .joinWaitlist:
                try await gameService.joinGame(id: listing.id)
            case .leave:
                try await gameService.leaveGame(id: listing.id)
            case .cancel:
                try await gameService.cancelGame(id: listing.id)
            case .none:
                break
            }
            // The listener re-emits the roster the server actually stored, so
            // there's nothing to apply optimistically here.
        } catch {
            // `GameService` already reported it; `errorMessage` is mirrored.
        }
    }

    /// Marks a run finished.
    ///
    /// Separate from `perform(_:on:)` because completion isn't an `Action` —
    /// see `canComplete(_:currentUserId:now:)` — but it shares `pendingGameId`
    /// with it on purpose: one write per card at a time, whichever kind, so
    /// completing can't race the cancel sitting next to it.
    ///
    /// The run disappears from both lists once the listener echoes the write:
    /// `Game.isVisible(at:)` excludes `completed`, so `rebuild()` drops it.
    /// That's the run moving to the Home stats card, not a deletion — which is
    /// what the confirmation dialog on the card is there to set up.
    func complete(_ listing: Listing) async {
        guard pendingGameId == nil else { return }

        pendingGameId = listing.id
        defer { pendingGameId = nil }

        do {
            try await gameService.completeGame(id: listing.id)
        } catch {
            // `GameService` already reported it; `errorMessage` is mirrored.
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    /// Re-attach now instead of waiting out the backoff.
    func retry() {
        gameService.retry()
    }

    // MARK: - The timeline

    /// One run on the board, and whether you're on it.
    ///
    /// The tab used to draw two collapsible sections — *Queued Games* and
    /// *Public Games* — and that split cost the whole first viewport: two
    /// headers, two count capsules, two chevrons and a rule, with the first
    /// `Join` around 240pt down the page. The sections are now one list
    /// ordered by tip-off, and `isYours` is what the split used to say.
    nonisolated struct TimelineEntry: Identifiable, Equatable {
        let listing: Listing
        /// You're on this run's roster — confirmed or waitlisted. Drawn as a
        /// rail down the card's leading edge rather than as a section.
        let isYours: Bool

        var id: String { listing.id }
    }

    /// Every run you can see tonight, soonest first.
    var timeline: [TimelineEntry] {
        Self.timeline(queued: queued, nearby: nearby)
    }

    /// Merges the two lists into one board.
    ///
    /// **`queued` is walked first, and that is the whole correctness of this
    /// function.** A run you host publicly arrives on *both* listeners, so the
    /// same game appears in both arrays; taking `queued` first means the
    /// duplicate is dropped from `nearby` and the surviving entry is the one
    /// marked `isYours`. Walking `nearby` first would render your own run as a
    /// stranger's — with a `Join` button on a run you are already on.
    ///
    /// Ties break on id, not on array order: two runs at the same tip-off
    /// would otherwise swap places between rebuilds while showing identical
    /// times, the same reason `HomeViewModel.rankHotCourts` breaks ties on
    /// name.
    nonisolated static func timeline(
        queued: [Listing],
        nearby: [Listing]
    ) -> [TimelineEntry] {
        var seen = Set<String>()
        var entries: [TimelineEntry] = []

        for listing in queued where seen.insert(listing.id).inserted {
            entries.append(TimelineEntry(listing: listing, isYours: true))
        }
        for listing in nearby where seen.insert(listing.id).inserted {
            entries.append(TimelineEntry(listing: listing, isYours: false))
        }

        return entries.sorted {
            let left = $0.listing.game.scheduledTime
            let right = $1.listing.game.scheduledTime
            return left == right ? $0.id < $1.id : left < right
        }
    }

    // MARK: - Presentation helpers

    /// The hero's number: how many runs are on the board at all.
    var timelineCount: Int { timeline.count }

    /// The words beside the hero's number — "2 games on the schedule".
    ///
    /// *Schedule*, not *tonight*: a run can be booked up to
    /// `Game.schedulingWindow` ahead, so the board is whatever is coming up.
    /// It's also the player's word for it — you check the schedule.
    nonisolated static func scheduleText(count: Int) -> String {
        count == 1 ? "game on the schedule" : "games on the schedule"
    }

    /// The band's eyebrow.
    var eyebrowText: String {
        Self.eyebrowText(tipOffs: timeline.map(\.listing.game.scheduledTime), now: Date())
    }

    /// "Tonight" while nothing on the board is later than today, "Coming up"
    /// once anything is.
    ///
    /// The band used to say "Tonight" unconditionally, which was wrong for any
    /// board holding tomorrow's run. It doesn't carry the radius either: only
    /// the public half is built with it — a run you're on is listed however far
    /// away it is — so "Within 14 miles" over the count wasn't true of the
    /// board. The empty board still names the radius, which is where it's the
    /// answer.
    ///
    /// Tested against the start of tomorrow rather than for *today*, so a run
    /// that tipped off late last night and is still inside
    /// `Game.visibilityGrace` doesn't turn the board into "Coming up".
    nonisolated static func eyebrowText(
        tipOffs: [Date],
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else {
            return "Tonight"
        }
        return tipOffs.contains { $0 >= tomorrow } ? "Coming up" : "Tonight"
    }

    /// Whether you hold a place on any run on the board — what the band's
    /// rail marks, the same rail `GameCard` draws down each of those runs.
    var hasRosterSpot: Bool { !queued.isEmpty }

    /// The line under the hero: where you stand, in a player's words.
    var rosterText: String {
        let waitlisted = queued.filter(isWaitlisted).count
        return Self.rosterText(
            suitedUp: queued.count - waitlisted,
            waitlisted: waitlisted,
            onSchedule: timelineCount
        )
    }

    /// Where you stand on the board.
    ///
    /// It read "you're in 2 · within 14 miles" — lower-case, and "in" what?
    /// It now says it the way a player would, and it tells a spot from a place
    /// on the waitlist, because the rail marks both and only one of them means
    /// you're playing.
    ///
    /// "Both" and "all" when every run on the board is yours: "2 games on the
    /// schedule — you're suited up for 2" says the number twice.
    nonisolated static func rosterText(suitedUp: Int, waitlisted: Int, onSchedule: Int) -> String {
        guard suitedUp > 0 else {
            return waitlisted > 0 ? "You're on the waitlist for \(waitlisted)" : "You're a free agent"
        }

        let suited: String
        if suitedUp == onSchedule {
            switch onSchedule {
            case 1:  suited = "You're suited up"
            case 2:  suited = "You're suited up for both"
            default: suited = "You're suited up for all \(onSchedule)"
            }
        } else {
            suited = "You're suited up for \(suitedUp)"
        }

        return waitlisted > 0 ? "\(suited) · waitlisted for \(waitlisted)" : suited
    }

    /// What the board says when the listener has answered and there is
    /// genuinely nothing on. Distinct from "still loading", which the tab
    /// renders separately.
    var emptyBoardText: String {
        "No runs within \(Int(radiusMiles)) miles tonight."
    }

    var queuedCountText: String {
        queued.count == 1 ? "1 run" : "\(queued.count) runs"
    }

    var nearbyCountText: String {
        nearby.count == 1 ? "1 run" : "\(nearby.count) runs"
    }

    var queuedEmptyText: String {
        "Join a public run below, or start your own from the Court Map."
    }

    var nearbyEmptyText: String {
        "No public runs within \(Int(radiusMiles)) miles. Start one from the Court Map."
    }
}
