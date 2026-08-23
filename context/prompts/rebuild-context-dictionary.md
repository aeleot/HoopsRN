# hoopsRN Context Dictionary — Full Rebuild

Rebuild the context dictionary in `context/` from a complete read of the codebase.

The dictionary is **working memory for an agent**, and documentation second. A future session starts with no knowledge of this project, reads `context/INDEX.md`, and must be able to make a correct change without rediscovering the codebase. Optimise for that reader.

Run this when the dictionary doesn't exist, or when it has drifted far enough that incremental repair isn't worth it. For routine upkeep use `context/prompts/refresh-context-dictionary.md`.

---

## The inclusion test

Before writing any sentence, ask: **would an agent make a wrong change without this?**

Include:
- Constraints and invariants that aren't visible from one file (the vendor boundary, the mutability contract, startup ordering).
- Non-obvious rationale — why the code is shaped this way, especially where the obvious approach was rejected.
- Cross-file wiring: what publishes, what subscribes, what has to be redeployed alongside a code change.
- Where a thing lives, when finding it requires a search.

Exclude:
- Anything restating code that's plain on reading (property lists, method signatures, obvious names).
- File and line counts, exhaustive file inventories, "N Swift files".
- Feature wishlists, roadmaps, marketing description, target audience.
- Setup instructions for standard Xcode/SPM workflows.

Dense and short beats complete. If an entry is mostly prose that could be replaced by "read the file," cut it.

---

## Dictionary structure

Every entry has a **stable filename** and an **owned scope** — the source paths it is responsible for. Scopes must not overlap, and their union must cover everything in the repo that matters. The scope lines are what make the quick pass possible: a rerun maps changed files onto scopes to find stale entries.

| Entry | Owns | Answers |
|---|---|---|
| `INDEX.md` | — | Where do I look for X? What's current? |
| `ARCHITECTURE.md` | `hooprApp.swift`, `Services/`, `ViewModels/` | How is the app wired, and what may not be broken? |
| `DATA_MODEL.md` | `Models/` | What are the domain types and their contracts? |
| `database/DATABASE_SCHEMA.md` | `firestore.rules`, `firestore.indexes.json`, `firebase.json`, `.firebaserc` | What's stored server-side, and what may a client write? |
| `database/USER_PROFILE_WORKFLOW.md` | runtime auth + profile behaviour | What happens between sign-in and a rendered profile? |
| `MAP_LAYER.md` | `Views/MapView.swift`, `Views/Tabs/` | How does the map and its bottom sheet work? |
| `COURT_DATASET.md` | `Resources/`, `tools/`, `location-decoder-script/` | Where do courts come from and how do I regenerate them? |
| `UI_SHELL.md` | `Views/RootView.swift`, `Views/MainTabView.swift`, `Views/LoginView.swift`, `Views/Profile/`, `Support/Theme.swift` | How does navigation work and what are the visual conventions? |
| `BUILD_AND_CONFIG.md` | `hoopr.xcodeproj/`, `Package.resolved`, `hooprTests/`, `hooprUITests/` | How does it build, what does it depend on, what's tested? |
| `GAPS.md` | — | What's unfinished, and what do the docs get wrong? |

Layout: entries live at the root of `context/`, except the two database entries which live in `context/database/`. `context/prompts/` holds these prompts — it is **not** a dictionary entry and gets no `Scope`/`Verified` stamp.

`database/USER_PROFILE_WORKFLOW.md` and `database/DATABASE_SCHEMA.md` already exist and are good. Refresh them in place; keep their names, location, and voice.

---

## Entry format

Every entry, without exception:

```markdown
# hoopsRN — <Entry Name>

**Scope:** `path/one`, `path/two`
**Verified:** YYYY-MM-DD @ <short commit sha>

<One paragraph: what this entry covers and when to read it.>

---

## <Section>

<Prose. Tables for field-by-field or case-by-case detail. Code snippets only
where a pattern can't be conveyed in words — 5-15 lines, from the real file.>

---

## Invariants

- <Rules that must not be broken. The highest-value part of the entry.>

## See also

- `OTHER.md` — <why you'd go there>
```

