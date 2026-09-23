# Design Brief — UI Revamp, Phase 2a

**Status:** **Checkpoint 1 answered 2026-09-22** (§7.5) — 2b in progress, Home first
**Drafted:** 2026-09-21 @ 1a2710d + the uncommitted Phase 1 tree
**Touches (proposed):** `hoopr/Support/Typography.swift`, `hoopr/Support/Theme.swift`,
`hoopr/Views/` (every screen in §5), `hoopr/ViewModels/` (derived properties only —
`HomeViewModel`, `LocalRunsViewModel`), `hooprTests/`

> `context/plans/` is not a dictionary entry and carries no `Scope`/`Verified`
> stamp. This file describes work that **hasn't happened**. It is the design
> `UI_REVAMP_PROMPT.md` § 2a asks for, and the thing §2e judges the code
> against. Measurements it cites are from `UI_REVAMP_AUDIT.md`; the record of
> what shipped goes in `UI_REVAMP_CHANGELOG.md`.

**Checkpoint 1 was answered on 2026-09-22 — see [§7.5](#75--checkpoint-1-answered).**
The four decisions there override the "designed to" column wherever they differ.

---

## 1 — Point of view

**hoopsRN should read like a scoreboard: the number you came for, legible from
across the gym, and nothing competing with it.**

That suits pickup basketball because the sport already solved this problem. A
gym scoreboard carries four facts in numerals a foot tall and puts everything
else — rules, rosters, standings — somewhere you go look. The app's own moments
match it: the ledger's highest-frequency task (F1, "am I playing tonight?") is a
**glance, one-handed, on the way out of the door**, and its most one-handed
moment (F11, arriving at a match) is outdoors in sun. Neither is a reading
task. Both are look-and-know.

The app today does the opposite: on Home, Runs and Seasons the largest type is a
greeting, the word "Runs" and the word "Seasons" — three labels that carry no
information — while the answers sit at 17pt inside boxes (`UI_REVAMP_AUDIT.md`
§8.5). That is the single finding this phase exists to fix.

### The three principles

Each is written so a reviewer can catch a screen breaking it without knowing the
design.

**P1 — The answer is the biggest thing.** Every screen answers one question (the
ledger's *decision it supports*). The fact that answers it is the largest,
strongest element in the first viewport. *Catch it:* point at the largest
element and ask "is that the question or the answer?" A screen whose biggest
element is a greeting, a section label, or the tab's own name fails.

**P2 — Numbers are set as numbers.** Time to tip-off, spots left, distance,
W–L, roster counts and streaks are display-tier numerals with their unit
demoted — not embedded in a 13pt sentence. *Catch it:* find every number on the
screen; if one the decision turns on is smaller than the words around it, the
screen fails.

**P3 — A box has to earn its edges.** Chrome is drawn only where it groups one
tappable unit or separates interactive content from the page. Grouping otherwise
is done with rank, scale and space. *Catch it:* count the drawn rectangles in
the first viewport and name what each one groups. "It's a section" is not a
reason.

**What P1–P3 do not license.** They are not a mandate to delete. §2c's utility
rule outranks all three: a screen that gets quieter by hiding something a user
acts on has failed, not succeeded.

---

## 2 — Identity motifs

Three, each with a job. A motif that carries no information or affordance is
decoration and is cut (§2a).

### M1 — Scoreboard numerals

Tabular, heavy, tight-set numerals for the app's real numbers.

- **Where:** Home's next-run time; Runs' tip-off column and spots-left; the map
  court card's distance; Seasons' and `SquadDetailView`'s W–L; `GameDayView`'s
  countdown; `ResultView`'s outcome and score.
- **The job:** it *is* the information. "2 spots left" as a numeral is a
  decision made at a glance; the same words at 13pt are a sentence to parse.
  This is P2's instrument.
- **Mechanics:** `monospacedDigit()` so a counting number doesn't jitter its
  own layout when it changes (Phase 3 animates these with
  `ContentTransition.numericText`, which requires stable digit widths).

### M2 — The paint

A screen's hero sits in a **full-bleed band** — the ground the answer stands
on — closed by a single hairline baseline, with the list or rows below it. Named
for a court's key: one painted region, one line, everything else is floor.

- **Where:** the top band on Home, Runs, Seasons, `SquadDetailView`,
  `GameDayView`, `ProfileView`, `LoginView`.
- **The job:** it is what **replaces** the card this phase deletes. P3 removes
  the box that used to say "these things belong together"; the band and its
  baseline say it with a layer instead, and cost one hairline rather than four
  edges plus a shadow. It is also the layer §2c's rule wants: content at the
  base, chrome floating over it.
- **Mechanics:** the band is `hooprFill` (light) / `hooprElevatedSurface`
  (dark), the baseline is `hooprSeparatorStrong` — all three defined and
  asserted in Phase 1 and **drawn nowhere yet**. This is the composition that
  wants them. It is full-bleed, so it extends under the status bar and the
  content scrolls beneath it (Phase 4's scroll-edge effect lands here).
- **Not:** a gradient, a glow, a texture, or a court diagram. One region, one
  line.

### M3 — Crest colour as a surface

A squad's own `hooprSquad(colorKey)` fill is the ground of every screen about
that squad.

- **Where:** `SeasonsTab`'s squad home band, `SquadDetailView`,
  `GameDayView`, `ResultView`'s crest buttons (already).
- **The job:** orientation. More than one squad is legal (`gaps/SEASONS.md`) and
  the pushed screens carry a `SeasonGame` value with no visual difference
  between squads today — the colour answers *which squad am I looking at* before
  the name is read. It is the one place in the app where colour is identity
  rather than state.
- **Mechanics:** `hooprOnCrest` is already the asserted pairing. The crest
  colours are saturated, so the band carries the **crest and name only** — never
  body text, and never a control that needs its own contrast ratio. Phase 4's
  `MeshGradient` treatment is built *into* this band, not laid behind the old
  layout.
- **Measured against, and not built as a ground (2026-09-22).** The band needs
  secondary text, the profile button and its baseline, and no crest tint strong
  enough to read as the squad's colour keeps those at AA: at 14% the secondary
  text is 4.26:1 on gold in dark mode, and the baseline falls under 3:1 on red
  and gold even at 10%. The squad's colour is carried by the crest instead —
  large and full-strength in the band. Phase 4's gradient will meet the same
  arithmetic.

### Not a motif: the heat ramp

`hooprHeat(tier:)` / `hooprOnHeat(tier:)` is a **colour rule**, not an identity
device: one definition of "how busy is this court", used identically on map
pins, Home's hot list and the map sheet's rows. Phase 1 built it and paired it
with its own foreground. This phase extends it to the places that currently
render busyness as grey text, and nowhere else. Listed here so it isn't mistaken
for a fourth motif and spent on decoration.

---

## 3 — Type roles

Presets over `.hooprFont` in `Support/Typography.swift`. **Constraint 2 holds** —
each role is a `hooprFont` call with a size and weight, so there is exactly one
scaling curve in the app and `HooprFontMetrics` stays the only arithmetic.

Roles are added as `View` extensions beside `hooprFont`, not as a parallel
system: `.hooprType(.numeral)` resolves to `.hooprFont(44, weight: .bold)` plus
`monospacedDigit()`. A call site that needs a size the table doesn't have keeps
using `.hooprFont` directly — the roles are a vocabulary, not a lock.

| Role | Size / weight | Metrics style | At `.accessibility3` | ×    | Cap or reflow |
|---|---|---|---:|---:|---|
| `numeral` | 44 bold, `monospacedDigit` | `.largeTitle` | **65.3pt** | 1.49 | **reflows** — measured, see below |
| `display` | 40 bold | `.largeTitle` | **59.7pt** | 1.49 | **reflows**, wraps to 2 lines |
| `title` | 28 bold | `.title1` | 47.0pt | 1.68 | reflows |
| `headline` | 20 semibold | `.title3` | 40.7pt | 2.03 | reflows |
| `subhead` | 17 semibold | `.body` | 37.0pt | 2.18 | reflows |
| `body` | 15 regular | `.subheadline` | 32.3pt | 2.16 | reflows |
| `caption` | 13 regular | `.footnote` | 29.0pt | 2.23 | reflows |
| `label` | 12 bold, caps, kerning 0.6 | `.caption1` | 29.3pt → **16** | 2.44 | `maximumSize: 16` |
| `badge` | 11 bold, caps | `.caption2` | 29.7pt → **14** | 2.70 | `maximumSize: 14` |

Scaled sizes are **measured**, not estimated: `UIFontMetrics(forTextStyle:)
.scaledValue(for:compatibleWith:)` at `accessibilityExtraLarge` on the iOS 26.5
runtime, through the same `metricsStyle(for:)` ladder `HooprFontMetrics` uses.

### The finding that shapes every composition below

**Dynamic Type compresses this hierarchy to almost nothing.** The display tier
scales by ×1.49 and the caption tier by ×2.23 — the *smallest* roles grow most.
So the ratio between the hero and the body text collapses:

| | `numeral` | `caption` | ratio |
|---|---:|---:|---:|
| default | 44pt | 13pt | **3.4×** |
| `.accessibility3` | 65.3pt | 29.0pt | **2.3×** |

A design whose hierarchy is carried by **size alone loses a third of it** at the
size constraint 6 names — and the two capped caps roles (16 and 14) end up
*smaller* than body text there, which is correct but means a label can no longer
be told from content by size at all.

This is the argument for M2. The band, the baseline and the layer ordering carry
hierarchy that does not scale away: at `.accessibility3` the hero is still the
hero because of **where it is**, not because it is big. Any screen below that
leans only on point size is wrong, and the `.accessibility3` screenshots in §2e
are where that shows up.

**The display tier reflows and is measured, not capped.** §2c forbids a cap
below legibility, so `numeral` and `display` carry none. Instead each hero that
uses them declares its frame and its content's worst case in **one metrics
type**, tested at `.accessibility3` — exactly the `ResultPillMetrics` /
`SeasonsAccessibilityTests` pattern that already exists (`UI_REVAMP_AUDIT.md`
§8.6). The first three to write:

- `HeroNumeralMetrics` — the widest string each numeral hero can hold
  ("10 / 10", "Tip-off in 12h 34m", "—") against the page width minus
  `2 × Spacing.pageMargin` = **362pt on iPhone 17** (402 × 874pt, measured from
  the Phase 0 captures at 1206 × 2622 @3×), at **65.3pt**. A long
  countdown will not fit on one line there and must wrap by design, not by
  luck — which is exactly what this type is for asserting.
- `RunRowMetrics` — the Runs row's leading time column against a 2-line court
  name, which is what `GameCard` fails today (`gaps/ACCESSIBILITY.md`).
- `StatsLineMetrics` — replaces the three fixed columns that break mid-word
  (`UI_REVAMP_AUDIT.md` §7.4 defect 1).

**Two existing wrongs this table closes for free.** The uppercase section label
has six spellings at two sizes and two weights (`UI_REVAMP_AUDIT.md` §2.4) —
`label` is the one. And the app's deepest `minimumScaleFactor` floors (Home's
greeting at 0.65, the pane selector at 0.8) sit on elements this phase removes
or reflows, so `UI_SHELL.md`'s "never `minimumScaleFactor`" invariant gets
closer to true as a side effect rather than as a task.

### New colour roles this brief needs

Tokens from Phase 1 are the floor, not the ceiling (§2a). Two roles are missing
for the compositions below, and both go into `Theme.swift` **in this phase**
with a `ThemeContrastTests` assertion for every pairing:

- **`hooprOnFill`** — the text colour asserted against `hooprFill` specifically,
  which M2's band makes a *text ground* for the first time. Today `hooprFill` is
  only ever a control ground and no pairing is asserted on it at display weight.
- **`hooprBaseline`** — M2's hairline. May resolve to `hooprSeparatorStrong`; it
  gets its own name because the band's baseline and a list's row divider are
  different jobs and should be re-tunable apart.

No other new roles are anticipated. `hooprElevatedSurface`, `hooprHoverFill` and
`hooprSeparatorStrong` already exist unused and are what M2 spends.

---

## 4 — Layout archetypes

Five. Each screen in §5 names exactly one.

**A1 · Answer-first.** A full-bleed hero band (M2) carrying one fact at display
or numeral scale, closed by the baseline, over supporting content that may
scroll under it. One primary action, inside or immediately below the band.
→ **Home**, `GameDayView`, `ResultView`, the map's court card.

**A2 · Board.** A summary strip (a count, a range, a rank) over a single
ordered list of rows — no per-section boxes, no disclosure. Ordering *is* the
grouping.
→ **Runs**, `ProfileView`, the Friends pane, `InboxSheet`, `SquadDetailView`'s
history.

**A3 · Full-bleed content + detent sheet.** Content is the base layer, edge to
edge; every control floats over it on glass; the list lives in a sheet with
detents.
→ **Map** — and only the map. This is the app's one already-correct composition
(`UI_REVAMP_AUDIT.md` §6.3) and the **keep** candidate under §2e (assumption
A4).

**A4 · Crest-grounded.** A1's band, grounded in M3's squad colour, with a
*conditional hero*: the thing that needs acting on outranks the thing that is
merely true.
→ **Seasons**, `SquadDetailView`.

**A5 · Single focused task.** One question, one control, centred; no list, no
chrome, nothing else on screen.
→ `LoginView`, `PlayerProfileSheet`, and every sheet (`CreateGameSheet`,
`QueueSheet`, `CreateSquadSheet`, the profile edit sheets).

**The four tabs use four different archetypes** — Home A1, Runs A2, Map A3,
Seasons A4 — against §2e's floor of three. That is the answer to §8.5: the
sameness goes away structurally, not stylistically.

---

## 5 — Per-screen entries

Each entry carries what §2e's structural test compares: the question, the hero,
the primary action's placement, what is **removed or demoted**, before- and
after-skeletons, the four composed states, and what gets harder. Before-skeletons
are quoted from `UI_REVAMP_AUDIT.md` §6; container counts are its measurements.

A note on the counts: *panels* are bordered/filled/shadowed rectangles that group
content; *shapes* are panels plus every filled or bordered control
(`UI_REVAMP_AUDIT.md` §1). Targets below are stated as both.

---

### 5.1 Home — `Views/Tabs/HomeTab.swift` · archetype A1

**Question (ledger F1):** *Am I signed up for something tonight, and where?*
**Facts the decision needs:** which court · what time · am I in, hosting, or on
the waitlist.

**Hero:** the run itself. The court name at `display`, the tip-off time as a
`numeral`, your standing on it as a badge — in M2's band, which is also the tap
target into Runs.

**Primary action:** the band. Today Home has no primary action at all; the only
filled button on the screen is inside the *empty* state. After, the band is one
button (→ Runs), and where there is no run the band carries a filled action
instead.

**Removed or demoted:**

| Element | Before | After | Why |
|---|---|---|---|
| The greeting | 28pt, largest type on screen | **removed** | P1. It carries no information — the user knows their own name — and it is the element §2c's "maps to no decision or task" rule points at. **This is assumption A2.** It also removes the app's deepest `minimumScaleFactor` (0.65). |
| "Your Stats" card | a card, 3 columns, 2 dividers, above the answer | one quiet `caption` line, below the answer | The data is a **self-reported counter the owner writes** that under-counts by construction (ledger F14). §2d makes giving it the weight of a confirmed result an automatic fail — so it is drawn at the weight of what it is. Fixes the mid-word break at `.accessibility3` by construction (§7.4 defect 1). |
| Four `label` section headers | "YOUR STATS", "NEXT RUN", "HOT RIGHT NOW" + banner | **one** ("TONIGHT NEARBY", over the hot list) | P3/P1. The hero needs no label to say what it is. |
| Five `cardChrome()` call sites | 5 | **0** | P3. The band and the baseline group; the hot courts become rows. |
| Friend-request banner | a card at the bottom, below the fold | a row in the hot list's place when it exists, and the `ProfileButton` dot (unchanged) | Ledger F8 — it "must not be missable", and a card below the fold already fails that. **The `hooprRed` indicator invariant is unchanged: one per surface.** |

**Before-skeleton** (`UI_REVAMP_AUDIT.md` §6.1) — *3 panels / 4 shapes*:

```
ScrollView → VStack(spacing: 24)
├── header        28pt greeting · Spacer · ProfileButton      ← hero, carries nothing
├── [hasStats] "YOUR STATS"  → StatsCard                      card
├── "NEXT RUN"   → nextRunCard | noRunCard                    card   ← the actual answer
├── "HOT RIGHT NOW" → hotCourtsCard                           card
└── [requests] friendRequestBanner                            card
```

**After-skeleton** — target *0 panels / 2 shapes*:

```
ScrollView
├── heroBand                     M2, full-bleed, ignoresSafeArea(.top)   ← the answer
│   ├── ProfileButton            trailing, floating over the band
│   ├── "TONIGHT" / "TOMORROW"   label
│   ├── court name               display 40, 2 lines, reflows
│   ├── tip-off time             numeral 44, monospacedDigit
│   ├── [badge] HOSTING · WAITLIST · IN                       one pill
│   └── distance · spots left    caption + numeral inline
│   ── baseline ──
├── "TONIGHT NEARBY"  label → hot court rows (heat dot · name · count numeral)
├── [requests > 0] request row   name · Accept                       ← promoted above the fold
└── stats line                   caption, one line, last
```

**Composed states** — §2c: each is laid out, not a grey sentence.

- **Loading.** `GameService.hasLoadedGames` exists on the service but
  `HomeViewModel` does not subscribe to it, so **Home cannot currently tell
  "no run" from "not loaded yet"** and renders the empty state during the first
  frames. Fix: a `hasLoaded` derived property on `HomeViewModel` (presentation
  only, no new read). The band renders its own frame with the label and a
  placeholder rhythm at the hero's real metrics — so nothing moves when the
  answer arrives.
- **Empty (loaded, no run).** The band's display line is *"Nothing on tonight"*
  and the numeral position is taken by the busiest court's count, with **"Find a
  court"** filled beneath it. The hot list is the answer to "so what do I do".
- **First run (no stats, no run, no friends).** As empty, minus the stats line;
  the hot list keeps its place because a new account in a covered city still has
  courts.
- **Error.** **`HomeViewModel` has no `errorMessage` and Home has no error
  state today** — a listener failure renders as an empty screen. `ErrorBanner`
  goes directly under the baseline, and the band holds its last-known answer
  rather than collapsing. This is new surface area and is listed in §6 as such.

**What gets harder:** nothing. Every element keeps its tap cost (all are 0-tap
reads); the friend-request banner and the hot list both move *up*. Stats stay on
Home rather than moving to Profile precisely so nothing goes from 0 taps to 3.

**Axes changed: 5 of 5** — hero, container primitive, section order, primary
action, disclosure.

---

### 5.2 Runs — `Views/Tabs/LocalRunsTab.swift`, `Views/Games/GameCard.swift` · archetype A2

**Question (ledger F2):** *What can I get into tonight?* — with F4 (*leave,
cancel, close out*) on the same surface.
**Facts the decision needs:** how far · what time · is there room · do I know
anyone on it.

**Hero:** the board's summary strip — **how many runs are on near you tonight**,
as a `numeral`, with your own commitment count and the radius beside it. It is
the only element on Runs that answers the tab's question before any scrolling.

**Primary action:** `Join`, on the first row — inside the first viewport.
Today the first primary button is roughly **240pt down the page**.

**Removed or demoted:**

| Element | Before | After | Why |
|---|---|---|---|
| The 28pt "Runs" title | largest type on screen | **removed** | P1 — it restates the tab label. |
| Two collapsible section headers | 18pt title + count capsule + rotating chevron, ×2 | **removed**; the counts move into the hero numeral | P3. **This is assumption A3** and it overturns a `UI_SHELL.md` rationale — see §7. |
| The full-bleed 1pt section rule | 1 | removed | The timeline's order does the separating. |
| The capacity bar | a 5pt track + fill on every card | **removed** | It and `rosterText` answer the same question twice. P2 keeps the one the decision turns on — **spots left**, as a numeral. **This is assumption A6.** |
| `GameCard`'s `cardChrome()` | 1 per run | **kept** | P3's own test: a run *is* one tappable unit carrying its own controls. The card earns its edges; its **interior** is what changes. |

**Before-skeleton** (`UI_REVAMP_AUDIT.md` §6.2) — *0 panels / 2 shapes empty;
~2 panels / 7 shapes populated (never captured — see A9)*:

```
ScrollView → LazyVStack(spacing: 0)
├── header      28pt "Runs" · ProfileButton                   ← hero, carries nothing
├── [error] ErrorBanner
├── section "Queued Games"   header(title · count · chevron) → GameCards
├── Rectangle 1pt rule
└── section "Public Games"   identical shape
```

**After-skeleton** — target *N panels (one per run) / N+2 shapes*:

```
ScrollView
├── heroBand                   M2, full-bleed                        ← the board
│   ├── ProfileButton          trailing, floating
│   ├── "TONIGHT" label
│   ├── <N> runs near you      numeral 44
│   └── you're in <M> · within <R> miles       caption
│   ── baseline ──
├── [error] ErrorBanner
└── timeline — one list, ordered by tip-off
    └── GameCard (redesigned)
        ├── leading rail       filled when it's yours — replaces the section split
        ├── time column        numeral, tabular, the row's rank
        ├── court name         subhead, 2 lines
        ├── spots left         numeral + "left"          ← replaces the capacity bar
        ├── distance · friends here · [lock]  caption row
        ├── [badge]            HOSTING · WAITLIST · FULL
        ├── [waitlist] "this list doesn't move up yet"    ← see below
        ├── action             full width
        └── [canComplete] secondary
```

**The waitlist line is the one place this redesign adds information.** A full
run's waitlist **never promotes** — when a player leaves, the seat is not handed
on (`gaps/GAMES.md`), and nothing on the card says so today. §2d forbids drawing
a feature as working that a gap file says isn't; leaving it silent is exactly
that. **This is assumption A7** and it needs the user's answer, because the
honest line is also a discouraging one.

**Composed states:**

- **Loading.** `LocalRunsViewModel` does not publish `hasLoadedGames` either
  (the service has it; `FindAMatchViewModel` uses it). Same fix, same
  constraints: a derived property, no new read. Until it exists, "no runs
  tonight" is shown to a user whose listener simply hasn't answered.
- **Empty (loaded, nothing on).** The hero numeral is **0**, and the band
  carries the action that fixes it: *"Nobody's on tonight — start one"* →
  the map. Today this screen is a title, two headers and two grey sentences
  (`UI_REVAMP_AUDIT.md` §8.7).
- **First run.** As empty; `queuedEmptyText` / `nearbyEmptyText` already exist
  and their copy is reused rather than rewritten.
- **Error.** `ErrorBanner` under the baseline (it already exists here), with
  `isRecovering` distinguished — the supervisor is re-attaching, which is not
  the same as a failure the user should act on.

**What gets harder:** the collapse control goes. A user who collapsed "Public
Games" to see only their own runs now scans a list where theirs carry a filled
rail and the hero states their count. That is a **written 2e exception** and is
on the Checkpoint 1 list.

**Axes changed: 5 of 5.**

---

### 5.3 Map — `Views/Tabs/MapTab.swift`, `CourtRow`, `CourtGameRow` · archetype A3

**Marked `keep` at the tab level** — §2e's single permitted keep, assumption A4.

**Justification against §2c, as §2e requires.** The map already satisfies the
layer rule that the rest of this phase is trying to reach: content is the base
layer, edge to edge; every control floats over it on glass; the list lives in a
detent sheet; the primary action is pinned so it cannot fall below the fold. Its
first viewport draws **1 panel / 6 shapes**, the lowest panel count in the app.
Recomposing it would be change for its own sake, and §2d calls that out by name.

**What is redesigned anyway** — 2b names three files, and none of them is the
tab's composition:

- **The court detail card** (archetype A1 within the sheet). Hero: the court
  name at `display` with **distance as a numeral**. *(Built at `title`, not
  `display`, with the distance's number weighted rather than set as a numeral:
  at the `.medium` detent the sheet has ~155pt for the header and the runs. See
  the changelog.)* It currently truncates
  *both* of its own lines at `.accessibility3` — "East En…" and "Durham · 0.…" —
  because the star and close buttons scale with the text and take the width the
  name needs (`UI_REVAMP_AUDIT.md` §7.4 defect 2), against `MAP_LAYER.md`'s own
  rule that *badges are shed, the name is not*. The redesign gives it the ladder
  `CourtRow` has. **This is recorded as a defect closed, not a feature added.**
- **`CourtGameRow` / the card's `runRow`** takes the Runs row treatment (§5.2)
  so a run reads identically on both surfaces — which `UI_SHELL.md` already
  requires and `LocalRunsViewModel.action(for:)` already guarantees.
- ~~**The heat ramp reaches the rows.** `CourtRow` states busyness as grey
  text today; it gets the same `hooprHeat(tier:)` dot the pins use.~~
  **Wrong, and dropped (2026-09-22).** `CourtRow` shows no busyness at all;
  `CourtGameRow` is the row with runs, and a leading dot there moves its text
  column off the Nearby row's, which `MAP_LAYER.md` guards. See the changelog.

**The ODbL attribution (assumption A8).** The bundled court dataset requires
attribution and it is displayed **nowhere** — an outstanding licensing
obligation (`gaps/ASSETS_AND_DATA.md`) and the one gap in the ledger a redesign
could actually close. Proposed home: a single `caption` line in the map sheet's
rest state, under the court list. **Out of scope unless the user says
otherwise.**

**What gets harder:** nothing. **Axes changed: tab = 0 (keep, justified); court
card = 3 of 5** (hero, section order, disclosure).

---

### 5.4 Seasons — `Views/Seasons/SeasonsTab.swift`, `MatchmakingCard.swift` · archetype A4

**Question (ledger F13 / F10):** *What's our record, and are we playing?*

**Hero — conditional, and that is the design.** Prominence follows utility
(§2c), and on this screen what matters changes:

- `MatchmakingCard` **matched** → the match is the hero: opponent, court, time
  to tip-off as a `numeral`. It is the one thing on the screen the user must act
  on.
- `MatchmakingCard` **searching / settling** → the search is the hero, honest
  about the pool. An empty pool is **the default experience in a new city, not
  the edge case** (`gaps/SEASONS.md`); the existing copy is honest and is kept.
- **idle** → the record is the hero: **W–L as scoreboard numerals** in M3's
  crest-coloured band, form pills beside it. *(Built in a neutral band — see
  M3's measurement — and the form became five green / red / grey dots pinned
  to the band's bottom-right with no caption beside the numeral: the user's
  call, 2026-09-22. See the changelog.)*

**Primary action:** `Queue up`, in the band. Today it is two cards down.

**Removed or demoted:** the 28pt "Seasons" title (**removed** — the squad's own
name replaces it, which is information); `squadHeader`'s card (**becomes the
band**, no chrome); `rosterCard` (**rows** under one `label`); other-squad cards
(**rows**). `cardChrome()` 3+ → **0–1** (`MatchmakingCard` keeps a container
only in its matched state, where it is one tappable unit).

**Before-skeleton** (`UI_REVAMP_AUDIT.md` §6.4) — state B, *3 panels / 5 shapes*:

```
ScrollView → VStack(spacing: 16)
├── header       28pt "Seasons" · ProfileButton            ← hero, carries nothing
├── squadHeader  card — crest · name 22pt · record · FormGuide · chevron
├── MatchmakingCard  card — one of {idle, searching, settling, matched}
├── rosterCard   card
├── [n>1] otherSquads — one card each
└── "Create another squad"  bare text button
```

**After-skeleton** — target *0–1 panels / 2 shapes*:

```
ScrollView
├── crestBand                  M2 + M3, full-bleed, hooprSquad ground
│   ├── ProfileButton          trailing, floating
│   ├── crest · squad name     title
│   ├── W–L                    numeral 44          ← idle hero
│   ├── FormGuide              beside the record (the Phase 1 ViewThatFits)
│   └── format · region        caption
│   ── baseline ──
├── matchState                 idle → "Queue up" filled · searching/settling → live line
│                              matched → promoted ABOVE the band as the hero
├── "ROSTER" label → member rows
├── [n>1] "OTHER SQUADS" label → squad rows
└── "Create another squad"     quiet, last, unchanged
```

**State (A), no squad, is kept and restyled, not recomposed.** It is the one
composition in the app already built as a hero — crest → 22pt line → one action
(`UI_REVAMP_AUDIT.md` §6.4) — and **assumption A5** proposes it as the model the
rest of this brief is derived from. It gains M2's band and the type roles and
nothing else.

**Composed states:** `SquadViewModel.hasLoaded` already exists and `SeasonsTab`
already uses it — this is the one screen whose loading/empty distinction is
correct today, and it stays. Error: `ErrorBanner` under the baseline,
`isRecovering` distinguished.

**What gets harder:** nothing. **Axes changed: 5 of 5.**

---

### 5.5 `SquadDetailView` · archetype A4 + A2

**Question:** *how have we actually done?*
**Hero:** the record in M3's band, as numerals — the same band as §5.4 so the
push reads as a continuation (Phase 3's `matchedGeometryEffect` lands here).

**Removed or demoted:** this is the card-stack pattern at its limit — **six
`cardChrome()` blocks in one column, each with its own uppercase label, nothing
on the screen larger than 22pt** (`UI_REVAMP_AUDIT.md` §6.7). After: band +
history as a **board** of rows + roster rows + controls quiet at the bottom.
*5 panels / 8 shapes → target 0 panels / 2 shapes.*

**The record's authority is deliberate, and it is §2d's other half.** A squad's
W–L is a query over **mutually-confirmed** matches — "the one number in the app
nobody can type" (ledger F12/F13). It gets the scoreboard treatment. Home's
`completedGameCount` is a self-reported counter the owner writes, and gets a
caption line (§5.1). **The two must not be drawn with the same authority**, and
this brief's answer to that is the type role each is allowed.

**What gets harder:** nothing — invite buttons move from mid-page into the
roster rows they belong to. **Axes changed: 4 of 5** (hero, container, order,
action placement). *(Built 2026-09-23: pending invites join the roster rows; the
friends you could invite stay a labelled list under it, since they aren't on the
roster. The bar is hidden and the band carries the back button so it starts
where the tab's does — the user's call. See the changelog.)*

---

### 5.6 `GameDayView` · archetype A1

**Question (ledger F11):** *do I leave now?*
**Hero:** the countdown — `countdownHeadline` ("Tip-off in 42m") — at `numeral`
scale in the band. Today it is 22pt **inside a card**, which is the clearest
single instance of P1 and P2 being broken together.

**Removed or demoted:** eight stacked cards → band + court line + **one**
roster comparison (ours / theirs side by side, arrival counts as numerals) +
the action. The notification note is demoted to a `caption` — and stays, because
it is honest: reminders are **local notifications scheduled by a client that's
open**, so a member whose app never opens gets nothing (`gaps/SEASONS.md`).

**Primary action:** `We're here`, immediately under the band — it is the one
thing this screen asks of a user standing outdoors. Today it is after two roster
cards.

**Composed states:** cancelled (already handled, kept, promoted into the band);
error; and **"Final"**, which `countdownHeadline` already produces once the
window closes.

**What gets harder:** nothing. **Axes changed: 4 of 5.**
**Not verifiable in the simulator** — needs a live match (`UI_REVAMP_AUDIT.md`
§7.3). Its evidence row will be a component render, and the changelog will say
so. *(Built 2026-09-23 as described; the countdown reads as a label over the
numeral — "Tip-off in" / "1h 42m" — because the one-line form doesn't fit one
line at 44pt. Cancel match gained a confirmation. See the changelog.)*

---

### 5.7 `ResultView` · archetype A1 / A5

**Question (ledger F12):** *who won?*

This is the sharpest failure in the audit and it is structural: the screen that
delivers the app's **one trustworthy number** renders it as two lines of 13pt
body text inside a card, with roughly 600pt of blank page beneath — *1 panel /
1 shape* (`UI_REVAMP_AUDIT.md` §6.7). "You won" is the most emotionally loaded
string in the product and it is currently set **smaller than the word "Seasons"
on the tab it came from**.

**Hero:** the outcome at `display` scale, with the score as `numeral`s when one
was entered, on M3's winning crest colour. *(Built 2026-09-23 with the winning
crest drawn above the outcome instead: M3's tinted ground was measured below AA
on the Seasons tab. See the changelog.)*
**Primary action (reporting state):** the two crest buttons, large and centred —
A5, one question, one control. They are "the only place a `SquadCrest` is not
decorative" (`UI_SHELL.md`) and keep their explicit labels.
**Removed:** the card around the outcome; the uppercase labels.

**Composed states — all four are real here and all four exist today:**
awaiting the other leader (**waits forever** — no timeout, no forfeit, no nudge,
`gaps/SEASONS.md` — so the copy must not imply one is coming); **disputed**,
which is a *designed* outcome and not an error, and must not be drawn in
`hooprRed` as a failure; **confirmed**; and **reportable**.

**What gets harder:** nothing. **Axes changed: 4 of 5.**
**Never exercised on two real devices** (`gaps/SEASONS.md`) — so, strictly, its
rendering is unseen, and the evidence row will say so.

---

### 5.8 `LoginView` · archetype A5

**Question:** *let me in* — and, for a brand-new user, *what is this?*

**This screen proposes the brief's one structural exception, and it is on the
Checkpoint 1 list.** Login's hero today is "hoopsRN" at 34pt — the app's only
real typographic hero, and the right one. Changing it for the sake of §2e's
quota would be change for its own sake.

**What changes honestly:** the hero gains the fact a first-time user actually
lacks. Login is **the only screen in the app with no data on it** (assumption
A1), and one line saying what hoopsRN is for is information, not ornament — it
is the only screen where the *product* is the thing being explained. The brand
block becomes M2's band filling the top; the form moves onto
`hooprElevatedSurface` pinned above the bottom safe area, which is also where a
one-handed thumb is.

**Before-skeleton** (`UI_REVAMP_AUDIT.md` §6.5) — *0 panels / 3 shapes*:

```
VStack(spacing: 0) — Spacer · brand(44pt glyph · 34pt wordmark · mode title)
                   · fields · [error] · 52pt submit · mode switch · Spacer ×2
```

**After-skeleton** — target *1 panel / 3 shapes*:

```
ZStack
├── heroBand          M2, top half, full-bleed          ← Phase 4's MeshGradient lands here
│   ├── glyph · "hoopsRN"       display
│   └── one line: what it's for  body                   ← the added information
└── form              hooprElevatedSurface, pinned above the safe area
    ├── Email · Password        field grounds
    ├── [error]
    ├── submit                  filled, 52pt
    └── mode switch             quiet
```

**Axes changed: 3 of 5 claimed** (container primitive, primary-action placement,
section order) **+ a hero whose content changes but whose identity does not.**
If the user judges that short of §2e's "one of them the hero", the honest answer
is that Login should be granted a written exception rather than redesigned into
something worse. **Checkpoint 1 decides.**

**What gets harder:** nothing — the form stays two fields and one tap.
**Not verifiable without a sign-out** (`UI_REVAMP_AUDIT.md` § Not verified).
*(Built 2026-09-23 as designed, except that the form sits on the page ground:
in dark mode `hooprElevatedSurface` is the band's own value. See the
changelog.)*

---

### 5.9 `ProfileView` and the Friends pane · archetype A2

**Question:** *change something about me* — and, on the other pane, *find
someone*.

**This is the boxiest screen in the app: 7 panels / 14 shapes** in one
screenful, because `ProfileRow` gives every field a card **and** a tinted icon
tile (`UI_REVAMP_AUDIT.md` §8.7). `UI_SHELL.md` records the row as the *fix* for
a card mosaic whose heights carried meaning — it fixed that and kept the card.

**Hero:** the identity block, which this screen already has (the `@handle` at
30pt, won by deleting an orange header slab). It gains M2's band and the
`display` role, plus the one fact that identifies you **to other people** — your
home court. The uid stays, demoted, keeping its copy-on-tap.

**Removed or demoted:** `profileRowChrome()` — the second copy of the card
recipe — on every row; the tinted icon tiles; the pane selector's filled ground.
Rows become rows on the page, separated by hairlines and grouped under `label`s
by subject. *7 panels / 14 shapes → target 0 panels / 3 shapes.*

**Kept exactly as they are, because `UI_SHELL.md`'s reasons still hold:** the
pane selector pinned as a section header; the inbox in the top bar opposite the
back chevron (ledger F8 — the one thing another person is blocked on); **Sign
Out as the last row, not a pinned bar**; rows sized by their content with **no
fixed height** (a `.frame(height:)` row paints over its neighbour); read-only
fields expressed by omitting `onTap`.

**Friends pane:** `FriendRow`'s **inline, unnamed copy of the card recipe**
(radius 14) becomes a row. Search stays a permanently visible pinned control —
`UI_SHELL.md`'s rationale that *finding someone is an action, not a list* holds
and is not overturned. The pane's `minimumScaleFactor(0.8)` goes with the
selector's redesign.

**A gap this screen must not paper over:** there is **no blocking, no reporting
and no rate limiting** — anyone can ask anyone, repeatedly, and declining is the
only recourse (`gaps/FRIENDS.md`). The redesign adds no affordance implying
otherwise.

**What gets harder:** nothing. Every row keeps its tap count; the identity gains
a fact. *(Built 2026-09-23 as designed; the selector became an underline, and
the top bar takes the band's ground at rest. See the changelog.)*
**Axes changed: 3 of 5** (container primitive — the largest single drop in the
app, section order/grouping, disclosure) **+ hero content**. Like Login, its
hero *identity* does not change; unlike Login, its container change is drastic.

---

### 5.10 `PlayerProfileSheet` · archetype A5

**Question:** *is this the right person, and what are we to each other?*
**Hero:** the identity — avatar, name, handle — with **the relationship as the
one strong line**, since that is what the sheet is opened to resolve. The
sideways identity band stays sideways: a sheet opens at a height it must live
within (`UI_SHELL.md`), and that reason is unchanged.
**Primary action:** the `safeAreaInset` action bar, kept — it is already the
right pattern.
**Removed:** `ProfileRow`'s card chrome, matching §5.9.

**Renders a deliberate subset of a profile.** `users` is readable whole by any
signed-in account, so the subset is a **display choice, not privacy**
(`UI_SHELL.md` invariant) — the redesign does not reach for a field just because
it decodes. Mutual-friend counts are **impossible**, not omitted: `friendships`
is participants-only (`gaps/FRIENDS.md`).

**No structural quota** beyond §2c/§2d. **What gets harder:** nothing.

---

### 5.11 The sheets · archetype A5

**No structural quota — a form's layout is dictated by its fields (§2b).** What
applies is §2c (states are compositions, numbers are content, boxes earn edges)
and §2d.

| Sheet | Now | After | Note |
|---|---|---|---|
| `CreateGameSheet` | 4 hand-rolled cards, **its own card recipe** | one form on one surface; the court is the hero, the time is a numeral | 3 taps with defaults accepted — **must not rise** |
| `QueueSheet` | `cardChrome()` ×3 | one form; the window as numerals | its `ViewThatFits` chip ladder is the pattern, not the exception — keep it |
| `CreateSquadSheet` | `cardChrome()` ×4 | the **crest preview is the hero** — it is the one crest in the app that is *feedback* | M3's colour is chosen here |
| `InboxSheet` | rows + count capsules, page margin **16** | a board; margin → `Spacing.pageMargin` | ledger F8 — must not be missable |
| `ProfileEditSheets` (×5) | **five card recipes, margins 16 *and* 20 in one file** | one recipe, one margin | the home-court picker keeps saving on tap, with no Save button |

**`CreateGameSheet`'s invite step is §2d's standing automatic fail, and the one
thing in this brief that is a correctness fix rather than a design choice.**
A host can copy `hoopsrn://game/{id}` from the sheet and from `InviteLinkCard`,
and **that is the whole of it**: the scheme is unregistered, nothing implements
`.onOpenURL`, and the `games` read rule refuses a non-member — so **a recipient
who taps the link gets nothing, and an invite-only run still holds only its
host** (`gaps/GAMES.md`).

Both surfaces present it as usable. The redesign must not. The proposed framing:
the invite step leads with **the court and time as the thing to send a friend**,
and the link is offered below as a copyable reference **labelled with what it
actually does today**. The wording is a §2d obligation, not a stylistic choice,
and it is written once and used on both surfaces. *(Built 2026-09-23, with a
"Send the court and time" share button; every sheet in the table shipped. See
the changelog. `CreateGameSheet` was rebuilt the same day as an inset-grouped
form at the user's request — "not very structured", "more text and not a lot
of icons" — which overrides this table's "one form on one surface" for it.)*

---

## 6 — What this brief adds beyond layout

Listed separately so §2e can check them and so none of it is smuggled in as
styling.

1. **Two colour roles** — `hooprOnFill`, `hooprBaseline` — with a
   `ThemeContrastTests` assertion per pairing, in this phase (§3).
2. **Type-role presets** in `Typography.swift`, over `.hooprFont`, plus three
   metrics types with `.accessibility3` tests (§3).
3. **Two derived properties**, presentation-only, no new reads: `hasLoaded` on
   `HomeViewModel` and on `LocalRunsViewModel`, both from
   `GameService.hasLoadedGames`, which already exists and which
   `FindAMatchViewModel` already consumes. Tested in the shape of
   `HomeViewModelTests` / `LocalRunsViewModelTests`.
4. **An error state for Home**, which has none today.
5. **One new sentence of user-facing information** — the waitlist's
   non-promotion (§5.2, assumption A7) — and **one correction** — the invite
   link's real behaviour (§5.11).
6. **Three existing defects closed by construction**, recorded as closed rather
   than as features: `StatsCard`'s mid-word break, the map court card's
   double truncation, `GameCard`'s `.accessibility3` collapse.

**Out of scope and untouched:** services, models, `firestore.rules`; navigation
topology (four tabs in a native `TabView`, `ProfileView` replacing
`MainTabView`, `RootViewModel.destination`); `sheet(item:)` presentation; every
`UI_SHELL.md` invariant not explicitly named above as overturned. Motion, glass
and packages are Phases 3–5 — **the static layout must look finished without
them.**

---

## 7 — Checkpoint 1

**Stop. No view code until this is answered** (§2b).

### 7.1 The ten assumptions, and what each one changes

These are `UI_REVAMP_AUDIT.md` §5.3's list. Each has been **designed to** rather
than decided silently, as the prompt's failure paths require — the "designed to"
column is what the brief above assumes, and what changes if it is wrong.

| # | Assumption | Designed to | If it's wrong |
|---|---|---|---|
| **A1** | `LoginView`'s job includes being a **first impression**, not just collecting two fields | **Yes** — it gains one line saying what the app is for; Phase 4's `MeshGradient` lands in its band | Login stays a plain form; §5.8's hero change is cut and Login needs a written §2e exception instead |
| **A2** | Home's **greeting** is worth keeping at all | **No** — removed entirely | The greeting stays, demoted to a `caption` above the band; Home's hero change survives either way |
| **A3** | Runs' two sections are **read in one pass** | **Yes** — one time-ordered timeline, your runs marked by a rail | The two sections stay and Runs keeps its collapsible headers; its hero (the board strip) survives, but the axes drop from 5 to 3 |
| **A4** | The **map is the `keep`** tab | **Yes** — justified in §5.3 | Another tab must be the keep, or the map is recomposed for no reason §2c can name |
| **A5** | Seasons' **no-squad hero** is the model, not an exception | **Yes** — archetypes A1/A4 are derived from it | The archetypes need another source; the compositions above don't change much |
| **A6** | **"Spots left"** matters more than "N/M on the roster" | **Spots left**, as a numeral; the capacity bar is removed | The bar stays and `rosterText` gets the numeral instead |
| **A7** | The **waitlist's non-promotion** should be visible on the card | **Yes** — one line on a waitlisted card | The line is cut, and §2d's "drawn as working" objection stands unanswered on that one card |
| **A8** | The **ODbL attribution** has to land in this revamp | **No** — proposed home recorded (map sheet, rest state), out of scope unless you say otherwise | It ships in §5.3 and closes a live licensing obligation |
| **A9** | The evidence table may compare a **populated after-shot with an empty before-shot** | **Largely moot** — Phase 1's live set is populated and becomes the Phase 2 before-set (§7.2). One narrow question survives: photograph a joinable public run, or cite the render harness for it? | If you'd rather not create data, §5.2's Join / WAITLIST / FULL evidence is component renders, stated as such |
| **A10** | Light mode's page ground **stays pure white** | **Yes** — M2's band carries depth via `hooprFill` + the baseline, not by dropping the ground | The ground drops off white, which re-tunes `hooprFill` and `hooprBorder` on **every** screen and overturns `testCardSeparatesFromBackgroundInDarkMode` |

### 7.2 A9 — mostly answered, and the answer changes the baseline

**A9 as `UI_REVAMP_AUDIT.md` §5.3 states it is out of date.** It was written
when the account had no runs. Phase 1's live pass then put **three real runs on
the account**, and its 21-screen × 4-variant capture set survives. Verified in
this session:

- **Home is populated** — a real next-run card (East End Park · Today ·
  12:45 PM · HOSTING · 1 / 10 · 0.7 mi · capacity bar), a populated stats card
  (Runs 2 · Streak 1 wks · Last Run Today) and a three-row hot list with real
  counts (4+ today, 1 today, 1 today).
- **Runs is populated** — five queued runs, three `GameCard`s in the first
  viewport.

**So the Phase 2 before-set is the Phase 1 live set, not the Phase 0 set** — and
that is correct on its own terms: Phase 2 builds on the Phase 1 tree, so
comparing against 1a2710d would charge Phase 2 with Phase 1's colour changes.
The Phase 0 set stays the *skeleton* baseline for §2e's structural test, which
is a text comparison and is unaffected. Both sets are preserved in this
session's scratchpad.

**What is still not captured, and it is the state §5.2 turns on.** All five runs
are **invite-only and hosted by this account**, and Public Games reads
**"0 runs"**. So there is no screenshot anywhere of:

- a **joinable** public run — i.e. the `Join` button, which is ledger F2, the
  redesign's most important single control;
- a **WAITLIST** or **FULL** card, which is what §5.2's new waitlist line (A7)
  attaches to;
- a run the account is on but does not host.

Phase 1's render harness already draws exactly these three as **component**
renders from synthetic `Game`s — a hosted private run, a joinable public run, a
waitlisted full run — and I have preserved it. That covers the card; it does not
cover the card *in a screen*, among neighbours, under a scroll.

**The one remaining question, much narrower than A9 was:** do you want to create
**one public run** on the simulator so the Join state is photographable on a real
screen? If not, §5.2's evidence row cites the harness for those three states and
says so in the changelog. Everything else is now covered by real captures.

### 7.3 Three decisions that overturn a recorded rationale

The prompt says to **wait** on these rather than decide them (§ *Wait vs stop*).

1. **Runs' collapsible sections (A3).** `UI_SHELL.md`'s invariant says a list
   screen is built from the `LocalRunsTab` parts — *collapsible section header,
   one shared card, one write in flight*. §5.2 keeps the shared card and the
   single write and **drops the collapsible header**. Why the reason no longer
   holds: the header's job was to manage length by letting you fold a section
   away, and it does that at the cost of the screen's entire first viewport —
   two headers, two capsules, two chevrons and a rule, with the first `Join`
   240pt down. A time-ordered list with your runs railed does the same job with
   rank instead of disclosure. **Your call.**

2. **Login's hero (A1, §5.8).** Whether the content change clears §2e's "one of
   them the hero", or Login should take a written exception. I have argued for
   the exception being the *honest* answer if you don't buy the content change.

3. **The waitlist line (A7).** New user-facing information, on a card, saying a
   thing that will disappoint. §2d says the silence is worse. **Your call.**

### 7.4 What I need from you to proceed

- **A1–A8 and A10** — confirm or correct the "designed to" column. Silence on a
  row means I build what it says.
- **A9** — now just: create one **public** run on the simulator so `Join` is photographable, or accept component renders for that state?
- **§7.3's three** — each needs a yes or no.

On your answer I write **Home end to end** (code, four states, both appearances,
`.accessibility3`), then stop again at **Checkpoint 2** with its before/after
pairs and 2e evidence before touching any other screen.

---

## 7.5 — Checkpoint 1, answered

Answered 2026-09-22. Everything not listed here was accepted as the §7.1
"designed to" column states it.

| Question | Answer | Effect |
|---|---|---|
| **A3 · Runs' collapsible sections** | **One ordered list.** Disclosure is replaced by rank: ordered by tip-off, your runs railed, counts in the hero. | §5.2 builds as written. `UI_SHELL.md`'s "collapsible section header" clause is **overturned for Runs** and must be restated there when 2b ships — the shared card and the one-write-in-flight clauses are untouched. The lost fold-away is the written §2e utility exception. |
| **A7 · The waitlist line** | **Say it on the card.** | §5.2's line ships, worded as a current limitation rather than a dead end. Closes §2d's objection on that card. |
| **A9 · The Join state** | **A public run has been created on the booted simulator** by the user. | `Join` is photographable on a real screen. The render harness stays the fallback for **WAITLIST** and **FULL**, which still exist in no screenshot; the changelog will say which states are screens and which are component renders. |
| **A8 · ODbL attribution** | **In scope** — ships with the map. | §5.3 gains it: one `caption` line in the map sheet's rest state, under the court list. Closes the one ledger gap a redesign can close. |

**Not asked, and therefore built as §7.1 states them:** A1 (Login is a first
impression), A2 (**the greeting is removed**), A4 (the map is the `keep`), A5
(Seasons' empty state is the model), A6 (**spots left**, not N/M), A10 (light
mode's page ground stays white).

**Checkpoint 2 is still ahead:** Home ships end to end first, then stops for
its before/after pairs and §2e evidence before any other screen is touched.

---

## See also

- `UI_REVAMP_PROMPT.md` — the phase contract this is 2a of
- `UI_REVAMP_AUDIT.md` — §5 the ledger, §6 the before-skeletons, §7 the
  screenshots, §8 the findings
- `UI_REVAMP_CHANGELOG.md` — what actually shipped, per phase
- `UI_SHELL.md` — the invariants, and the rationales §7.3 proposes overturning
- `MAP_LAYER.md` — read before §5.3; `gaps/SEASONS.md` — read before §5.4–§5.7
