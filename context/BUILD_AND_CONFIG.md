# hoopsRN — Build and Config

**Scope:** `hoopr.xcodeproj/`, `hooprTests/`, `hooprUITests/`,
`hoopr/Assets.xcassets/`, `hoopr/GoogleService-Info.plist`, `.gitignore`,
`tools/check_context_drift.py`, `package.json`, `package-lock.json`
**Verified:** 2026-09-17 @ 2c75b14

`Package.resolved` isn't listed separately — it lives under `hoopr.xcodeproj/`
and is covered by it. (Anything backticked between the `Scope` and `Verified`
lines is parsed as an owned path, so notes belong here, below the stamp.)

Project identity, dependencies, the Firebase CLI surface, and what the tests
actually cover. Read this before changing a build setting, adding a dependency,
or assuming something is tested.

---

## Identity

| | |
|---|---|
| Display name | **hoopsRN** (`INFOPLIST_KEY_CFBundleDisplayName`) |
| Bundle ID | `Big-Boss-LLC.hoopr` (tests `…hooprTests`, UI tests `…hooprUITests`) |
| Deployment target | **iOS 26.5** |
| Swift | 5.0 |
| Version | `MARKETING_VERSION` 1.0, `CURRENT_PROJECT_VERSION` 1 |
| Supported platforms | `iphoneos iphonesimulator macosx xros xrsimulator` |
| Device family | `1,2,7` — iPhone, iPad, Vision |
| Info.plist | **none on disk** — `GENERATE_INFOPLIST_FILE = YES` |

Because the Info.plist is generated, plist keys are build settings. The location
permission string is `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` =
"hoopsRN needs your location to find nearby basketball courts." Editing it means
editing the build setting, not a file.

The iOS 26.5 target is unusually restrictive for an app with no 26-only API
requirement — see `GAPS.md`.

**The product was renamed hoopsRN on 2026-08-15, and the rename was deliberately
shallow.** What changed: the home-screen name (`CFBundleDisplayName`), the two
user-facing strings that said "Hoopr" (the location prompt and the sign-in
wordmark), the log subsystem (`com.hoopsrn`), the invite URL scheme
(`hoopsrn://`), and the docs. What did **not** change, and still says `hoopr`:
the bundle ID, the Xcode target and scheme names, `CFBundleName`, the
`hoopr/`, `hooprTests/` and `hooprUITests/` directories, the Swift module, and
every `hoopr`-prefixed identifier in `Theme.swift` and `Typography.swift`. The
bundle ID is the reason — `GoogleService-Info.plist` binds
`Big-Boss-LLC.hoopr` to the Firebase app, so changing it needs a new iOS app
registered in the Firebase console (project `hoopsrn-4f1e9`) and a fresh plist,
and it orphans existing installs. If the identifiers are renamed later, the
agreed prefix is `hoops` — `hoopsOrange`, `hoopsFont`.

**File-system-synchronized groups.** All three targets use
`PBXFileSystemSynchronizedRootGroup`; the `Sources` and `Resources` build phases
are literally empty. A new Swift file or resource in `hoopr/` is picked up
automatically — no pbxproj edit, and no way to exclude a file short of moving it
out of the directory.

## Dependencies

One direct SPM dependency: `firebase-ios-sdk` **12.16.0**
(`upToNextMajorVersion`). Three products are linked into the app target:
**FirebaseAuth**, **FirebaseCore**, **FirebaseFirestore**. Analytics, Messaging,
Storage, Crashlytics are *not* linked, though transitive pins for
GoogleAppMeasurement and the ads on-device conversion SDK appear in
`Package.resolved` — 13 pins total, all transitive apart from Firebase itself.

`Package.resolved` **is** tracked, so the pins above are reproducible. It was
gitignored until 2026-08-21: `.gitignore` carried a blanket `*.xcworkspace`,
which matches the `project.xcworkspace` *directory* inside `hoopr.xcodeproj`,
and the resolved file lives under it — so a fresh clone re-resolved
`upToNextMajorVersion` to whatever was current that day. The pattern is gone;
per-user workspace state is covered by `xcuserdata/`, which matches at any
depth. **Don't reintroduce a `*.xcworkspace` rule** without checking what it
swallows.

`GoogleService-Info.plist` is committed at `hoopr/GoogleService-Info.plist`.

**`UserNotifications` needs no dependency and no project change.** It is a
system framework and auto-links; local notifications need no APNs token, which
is why `AppDelegate` still registers nothing. Real push would need FCM
(unlinked) plus a Cloud Function — see `GAPS.md`.

