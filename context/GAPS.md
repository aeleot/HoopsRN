# hoopsRN — Gaps and Drift

**Scope:** —
**Verified:** 2026-08-15 @ map-tab

What's unfinished, where comments or docs contradict the code, and what to do
next. Read this before trusting an inline comment, and before assuming a feature
exists because a field or a tab does. Drift is recorded **here** rather than
being reproduced in the entry that owns the code.

Dated **TODO** sections track a single feature's remaining work from the point
it partly shipped; the general "Next steps" list below is everything else.

---

## Unfinished

**Features**

- **Name search can't see an account until its owner has opened the app since
  the `userNameLower` backfill shipped.** `UserProfileService` writes the
  missing search key on the owner's own client, because the update rule is
  owner-only and there's no Cloud Function to do it server-side — so the
  migration completes one account at a time, as people launch the app. Anyone
  who hasn't is findable by user ID but not by name. Nothing more can be done
  about this from the client; a real backfill needs an admin-SDK script run
  against the project.
- **No blocking, reporting, or rate limiting on friend requests.** Anyone
  signed in can search for anyone and send them a request; declining (which
  deletes the edge) is the only recourse, and nothing stops the same person
  asking again. The client bounds the *accidental* case — 300ms search debounce,
  20-result cap, one write in flight — but a modified client isn't bound by any
  of that, and a server-side limit needs Cloud Functions (Blaze plan). Phase 5
  in `plans/FRIENDS.md`.
- **Another player's profile shows a chosen subset, which isn't the same as
  privacy.** `PlayerProfileSheet` renders name, home court and joined, and
  deliberately leaves `favoriteCourtIds` and `preferredRadius` off — but `users`
  documents are readable whole by any signed-in account, so those fields are
  still on the wire. The real fix is the owner-only `users/{uid}/private/…`
  subcollection named in `database/DATABASE_SCHEMA.md`; it hasn't been built.
- **Friends' private runs stay invisible.** Friendship doesn't factor into the
  `games` read rule and can't without a rules change — see the note under
  invite-only runs below, which this overlaps with.
- The court detail sheet shows name, address and a Start Run button. `hoops`,
  `surface`, `isLit`, `isCovered` and `access` decode from the dataset and are
  read **nowhere** except the filter chips.
- No occupancy or check-in. Games exist — scheduling, joining, leaving,
  cancelling — but match-making does not. See `plans/LIVE_HEADCOUNT.md`.
- **An invite link can be sent but not opened.** A host can copy
  `hoopsrn://game/{id}` from the create sheet and from the run's card in Queued
  Games (shipped 2026-08-15), and that's the whole of it: `hoopsrn://` isn't a
  registered URL scheme, nothing implements `.onOpenURL`, and the `games` read
  rule still refuses a non-member, so a recipient who taps the link gets
  nothing. An invite-only run still holds only its host. §4 below has the
  receiving half.
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
- Auth has sign-in, sign-up, sign-out, and a password reset (the profile's
  `Password` card mails a link via `AuthService.sendPasswordResetEmail(to:)`).
  No social login and no account deletion — and `firestore.rules` denies
  profile deletes outright, so account deletion needs a rules change too.
- The reset uses Firebase's **default hosted reset page**. No
  `ActionCodeSettings`, so the link doesn't come back into the app, and the
  email is Firebase's default template with the project's name on it. Both are
  console/config work rather than code. The app is also never told when the
  link is used, so nothing in it reflects "password last changed".
- Distances and the recenter target are anchored to a hardcoded Durham point
  (`LocationService.homeLocation`), not the device's location. Device location
  is requested on the first recenter tap only, so MapKit can draw the blue dot.
  `LocationService.userLocation` is published but **never consumed**.

**Reliability**

- The recovery path in `ListenerSupervisor` is covered by unit tests but has
  **never been exercised against a live terminal error** — doing so means
  deploying a broken ruleset or dropping an index on the real project. The
  wiring is verified; the end-to-end heal is not.

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

