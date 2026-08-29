# Implement — Seasons Phase 7 (polish and fold-in)

Make the feature read as finished rather than freshly built, then retire the
plan that designed it into the docs that describe what shipped — Phase 7 of
`context/plans/SEASONS.md`.

**This supersedes the Phase 7 section of
`context/prompts/implement-seasons-phases-6-7.md`.** That section was written
before Phase 6 shipped and is now wrong in three specific places, each called
out below. Where the two disagree, **this document wins** — it was written
against the tree as it actually stands.

**Read `context/plans/SEASONS.md` in full before writing anything**, especially
§5 (interface and the two things that will bite), §6's Phase 7, §7 (explicitly
out of reach), and §8 (risks). It is the authoritative spec. This prompt tells
you *how to execute* the fold-in correctly; it does not restate the design.
Where anything here seems to conflict with the plan, **the plan wins — but stop
and flag the conflict**, because a conflict means one of the two documents is
stale.

**Also read the two prior prompts** —
`context/prompts/implement-seasons-phases-1-3.md` and
`context/prompts/implement-seasons-phases-4-5.md`. Their invariants still hold
and their error-handling tables are still the house answer.

> **This is one session, and it is the last one in the plan.** Unlike Phases 1–6
> it ships no new behaviour, so there is nothing to sequence — but there is a
> hard ordering *inside* it: **accessibility first, docs second.** The docs
> describe the code, so folding in before the code stops moving means writing a
> description of a tree that changes underneath you, and then restamping it at a
> commit that no longer matches.

---

## Where Phase 6 stopped, and the three things that changes about this phase

Phase 6 shipped in `9ff5968`, stamped in `815f06e`. Baselines to beat:

| Suite | Command | Baseline |
|---|---|---|
| Swift | `xcodebuild test -project hoopr.xcodeproj -scheme hoopr -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:hooprTests` | **420 passing, 0 failing, 26 suites** |
| Rules | `npm run test:rules` | **92 passing, 0 failing** |

### Correction 1 — `DATABASE_SCHEMA.md` is done. It is four files, not five.

The older prompt lists five documentation files and calls `DATABASE_SCHEMA.md`
"substantially done." It is now **finished and current**: Phase 6 added the
reporting section, the derived-status invariant, the second index, and the
report row in the Access list, then stamped it at `9ff5968`.
`check_context_drift.py` reports it **current**, and the tool's own instruction
applies — *don't restamp an entry it calls current.*

**Do not re-fold `DATABASE_SCHEMA.md`.** If you believe it has a gap, say what
the gap is before touching it; an entry the drift tool calls current is
evidence, not an invitation.

The four that are genuinely stale, all verified at `37aaf7a`:

- `context/ARCHITECTURE.md`
- `context/DATA_MODEL.md`
- `context/UI_SHELL.md`
- `context/BUILD_AND_CONFIG.md`

### Correction 2 — `hoopr/Views/Seasons/` is owned by nothing, and that is the finding

`check_context_drift.py` prints an **UNOWNED CHANGES** section, and every file
in `hoopr/Views/Seasons/` is in it. `UI_SHELL.md`'s `Scope:` enumerates specific
view paths (`hoopr/Views/Profile/`, `hoopr/Views/Games/`, `hoopr/Views/Friends/`,
a list of `Components/`) and **does not include `hoopr/Views/Seasons/`**.

Two consequences the older prompt could not have known:

1. **The drift tool will never report `UI_SHELL.md` stale for a Seasons view
   change**, so its own done-when — "`check_context_drift.py` reports zero stale
   documents whose `Scope:` includes any Seasons-touched path" — is vacuously
   true for the entire Seasons view tree and proves nothing.
2. **`INDEX.md`'s own claim is currently false.** It says scopes "together cover
   every source path in the repo." They don't.