### The JavaScript half

`package.json` at the repo root exists for **one** purpose: running
`firestore.rules` against the Firestore emulator. The iOS app is the product;
this is test tooling.

Three dev dependencies and nothing else — `firebase-tools` (the emulator),
`firebase` (the client SDK the tests drive), and `@firebase/rules-unit-testing`
(which loads the ruleset off disk and mints authenticated contexts). The runner
is Node's built-in `node:test`, **deliberately**: this repository has no
JavaScript test culture to match, and a second test framework is a second thing
to keep working.

`node_modules/` is gitignored and already contained 27 unrelated packages before
any of this — `axios` and its transitives, belonging to
`location-decoder-script/`, which declares them in its own `package.json`.
Somebody ran `npm install` from the repo root. Left alone they are harmless;
deleted, that script needs its own `npm install` in its own directory.
`firestore-tests/README.md` says so, so nobody deletes the wrong thing.

## Assets

`Assets.xcassets` holds only `AppIcon.appiconset` (14 declared slots, **no
images**) and `AccentColor.colorset` (**no colour defined**). Nothing in the app
references an asset catalogue entry — every colour comes from `Theme.swift` and
every icon is an SF Symbol. `.gitignore` covers the usual Xcode noise plus
`node_modules/` and `*.xcworkspace`.

## Repo tooling

`tools/check_context_drift.py` is the context dictionary's own pre-check: it
parses every entry's `Scope`/`Verified` header, diffs the owned paths against
the **working tree** (not just `HEAD`, so uncommitted work counts), and reports
which entries are stale. It lives under `tools/` beside the court scripts but
has nothing to do with court data — it's owned here so a change to it doesn't
mark `COURT_DATASET.md` stale.

It **validates that scope paths exist** before diffing, and leads its report
with a `BROKEN SCOPE` section when they don't. That check is the whole reason to
trust the rest of the output: `git diff <sha> -- <path>` exits 0 with empty
output for a pathspec that matches nothing, so before this an entry with a
typo'd scope was reported CURRENT forever — which is exactly how
`database/USER_PROFILE_WORKFLOW.md` sat two weeks stale with a code map
pointing at a deleted file.

**The directories it scans are listed explicitly in `entry_files()`, not
walked** — `context/*.md`, plus `context/database/` and `context/gaps/`. Adding
a subdirectory under `context/` therefore means adding a line to that function,
and forgetting to is worse than a typo'd scope: every entry in the new folder is
silently unchecked forever, with no `BROKEN SCOPE` line to say so, because the
tool never learns the file exists. `INDEX.md` says this too, next to the
`gaps/` description.

It also folds `git status --porcelain`'s untracked files into every entry's
diff, not just `git diff`'s tracked changes. `git diff <sha> -- <path>` only
ever compares content git already knows about, so a brand-new file — created,
never staged — was invisible to this tool from the moment it landed, no matter
whose scope it fell in. Two new test files and `CourtHeat.swift` sat unowned
this way for one drift-check run during the heat-map work before the tool was
fixed to look for them.

```bash
python3 tools/check_context_drift.py
```

## Firebase CLI surface

Four files at the repo root, all version controlled and authoritative — the
Firebase console is not:

```
.firebaserc              → default project: hoopsrn-4f1e9
firebase.json            → rules, indexes, and the Firestore emulator on 8080
firestore.rules          → security rules (source of truth)
firestore.indexes.json   → composite indexes: six, across three collections
```

Any rules or index change must be deployed:

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

`--dry-run` compiles the rules and reads the index file without changing the
project — worth running before any deploy.

Until deployed, writes fail with `permission-denied` and the app shows "Not
allowed to save yet." A newly created database denies everything.

**`singleProjectMode` is off in `firebase.json`, deliberately.** `node --test`
runs the rules files in parallel processes against one shared emulator, so with
a single project ID one file's `clearFirestore()` deletes another file's
fixtures mid-run — surfacing as a rules `Null value error` on a document seeded
a moment earlier, which reads as a rules bug and isn't one. A project per test
file makes them independent of the runner's concurrency.

### A dry-run is not a test

This is the distinction the whole rules suite exists for.
`firebase deploy --dry-run` proves the file **compiles**. It cannot evaluate
whether a write is allowed, and every `allow` in `firestore.rules` had only ever
been *read* until `firestore-tests/` existed.

