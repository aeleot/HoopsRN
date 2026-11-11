# Plan — Launch Gameplan

**Status:** active. Week of **Mon 2026-10-19 → Sun 2026-10-25**.
**Source:** every item comes from [`PRE_LAUNCH_AUDIT.md`](PRE_LAUNCH_AUDIT.md). In
this file, **A§3.1** means *audit section 3.1*.
**Milestones:**

| | Date | Meaning |
|---|---|---|
| 🟢 **COMPLETE** | **Sun 2026-10-25** | Every audit P0 and P1 item is fixed and tested on two physical phones, and the release-candidate build is on TestFlight. |
| 🚀 **Submit** | Mon 2026-11-02 | After a one-week TestFlight beta with real players. |
| 🏁 **Launch** | **Thu 2026-11-05** | Public release on the App Store. If review rejects the build once, the fallback is **Tue 2026-11-10**. |

> Like everything in `context/plans/`, this file has no `Scope`/`Verified`
> stamp. Tick boxes as work lands, and record each day in the **Daily log**
> (§11). When the week is over, everything here either shipped (fold it into
> the dictionary entries) or moved to the 1.1 list (§10).

---

## 1. How the week works

### Three tracks, running in parallel

| Mark | Track | Who |
|---|---|---|
| 🛠 | **Code.** App, rules, and tests. | Claude sessions write it, and you review and merge each change. |
| 👤 | **Things only you can do.** Apple and Firebase accounts, App Store Connect, legal text, physical phones, recruiting testers. | You |
| 📄 | **Docs.** The audit's §6 drift fixes and §8 gap filing. | A separate Claude session, Thursday–Sunday. It touches no code, so it can't conflict with the code track. |

### Definition of Done (every 🛠 item, no exceptions)

1. The code change is merged to `main` through a pull request.
2. **Unit tests** cover each new rule or decision. In this codebase that means
   lifting the logic into a `nonisolated static` pure function and testing
   that function.
3. Any rules change gets a **rules test**, and is **mutation-checked**: weaken
   the new clause, confirm exactly the expected test fails, then restore it.
4. Both suites pass, and there are **zero compiler warnings** (warnings become
   errors from Monday on).
