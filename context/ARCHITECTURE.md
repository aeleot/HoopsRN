# hoopsRN — Architecture

**Scope:** `hoopr/hooprApp.swift`, `hoopr/Services/`, `hoopr/ViewModels/`,
`hoopr/Support/FailureText.swift`, `hoopr/Support/PreferredRadiusPublisher.swift`
**Verified:** 2026-08-26 @ 8ad0041

How the app is assembled: who owns what, what gets injected where, and the two
orderings/boundaries that break the design if violated. Read this before
touching anything Firebase-adjacent, adding a service, or moving where an
object is constructed.

---

## Ownership and injection

`hooprApp` owns seven services as `@StateObject` for the process lifetime and
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

Seven view models are built from them, each `@StateObject` inside the view it
backs: `RootViewModel` (from `AuthService`), `LoginViewModel` (`AuthService`),
`FindAMatchViewModel` (`CourtService` + `LocationService` + `GameService` +
`UserProfileService`), `HomeViewModel` (`AuthService` + `CourtService` +
`GameService` + `UserProfileService` + `FriendService`), `ProfileViewModel`
(`AuthService` + `UserProfileService` + `CourtService`), `LocalRunsViewModel`
(`GameService` + `CourtService` + `UserProfileService`), `FriendsViewModel`
(`FriendService` + `UserProfileService` + `CourtService` — the last one only to
name a home court on another player's profile), and `CreateGameViewModel`
(`GameService`, plus the `Court` the form was opened from — the one view model
built per-presentation rather than per-screen, inside `CreateGameSheet`).

`LocalRunsViewModel`, `FriendsViewModel` and `FindAMatchViewModel` are where
**cross-collection joins live**. A service owns one collection and never
learns about another's: `LocalRunsViewModel` joins runs to the bundled court
dataset for its distance filter, `FriendsViewModel` joins friendship uids to
profiles for their names, and `FindAMatchViewModel` joins `GameService`'s
`queuedGames` + `publicGames` to the court dataset to colour the map's pins by
how busy each court is today — see `MAP_LAYER.md`'s `CourtHeat` section, and
`gameCountsByCourt`'s doc comment for why summing those two arrays needs a
dedup. Pushing any of these down into a service would give one collection's
owner a dependency on another's.

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
}
```

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
| `Services/FirestoreFailure.swift` | `FirebaseFirestore` | *(nothing)* | `FirestoreFailure`, the shared classification |
| `Services/ListenerSupervisor.swift` | *(none)* | listener re-attach + `FailureContext` | both, to the three Firestore services |

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

Both are `nonisolated` (the project defaults to `MainActor` isolation) so the
error mappers and tests can reach them off the main actor.

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

## See also

- `database/USER_PROFILE_WORKFLOW.md` — the sign-in → provisioned-profile
  sequence in full.
- `DATA_MODEL.md` — the domain types these services publish.
- `UI_SHELL.md` — what consumes each published property.