- `firestore.rules` still has **no repeatable behavioural coverage**.
  `FirestoreRulesParityTests` pins the constants and the `status` derivation
  that Swift also owns, but nothing evaluates the rules themselves — that a
  non-member can't read a private run, that the membership diff really does
  reject writing someone else's uid. The `friendships` block was validated by
  hand on 2026-08-14 (see the Friends TODO), which proves it was correct that
  day and nothing about the next edit. That needs the Firebase emulator, which
  isn't set up.

**Configuration**

- **The app is called hoopsRN; everything structural still says `hoopr`.** The
  2026-08-15 rename was deliberately shallow — display name, user-facing
  strings, log subsystem and URL scheme only. The bundle ID, target and scheme
  names, module name, the three source directories, and every `hoopr`-prefixed
  identifier in `Theme.swift`/`Typography.swift` are unchanged. This is not
  drift to be quietly repaired: the bundle ID is pinned by
  `GoogleService-Info.plist` and can't move without a new Firebase iOS app
  registration and a fresh plist. `BUILD_AND_CONFIG.md` has the full split, and
  the agreed prefix (`hoops`) if the identifiers are ever renamed.
- Deployment target is **iOS 26.5**, which excludes almost every device in use
  and isn't required by any API the app calls. Worth confirming this is
  intentional rather than an artifact of the Xcode version it was created with.
- `SUPPORTED_PLATFORMS` includes `macosx` and `xros` and the device family is
  `1,2,7` (iPhone, iPad, Vision), but the UI is iPhone-portrait-shaped
  throughout — `UIScreen.main.bounds` is read directly for sheet sizing in
  `MapTab`, which also warns as deprecated on iOS 26.

## Untested

Six suites, 85 cases (counted from a green `-only-testing:hooprTests` run on
2026-08-15; the "65" recorded here previously was stale).
`UserProfileTests`, `GameTests` and `FriendshipTests`
decode through the real
`Firestore.Decoder` and pin the pure rules the client shares with
`firestore.rules`; `FirestoreRulesParityTests` parses the rules file and fails if
either copy of a shared constant moves alone; `ServiceFailureTests` covers the
re-attach schedule, per-listener recovery, and the read/write split in the error
messages.

Untested and worth it: `MapView`'s zoom-conversion inverses, `RootViewModel`'s
gating rule, `FindAMatchViewModel`'s nearby filtering and ordering,
`LocalRunsViewModel.action(for:)` and its radius/dedupe filtering,
`FriendsViewModel`'s profile-resolution cache (including the
name-that-never-resolves case), the four
`mapped(_:)` error translations, and — most valuable and hardest — what the
security rules actually *permit* (membership diffs, duplicate rosters, pinned
timestamps), which the parity tests deliberately don't touch. The `friendships`
rules have been walked through by hand once; `games` never has, and neither is
re-run by anything. There is no emulator setup in the repo.
`hooprUITests/LaunchTests.swift` is Xcode scaffold. (`hooprTests/hooprTests.swift`
and the second UI test file, named here until 2026-08-15, are gone.)

The UI test target currently fails to launch its runner
(`hooprUITests.xctrunner`, `RequestDenied` from SpringBoard), so `xcodebuild
test` has to be scoped with `-only-testing:hooprTests`.

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

## TODO — Friends (opened 2026-08-13)

What's left on the friends feature specifically, kept together so it isn't
scattered through the general list below. Phases refer to `plans/FRIENDS.md` §8.

**Shipped:** the `friendships` collection and its rules (Phase 1), and the
Friends tab's respond-and-view half (Phase 2). Both are deployed and running.

### Verification — done by hand, 2026-08-14

The six two-account checks in the Phase 1 prompt were all validated manually by
the repo owner against the live project, closing what had been open since Phase
1 shipped:

- [x] A participant can read their own edge, and the listeners attach without a
      permission error — confirmed live on 2026-08-13.
- [x] The recipient can accept: `pending` → `accepted` with `uidA`/`uidB`/
      `requestedBy` unchanged, and the row re-buckets from Requests to Friends
      on the snapshot with no refresh.
- [x] A third account is refused a read — a friendship isn't visible to
      strangers.
- [x] The requester cannot accept their own request.
- [x] Create through the rules, rather than seeded in the console:
      `isOrderedPair`, `idMatchesPair` and the `request.time` pinning all hold
      against a real client write.