So the fold-in is not only prose. **`UI_SHELL.md`'s `Scope:` line must gain
`hoopr/Views/Seasons/`**, and that is what makes the fold-in checkable
afterwards. Same question, separately, for `package.json` / `package-lock.json`,
which are also unowned and are repo tooling — `BUILD_AND_CONFIG.md` is the
natural owner, and its `Scope:` already carries `tools/check_context_drift.py`.
(`firestore-tests/` is already owned, by `DATABASE_SCHEMA.md`.)

**Not yours to adopt.** The unowned list also contains `README.md`,
`hoopr/Views/Components/StatsCard.swift`, and
`plans/STATS_CARD_IMPLEMENTATION_PLAN.md`. Those belong to an unrelated home-page
change (`85b2eb7`, `9307d16`), not to Seasons. Leave them unowned and say you
did; widening a scope to swallow somebody else's untracked work is how an entry
starts lying about what it covers.

### Correction 3 — `SquadCrest` already made a deliberate accessibility decision

The older prompt says `SquadCrest` "renders as a decorative SF Symbol with no
accessibility label of its own — check it, and add one." **Check it first: it is
`.accessibilityHidden(true)`, on purpose, with the reason written next to it** —
every crest is rendered beside the squad's name, so announcing it separately
would read the squad twice.

Adding an `accessibilityLabel` to a hidden element does nothing at all. So "add
a label to `SquadCrest`" is the wrong instruction, and following it produces
code that looks like a fix and speaks like silence. The real work is a **call
site audit** — see Part A.

---

## Invariants — carried forward, still load-bearing

**No new behaviour.** Phase 7 ships polish and documentation. A change that adds
a screen, a collection, a rules path, or a service method is out of scope; see
"Wait vs. stop."

**Xcode target membership is automatic.** `PBXFileSystemSynchronizedRootGroup`
picks up any `.swift` file under `hoopr/` or `hooprTests/`. **Do not hand-edit
`project.pbxproj`.**

**Every test targets a `nonisolated static` pure function — except the two
existing UIKit-measuring exceptions.** `TabBarLabelTests` and
`ThemeContrastTests` render and measure real UIKit objects on `@MainActor`, and
they are the pattern any new Dynamic Type or contrast test copies. Do not
introduce a third style.

**Styling is not freehand.** `Color.hoopr*` roles, `.hooprFont(_:weight:)`,
`.cardChrome()`. There are no literal colours in `Views/`.

**Docs are stamped at the commit whose content they describe**, and the repo's
convention is a **separate follow-up commit** that does only that — see
`4808d3c`, `0de2f48`, `815f06e`. Never restamp an entry the drift tool calls
current.

---

# Part A — Accessibility and polish

Do this first, and commit it before touching a single doc.

## A1 — The crest call-site audit

`SquadCrest` itself is correct and should stay hidden. Twelve call sites use it;
audit each and fix the ones where the crest is **not** adjacent to the name it
stands for, because that is the only case where hiding it loses information.

Known before you start:

- **`MatchmakingCard.swift:168` and `:180` are the real problem, and one of them
  is worse than an accessibility bug.** The match-found row renders my crest,
  "vs", the opponent's crest, then the opponent's name. My own squad's name
  appears nowhere in that row, so a screen reader gets "vs, {opponent}". And
  line 180 is a **hardcoded placeholder** — `shield.fill` / `blue` — with a
  comment saying a real fetch "isn't worth it before Phase 7's polish pass."
  This is that pass, and a sighted user is currently shown a crest that is not
  the opponent's.
  **`ResultViewModel` already solves exactly this**: it resolves both squads via
  `squadService.squad(id:)` then `fetchSquad(id:)`, which is the one-off read
  `squads` being world-readable exists to allow. Reuse that shape rather than
  inventing a second one.
- **`CreateSquadSheet.swift:95`** is a live preview of the crest being chosen.
  It has no name beside it, so hidden means a VoiceOver user building a squad
  gets no feedback that the icon and colour pickers changed anything.
