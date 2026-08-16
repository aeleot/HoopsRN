# hoopsRN — Build and Config

**Scope:** `hoopr.xcodeproj/`, `Package.resolved`, `hooprTests/`, `hooprUITests/`,
`hoopr/Assets.xcassets/`, `hoopr/GoogleService-Info.plist`, `.gitignore`
**Verified:** 2026-08-13 @ map-tab

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

`GoogleService-Info.plist` is committed at `hoopr/GoogleService-Info.plist`.

## Assets

`Assets.xcassets` holds only `AppIcon.appiconset` (14 declared slots, **no
images**) and `AccentColor.colorset` (**no colour defined**). Nothing in the app
references an asset catalogue entry — every colour comes from `Theme.swift` and
every icon is an SF Symbol. `.gitignore` covers the usual Xcode noise plus
`node_modules/` and `*.xcworkspace`.

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

Six suites carry the real coverage: `UserProfileTests`, `GameTests` and
`FriendshipTests` run through `Firestore.Decoder` — the same decoder the
services use — so a field rename in the console or in the model fails a test
rather than silently emptying the UI. `ServiceFailureTests` covers error
classification and `ListenerSupervisor`'s backoff, `FirestoreRulesParityTests`
parses `firestore.rules` and fails when a mirrored bound drifts, and
`FriendsViewModelTests` covers the Friends tab's three pure decisions.

`GameTests` covers the stored `games` shape, pending server timestamps, the
`in_progress` raw value, required-field failures, and the pure rules the client
shares with `firestore.rules`: derived status, roster clamping, membership
queries, and the visibility grace window.

`UserProfileTests`:

| Test | Guards |
|---|---|
| `testDecodesStoredDocumentShape` | The full stored document, `Timestamp` → `Date` included. |
| `testDecodesMinimalDocument` | A freshly provisioned profile: no `email`, no `homeCourtId`. Both must stay optional. |
| `testMissingUserNameFailsToDecode` | A missing `userName` must fail loudly, not render blank. |
| `testDecodesPendingServerTimestamps` | Unresolved `serverTimestamp()` sentinels read back as null must not crash decoding. |

`FriendsViewModelTests` exercises the three `nonisolated static` helpers on
`FriendsViewModel` — they're static precisely so they can be tested without
Firebase, a live service, or a main actor:

| Test group | Guards |
|---|---|
| `looksLikeUserId` | Which typed text is *also* tried as an exact user ID. A 28-char ASCII alphanumeric yes; names, hyphenated IDs, non-ASCII, and absurd lengths no. |
| `merged` | Exact-ID hit ranks first, duplicates collapse by uid, the signed-in user is dropped without consuming a result slot, and the cap holds. |
| `relationship` | Direction read off `requestedBy` from *both* sides of a pair — the case a naive `uidA == me` implementation gets wrong. |

Everything else is Xcode scaffold: `hooprTests/hooprTests.swift` (empty
`testExample` + `measure {}`), `hooprUITests/hooprUITests.swift`, and
`hooprUITestsLaunchTests.swift` (launch + screenshot attachment).

Worth testing and currently untested: `MapView.zoomLevelFromSpan` /
`spanFromZoomLevel` round-tripping, `RootViewModel`'s gating rule,
`FindAMatchViewModel.nearby(courts:to:)` filtering and ordering, and both
`mapped(_:)` error translations.

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
