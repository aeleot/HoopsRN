# Implement — Seasons Phases 6–7 (results and record, polish and fold-in)

Turn a played match into a trustworthy result, then close the plan out — Phases
6 and 7 of `context/plans/SEASONS.md`.

**Read `context/plans/SEASONS.md` in full before writing anything.** It is the
authoritative spec: §3 for the reporting design and why it's trustworthy
without a server, §5 for screens 8 and 9, §6 for the phase boundaries, §7 for
what's explicitly out of reach. This prompt tells you *how to execute* that
plan correctly and in the right order; it does not restate the design. Where
anything here seems to conflict with the plan, **the plan wins — but stop and
flag the conflict**, because a conflict means one of the two documents is
stale.

**Also read both prior prompts**, in order:
`context/prompts/implement-seasons-phases-1-3.md` and
`context/prompts/implement-seasons-phases-4-5.md`. Their invariants still
hold, their error-handling tables are still the house answer, and their "wait
vs. stop" rules still apply. This prompt adds to them rather than replacing
them.

> **Run these as two separate sessions, in this order, committing between
> each: Phase 6, then Phase 7.** Phase 6 is a rules transition, a service
> method, and two screens — it can be reasoned about in isolation and is
> independently shippable. Phase 7 touches five documentation files and a
> handful of small view changes across the whole feature; running it before
> Phase 6 lands would mean folding an incomplete plan into permanent docs,
> which is the opposite of what a fold-in is for.

---

## Where the last session stopped, and why

Phases 1 through 5 shipped across nine commits, most recently `0de2f48`. The
Swift suite is at **401 passing, 0 failing, 26 suites**; the emulator rules
suite (`npm run test:rules`) is at **66 passing, 0 failing**. Both rules and
indexes are deployed to `hoopsrn-4f1e9`.

`SeasonGame` already carries every field Phase 6 needs —
`homeReport`/`awayReport`/`homeScore`/`awayScore`/`result`/`confirmedAt` are
all declared on the model (`hoopr/Models/SeasonGame.swift`), because Phase 4
had to know the full shape to write the create rule's key allowlist. **None of
them has a write path.** The `seasonGames` rules block currently permits
exactly two transitions — cancel, and self-add to `arrivedPlayerIds` — and
`allow delete: if false` covers everything else. Reporting is new rules
surface, not a fill-in-the-blank on existing surface.

`SquadDetailView`'s own doc comment already says what's missing: *"Game
history and the form guide are Phase 6's; the space they'll occupy says so
rather than rendering an empty list that looks broken."* That empty space is
screen 9's half of this phase — Phase 6 is not only the Result screen.

**One thing this prompt cannot verify for you, and does not try to.** The
person running this session confirmed the single-client flow works — a squad
can be created, queued, matched, and shown on game day — but explicitly
deferred **two-account manual testing** to after the feature is fully built
out. Mutual confirmation is the one part of Seasons whose entire purpose is
*two different people disagreeing or agreeing with each other* — a property
no single-client smoke test can exercise. Build it, verify it against the
rules emulator (which **can** simulate two distinct authenticated callers) and
against `SeasonGameTests`' pure logic, and say plainly that the live two-person
confirm/dispute flow is unverified until that manual pass happens. Do not
describe it as working end to end.

Two more things worth knowing before you start, so you don't rediscover them:

- **The tab-label decision (`"Seasons"` vs `"Squad"`) is already settled.**
  `hooprTests/TabBarLabelTests.swift` measures all four tab labels at
  `.accessibility3` and asserts "Seasons" is the tightest fit and still has
  room. Phase 7's own list names this decision, but it does not need to be
  revisited — it needs to be *left alone*. If you find yourself wanting to
  change it, that's a signal something else drifted, not that this is open.
- **`database/DATABASE_SCHEMA.md` already documents `squads`, `squadInvites`,
  `matchTickets`, and `seasonGames`** — including §3's reporting design, added
  ahead of the rules that implement it, in the "Arrival" and surrounding
  sections. Phase 7's fold-in work for that specific file is close to done;
  read it before assuming there's a gap. `ARCHITECTURE.md`, `DATA_MODEL.md`,
  `UI_SHELL.md`, and `BUILD_AND_CONFIG.md` are the ones `check_context_drift.py`
  actually reports stale, and those are Phase 7's real work.

---