`Scope` and `Verified` are machine-read by the quick pass. Get the commit sha from `git rev-parse --short HEAD`.

**`INDEX.md`** is the exception — it holds no content of its own, only:
1. A table of every entry: name, one-line description, `Verified` date + sha.
2. A **routing table** — the most useful thing in the dictionary:

   | If you're changing… | Read first |
   |---|---|
   | anything touching Firebase | `ARCHITECTURE.md` (vendor boundary) |
   | a stored profile field | `database/DATABASE_SCHEMA.md` + `database/USER_PROFILE_WORKFLOW.md` |
   | map behaviour or the bottom sheet | `MAP_LAYER.md` |
   | court data | `COURT_DATASET.md` |
   | navigation or styling | `UI_SHELL.md` |

3. A one-line statement of how to refresh the dictionary: run `context/prompts/refresh-context-dictionary.md`, or `context/prompts/rebuild-context-dictionary.md` to rebuild from scratch.

---

## Verified facts — confirm each, correct the entry where the code disagrees

These were true when this prompt was written. **The code wins.** If a value has changed, use the code's value and note the change in your closing summary.

| Fact | Value | Source |
|---|---|---|
| Bundle ID | `Big-Boss-LLC.hoopr` | `project.pbxproj` |
| Deployment target | iOS **26.5** — *not* 17.0; older docs are wrong | `project.pbxproj` |
| Swift | 5.0 | `project.pbxproj` |
| Info.plist | **none on disk** — generated; location string is `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` | `project.pbxproj` |
| Firebase | firebase-ios-sdk **12.16.0** — Core, Auth, Firestore | `Package.resolved` |
| Firebase project | `hoopsrn-4f1e9` | `.firebaserc` |
| Dataset | `courts.json` v1, generated 2026-08-06, **213 courts**, 6 Triangle cities | `hoopr/Resources/courts.json` |
| Home location | hardcoded Durham `35.9940, -78.8986` | `LocationService.defaultLocation` |

---

## Per-entry content requirements

Only the things an agent would get wrong without being told. Verify each claim.

**`ARCHITECTURE.md`**
- Four services owned as `@StateObject` in `hooprApp.swift` for the app's lifetime, injected downward; four view models built from them. Name what each service publishes.
- **Vendor boundary (invariant):** `AuthService` is the only file importing `FirebaseAuth`; `UserProfileService` the only one importing `FirebaseFirestore`. Above them the app speaks `AuthenticatedUser` / `AuthError` / `UserProfile` / `UserProfileError` only. Adding a Firebase import anywhere else breaks the design.
- **Startup order (invariant):** `FirebaseApp.configure()` runs in `hooprApp.init()`, *not* the `AppDelegate` — `AuthService.init()` calls `Auth.auth()`, which traps if Firebase isn't configured, and `@StateObject` initializers are autoclosure-deferred. `UserProfileService` depends on `AuthService`, so both are constructed there. The `AppDelegate` is a deliberate no-op kept for future APNs and must not configure Firebase again. *(Older docs say "via AppDelegate" — wrong.)*
- `UserProfileService` is `@MainActor` and owns one profile listener per session, so the greeting and the profile screen read the same state instead of opening separate listeners.
- `RootViewModel` exists separately from `RootView` so the gating rule is testable without rendering.