- [x] The three deletes (decline, cancel, unfriend), and a declined pair's
      deterministic ID is re-usable afterwards.
- [x] The simultaneous-request collision resolves to an accept rather than a
      surfaced `permission-denied`.
- [x] `searchProfiles(matching:)` against a real prefix, alongside
      `profiles(for:)`, which was already confirmed working.

**This was a one-time manual pass, not coverage.** Nothing in the repo re-runs
it: there's no emulator, and the throwaway script used during Phase 1 lived in a
session scratchpad and is gone. Any future edit to the `friendships` block, or
to the `users` key allowlists, is unverified until someone repeats these six
checks by hand — see "Untested".

### To build

- ~~**Phase 3 — discovery.**~~ **Shipped 2026-08-15.** Search (name prefix +
  exact ID), `PlayerProfileSheet`, `InboxSheet` with its badge, and `FriendRow`
  replacing `FriendCard`. No backend change — Phase 1 already had every service
  method. One thing it did *not* clear: **`sendRequest`'s simultaneous-request
  collision handling still hasn't run against a live pair.** It's now reachable
  from the UI for the first time, but reaching it needs two accounts sending to
  each other before either sees the other's request, and that hasn't been done.
- **Phase 4 — friends' public runs.** `LocalRunsViewModel` gains
  `friendService`, `GameCard` grows an "N friends here" badge. No rules, index,
  or listener — a client-side intersection of two lists the app already holds.
  `MainTabView` already has `friendService` to pass in.
- **Friend profile detail.** `plans/FRIENDS.md` §6 says tapping a friend shows
  name + home court. Not built, and it needs the visibility question below
  settled first.

### Data and privacy debt

- **Existing accounts have no `userNameLower`.** It's only written at
  provisioning or when a name is saved, so every account created before it
  existed — including the developer's — is invisible to Phase 3's search until
  its owner re-saves their name once. Either backfill it or accept that search
  misses older accounts; don't discover this when search "doesn't work".
- **Decide what `users` is allowed to contain.** `email` was removed and purged
  for being world-readable to any signed-in account, and both create and update
  now carry key allowlists. `homeCourtId` and `favoriteCourtIds` are still
  there and are a location pattern attached to a named person. The standard fix
  is a public document plus an owner-only `users/{uid}/private/…`
  subcollection — which Phase 5's blocking list will need regardless.
- **Test data is live.** A hand-seeded friendship between the developer's
  account and `chaseallen122` exists in the production project. Delete it when
  it stops being useful.

### Deferred on purpose (Phase 5)

Blocking and reporting — note there is **no rate limit and no block**, so anyone
who learns a uid can send unlimited requests. Push notifications on request and
acceptance. Unique handles and typo-tolerant search. Friends' *private* runs,
which needs a real authorization design and overlaps with invite-only games
(§4 below).

---

## Next steps

Roughly in order of value per unit of effort. Each names the files it touches so
it can be picked up cold.

> **Deployed as of 2026-08-13:** rules and both `games` indexes are live,
> including the `favoriteCourtIds` fix, the duplicate-roster guards, the
> `friendships` block, and the `users` create/update key allowlists. Nothing
> below is blocked on a deploy.

### 1. Decide how long a finished run stays listed

Currently `Game.visibilityGrace` is **3 hours** after `scheduledTime`, applied in
two places that must agree: the Firestore query's cutoff, and
`Game.isVisible(at:)` re-applied on every rebuild.

Raising it (6h was floated) is a one-constant change in `Models/Game.swift`. The
real issue is subtler and worth fixing at the same time: **the query's cutoff is
fixed when the listener attaches.** A session left open overnight keeps querying
against last night's cutoff. `isVisible(at:)` hides those rows client-side, so
nothing wrong is displayed — but the query keeps paying for them, and the
`limit(to:)` budget is spent on runs that will never render.

`GameService.attachListeners()` now recomputes the cutoff every time it runs, so
a re-attach picks up a fresh window — but it only runs on sign-in and on
recovery, so a healthy long-lived session still holds its original cutoff.

Options, cheapest first: recompute on foreground via `scenePhase` and re-attach;
or drop the range clause from the query and filter entirely client-side (removes
one composite index, costs more reads); or move retirement server-side with a
scheduled Cloud Function writing `status: "completed"` — which is also what
unblocks step 1.

