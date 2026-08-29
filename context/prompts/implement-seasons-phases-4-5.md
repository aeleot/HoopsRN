# Implement — Seasons Phases 4–5 (season games, game day)

Turn a won claim into a scheduled game both squads can see, then make game day
work — Phases 4 and 5 of `context/plans/SEASONS.md`.

**Read `context/plans/SEASONS.md` in full before writing anything.** It is the
authoritative spec. This prompt tells you *how to execute* it and what the
previous session left open; it does not restate the design. Where anything here
seems to conflict with the plan, **the plan wins — but stop and flag the
conflict**, because a conflict means one of the two documents is stale.

**Also read `context/prompts/implement-seasons-phases-1-3.md`.** Its invariants
still hold, its error-handling table is still the house answer, and its
"wait vs. stop" rules still apply. This prompt adds to it rather than replacing
it.

> **Run these as three separate sessions, in this order, committing between
> each: Phase 3.5, then Phase 4, then Phase 5.** Each is independently
> shippable and leaves the app working. Phase 3.5 is infrastructure and
> concurrency; Phase 4 is a schema, a rules block and three screens; Phase 5 is
> a vendor boundary and a permission moment. Attempting them together will
> exhaust context somewhere in Phase 4's rules and produce drift in the
> emulator harness — which is the half everything else is now verified against.

---

## Where the last session stopped, and why

Phases 1–3 shipped in `54ff8a8`, `d6bca0e`, `a4be2d0`. The suite went from 212
to 346 passing, 0 failing. **`MatchmakingService` was deliberately not built.**

`SEASONS.md` §6 makes the Firestore emulator a Phase 0 gate, and it is open:
`firebase.json` declares no `emulators` block, there is no `package.json`, and
`node_modules/` holds 27 transitive HTTP packages left over from the
court-fetch scripts rather than a Firebase test stack. The claim is a
one-document race, and **a race that has never been raced is a claim, not a
result** — so the previous session built everything that didn't depend on it
(`MatchTicket`, `MatchRules`, 40-odd tests, the `matchTickets` rules block, the
pool index) and stopped at the transaction.

**Phase 4 is "game creation on a won claim." There is no won claim yet.** So
this prompt opens with Phase 3.5: close the gate, then finish Phase 3.

Five other things were left open and are folded in below rather than left to be
rediscovered.

---

## Preflight — three gates

### Gate 1 — the blank screen. Blocks Phase 5's verification entirely.

The app **builds, launches, and does not crash**, but renders a blank white
screen in the iPhone 17 simulator. Established last session:

- the process stays alive, completes network activity, and requests location;
- nothing in `log show --predicate 'process == "hoopr"'` reports a crash;
- SpringBoard renders normally, so the simulator itself is fine;
- **and a build from `54ff8a8` — which changes no UI at all — shows the same
  blank screen.** It is pre-existing, not something Seasons introduced.

Neither `RootView`'s `LaunchScreen` (a `basketball.fill` glyph and a spinner)
nor `LoginView` is drawing.

**Diagnose this before Phase 5.** Phase 5's done-when is "a scheduled game
notifies at T−60 and both squads can see each other arrive," which cannot be
observed in a unit test. Start at `RootViewModel.destination` — log which case
it resolves to, and whether `AuthService.$currentUser` ever emits.

- If it is fixable, fix it in its own commit, before Phase 4's screens. It is
  not Seasons work and should not ride in a Seasons commit.
- If it is not, **say so explicitly and scope Phase 5 down**: build it, unit-test
  the scheduling decisions, and report that the T−60 delivery and the live
  arrival check marks are unverified. Do not describe them as working.

### Gate 2 — the emulator. Blocks Phase 4.

Phase 3.5 exists to close this. See below.

### Gate 3 — the schema doc. Blocks Phase 4's schema.