## Invariants — carried forward, still load-bearing

Everything in both prior prompts still applies. The four that will bite
hardest here:

**Every test targets a `nonisolated static` pure function.** No test in this
suite instantiates a service. The decision of whether two reports agree, and
what the resulting write should contain, has to be reasoned out as data before
it's reasoned out as a Firestore call — see the chain-of-thought below.

**The vendor boundary holds.** Firebase imports live only in
`hoopr/Services/`; `UserNotifications` lives only in
`hoopr/Services/NotificationService.swift`. Phase 6 adds no new vendor, so this
is a reminder, not a new constraint: don't let a `Timestamp` or a
`FieldValue` leak into `Models/` or a view model while wiring the report write.

**Server timestamps are pinned, not requested.** `confirmedAt` is exactly the
same shape as `createdAt`/`updatedAt` elsewhere: `FieldValue.serverTimestamp()`
client-side, `== request.time` in the rules.

**Xcode target membership is automatic.** Do not hand-edit
`project.pbxproj`. This has not changed and will not change.

**Run tests with the target filter, always:**

```bash
xcodebuild test -project hoopr.xcodeproj -scheme hoopr -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:hooprTests
```

**Evaluate the rules against the emulator, not just a dry-run:**

```bash
npm run test:rules
```

A dry-run proves `firestore.rules` compiles. It cannot evaluate a report
write, an agreement, or a disagreement — the emulator suite
(`firestore-tests/`) is the only thing that can, and it already has the
pattern to follow: `firestore-tests/season-games.test.mjs` seeds two squads
and two authenticated contexts exactly the way a reporting test needs to.

---

# Phase 6 — Results and record

**No standings, no leaderboards, no skill rating.** Phase 6 ends when a
completed game moves both squads' records, and a disagreement moves neither.

## Build

- The reporting rules block on `seasonGames` — a third `allow update` path,
  separate from cancel and arrival, following the "one write, one path"
  split those two already establish.
- `SeasonGameService.reportResult(gameId:squadId:winningSquadId:homeScore:awayScore:)`
  (name it however reads best; the shape matters more than the name) — the
  write that lands a leader's own report and, when it completes a matching
  pair, also sets `result`/`confirmedAt`/`status`.
- `hoopr/Views/Seasons/ResultView.swift` — screen 8.
- Fill in `SquadDetailView`'s history and form-guide space — screen 9's other
  half, and the reason the empty space there says "Phase 6's" instead of
  rendering nothing.
- `hooprTests/SeasonGameServiceTests.swift` or an extension of
  `SeasonGameTests.swift` — whichever the pure logic actually needs; see the
  chain-of-thought below for what "the pure logic" means here.
- Rules tests in `firestore-tests/`, most naturally a new
  `firestore-tests/results.test.mjs` alongside `season-games.test.mjs` and
  `arrival.test.mjs`.

## Who decides "these two reports agree," and where

**State your reasoning before you write it**, the same way Phase 4 stated
which service owns `seasonGames` and Phase 5 stated the pure/service split for
notifications. §3 says the mechanics; it does not say the shape of the write
that implements them, and there are two candidate shapes:

- A plain `updateData` call that writes only the caller's own report field,
  leaving `result`/`status` for... something else to compute.
- A `runTransaction` that reads the document, decides locally whether this
  report completes a matching pair, and writes the report **and** (when it
  applies) `result`/`confirmedAt`/`status = confirmed` in the same commit —
  following `GameService.mutateRoster`'s shape, the same one
  `MatchmakingService`'s claim transaction and `SquadService.mutateRoster`
  already use for "read the current state, decide the delta, write" against a
  single document.

The plain-write shape has a real race in it: two leaders reporting within
moments of each other can each read a stale "no report yet" from their own
client's cache and each write only their own field, with neither write seeing
the other's — leaving both reports stored but `result` never set, because
nothing ever ran the "do these agree" check against the state that actually
landed. A transaction closes that race the same way every other contested
single-document write in this codebase closes it. If you land on the
transaction shape — and the codebase's own precedent suggests you should —
say so in the commit message and cite `GameService.mutateRoster` as the
pattern, the same way Phase 3.5's prompt asked for the claim transaction.