**`DATA_MODEL.md`**
- `Court`: `id` is a stable build-time UUID **not derived from coordinates**, so correcting a court's position never orphans future games/ratings/check-ins. `osmType`/`osmId` retained so a future extract matches instead of duplicating. `Access` is derived at build time because OSM rarely tags apartment and hotel courts as private.
- `CourtDataset`: the `version` exists so a future CDN copy can be compared without parsing courts.
- `UserProfile`: Firebase-free by design; `userName` is a display name, **not a unique handle**; `id` duplicates the document ID so decoding needs no optionals. **Never hand it to `setData(from:)`** — `UserProfileService` writes explicit field maps so server timestamps stay server-assigned and `createdAt` is never clobbered.
- `AuthError` and `UserProfileError` cases, and what each actually means — particularly `notConfigured` (Auth never enabled on the project; surfaces as a generic internal error containing `CONFIGURATION_NOT_FOUND`), `providerDisabled`, and `permissionDenied` (almost always undeployed rules).

**`database/DATABASE_SCHEMA.md`** *(exists — verify and refresh)*
- `users`, document ID == Auth uid. Field table with required/mutable columns.
- **Mutability contract (invariant):** `id`, `email`, `createdAt` are write-once; only `userName`, `homeCourtId`, `updatedAt` may change — enforced server-side by `diff().affectedKeys().hasOnly([...])`, not client discipline.
- **Two-step rule (invariant):** a new editable field needs both a write method *and* an addition to `hasOnly([...])` plus `firebase deploy --only firestore:rules`. Skipping the redeploy fails saves with `permission-denied`.
- Absent-vs-null convention: clearing `homeCourtId` deletes the field; an absent email is omitted, never written as null.
- Access: read by any signed-in user (names must resolve in shared contexts later), write by owner only, delete denied.
- `homeCourtId` holds a `Court.id` from the bundled dataset — courts aren't in Firestore, so nothing validates it server-side.

**`database/USER_PROFILE_WORKFLOW.md`** *(exists — verify and refresh)*
- Why two identity layers: Auth owns credentials, Firestore owns what other players see. The greeting previously sliced the email at `@` on every render; the stored profile replaces that guess.
- The sign-in → provisioned-profile sequence end to end.
- Idempotent provisioning: accounts predating profiles have no document, so it runs on every sign-in and no-ops when present. Seed name is the email local part, falling back to `"Hooper"`.
- The `observedUID` guard — Firebase re-emits the same user on token refresh; the listener must not churn.
- The edit cycle: `EditableField`, draft/save/cancel, `isSaving`, and why `email` and `dateJoined` are read-only.

**`MAP_LAYER.md`**
- **The UUID trigger pattern** — `RecenterTrigger` / `ZoomTrigger` / `AbsoluteZoomTrigger` each carry a `UUID` and define `==` on it alone, so SwiftUI always sees a new value; the `Coordinator` records the last-handled ID so `updateUIView` applies each exactly once. Worth a snippet.
- Annotation diffing by `court.id` — set difference only, never a wholesale reload.
- Log-scale zoom between 0.01° and 5.0° spans; `zoomLevelFromSpan`/`spanFromZoomLevel` are inverses so slider and map agree. Stepped zoom factors 0.75 / 1.4.
- 200ms debounce on region reporting; 50ms delay before `onMarkerDeselect` because pin-to-pin taps deselect before selecting.
- `canShowCallout = false` — the sheet owns detail display.
- `MapTab`'s `SheetState` machine: `.list` / `.collapsed` / `.detail(court:returningTo:)`, where `.detail` carries the rest state so dismissing restores what was showing before. The sheet only claims a drag that starts with the list at the top (`listScrollOffset`); `tapSlop`, `collapseThreshold`.
- The `isDraggingSlider` guard that stops map-driven zoom updates fighting the user's finger.
- `NearbyCourt` distances computed once at list build, never during scroll; 5-mile radius.
- **Distances and recentering use the hardcoded Durham location, not the device's.** Device location is requested on first recenter tap only so MapKit can draw the blue dot — the map no longer blocks on a permission prompt. Swapping `FindAMatchViewModel.homeLocation` is the intended future change and the pipeline follows it with no other edits.

