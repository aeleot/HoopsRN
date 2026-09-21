# Plan — Launch Readiness

**Status:** partly shipped — items 1, 3, 6 and 10 landed 2026-09-20
**Drafted:** 2026-09-20
**Touches:** `hoopr.xcodeproj/project.pbxproj`, `hoopr/Assets.xcassets/AppIcon.appiconset/`,
`firestore-tests/`, `hoopr/Views/Tabs/MapTab.swift`, Firebase console (App Check,
Crashlytics), `context/gaps/CONFIGURATION.md`, `context/gaps/TESTING.md`,
`context/gaps/PROFILES.md`

> `context/plans/` is not a dictionary entry and carries no `Scope`/`Verified`
> stamp. A plan describes work that hasn't happened; the dictionary describes
> code that has. When an item below ships, fold what's true into the entries
> named in "Documentation debt" and strike it from here.

---

## Summary

A staff-level audit of all 89 Swift files (22,530 lines) against four lenses —
code reduction, execution efficiency, user safety, maintainability.

**The Swift is production-grade. Nothing below is a code defect.** The audit
found 2 force unwraps in 22.5k lines and both are provably total; zero logging
statements; every one of the 12 snapshot listeners captures `[weak self]` *and*
tears down in `deinit`; every Firestore query carries a `.limit(to:)`; all 5
`DateFormatter`s are already cached as `static let`. The DRY lens found no
duplication worth consolidating and the efficiency lens found no quadratic path
— the one `contains` inside a loop (`SquadViewModel.swift:510`) is over a
`Set<String>`, so it is O(1).

**Every blocker is configuration, infrastructure, or test coverage.** Three of
them stop an App Store submission outright. That is a good problem to have at
this stage, but none of them are fixed by writing Swift, so none of them will be
found by the existing 457 tests.

**Estimated net line reduction: ~0.** This is a real result, not a gap in the
audit. The one structural item (§9) is a reorganisation that moves lines between
files rather than deleting them. Reporting a reduction figure here would be
invented.

---

## Correction — the audit got §3's premise wrong

**This document originally said "no API the app calls requires iOS 26."** It
does not hold, and the error is worth keeping rather than quietly editing out:
the audit inherited the claim from `BUILD_AND_CONFIG.md` and confirmed it with a
grep narrow enough to miss what it was looking for — it searched for
`#if os(...)` version gates and found none, which says nothing about API
availability.

What was actually there:

| API | Floor | Sites |
|---|---|---|
| `glassEffect(_:in:)` | iOS 26.0 | 5 — `MapTab` ×2, `GlassChip`, `HooprSearchField`, `ProfileIdentity` |
| `MKMapItem(location:address:)`, `MKAddress` | iOS 26.0 | 1 — `MapTab.openDirections` |
| `onGeometryChange`, `onScrollGeometryChange` | iOS 18.0 | 4 — `MapTab` ×2, `ProfileView` ×2 |

The compiler found the MapKit pair; a grep never would have, because the call
reads like ordinary MapKit. **The lesson for the next audit: availability is a
compiler question, not a grep question.** Lowering a deployment target and
building is the cheap way to enumerate what the floor is actually holding up.

This did not change the recommendation — 18.0 was still right — but it changed
the cost from "zero code" to "one shared modifier plus one branch", which is the
kind of estimate a plan exists to get right.

---

## 🔴 Critical — these stop a submission

### 1. ~~The app icon set is empty~~ — FIXED 2026-09-20

**Location:** `hoopr/Assets.xcassets/AppIcon.appiconset/`

**Real gap:** the directory contains `Contents.json` and nothing else. The JSON
declares three 1024×1024 entries (light, dark, tinted) and **none of them carries
a `filename` key** — zero across the whole file. There is no image to build.

App Store Connect rejects the upload at processing time, before review: a
missing 1024×1024 marketing icon is `ITMS-90022`/`ITMS-90713`. `gaps/
ASSETS_AND_DATA.md` records a "placeholder app icon", which undersells it —
there is no placeholder, there is nothing.

**Fixed:** all three slots now carry a 1024×1024 opaque PNG — `AppIcon.png`,
`AppIcon-Dark.png`, `AppIcon-Tinted.png`. The 12 dead `mac` idiom slots went
with the platform trim in §6.

