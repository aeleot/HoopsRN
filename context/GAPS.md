# hoopsRN — Gaps and Drift

**Scope:** —
**Verified:** 2026-08-21 @ 9a81cc2

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
- `location-decoder-script/reverseGeocode.js` writes its output to
  `hoopr/Resources/courts_updated.json` — inside the bundled directory. The
  stale copy that sat there unloaded has been deleted, but re-running the script
  puts it straight back into the app bundle.
- `tools/build_courts.py` can't be re-run: its inputs (`raw_triangle.json`,
  `sites_raw.json`) aren't in the repo.
- The ODbL attribution string is decoded into `CourtDataset` and then
  **discarded** — `CourtService` keeps only `courts`, and there is no
  `attribution` property anywhere to display. That's a licence obligation
  currently unmet, and closing it means holding the value as well as rendering
  it. (This entry said the string was "loaded into `CourtService.attribution`"
  until 2026-08-21; no such property has ever existed. `CourtService` now
  publishes `loadError`, but still keeps no `attribution`.)
- ~~A court-dataset load failure is completely silent.~~ **Fixed 2026-08-21.**
  `CourtService` publishes `loadError`, `FindAMatchViewModel` mirrors it as
  `datasetError`, and the map's empty state reports "Court data unavailable"
  ahead of any per-tab wording — a broken bundle no longer reads as "no courts
  within 5 miles". Still no retry, deliberately: the dataset ships in the app
  bundle, so a failure is a build problem rather than a transient one.

**Accessibility**

- **`hooprOrange` fails WCAG AA as a *foreground* in light mode.** It measures
  2.29:1 on `hooprBackground` and `hooprSurface` and 2.10:1 on `hooprFill` —
  under the 4.5:1 text floor *and* the 3:1 graphic floor. Dark mode is fine
  (10.24 / 8.29 / 6.79), because the orange is lifted there and the grounds are
  dark. Affected: `ProfileRow`'s leading symbols, `PlayerAvatar`'s initials
  (genuinely text), `CourtRow`'s filled star, `GameCard`'s and `MapTab`'s
  basketball glyphs, the map's recenter glyph, `ProfileIdentityBlock`'s avatar
  ring.
  *(`hooprOrange` was softened — desaturated, same hue — on 2026-08-21 as a
  pure taste change, unrelated to this gap and not meant to address it. It
  moved these ratios slightly further under the floor, from 2.55 / 2.34, because
  pulling saturation toward white also pulls a colour's own luminance toward
  white's. Worth knowing before assuming a future retune of the brand colour
  fixes this for free — it can just as easily make it worse.)*
  The fix is a second brand role — a deepened orange for marks that are *read*
  rather than filled — plus a sweep of those call sites. The reverted palette
  had exactly this and called it `hooprBrandText` (`git show
  a6e5668:hoopr/Support/Theme.swift`), tuned to 42% lightness for 4.99:1; that
  value is coral, not orange, so it can't be lifted verbatim.
  `ThemeContrastTests.testBrandAsForegroundIsATrackedGap` pins the current
  failing state and **fails the moment the gap closes**, so it can't be
  forgotten. Add the real assertions in the same change that adds the role.

  **Updated 2026-08-26 — the tab bar is now this gap's most prominent
  instance.** Navigation moved to a native `TabView` whose selected item takes
  `hooprOrange` via `.tint`, which colours the glyph *and* its ~10pt label. The
  old shell's pills never hit this: they painted the brand as a *fill* with
  `hooprOnBrand` on top, which passes at 6.61:1. In light mode the selected tab
  label now reads *lighter* than the unselected ones, inverting the hierarchy it
  exists to signal. Shipped as a deliberate product decision, with the numbers
  known: `hooprDarkOrange` was measured as an alternative and reaches only
  ~3.85:1 — it clears the graphic floor and still misses the text one — and a
  monochrome bar passes but drops the brand from the app's most-seen control. A
  starting value of roughly `#B4491E` measures ~5.4:1 on white and is the
  cheapest honest fix. `ThemeContrastTests.testTabBarSelectionIsATrackedGap`
  records it the same failing-direction way.
  *(Fixed on 2026-08-21: the same revert had left `hooprOnBrand` as white on
  that orange at 2.55:1 / 2.25:1, on every primary button. It is now black —
  8.24:1 / 9.33:1 — with `hooprOnRed` split out for the one label on a red
  fill, where the required colour inverts with the appearance.)*

**Invariant violations**

- ~~`Court.displayName` is not used everywhere a court is named.~~ **Fixed
  2026-08-21.** `LocalRunsViewModel.Listing.courtName` and `CreateGameSheet`'s
  title both rendered the raw `name`, so a run's card and the form that creates
  it said "Long Meadow Park Basketball Court #2" while every other surface said
  "Long Meadow Park #2". Both were collateral from `eb67f1c` reverting the
  palette commit, which had bundled `Court.displayName` into the same change;
  `da44193` restored the property and most callers but missed these two. Both
  now use `displayName`.
  *(The home-court picker's **search** still matches over the full `name` —
  deliberate, a wider haystack rather than a violation.)*

**Code quality**

