# Hoopr — Build and Config

**Scope:** `hoopr.xcodeproj/`, `Package.resolved`, `hooprTests/`, `hooprUITests/`,
`hoopr/Assets.xcassets/`, `hoopr/GoogleService-Info.plist`, `.gitignore`
**Verified:** 2026-08-07 @ 2d483bb

Project identity, dependencies, the Firebase CLI surface, and what the tests
actually cover. Read this before changing a build setting, adding a dependency,
or assuming something is tested.

---

## Identity

| | |
|---|---|
| Bundle ID | `Big-Boss-LLC.hoopr` (tests `…hooprTests`, UI tests `…hooprUITests`) |
| Deployment target | **iOS 26.5** |
| Swift | 5.0 |
| Version | `MARKETING_VERSION` 1.0, `CURRENT_PROJECT_VERSION` 1 |
| Supported platforms | `iphoneos iphonesimulator macosx xros xrsimulator` |
| Device family | `1,2,7` — iPhone, iPad, Vision |
| Info.plist | **none on disk** — `GENERATE_INFOPLIST_FILE = YES` |

Because the Info.plist is generated, plist keys are build settings. The location
permission string is `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` =
"Hoopr needs your location to find nearby basketball courts." Editing it means
editing the build setting, not a file.

The iOS 26.5 target is unusually restrictive for an app with no 26-only API
requirement — see `GAPS.md`.

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
firestore.indexes.json   → composite indexes: empty, none needed yet
```

Any rules change must be deployed:

```bash
firebase deploy --only firestore:rules
```

Until deployed, writes fail with `permission-denied` and the app shows "Not
allowed to save yet." A newly created database denies everything.

## Tests

**`hooprTests/UserProfileTests.swift` is the only real coverage.** Four cases,
run through `Firestore.Decoder` — the same decoder `UserProfileService` uses —
so a field rename in the console or in the model fails a test rather than
silently emptying the profile UI:

| Test | Guards |
|---|---|
| `testDecodesStoredDocumentShape` | The full stored document, `Timestamp` → `Date` included. |
| `testDecodesMinimalDocument` | A freshly provisioned profile: no `email`, no `homeCourtId`. Both must stay optional. |
| `testMissingUserNameFailsToDecode` | A missing `userName` must fail loudly, not render blank. |
| `testDecodesPendingServerTimestamps` | Unresolved `serverTimestamp()` sentinels read back as null must not crash decoding. |

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
