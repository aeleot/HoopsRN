# hoopsRN — Build and Config

**Scope:** `hoopr.xcodeproj/`, `hooprTests/`, `hooprUITests/`,
`hoopr/Assets.xcassets/`, `hoopr/GoogleService-Info.plist`, `.gitignore`,
`tools/check_context_drift.py`
**Verified:** 2026-08-21 @ 0edbeec

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
firebase.json            → points at the rules and indexes files
firestore.rules          → security rules (source of truth)
firestore.indexes.json   → composite indexes: two, both for `games`
```

Any rules or index change must be deployed:

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

`--dry-run` compiles the rules and reads the index file without changing the
project — worth running before any deploy.

Until deployed, writes fail with `permission-denied` and the app shows "Not
allowed to save yet." A newly created database denies everything.

## Tests

**112 test methods across ten suites**, from a green
`-only-testing:hooprTests` run on 2026-08-21. All of them carry real coverage;
there is no scaffold left in `hooprTests/`.

| Suite | Cases | Guards |
|---|---|---|
| `GameTests` | 21 | Decoding, derived status, form validation, roster membership, visibility, presentation, the invite-link string, distance. |
| `UserProfileTests` | 17 | Decoding, the radius coercion ladder, name validation. |
| `FriendsViewModelTests` | 16 | `looksLikeUserId`, search-stream `merged`, `relationship`. |
| `ServiceFailureTests` | 15 | Backoff schedule, per-listener recovery, read/write messaging, `FirestoreFailure` classification. |
| `FriendshipTests` | 10 | Decoding, the derived document ID, direction. |
| `ThemeContrastTests` | 8 | Every colour pairing the UI actually draws, against WCAG AA. |
| `CourtHeatTests` | 8 | `CourtHeat.color(forGameCount:)`'s five stops, its ceiling and floor clamps. |
| `CourtTests` | 6 | `Court.displayName`. |
| `FirestoreRulesParityTests` | 6 | The `status` derivation and the shared bounds, parsed out of `firestore.rules`. |
| `FindAMatchViewModelTests` | 5 | `gameCountsByCourt` — the per-court/per-day join behind the map's heat colours. |

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
clamps to the same deep red rather than indexing off the end of the array, and
a negative count clamps to the quietest stop instead of crashing.
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
`FindAMatchViewModel`'s ranking and radius filtering, `MapTab`'s detent
transitions, and the four `mapped(_:)` error translations. (The zoom-conversion
round-trip named here until 2026-08-21 is gone — so are the functions.)

---

## Invariants

- The repo is authoritative for Firebase config. Rules edited in the console are
  lost on the next deploy.
- Deployment target, bundle ID, and the location usage string live in
  `project.pbxproj` build settings — there is no Info.plist to edit.
- New Firebase products must be added as SPM product dependencies *and* used
  only behind the vendor boundary (`ARCHITECTURE.md`).

## See also

- `database/DATABASE_SCHEMA.md` — the rules these deploy commands ship.
- `ARCHITECTURE.md` — where the SDK is allowed to be imported.
- `GAPS.md` — untested areas and the deployment-target question.