**The icon is the launch screen's mark.** `RootView.LaunchScreen` draws
`basketball.fill` in `hooprOrange` over `hooprBackground`; the icon is that same
SF Symbol rendered at 1024 in the same two colours, so the home screen and the
app's first frame agree rather than being two different marks.

**It is a placeholder in intent, not in quality** — a rendered system symbol is
not a brand mark, and replacing it later costs nothing. What it is not any more
is a build that cannot be submitted.

Verified by compiling the catalogue rather than by eye:

```bash
xcrun actool hoopr/Assets.xcassets --compile /tmp/icon-check --platform iphoneos --minimum-deployment-target 18.0 --app-icon AppIcon --output-partial-info-plist /tmp/icon-check/partial.plist
```

That emits `CFBundleIconName: AppIcon` with zero errors, and `assetutil --info`
on the resulting `Assets.car` lists all three renditions.

---

### 2. No App Check — the ruleset is the only thing standing between the
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

### 3. ~~`IPHONEOS_DEPLOYMENT_TARGET = 26.5` ships to almost nobody~~ — FIXED 2026-09-20

**Location:** `hoopr.xcodeproj/project.pbxproj` — all **6** build configurations.

**Real gap:** iOS 26.5 is a point release from 2026. Setting it as the floor
excluded all but the sliver of the installed base already on the very latest
point release, for an app whose 26-only API use came to six call sites — all of
them cosmetic or cosmetically degradable. See the correction above for what the
audit got wrong about this.

**Fixed: iOS 18.0 in all 6 configurations**, reached by gating the six sites
rather than dropping the features:

- **`Support/Glass.swift`** is new, and holds the app's only glass
  `#available`. `.hooprGlass(tint:interactive:in:)` is Liquid Glass on iOS 26
  and `.ultraThinMaterial` below it. The fallback stays *translucent* on
  purpose — every one of these surfaces floats over a map or a scrolling list,
  and an opaque fill turns a floating chip into a panel, which is the exact
  failure `GlassChip` was written to avoid. A tint rides on top of the material
  rather than replacing it, so "the same object lit up" survives the fallback.
  All five sites now route through it and none calls `glassEffect` directly.
- **`MapTab.openDirections`** branches on `#available`: `MKMapItem(location:address:)`
  on 26, `MKMapItem(placemark:)` below. The route is identical; only the Maps
  callout label is terser.

**18.0 and not 17.0**, deliberately: `onGeometryChange` and
`onScrollGeometryChange` are iOS 18 and two of the four sites size `MapTab`'s
sheet. Rewriting those against `GeometryReader` is the most delicate change
available on the most complex screen in the app, for one more OS version. Not
before launch.

**Unverified below iOS 26.** The fallback path compiles and the suite passes,
but neither has run on a device or simulator older than 26 — `gaps/CONFIGURATION.md`
carries that as the live risk.

---

## 🟡 High — these do not block the upload, but they make launch week blind or
risky

### 4. No crash reporting

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

### 5. `games`, `friendships` and `users` have zero rules test coverage

**Location:** `firestore-tests/` — `arrival`, `claim-race`, `match-tickets`,
`results`, `season-games`, `squads`.

**Real gap:** the emulator suite covers the six newest collections and none of
the three oldest. `users` and `games` carry the most intricate rules in the file
— the `users` key allowlist is, by the ruleset's own comment at
`firestore.rules:41`, "what keeps this document safe to leave world-readable",
and it is asserted by nothing. A regression that widens it produces no test
failure, no build failure, and no visible symptom; it silently exposes every
profile.

`gaps/TESTING.md` records the absence. What the audit adds is the priority
argument: this is not three equal gaps. The `users` allowlist is load-bearing
for the privacy posture of the entire app, and it is one `npm run test:rules`
case away from being defended.

**Fix:** three new `.test.mjs` files against the existing `harness.mjs`. Start
with `users` and assert the negative cases, which are the ones that matter:

- a write adding a key outside the allowlist (`email`, `phone`) is **denied**
- a write to another uid's document is **denied**
- a delete is **denied** (the rule is `allow delete: if false`)
- an unauthenticated read is **denied**; a signed-in read of a stranger is
  **allowed** (this is intended — pin it so the intent is explicit)

