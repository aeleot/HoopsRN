# hoopsRN — Architecture

**Scope:** `hoopr/hooprApp.swift`, `hoopr/Services/`, `hoopr/ViewModels/`,
`hoopr/Support/FailureText.swift`, `hoopr/Support/PreferredRadiusPublisher.swift`
**Verified:** 2026-08-29 @ 4575026

How the app is assembled: who owns what, what gets injected where, and the two
orderings/boundaries that break the design if violated. Read this before
touching anything Firebase-adjacent, adding a service, or moving where an
object is constructed.

---

## Ownership and injection

`hooprApp` owns eleven services as `@StateObject` for the process lifetime and
passes them down as plain `let`s. There is no `@EnvironmentObject` anywhere —
every view model takes its dependencies through its initializer, so any of them
can be built with a stub.

| Service | Publishes | Notes |
|---|---|---|
| `AuthService` | `currentUser: AuthenticatedUser?`, `hasLoadedInitialState: Bool` | `hasLoadedInitialState` exists because Firebase restores a cached session asynchronously — session state is genuinely unknown until the first listener callback. |
| `UserProfileService` | `currentProfile: UserProfile?`, `errorMessage: String?`, `isRecovering: Bool` | `@MainActor`. Subscribes to `AuthService` itself. Owns a `ListenerSupervisor`. |
| `CourtService` | `courts: [Court]`, `loadError: String?` | Loads the bundled dataset synchronously in `init()`, sorted by `name`. A missing or undecodable `courts.json` leaves `courts` empty **and sets `loadError`** — `FindAMatchViewModel` mirrors it as `datasetError` so the map's empty state can say why rather than reading as "no courts near you". No retry: the dataset is in the app bundle, so a failure is a build problem. |
| `LocationService` | `authorizationStatus` | `CLLocationManagerDelegate` wrapper. Also owns `homeLocation`, the single anchor every distance in the app measures from. It publishes **no device coordinate**: a `userLocation` property existed but nothing ever read it — every distance goes through `homeLocation`, and the blue dot is MapKit's own `showsUserLocation`. Removed 2026-08-22 along with the `didUpdateLocations` callback that fed it; the permission request survives only so that dot can draw. |
| `GameService` | `queuedGames: [Game]`, `publicGames: [Game]`, `errorMessage: String?`, `isRecovering: Bool` | `@MainActor`. Subscribes to `AuthService` itself. Owns two session-scoped query listeners and a `ListenerSupervisor` that keys their health separately. |
| `FriendService` | `friends: [Friendship]`, `incomingRequests: [Friendship]`, `outgoingRequests: [Friendship]`, `errorMessage: String?`, `isRecovering: Bool` | `@MainActor`. Subscribes to `AuthService` itself. Two session-scoped query listeners (`uidA == me`, `uidB == me`) merged client-side, and a `ListenerSupervisor` keying their health separately. |
| `RecentCourtsStore` | `recentCourtIds: [String]` | `UserDefaults`-backed; deliberately on-device. |
| `SquadService` | `squads: [Squad]`, `incomingInvites`/`sentInvites: [SquadInvite]`, `errorMessage`, `isRecovering`, `hasLoadedSquads` | `@MainActor`. Subscribes to `AuthService` itself. **Owns two collections** — `squads` and `squadInvites` — justified because a `squadInvite` has no independent existence: it is created against a squad, consumed by a write to that same squad, and deleted in the same breath. |
| `MatchmakingService` | `myTicket: MatchTicket?`, `pool: [MatchTicket]`, `wonClaim: MatchCandidate?`, `isBackingOff: Bool` | `@MainActor`. Owns `matchTickets`, the pool listener, and **the one contested write in the app** — the claim transaction. Its retry is about contention, not network health, and is deliberately separate from the supervisor's. |
| `SeasonGameService` | `games: [SeasonGame]`, `errorMessage`, `isRecovering`, `hasLoadedGames` | `@MainActor`. Owns `seasonGames`. A `seasonGame` earns its own service where a `squadInvite` didn't: it outlives both tickets, has its own listener, and is what a squad's record is derived from. |
| `NotificationService` | `authorizationStatus: UNAuthorizationStatus?` | The only file in the app importing `UserNotifications`. **Executes a plan and decides nothing** — see the vendor boundary below. |

