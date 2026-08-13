# Hoopr — Architecture

**Scope:** `hoopr/hooprApp.swift`, `hoopr/Services/`, `hoopr/ViewModels/`
**Verified:** 2026-08-13 @ map-tab

How the app is assembled: who owns what, what gets injected where, and the two
orderings/boundaries that break the design if violated. Read this before
touching anything Firebase-adjacent, adding a service, or moving where an
object is constructed.

---

## Ownership and injection

`hooprApp` owns six services as `@StateObject` for the process lifetime and
passes them down as plain `let`s. There is no `@EnvironmentObject` anywhere —
every view model takes its dependencies through its initializer, so any of them
can be built with a stub.

| Service | Publishes | Notes |
|---|---|---|
| `AuthService` | `currentUser: AuthenticatedUser?`, `hasLoadedInitialState: Bool` | `hasLoadedInitialState` exists because Firebase restores a cached session asynchronously — session state is genuinely unknown until the first listener callback. |
| `UserProfileService` | `currentProfile: UserProfile?`, `errorMessage: String?` | `@MainActor`. Subscribes to `AuthService` itself. |
| `CourtService` | `courts: [Court]`, `loadError: String?` | Loads the bundled dataset synchronously in `init()`. |
| `LocationService` | `userLocation: CLLocationCoordinate2D?`, `authorizationStatus` | `CLLocationManagerDelegate` wrapper. Also owns `homeLocation`, the single anchor every distance in the app measures from. |
| `GameService` | `queuedGames: [Game]`, `publicGames: [Game]`, `errorMessage: String?` | `@MainActor`. Subscribes to `AuthService` itself. Owns two session-scoped query listeners. |
| `RecentCourtsStore` | `recentCourtIds: [String]` | `UserDefaults`-backed; deliberately on-device. |

Four view models are built from them, each `@StateObject` inside the view it
backs: `RootViewModel` (from `AuthService`), `LoginViewModel` (`AuthService`),
`FindAMatchViewModel` (`CourtService` + `LocationService`), `ProfileViewModel`
(`AuthService` + `UserProfileService` + `CourtService`).

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

`hooprApp.swift` imports `FirebaseCore` for the one `configure()` call.
`hooprTests/UserProfileTests.swift` imports `FirebaseFirestore` deliberately —
it decodes through the real `Firestore.Decoder`.

All three services translate the SDK's `NSError`s into domain enums in a
private static `mapped(_:)`; view models then map those to user-facing strings. No
`DocumentSnapshot`, `User`, or `AuthErrorCode` reaches a model, view model, or
view.

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
- Combine subscriptions in view models use `sink { [weak self] … }`, not
  `assign(to:on: self)`, which would retain `self` through its own cancellable
  set. `ProfileViewModel` says so in a comment; `RootViewModel` and
  `FindAMatchViewModel` don't follow it — see `GAPS.md`.

## See also

- `database/USER_PROFILE_WORKFLOW.md` — the sign-in → provisioned-profile
  sequence in full.
- `DATA_MODEL.md` — the domain types these services publish.
- `UI_SHELL.md` — what consumes each published property.