That stopped being tolerable at `matchTickets`, whose claim is a contested
single-document transaction between two squads' leaders — the one place
correctness depends on Firestore's concurrency guarantees rather than on
anybody's code. It matters again at `seasonGames`' reporting rules, whose entire
subject is two different people agreeing or disagreeing: a property no
single-client test can exercise.

```bash
npm install        # once
npm run test:rules # starts the emulator, runs every *.test.mjs, shuts it down
npm run emulators  # or: keep one running while you iterate
```

Needs a JDK (`brew install openjdk`). The suite **fails loudly** when no
emulator answers rather than skipping, because a rules suite that reports green
for a ruleset it never evaluated is worse than no rules suite at all.

## Tests

There are **two** suites, in two languages, and neither can do the other's job.

- **`hooprTests` — 457 test methods across 28 suites**, from a green
  `-only-testing:hooprTests` run on 2026-09-18. All of them carry real coverage;
  there is no scaffold left in `hooprTests/`.
- **`firestore-tests/` — 102 tests**, run by `npm run test:rules` against the
  Firestore emulator. This is the only place `firestore.rules` is *evaluated*
  rather than read; see "A dry-run is not a test" above. (Counted directly from
  the suite on 2026-09-17, including the two burst-rate-floor tests added to
  `match-tickets.test.mjs` and the three added to `results.test.mjs` — not
  re-run here, since this environment has no JDK for the emulator; see
  `firestore-tests/README.md`.)

  **`claim-race.test.mjs` is the one that races rather than asserts.** It runs
  two commits against one ticket, and two squads committing against *each
  other*, fifteen rounds each, and requires exactly one match to survive. The
  second of those is a regression test with a known failing baseline: run
  against the pre-fix ruleset it produces two winners and two matches, which is
  the duplicate-match bug users were seeing.

**Every Swift test targets a `nonisolated static` pure function.** No test in
the suite instantiates a service, and there are no service stubs anywhere in
`hooprTests/`. That is a design constraint, not an accident: logic that can't be
reached as a pure function is, in this project, untestable — which is why
`MatchRules` is a free function over two structs rather than a method on
`MatchmakingService`, and why `SeasonGameNotifications` decides what to schedule
while `NotificationService` merely schedules it.

Two suites are the deliberate exceptions, and both measure UIKit rather than
logic: `TabBarLabelTests` renders a real tab bar, and `ThemeContrastTests`
resolves real colours. A third measurement style would be one too many.

| Suite | Cases | Guards |
|---|---|---|
| `SeasonGameTests` | 47 | The derived record and form guide, the report derivation and what a report write contains, who may report and when, create-time validation mirroring the rules, and the queue windows. |
| `MatchRulesTests` | 43 | The pure matchmaker: every hard rule rejecting in isolation, soft-rule ordering, relaxation over time, window arithmetic across midnight and DST, empty pool, self-match. Lost the stale-claim cases when the atomic commit deleted the window they pinned. |
| `SquadTests` | 31 | Decoding, name and roster bounds, leadership, the icon/colour allowlists. |
| `GameTests` | 28 | Decoding, derived status, form validation, roster membership, visibility, presentation, the invite-link string, distance. |
| `MatchTicketTests` | 22 | Ticket validation, claimability, `isSearching` vs. `isClaimable`, `winPercentage`'s unplayed midpoint. |
| `FirestoreRulesParityTests` | 21 | Every bound mirrored between Swift and `firestore.rules`, parsed out of the rules file as text — including the `open` -> `matched` transition and the two burst-rate floors. |
| `LocalRunsViewModelTests` | 24 | Which button a run offers; whether the host may mark a run complete (host-only, not before tip-off, not twice, and a roster of one is still a run); and the friends-on-a-run join: resolving an edge from either side of the stored pair, never counting yourself, both rosters, sorted and deduped, and the badge's own singular/plural copy. |
| `FindAMatchViewModelTests` | 18 | `gameCountsByCourt` — the per-court/per-day join behind the map's heat colours and pin counts — plus `rankActive`, the **Now** segment's ordering: soonest run first, distance/name tiebreaks, `isVisible(at:)` filtering, and that every `ActiveCourt` has at least one game. |
| `UserProfileTests` | 17 | Decoding, the radius coercion ladder, name validation. |
| `SquadViewModelTests` | 17 | `invitableUids`, the roster sort, and the region derivation. |
| `ServiceFailureTests` | 17 | Backoff schedule, per-listener recovery, read/write messaging, `FirestoreFailure` classification. |
| `MapTabDetentTests` | 17 | The bottom sheet's detent transitions. |
| `FriendsViewModelTests` | 16 | `looksLikeUserId`, search-stream `merged`, `relationship`. |
| `HomeViewModelTests` | 15 | `rankHotCourts` — ordering, the `displayName` tie-break, zero/absent counts dropped, the limit, unknown court ids ignored. |
| `SeasonGameNotificationsTests` | 13 | The scheduling plan: three reminders for a future match, none for one already started, stable identifiers across a reschedule. |
| `ClaimPolicyTests` | 13 | Jitter, the three-attempt bound, and the backoff poll. |
| `ThemeContrastTests` | 12 | Every colour pairing the UI actually draws, against WCAG AA — including all eight crest fills against `hooprOnCrest` — plus the tracked brand-as-foreground gaps asserted in the failing direction. |
| `MatchmakingViewModelTests` | 12 | `Phase.phase(ticket:nextGame:committedGame:hasSettlingTimedOut:)` — searching vs. settling vs. matched vs. idle, including a spent ticket that outlives its match by hours and a match that never arrives past `settlingGrace`. |
| `CourtSearchTests` | 11 | Court name matching and ranking. |
| `FriendshipTests` | 10 | Decoding, the derived document ID, direction. |
| `CourtHeatTests` | 10 | `CourtHeat.color(forGameCount:)`'s five stops, its clamps, and the ramp's shape. |
| `CourtFilterTests` | 10 | The court filter predicates. |
| `SeasonsAccessibilityTests` | 8 | Dynamic Type behind the Seasons tab: that a fixed-diameter pill keeps its glyph inside its own circle at every content size, and that the cap making that true is load-bearing. |
| `LocationServiceTests` | 6 | The home-location anchor. |
| `CourtTests` | 6 | `Court.displayName`. |
| `CourtBadgesTests` | 6 | `amenities(for:limit:)` — that narrowing a row's badges never drops the "Restricted" caution. |
| `CourtMarkerTests` | 4 | Marker count formatting and truncation. |
| `TabBarLabelTests` | 3 | That four tab labels fit the narrowest bar at `.accessibility3` — the evidence behind "Seasons" over "Squad". |