Then `games` (host-only update/delete, roster diffs) and `friendships`
(participant-only read, the request/accept transition).

---

### 6. ~~The project claims iPad, Vision and macOS; the UI is iPhone-portrait~~ — FIXED 2026-09-20

**Location:** `TARGETED_DEVICE_FAMILY = "1,2,7"`;
`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx xros xrsimulator"`.

**Real gap:** App Review tests on iPad when the binary declares iPad support.
`gaps/CONFIGURATION.md` notes the UI is "iPhone-portrait-shaped throughout" and
that nothing but `MapTab`'s sheet has been checked at another shape. An
unadapted iPhone layout stretched to iPad is a Guideline 2.4.1 rejection, and it
arrives *after* the review wait rather than at upload.

**Fixed:** `TARGETED_DEVICE_FAMILY = "1"` and `SUPPORTED_PLATFORMS = "iphoneos
iphonesimulator"` in all 6 configurations. The 12 `mac` idiom slots came out of
`AppIcon.appiconset/Contents.json` with them. Both settings are reversible in
one line when an iPad layout actually exists — shipping iPhone-only is not a
concession, it is an accurate declaration of what was built.

`XROS_DEPLOYMENT_TARGET = 26.5` survives in all six configurations. It is inert
with `xros` off the platform list, and Xcode rewrites these keys unprompted, so
it was left alone rather than fought with. It does not mean visionOS is
supported.

---

## 🟢 Medium — real, measurable, not urgent

### 7. The test target compiles under different actor isolation than the app