- `firestore.rules` still has **no repeatable behavioural coverage**.
  `FirestoreRulesParityTests` pins the constants and the `status` derivation
  that Swift also owns, but nothing evaluates the rules themselves — that a
  non-member can't read a private run, that the membership diff really does
  reject writing someone else's uid. The `friendships` block was validated by
  hand on 2026-08-14 (see the Friends TODO), which proves it was correct that
  day and nothing about the next edit. That needs the Firebase emulator, which
  isn't set up.
- ~~`CourtRow.badges` is dead and already wrong.~~ **Fixed 2026-08-21.** Both
  it and the unused `CourtBadges.labels(for:)` are deleted. `CourtBadges` is
  now the only definition of what a court's amenity chips say.

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
- ~~`Package.resolved` is gitignored.~~ **Fixed 2026-08-21.** `.gitignore`'s
  `*.xcworkspace` line matched the `project.xcworkspace` *directory* inside
  `hoopr.xcodeproj`, so the SPM pins were untracked and a fresh clone
  re-resolved `upToNextMajorVersion` to whatever was current that day. The
  pattern is gone — the per-user state it was meant to catch is already covered
  by the `xcuserdata/` rule, which matches at any depth — and the file is now
  tracked, so the versions `BUILD_AND_CONFIG.md` states are reproducible.
- Deployment target is **iOS 26.5**, which excludes almost every device in use
  and isn't required by any API the app calls. Worth confirming this is
  intentional rather than an artifact of the Xcode version it was created with.
- `SUPPORTED_PLATFORMS` includes `macosx` and `xros` and the device family is
  `1,2,7` (iPhone, iPad, Vision), but the UI is iPhone-portrait-shaped
  throughout. `MapTab`'s sheet now sizes off `onGeometryChange` rather than
  `UIScreen.main.bounds`, so it at least follows its container — but nothing
  else has been checked at another shape.

## Untested

Seven suites. 85 cases were counted from a green `-only-testing:hooprTests` run
on 2026-08-15; `CourtTests`' six have been added since and the suite has not been
re-counted, so treat 91 as arithmetic rather than an observed number.
`UserProfileTests`, `GameTests` and `FriendshipTests`
decode through the real
`Firestore.Decoder` and pin the pure rules the client shares with
`firestore.rules`; `FirestoreRulesParityTests` parses the rules file and fails if
either copy of a shared constant moves alone; `ServiceFailureTests` covers the
re-attach schedule, per-listener recovery, and the read/write split in the error
messages.

Untested and worth it: `RootViewModel`'s gating rule, `MapTab`'s detent
transitions and the `displayDetent` rule that keeps a detail card on screen,
`FindAMatchViewModel`'s nearby filtering and ordering,
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
`Court.displayName` moved out of this list on 2026-08-21 — `CourtTests` covers it.

The UI test target currently fails to launch its runner
(`hooprUITests.xctrunner`, `RequestDenied` from SpringBoard), so `xcodebuild
test` has to be scoped with `-only-testing:hooprTests`.

---

## Known drift

Comments and docs that contradict the code. **The code wins.**

| Where | Says | Actually |
|---|---|---|
| `context/prompts/*.md` | cite `firestore.rules` pointing at `"hoopr project info/…"` as standing drift | fixed; the prompts use it as a stale worked example |

**Nothing else is outstanding.** Every other row this table carried was
corrected in the code on 2026-08-21 rather than recorded here: `UserProfile`'s
`homeCourtId` doc (it *is* written), `UserProfileTests`' matching comment,
`build_courts.py`'s `LAUNCH_CITIES` (now says the shipped file has six cities),
`fetch_city_courts.py`'s reference to the deleted `CourtSearchService.swift`,
`CourtRow`'s dead `badges`, `CourtTests`' "six screens" claim, `firestore.rules`
protecting a removed `email` field, and `MainTabView`'s "three tabs".

Resolved on 2026-08-21 by the full rebuild, kept here only so they aren't
re-reported: `database/USER_PROFILE_WORKFLOW.md` carried a `Scope` of
path *fragments* (`AuthService`, `Views/Profile/`) that matched nothing in the
repo, so `check_context_drift.py` reported it "current" for two weeks while its
code map pointed at a deleted file. It now declares no scope at all and is
revisited by hand, like this entry.

Resolved earlier, same purpose:
`firestore.rules` header path, `Color.hooprDarkOrange` being unused (it is now
the map marker tint), `FindAMatchViewModel`'s `assign(to:on:)` retain cycle,
`MapTab`'s `UIScreen.main.bounds` deprecation, the bundled-but-unloaded
`courts_updated.json`, and the court attribute fields going unread.

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

- Register `hoopsrn` under `CFBundleURLSchemes` — the scheme `InviteLink`
  actually mints, not `hoopr` — and handle `.onOpenURL` in
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

- Consume `LocationService.userLocation` so distances follow the device;
  `homeLocation` is the single seam and every distance follows it.
- Display the ODbL attribution — `CourtService` discards it today, so this
  means holding the value as well as rendering it.
- Give `hooprOrange` a readable companion role so it can be used as a
  foreground without failing AA in light mode — see **Accessibility** above.
  **Raised in priority 2026-08-26:** the tab bar's selected item is now the
  most-seen instance of this failure, and `MainTabView`'s `.tint` is the single
  call site that would consume the new role first.
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