`context/database/DATABASE_SCHEMA.md` contains **no mention of `squads`,
`squadInvites` or `matchTickets`.** Three collections shipped without it, and
the plan asks for the opposite in four places — §1.3 ("record this in
`database/DATABASE_SCHEMA.md`"), §1.5 ("Record it … rather than leaving it to be
discovered"), §3 ("State it in `database/DATABASE_SCHEMA.md` next to the
rule"), and §6's Phase 0 ("Write the decisions into
`database/DATABASE_SCHEMA.md` **before** code").

**Backfill the three shipped collections before adding a fourth.** Documenting
four at once is how a schema doc becomes a summary of what someone remembered.
What has to be in it, because none of it is recoverable from the code alone:

1. **`squads` is readable by any signed-in user**, like `users` and unlike
   `friendships` — an opponent has to render your crest on a match card. The
   plan states this for `seasonGames` and leaves it implicit for `squads`. The
   create rule's key allowlist is what keeps it safe.
2. **`matchTickets` carries no `updatedAt`.** §1.3's field table omits it;
   §2.2's rules snippet includes it in `affectedKeys()`. The field table won,
   because `claimedAt` already is the ticket's "when did this change" stamp and
   the claim is the ticket's only mutation. **Record the resolution, not just
   the outcome** — and if Phase 4's `matched` transition makes you want an
   `updatedAt` after all, that is a decision to reopen deliberately, not to
   drift into.
3. **Record proximity is a gate, not only a score.** §2.1 lists it under soft
   rules; the same section's relaxation paragraph names "the record-proximity
   tolerance" as something relaxation widens. It is implemented as a gate —
   0.35 apart at relaxation 0, fully open at relaxation 1 — so it changes *when*
   an uneven match happens, never *whether*. This is the hook a skill rating
   plugs into later (§7).
4. **`squadInvites` are answered from the Seasons tab**, which is not one of
   the plan's numbered screens. Without somewhere to accept, a roster could
   never gain a second member, which is the only thing the self-join rule
   exists for.

`CLAUDE.md` also says "120 real test methods across 11 suites." It is 347
across 23. Fix that in the same pass.

---

## Invariants — carried forward, still load-bearing

Every invariant in `implement-seasons-phases-1-3.md` still applies. The three
that will bite hardest here:

**Xcode target membership is automatic.** `PBXFileSystemSynchronizedRootGroup`
picks up any `.swift` file under `hoopr/` or `hooprTests/`. **Do not hand-edit
`project.pbxproj`.** This now extends to frameworks: `import UserNotifications`
needs no project change — the framework auto-links.

**Every test targets a `nonisolated static` pure function.** No test in this
suite instantiates a service. Phase 5's scheduling decisions — which
notifications, when, with what identifiers and copy — must therefore be a pure
function over a `SeasonGame` and a `now`, with `UNUserNotificationCenter`
merely *executing* the plan it returns. A method that both decides and
schedules is, in this project, untestable.

**The vendor boundary holds, and now has a second vendor.** Firebase imports
live only in `hoopr/Services/`. `UserNotifications` gets the same treatment:
one service owns the framework, and no view or view model imports it.

**Server timestamps are pinned, not requested.** `FieldValue.serverTimestamp()`
client-side, `== request.time` in the rules.

**Run tests with the target filter, always:**

```bash
xcodebuild test -project hoopr.xcodeproj -scheme hoopr -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:hooprTests
```

**Dry-run rules before claiming they work** — and from Phase 3.5 on, that is no
longer sufficient on its own:

```bash
firebase deploy --only firestore:rules,firestore:indexes --dry-run
```

---

# Phase 3.5 — Close the gate, then finish Phase 3

**No new screens, no new collections.** This phase ends when the claim race has
actually been raced.

## Build

- An `emulators` block in `firebase.json` — Firestore on 8080 is enough; the
  emulator UI is optional and costs a second port.
- A `package.json` at the repository root with `firebase-tools` and
  `@firebase/rules-unit-testing`. **Prefer node's built-in `node:test` runner**
  over adding Jest or Vitest: this repo has no JS test culture to match, and a
  second test framework is a second thing to keep working.
  `node_modules/` is already gitignored and untracked, so nothing has to be
  reconciled with the 27 orphaned packages already there — but say in the
  `package.json` or a sibling README what they were for, or somebody will
  delete the wrong thing.
- `firestore-tests/` (or similar) — the rules suite. **This is the deliverable
  the gate exists for**, not a side effect of it.
- `hoopr/Services/MatchmakingService.swift` — pool listener, scan, claim
  transaction, jitter and backoff. Plan §2.2 and §2.5.
- Whatever `MatchRules` needs that Phase 3 deferred. It should need nothing;
  if it does, that is a finding worth reporting.

## The rules suite is the point

`FirestoreRulesParityTests` says in its own doc comment: *"What this is not: a
rules evaluator… Full rules coverage needs the Firebase emulator, which isn't
wired up here."* That sentence stops being true in this phase. Cover, at
minimum:

- **The claim race.** Two concurrent clients, one ticket. Exactly one wins; the
  loser gets a transaction failure, not a corrupted document. Run it enough
  times to mean something — a race that passes once passed by luck.
- **Stale re-claim.** A ticket claimed 91 seconds ago can be re-claimed; one
  claimed 89 seconds ago cannot. This is the constant three places already
  agree on in Swift; the emulator is where the fourth copy — the deployed rule —
  finally gets checked.
- **Phase 1 test case #3, which was never runnable.** "A self-join write whose
  `memberIds` diff contains a uid other than the caller's is rejected." A
  dry-run compiles rules; it cannot evaluate a write. This can.
- **The duplicate-roster hole.** `['leader','me','me','me','me','me']` must be
  refused. The whole no-duplicates check exists for it and nothing has ever
  exercised it.
- **The invite friendship gate.** An invite to a stranger is refused; to a
  pending friend, refused; to an accepted friend, allowed.
- **The three squad update paths in isolation.** A leader edit that also
  touches `memberIds`; a join that also renames; a leader trying to self-leave.

Each of these is a rule that has only ever been *read*. Treat a passing
dry-run as evidence the file compiles and nothing more.

## MatchmakingService

Follow `GameService.mutateRoster` for the transaction's shape:
`database.runTransaction`, an `errorPointer` on the read failure path, and a
raw-value outcome enum carried out of the block because `runTransaction` hands
back `Any?`.

**Re-check `MatchRules` inside the transaction.** The pool snapshot that
produced the candidate may be seconds stale, and the transaction's own read is
the only view of the ticket that is guaranteed current.

**Do not implement retry-on-transient-error yourself.** `ListenerSupervisor`
owns that for the pool listener. The claim's own retry is a different thing —
bounded at three attempts, then a 15-second poll — and it is about *contention*,
not network health. Keep them separate, and say so in a comment, because the
next reader will try to merge them.

The pool query is `region ==`, `format ==`, `status in ['open', 'claimed']`,
`expiresAt >`. The composite index for it already exists. `status in [...]`
rather than `== 'open'` is what makes stale claims visible to the scanner; a
query that filtered to `open` alone would make §2.3's recovery unreachable and
nothing would report it.

Jitter 0.5–3s before claiming, claim only the top candidate, re-scan on
failure rather than blindly trying the next.

## Done when

Two concurrent clients race for one ticket against the emulator and exactly one
wins — proven, repeatedly, in a test that runs from the command line. The Swift
suite still passes. No `seasonGames` document exists yet.

---

# Phase 4 — Season games

**No notifications, no arrival, no results.** Phase 4 ends when both squads see
the same scheduled game and either leader can cancel it.

## Build

- `hoopr/Models/SeasonGame.swift` — the model and its pure helpers. Plan §1.5.
- `hoopr/Services/SeasonGameService.swift` — the `squadIds array-contains`
  listener and the create/cancel writes.
- The `seasonGames` rules block (plan §2.4), the `matched` transition on
  `matchTickets`, and the `(squadIds, scheduledTime)` composite index.
- `hoopr/Views/Seasons/QueueSheet.swift` — screen 4.
- Searching and match-found states — screens 5 and 6. They are states of squad
  home, not separate destinations; the plan's §5 screen 2 already says the card
  is *"next match, searching, or find a match."*
- `hooprTests/SeasonGameTests.swift`, and rules tests in the Phase 3.5 harness.

## Who owns the write, and why it matters

The claim-then-create sequence spans two collections: `MatchmakingService` owns
`matchTickets`, and `seasonGames` needs an owner. **State your reasoning before
you write it.** The house rules pull in opposite directions here:

- One service per collection, and services have no dependencies on each other.
- `SquadService` already owns two collections, justified because a
  `squadInvite` "has no independent existence." A `seasonGame` **does** — it
  outlives both tickets, has its own listener, and survives into Phase 6.

**Default: `SeasonGameService` owns `seasonGames`, and a view model holding both
services sequences claim → create → mark matched.** That keeps the services
independent, at the cost of putting a write *sequence* in a view model where
the precedent is joins only. If you conclude otherwise, say why in the commit
message.

**Stop and report if the orchestration requires one service to hold a reference
to another.** Nothing here needs that, and if it seems to, the design has
drifted.

## The double-booking window the plan does not cover

§2.3 covers a claimer that dies *before* writing the game: the claim goes stale
after 90 seconds and the ticket returns to the pool. It does not cover a
claimer that dies **after** writing the game and before marking the tickets
`matched`.

That ticket also goes stale — and its game already exists. A third squad
re-claims it and creates a second game against a squad that already has one.

**Handle it, and handle it the way the security model allows.** The fix that
needs no new permission: **each squad marks its own ticket `matched` off its
own `seasonGames` listener.** A leader can always write their own ticket, so
the home squad closes the window itself the moment the game lands, without
anyone writing anyone else's document. The away leader's write stays as the
fast path; this is the one that makes it safe.

The `matched` transition rule therefore admits two writers: the leader named in
`claimedBy`, and the ticket's own leader. Keep it a separate `allow update`
from the claim — the same one-write-one-path split `squads` uses.

Duplicate games can still be created inside the window. Render the
earliest-created one and let a leader cancel the other; do not try to prevent
it in rules, which cannot query.

## `wins` and `losses` are a query, and the query is empty

Plan §1.1: a squad's record is derived from
`seasonGames where squadIds array-contains {squadId} and status == "confirmed"`,
never stored. `matchTickets` denormalizes `wins`/`losses` *at queue time* for
ranking.

Until Phase 6 confirms anything, that query returns nothing and every ticket
queues at 0–0. **Write the derivation now anyway.** A ticket that hardcodes
zeros is a ticket whose numbers silently stay zero after Phase 6 ships, and
nothing will fail — `MatchRules` will just rank everyone as unplayed forever.
`MatchTicket.winPercentage` already returns 0.5 for an unplayed squad, so the
empty case is already correct; what is missing is the query that fills it.

## Screens 4–6

**Screen 4 — queue sheet.** Time window as chips ("Tonight", "Tomorrow
evening", "Custom") and courts as a multi-select defaulting to the three
nearest, so the common case is two taps. `MatchTicket.validate` already mirrors
every bound the create rule enforces; the sheet's Save button and its inline
hint both read it, the way `CreateGameSheet` reads `Game.validate`.

**Screen 5 — searching.** Live pool count, elapsed time, and an explicit
"Widening the search" state when relaxation kicks in. Cancellable.
`MatchRules.relaxation(for:now:)` is what the copy reads — the UI says the
standards are widening *because* they are, not on a timer that happens to
agree.

**Screen 6 — match found.** Both crests, the opponent's record, court, time,
and the leader's cancel control.

Styling is not freehand: `Color.hoopr*` roles, `.hooprFont(_:weight:)`,
`.cardChrome()`, `SquadCrest` at one of its five named sizes, sheets with
`sheet(item:)`. There are no literal colours in `Views/`; do not be the first.

## Done when

Two simulator instances queue, match, and both see the same scheduled game with
the same court and the same tip-off, and either leader can cancel it. Verified
against the emulator for the rules and in the app for the flow — or, if Gate 1
is still open, verified against the emulator and reported honestly as unseen.

---

# Phase 5 — Game day

**No results, no reports, no record.** Phase 5 ends when both squads can see
each other arrive.

## Build

- `hoopr/Services/NotificationService.swift` — the only file in the app that
  imports `UserNotifications`.
- `hoopr/Models/SeasonGameNotifications.swift` — **the pure part**: which
  notifications a game needs, when they fire, their identifiers and their copy,
  as a function of a `SeasonGame` and a `now`.
- The `arrivedPlayerIds` update path in `firestore.rules`.
- `hoopr/Views/Seasons/GameDayView.swift` — screen 7.
- `hooprTests/SeasonGameNotificationsTests.swift`, and rules tests for arrival.

## The split is the whole design

`UNUserNotificationCenter` cannot be tested here, and the *decision* about what
to schedule is the part that can be wrong in a way nobody notices — a
notification that fires at the wrong hour, or an identifier that duplicates
instead of replacing. So:

```swift
nonisolated enum SeasonGameNotifications {
    struct Planned: Equatable {
        let identifier: String   // "seasonGame:{id}:{kind}"
        let fireDate: Date
        let title: String
        let body: String
    }

    static func plan(for game: SeasonGame, opponentName: String, now: Date) -> [Planned]
}
```

`NotificationService` executes a plan and nothing else: it requests
authorization, removes the identifiers in the plan, and adds the requests.
Every decision — including "this game already started, schedule nothing" — is
in the pure function, and every one of them gets a test.

Identifiers are `seasonGame:{id}:{kind}` precisely so a cancellation or a stale
copy is **removed and replaced** rather than duplicated. Test that a re-plan
for a rescheduled game produces the same identifiers.

Copy, from plan §4:

| Trigger | Copy |
|---|---|
| T−60 min | "3v3 vs {opponent} in an hour — {court}" |
| T−0 | "Tip-off. Tap to mark your squad as arrived." |
| T+90 min | "How'd it go? Record the result." |

The T+90 one points at a screen Phase 6 builds. Ship it anyway — the schema and
the copy are settled, and a notification added later would miss every game
played in between.

## The permission moment

Ask at **match found**, not at launch and not on the game-day screen. It is the
first moment a notification is worth anything and the first moment the user has
just gained something, which is the only leverage a permission prompt ever has.
A denial is not an error state: the game-day screen works without
notifications, and it should say what was missed rather than nagging.

**`AppDelegate` needs no change.** Its comment names APNs registration as its
future purpose, and local notifications need no APNs token — so do not add
registration, and do not read the comment as an instruction.

## The limitation is named, not fixed

A client that never launches between the match being made and the game starting
never schedules its notification. Real push needs Blaze and a Cloud Function.
**Put this in `context/GAPS.md` when this ships**, in the same commit, rather
than letting someone rediscover it. `GAPS.md` already carries the same shape of
entry for `userNameLower`'s client-side backfill; match it.

## Arrival

`arrivedPlayerIds` is the existing self-only membership pattern verbatim: the
diff is exactly the caller's own uid, and the caller must be in one of the two
squads' `memberIds` — two `get()`s, well inside the ten-access ceiling. Reuse
the `games` idiom, **including the no-duplicates check**; the reason it is not
optional is documented in the `squads` block and has not changed.

Both squads read the same array off the same listener, which is the moment in
the brief where one squad sees they are first to the court.

## Done when

A scheduled game notifies at T−60, and both squads see each other's check marks
live. If Gate 1 is still open, the notification delivery and the live update are
**unverified** — say so plainly and do not describe them as working.

---

## Error handling

Everything in `implement-seasons-phases-1-3.md`'s table still applies. New
paths:

| Situation | Required response |
|---|---|
| Claim transaction loses the race | Expected, not an error. Re-scan and take the next candidate. **Never surface a message** — losing a race is invisible by design. |
| Claim fails three times | Back off to a 15s poll. A quiet "still looking" state, not an error banner. |
| Game created, tickets not marked `matched` | The home squad's own client closes the window off its `seasonGames` listener. No user-visible error. |
| Two games exist for one pair | Render the earliest-created; a leader cancels the other. Log it — if it happens more than rarely, the jitter or the stale window is wrong. |
| Notification authorization denied | Not an error. The game-day screen works; it states once what won't arrive, and never asks again. |
| Notification scheduling throws | Log and continue. A missing reminder must never block the screen that shows the game. |
| `arrivedPlayerIds` write refused | The caller isn't on either roster, or the state moved. Say the state may have changed; **never blame deployment on a write**. |
| Emulator not running when the rules suite is invoked | Fail with a message naming the command that starts it. A rules suite that silently passes without an emulator is worse than none. |
| A `seasonGame` fails to decode | Skip that document, log it, keep the rest of the list — `GameService.decoded`'s rule. One drifted row must not blank game day. |

---

## Wait vs. stop

**Wait for input — ask, then hold — if:**

- Closing Gate 2 would mean adding a second JS test framework, or otherwise
  growing the toolchain beyond `firebase-tools` plus
  `@firebase/rules-unit-testing`. That is a repo-shape decision.
- The blank screen (Gate 1) turns out to be a Firebase project or credentials
  problem rather than a code one. Nothing in this prompt authorizes touching
  either.
- A plan decision reads two ways and the readings produce different schemas.
  Quote both readings; do not pick one. Two such cases are already resolved in
  Gate 3 — resolve a third the same way, in writing, and only after asking.

**Stop and report — do not retry — if:**

- The claim race does not produce exactly one winner. That invalidates §2.2,
  which the entire feature rests on. Report the observed behaviour before
  changing any design.
- One service needs a reference to another. Nothing here needs that.
- A rules change would weaken an existing `games`, `users`, `friendships`,
  `squads` or `matchTickets` rule. Nothing here needs that either.
- `project.pbxproj` seems to need editing. It does not; a synchronized group
  picks files up and frameworks auto-link.
- You find yourself needing a Cloud Function. `SEASONS.md` §0 exists precisely
  because there isn't one.
- The Swift suite fails in a way suggesting it was already broken. The baseline
  is **346 passing, 0 failing** at `a4be2d0`. Report before changing anything.

---

## Chain-of-thought

**Before writing `MatchmakingService`'s claim transaction, state:**

1. What the transaction reads, what it re-checks, and why re-checking inside is
   not redundant with the scan outside
2. What happens to each loser of the race, and why that is not an error
3. Which retry belongs to `ListenerSupervisor` and which belongs to the claim,
   and what breaks if they are merged

**Before writing the `seasonGames` create rule, state:**

1. What authorizes naming another squad's ID in a document, given that no
   client may write another person's uid
2. Which fields are pinned to the home ticket, and what a modified client could
   do if they weren't
3. How many document accesses the rule costs and how that compares to the ten
   the platform allows

**Before writing `SeasonGameNotifications`, state:**

1. Which decisions are in the pure function and which are in the service, and
   how you would test each
2. What makes an identifier stable across a reschedule, and what duplicates if
   it isn't
3. What a user who denied permission sees, and what they don't

Then write the code.

---

## Model recommendation

| Phase | Model | Why |
|---|---|---|
| 3.5 | **Opus** | Emulator infrastructure plus transaction semantics. The race is the one thing in this feature that cannot be reasoned about from the code alone. |
| 4 | **Opus** | A rules block with cross-document `get()`s, a two-collection write sequence, and a recovery window the plan doesn't cover. Rules mistakes surface as `permission-denied` at runtime, not as compile errors. |
| 5 | **Sonnet** | A vendor wrapper, a pure scheduling function, and one screen against an established design system. Escalate to Opus if the arrival rules need more than the `games` idiom. |

---

## Test cases — these verify the prompt, not just the code

**Phase 3.5**
1. Two concurrent transactions claim the same ticket; exactly one commits and
   the document ends up claimed by that one squad. Repeated, not observed once.
2. A `memberIds` write adding a uid other than the caller's is rejected by the
   emulator — the assertion `FirestoreRulesParityTests` says it cannot make.
3. `MatchmakingService` losing a claim surfaces **no** `errorMessage`, and
   re-scans.

**Phase 4**
1. A `seasonGames` create naming a court absent from the home ticket's
   `courtIds` is rejected; the same create with a listed court succeeds.
2. A leader whose game exists but whose ticket is still `claimed` marks their
   **own** ticket `matched`, and the rules allow it.
3. Both squads' `squadIds array-contains` listeners deliver the same game
   document with the same `courtId` and `scheduledTime`.

**Phase 5**
1. `SeasonGameNotifications.plan(for:opponentName:now:)` returns three planned
   notifications for a future game, none for a game that already started, and
   identical identifiers when re-planned after a reschedule.
2. An `arrivedPlayerIds` write adding a uid other than the caller's is
   rejected; adding the caller's own succeeds; adding a duplicate is rejected.
3. With notification permission denied, the game-day screen still renders the
   countdown, the court and both rosters.