Twelve view models are built from them, each `@StateObject` inside the view it
backs: `RootViewModel` (from `AuthService`), `LoginViewModel` (`AuthService`),
`FindAMatchViewModel` (`CourtService` + `LocationService` + `GameService` +
`UserProfileService`), `HomeViewModel` (`AuthService` + `CourtService` +
`GameService` + `UserProfileService` + `FriendService`), `ProfileViewModel`
(`AuthService` + `UserProfileService` + `CourtService`), `LocalRunsViewModel`
(`GameService` + `CourtService` + `UserProfileService`), `FriendsViewModel`
(`FriendService` + `UserProfileService` + `CourtService` — the last one only to
name a home court on another player's profile), `CreateGameViewModel`
(`GameService`, plus the `Court` the form was opened from — the one view model
built per-presentation rather than per-screen, inside `CreateGameSheet`),
`SquadViewModel` (`SquadService` + `FriendService` + `UserProfileService` +
`CourtService`), `MatchmakingViewModel` (`MatchmakingService` +
`SeasonGameService` + `CourtService` + `SquadService` + `NotificationService`),
`GameDayViewModel` and `ResultViewModel` (both `SeasonGameService` +
`SquadService`, the latter two built per-presentation from the value being
pushed).

`LocalRunsViewModel`, `FriendsViewModel`, `FindAMatchViewModel`,
`SquadViewModel`, `GameDayViewModel` and `ResultViewModel` are where
**cross-collection joins live**. A service owns one collection and never
learns about another's: `LocalRunsViewModel` joins runs to the bundled court
dataset for its distance filter, `FriendsViewModel` joins friendship uids to
profiles for their names, and `FindAMatchViewModel` joins `GameService`'s
`queuedGames` + `publicGames` to the court dataset to colour the map's pins by
how busy each court is today — see `MAP_LAYER.md`'s `CourtHeat` section, and
`gameCountsByCourt`'s doc comment for why summing those two arrays needs a
dedup. On the Seasons side, `SquadViewModel` joins `squadInvites` to
`friendships` for the invite picker (the join that makes it a view model at
all), and `GameDayViewModel`/`ResultViewModel` join a match to both squads'
rosters and crests. Pushing any of these down into a service would give one
collection's owner a dependency on another's.

### The one deliberate exception: a write *sequence* in a view model

`MatchmakingViewModel` holds the claim → create → mark-matched sequence, and
that is more than a join — it is a cross-collection **write sequence**, which
this document otherwise puts nowhere.

It lives there because the alternative is worse. `MatchmakingService` owns
`matchTickets` and `SeasonGameService` owns `seasonGames`; services here have no
references to each other, and nothing about the sequence needs them to. One
object holding both and calling them in order costs a house-rule asterisk. One
service reaching into another would cost the house rule itself.

The **order** inside it is load-bearing: the game is written first, because it is
the durable thing and the tickets are bookkeeping. A client that dies after the
game and before the tickets leaves a game both squads can still see, and each
squad's own client closes its own ticket off its own `seasonGames` listener. The
reverse order would take two squads out of the pool with nothing to show them.

`RootViewModel` is a separate type from `RootView` specifically so the
launching/login/main gating rule can be tested without rendering.

---

## Startup order

```swift
init() {
    // Must run before any service is constructed: `AuthService.init()`
    // calls `Auth.auth()`, which traps if Firebase isn't configured yet.
    FirebaseApp.configure()

    let authService = AuthService()
    _authService = StateObject(wrappedValue: authService)
    _userProfileService = StateObject(wrappedValue: UserProfileService(authService: authService))
    _gameService = StateObject(wrappedValue: GameService(authService: authService))
    _friendService = StateObject(wrappedValue: FriendService(authService: authService))
    _squadService = StateObject(wrappedValue: SquadService(authService: authService))
    _matchmakingService = StateObject(wrappedValue: MatchmakingService(authService: authService))
    _seasonGameService = StateObject(wrappedValue: SeasonGameService(authService: authService))
}
```

Every service that subscribes to `AuthService` is built here, in `init()`, for
the same reason the first three were. `CourtService`, `LocationService`,
`RecentCourtsStore` and `NotificationService` don't, so they stay property
initializers.

Three things are load-bearing here:

- **`FirebaseApp.configure()` runs in `hooprApp.init()`, not the `AppDelegate`.**
  `AuthService.init()` attaches a Firebase auth listener, which traps if
  Firebase hasn't been configured. The `AppDelegate` exists only as a hook for
  future APNs registration and must not configure Firebase a second time.
- **`AuthService` and `UserProfileService` are built in `init()`, not in
  property initializers.** `@StateObject`'s wrapped value is an `@autoclosure`,
  so a property initializer would defer construction; and `UserProfileService`
  needs `authService` injected, which a property initializer can't reference.
- **`UserProfileService.database` is `lazy`**, so the Firestore singleton is
  never touched before configuration either.

---

## Vendor boundary

**Firebase modules may be imported only by files in `hoopr/Services/`.** Each
service owns exactly one collection and translates SDK errors into a domain
enum before publishing anything upward.

*(This invariant used to name `UserProfileService` as the only permitted
Firestore importer. `GameService` is the second, and the rule was rewritten
rather than quietly broken — the intent was always "Firebase types never escape
the service layer", which still holds.)*

| File | Import | Owns | Exposes upward |
|---|---|---|---|
| `Services/AuthService.swift` | `FirebaseAuth` | identity | `AuthenticatedUser`, `AuthError` |
| `Services/UserProfileService.swift` | `FirebaseFirestore` | `users` | `UserProfile`, `UserProfileError` |
| `Services/GameService.swift` | `FirebaseFirestore` | `games` | `Game`, `GameError` |
| `Services/FriendService.swift` | `FirebaseFirestore` | `friendships` | `Friendship`, `FriendError` |
| `Services/SquadService.swift` | `FirebaseFirestore` | `squads`, `squadInvites` | `Squad`, `SquadInvite`, `SquadError` |
| `Services/MatchmakingService.swift` | `FirebaseFirestore` | `matchTickets` | `MatchTicket`, `MatchCandidate`, `MatchTicketError` |
| `Services/SeasonGameService.swift` | `FirebaseFirestore` | `seasonGames` | `SeasonGame`, `SeasonGameError` |
| `Services/NotificationService.swift` | `UserNotifications` | scheduled local notifications | `UNAuthorizationStatus` only |
| `Services/FirestoreFailure.swift` | `FirebaseFirestore` | *(nothing)* | `FirestoreFailure`, the shared classification |
| `Services/ListenerSupervisor.swift` | *(none)* | listener re-attach + `FailureContext` | both, to the six Firestore services |

**`UserNotifications` is a second vendor, and gets the same treatment.**
`NotificationService` is the only file that imports it, and it *executes* a plan
rather than making one: which notifications a match needs, when they fire, their
identifiers and their copy are all decided by
`SeasonGameNotifications.plan(for:opponentName:courtName:)`, a pure static over a
`SeasonGame`. A method that both decided and scheduled would be untestable here,
which is the whole reason the split exists — a notification that fires at the
wrong hour is not something a screen can show you.

`hooprApp.swift` imports `FirebaseCore` for the one `configure()` call.
`hooprTests/UserProfileTests.swift` imports `FirebaseFirestore` deliberately —
it decodes through the real `Firestore.Decoder`.

All four services translate the SDK's `NSError`s into domain enums in a
private static `mapped(_:)`. The three Firestore ones don't classify the error
themselves — they switch over `FirestoreFailure.classify(_:)`, which owns the
`FirestoreErrorDomain` guard and the code-to-case mapping once, so a newly
handled code can't be added to one service and forgotten in the other two.
*What went wrong* is decided there; *what to call it* stays per-collection.
View models then map those to user-facing strings. No
`DocumentSnapshot`, `User`, or `AuthErrorCode` reaches a model, view model, or
view.

## Shared derivations

Two pieces of duplication were pulled out and are easy to re-create by accident,
because in both cases the copies were byte-identical and each read naturally at
its own call site:

- **`Support/FailureText.swift`** — the failure sentences more than one mapper
  produces. Only genuinely shared wording belongs there; anything a single flow
  words for itself stays at its call site, because `ProfileViewModel`
  deliberately says something different from `LoginViewModel` about the same
  invalid email.
- **`Support/PreferredRadiusPublisher.swift`** — `preferredRadiusMiles`, the
  `UserProfile?` → miles pipeline (`effectivePreferredRadius`, the default while
  signed out, `removeDuplicates`, `receive(on:)`) that `FindAMatchViewModel` and
  `LocalRunsViewModel` both need. It shares the *operator chain*, not the
  subscription — each view model still subscribes to
  `userProfileService.$currentProfile` itself, so isolation is unchanged and the
  fallback rule has one home.

- **`Support/Typography.swift`'s `HooprFontMetrics`** — the size arithmetic
  behind `hooprFont`, pulled out of the private `ScaledSystemFont` modifier so
  the one question the type ramp can get wrong (*does this still fit the frame
  it's locked into?*) can be asked without hosting a view.
  `SeasonsAccessibilityTests` asks it of every fixed-size badge, and the answer
  is only worth anything because it runs the same code the modifier does rather
  than a second copy of the curve.

Both are `nonisolated` (the project defaults to `MainActor` isolation) so the
error mappers and tests can reach them off the main actor.

### Derivations mirrored across the wire

A third kind of duplication is deliberate and cannot be removed: logic that
exists **once in Swift and once in `firestore.rules`**, because the client has to
predict what the server will accept and the server cannot run Swift. These are
kept honest by tests that read the rules file as text, and they must move
together:

| Swift | Rules | What breaks if they drift |
|---|---|---|
| `Game.status(playerCount:maxPlayers:)` | the `games` status expression | A run reads `full` locally and `open` server-side. |
| `SeasonGame.reportOutcome` | `derivedResultHolds()` on `seasonGames` | A result the client shows as confirmed that the server considers disputed. |
| `MatchRules.staleClaim` | the 90-second re-claim window | A ticket the scanner thinks is claimable and the rules refuse. |
| `Squad`/`MatchTicket` bounds and allowlists | their create rules | `permission-denied` on a write the form said was fine. |

`FirestoreRulesParityTests` parses `firestore.rules` from the source tree and
fails when a mirrored constant moves on only one side. It is **not** a rules
evaluator, and says so in its own doc comment — `firestore-tests/` is.

---

## Session-scoped listeners

`UserProfileService` and `GameService` subscribe to `AuthService.$currentUser`
**themselves**, not via a view model. A view model's lifetime is tied to a screen, so driving the
listener from `ProfileViewModel` would tear it down every time the profile
closed. One listener per signed-in session means the `MainTabView` greeting and
the profile screen read the same published `currentProfile` rather than opening
separate listeners on the same document.

The `observedUID` guard is why that listener doesn't churn: Firebase re-emits
the same user on token refresh, and `handleAuthChange` returns early when the
uid is unchanged.

**Two Seasons listeners are session-scoped but not self-driving**, and the
difference is worth naming. `SeasonGameService.observe(squadIds:)` and
`MatchmakingService.startSearching(...)` both need to know *which squads are
mine*, which is `squads`' business — and a service here never learns about
another's collection. So they are pointed by a view: `SeasonsTab` calls
`observe(squadIds:)` with every squad the user is on, and `MatchmakingViewModel`
starts the pool listener for the squad its card is showing.

`seasonGames` uses `array-contains-any` rather than `array-contains` precisely
because the tab passes *all* of them — a person on two squads gets both from one
query, and screen 9's history works for a squad that isn't the primary one. The
ceiling is Firestore's ten, named in `SeasonGameService.Limit.observedSquads`
rather than left as a silent truncation.

`ProfileViewModel` mirrors `userProfileService.$errorMessage` as well as
handling its own throws, so failures the service raises on its own (profile
load, provisioning) surface on screen and not only in the log.

### Recovery

**An error delivered to a snapshot listener means that listener is already
dead.** Firestore retries transient failures internally and never surfaces them;
anything that reaches the callback is something it gave up on. Nothing
re-attaches automatically, which is how a still-building index once emptied both
Local Runs lists until the app was relaunched.

`ListenerSupervisor` is what re-attaches them. All three Firestore services own one,
hand it a weakly-captured re-attach closure, and report every listener error and
every snapshot to it. Delays escalate 2s → 5m and then repeat rather than giving
up, since the failures it exists for (an index finishing, a ruleset being
deployed) heal on their own. Returning to the foreground jumps the queue, and so
does the "Try again" button on the Local Runs banner.

It tracks health **per listener**, by key. `GameService` and `FriendService` each
run two, and other people's actions produce snapshots on the healthy one
continuously — with a single
flag, those successes would cancel the dead listener's re-attach and leave that
list permanently empty. Recovery ends only when every listener that failed has
reported back, and `errorMessage` survives until then for the same reason.

### `permission-denied` means two different things

Firestore returns the same code for "the ruleset was never deployed" and "the
rules deliberately rejected this". The error can't distinguish them; the side it
came from can, which is what `FailureContext` carries:

- A denied **read** was one of the queries shaped so it only ever asks for
  documents the read rule already admits — for `users` and `games` because the
  rule grants any signed-in user, and for `friendships` because both listeners
  filter on the caller's own uid. So the server isn't running the rules in this
  repo → the message names deployment.
- A denied **write** was already validated client-side (`Game.validate`,
  `UserProfile.validate(userName:)`), so the server rejected something the
  client believed was legal → the message describes the rejection and says
  nothing about deployment, because blaming it would hide a genuine
  authorization bug.

---

## Invariants

- `FirebaseApp.configure()` runs first in `hooprApp.init()`. Never move it to
  the `AppDelegate`, and never call it twice.
- Firebase modules are imported only under `hoopr/Services/` (plus
  `FirebaseCore` in `hooprApp`, and the test target). Adding one to a model,
  view model, or view breaks the design.
- `GameService` clears `errorMessage` on a successful snapshot **only when the
  error came from a load**. Two listeners are open and other people's joins
  produce snapshots continuously, so clearing on any success would wipe an
  action's failure off the screen milliseconds after it appeared.
- Services are constructed once in `hooprApp` and injected. Never construct one
  inside a view or view model outside a `#Preview`.
- `UserProfileService` is `@MainActor` and owns exactly one profile listener per
  session. Don't open a second listener on `users/{uid}` anywhere.
- Every snapshot callback reports to its `ListenerSupervisor` — `recordFailure`
  on an error, `recordSuccess` on a snapshot, both keyed by listener. A new
  listener that skips this is a listener that never comes back.
- A service's re-attach closure captures `self` **weakly**. The service owns the
  supervisor, so a strong capture is a cycle.
- Anything reported to the user goes through `message(for:whileDoing:context:)`
  with the context it actually came from. Passing `.write` for a read (or the
  reverse) is how a deployment problem starts reading as an auth bug.
- Combine subscriptions in view models use `sink { [weak self] … }`, not
  `assign(to:on: self)`, which would retain `self` through its own cancellable
  set. `ProfileViewModel`, `LocalRunsViewModel` and `RootViewModel` each say so
  in a comment; there are no remaining holdouts.
- **No service holds a reference to another service.** Cross-collection work is
  a view model's job — joins as a rule, and the claim → create → mark-matched
  sequence as the one named exception above.
- `UserNotifications` is imported only by `NotificationService`, and that service
  makes no decisions. Every choice about what to schedule belongs in
  `SeasonGameNotifications`, where it can be tested.
- A contested write goes through a **transaction**, not a read-then-write. The
  claim, `GameService.mutateRoster`, `SquadService.mutateRoster` and
  `SeasonGameService.reportResult` all read inside the transaction because the
  listener's copy can be stale — which is precisely the race each of them
  exists to close.
- Anything mirrored into `firestore.rules` moves on both sides in the same
  commit, and gains a parity test if it doesn't have one.

## See also

- `database/USER_PROFILE_WORKFLOW.md` — the sign-in → provisioned-profile
  sequence in full.
- `DATA_MODEL.md` — the domain types these services publish.
- `UI_SHELL.md` — what consumes each published property.