5. You've tried it on a **physical iPhone**, not only the simulator.
6. The audit checkbox is ticked, and the owning doc or `gaps/` file is updated
   (or added to the 📄 track's queue).

### Branching

- **Monday morning:** merge `queue-system` into `main` and push. From then on,
  `main` is the release branch.
- One short-lived branch per audit item, named like `fix/a3.1-forgot-password`.
- There's no CI server, so **the gate runs locally**: both suites must be green
  on your machine before you merge.
- **After the feature freeze (Fri 18:00):** a change can only merge if it has a
  bug ID (§8), a test that fails without it, and a re-run of the affected
  regression cases. No refactors. The `MapTab.swift` split waits until after
  launch.

### Commands

```bash
# Swift unit tests. Use a spare simulator and a scratch DerivedData, never the
# booted one or the default. See memory: xcodebuild-test-hygiene.
nice -n 10 xcodebuild test -project hoopr.xcodeproj -scheme hoopr \
  -destination 'platform=iOS Simulator,id=<spare-device-id>' \
  -only-testing:hooprTests -derivedDataPath <scratch>/DD \
  -clonedSourcePackagesDirPath <scratch>/SourcePackages \
  -resultBundlePath <scratch>/tests.xcresult
xcrun xcresulttool get test-results summary --path <scratch>/tests.xcresult

# Rules tests. Run these only after xcodebuild has finished: under build load
# the emulator health check times out and every test fails, which looks like a
# rules regression but isn't.
npm run test:rules

# Docs drift
python3 tools/check_context_drift.py
```

Today's numbers, which each day may only go up: **811 Swift tests in 48
suites, 148 rules tests.** Write each day's totals in the daily log.

---

## 2. Decisions to make before Monday's code starts

Each decision has a recommendation. Record your answer in the right-hand
column. Several days' tasks branch on these.

| # | Decision | Recommendation | Why | Answer |
|---|---|---|---|---|
| D1 | Move to the Blaze plan, or stay on Spark? | **Blaze, with a $25/month budget alert** | Removes the hard daily read limit that would take the app offline for everyone (A§4.2). Costs pennies at launch scale. Unlocks Cloud Functions for 1.1. | |
| D2 | Keep iOS 18 as the minimum, or raise it to iOS 26? | **Raise to 26.0 for 1.0** | No iOS 18 code path has ever run (A§4.4). Raising the minimum means every path that ships has been seen. Lower it again in 1.1, after an iOS 18 test pass. | |
| D3 | Cancel runs softly, so players see "Called off by the host" (A§3.8)? | **Yes** | It's a small change, and without it someone drives to a court for a run that no longer exists. | |
| D4 | Build Universal Links for 1.0 (A§7.1)? | **Stretch goal.** Build it only if Saturday's test INV-01 shows the `hoopsrn://` link isn't tappable in iMessage. | It's a medium-sized job, and the custom link might work well enough for 1.0. | |
| D5 | Require email verification at sign-up? | **No for 1.0** | It adds friction to sign-up. App Check covers most of what it protects against. | |
| D6 | Where does "onboarding finished" get stored? | **On the device, in `UserDefaults` keyed by uid** | Needs no rules change or new profile field. Reinstalling shows onboarding again, which is harmless. | |
| D7 | Treat the home court and favourite courts as "location" on the App Store privacy label? | **Yes, as "Coarse Location, linked to the user, not used for tracking"** | The conservative answer. Reviewers don't penalize over-disclosing. | |
| D8 | Where does the offensive-word list come from? | A short list in the repo (`hoopr/Resources/blocked_terms.txt`), checked as whole words, ignoring case | Simple, easy to review, and easy to grow later. | |

---

## 3. Calendar at a glance

| Day | Date | Theme | Gate at the end of the day |
|---|---|---|---|
| 0 | **Sun 10/18** (tonight, ~1h) | Unblock the critical path | — |
| 1 | **Mon 10/19** | On a real phone. Fix every bug that takes about an hour. Zero warnings. | **G1** |
| 2 | **Tue 10/20** | Runs and squads behave correctly. Rules deploy #1. Legal pages live. | **G2** |
| 3 | **Wed 10/21** | Account deletion (P0) | **G3** |
| 4 | **Thu 10/22** | Report, block and filter (P0). Privacy manifest (P0). Rules deploy #2. | **G4: every P0 coded** |
| 5 | **Fri 10/23** | Onboarding, location, App Check and Crashlytics. **Feature freeze 18:00.** Release candidate 1 to TestFlight. | **G5: freeze** |
| 6 | **Sat 10/24** | **Test day:** the full test plan on two phones. Fix, then release candidate 2. | **G6** |
| 7 | **Sun 10/25** | Docs, Firebase console, App Store Connect, final regression | 🟢 **G7: COMPLETE** |
| — | Mon 10/26 – Sun 11/1 | External TestFlight beta with 5–15 local players | **G8** |
| — | Mon 11/2 | Go/no-go review, then submit for App Review | — |
| — | **Thu 11/5** | 🏁 Public launch | — |

### Every audit item, mapped to a day

So nothing gets lost. The test IDs refer to §7.

| Audit | Item | Day | Tested by |
|---|---|---|---|
| A§2.1 | In-app account deletion | Wed | DEL-01–05, rules: `account-deletion.test.mjs` |
| A§2.2 | Privacy manifest | Thu | REL-04 |
| A§2.3 | Privacy policy, terms and support links | Mon (write) · Tue (host) · Thu (in-app links) | UI-07, REL-05 |
| A§2.4 | Report, block and filter | Thu | FRD-05–08, rules: `reports.test.mjs`, `blocks.test.mjs` |
| A§3.1 | Password reset when signed out | Mon | AUTH-04–06 |
| A§3.2 | Location permission and refresh | Fri (Mon if time allows) | LOC-01–05 |
| A§3.3 | Lock to portrait | Mon | UI-01 |
| A§3.4 | Sign-out cleanup | Mon | AUTH-09, NOT-03 |
| A§3.5 | Waitlisted runs disappearing | Tue | RUN-04, RUN-05 |
| A§3.6 | Default name, long emails, profile setup retry | Mon (stopgap) · Fri (onboarding) | AUTH-01, AUTH-07, AUTH-08, LOC-06, LOC-07 |
| A§3.7 | Disbanding mid-match | Tue | SEA-07 |
| A§3.8 | Soft cancel (if D3 is yes) | Tue | RUN-06 |
| A§4.1 | App Check and Crashlytics | Fri | REL-02, REL-03 |
| A§4.2 | Blaze decision and budget alert · cap the completed-runs listener | Mon (👤) · Fri (🛠, if time allows) | REL-07, BE-04 |
| A§4.3 | Firebase console checklist | Mon, Tue, Sun (👤) | BE-01–03 |
| A§4.4 | Signing team, merge, encryption flag, build number, iOS 18, demo account, App Store Connect | Day 0, Mon, Sun | REL-01, REL-05 |
| A§5.1 | Compiler warnings | Mon | Gate: zero warnings |
| A§5.2 | `users` rules, emoji names, last-day scheduling | Tue | RUN-08, rules tests |
| A§5.2 | Tip-off default | Sat (check on device) | RUN-09 |
| A§5.3 | Sheet convention, debug prints, accent colour | Mon | Code review |
| A§5.4 | Repo hygiene | Sun (branches) · 1.1 (scripts) | — |
| A§6 | Documentation drift | Thu–Sun (📄) | Drift check is clean |
| A§7.1 | Onboarding · notification pre-prompt · accessibility fixes | Fri | LOC-01, NOT-01, UI-02 |
| A§7.1 | Universal Links | Fri stretch (D4) | INV-01 |
| A§7.1 | Host promotes from waitlist · Add to Calendar · players share link · rating prompt | **1.1** (§10) | — |
| A§8 | File the new gaps | Sun (📄) | — |
| A§9 | Manual two-phone verification | **Sat** | All of §7 |

---

## 4. Day 0 — tonight, Sun 10/18 (about an hour, all 👤)

These are on the critical path, because Apple and Firebase can take days to
respond. Find out tonight, not on Saturday.

- [ ] 👤 **Apple Developer Program.** Confirm the membership is active, and
      under which entity. If it's meant to be **Big-Boss-LLC**, enrolling as an
      organization needs a D-U-N-S number, which can take days. **If this isn't
      already active, it's the biggest risk to the schedule** (R1 in §9).
- [ ] 👤 **App Store Connect.** Create the app record for bundle ID
      `Big-Boss-LLC.hoopr`, which also **reserves the name "hoopsRN"**. Pick a
      fallback name now in case it's taken.
- [ ] 👤 **Tester 2.** Line up a second person with an iPhone for **all of
      Saturday**. Add them in App Store Connect → Users and Access, so they're
      an *internal* TestFlight tester. Internal testers don't wait for Beta App
      Review.
- [ ] 👤 **Beta players.** Start recruiting 5–15 pickup players in the
      Triangle for the 10/26 beta.
- [ ] 👤 Push the 7 local commits. Commit `PRE_LAUNCH_AUDIT.md`, this file,
      and the `INDEX.md` row.
- [ ] 👤 Fill in the Answer column of §2.

---

## 5. The week, day by day

### Day 1 — Mon 10/19: running on a real phone, quick fixes, zero warnings

**Goal:** close every bug that takes about an hour, and finish the day on
`main`, running on a physical iPhone, with no compiler warnings.

**Morning, first:**
- [ ] 👤 Merge `queue-system` → `main` (pull request), and push.
- [ ] 👤 Set `DEVELOPMENT_TEAM`. Run a Debug build on **your iPhone**, tap
      through every tab, and write down anything odd as a bug (§8).
- [ ] 👤 Make the D1 call. If it's Blaze: upgrade the project and set a budget
      alert at 50%, 90% and 100%.
- [ ] 👤 In the Firebase console: turn on **email enumeration protection**. Run
      the query for anyone on two squads (A§4.3) and fix any it finds.

**Code:**
- [ ] 🛠 **A§3.1** "Forgot password?" on the login screen. Use the same
      wording whether or not the email has an account. Trim the email with
      `.whitespacesAndNewlines`. *Tests:* the message wording for each
      `AuthError`, and the trimming.
- [ ] 🛠 **A§3.3** Portrait only, in both build configurations.
- [ ] 🛠 **A§3.4** On sign-out: remove pending and delivered notifications,
      and clear the three on-device stores (or key them by uid). *Test:* a
      pure function that lists what sign-out must clear, so nothing gets
      missed later.
- [ ] 🛠 **A§3.6 stopgap.** Default name becomes `Hooper` plus a short random
      suffix, truncated to the 50-character limit. Run profile setup again
      when a snapshot says the profile is missing and setup isn't already
      running. *Tests:* the default never contains anything from the email;
      a 64-character email name is handled; the "run setup again?" decision
      as a pure function.
- [ ] 🛠 **A§5.1** Fix all 10 app warnings and all 27 test warnings. Set
      `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on both test configurations,
      and turn on `SWIFT_TREAT_WARNINGS_AS_ERRORS`.
- [ ] 🛠 **A§5.3** Convert the three `sheet(isPresented:)` calls to
      `sheet(item:)`. Remove the `-MapLayoutDiagnostics` prints. Set the
      accent colour.
- [ ] 🛠 **A§4.4** Add `ITSAppUsesNonExemptEncryption = NO`. If D2 is "raise
      to 26": set `IPHONEOS_DEPLOYMENT_TARGET = 26.0`, delete the code paths
      that only ran below iOS 26, and confirm the build is still clean.

**👤 Legal, in parallel:** draft the privacy policy, terms of use (including
zero tolerance for objectionable content, which Guideline 1.2 expects), and a
support page. A generator is fine as a starting point. Be accurate about
Firebase, what data is stored, and how deletion works.

**G1 — end of Monday:**
- [ ] `main` contains everything above, and both suites are green.
- [ ] The build has zero warnings with warnings-as-errors turned on.
- [ ] The app runs on a physical iPhone. Forgot-password works when signed
      out, rotating the phone does nothing, and sign-out → sign-in leaves no
      trace of the previous user.

### Day 2 — Tue 10/20: runs and squads behave correctly, rules deploy #1, legal pages live

**Goal:** fix the data bugs in runs and squads, and get all of Tuesday's rules
changes into **one** tested deploy.

**First thing in the morning:**
- [ ] 🛠👤 Add the `(queuedPlayerIds CONTAINS, scheduledTime ASC)` index to
      `firestore.indexes.json` and **deploy only the indexes now**, so it can
      build while you work. Check it reads "Enabled" in the console before
      testing the client.

**Code:**
- [ ] 🛠 **A§3.5** A listener for runs you're waitlisted on, merged into the
      Runs list with a "Waitlisted" badge. *Tests:* how the merge orders and
      de-duplicates runs (a pure function); a rules test that the waitlist
      query is allowed for a private run you're waitlisted on and refused for
      someone who isn't.
- [ ] 🛠 **A§3.7** Disbanding first cancels any scheduled match, then
      withdraws the open ticket, then deletes the squad. If either step fails,
      stop and say why. *Tests:* the cleanup plan as a pure function over the
      squad's matches and ticket; an emulator test that runs the sequence as
      the leader.
- [ ] 🛠 **A§3.8** (if D3 is yes) Add a host-only rules clause for
      `status: cancelled`, a `.cancelled` status in the model, keep cancelled
      runs visible until the run's display window ends, and show a "Called off
      by the host" card. *Tests:* rules (host allowed, others refused, the
      roster can't change once cancelled), visibility, and the card's wording.
- [ ] 🛠 **A§5.2** Tighten the `users` create rule:
      - `createdAt == request.time`.
      - `userNameLower` must equal the lower-cased name (the app's search key
        is trim plus lowercase). Test this with accented and non-Latin names
        before deploying. If the rules' lowercasing disagrees with Swift's for
        any of them, keep only the size checks. Also cover the old
        search-key backfill path, which writes `userNameLower` on its own.
      - A limit on the length of `favoriteCourtIds`.
      Add a rules test with an emoji name and match the app's length check to
      whatever it shows. Pull the date picker's last allowed time in by one
      hour.
- [ ] 🛠👤 **Rules deploy #1**, following the protocol in §6.

**👤 Hosting:**
- [ ] Run `firebase init hosting` and publish `/privacy`, `/terms` and
      `/support` to `hoopsrn-4f1e9.web.app`. Commit the `public/` folder and
      the `firebase.json` change.
- [ ] Customize the password-reset email: sender name and template (A§4.3).

**G2 — end of Tuesday:**
- [ ] Both suites green. Rules tests went up by at least 12.
- [ ] Rules deploy #1 is live, and the console's rules version matches the
      commit.
- [ ] On your phone, using account C on the simulator as well: a waitlisted
      private run shows up with its badge, and a cancelled run shows "Called
      off".
- [ ] The three legal URLs load on a phone.

### Day 3 — Wed 10/21: account deletion (P0, A§2.1)

**Goal:** a user can delete their account completely, starting from Profile.
If deletion fails partway, retrying finishes the job.

- [ ] 🛠 **Deletion plan:** a pure function that takes what the account
      currently has (runs hosted, joined and waitlisted; squads led and joined;
      scheduled matches; the open ticket; invites in both directions;
      friendships) and returns the ordered steps. It runs in this order:
      1. re-authenticate
      2. cancel scheduled matches
      3. withdraw the ticket
      4. disband squads they lead, leave squads they're on
      5. delete invites
      6. cancel hosted runs, leave joined and waitlisted runs
      7. delete friendships
      8. delete `users/{uid}`
      9. clear the device (as in A§3.4)
      10. delete the Auth account

      *Tests:* each kind of thing the account can have produces the right
      steps; the order holds; running the plan on an empty account is a
      no-op; re-running it after a partial failure skips only what's already
      gone.
- [ ] 🛠 **Who runs it:** a new `AccountDeletionViewModel` that calls each
      service's existing methods. It spans every collection, so per
      `ARCHITECTURE.md` it belongs in a view model, not a service. It holds no
      Firebase types; `AuthService` gains `reauthenticate(password:)` and
      `deleteAccount()`.
- [ ] 🛠 **Rules:** `users` allows `delete: if isOwner()`, with a test.
      **New `firestore-tests/account-deletion.test.mjs`:** set up an account
      with something in every collection, run the whole sequence *as that
      user* against the rules, and assert every step is allowed and nothing
      references the user afterwards. This is the strongest single check
      that deletion works.
- [ ] 🛠 **Screen:** a red "Delete account" row below Sign Out. It explains
      what happens (match history stays, under the squad's name), asks for
      the password, asks you to type `DELETE`, shows progress, and offers
      **Retry** if a step fails.
- [ ] 🛠👤 Deploy the `users` delete rule. It's small and safe to ship on its
      own, or it can wait for Thursday's deploy.

**👤 In parallel:** draft the App Store description, subtitle and keywords.
Answer the privacy-label questions (using D7) and the age-rating
questionnaire, in a scratch doc.

**G3 — end of Wednesday:**
- [ ] Both suites green, including the new deletion test.
- [ ] On your phone, a throwaway account (E) holding a hosted run (that B
      joined), a friendship, a squad it leads with a scheduled match, and a
      pending request is deleted completely. You check the console by hand
      afterwards.
- [ ] Signing up again with the same email works.

### Day 4 — Thu 10/22: report, block, filter and the privacy manifest (P0, A§2.2 and A§2.4)

**Goal:** every App Store blocker is coded by the end of the day.

- [ ] 🛠 **Report:** a `reports/{autoId}` collection. The rule is create-only,
      `reporterId == request.auth.uid`, with a field allowlist (`targetType`,
      `targetId`, `reason`, `details`, `createdAt == request.time`) and no
      reads at all. A "Report" action on `PlayerProfileSheet` and on an
      opponent's squad, with a reason picker and a confirmation.
      *Tests:* rules (create allowed, read refused, can't report on someone
      else's behalf, unknown fields refused), mutation-checked.
- [ ] 🛠 **Block:** `blocks/{blockerUid}_{blockedUid}`. Only the blocker can
      create, read or delete it. **The `friendships` and `squadInvites`
      create rules gain**
      `!exists(/databases/$(database)/documents/blocks/$(target)_$(request.auth.uid))`.
      On the client: hide blocked users from search and the inbox, put
      "Block" on the profile sheet and on incoming requests (blocking also
      deletes any pending friendship), and add a "Blocked players" list in
      Profile where you can unblock. *Tests:* rules (a blocked user's
      request and squad invite are refused, both directions behave
      correctly), mutation-checked; the search and inbox filtering as pure
      functions.
- [ ] 🛠 **Filter:** load the word list (D8) and check it in both
      `UserProfile.validate(userName:)` and `Squad.validate(name:)`, with a
      new error case and its message. *Tests:* blocked words are refused;
      ordinary words that merely contain a blocked word aren't (the
      "Scunthorpe" problem); matching ignores case.
- [ ] 🛠 **A§2.2** Add `hoopr/PrivacyInfo.xcprivacy`: UserDefaults with reason
      `CA92.1`, the collected data types, and tracking off. Add it to the app
      target.
- [ ] 🛠 **A§2.3** Profile gets rows for Privacy Policy, Terms, Contact
      Support (a `mailto:` link or the support page), Blocked players, and
      Delete account. The sign-up form gets a line linking to the terms.
- [ ] 🛠👤 **Rules deploy #2** (reports, blocks, and the two create-rule
      changes), following §6.

**📄 Docs track starts (separate session):** the audit's §6 table, row by
row. Restamp each stale dictionary entry *after* reading it again, and add the
24 unowned source paths to an entry's `Scope`.

**G4 — every P0 is coded:**
- [ ] Every item in A§2.1–2.4 is merged.
- [ ] Rules deploy #2 is live, and the console version matches the commit.
- [ ] On your phone, using account C: blocking C stops C's friend request (the
      server refuses it), a report from A shows up in the console, an
      offensive squad name is rejected, and the Profile links open.

### Day 5 — Fri 10/23: onboarding, location and monitoring. Feature freeze at 18:00

**Goal:** a brand-new user's first five minutes are right, the app reports its
own crashes, and **release candidate 1** is on TestFlight overnight.

- [ ] 🛠 **Onboarding (A§7.1, closes A§3.2 and A§3.6 properly):** four
      steps.
      1. Display name, through the existing validation and the word filter.
      2. Location: one sentence explaining why, *then* the system prompt.
      3. Home court (can skip).
      4. Done.

      Shown once per uid (D6). Also shown to existing accounts whose name is
      still their email's prefix (A§3.6). *Tests:* which step to show next, as
      a pure function over the profile, permission and finished-flag.
- [ ] 🛠 **A§3.2:** `LocalRunsViewModel` and `HomeViewModel` subscribe to
      `$coordinate`. A banner explains when location is denied and links to
      Settings. Use `requestLocation()` (one fix) on launch and when the app
      returns to the foreground, instead of updating continuously.
      *Tests:* what each permission state shows; that a new location
      triggers a rebuild.
- [ ] 🛠 **Notification pre-prompt:** one sentence ("Get a reminder before
      tip-off?") before the system dialog.
- [ ] 🛠 **Accessibility fixes** (A§7.1 row 8): the inbox's sent-request row
      at `.accessibility3`, and Profile's identity block showing through the
      glass bar.
- [ ] 🛠👤 **A§4.1 App Check:** add the `FirebaseAppCheck` package. In
      `hooprApp.init()`, set the App Attest provider *before*
      `FirebaseApp.configure()`, and the debug provider on the simulator. Add
      the App Attest capability, set to the production environment for
      release builds. Register the app in the App Check console. **Leave it
      in monitoring mode; don't enforce.**
- [ ] 🛠👤 **A§4.1 Crashlytics:** add the `FirebaseCrashlytics` package and
      the dSYM upload build phase. **This project has
      `ENABLE_USER_SCRIPT_SANDBOXING = YES`**, so the upload script must
      declare the input files listed in Firebase's setup docs, or it fails
      with a sandbox error. Record non-fatal errors on the `FirestoreFailure`
      paths. Add a hidden test-crash trigger, compiled into DEBUG builds and
      the TestFlight build only, and remove it before submission.
- [ ] 🛠 (if time allows, and only if D1 is Spark) **A§4.2** Cap the
      completed-runs listener.
- [ ] 🛠 (stretch, D4) **Universal Links:** an `apple-app-site-association`
      file on Hosting, the `applinks:hoopsrn-4f1e9.web.app` Associated Domain,
      the invite parser accepting both `https://…/game/{id}` and
      `hoopsrn://`, and share text that uses the https link.

**18:00: feature freeze.** After this, only fixes for logged bugs (§1).

**Evening, release candidate 1:**
- [ ] 👤 Bump `CURRENT_PROJECT_VERSION`. Archive the **Release**
      configuration. In Xcode's Organizer, run **Generate Privacy Report** on
      the archive (REL-04). Upload, and add the build to the internal tester
      group, so it's processed by morning.
- [ ] 👤 Write the Saturday account plan into §7.0 (which phone, which
      account, which squad).

**G5 — feature freeze:**
- [ ] Every 🛠 item from Day 1 to Day 5 is merged, except the stretch items.
- [ ] Both suites green, zero warnings. Test counts are written in the daily
      log.
- [ ] Release candidate 1 is uploaded to TestFlight.

### Day 6 — Sat 10/24: test day (two phones, release build)

**Goal:** run all of §7 on **the TestFlight build**, which is the Release
configuration and has the DEBUG-only code compiled out. Fix whatever it finds.

| Time | Block |
|---|---|
| 08:30 | **Schedule a Seasons match about 70 minutes out** (SEA-01), so its T−60, T−0 and T+90 reminders fire during the day (NOT-02, NOT-03). |
| 08:45–12:00 | §7 scenario suite: AUTH, LOC, RUN, INV, FRD, SQD, SEA, DEL. Both phones plus the simulator (account C). |
| 12:00–13:00 | §7 interface, accessibility and release-build checks (UI, REL, NET), split between the two testers. |
| 13:00–14:30 | **Free-form bug hunt**, 90 minutes with set themes (§7.9). |
| 14:30 | **Triage** (§8). Severity 1 and 2 get fixed today. Severity 3 is logged. |
| 14:30–19:00 | 🛠 Fixes, each with a test. Every fix re-runs its area's test cases. |
| 19:00 | 👤 **Release candidate 2** to TestFlight (only if anything was fixed). |
| 20:00 | Quick check (§7.10) on RC2, both phones. |

**G6 — end of Saturday:**
- [ ] Every §7 case is run and its result recorded.
- [ ] No open severity 1 or 2 bugs, or each one has a fix in RC2 that has
      passed the quick check.
- [ ] Decision D4 is settled using INV-01's result.

### Day 7 — Sun 10/25: COMPLETE 🟢

**Goal:** everything the store submission needs is ready. A last pass over
the final build.

- [ ] 📄 Finish the A§6 doc fixes, and file the A§8 gaps in their `gaps/`
      homes (or close them, if this week fixed them). Delete
      `LAUNCH_READINESS.md` and its row in `INDEX.md`. Update `ROADMAP.md`
      (the rules deploy dates, and remove what shipped). Fix
      `PRODUCT_OVERVIEW.md`'s test counts and feature claims. Update the
      counts in `CLAUDE.md`.
- [ ] 👤 **Firebase console (A§4.3):** delete test data (the
      `chaseallen122` friendship, test runs, squads and accounts), keeping
      only the demo account's data. Confirm the rules version and that every
      index reads "Enabled" (BE-01, BE-02).
- [ ] 👤 **Demo account for App Review (A§4.4):** create account **D** with
      a friend, a squad, two upcoming public runs in Durham, and one upcoming
      run it hosts. Sign in on a clean phone and check it.
- [ ] 👤 **App Store Connect:**
      - screenshots (6.9-inch required; use the demo account, with real
        Durham data)
      - description, subtitle and keywords
      - support URL and privacy policy URL
      - age rating and privacy label
      - **"Manually release this version"**
      - **review notes:** the demo login; "Courts cover the Raleigh–Durham
        area. With location off, the app centres on Durham"; where Report,
        Block and Delete Account are
- [ ] 🛠 Remove the test-crash trigger if it's reachable in Release. Build
      **release candidate final**.
- [ ] 👤 **Final regression:** the quick check (§7.10), plus every test case
      touched by a fix since release candidate 1, on the final build.
- [ ] 👤 Tag `v1.0.0-rc` on `main` and push. Prune the stale branches
      (A§5.4).
- [ ] 👤 Submit the final build for **external** TestFlight (Beta App Review
      usually takes about a day). Invite the beta players.

**G7 — COMPLETE: every box below must be ticked.**
- [ ] Every A§2 and A§3 item is closed and passed on two physical phones.
- [ ] App Check is reporting in monitoring mode. A Crashlytics test crash has
      shown up with readable (symbolicated) stack frames.
- [ ] Both suites are green, at or above Friday's counts. Zero warnings.
- [ ] Rules and indexes are deployed from `main`, and the console version
      matches the commit.
- [ ] The final release candidate is on TestFlight. No open severity 1 or 2
      bugs.
- [ ] The drift check shows no stale entries and no source paths without an
      owner. The A§8 gaps are filed.
- [ ] App Store Connect is complete except for pressing Submit.
- [ ] `v1.0.0-rc` is tagged and pushed.

---

## 6. Rules deploy protocol (deploy #1 Tuesday, deploy #2 Thursday, any fix after that)

Rules are the one change that hits **every installed build at once**. Follow
these steps in order, every time:

1. [ ] Run `npm run test:rules` on a quiet machine (no build running). It must
       be green.
2. [ ] **Mutation-check** every new or changed clause: weaken it, and confirm
       the specific intended test fails *and nothing else*. A test that's
       never been seen to fail proves nothing (`gaps/TESTING.md`).
3. [ ] `firebase deploy --only firestore:rules,firestore:indexes --dry-run`
       compiles cleanly.
4. [ ] **Indexes go first.** Deploy them, and wait until every one reads
       "Enabled" in the console.
5. [ ] Deploy the rules, from a clean `main` checkout.
6. [ ] Write the date and commit in `ROADMAP.md`'s deploy note.
7. [ ] Within 15 minutes, on a phone: try the flows the change touched, plus
       sign-in, the Runs tab and the inbox. **If anything shows
       "permission-denied", roll back right away** in the console (Rules →
       history → the previous version), then fix it in the repo.
8. [ ] **Keep it compatible.** After Friday, rules have to accept writes from
       the release candidate already on testers' phones. No rules change
       after the freeze unless a logged bug requires it.

---

## 7. Test plan

### 7.0 Devices and accounts

| Slot | Device | Account | Role |
|---|---|---|---|
| **A** | Your iPhone, running the TestFlight build | A (you) | Hosts runs. Leads squad 1. |
| **B** | Tester 2's iPhone, running the TestFlight build | B | Joins runs. Leads squad 2 (its own, one-person squad). |
| **C** | Simulator, iPhone 17e (small screen), iOS 26.5 | C | Joins squad 1, then waitlist and block cases |
| **E** | Either phone, signed in partway through the day | E (throwaway) | Account deletion |
| **D** | — | D (demo) | Created Sunday and kept for App Review |
| Sizes | Simulators: iPhone 17e and 17 Pro Max | any | Smallest and largest screens |

There's no minimum squad size for queueing, so A's squad (with C) and B's
squad can be matched against each other. They share no players, so the
matchmaking rules allow the pairing.

**Setting coverage:** don't test every combination. Instead, make sure every
setting value is seen at least once across the day:

- light and dark mode
- text size at default and at `.accessibility3`
- VoiceOver on
- Reduce Motion on
- location: not asked yet, allowed, denied, approximate
- notifications allowed and denied
- network: Wi-Fi, cellular, offline, and **Very Bad Network**
  (Settings → Developer → Network Link Conditioner, on the phone running from
  Xcode)

### 7.1 Sign-in and accounts (AUTH)

| ID | Test | Expected |
|---|---|---|
| AUTH-01 | Fresh install, sign up with a new email | Onboarding opens. The profile is created. **The name has nothing from the email in it.** |
| AUTH-02 | Sign out, then sign back in | Lands on Home. No flash of the login screen on relaunch. |
| AUTH-03 | Wrong password | "Incorrect email or password". Nothing else changes. |
| AUTH-04 | Signed out → Forgot password → a real email | The neutral message appears, the email arrives, the reset works. Phone B, signed in to the same account, drops back to the login screen. |
| AUTH-05 | Forgot password with an email that has no account | **The same** neutral message. |
| AUTH-06 | Paste an email with a trailing space or newline | It's accepted. |
| AUTH-07 | Sign up with an email whose name part is 55 characters (make one with a + alias) | The profile is created normally. |
| AUTH-08 | Airplane mode at the moment of sign-up, then turn it off | The profile is created **without relaunching** (A§3.6 retry). |
| AUTH-09 | A schedules a match → sign out → sign in as C on the same phone | C sees none of A's recent courts and gets none of A's reminders. |
| AUTH-10 | Delete the app and reinstall, signed in | Firebase keeps the sign-in on the device, so it signs straight in. Onboarding is shown again (D6) and can be finished quickly. |

### 7.2 Onboarding and location (LOC)

| ID | Test | Expected |
|---|---|---|
| LOC-01 | Fresh install, **physically in Raleigh or Cary** (or the simulator set to Cary): onboarding → allow location | The reason shows *before* the system prompt. Home, Runs and Map all measure from the phone. Nearby runs appear. |
| LOC-02 | Deny location | A banner says distances are from Durham, and its link opens Settings. |
| LOC-03 | Turn location on in Settings, then come back to the app | Home, Runs and Map all update without relaunching. |
| LOC-04 | Precise location off | Works, with approximate distances. |
| LOC-05 | Move more than 100 m (or simulate it) | Distances update on all three tabs. |
| LOC-06 | Name and home court chosen in onboarding | Both show on Profile. Searching for the name finds the user. |
| LOC-07 | An existing account still named after its email | Asked once for a new name. Not asked again after setting one. |

### 7.3 Runs (RUN)

| ID | Test | Expected |
|---|---|---|
| RUN-01 | A creates a public run in range of B | It appears on B's Runs tab live, without a refresh. |
| RUN-02 | B joins | A's card updates live, and "1 friend here" shows if they're friends. |
| RUN-03 | A run with room for 2: A hosts, B joins (now full), C joins | C goes on the waitlist, and C's card shows "Waitlisted". |
| RUN-04 | C is waitlisted on a public run **outside** C's radius | It still shows on C's Runs tab with the badge (A§3.5). |
| RUN-05 | A private run that's full; C opens its invite link and joins the waitlist | It shows on C's Runs tab, and C can leave the waitlist from there. |
| RUN-06 | A cancels a run B has joined | B sees "Called off by the host" until the run's display window ends (A§3.8). |
| RUN-07 | After tip-off, A marks the run complete | It leaves the lists. A's count and streak update. |
| RUN-08 | Create a run on the last allowed day, at the latest allowed time | It's saved (A§5.2). |
| RUN-09 | Open "Start a run" at about 23:50 and at about 00:50 | The default tip-off is an hour from now, rounded up to the quarter hour, in local time (ROADMAP §3). |
| RUN-10 | B and C tap Join on the last seat at the same moment | One gets the seat, the other gets the waitlist. Neither sees an error. |

### 7.4 Invites (INV)

| ID | Test | Expected |
|---|---|---|
| INV-01 | A shares a private run's link to B **through iMessage** | **Record whether the link is tappable.** This decides D4. |
| INV-02 | B opens the link while the app is running, on another tab, with a sheet open | The invite sheet appears on top. |
| INV-03 | B opens the link with the app fully closed | The app launches straight into the invite sheet. |
| INV-04 | B opens the link while signed out | After signing in, the invite sheet appears. |
| INV-05 | A link to a run that was cancelled | "Called off" wording. |
| INV-06 | A link to a run that's over | "This run is over". |

### 7.5 Friends and safety (FRD)

| ID | Test | Expected |
|---|---|---|
| FRD-01 | Search by the start of a name, and by an exact user ID | Both find the user. |
| FRD-02 | A sends B a request, B accepts | B's inbox badge appears live, and both friends lists update. |
| FRD-03 | A and B send each other requests at the same moment | They become friends, and neither sees an error (`gaps/FRIENDS.md`). |
| FRD-04 | Decline, cancel and remove-friend, each once | Each takes effect on both phones. |
| FRD-05 | A blocks C | C's request to A is **refused by the server** with a clear message. C doesn't appear in A's search. Unblocking puts everything back. |
| FRD-06 | A blocks C, then C sends A a squad invite | Refused. |
| FRD-07 | A reports C (reason: offensive name) | A confirmation shows. The document appears in `reports` in the console, and C can't read it. |
| FRD-08 | Set a display name or squad name containing a blocked word, and one containing a harmless word that contains it | The first is refused with a message. The second is accepted. |

### 7.6 Squads and Seasons (SQD and SEA)

| ID | Test | Expected |
|---|---|---|
| SQD-01 | A creates squad 1 and invites C. C accepts. | C appears on the roster, on both. |
| SQD-02 | A invites B while B already leads squad 2 | B's inbox row explains why B can't join. |
| SQD-03 | C leaves squad 1, then rejoins | Both work, and the roster updates live. |
| SEA-01 | Squad 1 and squad 2 queue with overlapping courts and time windows, for about 70 minutes out | Matched within seconds. Both see the match card with the opponent's crest and record. |
| SEA-02 | The notification pre-prompt and the system prompt on the first match | Pre-prompt, then the system dialog. If denied, game day shows that reminders are off. |
| SEA-03 | Game day: A taps "We're here" | Phone B sees it live. |
| SEA-04 | Both leaders report the same winner | Confirmed. The winner sees confetti **exactly once**. Both records update. |
| SEA-05 | A second match: the leaders report different winners, then one re-reports | Disputed, then confirmed. |
| SEA-06 | A leader cancels a scheduled match | The other side sees it cancelled. |
| SEA-07 | **A disbands squad 1 while it has a scheduled match** | The match is cancelled first. B sees "cancelled", **not** "Waiting on". Squad 1's ticket is gone from the pool. |
| SEA-08 | A queues and puts the app in the background. B queues. | B's phone makes the match. When A reopens the app, the match is there. |

### 7.7 Notifications (NOT)

| ID | Test | Expected |
|---|---|---|
| NOT-01 | Allow notifications through the pre-prompt | Granted. Reminders get scheduled. |
| NOT-02 | The T−60, T−0 and T+90 reminders from SEA-01 | Each fires on both phones. Tapping one opens the inbox. |
| NOT-03 | On a third phone or the simulator, schedule a match, sign out before T−60, then wait | **Nothing fires.** |
| NOT-04 | A reminder arrives while the app is open | It shows as a banner. |

### 7.8 Account deletion (DEL)

| ID | Test | Expected |
|---|---|---|
| DEL-01 | Account E has: a hosted run B joined, a run A hosts that E joined, a waitlist spot, a friendship with A, a pending request to B, and a one-person squad it leads with a scheduled match against squad 2. E deletes its account. | It asks for the password, asks to type DELETE, then finishes. **Then check in the console:** no `users/E`, no friendships with E, the hosted run cancelled (B sees "Called off"), E gone from A's roster, the squad gone, the match cancelled (B sees it), no invites or ticket left. |
| DEL-02 | Turn airplane mode on partway through deleting | The error says what failed. **Retry** after reconnecting finishes the job. |
| DEL-03 | Sign up again with E's email | A fresh, empty profile. |
| DEL-04 | Enter the wrong password at the re-authentication step | A clear error. Nothing is deleted. |
| DEL-05 | VoiceOver through the whole deletion flow | Every step can be reached and is read out properly. |

### 7.9 Interface, accessibility, network and release build (UI, NET, REL, BE)

| ID | Test | Expected |
|---|---|---|
| UI-01 | Rotate the phone on every tab and with every sheet open | Nothing rotates. |
| UI-02 | Every tab, onboarding and the new sheets: light and dark, default and `.accessibility3` text | No clipped or cut-off text. The inbox's sent-request row and the Profile header are fixed. |
| UI-03 | **VoiceOver sweep:** every item in `gaps/ACCESSIBILITY.md`'s "Still to do", plus onboarding, report, block and delete | Everything has a label, the reading order makes sense, and the scoreboard stops rotating under VoiceOver. |
| UI-04 | Reduce Motion: the squad push, the scoreboard and the calendar | The calmer motion versions are used. |
| UI-05 | Smallest and largest screens (17e and 17 Pro Max simulators): every tab and onboarding | Nothing overlaps. Buttons are at least 44pt. |
| UI-06 | Haptics (phone only) | They fire where they're designed to. |
| UI-07 | Profile → Privacy, Terms, Support | Each opens the right page or a mail draft. |
| NET-01 | Airplane mode on Home and Runs, then off | You see the "Try again" error, **not** an empty list that looks loaded. It recovers without relaunching. |
| NET-02 | Very Bad Network: join, leave and create a run | Shows pending, then either succeeds or gives a clear error. No double joins. |
| NET-03 | Leave the app in the background for over an hour, then return | The lists refresh to the current time window. |
| NET-04 | Force-quit the app in the middle of creating a run | No half-created run, and no stuck "saving" spinner. |
| REL-01 | The TestFlight build | The DEBUG-only screens (the component gallery) aren't reachable. |
| REL-02 | Trigger the Crashlytics test crash (not attached to the debugger), then reopen the app | It shows up in Crashlytics within about 10 minutes, with readable (symbolicated) stack frames. |
| REL-03 | Use the app for 10 minutes | The App Check console shows **verified** requests from the build. |
| REL-04 | The archive's privacy report | It lists UserDefaults with reason `CA92.1` and the declared data types. |
| REL-05 | The Profile footer's version | It matches the build that was uploaded. |
| REL-06 | Cold launch on phone A (open the app fully closed) | Home is usable in about 2 seconds or less. |
| REL-07 | **Count the reads of one cold launch** (Firestore console → Usage, before and after) | Write the number into A§4.2 to replace the estimate. |
| REL-08 | Instruments → Leaks: 10 minutes of switching tabs and opening and closing sheets | No steady growth. |
| REL-09 | 20 minutes on the Map tab with location on (Xcode's energy gauge) | No runaway energy use, now that location isn't continuous. |
| BE-01 | Console: rules version history | The live version is the latest deploy, from the commit recorded in ROADMAP. |
| BE-02 | Console: indexes | All "Enabled", including the new waitlist index. |
| BE-03 | As account C, try to read `reports` and someone else's `blocks` | Refused (spot check; the rules tests already cover this). |
| BE-04 | Billing | The budget alert is set (if Blaze) and an alert email has been received (send a test one). |

**Free-form bug hunt (Sat 13:00, 90 minutes).** Each tester picks two of
these themes and writes down everything odd:

1. "My first 10 minutes as a brand-new user in Cary."
2. "Try to break the inbox": rapid accepts and declines, plus notifications
   arriving at the same time.
3. Switch tabs as fast as possible with sheets open, and rotate the phone.
4. "I'm a troll": spam requests, offensive names, block, then unblock.
5. Edges of time: create runs at 23:55 and at midnight, on the last allowed
   day, and leave the app in the background across midnight.
6. Spotty connection: walk out of Wi-Fi range in the middle of a match
   report.

### 7.10 Quick check (about 20 minutes, on every new release candidate)

AUTH-02 · AUTH-04 · LOC-01 (or LOC-03) · RUN-01 · RUN-02 · RUN-06 · INV-03
· FRD-02 · FRD-05 · SEA-03 · DEL-04 · UI-01 · NET-01 · REL-01 · REL-05.
Plus **every test case in the area a fix touched**.

---

## 8. Bug triage

Log every finding as a GitHub issue labelled `launch`, plus one severity
label. Fix it on a `fix/<issue#>` branch, with a test that fails without the
fix.

| Severity | Meaning | When it must be fixed |
|---|---|---|
| **Sev 1** | A crash, data loss, a security or privacy hole, an App Store blocker, or a core flow that can't be completed (sign-in, joining a run, deletion) | **The same day.** It blocks the release candidate. |
| **Sev 2** | A core flow that's wrong but can be completed, misleading information, an accessibility blocker | Before **COMPLETE** (Sunday) |
| **Sev 3** | Cosmetic, or has an easy workaround | The 1.1 list (§10), unless it's a one-line fix with a test |

**Before the beta starts (Mon 10/26), nobody downgrades a Sev 1 or Sev 2.**
If a severity really is wrong, write down why in the issue.

---

## 9. Risks and what to cut if the week slips

### Risks

| # | Risk | Likelihood | Impact | What to do about it |
|---|---|---|---|---|
| R1 | The Apple Developer account isn't active, or the LLC still needs a D-U-N-S number | Unknown, so **check it tonight** | Blocks TestFlight and every date | Day 0 check. Fallback: enroll as an individual for 1.0 and move the app to the LLC later. |
| R2 | The name "hoopsRN" is taken | Low | Store listing and branding | Reserve it on Day 0. Have a fallback ready. |
| R3 | Rejected under 1.2 (user content) or 5.1.1(v) (deletion) anyway | Medium | About a week's delay | Thursday's complete set of safeguards. Review notes that point to each one. The 11/10 fallback launch date. |
| R4 | A rules deploy breaks an installed build | Low | Everyone gets "permission-denied" | The §6 protocol, rollback in the console, and no rules changes after the freeze. |
| R5 | Account deletion takes longer than a day | Medium | Pushes Thursday back | It's the only item in Wednesday, and Thursday has slack built in. Cut from the list below, never from P0. |
| R6 | Tester 2 can't make Saturday | Medium | No two-phone pass | Book them tonight. Fallback: the simulator as phone B for everything except notifications and haptics, then a two-phone session on Monday 10/26 before the beta starts. |
| R7 | The daily read limit runs out during the beta (if still on Spark) | Medium | The app stops working for everyone | D1 = Blaze. Otherwise REL-07 tells you the real number, and cap the completed-runs listener. |
| R8 | App Review sees an empty app | High without the demo account | Rejected under 2.1 | The demo account D, data in Durham, and review notes. |
| R9 | Scope creep from good ideas found during testing | High | Delays | The freeze rule, and ideas go to §10. |

### What to cut, in this order

1. Universal Links. Becomes 1.0.1, unless INV-01 shows invites are
   unusable.
2. Capping the completed-runs listener. Only matters on Spark.
3. The two accessibility fixes, which are Sev 3. Become 1.0.1.
4. The notification pre-prompt.
5. Onboarding's home-court step. Keep the name and location steps.
6. Soft cancel (A§3.8). Fall back to a cancel confirmation that warns
   "players won't be notified".

**Never cut:** any A§2 item, A§3.1–3.7, App Check monitoring, Crashlytics,
the Saturday test day, the final regression, and the demo account.

**If COMPLETE slips by more than a day:** it moves to Tue 10/27. The beta
shrinks to at least 5 days, and submission and launch move with it. The
two-phone test day is never skipped or shortened.

---

## 10. After COMPLETE: beta, submission, launch, and the 1.1 list

### The beta, Mon 10/26 → Sun 11/1 (G8)

- [ ] 5–15 local players on external TestFlight, with a one-paragraph brief:
      "create a run, invite a friend, try Seasons with a squad".
- [ ] Check every day: Crashlytics (crash-free users), Firestore usage
      against the daily limit, new sign-ups, **reports (twice a day, because
      Apple requires timely responses)**, and the support inbox.
- [ ] Only Sev 1 and Sev 2 fixes. Each one is a new build, gets the quick
      check, and is logged.
- [ ] **G8 — ready to submit when:** at least 99.5% of beta users are
      crash-free, there are no open Sev 1 or Sev 2 bugs, at least 3 real runs
      have been created and joined by testers, and at least one Seasons match
      has been confirmed between two testers who aren't you.

### Submission, Mon 11/2

- [ ] Go/no-go: G8 is met, the demo account still works (sign in on a clean
      phone that morning), and the rules haven't changed since the final
      release candidate.
- [ ] Submit, set to manual release. If rejected, fix it, reply in
      Resolution Center, and resubmit the same day.

### Launch day, Thu 11/5 (fallback Tue 11/10)

- [ ] Morning: confirm the rules and indexes haven't changed, App Check is
      still in monitoring, Crashlytics alerts are on (new fatal issue, and
      crash-rate spikes), and the budget alert is on.
- [ ] Release. Install from the **App Store** onto a clean phone and repeat
      AUTH-01, LOC-01 and RUN-01.
- [ ] Announce to the local players.
- [ ] Watch closely: every 4 hours on day 1, twice a day on days 2–3. Check
      Crashlytics, Firestore usage, sign-ups, reports, and support email.

### When something goes wrong

| Symptom | First move |
|---|---|
| A crash spike | Find it in Crashlytics, fix it with a test, upload a hotfix build, and **request an expedited review** |
| "Not allowed" or permission-denied errors everywhere | Firebase console → Rules → history → **roll back to the previous version**. Then find the cause in the repo using the rules tests. |
| The daily read limit runs out (Spark) | **Upgrade to Blaze right away** (it takes minutes). Requests start working again. |
| An abusive account | Disable it in Firebase Auth, delete its content in the console, and answer the report |
| A data bug in production | There's no remote switch to turn features off in 1.0, which is an accepted risk. Fix it in a hotfix, and repair the data in the console. |
| Everything else | Write it up as a Sev-labelled issue and triage it (§8) |

### The 1.1 list (starts the week after launch)

Items the audit put after launch, plus whatever this week cut:

- Turn App Check enforcement on once at least 95% of requests are verified
  for a week.
- From A§7.1: host promotes from the waitlist, Add to Calendar, players
  can share private-run links, a rating prompt, Universal Links (if cut).
- Split `MapTab.swift` (A§5.3). Turn on `SWIFT_STRICT_CONCURRENCY = complete`.
- Test iOS 18 and lower the minimum again (if D2 raised it).
- A§5.4's two scripts.
- Then the post-launch list in A§7.2: run detail, push notifications (now
  possible on Blaze), automatic completion and waitlist promotion, and the
  rest.

---

## 11. Daily log

One row per day, filled in at the gate. A slip is written here the day it
happens, not discovered on Sunday.

| Date | Gate | Met? | Swift tests | Rules tests | Warnings | Open Sev 1/2 | Notes and slips |
|---|---|---|---|---|---|---|---|
| Sun 10/18 | Day 0 | | 811 / 48 | 148 | 10 + 27 | — | Audit and gameplan written |
| Mon 10/19 | G1 | | | | 0 | | |
| Tue 10/20 | G2 | | | | 0 | | |
| Wed 10/21 | G3 | | | | 0 | | |
| Thu 10/22 | G4 | | | | 0 | | |
| Fri 10/23 | G5 | | | | 0 | | |
| Sat 10/24 | G6 | | | | 0 | | |
| Sun 10/25 | **G7 COMPLETE** | | | | 0 | 0 | |

---

## See also

- [`PRE_LAUNCH_AUDIT.md`](PRE_LAUNCH_AUDIT.md): what each item is and why.
  This file only schedules and tests them.
- [`../ROADMAP.md`](../ROADMAP.md): update its deploy note at each rules
  deploy, and remove items as they ship.
- [`../gaps/TESTING.md`](../gaps/TESTING.md) and
  [`../gaps/ACCESSIBILITY.md`](../gaps/ACCESSIBILITY.md): where the manual
  checks in §7 came from.
- `firestore-tests/README.md`: the rules test setup (it needs a JDK).