- **`SeasonsTab.swift:224`** (hero empty state) and **`:428`** (a redacted
  placeholder for an unresolved invite) are genuinely decorative. Hidden is
  correct. Leave them and say why.

Already labelled and needing no work — confirm rather than redo: `FormGuide` and
`FormPill`, `ResultView`'s two winner buttons and score fields, `GameDayView`'s
arrival marks, `CreateSquadSheet`'s icon/colour/format pickers, `QueueSheet`'s
court chips, `SeasonsTab`'s squad header.

## A2 — Dynamic Type at `.accessibility3`

The tab bar is already pinned by `TabBarLabelTests`, and **the label decision is
settled: "Seasons", not "Squad".** That test measures all four labels at
`.accessibility3` and asserts Seasons is the tightest fit and still has room.
Phase 7's list names the decision; it needs to be *left alone*. If you find
yourself wanting to reopen it, something else drifted.

What is **not** covered is every screen behind the tab. Render each at
`.accessibility3` before deciding nothing needs to change — the likely clippers,
in order:

- `QueueSheet`'s time chips and court multi-select rows
- `MatchmakingCard`'s match-found card, whose crest-vs-crest row is horizontal
  and fixed-width
- `GameDayView`'s roster rows, which carry a trailing arrival mark
- `ResultView`'s two side-by-side crest buttons — new in Phase 6, never measured
- `SquadDetailView`'s history rows, whose badge is a fixed 28pt circle

Follow `TabBarLabelTests`' method: host the view, override the content size
category, measure, and assert the **outcome** (it fits) rather than the
mechanism. That test's doc comment explains why it asserts what it does; read it
before writing a fourth measurement style.

## A3 — Empty states

Every list that can be empty needs a sentence saying why, not a blank.

Phase 6 already did screen 9's history ("No matches yet. Queue up and your
results will collect here.", with a distinct "Loading your matches…" for the
pre-first-snapshot case) and the record card. **Audit the rest** rather than
assuming: the searching state's zero-pool copy, `QueueSheet` with no courts in
range, `SquadDetailView`'s invite picker (already distinguishes "no friends yet"
from "everyone already asked"), and the roster while names are unresolved.

The distinction that matters everywhere: **"nothing here yet" and "this failed
to load" are different sentences.** `hasLoadedGames` / `hasLoadedSquads` exist
precisely so the two can be told apart.

---

# Part B — The fold-in

Only after Part A is committed.

`context/plans/SEASONS.md`'s own header states the contract: *"When a phase below
ships, fold what's true into the dictionary entries it names and strike it from
here."*

**Read each document's existing structure before adding to it.** These are living
documents with their own conventions, not blank pages. Each already has an
`## Invariants` section and a `## See also` section, and Seasons content belongs
*inside* the existing shape, not bolted on as a new top-level section at the end.

Section placement, given each file's actual headers today:

### `ARCHITECTURE.md` — `Scope:` already covers `Services/` and `ViewModels/`

| Existing section | What Seasons adds |
|---|---|
| `## Ownership and injection` | `SquadService` (two collections, and why `squadInvites` has no independent existence), `MatchmakingService`, `SeasonGameService`, `NotificationService`. **And the one deliberate house-rule asterisk:** `MatchmakingViewModel` holds a cross-collection *write sequence*, not just a join — its own doc comment argues the case, and that argument belongs here. |
| `## Vendor boundary` | `UserNotifications` is a **second vendor**, confined to `NotificationService` the way Firebase is confined to `Services/`. |
| `## Shared derivations` | `SeasonGame.reportOutcome` ↔ the rules' `derivedResultHolds()`, joining `Game.status` as a derivation mirrored on both sides of the wire. Also `MatchRules.staleClaim`'s four copies. |
| `## Session-scoped listeners` | The `squadIds array-contains-any` listener, its ten-squad ceiling, and that `observe(squadIds:)` is driven by `SeasonsTab` — not by a `SquadService` subscription, because services here don't depend on each other. |
| `## Invariants` | Whatever of the above is a rule rather than a description. |