### The rules suite

`firestore-tests/` covers what only an emulator can:

| File | Guards |
|---|---|
| `claim-race.test.mjs` | Two shapes, fifteen rounds each: concurrent clients racing one ticket, and two squads committing against *each other*. **Exactly one match survives either way** — the guarantee the atomic commit rests on, and the second shape is a regression test with a known failing baseline against the pre-fix ruleset. |
| `squads.test.mjs` | The three squad update paths in isolation, the self-join uid diff, the duplicate-roster hole, the invite friendship gate. |
| `match-tickets.test.mjs` | Ticket bounds, the `open` -> `matched` transition (no more `claimed`), and the two burst-rate floors: a squad younger than 5s can't queue, a ticket younger than 5s can't be abandoned and requeued. |
| `season-games.test.mjs` | What authorizes naming another squad — **both** tickets' `getAfter()` proof, not just the home one — the court/window pinning, and the forged-leader refusal. |
| `arrival.test.mjs` | Self-add only, no undo, no duplicates, refused once a match leaves `scheduled`. |
| `results.test.mjs` | Mutual confirmation, evaluated with **two distinct authenticated leaders** — agreement confirms, disagreement disputes, a leader cannot write the other's report or manufacture an agreement alone, a disputed match is resolved by re-reporting, and the per-leader 5s re-touch floor doesn't catch two different leaders' first reports arriving moments apart. |

`UserProfileTests`, `GameTests` and
`FriendshipTests` run through `Firestore.Decoder` — the same decoder the
services use — so a field rename in the console or in the model fails a test
rather than silently emptying the UI. `ServiceFailureTests` covers error
classification and `ListenerSupervisor`'s backoff, `FirestoreRulesParityTests`
parses `firestore.rules` and fails when a mirrored bound drifts,
`FriendsViewModelTests` covers the Friends pane's three pure decisions, and
`CourtTests` pins `Court.displayName`.

`CourtTests` (six cases) is the only coverage of a `Court`, and it earns its
place because `displayName` is a string substitution rendered on six screens:
boilerplate stripped, a trailing `#2` suffix kept, whitespace collapsed, case
insensitivity, the strip-to-nothing fallback, and a name without the boilerplate
left alone.