### 2. Rules coverage, via the Firebase emulator

`FirestoreRulesParityTests` keeps the *shared constants* honest, but nothing
tests what the rules actually permit. The emulator (`firebase emulators:exec`)
plus `@firebase/rules-unit-testing` would let the membership diff, the
read rule, and the host-only delete be asserted directly — the checks that
carry the real security weight. Needs a Node test target, not a Swift one.

### 3. Waitlist promotion — needs a Cloud Function

The update rule deliberately forbids writing another user's uid, so promotion
cannot be done by the leaving client. A scheduled or triggered Function running
with admin credentials is the intended answer, and the same Function is the
natural home for `in_progress` / `completed` transitions. **This is the first
thing in the project that requires the Blaze plan** — worth confirming before
designing around it.

### 4. Invites — the receiving half

**Sending shipped 2026-08-15.** `Support/InviteLink.swift` owns the
`hoopsrn://game/{id}` format, `GameService.createGame` returns the new document
ID, `CreateGameSheet` swaps to an invite step after a private run is written,
and `GameCard` repeats the link on a private run you host. `InviteLinkCard` is
the shared copy control. Nothing about the backend changed.

What's left is everything that makes the link *work*, and it's the part that
carries the security decision:

- Register `hoopr` under `CFBundleURLSchemes` and handle `.onOpenURL` in
  `hooprApp`, stashing the pending `gameId` across a cold start and a sign-in.
- Split the `games` `read` rule into `get` (any signed-in user, by direct
  document reference) and `list` (unchanged). **This is the decision, not a
  detail: an unguessable ID is not an authorization model.** The alternative is
  an `inviteToken` field checked in the rule, which is a schema change and a
  rotation story. Pick one deliberately.
- `GameService.fetchGame(byId:)` plus an `InviteJoinView` covering the states a
  link can land in: already on the roster, full (waitlist), aged out, deleted.

`context/prompts/invitation_for_private_game.md` has the full worked design,
including the view-model skeleton. Its §3 (share sheet) and §5 (private badge)
are satisfied — the copy link replaces the `UIActivityViewController`, and the
card already carries a lock and "Invite only".

### 5. Confirm the tip-off default across time zones

`CreateGameViewModel.defaultTipOff` computes now + 1h rounded up to the quarter
hour. On the simulator at 00:54 local it produced a picker showing **5:00 AM**,
a three-hour gap that suggests a mismatch between the simulator clock and the
`DatePicker`'s display zone rather than the arithmetic. Reproduce on a device
before changing anything — `Date(timeIntervalSinceReferenceDate:)` rounding is
zone-independent, so the arithmetic is probably innocent.

### 6. Rules testing

The rules now carry the project's most consequential logic — the membership
diff, pinned server timestamps, derived status, duplicate rosters — and none of
it is covered. `firebase emulators:exec` with a rules test suite is the standard
answer and would pay for itself the first time someone edits `hasOnly`.

### 7. Smaller, self-contained

- Fix `RootViewModel`'s retain cycle to match the other two view models.
- Consume `LocationService.userLocation` so distances follow the device;
  `homeLocation` is the single seam and every distance follows it.
- Display the ODbL attribution — an outstanding licence obligation.
- Surface `hoops` / `surface` / `isLit` on the court detail sheet; the data is
  already decoded and already shown on `CourtRow` badges.
- Replace `UIScreen.main.bounds` in `MapTab` with a context-derived
  screen; it's the only deprecation warning in the build.
- Rename `FindAMatchViewModel` to match `MapTab`. The view was renamed when the
  third tab became Friends; its view model wasn't, so the file backing the
  court map is still named for matchmaking.

## See also

- `INDEX.md` — where each subject actually lives.
- `BUILD_AND_CONFIG.md` — the identity values behind the configuration notes.
- `database/DATABASE_SCHEMA.md` — the two-step rule, and how `favoriteCourtIds`
  fell through it.
- `plans/LIVE_HEADCOUNT.md` — the check-in feature, still unbuilt.
- `plans/FRIENDS.md` — the design behind the TODO above; Phases 1–2 shipped,
  3–5 still proposals.