**Re-reporting after a dispute is not a separate feature — it's the same
write path, called again.** §3 point 3: *"Either leader may clear their own
report and re-enter it, which is how a dispute gets resolved."* If your rule
only permits the transition from *no report* to *report*, a `disputed` game
can never be re-reported and the design's own stated recovery path is
unreachable. The rule has to permit overwriting an existing report field with
a new value — including from `disputed` back toward `confirmed` — not just
setting it once.

## The rule itself

Three things the rule has to hold, all statable from §3 directly:

1. **Each report field is pinned to its own leader.** `homeReport` only ever
   moves on a write from `homeLeaderId`; `awayReport` only from
   `awayLeaderId`. Neither leader may write the other's field, in either
   direction — this is the same "a client may only ever write its own lane"
   principle `games` and `squads` already build on, applied to a report
   instead of a roster slot.
2. **`result` may only be set to a value both reports agree on.** The rules
   check `incoming().result == incoming().homeReport &&
   incoming().result == incoming().awayReport` (or the equivalent once you've
   settled the transaction shape above) — never trust a client's claim that
   they agree without checking the two stored values say so.
3. **`status` is derived from the reports, not chosen.** `confirmed` only
   when both reports exist and match; `disputed` when both exist and don't;
   otherwise the game stays `scheduled` until reported once. This is the same
   "status is derived, never chosen" principle `games`' `open`/`full` and
   `matchTickets`' pool-visible states already build on — see
   `database/DATABASE_SCHEMA.md`'s `## Invariants` section, which names this
   pattern explicitly and should gain one more line for this collection.

## The record and the form guide

**Nothing here changes `SeasonGame.record(for:in:)` or
`SeasonGame.form(for:in:limit:)`.** Both were written in Phase 4, deliberately,
before anything could ever populate them with a `confirmed` game — see that
model file's doc comments for why. Phase 6 is the phase where they start
returning something other than the unplayed default. If you find yourself
wanting to change either function's signature or logic to make Phase 6 work,
stop: that's a sign the derivation was wrong in Phase 4, not that Phase 6
needs new logic, and it's worth reporting rather than quietly patching around.

## Screens 8–9

**Screen 8 — result.** "Who won?" as two large crest buttons — the plan's own
words — then a waiting / confirmed / *"results don't match"* state depending
on where the game's two reports stand. Styling is not freehand: the same
`Color.hoopr*` roles, `.hooprFont(_:weight:)`, and `.cardChrome()` every other
Seasons screen uses; no literal colours.

Reachable from game day once `now` is past `scheduledTime` — §4's T+90
notification already points here, which is why Phase 5 shipped that copy
before this screen existed. Wire the tap-through the same way
`MatchmakingCard`'s match-found state wires into game day: a `Route` case
carrying the `SeasonGame` value, not a re-lookup by ID.