### `DATA_MODEL.md` — sections are one per type, in rough dependency order

Add `Squad` / `SquadFormat` / `SquadError`, `SquadInvite`, `MatchTicket`,
`MatchRules` / `MatchCandidate`, `SeasonGame` / `SeasonGameError`, and
`SeasonGameNotifications`, each as its own `## ` section matching the existing
`## \`Game\` and \`GameError\`` shape. The two derivations worth their own prose
are `SeasonGame.record(for:in:)` / `.form(...)` (a record is a query, never a
field) and `SeasonGame.reportOutcome`.

### `UI_SHELL.md` — **and its `Scope:` line**

| Existing section | What Seasons adds |
|---|---|
| `Scope:` (line 3) | **`hoopr/Views/Seasons/`.** See Correction 2. Without this the rest of the fold-in is invisible to the drift tool. |
| `## MainTabView` | The fourth tab, `trophy.fill`, and a pointer to `TabBarLabelTests` for why the label is "Seasons". |
| a new `## Seasons` section, after `## LocalRunsTab` | Screens 1–9 and which are *states* rather than destinations — screens 5 and 6 live inside `MatchmakingCard`, and the plan's §5 screen 2 says so. |
| `## Visual conventions` | `SquadCrest`'s five named sizes and one-view-with-a-size-parameter rule, the eight-colour crest palette and its `hooprOnCrest` pairing, and `FormGuide`. |

### `BUILD_AND_CONFIG.md`

| Existing section | What Seasons adds |
|---|---|
| `Scope:` (line 3) | `package.json` / `package-lock.json`, if you conclude it should own them. |
| `## Dependencies` | `firebase-tools`, `firebase`, `@firebase/rules-unit-testing`, and that `node:test` was chosen deliberately over a second test framework. |
| `## Repo tooling` | `npm run test:rules` and `npm run emulators`, the JDK requirement, and the orphaned `axios` tree `firestore-tests/README.md` explains. |
| `## Firebase CLI surface` | The emulator, and **that a dry-run is not a test** — it compiles the file and evaluates nothing. |
| `## Tests` | The real count (**re-derive it, don't copy this prompt's number**), the 26 suites, and the rules suite as a second, separate suite with its own command. |

---

# Part C — Retiring the plan

## C1 — Strike the shipped phases from `SEASONS.md`

Phases 0 through 7 have all shipped. Strike them per the file's own header note.

**Keep §7 ("Explicitly out of reach for v1") and §8 ("Risks").** Those describe
permanent boundaries and live risks, not phase progress, and striking them would
delete information nothing else carries forward. Keep enough of §0 to preserve
*why there is no server-side matchmaker* if that reasoning has no home in the
dictionary yet — `INDEX.md`'s plans table currently advertises §0 as the answer
to that question.

Update `INDEX.md`'s Plans table row for `SEASONS.md` from "Proposed" to shipped,
matching how `plans/FRIENDS.md`'s row records a partly-shipped plan.

## C2 — `BACKLOG.md` A2

A2 begins at **line 150**, and its indented "Architectural decision this story
must settle first" block (around lines 175–190) proposes unifying
`queueEntries/{uid}` and `checkins/{uid}` into one `presence/{uid}`.

`SEASONS.md` §1.3 already settled that **`matchTickets` is deliberately not part
of that unification** — its subject is a squad, not a person; its lifecycle is a
two-party negotiation, not a self-declaration; and its ID space is squad IDs.
The reasoning is already written into `DATABASE_SCHEMA.md`'s `matchTickets`
section under "Not part of `presence/{uid}`".

A2's own text doesn't know that. Make it reference the resolution, so a future
reader isn't left wondering whether `matchTickets` was simply forgotten. **A2
itself stays open** — the `queueEntries`/`checkins` unification is still
unsettled and still that story's job.

