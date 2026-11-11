# Plan — Pre-Launch Audit

**Status:** proposed. Every unchecked box below is open work.
**Audited:** 2026-10-18 @ `ff9bbe2` (branch `queue-system`, working tree clean)
**Supersedes:** [`LAUNCH_READINESS.md`](LAUNCH_READINESS.md). Its five items are folded in below (§4.1–4.2, §5.2, §5.6). Its summary says "every submission blocker has since shipped", and that's wrong: four App Store blockers are still open (§2).
**Touches:** the whole app, `firestore.rules`, `hoopr.xcodeproj`, the Firebase console, App Store Connect

> `context/plans/` isn't a dictionary entry, carries no `Scope`/`Verified`
> stamp, and isn't drift-checked. As each item ships, fold what's now true into
> the entry that owns it, file anything still open in the right `gaps/` file,
> and delete the item from here.

---

## 1. Verdict

**The engineering is in good shape. The product isn't ready to submit yet.**

The code is clean, both test suites pass, and the security rules are well
built. What stands between this build and real users is mostly *around* the
code:

- four App Store requirements the app doesn't meet yet (§2)
- seven bugs a first-time user will hit within minutes (§3)
- the production plumbing that makes launch week observable (§4)

None of these needs a redesign. The rough size: **about 1–2 weeks of focused
work plus one two-phone device pass**, then TestFlight.

### What was verified in this audit, and how

| Check | Result | How |
|---|---|---|
| Swift unit tests | ✅ **811 / 811 pass** across 48 suites, 0 runtime warnings | `xcodebuild test … -only-testing:hooprTests` on an isolated iPhone 17 Pro (iOS 26.5) sim, counted from the `.xcresult` |
| Security-rules tests | ✅ **148 / 148 pass** | `npm run test:rules` against the Firestore emulator |
| Compiler warnings | ⚠️ **10 in the app target, 27 in tests**. All are Swift 6 concurrency diagnostics, none is a correctness bug today. | Build log of the run above (§5.1) |
| Crash-prone constructs | ✅ 0 `try!`, 0 `TODO`/`FIXME`. 1 `fatalError` (the standard `init(coder:)` stub). 2 force unwraps, both on constants that can't fail. | grep sweep of `hoopr/` |
| Query ↔ index coverage | ✅ Every composite query in `Services/` has a matching index in `firestore.indexes.json` | Each `whereField`/`order` chain checked against the index list |
| Vendor boundary | ✅ No `import Firebase*` outside `Services/` and `hooprApp.swift` | grep |
| Rules deploy freshness | ✅ `firestore.rules` last changed 2026-10-09 (`b7968c2`), the same day `ROADMAP.md` records the deploy | `git log -- firestore.rules`. **Still confirm in the console** (§4.3). |
| Docs vs code | ⚠️ 6 of 7 dictionary entries stale, 24 source paths owned by no entry, several false claims (§6) | `python3 tools/check_context_drift.py` plus reading each entry by hand |
| App icon | ✅ All three 1024² variants present, none has an alpha channel | `sips -g hasAlpha` |

---

## 2. P0: App Store submission blockers

Each of these is either a written App Review rule or an upload-time check. Expect a rejection, or a failed upload, until all four are closed.

### 2.1 No in-app account deletion (Guideline 5.1.1(v))

Any app that lets people create an account must also let them delete it from
inside the app. hoopsRN has no delete path at all. `firestore.rules:117` is
`allow delete: if false` on `users`, and there's no UI for it.
[`gaps/PROFILES.md`](../gaps/PROFILES.md) records the gap but doesn't flag it as a blocker.

**Doable on Spark, with no Cloud Function.** Every write the cleanup needs is
already one the rules let the owner make. The order matters, because each
step needs the account to still exist:

- [ ] **Re-authenticate first.** `User.delete()` throws `requiresRecentLogin`
      on any session older than a few minutes. Prompt for the password and
      call `reauthenticate(with:)`.
- [ ] **Season play:** cancel any `scheduled` match the user's squad is in
      (`SeasonGameService.cancelGame(bySquadId:)`), withdraw the squad's open
      ticket (`MatchmakingService.leaveQueue`), then disband squads they lead
      and leave squads they're on. Delete pending `squadInvites` in both
      directions.
- [ ] **Runs:** cancel runs they host, and leave runs they're on or
      waitlisted for.
- [ ] **Friends:** delete every `friendships` edge. Either party may already
      do this.
- [ ] **Profile:** change `users` delete to `allow delete: if isOwner()`,
      add a rules test for it, deploy, then delete `users/{uid}`.
