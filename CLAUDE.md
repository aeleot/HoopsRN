# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick start

- **Read first**: [`context/INDEX.md`](context/INDEX.md) is a routing table into architecture, data model, UI structure, and more. Start there for any major change.
- **Tests**: `xcodebuild test -project hoopr.xcodeproj -scheme hoopr -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:hooprTests`
- **Run**: Open `hoopr.xcodeproj` in Xcode, select the `hoopr` scheme, pick an iOS 26.5 Simulator, Cmd+R.
- **Run a single test**: `xcodebuild test -project hoopr.xcodeproj -scheme hoopr -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:hooprTests/SuiteName/testName`

## Common commands

| Task | Command |
|---|---|
| Run all unit tests | `xcodebuild test -project hoopr.xcodeproj -scheme hoopr -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:hooprTests` |
| Run a specific test suite | `xcodebuild test -project hoopr.xcodeproj -scheme hoopr -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:hooprTests/GameTests` |
| Dry-run Firebase rules/indexes | `npm install -g firebase-tools && firebase login && firebase deploy --only firestore:rules,firestore:indexes --dry-run` |
| Check if docs are stale | `python3 tools/check_context_drift.py` |
| Regenerate court dataset | `python3 tools/build_courts.py` or `python3 tools/fetch_city_courts.py` |

**Important:** Don't run `xcodebuild test` without `-only-testing:hooprTests` — the UI test runner currently fails to launch (`RequestDenied` from SpringBoard), which masks real failures.

## Architecture overview

hoopsRN is a **SwiftUI iOS app** (deployment target iOS 26.5) that finds pickup basketball games via Firebase (Auth + Firestore). The app is well-documented — see the context dictionary below for detailed architecture, data model, UI structure, etc.

### Service layer owns Firebase

- **One service per collection:** `UserProfileService` (profiles), `GameService` (games), `FriendService` (friendships). Each owns a Firestore query listener, translates SDK errors to a domain enum, and publishes clean models upward.
- **`AuthService`** bootstraps and publishes the current user. `UserProfileService`, `GameService`, and `FriendService` all subscribe to it (internally, no view-level dependency).
- **`CourtService`** loads the bundled court dataset synchronously (no Firestore).
- **`LocationService`** wraps `CLLocationManagerDelegate`, publishes `homeLocation` (the anchor for all distances in the app), and owns the location permission request.
- **`RecentCourtsStore`** is `UserDefaults`-backed, deliberately on-device.

**Vendor boundary:** Firebase imports are **only in `hoopr/Services/`**. Views and view models never touch Firebase types.

### Startup order (load-bearing)

```swift
init() {
    FirebaseApp.configure()  // Must run before AuthService.init()
    let authService = AuthService()
    _authService = StateObject(wrappedValue: authService)
    // UserProfileService, GameService, FriendService follow
}
```

Three things break the design if violated:
1. `FirebaseApp.configure()` runs in `hooprApp.init()`, not `AppDelegate` — `AuthService.init()` attaches a listener and will trap if Firebase isn't configured.
2. `AuthService` and services that depend on it are built in `init()`, not property initializers — property initializers defer construction, breaking dependency order.
3. `UserProfileService.database` is `lazy` so the Firestore singleton is never touched before configuration.

### Cross-collection joins live in view models

`LocalRunsViewModel`, `FriendsViewModel`, and `FindAMatchViewModel` join data from multiple services — the services themselves have no dependencies on each other. For example:
- `LocalRunsViewModel` joins runs to the bundled court dataset for distance filtering.
- `FriendsViewModel` joins friendship UIDs to profiles for names.
- `FindAMatchViewModel` colours map pins by court busyness (summing queued and public games, deduped by court ID).

Pushing joins into a service layer would create unwanted collection-to-collection dependencies.

### No `@EnvironmentObject` — explicit dependency injection

Every view model takes its dependencies through `init()`, never via environment. This makes every view model and every dependency testable in isolation.

## Context dictionary

The codebase has a published **context dictionary** at [`context/INDEX.md`](context/INDEX.md) that routes to specific docs by task:

| If you're changing… | Read |
|---|---|
| Firebase listener, error handling | [`ARCHITECTURE.md`](context/ARCHITECTURE.md) |
| Firestore schema, write rules, stored fields | [`database/DATABASE_SCHEMA.md`](context/database/DATABASE_SCHEMA.md) |
| Profile fields or sign-in flow | [`database/USER_PROFILE_WORKFLOW.md`](context/database/USER_PROFILE_WORKFLOW.md) |
| Games, rosters, run scheduling | [`database/DATABASE_SCHEMA.md`](context/database/DATABASE_SCHEMA.md), [`UI_SHELL.md`](context/UI_SHELL.md) |
| Friendships, requests, player search | [`database/DATABASE_SCHEMA.md`](context/database/DATABASE_SCHEMA.md), [`UI_SHELL.md`](context/UI_SHELL.md) |
| Map behaviour, bottom sheet | [`MAP_LAYER.md`](context/MAP_LAYER.md) |
| Court data or adding a city | [`COURT_DATASET.md`](context/COURT_DATASET.md) |
| Navigation, screens, styling | [`UI_SHELL.md`](context/UI_SHELL.md) |
| Domain types, error cases | [`DATA_MODEL.md`](context/DATA_MODEL.md) |
| Build settings, dependencies, test coverage | [`BUILD_AND_CONFIG.md`](context/BUILD_AND_CONFIG.md) |
| Code vs. docs conflicts | [`GAPS.md`](context/GAPS.md) — **always read this before trusting a code comment** |

**Before refreshing docs:** Run `python3 tools/check_context_drift.py` to see which docs are stale. It diffs owned scopes against the working tree and reports staleness.

## Key patterns and constraints

### Models are in `hoopr/Models/`
Domain types: `Game`, `UserProfile`, `Friendship`, `Court`, `GameStatus`, error enums. No Firestore types escape the service layer.

### Services are in `hoopr/Services/`
Query listeners, error translation, and state publication. Subscribe to `AuthService` internally; publish clean models. `ListenerSupervisor` recovers from transient network errors per listener.

### ViewModels are in `hoopr/ViewModels/`
Built per-screen or per-presentation (e.g., `CreateGameViewModel` only in `CreateGameSheet`). No `@EnvironmentObject` — all dependencies injected in `init()`. Safe to test with stubs.

### Views are in `hoopr/Views/`
Organized by feature (e.g., `Views/Friends/`, `Views/Map/`). Navigate with `NavigationStack`, present sheets with `sheet(item:)`, never with `isPresented`.

### Styling is centralized
`Theme.swift` (colours), `Typography.swift` (fonts, sizes). Both use `hoopr`-prefixed identifiers (historical prefix, survives the 2026-08-15 product rename to hoopsRN).

### Firebase errors are service concerns
A `ListenerSupervisor` in each service retries transient errors (network, quota). Persistent errors (`permission-denied`, `not-found`) surface as a domain enum and stop the listener. View models publish clean error messages, never raw Firebase text.

### Location and distance
Every distance in the app measures from `homeLocation`, not device location. The `CLLocationManagerDelegate` remains active only so MapKit's blue dot can draw. Removed the `userLocation` property in 2026-08-22 — nothing ever read it.

### Firestore rules and indexes must be deployed
Until `firestore.rules` is deployed, writes fail with `permission-denied` — the app surfaces "Not allowed to save yet". Run `firebase deploy --only firestore:rules,firestore:indexes --dry-run` to compile without deploying.

### Bundle ID is load-bearing
`Big-Boss-LLC.hoopr` binds to the Firebase app `hoopsrn-4f1e9`. Changing it requires a new app in the Firebase console and a fresh `GoogleService-Info.plist` — it orphans existing installs.

### Tests are unit-focused, UI tests skip
`hooprTests/` has 120 real test methods across 11 suites. `hooprUITests` fails to launch on this project (SpringBoard `RequestDenied`), so don't run it. The fixture data in test files is non-scaffolding — it's either real Firestore documents or realistic test doubles.

## Token efficiency

To reduce token usage in future sessions:

1. **Refer to context docs by name** — if you're touching the map layer, say "See `MAP_LAYER.md`" instead of asking me to re-derive it.
2. **Trust the existing architecture** — the service/view-model/view split is stable. Don't ask about it again; just follow it.
3. **Link short-form to scope.** Instead of naming all affected files, say "in the Services layer" or "in the `Views/Map/` view tree."
4. **Reuse test patterns** — the test suites follow a consistent pattern (given/when/then mocks, property assertions). Copy from `GameTests.swift` or `FriendsViewModelTests.swift` rather than asking for test structure.
5. **Check INDEX.md first.** If you're unsure which doc to read, INDEX.md routes to the right one. Let it guide you before asking clarifying questions.