**`COURT_DATASET.md`**
- Why bundled rather than fetched: instant population, works offline, no dependence on a volunteer-run API that intermittently times out.
- `CourtService` hardcodes the `"courts"` resource name and sorts by name; failures publish `loadError`.
- Regeneration: what `tools/build_courts.py` and `tools/fetch_city_courts.py` each do, and where `location-decoder-script/reverseGeocode.js` fits. Note `node_modules/` is committed at the repo root.
- Current dataset header: version, generated date, cities, count, attribution.

**`UI_SHELL.md`**
- `RootView` gates `.launching` / `.login` / `.main` with a 0.2s crossfade; `.launching` exists so the login screen never flashes at a user whose session is about to restore.
- `MainTabView` is a custom shell, not a system `TabView`: header ~14% of height, greeting + profile button, three pill tabs. `MapTab` stays mounted via opacity/`allowsHitTesting` while the other two mount conditionally — so map state survives tab switches.
- `ProfileView` **replaces** `MainTabView` full-screen rather than rendering inside it, because it owns its own header and back button.
- The six `Theme.swift` colours with usage. Note the map marker tint is a hardcoded `UIColor` duplicating `hooprOrange` rather than deriving from it.
- Light mode only: literal colours, direct `.black` / `Color.white`, no dark-mode handling.

**`BUILD_AND_CONFIG.md`**
- The identity table above.
- SPM dependency set and which Firebase products are actually linked.
- Firebase CLI surface: `firebase.json`, `firestore.rules`, `firestore.indexes.json`, `.firebaserc`, and the deploy command rules changes require.
- Tests: `hooprTests/UserProfileTests.swift` is **real coverage** — it runs documents through `Firestore.Decoder`, the same decoder the service uses, so a field rename in the console or the model fails a test rather than silently emptying the profile UI. Everything else (`hooprTests.swift`, both UI test files) is Xcode scaffold. *(Older docs claiming "no real tests" are out of date.)*
- Untested areas worth naming: the zoom-conversion inverses, `RootViewModel`'s gating rule, the distance filter, and both error mappings.

**`GAPS.md`** — dated, and split into two lists.

*Unfinished:* no way to send a friend request from the UI (the `friendships` backend supports it; the search bar doesn't exist yet); the detail sheet shows name and address only while `hoops`/`surface`/`isLit`/`isCovered`/`access` sit unused; no occupancy or check-in; `AppIcon.appiconset` has no images and `AccentColor` is empty; `courts_updated.json` (135 courts) is stale and never loaded; distances anchored to a hardcoded point; no password reset, social login, or account deletion; `FindAMatchViewModel.select(_:)` is an empty hook; iOS 26.5 target is unusually restrictive — flag in case it's unintentional.

*Known drift (comments/docs contradicting code):* `firestore.rules` points at `"hoopr project info/DATABASE_SCHEMA.md"` but the folder is `context/`; `UserProfile.homeCourtId`'s comment says "read but never written yet" while `updateHomeCourt` and the profile picker both write it. Record drift here rather than reproducing it elsewhere.

---

## Procedure

1. `git rev-parse --short HEAD` — stamp every entry with it.
2. Read `hooprApp.swift` first; startup order and ownership explain the rest.
3. Read `Models/` → `Services/` → `ViewModels/` → `Views/`. `MapView.swift` and `MapTab.swift` are the two densest files — read them fully.
4. Read `firestore.rules`, `.firebaserc`, `firebase.json`.
5. Pull identity values from `project.pbxproj` and `Package.resolved`; parse the `courts.json` header only.
6. Read the test files and report actual coverage.
7. Skim `tools/` and `location-decoder-script/`.
8. Write all ten entries, then `INDEX.md` last so it reflects what you actually wrote.
9. Verify every scope path in the table resolves, and that no repo path that matters is unowned.
10. Close with a short summary to the user: entries written, facts that had changed since this prompt, and any drift found.
