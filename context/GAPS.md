# Hoopr — Gaps and Drift

**Scope:** —
**Verified:** 2026-08-07 @ 2d483bb

What's unfinished, and where comments or docs contradict the code. Read this
before trusting an inline comment, and before assuming a feature exists because
a field or a tab does. Drift is recorded **here** rather than being reproduced
in the entry that owns the code.

---

## Unfinished

**Features**

- `LocalGamesTab` and `FindMatchTab` are placeholder labels — a centred `Text`
  and nothing else. Two of the three tabs are empty.
- The court detail sheet shows name and address only. `hoops`, `surface`,
  `isLit`, `isCovered` and `access` decode from the dataset and are read
  **nowhere in the app**.
- No occupancy, check-in, game creation, or match-making of any kind.
  `FindAMatchViewModel.select(_:)` is an empty hook.
- Auth has sign-in, sign-up, and sign-out only. No password reset, no social
  login, no account deletion — and `firestore.rules` denies profile deletes
  outright, so account deletion needs a rules change too.
- Distances and the recenter target are anchored to a hardcoded Durham point
  (`LocationService.defaultLocation`), not the device's location. Device
  location is requested on the first recenter tap only, so MapKit can draw the
  blue dot. `LocationService.userLocation` is published but **never consumed**.

**Assets and data**

- `AppIcon.appiconset` declares 14 image slots and contains no images;
  `AccentColor.colorset` has no colour defined. The app ships with the default
  placeholder icon.
- `courts_updated.json` (135 courts, `"lat,lon"` string IDs, flat array) is
  committed and bundled but never loaded — it wouldn't decode as a
  `CourtDataset` if it were. It's the abandoned output of
  `location-decoder-script/reverseGeocode.js`.
- `tools/build_courts.py` can't be re-run: its inputs (`raw_triangle.json`,
  `sites_raw.json`) aren't in the repo.
- The ODbL attribution string is loaded into `CourtService.attribution` and
  never displayed. That's a licence obligation currently unmet.
- `Color.hooprDarkOrange` is declared and unused.

**Code quality**

- `RootViewModel` and `FindAMatchViewModel` use `assign(to:\.x, on: self)`
  stored in `self`'s own cancellable set — a retain cycle.
  `ProfileViewModel` has a comment explaining why it uses `sink { [weak self] }`
  instead; the other two don't follow it. Invisible today because both live as
  long as the screens that own them.
- Light mode only. No `colorScheme` handling anywhere; every colour is a literal
  RGB value and text is written as `.black` / `Color.white` directly.
- Fonts are all `.system(size:)` literals — no Dynamic Type.

**Configuration**

- Deployment target is **iOS 26.5**, which excludes almost every device in use
  and isn't required by any API the app calls. Worth confirming this is
  intentional rather than an artifact of the Xcode version it was created with.
- `SUPPORTED_PLATFORMS` includes `macosx` and `xros` and the device family is
  `1,2,7` (iPhone, iPad, Vision), but the UI is iPhone-portrait-shaped
  throughout — `UIScreen.main.bounds` is read directly for sheet sizing.

## Untested

Only `hooprTests/UserProfileTests.swift` is real coverage. Untested and worth
it: `MapView`'s zoom-conversion inverses, `RootViewModel`'s gating rule,
`FindAMatchViewModel.nearby(courts:to:)`, and both `mapped(_:)` error
translations. `hooprTests/hooprTests.swift` and both UI test files are Xcode
scaffold.

---

## Known drift

Comments and docs that contradict the code as of 2d483bb. **The code wins.**

| Where | Says | Actually |
|---|---|---|
| `firestore.rules:6` | points at `"hoopr project info/DATABASE_SCHEMA.md"` | the file is `context/database/DATABASE_SCHEMA.md` |
| `Models/UserProfile.swift:26` | `homeCourtId` is "Read but never written yet — no UI sets it" | `UserProfileService.updateHomeCourt` writes it and `HomeCourtPickerSheet` sets it |
| `hooprTests/UserProfileTests.swift:14` | `homeCourtId` is what "the app reads but never writes" | same — the comment predates the picker |
| `tools/build_courts.py:32` | `LAUNCH_CITIES = {"Durham", "Raleigh"}` | the shipped dataset has six cities; the other four were appended by `fetch_city_courts.py` |
| `tools/fetch_city_courts.py:39` | mirrors "CourtSearchService.swift used to try" | `CourtSearchService.swift` no longer exists — the live-query path was removed |
| `context/PROJECT_CONTEXT.md` *(deleted at 2d483bb+)* | iOS 17.0 target, `ProfileTab.swift`, "unit test scaffold (empty)" | superseded by this dictionary; deleted during the rebuild |

Anything else that reads as stale should be corrected in place and recorded
here, not left to be rediscovered.

## See also

- `INDEX.md` — where each subject actually lives.
- `BUILD_AND_CONFIG.md` — the identity values behind the configuration notes.