- [ ] Clear on-device state (§3.4), then call `Auth.auth().currentUser?.delete()`.
- [ ] Make every step idempotent, so a retry after a failure partway through
      finishes the job instead of failing on the steps already done.
- [ ] Leave `seasonGames` alone. Those records are deliberately undeletable,
      and they already denormalize squad names.

Put the entry point in Profile, below Sign Out, as a red row behind a typed
confirmation. (Once on Blaze, the Firebase *Delete User Data* extension could
replace most of the client-side cleanup.)

### 2.2 No privacy manifest (`PrivacyInfo.xcprivacy`)

There isn't one anywhere in the project. The app calls `UserDefaults`
directly through `RecentCourtsStore`, `InboxDismissalsStore`,
`CelebratedWinsStore` and `@AppStorage`. That's a *required-reason API*, and
App Store Connect flags an upload that doesn't declare it (ITMS-91053).

- [ ] Add `hoopr/PrivacyInfo.xcprivacy` to the app target with
      `NSPrivacyAccessedAPICategoryUserDefaults` → reason `CA92.1`.
- [ ] Declare the collected data types: email address, user ID, name, and
      other user content (squad names, runs). Set `NSPrivacyTracking` to
      `false`. Firebase's SDKs ship their own manifests, so the app only
      declares its own use.