## C3 — `GAPS.md`

Add anything Part A surfaced and chose not to fix, in the shape the existing
Seasons entry at line 28 already uses (the local-notification ceiling — a named
limitation with its cause and what it would take to lift). If Part A's crest
work leaves `MatchmakingCard` doing one extra read per match card, that is a
cost worth naming rather than hiding.

**One entry is required regardless: the two-account manual pass is still
outstanding.** Phase 6 verified the confirm/dispute/re-report rules against two
distinct authenticated contexts in the emulator and the derivation in the Swift
suite, but **the live two-person flow has never been exercised**, and neither has
`ResultView`'s rendering — screen 8 needs a played match between two squads,
which one client cannot produce. Phase 7 does not close this. Record it plainly
so it isn't mistaken for verified.

---

## Error handling

Everything in the prior prompts' tables still applies. New paths:

| Situation | Required response |
|---|---|
| `check_context_drift.py` still reports a doc stale after you folded Seasons in | The doc's `Verified:` stamp wasn't moved to the commit that finished the fold, **or** its `Scope:` doesn't actually cover the paths you wrote about. Check the `Scope:` line before assuming the stamp. Fix the doc, never the tool. |
| The tool reports a doc **current** that you believe needs Seasons content | Believe the tool and stop. It diffs owned paths against the working tree; "current" means nothing in that scope moved. `DATABASE_SCHEMA.md` is the live example. Say what you think is missing rather than restamping. |
| A Seasons path still appears under **UNOWNED CHANGES** after the fold-in | Expected for `README.md`, `StatsCard.swift`, and `plans/STATS_CARD_IMPLEMENTATION_PLAN.md` — not Seasons, leave them. **Not** expected for anything under `hoopr/Views/Seasons/`; that means the `Scope:` edit in Correction 2 didn't happen. |
| A VoiceOver label is missing on an existing view | Not a crash and not a test failure by default. Worth its own accessibility test, following `ThemeContrastTests`' pattern of pinning a design property so a regression fails loudly. |
| Adding an `accessibilityLabel` doesn't change what VoiceOver speaks | The element is `accessibilityHidden(true)`, or an ancestor combined it away with `.accessibilityElement(children: .combine)`. Labels on hidden elements are silent. Fix the container, not the leaf. |
| A screen clips at `.accessibility3` | Fix the layout — `fixedSize(horizontal:vertical:)`, a wrapping stack, or `maximumSize:` on `hooprFont`. **Never `minimumScaleFactor`**, which is the thing the native tab bar was adopted to stop needing. |
| Fetching the opponent's real crest fails | An opponent's crest is decoration on a match card. Fall back to the neutral placeholder and keep the card, exactly as `fetchRecord(for:)` returns an unplayed record rather than throwing. A failed read of a decoration must never take down the thing it decorates. |
| The Swift or rules suite fails | **Stop and report.** Baselines are 420/0 and 92/0. Phase 7 changes no behaviour, so a failure means something in Part A broke a contract rather than a test needing an update. |
| Polish work makes an out-of-reach item feel newly urgent | Name it as a follow-up in `GAPS.md`. `SEASONS.md` §7 names every one of these as out of reach for v1; Phase 7 is not a chance to reopen decided scope. |

---

## Wait vs. stop

**Wait for input — ask, then hold — if:**

- Folding into `ARCHITECTURE.md` or `UI_SHELL.md` would mean **restructuring**
  either document's existing sections rather than adding to them. Quote the
  conflict; don't restructure a document you didn't author without asking.
- The `Scope:` edits in Correction 2 would make two entries' scopes **overlap**.
  `INDEX.md` states scopes don't overlap, and resolving an overlap means
  deciding which entry owns a path — an ownership decision, not a fold-in.
- Fixing a clip at `.accessibility3` would need a change to `Theme.swift` or
  `Typography.swift`, i.e. a shared role. That has app-wide reach.
