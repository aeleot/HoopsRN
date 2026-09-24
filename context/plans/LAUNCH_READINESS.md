# Plan — Launch Readiness

**Status:** proposed — five open items, none of them a submission blocker
**Drafted:** 2026-09-20 · **Pruned:** 2026-09-24 (the icon, deployment
target, device family, permission string and rules coverage all shipped
2026-09-20 and were removed — they're in git history)
**Touches:** `hoopr.xcodeproj/project.pbxproj`, `hoopr/Views/Tabs/MapTab.swift`,
Firebase console (App Check, Crashlytics)

> `context/plans/` is not a dictionary entry and carries no `Scope`/`Verified`
> stamp. When an item below ships, fold what's true into the entries it names
> and delete it from here.

---

## Summary

A staff-level audit of the Swift on 2026-09-20 found **no code defects** —
every blocker was configuration, infrastructure or test coverage, and every
submission blocker has since shipped. What's left is launch-week visibility and
debt.

| # | Item | Effort | Blocks submission |
|---|---|---|---|
| 1 | App Check, monitoring mode | ~2h + console | No, but ship close behind |
| 2 | Crashlytics + dSYM upload | ~1h | No |
| 3 | Actor isolation on the test targets | ~15min | No |
| 4 | `SWIFT_STRICT_CONCURRENCY = complete` | ~2h | No |
| 5 | Split `MapTab.swift` | ~4h | No — **after** launch |

**§1 (App Check) is the highest-value item.** It is the one thing standing
between an extracted `GoogleService-Info.plist` and every document in the
database.

---

## 🟡 High — these don't block the upload, but make launch week blind or risky

### 1. No App Check — the ruleset is the only thing standing between the
database and the internet

**Location:** package dependencies (`FirebaseAuth`, `FirebaseCore`,
`FirebaseFirestore` only); no `AppCheck` reference anywhere in `hoopr/`.

**Real gap:** a concrete, end-to-end attack that works today.
`GoogleService-Info.plist` ships inside every IPA and is extractable from any
downloaded build in under a minute. Sign-up has no email verification, no
CAPTCHA and no App Check (`gaps/PROFILES.md`), so an account costs nothing and
can be scripted against the Auth REST endpoint. With one scripted account, the
read rules grant the whole database:

| Collection | Rule | What a scripted account reads |
|---|---|---|
| `users/{uid}` | `allow read: if request.auth != null` (`firestore.rules:38`) | every profile, whole — including `homeCourtId` + `favoriteCourtIds`, which `gaps/PROFILES.md` correctly calls "a location pattern attached to a named person" |
| `squads/{squadId}` | `allow read: if isSignedIn()` (`:413`) | every squad and roster |
| `matchTickets/{squadId}` | `allow read: if isSignedIn()` (`:633`) | every queue entry |
| `seasonGames/{gameId}` | `allow read: if isSignedIn()` (`:937`) | every scheduled match, with its court and time |

The ruleset is well built and its key allowlists are what make a world-readable
profile *survivable*. But rules govern what an authenticated principal may do;
they cannot govern **who gets to be a principal**. App Check is the control that
does, and it is absent. On the Spark plan the same hole is also a denial-of-
wallet path: scripted reads burn the free quota and the app goes dark for real
users.

**This is the single highest-value item in the document.** It is console work
plus roughly ten lines of Swift, and it retroactively gives every per-account
limit in `gaps/RATE_LIMITING.md` its teeth back — that file's conclusion that
"a limit scoped to a uid is a speed bump when a fresh uid costs nothing" is
exactly what App Check reverses.

**Fix:** add the `FirebaseAppCheck` product, install the App Attest provider
*before* `FirebaseApp.configure()`, and register the key in the Firebase console.
Run it in monitoring mode first and only enforce once the console shows verified
traffic — enforcing immediately locks out every already-installed build.

```swift
// hooprApp.swift — in init(), BEFORE FirebaseApp.configure()
#if !targetEnvironment(simulator)
AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
#endif
FirebaseApp.configure()
```

The simulator guard matters: App Attest has no simulator implementation, so
without it every simulator run fails its token fetch. Use the debug provider
there if you want parity.

---

### 2. No crash reporting

**Location:** no Crashlytics, Sentry or equivalent anywhere in the project.

**Real gap:** the first production crash is invisible. There is no symbolicated
stack, no affected-user count, no regression signal between builds — the only
channel is a one-star review describing the symptom. This matters more than
usual here because `ListenerSupervisor` is deliberately designed to *recover
silently* from listener failures; a bug that degrades into permanent recovery
looks like "the list is slow" from the outside and produces no crash at all.
Without telemetry neither failure mode is observable.

**Fix:** add `FirebaseCrashlytics` (same SDK, no new vendor, no new privacy
disclosure beyond what Firebase already requires) and upload dSYMs from the
build. Non-fatal recording on the `FirestoreFailure` paths would also surface
the recovery case, which is the one that will otherwise never reach you.

---

## 🟢 Medium — real, measurable, not urgent

### 3. The test target compiles under different actor isolation than the app

**Location:** `project.pbxproj` — `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is
set at lines 444 and 488 (app target, Debug and Release) and is **absent** from
the `hooprTests` and `hooprUITests` configurations.

**Real gap:** a verifiable inconsistency, not a style preference. Types in the
app target default to `@MainActor`; the same code compiled into the test target
defaults to `nonisolated`. The 666 tests therefore exercise isolation semantics
that production does not have, in both directions — a test can reach a member
without the hop production requires, and a concurrency bug that the app target's
default would have caught at compile time is invisible from the suite.

**Fix:** add the setting to all four test configurations so the suite and the
app agree.

---

### 4. Data-race safety is not enforced at compile time

**Location:** `SWIFT_VERSION = 5.0` in all 6 configs; no `SWIFT_STRICT_CONCURRENCY`.

**Real gap:** Swift 5 language mode with no strict-concurrency setting means
`minimal` checking. The codebase is *written* as if it were on — models are
`nonisolated ... Sendable`, services are `@MainActor`,
`SWIFT_APPROACHABLE_CONCURRENCY` is on — across 64 `Task {}` sites. The
discipline is real and the compiler is verifying almost none of it.

**Fix:** set `SWIFT_STRICT_CONCURRENCY = complete` and fix what it reports. Given
the existing annotations the diagnostic count should be low, and the setting is
the cheapest way to confirm that. Swift 6 language mode is the eventual target;
`complete` under Swift 5 is the step that de-risks it without a migration.

---

### 5. `MapTab.swift` is 1,388 lines and ~40 members in one `View`

**Location:** `hoopr/Views/Tabs/MapTab.swift` — the largest file in the repo.

**Real gap:** measurable by responsibility count, not by line count alone. One
type owns map overlay and recenter (`:288`–`:413`), search pane and results
(`:521`–`:620`), sheet chrome, handle and header (`:414`–`:497`, `:780`–`:823`),
three list modes (`:622`–`:729`), court cards and run rows (`:824`–`:983`), drag
gesture and detent physics (`:1041`–`:1089`), and Maps hand-off (`:1026`). Any
change to the sheet's drag behaviour requires reading past the search pane to
reach it.

The internal organisation is good — members are `private`, names are accurate,
and the MARK structure is followed — which is why this is Medium and not High.
It is debt, not a defect.

**Fix:** extract along the seams already visible in the member names, into
`Views/Map/`: `MapSearchPane`, `MapCourtCard`, `MapSheetChrome`. Net line change
≈ 0 — this buys reviewability, not brevity, and the report should not pretend
otherwise. **Do this after launch.** Restructuring the most complex screen in
the app during the week you are chasing items 1–3 trades a real risk for a
cosmetic gain.

---

## Documentation owed when these ship

- **1** changes the conclusion of `gaps/RATE_LIMITING.md` — per-account limits
  become meaningful once accounts are attested — and softens the sign-up bullet
  in `gaps/PROFILES.md`.
- **3, 4** belong in `BUILD_AND_CONFIG.md`.
- **5** touches `MAP_LAYER.md` and `UI_SHELL.md`, and the new paths need adding
  to the owning entry's `Scope` so `check_context_drift.py` keeps tracking them.

## See also

- `../gaps/PROFILES.md` — the world-readable profile that §1 turns from a
  documented trade-off into an exploitable one.
- `../gaps/RATE_LIMITING.md` — why unattested free accounts cap every limit.
- `SCALE_UP.md` — assumes the Spark plan; §1's quota-burn path is a risk to that
  assumption.