- [ ] Fill in the App Store Connect privacy label to match. The device's
      location never leaves it (it's only used for distances), but a chosen
      home court and saved favourite courts are stored. Decide deliberately
      whether to label that as location.

### 2.3 No privacy policy, terms or support contact (5.1.1(i), 1.2)

A privacy policy link is required both in App Store Connect and somewhere
easy to find in the app. There's none, and there's no Terms or Support link
either: Profile's rows run Home Court → … → Joined → Sign Out
(`ProfileView.swift:432–538`).

- [ ] Write a privacy policy and terms of use, and host both. **Firebase
      Hosting is available on the Spark plan**, so
      `hoopsrn-4f1e9.web.app/privacy` costs nothing and is the same host §7.1
      wants for invite links.
- [ ] Add Privacy Policy, Terms, and Contact Support rows to Profile.
- [ ] Link the terms on the sign-up form ("By creating an account you agree
      to…").

### 2.4 User-generated content has no safeguards (Guideline 1.2)

Display names and squad names are typed by users and shown to strangers
through player search, squad crests and opponent cards. Anyone signed in can
send anyone a friend request. Guideline 1.2 asks for four things in an app
like this:

| Required | Today |
|---|---|
| A way to filter objectionable content | None. Names are length-checked only (`Squad.validate(name:)`, `UserProfile.validate(userName:)`). |
| A way to report content | None |
| A way to block abusive users | None ([`gaps/FRIENDS.md`](../gaps/FRIENDS.md)) |
| Published contact information | None (§2.3) |

Minimum set that works on Spark:

- [ ] **Report:** a "Report" action on `PlayerProfileSheet` and on an
      opponent's squad. It writes `reports/{autoId}`, with a create-only rule
      (`reporterId == request.auth.uid`, a field allowlist, no reads), and you
      review reports in the Firestore console. Apple expects "timely
      responses", so someone has to actually read them.
- [ ] **Block, enforced by the server, on Spark.** `gaps/FRIENDS.md` and
      `BACKLOG.md` B3 say blocking needs Cloud Functions. That's true for
      hiding someone from search, but not for stopping their requests. Store
      `blocks/{blockerUid}_{blockedUid}`. Because that ID can be computed,
      the `friendships` and `squadInvites` create rules can refuse the write
      with `exists(/databases/$(database)/documents/blocks/$(target)_$(request.auth.uid))`.
      Search results get filtered on the client.
- [ ] **Filter:** a word-list check on display names and squad names, on the
      client, at both validation sites. It doesn't need to be clever, it needs
      to exist.
- [ ] Contact info, as in §2.3.

---

## 3. P1: Bugs to fix before real users

Each item is a confirmed defect, with what the user sees and the fix. None of
them is in `gaps/` yet; §8 says where each one belongs.

### 3.1 A signed-out user can't reset their password

**What happens:** someone who forgets their password is locked out for good.
The login form is email, password, the submit button and the sign-in/sign-up
toggle (`LoginView.swift:70–83`). The only call to `sendPasswordResetEmail`
is `ProfileViewModel.swift:284`, which only runs when you're *signed in*.
`PRODUCT_OVERVIEW.md` lists "Password reset by emailed link" without that
caveat.

- [ ] Add **"Forgot password?"** under the password field, prefilled from
      the email field. Say "If an account exists for that email, we've sent a
      link" either way, so the screen doesn't reveal which emails have
      accounts.
- [ ] Trim with `.whitespacesAndNewlines`, not `.whitespaces`
      (`LoginViewModel.swift`). An email pasted with a trailing newline is
      currently rejected as invalid.

### 3.2 Location permission is only asked for by the Map tab's recenter button

**What happens:** on a fresh install, nothing asks for location until the
user finds and taps the ◎ button on the Map tab. That's the only caller of
`requestLocationPermission()` (`MapViewModel.swift:340`). Until then every
distance in the app is measured from downtown Durham. A new user in Raleigh,
about 25 miles away, with the default 5-mile radius, sees an empty Runs tab,
"Nothing on nearby" on Home, and wrong distances everywhere.

It gets worse once a fix does arrive: only `MapViewModel` subscribes to
`locationService.$coordinate`. `LocalRunsViewModel` and `HomeViewModel` read
`LocationService.homeLocation` when something *else* triggers a rebuild, so
they stay on the old anchor until a game snapshot happens to arrive.

- [ ] Ask for location after sign-in, ideally in onboarding (§7.1) with a
      one-line reason first, not from a map button.
- [ ] Subscribe `LocalRunsViewModel` and `HomeViewModel` to
      `$coordinate` and call `rebuild()` when it changes.
- [ ] When location is denied, say so: "Distances are from Durham. Turn on
      location in Settings", linking to `UIApplication.openSettingsURLString`.
      Today it falls back to Durham without a word.
- [ ] Optional, saves battery: `startUpdatingLocation()` never stops while
      the app is in the foreground. For distances to courts, one fix on launch
      or foreground (`requestLocation()`) is enough.

### 3.3 Landscape is turned on, but the UI was only built for portrait

`INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone` includes
`LandscapeLeft` and `LandscapeRight` in both Debug and Release
(`project.pbxproj:445, 490`), and nothing in code locks the orientation.
Rotate the phone and the map sheet's detent geometry (`SheetGeometry`), the
scoreboard and every band lay out in a shape nobody has checked.
[`gaps/CONFIGURATION.md`](../gaps/CONFIGURATION.md) says the UI is
"iPhone-portrait throughout, and the project says so". The first half is
true, the second isn't.

- [ ] Set both lines to `UIInterfaceOrientationPortrait` only.

### 3.4 Sign-out leaves the last user's notifications and on-device history

**What happens:** user A signs out and user B signs in on the same phone. B
still gets A's season-match reminders at T−60, T−0 and T+90, because
`ProfileViewModel.signOut()` (`:317`) only calls `authService.signOut()`.
Nothing removes pending notifications, and `NotificationService` has no
sign-out hook. `RecentCourtsStore`, `InboxDismissalsStore` and
`CelebratedWinsStore` are shared by every account on the device too, so B
sees A's recent courts.

- [ ] On sign-out, and on account deletion: call
      `removeAllPendingNotificationRequests()` and
      `removeAllDeliveredNotifications()`.
- [ ] Either clear the three stores on sign-out, or key them by uid.

### 3.5 Being waitlisted for a run can make it disappear

**What happens:** the `queued` listener matches on `playerIds` only
(`GameService.swift:223–228`). So a run you're *waitlisted* for appears only
if it's public **and** inside your radius. A private run you joined the
waitlist for from an invite link (which `InviteJoinSheet` offers whenever the
run is full) doesn't appear on any screen. You can't see it, you can't leave
the waitlist, and the only way back is to tap the link again. The `games`
list rule already allows reading by `queuedPlayerIds`
(`firestore.rules:171`). The client just never asks.

- [ ] Add a fourth listener: `queuedPlayerIds array-contains uid` and
      `scheduledTime > cutoff`. Merge its results into `LocalRunsViewModel.queued`
      with a "Waitlisted" badge.
- [ ] Add an index on `(queuedPlayerIds CONTAINS, scheduledTime ASC)` and
      **deploy it before the build that queries it ships.**

### 3.6 New profiles are named after the user's email address

**What happens:** `UserProfileService.fallbackUserName` (`:555`) uses the part
of the email before the `@` as the first display name. That name is stored on
a profile any signed-in account can read, and it's searchable by name. So
`jane.doe.1990@gmail.com` appears to everyone as **jane.doe.1990**. That's
most of her email address, which the comment at `:268` says is deliberately
never stored. Sign-up never asks for a name, so this is what most new users
will look like.

There are two more defects on the same path:

- **Long email names can't create a profile.** The part before the `@` can
  be 64 characters, but the create rule caps `userName` at 50
  (`firestore.rules:50–58`). Anyone whose email name is 51–64 characters gets
  `permission-denied` and has no profile at all.
- **A failed profile setup isn't retried.** `provisionProfileIfNeeded` runs
  once, from `attachListener`. If its `getDocument` fails on a network blip
  while the listener stays healthy, the listener keeps reporting "no
  document" without an error, and `currentProfile` stays `nil` until the next
  cold launch. *Likely, not reproduced.*

- [ ] Ask for a display name at sign-up (onboarding, §7.1). Until that
      exists, default to `"Hooper"` plus a short random suffix, not the
      email.
- [ ] Truncate whatever default is used to `UserProfile.maxUserNameLength`.
- [ ] When a snapshot says the profile doesn't exist and no setup is in
      progress, run the setup again.
- [ ] For existing accounts: think about a one-time prompt for anyone whose
      `userName` is still the part before the `@` in their email.

### 3.7 Disbanding a squad mid-match strands the other squad

**What happens:** `SquadService.disbandSquad` (`:473`) deletes the squad
document and nothing else. If the squad has a **scheduled** match:

- The disbanding leader loses the listener that showed the match (it's keyed
  to the squads they're on).
- The opponent's match stays `scheduled` forever, showing "Waiting on
  {squad}" for a report that can never come.

If the squad has an **open ticket**, the ticket keeps advertising a squad
that no longer exists until it expires.
[`gaps/RATE_LIMITING.md`](../gaps/RATE_LIMITING.md) mentions the ticket half;
the stranded match isn't recorded anywhere. The rules already let a leader
cancel a match and delete their own ticket, and both checks use IDs stored on
those documents (`firestore.rules` seasonGames cancel clause, matchTickets
delete), so this works on Spark.

- [ ] In `SquadViewModel.disband`, **before** the delete: cancel any
      scheduled match, then withdraw the ticket. Or block the disband with
      "Cancel your match first".
- [ ] Same treatment in the account-deletion flow (§2.1).

### 3.8 Cancelling a run deletes it without telling anyone (UX bug)

**What happens:** `GameService.cancelGame` deletes the document, so players
on the roster just see the card disappear. Someone who checked in the
afternoon can drive to the court that evening for a run that no longer
exists.

- [ ] Cancel softly instead: a host-only rules clause sets
      `status: cancelled`, and participants keep a "Called off by the host"
      card until the run's visibility window ends. The list queries and
      `isVisible(at:)` need to handle the new status. *Product call, but
      recommended.*

---

## 4. P1: Production operations

### 4.1 Observability (from `LAUNCH_READINESS.md` §1–2)

- [ ] **App Check with App Attest, in monitoring mode.** About 10 lines in
      `hooprApp.init()` before `FirebaseApp.configure()`, with the simulator
      guard. Switch to enforcement once the console shows verified traffic.
      This is what turns every per-account limit in
      [`gaps/RATE_LIMITING.md`](../gaps/RATE_LIMITING.md) from a speed bump
      into a real limit.
- [ ] **Crashlytics plus dSYM upload.** Also record non-fatal errors on the
      `FirestoreFailure` paths. `ListenerSupervisor` recovers silently by
      design, so a listener that never comes back looks like "the list is
      slow" and produces no crash. Non-fatals are the only way you'd see it.

### 4.2 The Spark plan's free daily limits will cap growth

The Spark plan allows **50,000 document reads a day**. Past that, every
request fails until the daily reset, for every user at once. A cold launch
attaches listeners capped at:

- 100 public runs
- up to 500 completed runs (the user's lifetime history)
- 200 season matches
- up to 2 × 100 squad invites
- friendships, squads, the profile, and the calendar's month query

Listeners that reconnect within about 30 minutes resume cheaply; a true cold
start re-reads everything. At around 100 reads per cold open, the limit runs
out at a few hundred daily users opening the app 2–3 times a day. Hostile
traffic is a separate risk (`LAUNCH_READINESS.md` §1); this is just normal
growth.

- [ ] **Make the [`ROADMAP.md`](../ROADMAP.md) §0 decision now.** Moving to
      Blaze removes the hard daily cap, costs very little at this scale, and
      also unlocks Cloud Functions, which the six features §0 lists are
      waiting on. **Set a budget alert the same day.**
- [ ] Either way, re-reading up to 500 completed runs on every launch just to
      compute a count and a streak is the most expensive listener in the app.
      Cap it to the weeks the streak actually needs, and keep the lifetime
      count as a stored counter.

### 4.3 Firebase console checklist

- [ ] Confirm the live rules and indexes match the repo (Firestore →
      Rules → version history). Re-run `npm run test:rules` before every
      future deploy.
- [ ] In Auth settings, check **email enumeration protection** is on.
      Customize the password-reset email (sender name, template, and
      `ActionCodeSettings`, optionally linking back to the app).
- [ ] Decide whether to require email verification at sign-up
      ([`gaps/PROFILES.md`](../gaps/PROFILES.md)).
- [ ] Remove test data from production: the test friendship with
      `chaseallen122` (ROADMAP §4), and any test runs or squads.
- [ ] Find and fix anyone still on two squads
      ([`gaps/SEASONS.md`](../gaps/SEASONS.md), "It isn't retroactive"). Only
      a console query over `squads` can answer this.

### 4.4 Release engineering

- [ ] **No `DEVELOPMENT_TEAM` is set** in `project.pbxproj`. Archiving needs
      one. Set it, then **run on a physical iPhone.** Every pass so far has
      been on a simulator, which is why haptics and App Attest are untested.
- [ ] Merge `queue-system` → `main`. `main` is from 2026-08-22, 70 commits
      behind this branch, and 7 of the local commits haven't been pushed.
      Release from `main` and tag the commit.
- [ ] Add `ITSAppUsesNonExemptEncryption = NO` (the app only uses HTTPS), so
      uploads stop asking the export-compliance question.
- [ ] Bump `CURRENT_PROJECT_VERSION` on every upload. It's `1` now.
- [ ] **Support iOS 18 or not.** The deployment target is iOS 18.0, but no
      fallback path has ever run
      ([`gaps/CONFIGURATION.md`](../gaps/CONFIGURATION.md)). Either install
      an iOS 18 simulator runtime and smoke-test it (glass, confetti, the
      pre-26 Maps hand-off), or raise the target to 26.0 and delete those
      paths.
- [ ] **App Review needs a demo account, and the reviewer won't be in North
      Carolina.** Apple's reviewers are in California. With location on, they
      see an empty map, no runs and "no courts nearby", which can read as an
      unfinished app (Guideline 2.1). Give them a seeded demo account (a
      friend, a squad, a couple of upcoming runs) and explain in the review
      notes that coverage is the Raleigh–Durham Triangle and that denying
      location centres the app on Durham.
- [ ] App Store Connect: screenshots at the required sizes, description,
      keywords, support URL, privacy policy URL (§2.3), the age-rating
      questionnaire (it has user interaction), and the privacy label (§2.2).

---

## 5. P2: Code cleanliness

The code is already disciplined: no TODOs, no stray debug output in release
builds, and errors are translated out of Firebase types everywhere. This
section is what's left to call it *clean*.

### 5.1 The 10 compiler warnings in the app target

All are Swift 6 actor-isolation warnings. They're harmless under Swift 5
mode, but each becomes an error in Swift 6.

| Site | Fix |
|---|---|
| `Services/ListenerSupervisor.swift:207–208` | Inside the `Task { @MainActor in … }`, write `guard let self else { return }` instead of reusing the captured weak `self`. |
| `ViewModels/FriendsViewModel.swift:226`, `ViewModels/ResultViewModel.swift:50` | A `@MainActor` store's `init` is used as a default argument. Mark the stores' `init(defaults:)` `nonisolated`, or build the default inside the body. |
| `ViewModels/HomeViewModel.swift:654` | `lastCompletedDateFormatter` → `nonisolated static let`. |
| `Views/Components/StatsScoreboard.swift:383, 428`, `Views/Tabs/HomeTab.swift:750, 795`, `Views/Tabs/RunCalendarPopup.swift:431` | `Spacing.sm`/`.md`/`.pageMargin` are read from nonisolated contexts. Mark the `Spacing` constants `nonisolated static let`. They're plain `CGFloat`s. |

- [ ] Fix all ten, then turn on `SWIFT_TREAT_WARNINGS_AS_ERRORS` for the app
      target, so they can't come back.
- [ ] Test target (27 warnings): add `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
      to both test configs (`LAUNCH_READINESS.md` §3), or mark
      `MatchmakingViewModel.Phase` and `FriendsViewModel.Relationship`
      `nonisolated`. Replace the deprecated `setOverrideTraitCollection` in
      `TabBarLabelTests.swift:116` with `traitOverrides`.
- [ ] Then `SWIFT_STRICT_CONCURRENCY = complete` (`LAUNCH_READINESS.md` §4).

### 5.2 Small rule and logic gaps

- [ ] **The `users` create rule is looser than the docs say.** It doesn't
      check `createdAt == request.time`, so a modified client can backdate
      the "Joined" date. `PRODUCT_OVERVIEW.md` says creation dates are
      "pinned server-side"; that's only true on *update*. It also doesn't
      check that `userNameLower` matches `lower(userName)`, so someone can
      appear in search under a different name. And `favoriteCourtIds` has no
      size limit. Tighten all three, with rules tests.
- [ ] **Emoji in names may be counted differently on each side.** Swift
      `String.count` counts what the user sees as characters; the rules'
      `size()` most likely counts code points. A 24-character squad name with
      a few emoji can pass the client check and get `permission-denied` from
      the server, which reads like an undeployed ruleset. Add a rules test
      with an emoji name and align the client's count to whatever it shows.
- [ ] **A run on the last allowed day can be refused.** The date picker's
      upper bound (`CreateGameViewModel.scheduleRange`) is exactly now + 30
      days, but the rule is a strict `< request.time + 30d`. On a phone whose
      clock runs fast, the last selectable minute is rejected. Pull the bound
      in by an hour.
- [ ] **Tip-off default** ([`ROADMAP.md`](../ROADMAP.md) §3): check on a
      device before touching any code.

### 5.3 Convention drift

- [ ] `CLAUDE.md` says sheets are "never [presented] with `isPresented`".
      Three are: `ProfileView.swift:141, 146` and `QueueSheet.swift:129`.
      Convert them, or reword the convention for sheets that carry no item.
- [ ] Remove the DEBUG-only `-MapLayoutDiagnostics` prints in
      `MapTab.swift:232–238, 445–451` and `tabBar(in:)` (`:1390`) now that
      the layout has settled.
- [ ] `AccentColor.colorset` has no colour in it. Set it to the brand orange,
      or delete it ([`gaps/ASSETS_AND_DATA.md`](../gaps/ASSETS_AND_DATA.md)).
- [ ] Split `MapTab.swift`, now 1,440 lines, **after** launch
      (`LAUNCH_READINESS.md` §5).

### 5.4 Repo hygiene

- [ ] Prune stale branches: local `color-scheme-plan`,
      `feature/profile-tab`, `initial-upload`, `map-tab`, `ui-tune-up`,
      `codex/map-tab-rework`, and the matching remotes, once merged.
- [ ] Fix or retire `location-decoder-script/reverseGeocode.js` (it writes
      into the app bundle) and `tools/build_courts.py` (its inputs aren't in
      the repo) ([`gaps/ASSETS_AND_DATA.md`](../gaps/ASSETS_AND_DATA.md)).

---

## 6. P2: Documentation drift found in this audit

The `context/` system only works if it's true. Before launch, these are wrong:

| Doc | Says | Actually |
|---|---|---|
| `ARCHITECTURE`, `BUILD_AND_CONFIG`, `DATA_MODEL`, `MAP_LAYER`, `UI_SHELL`, `database/DATABASE_SCHEMA` | Verified at `976d2cf` or `f30e4b2` | Their scoped files have changed since. Re-read and restamp each. |
| *(no entry)* | — | **24 source paths match no entry's `Scope`**: all of `Views/Components/*` added in the revamp, `Support/Motion.swift`, `Views/Tabs/MapBand.swift`, `MapFraming.swift`, `RunsBand.swift`, `Views/Debug/ComponentGallery.swift`, `tools/make_court_symbol.swift`. Add each to an owner's `Scope`. |
| `PRODUCT_OVERVIEW.md` | "Filter by lights, two-or-more hoops, and public access" | The filter chips were removed on 2026-10-10 (`ff9bbe2`). |
| `PRODUCT_OVERVIEW.md` | 666 tests / 44 suites, 141 rules tests | **811 / 48** and **148** |
| `PRODUCT_OVERVIEW.md` | "Password reset by emailed link" | Only while signed in (§3.1) |
| `PRODUCT_OVERVIEW.md` | "Account creation dates … pinned server-side" | Only on update (§5.2) |
| `CLAUDE.md` | 810 tests / 50 suites | 811 / 48 |
| `README.md` | "`IPHONEOS_DEPLOYMENT_TARGET` is 26.5" | 18.0 |
| `gaps/CONFIGURATION.md` | Portrait-only "and the project says so" | The project turns landscape on (§3.3) |
| `gaps/TESTING.md` | 481 / 30 Swift, 141 rules | 811 / 48, 148 |
| `gaps/GAMES.md`, `plans/BACKLOG.md` B3 | Universal Links and blocking need §0 infrastructure | Both work on Spark (§7.1, §2.4) |
| `plans/LAUNCH_READINESS.md` | "every submission blocker has since shipped" | Four are open (§2). Superseded by this doc. |
| `INDEX.md` | Lists four plans | `plans/MAP_PRESENTATION.md` exists and isn't listed |

- [ ] Run `python3 tools/check_context_drift.py` again once the rows above
      are fixed, and restamp only what you actually re-read.

---

## 7. UX touch-ups and features

### 7.1 Before launch: high value, works on Spark, small to medium size

| Item | Why | Size |
|---|---|---|
| **First-run onboarding.** Display name, then the location permission with a reason, then a home court, then (optional) notifications. | Closes §3.2 and §3.6 at the root. A new account currently lands on Home named after its email, with distances measured from Durham. This is [`BACKLOG.md`](BACKLOG.md) C3's onboarding half. | M |
| **Universal Links through Firebase Hosting** (`https://hoopsrn-4f1e9.web.app/game/{id}`, plus an `apple-app-site-association` file) | iMessage generally doesn't make custom schemes like `hoopsrn://` tappable, so today's invite link probably shows up as plain text. A web link opens the app if it's installed and a landing page with the App Store button if it isn't. Hosting is on Spark. It needs the Associated Domains capability. | M |
| **Ask before the notification prompt** | The system prompt currently fires the moment a match lands (`NotificationService.apply` → `requestIfNeeded`), with no context. One sentence first ("Get a reminder before tip-off?") raises the grant rate. | S |
| **The host can promote from the waitlist** | `gaps/GAMES.md` names a host action as one of the two fixes. A host-only rules clause that moves the first uid from `queuedPlayerIds` into `playerIds` works on Spark, without waiting for Blaze. | M |
| **Add to Calendar** on a run card (EventKit, write-only access) | It's a scheduling app. One tap puts the run in the user's calendar with the court's address. | S |
| **Let players share a private run's link, not just the host** | [`gaps/GAMES.md`](../gaps/GAMES.md) calls this a product call. Bringing a friend shouldn't need the host. | S |
| **Ask for an App Store rating** after the third completed run (`requestReview`) | Early ratings matter most. | S |
| **Inbox truncation at `.accessibility3`**, and Profile's identity block ghosting behind the glass bar | Already found and not fixed ([`gaps/ACCESSIBILITY.md`](../gaps/ACCESSIBILITY.md)). | S |

### 7.2 After launch, in rough order

1. **A run detail screen**: who's playing, the host, the waitlist
   ([`BACKLOG.md`](BACKLOG.md) C1). It's the biggest missing surface, and it
   needs a privacy decision on which profile fields a roster shows.
2. **Push notifications** (Blaze, FCM and a Function): friend requests,
   squad invites, a run filling up, matches. Everything is local-only today.
3. **Automatic run completion and waitlist promotion** (Blaze,
   [`BACKLOG.md`](BACKLOG.md) D6).
4. **Solo Queue Up**, find-or-create ([`BACKLOG.md`](BACKLOG.md) A1).
5. **Live court headcount** ([`LIVE_HEADCOUNT.md`](LIVE_HEADCOUNT.md)). Make
   the `presence` vs `checkins` decision first.
6. **Standings for Seasons.** A record exists but there's nowhere to compare
   it.
7. **Sign in with Apple.** Not required today (no third-party login), but it
   cuts sign-up friction a lot. Adding Google login later *would* make it
   mandatory.
8. **More cities** ([`SCALE_UP.md`](SCALE_UP.md)). The public-runs query has
   no geographic filter, so this has to land before a second metro.
9. **Recurring runs** and per-run chat (`PRODUCT_OVERVIEW.md`'s speculative
   list).

---

## 8. Newly filed gaps: where each one belongs

These came out of this audit and weren't recorded anywhere in `gaps/`. As
each is triaged, add it to its home or close it, and strike it here.

| Gap | Home |
|---|---|
| No in-app password reset when signed out (§3.1) | `gaps/PROFILES.md` |
| Account deletion is an App Store blocker, not just a missing feature (§2.1) | `gaps/PROFILES.md` |
| Location is only requested from the map, Home and Runs don't update when a fix arrives, and a denied permission is never mentioned (§3.2) | new `gaps/LOCATION.md`, or `MAP_LAYER.md` |
| Landscape is turned on (§3.3) | `gaps/CONFIGURATION.md` (correct the existing line) |
| Sign-out leaves notifications and device-wide stores behind (§3.4) | `gaps/SEASONS.md` (notifications) and `gaps/PROFILES.md` (stores) |
| Waitlisted private or out-of-radius runs are shown nowhere (§3.5) | `gaps/GAMES.md` |
| Default name is the email's local part; 51–64-character email names fail; setup has no retry (§3.6) | `gaps/PROFILES.md` |
| Disbanding a squad strands a scheduled match (§3.7) | `gaps/SEASONS.md` |
| Run cancellation is silent to players (§3.8) | `gaps/GAMES.md` |
| No privacy manifest, privacy policy, terms, report or filter (§2.2–2.4) | new `gaps/COMPLIANCE.md` |
| Spark's daily read limit under normal growth (§4.2) | `gaps/RATE_LIMITING.md`, or `plans/SCALE_UP.md` |
| App Review sees an empty app outside the Triangle (§4.4) | `gaps/ASSETS_AND_DATA.md` ("coverage") |
| `users` create rule: `createdAt`, `userNameLower` and `favoriteCourtIds` unchecked (§5.2) | `gaps/PROFILES.md` |
| Emoji name length may differ between client and rules (§5.2) | `gaps/TESTING.md` |
| Never run on a physical device, and no signing team set (§4.4) | `gaps/CONFIGURATION.md` |

---

## 9. Manual verification still owed

Nothing in either test suite can close these. Carried over from
[`ROADMAP.md`](../ROADMAP.md) §1, plus what this audit added. One afternoon
with **two physical iPhones and two accounts**:

- [ ] Sign-up → onboarding → Home on a fresh install, **in Raleigh or Cary,
      not Durham** (§3.2).
- [ ] Forgot password from the login screen, end to end (§3.1).
- [ ] An invite link sent from phone A through **iMessage**: is it tappable?
      Then opened on phone B cold, signed out, and with a sheet already up.
- [ ] A friend's join appearing live on the other phone's run card.
- [ ] Both people requesting each other at once
      ([`gaps/FRIENDS.md`](../gaps/FRIENDS.md)).
- [ ] Seasons: queue → match → game day → both leaders report → confirmed,
      and the disputed path ([`gaps/SEASONS.md`](../gaps/SEASONS.md)).
- [ ] Match reminders firing at T−60, T−0 and T+90, and gone after sign-out
      (§3.4).
- [ ] A VoiceOver sweep of every tab, plus haptics
      ([`gaps/ACCESSIBILITY.md`](../gaps/ACCESSIBILITY.md)).
- [ ] Account deletion end to end, then sign up again with the same email
      (§2.1).
- [ ] Rotate the phone on every tab (after §3.3, nothing should happen).

---

## 10. Suggested order

1. **Days 1–2:** the bugs in §3.1–3.6, which are each an hour or two, plus
   §5.1's warnings. Merge to `main`.
2. **Days 3–5:** account deletion (§2.1), report/block/filter (§2.4),
   onboarding (§7.1), which closes §3.2 and §3.6 properly.
3. **Day 5:** the privacy manifest, the policy and terms on Firebase
   Hosting, and the Profile links (§2.2–2.3). Make the Blaze decision and set
   a budget alert (§4.2). Add App Check (monitoring) and Crashlytics (§4.1).
4. **Day 6:** set the signing team, run on two devices, and do the §9 pass.
   Fix whatever it finds.
5. **Day 7:** clean up the Firebase console (§4.3), fix the docs (§6), seed
   the demo account, fill in App Store Connect, upload to TestFlight.
6. **After a week of TestFlight with real people:** submit. Then start §7.2.

---

## See also

- [`../ROADMAP.md`](../ROADMAP.md): the standing order of work. This audit
  slots in ahead of it until launch.
- [`../GAPS.md`](../GAPS.md): where the gaps in §8 should end up.
- [`LAUNCH_READINESS.md`](LAUNCH_READINESS.md): superseded by this document.
  Delete it once the items folded in here are tracked here.
- [`BACKLOG.md`](BACKLOG.md), [`SCALE_UP.md`](SCALE_UP.md),
  [`LIVE_HEADCOUNT.md`](LIVE_HEADCOUNT.md): the post-launch designs §7.2
  points to.