`CourtHeatTests` pins `CourtHeat.color(forGameCount:)` by resolved hex — zero
through four games each land on their own stop, everything at or above four
clamps to the same reddish orange rather than indexing off the end of the
array, and a negative count clamps to the quietest stop instead of crashing.
Two further cases assert the ramp's *shape* rather than its values: that every
stop is darker than the one before it, and that the steps are evenly sized. The
hex assertions alone can't distinguish a deliberate retune from one that
accidentally flattens two tiers into looking identical.
`FindAMatchViewModelTests` covers the join underneath it:
`gameCountsByCourt` dedupes a game that appears on both `queuedGames` and
`publicGames` (a public run the signed-in user also hosts or joined) down to
one, buckets by calendar day rather than a rolling 24 hours, and counts a
private run the same as a public one — deliberately, since by the time a game
reaches either array the read rule has already decided this account may see
it.

`GameTests` covers the stored `games` shape, pending server timestamps, the
`in_progress` raw value, required-field failures, and the pure rules the client
shares with `firestore.rules`: derived status, roster clamping, membership
queries, and the visibility grace window.

`UserProfileTests` is worth knowing in more detail, because most of it isn't
about decoding at all:

| Group | Guards |
|---|---|
| Decoding | The full stored shape (`Timestamp` → `Date`), a freshly provisioned document (no `homeCourtId`), a missing `userName` failing loudly rather than rendering blank, and unresolved `serverTimestamp()` sentinels not crashing the decoder. |
| `testIgnoresALegacyEmailField` | A document still carrying the purged `email` field decodes fine. Accounts written before the field was removed still exist. |
| Radius coercion | Six cases over `effectivePreferredRadius` — integer values, unset, stored-overrides-default, **zero**, out-of-range, and the range bounds. Zero is the one that matters: a perfectly good `Double` that would silently empty the nearby list. |
| Name validation | Five cases over `UserProfile.validate(userName:)`, including length measured *after* trimming. |

`FriendsViewModelTests` exercises the three `nonisolated static` helpers on
`FriendsViewModel` — they're static precisely so they can be tested without
Firebase, a live service, or a main actor:

| Test group | Guards |
|---|---|
| `looksLikeUserId` | Which typed text is *also* tried as an exact user ID. A 28-char ASCII alphanumeric yes; names, hyphenated IDs, non-ASCII, and absurd lengths no. |
| `merged` | Exact-ID hit ranks first, duplicates collapse by uid, the signed-in user is dropped without consuming a result slot, and the cap holds. |
| `relationship` | Direction read off `requestedBy` from *both* sides of a pair — the case a naive `uidA == me` implementation gets wrong. |

The only scaffold left is `hooprUITests/LaunchTests.swift` (launch + screenshot
attachment). The empty `hooprTests/hooprTests.swift` and the second UI test file
were deleted on 2026-08-15; every file in `hooprTests/` now carries real
coverage.

Worth testing and currently untested: `RootViewModel`'s gating rule,
`FindAMatchViewModel`'s plain nearby-radius `ranked(courts:from:)` (as opposed
to `rankActive`, now covered — see above), and the four `mapped(_:)` error
translations. (`MapTab`'s detent transitions were on this list until
`MapTabDetentTests` landed — see the suite table above. The zoom-conversion
round-trip named here until 2026-08-21 is gone — so are the functions.)

---

## Invariants

- The repo is authoritative for Firebase config. Rules edited in the console are
  lost on the next deploy.
- Deployment target, bundle ID, and the location usage string live in
  `project.pbxproj` build settings — there is no Info.plist to edit.
- New Firebase products must be added as SPM product dependencies *and* used
  only behind the vendor boundary (`ARCHITECTURE.md`).
- **Never hand-edit `project.pbxproj` to add a file.** The project is
  `objectVersion = 77` with `PBXFileSystemSynchronizedRootGroup`: any `.swift`
  file under `hoopr/` or `hooprTests/` is picked up automatically, and system
  frameworks auto-link. Editing it corrupts a synchronized group and the project
  stops opening.
- **Run the Swift suite with `-only-testing:hooprTests`, always.** Without it
  the UI test runner fails to launch (`RequestDenied` from SpringBoard) and
  masks real unit failures — a green-looking run that proved nothing.
- A rules or index change is not verified by a dry-run. Run `npm run test:rules`
  before claiming a rule works.
- A new mirrored bound gets a `FirestoreRulesParityTests` case in the same
  commit. A mismatch surfaces as `permission-denied` at runtime, not as a
  compile error.

## See also

- `database/DATABASE_SCHEMA.md` — the rules these deploy commands ship.
- `ARCHITECTURE.md` — where the SDK is allowed to be imported.
- `GAPS.md` — untested areas and the deployment-target question.
