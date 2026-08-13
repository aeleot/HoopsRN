# Hoopr — Gaps and Drift

**Scope:** —
**Verified:** 2026-08-13 @ map-tab

What's unfinished, where comments or docs contradict the code, and what to do
next. Read this before trusting an inline comment, and before assuming a feature
exists because a field or a tab does. Drift is recorded **here** rather than
being reproduced in the entry that owns the code.

---

## Unfinished

**Features**

- `FindMatchTab` is a placeholder label — a centred `Text` and nothing else.
  (`LocalGamesTab` was replaced by `LocalRunsTab`, which is real.)
- The court detail sheet shows name, address and a Start Run button. `hoops`,
  `surface`, `isLit`, `isCovered` and `access` decode from the dataset and are
  read **nowhere** except the filter chips.
- No occupancy or check-in. Games exist — scheduling, joining, leaving,
  cancelling — but match-making does not. See `plans/LIVE_HEADCOUNT.md`.
- **Runs have no invites.** `isPublic: false` makes a run undiscoverable, and
  nothing else can reach it, so an invite-only run currently holds only its
  host. The visibility flag is half a feature until invites land.
- **No waitlist promotion.** When a confirmed player leaves a full run, the
  freed slot isn't handed to the first waitlisted player — the update rule
  forbids writing another user's uid, deliberately. Needs a host action or a
  Cloud Function.
- **No host controls for `in_progress` / `completed`.** Both statuses are
  declared and neither is ever written; runs age out `Game.visibilityGrace`
  (3h) after tip-off instead.
- Game cards show court, time, roster, distance and capacity only. Player
  names, avatars, and any per-run detail screen are unbuilt. Names would need a
  read across `users` and a privacy decision, not just a UI.
- Auth has sign-in, sign-up, and sign-out only. No password reset, no social
  login, no account deletion — and `firestore.rules` denies profile deletes
  outright, so account deletion needs a rules change too.
- Distances and the recenter target are anchored to a hardcoded Durham point
  (`LocationService.homeLocation`), not the device's location. Device location
  is requested on the first recenter tap only, so MapKit can draw the blue dot.
  `LocationService.userLocation` is published but **never consumed**.

**Reliability**

- **A listener killed by a terminal error never recovers.** Firestore retries
  transient failures itself, but `permissionDenied` and `failedPrecondition`
  (a missing or still-building index) tear the listener down for good, and
  `GameService` only re-attaches on an auth change. Observed live: both Local
  Runs listeners died on a building index and stayed dead until the app was
  relaunched, with the error visible only in the log. Same exposure exists in
  `UserProfileService`.
- Firestore's own `permission-denied` for an **undeployed ruleset** is
  indistinguishable from a genuine authorization failure. Both services map it
  to a message naming the rules, which is right far more often than not — but
  it means a real authorization bug would read as a deployment problem.

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

**Code quality**

- `RootViewModel` uses `assign(to:\.destination, on: self)` stored in `self`'s
  own cancellable set — a retain cycle. `ProfileViewModel` and
  `LocalRunsViewModel` both carry a comment explaining why they use
  `sink { [weak self] }` instead; `RootViewModel` is now the only holdout.
  Invisible today because it lives as long as the screen that owns it.
- Light mode only. No `colorScheme` handling anywhere; every colour is a literal
  RGB value and text is written as `.black` / `Color.white` directly.
- Fonts are all `.system(size:)` literals — no Dynamic Type.
- `Game.status` is duplicated by necessity: once in Swift
  (`Game.status(playerCount:maxPlayers:)`) and once as an expression in
  `firestore.rules`. There is no mechanism keeping them in step, and a
  divergence surfaces as `permission-denied` on every write rather than as a
  logic error. Tested on the Swift side only.

**Configuration**

- Deployment target is **iOS 26.5**, which excludes almost every device in use
  and isn't required by any API the app calls. Worth confirming this is
  intentional rather than an artifact of the Xcode version it was created with.
- `SUPPORTED_PLATFORMS` includes `macosx` and `xros` and the device family is
  `1,2,7` (iPhone, iPad, Vision), but the UI is iPhone-portrait-shaped
  throughout — `UIScreen.main.bounds` is read directly for sheet sizing in
  `FindAMatchTab`, which also warns as deprecated on iOS 26.

## Untested

`UserProfileTests` and `GameTests` are the real coverage (32 cases). Both decode
through `Firestore.Decoder`, and `GameTests` additionally pins the pure rules the
client shares with `firestore.rules`.

Untested and worth it: `MapView`'s zoom-conversion inverses, `RootViewModel`'s
gating rule, `FindAMatchViewModel`'s nearby filtering and ordering,
`LocalRunsViewModel.action(for:)` and its radius/dedupe filtering, all three
`mapped(_:)` error translations, and — most valuable and hardest — the security
rules themselves, which encode real decisions (membership diffs, duplicate
rosters, pinned timestamps) that manual testing checks poorly. There is no
emulator setup in the repo. `hooprTests/hooprTests.swift` and both UI test files
are Xcode scaffold.

---

## Known drift

Comments and docs that contradict the code. **The code wins.**