**Location:** `project.pbxproj` — `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is
set at lines 444 and 488 (app target, Debug and Release) and is **absent** from
the `hooprTests` and `hooprUITests` configurations.

**Real gap:** a verifiable inconsistency, not a style preference. Types in the
app target default to `@MainActor`; the same code compiled into the test target
defaults to `nonisolated`. The 457 tests therefore exercise isolation semantics
that production does not have, in both directions — a test can reach a member
without the hop production requires, and a concurrency bug that the app target's
default would have caught at compile time is invisible from the suite.

**Fix:** add the setting to all four test configurations so the suite and the
app agree.

### 8. Data-race safety is not enforced at compile time

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

### 9. `MapTab.swift` is 1,130 lines and ~40 members in one `View`

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

### 10. ~~The location permission prompt says "hoopr"~~ — FIXED 2026-09-20

**Location:** `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`, both app
configurations.

**Real gap:** user-facing, and one of the first strings a new user reads. The
2026-08-15 rename was deliberately shallow and covered display name and
user-facing strings — this string is user-facing and was missed.

**Fixed:** now `"hoopsRN uses your location to show courts and runs near you."`

**This also caught a documentation error.** `BUILD_AND_CONFIG.md` listed the
location prompt among the strings the 2026-08-15 rename *did* change, and quoted
it as "hoopsRN needs your location to find nearby basketball courts." No such
string has ever been in the project — the setting read "hoopr uses your
location…" the whole time. Both the claim and the quote are corrected there.

---

## What is genuinely well built

Stated specifically, because it is what makes the list above short, and because
a future audit should not re-derive it:

- **Crash surface.** 2 force unwraps in 22,530 lines. `Game.swift:216` is
  `TimeZone(secondsFromGMT: 0)!`, which is total for 0; `MapView.swift:132` is
  the required-init `fatalError` for a nib path that does not exist. Neither is
  reachable. No `try!`, no `as!`, no implicitly unwrapped optionals.
- **No logging leaks.** Zero `print`/`NSLog`/`debugPrint` in the app target, so
  there is no path for a token or a uid to reach the device console. The one
  `Logger` is `ListenerSupervisor`'s, on its own subsystem.
- **Listener hygiene is complete.** 12 of 12 `addSnapshotListener` sites capture
  `[weak self]`, and every service that owns listeners removes them in `deinit`
  *and* on sign-out. `ListenerSupervisor` tracks failures per listener key
  precisely so a healthy listener's success cannot cancel a dead one's
  re-attach — that is a subtle bug, anticipated and closed before it shipped.
- **Every query is bounded.** All 10 use `.limit(to:)` against a named `Limit`
  constant. There is no unbounded collection read in the app.
- **Formatters are cached.** All 5 are `static let`, so none of the per-row
  `DateFormatter` construction that usually dominates a list-scroll profile
  exists here.
- **The vendor boundary holds.** No Firebase import outside `hoopr/Services/`.
- **Secrets storage is correct.** `UserDefaults` holds appearance preference and
  recent courts, and nothing else. No credential is persisted by app code.

---

## Suggested order

Items 1–3 are the submission gate. 4–6 are launch-week visibility and rejection
risk. 7–10 are debt.

| # | Item | Effort | Blocks submission | Status |
|---|---|---|---|---|
| 1 | App icon asset | ~1h design | **Yes** | **Done** 2026-09-20 |
| 3 | Deployment target → 18.0 | ~1h + regression pass | **Yes**, commercially | **Done** 2026-09-20 |
| 6 | `TARGETED_DEVICE_FAMILY = "1"` | ~5min | **Yes**, review risk | **Done** 2026-09-20 |
| 10 | Rename the permission string | ~2min | No | **Done** 2026-09-20 |
| 2 | App Check, monitoring mode | ~2h + console | No, but ship close behind | Open |
| 4 | Crashlytics + dSYM upload | ~1h | No | Open |
| 5 | Rules tests: `users`, then `games`, `friendships` | ~4h | No | Open |
| 7 | Actor isolation on test targets | ~15min | No | Open |
| 8 | `SWIFT_STRICT_CONCURRENCY = complete` | ~2h | No | Open |
| 9 | Split `MapTab.swift` | ~4h | No — **after** launch | Open |

**No submission blockers remain.** The estimate for the four that landed was
"four edits to two files"; it was actually seven files, because §3 turned out to
need the glass modifier and the MapKit branch. The build succeeds, the 457 unit
tests pass, and the app target compiles with no warnings of its own.

**§2 (App Check) is now the highest-value item left** and is unchanged by any of
this — it is still the one thing standing between an extracted
`GoogleService-Info.plist` and every document in the database.

---

## Documentation debt

**Paid for 1, 3, 6 and 10 on 2026-09-20:**

- `gaps/ASSETS_AND_DATA.md` — icon section struck. It also carried a wrong
  claim ("nothing will flag it"), corrected in place rather than deleted.
- `gaps/CONFIGURATION.md` — deployment-target and platforms sections struck,
  with the untested-below-26 fallback path recorded as what replaced them.
- `BUILD_AND_CONFIG.md` — identity table (target, platforms, device family),
  the corrected permission string, the false "no 26-only API" line, the rename
  paragraph's wrong claim about the location prompt, and a new Assets section.
- `UI_SHELL.md` — the glass rule and `Support/Glass.swift`, which was also
  added to its `Scope` so the drift check tracks it.
- `MAP_LAYER.md` — map chrome routes through `.hooprGlass`, and the two-branch
  directions hand-off.

**Still owed, when the rest ship:**

- **2** changes the conclusion of `gaps/RATE_LIMITING.md` — per-account limits
  become meaningful once accounts are attested — and softens the sign-up
  bullet in `gaps/PROFILES.md`.
- **5** updates the coverage table in `gaps/TESTING.md`.
- **7, 8** belong in `BUILD_AND_CONFIG.md`.
- **9** touches `MAP_LAYER.md` and `UI_SHELL.md`, and the new paths need adding
  to the owning entry's `Scope` so `check_context_drift.py` keeps tracking them.

**The `Verified` stamps on the four entries above are deliberately unchanged.**
This repo stamps entries in the commit that lands the work (see `de875eb`,
`c9b8f74`), and these edits are uncommitted — so `check_context_drift.py`
reports them stale, correctly. Restamp them as part of the commit, not before.

## See also

- `../gaps/CONFIGURATION.md` — already flagged the deployment target; §3 supplies
  the evidence that it is safe to lower.
- `../gaps/PROFILES.md` — the world-readable profile that §2 turns from a
  documented trade-off into an exploitable one.
- `../gaps/RATE_LIMITING.md` — why unattested free accounts cap every limit.
- `../gaps/TESTING.md` — the coverage table §5 fills in.
- `SCALE_UP.md` — assumes the Spark plan; §2's quota-burn path is a risk to that
  assumption.