**Screen 9 — squad detail's other half.** Full game history and the form
guide (the last five confirmed results as W/L pills — plan §5's "cheapest
possible way to make a record feel like a season rather than two integers").
Both read off `SeasonGameService`, which already exposes `record(for:)` and
`form(for:limit:)` — this is a rendering task, not a new join.

## Done when

A game reported by both leaders in agreement shows `confirmed` and moves both
squads' records and form guides; a game reported in disagreement shows
`disputed` and moves neither. Verified with two distinct authenticated
contexts in the rules emulator (not one context calling twice — that proves
nothing about the pinned-to-leader rule). The Swift suite still passes, and
the two-person live confirm/dispute flow is reported honestly as unverified
until the deferred manual testing pass happens.

---

# Phase 7 — Polish and fold-in

**No new collections, no new screens.** Phase 7 ends when the feature reads as
finished rather than freshly built, and the plan document that designed it is
retired into the docs that describe what actually shipped.

## Build

- **VoiceOver labels on the crest and the form guide.** `SquadCrest` currently
  renders as a decorative SF Symbol with no accessibility label of its own —
  check it, and add one (the squad's name is almost certainly the right
  label; a bare icon name is not). The form guide's W/L pills need the same
  treatment — a screen reader encountering five circles with no label reads
  as nothing.
- **Dynamic Type at `.accessibility3`, checked across every Seasons screen**
  — not just the tab bar, which is already covered by
  `TabBarLabelTests.swift`. `QueueSheet`'s time chips, `MatchmakingCard`'s
  match-found card, and `GameDayView`'s roster rows are the likely places
  something clips; render each at the largest content size before deciding
  nothing needs to change.
- **Empty states**, wherever one still renders as a blank list rather than a
  sentence explaining why it's blank. Screen 9's history section is the most
  likely candidate — Phase 6 fills it with real content when there's a
  confirmed game to show, but "your squad hasn't confirmed a result yet"
  needs its own sentence for the common case where there isn't one yet.
- Fold `context/plans/SEASONS.md` into `context/ARCHITECTURE.md`,
  `context/DATA_MODEL.md`, `context/database/DATABASE_SCHEMA.md`,
  `context/UI_SHELL.md`, and `context/BUILD_AND_CONFIG.md` — in that order of
  likely effort, cheapest first:
  - `DATABASE_SCHEMA.md` is **already substantially done** (see "Where the
    last session stopped, and why" above). Read it before writing anything;
    the remaining gap is Phase 6's reporting rule getting the same treatment
    the claim and arrival rules already got, not a from-scratch pass.
  - `ARCHITECTURE.md`, `DATA_MODEL.md`, `UI_SHELL.md`, and
    `BUILD_AND_CONFIG.md` are the four `check_context_drift.py` actually
    reports stale as of this prompt. Read each one's existing structure
    before adding to it — these are living documents with their own
    conventions, not blank pages.
- Strike the shipped phases from `SEASONS.md` itself, per the note at the top
  of that file: *"When a phase below ships, fold what's true into the
  dictionary entries it names and strike it from here."* Leave §7
  ("Explicitly out of reach for v1") and §8 ("Risks") — those describe
  permanent boundaries and known risks, not phase progress, and striking them
  would delete information nothing else carries forward.
- Update `context/plans/BACKLOG.md` A2 (around line 150) per `SEASONS.md`
  §1.3's own instruction: A2 proposes unifying `queueEntries`/`checkins` into
  one `presence/{uid}` collection, and `SEASONS.md` §1.3 already settled that
  `matchTickets` is deliberately **not** part of that unification, with the
  reasoning written into `DATABASE_SCHEMA.md`'s `matchTickets` section this
  session. A2's own text doesn't know that yet — it should reference the
  resolution rather than leave a future reader to wonder whether `matchTickets`
  was simply forgotten.
- Run `python3 tools/check_context_drift.py` after every doc you touch, and
  again at the end. A doc it still reports stale after you believe you've
  folded Seasons into it means the fold-in missed something, not that the
  tool is wrong.

## What's explicitly not this phase's job

**Do not build server-side matchmaking, real push notifications, tamper-proof
results, skill rating, cross-region matchmaking, additional formats,
standings, or roster management beyond what's built.** `SEASONS.md` §7 names
every one of these as out of reach for v1, and Phase 7 is polish on what
shipped, not a chance to reopen decided scope. If polish work makes one of
these feel newly urgent, name it as a follow-up in `GAPS.md` — the same
treatment Phase 5's push-notification limitation already got — rather than
building it here.

## Done when

Every Seasons screen reads correctly at `.accessibility3` with VoiceOver on,
every empty state explains itself, `check_context_drift.py` reports zero
stale docs in Seasons' scope, `SEASONS.md` has its shipped phases struck, and
`BACKLOG.md` A2 references the `presence` decision instead of predating it.

---

## Error handling

Everything in both prior prompts' tables still applies. New paths:

| Situation | Required response |
|---|---|
| A report write from someone who isn't either leader | Refused server-side. Say the state may have changed or the caller isn't authorized; **never blame deployment on a write**. |
| Both reports present and they disagree | Not an error. `status = disputed` is a legitimate, designed outcome — render the "results don't match" state, not a failure banner. |
| A leader re-reports after a dispute | Not an error, and not blocked. The rules must permit overwriting an existing report field — this is the design's own stated recovery path, not an edge case to guard against. |
| A report write races another leader's simultaneous report | If you chose the transaction shape, Firestore's retry handles it the same way every other contested single-document write in this codebase is already handled — see the claim transaction. If you chose the plain-write shape and hit this, that is the sign to switch shapes, not to add a second retry loop. |
| `SeasonGame.record`/`.form` return the unplayed default after a game you believe is confirmed | Check the write actually set `status = confirmed` **and** `result` — a report write that sets one without the other is a rules bug, not a client bug, and belongs in the rules file, not in the derivation functions. |
| A VoiceOver label is missing on an existing view | Not a crash, not a test failure by default — worth its own accessibility test if one doesn't already exist for that view, following `ThemeContrastTests`' pattern of pinning a design property so a regression fails loudly. |
| `check_context_drift.py` still reports a doc stale after folding Seasons in | The fold-in missed something in that doc's actual `Scope:` line, or the doc's `Verified:` stamp wasn't updated to the commit that finished the fold. Fix the doc, not the tool. |

---

## Wait vs. stop

**Wait for input — ask, then hold — if:**

- The reporting rule's transaction-vs-plain-write choice turns out to need a
  cross-document read (it shouldn't — everything §3 describes lives on one
  `seasonGames` document). If it does, that's a sign the design has drifted
  from what's built, and it's worth a question before proceeding.
- Folding `SEASONS.md` into `ARCHITECTURE.md` or `UI_SHELL.md` would mean
  restructuring either document's existing sections rather than adding to
  them. Quote the conflict; don't restructure a document you didn't author
  without asking.

**Stop and report — do not retry — if:**

- The Swift suite fails in a way suggesting it was already broken. The
  baseline is **401 passing, 0 failing** as of `0de2f48`. Report before
  changing anything.
- The rules emulator suite fails in a way suggesting it was already broken.
  The baseline is **66 passing, 0 failing**.
- A rules change would weaken an existing `games`, `users`, `friendships`,
  `squads`, `squadInvites`, `matchTickets`, or the cancel/arrival paths on
  `seasonGames`. Nothing in Phases 6–7 needs that.
- You find yourself needing a Cloud Function for reporting, disputes, or
  anything else. `SEASONS.md` §0 and §7 both exist precisely because there
  isn't one.
- `project.pbxproj` seems to need editing. It does not.

---

## Chain-of-thought

**Before writing the reporting rule, state:**

1. Which write shape you chose — plain update or transaction — and why,
   citing the specific race the other shape leaves open
2. What stops one leader from writing the *other* leader's report field, and
   what stops a client from setting `result` to a value neither report
   actually contains
3. How re-reporting after `disputed` is still reachable under the rule you
   wrote

**Before touching any of the five documentation files in Phase 7, state:**

1. What `check_context_drift.py` currently reports for that specific file,
   quoted
2. Which of that file's existing sections Seasons content belongs under,
   given the file's own structure — not a new top-level section bolted on
   at the end
3. What the file's `Verified:` stamp should become once you're done, and at
   which commit

Then write the code.

---

## Model recommendation

| Phase | Model | Why |
|---|---|---|
| 6 | **Opus** | A new contested-write shape on an existing document, a rules block that has to derive `status` correctly in four different states, and a race condition to reason through before writing a line of Swift. This is the same class of problem Phase 3.5's claim transaction and Phase 4's create rule were. |
| 7 | **Sonnet** | Mechanical, well-scoped work against established patterns — accessibility labels, Dynamic Type checks, and folding a finished design into docs that already know most of the shape. Escalate to Opus only if a documentation fold-in surfaces a design question `SEASONS.md` didn't actually settle. |

---

## Test cases — these verify the prompt, not just the code

**Phase 6**
1. Two different authenticated leaders each report a different squad ID as
   the winner; the rules refuse both — one for writing the other's field,
   both for what happens if `result` were derived from a disagreement — and
   the document remains `scheduled` until both fields are present.
2. Two different authenticated leaders each report the **same** squad ID as
   the winner, in either order; the second write sets `result`, `status =
   confirmed`, and `confirmedAt`, and `SeasonGame.record(for:in:)` for that
   squad now includes the win.
3. A `disputed` game has one leader clear and re-report their own field to
   now agree with the other's standing report; the rules permit the write
   and the game moves to `confirmed`.

**Phase 7**
1. `SquadCrest` and the form guide's W/L pills both expose a non-empty
   VoiceOver label; a snapshot or accessibility-audit test fails if either
   regresses to unlabeled.
2. Every Seasons screen renders without a truncated or clipped element at
   `.accessibility3` — checked the same way `TabBarLabelTests` already checks
   the tab bar, extended to the screens that test doesn't cover.
3. `python3 tools/check_context_drift.py` reports zero stale documents whose
   `Scope:` includes any Seasons-touched path, and `SEASONS.md`'s shipped
   phases are struck with their content findable in the doc each was folded
   into.