- Striking a phase from `SEASONS.md` would delete reasoning that has **no home**
  in any dictionary entry. Quote the orphaned passage rather than dropping it.

**Stop and report — do not retry — if:**

- Either suite fails in a way suggesting it was already broken. Report the
  baseline before changing anything.
- A doc fold-in surfaces a design question `SEASONS.md` didn't actually settle.
  That is a design gap, not a documentation gap, and writing a confident
  sentence over it is the worst available outcome.
- You find yourself needing a Cloud Function, real push, tamper-proof results,
  skill rating, standings, cross-region matchmaking, or a new format.
  `SEASONS.md` §0 and §7 both exist precisely because none of those are in reach.
- `project.pbxproj` seems to need editing. It does not.
- The tab-label decision seems to need revisiting. It is settled and tested.

---

## Chain-of-thought

**Before touching any of the four documentation files, state:**

1. What `check_context_drift.py` reports for that specific file right now,
   **quoted** — including whether its `Scope:` actually covers the paths you are
   about to describe
2. Which of that file's **existing** sections the Seasons content belongs under,
   given the file's own structure — not a new top-level section at the end
3. What the file's `Verified:` stamp should become, and at which commit

**Before changing any accessibility annotation, state:**

1. What VoiceOver speaks for that element today — including whether it is hidden
   or combined into an ancestor
2. What it should speak, and why that is the shortest true sentence
3. Which test would fail if it regressed

Then write the code.

---

## Model recommendation

| Part | Model | Why |
|---|---|---|
| A (accessibility) | **Sonnet** | SwiftUI against an established design system, with the measurement pattern already written in `TabBarLabelTests`. Escalate to Opus if a clip forces a shared `Theme.swift` or `Typography.swift` role. |
| B–C (fold-in) | **Sonnet** | Mechanical work against living documents whose conventions are visible in the files themselves. Escalate to Opus if the fold-in surfaces a design question `SEASONS.md` didn't settle, or if the `Scope:` edits produce an ownership overlap. |

---

## Test cases — these verify the prompt, not just the code

1. **The crest audit is real, not cosmetic.** `MatchmakingCard`'s match-found
   row renders the opponent's *actual* crest rather than the hardcoded
   `shield.fill`/`blue` placeholder, and a screen reader on that row hears both
   squads' names. A test fails if the placeholder returns.
2. **Every Seasons screen renders without a clipped element at
   `.accessibility3`** — checked the way `TabBarLabelTests` already checks the
   tab bar, extended to the five screens that test doesn't cover.
   `ResultView`'s two side-by-side crest buttons are the newest and least
   measured.
3. **The drift tool proves the fold-in landed.** After Part B,
   `python3 tools/check_context_drift.py` reports **zero stale entries**, and
   **no file under `hoopr/Views/Seasons/` appears under UNOWNED CHANGES** —
   which is only true if `UI_SHELL.md`'s `Scope:` was extended, and is the
   assertion the older prompt's version of this test could not make.
4. **`SEASONS.md`'s shipped phases are struck**, §7 and §8 survive intact, and
   every struck passage's content is findable in the entry it was folded into.
5. **`BACKLOG.md` A2 references the `matchTickets` resolution** rather than
   predating it, and A2 itself is still open.

---

## Done when

Every Seasons screen reads correctly at `.accessibility3` with VoiceOver on and
no crest lies about which squad it is; every empty state explains itself;
`check_context_drift.py` reports zero stale entries and no unowned Seasons path;
`SEASONS.md` has its shipped phases struck with §7 and §8 intact; `INDEX.md`'s
plans row reflects reality; `BACKLOG.md` A2 references the `presence` decision;
and `GAPS.md` records the outstanding two-account manual pass plainly enough
that nobody mistakes Seasons for end-to-end verified.

Both suites still green: **420 Swift, 92 rules, 0 failing.**