| Where | Says | Actually |
|---|---|---|
| `Models/UserProfile.swift:25` | `homeCourtId` is "Reserved for a future preference. Read but never written yet — no UI sets it" | `UserProfileService.updateHomeCourt` writes it and `HomeCourtPickerSheet` sets it |
| `hooprTests/UserProfileTests.swift:13` | `homeCourtId` is what "the app reads but never writes" | same — the comment predates the picker |
| `tools/build_courts.py:32` | `LAUNCH_CITIES = {"Durham", "Raleigh"}` | the shipped dataset has six cities; the other four were appended by `fetch_city_courts.py` |
| `tools/fetch_city_courts.py:39` | mirrors "CourtSearchService.swift used to try" | `CourtSearchService.swift` no longer exists — the live-query path was removed |
| `context/prompts/*.md` | cite `firestore.rules` pointing at `"hoopr project info/…"` as standing drift | fixed; the prompts use it as a stale worked example |

Resolved since the last pass, kept here only so they aren't re-reported:
`firestore.rules` header path, `Color.hooprDarkOrange` being unused (it is now
the map marker tint), and `FindAMatchViewModel`'s `assign(to:on:)` retain cycle.

Anything else that reads as stale should be corrected in place and recorded
here, not left to be rediscovered.

---

## Next steps

Roughly in order of value per unit of effort. Each names the files it touches so
it can be picked up cold.

### 1. Deploy the pending rules change — one command

`firestore.rules` in the repo is **ahead of the deployed ruleset**:
`favoriteCourtIds` was added to the `users` update rule, and duplicate-roster
guards were added to `games`.

```bash
firebase deploy --only firestore:rules
```

Until this lands, every star tap fails server-side and reverts silently. This is
the two-step rule biting for the second time — see `database/DATABASE_SCHEMA.md`.

### 2. Decide how long a finished run stays listed

Currently `Game.visibilityGrace` is **3 hours** after `scheduledTime`, applied in
two places that must agree: the Firestore query's cutoff, and
`Game.isVisible(at:)` re-applied on every rebuild.

Raising it (6h was floated) is a one-constant change in `Models/Game.swift`. The
real issue is subtler and worth fixing at the same time: **the query's cutoff is
fixed when the listener attaches.** A session left open overnight keeps querying
against last night's cutoff. `isVisible(at:)` hides those rows client-side, so
nothing wrong is displayed — but the query keeps paying for them, and the
`limit(to:)` budget is spent on runs that will never render.

Options, cheapest first: recompute on foreground via `scenePhase` and re-attach;
or drop the range clause from the query and filter entirely client-side (removes
one composite index, costs more reads); or move retirement server-side with a
scheduled Cloud Function writing `status: "completed"` — which is also what
unblocks step 4.

### 3. Make listeners recover from terminal errors

See *Reliability* above. A `failedPrecondition` or `permissionDenied` currently
means "relaunch the app," and the user is told nothing beyond a banner. Add a
bounded retry with backoff in `GameService.handle(_:error:describing:assign:)`
that re-invokes `startObserving` on those two codes. `UserProfileService` has the
same exposure and should get the same treatment.

### 4. Waitlist promotion — needs a Cloud Function

The update rule deliberately forbids writing another user's uid, so promotion
cannot be done by the leaving client. A scheduled or triggered Function running
with admin credentials is the intended answer, and the same Function is the
natural home for `in_progress` / `completed` transitions. **This is the first
thing in the project that requires the Blaze plan** — worth confirming before
designing around it.

### 5. Invites, to complete invite-only

`isPublic: false` is half a feature today. Minimum viable: a share link carrying
the `gameId`, plus a rule allowing a read by anyone holding it. That's a real
security decision — an unguessable ID is not an authorization model — so it
deserves its own design rather than an afternoon.

### 6. Confirm the tip-off default across time zones

`CreateGameViewModel.defaultTipOff` computes now + 1h rounded up to the quarter
hour. On the simulator at 00:54 local it produced a picker showing **5:00 AM**,
a three-hour gap that suggests a mismatch between the simulator clock and the
`DatePicker`'s display zone rather than the arithmetic. Reproduce on a device
before changing anything — `Date(timeIntervalSinceReferenceDate:)` rounding is
zone-independent, so the arithmetic is probably innocent.

### 7. Rules testing

The rules now carry the project's most consequential logic — the membership
diff, pinned server timestamps, derived status, duplicate rosters — and none of
it is covered. `firebase emulators:exec` with a rules test suite is the standard
answer and would pay for itself the first time someone edits `hasOnly`.

### 8. Smaller, self-contained

- Fix `RootViewModel`'s retain cycle to match the other two view models.
- Consume `LocationService.userLocation` so distances follow the device;
  `homeLocation` is the single seam and every distance follows it.
- Display the ODbL attribution — an outstanding licence obligation.
- Surface `hoops` / `surface` / `isLit` on the court detail sheet; the data is
  already decoded and already shown on `CourtRow` badges.
- Replace `UIScreen.main.bounds` in `FindAMatchTab` with a context-derived
  screen; it's the only deprecation warning in the build.

## See also

- `INDEX.md` — where each subject actually lives.
- `BUILD_AND_CONFIG.md` — the identity values behind the configuration notes.
- `database/DATABASE_SCHEMA.md` — the two-step rule that step 1 exists to close.
- `plans/LIVE_HEADCOUNT.md` — the check-in feature, still unbuilt.
