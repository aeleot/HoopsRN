# Changelog — UI Revamp

**Status:** in progress — Phase 1 shipped; Phase 2a answered; **Phase 2b:
Home and Runs shipped** (Checkpoint 2 passed after a blind read sent Home
back once); the map, Seasons, Login, Profile and the sheets not started
**Drafted:** 2026-09-21 @ 1a2710d
**Touches:** `hoopr/Support/Theme.swift`, `hoopr/Support/Spacing.swift` (new),
`hoopr/Support/CourtHeat.swift`, `hoopr/Views/` (30 files: the 22 the accent sweep
touched plus the 18 the spacing migration did, which overlap), `hooprTests/`, and the
docs named under each entry

> `context/plans/` carries no `Scope`/`Verified` stamp. This is the running
> record `UI_REVAMP_PROMPT.md` asks for after every phase: **what changed, what
> was deliberately left alone, and why.** Phase 2 adds its 2e evidence row per
> screen here. Measurements it cites live in `UI_REVAMP_AUDIT.md`.

---

## Phase 2b — Home, the vertical slice (2026-09-22)

The one screen done end to end before any other is touched, per §2b. **Stopped
at Checkpoint 2.** Design: `UI_REDESIGN_BRIEF.md` §5.1.

### 2e evidence — Home

| | Before | After |
|---|---|---|
| **Hero** | the greeting, 28pt, carrying no information | **the tip-off time, 44pt numeral** — the fact the decision turns on |
| **Axes changed** | — | **5 of 5** (hero, container primitive, section order, primary action, disclosure) |
| **Core-task taps** | 0 to read · 1 to reach Runs · 1 to "Find a court" | **unchanged** — 0 / 1 / 1 |
| **First-viewport containers** | 3 panels / 4 shapes | **1 panel / 2 shapes** |
| **Blind read** | — | **not yet run** (see *Outstanding*) |

**Squint test** (`sips -Z 160`). Before, the only legible element is the
greeting, over three grey boxes. After, "6:45 PM" and "East End Park" are
legible and the band reads as one region. That is the whole thesis in one
comparison.

**The five axes, each in a sentence:**

1. **Hero** — a greeting replaced by the tip-off time, set as a tabular numeral.
2. **Container primitive** — five `cardChrome()` call sites became **zero**; the
   full-bleed band and its `hooprSeparatorStrong` baseline group what the boxes
   used to.
3. **Section order** — the answer is first. The stats moved from *above* it to a
   single caption line at the bottom.
4. **Primary action** — Home had none (its only filled button was inside the
   empty state). The band is now the tap target into Runs, and the empty state
   carries a filled "Find a court" in the hero position.
5. **Disclosure** — the friend-request banner came up from below the fold to a
   row above it; four uppercase section labels became one.

### What changed

**Type roles (`Typography.swift`).** Nine named roles over `.hooprFont` —
`numeral`, `display`, `title`, `headline`, `subhead`, `body`, `caption`,
`label`, `badge`. Constraint 2 holds: every role resolves to a `hooprFont`
call, so `HooprFontMetrics` stays the only size arithmetic. `label` is one
spelling replacing the **six** the audit found. Both uppercase roles now use
`textCase(.uppercase)` rather than an uppercased string, so VoiceOver reads the
word instead of spelling it.

**One colour role (`Theme.swift`): `hooprHeroBand`.** The brief proposed two
(`hooprOnFill`, `hooprBaseline`); **both were dropped as redundant** — Phase 1
already asserts primary text, secondary text, error text, the accent and the
strong separator on `hooprFill`, and `hooprSeparatorStrong`'s own doc already
defines it as "a divider that carries structure". Adding aliases would have
been two names for values that exist. What *was* missing is a role meaning
"the ground a hero stands on", which resolves to `hooprFill` in light and
`hooprElevatedSurface` in dark — values the palette already proves, now pinned
by a test so the role can't drift into a third.

**`HomeViewModel`:** `hasLoaded`, `errorMessage` and `isRecovering`
republished from `GameService` (no new reads), plus four presentation-only
derived properties, each a thin wrapper over a `nonisolated static` so it can
be tested without a service.

**`HomeTab`:** rewritten around the band. Three composed states — booked,
open, loading.

### Two defects this closed, and one it found

- **`StatsCard`'s mid-word break at `.accessibility3`** ("Ru / ns", "Str /
  eak") is gone by construction: three fixed columns with two dividers became
  one sentence, and a sentence can only wrap at a space. Asserted.
- **Home had no error state at all** — a dead listener rendered as an empty
  screen, on the one tab whose whole job is that reading. It has one now.
- **A clip I introduced and caught by measuring rather than looking.** The
  band's court name was `.lineLimit(2)`, which looked right in every screenshot
  — because the run on the account is at "East End Park", thirteen characters.
  At `.accessibility3` the `title` role is 47pt and the page holds ~13
  characters a line, and **five courts in the shipped dataset need three or
  four lines**; the longest, "Saint Thomas More Academy High School Campus",
  needs four. The cap is now `nil`, and `HomeHeroMetrics` +
  `HomeHeroMetricsTests` measure **every court in the dataset** against it.
  *A screenshot could not have caught this.*

### Tests

**511 passed, 0 failed, 0 skipped** (from the `.xcresult`), up from 481.
+30: `TypeRoleTests` (9), `HomeHeroMetricsTests` (7), `HomeViewModelTests`
(+11), `ThemeContrastTests` (+3, every pairing drawn on the band plus the
baseline against both sides of itself).

### Deliberately left alone, and why

- **`GameCard`, the map card, Seasons, Profile** — 2b's order is Home first,
  then the rest, and Checkpoint 2 is between them.
- **`hooprOrange` vs `hooprBrandAccent` on the band.** The "Find a court"
  button stays a `hooprOrange` fill with `hooprOnBrand`; the HOSTING badge stays
  accent-on-wash. Phase 1's split is unchanged.
- **The greeting is gone, not demoted** (A2, answered). The user's name now
  appears only on Profile.
- **The waitlist non-promotion line is *not* on Home.** It belongs on
  `GameCard` (§5.2), where the decision is made; Home's band is read-only and
  points at Runs, which is `UI_SHELL.md`'s existing rationale.

### Outstanding for Checkpoint 2

- **The blind read has not been run.** §2e wants a fresh-context reviewer shown
  only the brief and the before/after pairs. Not run because this session was
  told not to spawn subagents unasked — needs the user's go-ahead, or a new
  session of their own.
- **Home's loading state is implemented and unit-covered but was not
  photographed.** On a warm start the app's own `.launching` splash covers the
  window: by the time Home is built, `hasLoadedGames` is already true. It still
  matters on a cold listener (`GameService` resets the flag on sign-out).
  Captured frames show the splash, not the band's placeholder.
- **The empty state was not photographed either** — the account has a run
  tonight, and producing the empty state means cancelling it, which is a write
  to the user's live account and theirs to make.
- **VoiceOver and Reduce Motion unverified**, as in Phase 1.

### Process notes

- **The app pins its own appearance, and that silently defeated
  `simctl ui appearance`.** The account had `Appearance: Dark` set, so
  `preferredColorScheme(.dark)` overrode the device for every capture. Worse,
  the two obvious fixes both *looked* like they worked and didn't: `simctl
  spawn booted defaults read` returned a **stale value from a different
  domain** ("light" while the real plist said "dark"), and editing the
  container plist directly was ignored because the simulator's `cfprefsd` had
  the old value cached — killing `cfprefsd` didn't help either. **Change it
  through the app's own UI**, and restore it afterwards (this session left it
  on Dark, as found).
- **A settle-based capture validator is not enough.** Requiring two identical
  consecutive frames passes happily on a *stale* frame: the first run produced
  a "dark/accessibility3" shot byte-identical to the light one. The validator
  now also requires each frame to **differ from the frame before the change**,
  and requires all four variants to be mutually distinct — which is what caught
  it.
- **`xcrun swiftc -target arm64-apple-ios18.0-simulator` + `simctl spawn`**
  measures iOS-only API (`UIFontMetrics`, text bounding boxes) in seconds
  without a build. Every scaled point size in the brief and in
  `Typography.swift`'s table is measured that way; the ones written from memory
  first were wrong for **every** role.

---

## Phase 2b — Home, three corrections from the user (2026-09-22)

The user reviewed Home in the simulator and raised three things. All three
were real, and the first was a regression this phase introduced.

### 1. The stats card "not appearing properly" — restored as a card

**It was not waiting on future work; the redesign had cut it.** Phase 2b
demoted the three-column card to one grey sentence at the bottom of Home, on
the reasoning that self-reported counters must not look as authoritative as a
squad's confirmed record. The second half of that holds. The first half
overshot: `plans/STATS_CARD.md` states the product intent as "a minimal card"
that surfaces engagement, and a bare sentence read as broken.

So `StatsCard` is a card again, with its three icons (basketball, flame,
clock), under a "Your stats" label that matches the hot list's. The authority
line is now held by **type tier** rather than by hiding it — the values are
row-tier `headline`, never the `numeral` / `display` tier the hero and squad
records use. It also says "1 wk" where the old card said "1 wks".

**And it can no longer break mid-word** — the defect in
`gaps/ACCESSIBILITY.md`, now closed. The old card gave each stat an equal third
of the width: 93pt at the default size, when "Yesterday" needs 92, and 116pt one
step up. The columns now hug their content, and `ViewThatFits` stacks the card
only when the row can't fit — measured by `StatsCardMetrics`: a row through
`.xxxLarge`, a stack from `.accessibility1`. Seen stacked in the live app at
`.accessibility3`, one stat per row, "Yesterday" whole.

### 2. The HOSTING pill sat off the line — measured, then fixed

The detail row mixed a 20pt numeral with 13pt captions and a capsule, and the
`HStack` centred the capsule against the tall numeral while the caption beside
it sat on its baseline. **Measured from the live captures at 3×: the pill's
label sat 3.7pt above the text next to it.** Now every fact on the line is the
same size, numbers carry their weight through weight and colour instead of
point size, and a new `FlowLayout` centres each item on its line. Same
measurement after: 1.5pt, all of it the "p" descender in "spots"; against the
digits, which have none, **0.5pt**.

### 3. "Wrap the text under the time, and icons for visibility"

Read as: give each line under the time an icon, and let the line wrap rather
than overflow. Done:

- **The court** carries `sportscourt.fill` in the accent — a court rather than
  a pin, because a pin beside the distance would say "location" twice. Aligned
  on the first baseline, so a court name that wraps (five in the dataset need
  three or four lines at `.accessibility3`) keeps its icon on the first line.
- **Spots and distance** carry `person.2.fill` and `location.fill`. The number
  in each is set in the primary colour at semibold, the unit in secondary —
  which needed `Distance.valueText` / `Distance.unit`, split out of
  `Distance.text` so the rounding rule still lives in one place.
- **`FlowLayout`** (new, `Views/Components/`) wraps only the item that has to
  move. At `.accessibility3` the pill and "9 spots left" stay on the first line
  and "0.7 mi" drops to the second — where the old `ViewThatFits` would have put
  every fact on its own line the moment the row was a point too wide.

### Tests

**532 passed, 0 failed, 0 skipped.** This change is net **+2**: six stats-card
tests in (`streakText`, the spoken form, the three stats and their icons, and
three `StatsCardMetrics` checks that pin the row/stack switch and that no value
must break), four stats-*sentence* tests out with the sentence. **The other +9
are not this session's**: a peer session reworking the Runs band's wording
replaced three `LocalRunsViewModelTests` with twelve of its own. Attributed from
a diff of the two `.xcresult` test lists, not assumed.

### Not verified this round

- **Light mode was not re-captured.** The app is pinned to Dark on this account
  and was left that way; every colour these changes draw is an asserted
  pairing (`hooprBrandAccent` on the band and on `hooprSurface`, both text
  roles on both), but the light rendering itself is unseen.
- **VoiceOver**: each detail and stat now carries a spoken label ("9 spots
  left", "1 week streak" rather than "1 w k"), unverified with VoiceOver
  running.

### A note for whoever works on Home next

`ProfileButton.Slot` — the fixed position every tab now gives the profile
button, and the 10% larger glyph — arrived from a **peer session** while this
work was in progress, along with edits to `MapTab`, `SeasonsTab` and the Runs
band. It is uncommitted and interleaved with this session's changes in the
working tree; neither session's work reverts the other's.

---

## Phase 2b — Runs, and what the blind read sent back (2026-09-22)

### The blind read, and the two things it caught

§2e's fresh-context reviewer was shown the brief **with §5 withheld** — §5 names
each screen's intended hero and primary action, so handing it over would have
made the test circular — plus the before/after pairs, and nothing else. It
matched the evidence table on the hero, the structural changes, the container
counts, the squint residue and P1/P3. It disagreed on two, and both were right:

1. **"There is no primary action drawn."** The band navigated to Runs but drew
   no affordance at all, so the most-opened screen in the app read as a
   scoreboard you cannot act on — the A1 archetype implemented without its
   action clause. Fixed: a **"Your runs ›"** cue in the accent, deliberately a
   cue and not a filled button, because the action is *navigation to a
   decision* and join/leave/cancel belong on Runs (`UI_SHELL.md`'s recorded
   reason for this card being read-only).
2. **P2 passed at the hero and failed everywhere below it.** "9 spots left" set
   the 9 at the same size and weight as the word beside it; the hot-court count
   had been promoted to a bold numeral but had its unit *deleted* — a bare "1"
   under no column header, where the old screen said "4+ today". Both fixed:
   the number takes `headline` with the unit demoted beside it, and "today" is
   back.

It also flagged, correctly, that **the pair was not data-matched** — the
before-shots were a day older, so some apparent change was drift. That is now
fixed for both screens; see *Evidence* below.

Its P2 objection to the stats line was **not** taken, and the reason is
recorded in `HomeViewModel.statsSummary`: those are self-reported counters the
owner's own client writes, and §2d makes giving them the authority of a
confirmed result an automatic fail. It is the one place a number stays inside a
sentence on purpose.

### 2e evidence — Runs

**Both rows below are data-matched:** the Phase 1 commit (`2638219`) was rebuilt
from a clean `git archive` into the scratchpad and captured on the same device,
same account, same single run, minutes apart from the after-set.

| | Before | After |
|---|---|---|
| **Hero** | the word "Runs", 28pt — the tab bar's own label | **"1 run on", 44pt numeral** |
| **Axes changed** | — | **5 of 5** |
| **Core-task taps** | Join = 1 | **unchanged** |
| **First-viewport containers** | 1 panel / 6 shapes | **2 panels / 5 shapes** |
| **Blind read** | — | not re-run for Runs |

**The panel count went up by one, and the reason is the band.** It is a filled
region that groups content, so it counts. What it replaced — a 28pt title row —
drew no rectangle, so the swap costs a panel and buys the screen's answer. The
*shape* count falls, and the two count capsules, two chevrons and the
section rule are gone. Note the before-count is data-dependent: with one run on
the board it is 1 panel; with five it was 2 panels / 7.

**The five axes:**

1. **Hero** — the tab's own name replaced by how many runs are on.
2. **Container primitive** — two collapsible sections over a scroll became a
   band plus a flat list; `GameCard` keeps `cardChrome()`, which is the one
   container on the screen that earns its edges (a run is a single tappable
   unit carrying its own controls).
3. **Section order and grouping** — split by *ownership* became ordered by
   *tip-off*, with ownership demoted to a rail.
4. **Primary-action placement** — the first `Join` was ~240pt down the page,
   behind two headers and a rule; it is now in the first viewport.
5. **Disclosure** — two chevron-collapsible sections became none.

### What changed

**`LocalRunsTab`** — band + one ordered board. **This overturns a `UI_SHELL.md`
invariant** ("a list screen is built from the `LocalRunsTab` parts: collapsible
section header, one shared card, one write in flight"). The shared card and the
single write are untouched; the collapsible header is not. Confirmed with the
user at Checkpoint 1 before any of it was written.

**`LocalRunsViewModel.timeline`** — merges the two listeners into one ordered
list. `queued` is walked first, and that ordering is the whole correctness of
it: a run you host publicly arrives on **both** listeners, so walking `nearby`
first would render your own run as a stranger's and offer "Join" on a run you
are already on. Tested.

**`GameCard`** — the time leads as the row's rank; **spots left replaced the
capacity bar** (the bar and `rosterText` drew one fact twice, neither of them
the question); `isYours` draws the rail that the section split used to say.

**`Game` gained `timeText`, `dayText(relativeTo:)` and `spotsText`**, beside
`rosterText` and `scheduledText()`. They started on `HomeViewModel` and
`GameCard` reached across to use them — a view referencing another screen's
view model. They belong on the model with the other run presentation strings,
which is also what stops the band and the board disagreeing about what time the
same run is at.

**`InviteLinkCard` now says what the link does.** A host can copy
`hoopsrn://game/{id}` and that is the whole of it — unregistered scheme, no
`.onOpenURL`, and the read rule refuses a non-member, so a recipient who taps
it gets nothing (`gaps/GAMES.md`). Both surfaces presented it as a working
invite, which is §2d's standing automatic fail and was visible three times over
on the old Runs screen. The note names what *does* work: send the court and the
time.

**The waitlist line shipped** (A7, answered yes): a waitlisted card now says
the list doesn't move up yet and to ask the host. Worded as a limitation with a
next step, not a dead end.

### A defect the screenshots caught that the tests could not

At `.accessibility3` the card's rank line ran out of width and SwiftUI broke
the **first** item — so "6:45 PM" rendered as "6:45 / PM". It is a *reflow*,
not a truncation, so it passed the no-clipping rule while destroying the thing
the line exists to do. Fixed with a `ViewThatFits` ladder that drops the badge
to its own line instead; the badge is the least load-bearing of the three.
**The light/default capture is byte-identical before and after that fix**,
which is how the ladder is known to engage only at accessibility sizes.

### Tests

**521 passed, 0 failed, 0 skipped**, up from 511. +10: `LocalRunsViewModelTests`
(+8, the merge's dedupe order and the band summary), `GameTests` (+11 for the
moved presentation strings), `HomeViewModelTests` (−9, moved to `GameTests`).

### Deliberately left alone

- **`MapTab.runRow`** still draws its own row rather than `GameCard`. The map's
  card lists runs *at one court*, so it asks no ownership question and needs no
  rail; folding them together is Phase 6's job, and only if 2c still wants it.
- **`CreateGameSheet`'s invite step copy** — the component carries the note now,
  so both surfaces tell the truth, but the sheet's own caption is §5.11's work.
- **The rail is not on the map's rows**, for the same reason.

### Outstanding

- **The blind read has not been re-run** on the corrected Home or on Runs.
- **Empty and loading states are still not photographed** on either screen —
  both are implemented and unit-covered. The account has a run tonight, and
  producing the empty board means cancelling it, which is the user's write.
- **VoiceOver and Reduce Motion unverified**, as in Phase 1.

---

## Phase 2b — Runs header and the profile button's slot, from user feedback (2026-09-22)

The user liked Home and not the Runs header. Three requests: the hero should
read "2 games on the schedule" rather than "2 runs on", with a subtle sense of
being a *player*; the "you're in 2" line under it looked wrong; and the profile
button jumped on every tab switch, and should be 10% larger.

### What changed

- **The Runs band** now reads, top down: eyebrow **"Tonight"**, or **"Coming
  up"** once any run on the board is later than today; **"2 games on the
  schedule"** (numeral plus headline); then a **roster line** with the card rail
  beside it:
  "You're suited up" / "…for both" / "…for all 4" / "…for 2", "· waitlisted for
  1" when you hold a waitlist place, "You're on the waitlist for 1" when that's
  all you hold, and "You're a free agent" (no rail, secondary colour) when you
  hold neither. The eyebrow used to say "Tonight" unconditionally, which was
  wrong for a board that runs to `Game.schedulingWindow` (30 days). **The radius
  left the band entirely:** a first pass put "Within 14 miles" in the eyebrow,
  and the user rejected it — it read as a filter setting, and it wasn't true of
  the board, since a run you're on is listed however far away it is. The empty
  board still names the radius. Rules live in
  `LocalRunsViewModel.eyebrowText(tipOffs:now:calendar:)`,
  `scheduleText(count:)` and `rosterText(suitedUp:waitlisted:onSchedule:)`;
  `boardSummaryText` is gone. The loading copy says "schedule" too. **Left
  alone:** the empty board's "No runs within N miles tonight." and the cards'
  run vocabulary, since the request was about the header.
- **`ProfileButton.Slot`** is the button's one position: the frame's top 12pt
  below the safe area, its trailing edge on `Spacing.pageMargin` — Home's
  placement. Before, Seasons sat 8pt further out and 4pt higher, and the map's
  sat 6pt further out and 3pt higher. Seasons now top-aligns its row (a
  centred row let the title's Dynamic Type push the button down); the map
  derives its chrome's top inset from `Slot.centerY` and the 46pt search
  field, and its search row takes the page margin on the trailing side only.
- **The glyph is 35.2pt** (from 32), capped at 41.8 so it still fits the 44pt
  frame, which is what stops Dynamic Type from moving it. The badge dot went
  11 → 12pt and was pulled onto the bigger glyph's rim.

### Evidence

Live app, iPhone 17, iOS 26.5, default text size, dark: the glyph's pixel
bounding box is **identical on all four tabs** — (1027, 236)–(1131, 340) at 3x,
35.0pt wide, centre (359.7, 96.0)pt. Measured by colour match; each capture was
checked to show the right tab (one taken mid-transition was retaken). Other text
sizes not captured.

### Tests

**530 passed, 0 failed, 0 skipped**, up from 521: `LocalRunsViewModelTests`
−3 (the old summary) +12 (schedule plurals, free agent, both/all, waitlist, and
the eyebrow's day boundary — including a run from late last night that is still
listed and must not read as "Coming up").

---

## Phase 1 — Design tokens: colour system and spacing (2026-09-21)

### Acceptance

| Criterion | Result |
|---|---|
| `ThemeContrastTests` green, including every new pairing | **Yes.** 22 tests, 12 of them new; each new pairing asserted in both appearances. |
| Full unit suite green | **Yes — 481 passed, 0 failed, 0 skipped, 30 suites**, up from 463 / 28. Counted from the `.xcresult`, not the log (see *Process*). |
| The tracked AA gap closed, `testTabBarSelectionIsATrackedGap` flipped, gap note removed from `GAPS.md` | **Yes.** Replaced by `testTabBarSelectionClearsAA`; `gaps/ACCESSIBILITY.md` no longer leads with it. |
| No visual regressions at default text size, either appearance | **Yes, in the live app** (the live pass below: dark mode 0.00% changed on 8 of 9 screens; in light every change is deepened orange) **and at component level** (render harness). *Not verified:* VoiceOver, Reduce Motion, `.accessibility3` for the reasons under *Not verified*. |
| Audit doc updated | **Yes** — `UI_REVAMP_AUDIT.md` §9, and corrections to §7.3 and §8.8. |

### What changed

**Colour (`Theme.swift`)**

- **`hooprBrandAccent`** — the brand as a *mark*. `#B8400F` in light: `hooprOrange`'s
  own hue (17.4°) and saturation with lightness lowered until it clears 4.5:1 on
  every ground a mark sits on (5.56 on white, 5.10 on `hooprFill`, 4.87 / 4.76 on
  the 12% / 14% orange washes, 4.70 on `hooprHoverFill`). Dark is `hooprOrange`'s
  own dark value, which already cleared it. **`hooprOrange` was not retuned** —
  it is now a fill, never a mark.
- **Elevation:** `hooprElevatedSurface`, `hooprHoverFill`, `hooprSeparatorStrong`.
- **Heat:** the five-stop palette moved into `Theme.swift` as
  `hooprHeat(tier:)`, **paired in one table with the label that reads on it**,
  `hooprOnHeat(tier:)`. `CourtHeat` is now only the rule (count → tier); its API,
  and every test of it, is unchanged.

**The sweep.** 76 `hooprOrange` uses in `Views/` were classified one by one rather
than swapped globally: **49 marks** → `hooprBrandAccent`, **21 fills** carrying
`hooprOnBrand` kept, 4 structural. The 4 are the reason it wasn't a find-and-replace:
`ProfileRow`'s icon tile and both run badges use *one* tint for the mark **and** the
12–14% wash behind it, so deepening the tint would have dulled every wash. The mark
and the wash are now two colours (`ProfileRowTint`; a `foreground` and a `wash` on
each badge). The tab bar's `.tint` moved to the accent.

**`CourtHeat` / `MapView`.** The pin's count label takes its colour per tier.

**Spacing (`Support/Spacing.swift`, new).** A scale on a 4pt grid and five roles —
`pageMargin` 20, `cardPadding` 16, `interCard` 16, `interRow` 12, `section` 24 — plus
`Pill` and `Chip` paddings. **71 edits in 18 files**, each matched by concept: numeric
`.padding` literals 231 → 172, `Spacing.*` uses 0 → 70. `ProfileView`'s private
`pageMargin` became the shared one.

**Tests.** +18 net. `ThemeContrastTests` 12 → 22 (accent on every ground and on both
washes, the tab bar, destructive and WAITLIST/FULL washes, the dark elevation ladder,
hover fill, strong separator, every heat tier); `CourtHeatTests` 10 → 13;
`SpacingTests` (3); `BrandMarkUsageTests` (2), which reads `Views/` and fails if a
view draws `hooprOrange` in `foregroundStyle`, `tint` or `stroke` — a fill is never
flagged, so Phase 2 adding orange buttons is free.

**Docs.** `UI_SHELL.md` (role table, spacing section, tab bar, invariants),
`MAP_LAYER.md`, `gaps/ACCESSIBILITY.md` (rewritten around what is still wrong),
`GAPS.md`, `PRODUCT_OVERVIEW.md`, `BUILD_AND_CONFIG.md`, `gaps/TESTING.md`, and dated
notes on `plans/APP_SHELL_AND_HOME.md` and `plans/BACKLOG.md`.

### The visible changes — these are the deviations from "no regression"

Measured by rendering the changed components at HEAD and at this tree on the same
simulator and diffing the pixels (0.13–1.24% of pixels changed per component; **no
component changed size**):

1. **Marks are a deeper orange in light mode** — `#EE6730` → `#B8400F`: glyphs,
   badge text, the capacity bar, focus rings, link text, the tab bar's selected item.
   **Dark mode: 0 pixels changed in every component.**
2. **Heat-pin counts turn white from tier 3** (black stops clearing there). Identical
   in both appearances, because the ramp is fixed.
3. **The Runs tab insets its cards 20pt, not 16** — the one *layout* change, made so
   the title and the content under it share an edge. Not measured by the harness
   (it renders components, not the tab).

Unchanged, and confirmed by the diff: layout, every fill, the washes behind badges
and tiles, the glass chips (0 pixels), the red destructive actions.

**One change that is not Phase 1's, made at your request during the live pass:** on
Seasons' squad home the W/L form pills now sit **beside the record** ("1–0 this season
(W)") instead of beneath it. `SquadRecordLine` in `SeasonsTab.swift`, a `ViewThatFits`:
beside for one to three results, beneath for four or five (five 28pt pills are 164pt in a
~230pt column) and at every accessibility size, so nothing clips. Rendered at 1, 3, 4 and
5 results, default and `.accessibility3`, and the old layout renders identically to the new
one wherever it falls back. **Not seen in the live app.** `SquadDetailView`'s Record card
still stacks its form beneath the number. Phase 2 recomposes this screen and may supersede
it.

### Found along the way

- **A real AA failure nobody had listed.** The pin's count was black on all five heat
  tiers — **4.01:1 and 3.43:1** on tiers 3 and 4, under the 4.5:1 a 12pt bold label
  needs, on exactly the courts busy enough to matter. A comment in `MapView` claimed
  black was "the only foreground that clears AA against every stop". Fixed and
  asserted for every tier.
- **The HOSTING badge measured 2.78:1**, not the 3.17 the gap docs quoted: it sits on
  a wash of orange, not on the card, so the ground was darker and more orange than
  anyone had measured.
- **The tab bar's real figure was 3.01:1** in light, not "~2.55". iOS 26 adjusts a tint
  before painting it (`#EE6730` → `#E55E27`). After: 5.43:1 in a calibrated harness
  render of a real `TabView`, unchanged 5.21:1 in dark.
- **The gap survived because the tests pinned the failure.** They asserted the ratio
  was *under* a threshold, so they passed on 2.29 and on 3.17 alike and the docs'
  numbers drifted stale unnoticed. A test that asserts a defect cannot tell you the
  defect changed.
- **Two reflow defects at `.accessibility3`**, from Phase 0's screenshots, now recorded
  in `gaps/ACCESSIBILITY.md` (`StatsCard` breaks mid-word; the map's court card
  truncates its own name).
- **Stale numbers and claims corrected**, listed in `GAPS.md`: three code comments,
  `MAP_LAYER.md`'s heat stop 0 (`F79331`, the pre-08-22 value), and the "462" in this
  audit, which was a log-grep artefact — the suite was 463.

### Deliberately left alone, and why

- **Light mode's page ground is still pure white.** It is a documented, test-pinned
  decision, and moving it re-tunes `hooprFill` and `hooprBorder` on every screen. It is
  a design decision, not a token-phase side effect — **A10** in the audit, for
  Checkpoint 1. `hooprElevatedSurface` is defined so the answer, either way, is a value
  change and not a call-site hunt.
- **`hooprElevatedSurface`, `hooprHoverFill`, `hooprSeparatorStrong` are defined and
  asserted but drawn nowhere.** Adopting them is a visible change (a stronger field
  outline, a pressed-row fill) that belongs with the composition that wants it.
- **Corner radii, control heights, `ProfileView`'s 10pt row gap, `Chip`'s 14 × 9.** They
  are composition decisions, and Phase 2 recomposes the screens they belong to.
- **Four screens still inset 16, not 20:** `InboxSheet`, `QueueSheet`, `GameDayView`,
  `ResultView`. Consistent within themselves, so there is no visible mismatch to fix.
- **The three drifted copies of the card recipe, the five badge spellings, the six
  button heights.** Phase 6 — and only where Phase 2 still wants a card.
- **`hooprDarkOrange`.** Still painted nowhere but the map's UIKit marker tint.
- **`GlassChip`'s labels over the map, the search field, the recenter glyph.** A
  translucent surface has no fixed ground to assert.
- **`CLAUDE.md`'s test destination command** (below).

### The live pass (2026-09-21, iPhone 17, iOS 26.5, your running Phase 1 build)

The app was runnable again once a Run session from 11:40 released Firestore's lock, and
your Phase 1 build (linked 14:52, symbols confirmed in the binary) was driven directly.
**22 screens and states, four variants each** (light / dark × default / `.accessibility3`),
including three real runs on the account — the first populated `GameCard`, Home next-run
card, hot-court list and heat pins in this audit.

**What was measured:**

- **Dark mode: 0.00% of pixels changed** below the status bar on 8 of 9 screens compared
  with the Phase 0 shots (the ninth, the queue sheet, is a Phase 0 capture artefact — below).
- **Light mode: every changed pixel is deeper orange** — the typical changed pair is literally
  `#EE6730 → #B8400F`, the fill becoming the accent — 0.08–0.51% of pixels per screen. The
  icon tiles' washes, every fill and label, and the destructive rows did not move. (The
  Dynamic Island, black in the old shots and absent in the new, is excluded; it was the
  largest single "change" until it was masked.)
- **The Runs tab now insets its cards 20pt**: card border at 19.7pt left and right, sharing
  the title's 20pt edge; the "Queued Games" header moved exactly +12px (= 4pt) while the title
  did not move. Title and header edges went from 3pt apart to 1pt (glyph side-bearing).
- **The tab bar renders 5.32:1 in light, 4.98:1 in dark** (before 3.01 / 5.09), sampled from
  the live app. The harness had predicted 5.43 / 5.21.
- **A tier-4 heat pin renders a white "4" on `#BF2010`**, 6.12:1, in both appearances.
- **Unselected tab items are unchanged** (identical darkest pixel on four screens).
- `hooprOrange` fills stayed vivid: the "Add a run" and "Send reset link" buttons, the selected
  "Public" and "Today" segments, the "9 SPOTS" capsules.

**What it found:** `GameCard`'s `.accessibility3` collapse (badge breaking "HOSTI / NG", name cut
to "Long Meado…", details row breaking mid-word), now in `gaps/ACCESSIBILITY.md`.

**How reliable the captures are — and were.** About a third of my first-pass size variants
were captured before the app had re-laid out at the new text size: 16 of 22 screens came out
fully consistent; `creategame-sheet` showed Home in all four (the screen changed underneath the
capture); five single variants were at the wrong size. `simctl ui content_size` returns
immediately and the app can lag it by seconds, worst on a sheet and on a screen a sheet has just
closed. The create-run set was retaken with a **self-validating script** (double-set the size,
require two identical screenshots, require accessibility to differ from default, compare the
screen at the end with the start); `map-now` and `seasons-squadhome` dark/`.accessibility3` were
retaken the same way. **The Phase 0 before-set has the same flaw**: its queue-sheet dark/default
shot shows taller rows than a consistent capture, which is why that one comparison reads 22%.
Every *light/default* before-shot I diffed was consistent; treat the other variants as
indicative, not authoritative.

### Not verified

- **VoiceOver and Reduce Motion.** Phase 1 changed no accessibility label and no animation, and
  the tooling can't operate VoiceOver; both are unverified rather than verified-clean. A three-minute
  manual swipe through one Runs card and one map pin would close it.
- **Login** (needs a sign-out, then you signing back in) and **Game Day** (needs a live match).
  The harness covered neither.
- **Three accessibility-size variants that came out stale and were not retaken:**
  `homecourt-sheet` and `password-sheet` light/`.accessibility3`, `profile-rows-lower` dark/default.
  None is a screen whose layout Phase 1 touched.
- **The Runs tab's 20pt inset at `.accessibility3` moves the `GameCard` collapse; it neither
  causes nor fixes it.** Rendering the same card at 16pt and 20pt margins: the collapse is
  identical in kind — the badge breaks "HOSTI / NG" either way — but the 8pt lost changes *how*:
  the court name gains a second line ("Long / Meado…" rather than "Long M…"), the roster text
  truncates ("pla / ye…") where it used to wrap ("play / ers"), and the card is 43pt taller.
  A mixed, slightly-worse-in-one-place result on a card that was already broken; Phase 2's Runs
  redesign has to fix the card either way (`gaps/ACCESSIBILITY.md`).
- **Something else drove the simulator during the pass.** Three times the screen changed with no
  tap from me (the create-squad crest, the create-run sheet, the Runs tab at the start). Nothing
  was written to the account: the only writes are the ones you made. If it was you, no harm — but
  two drivers cost time and left one capture set invalid.
- **Nothing below iOS 26 has run** — `gaps/CONFIGURATION.md` still holds; no iOS 18 runtime is installed.

### Process — things that will bite the next session

- **`CLAUDE.md`'s test command no longer resolves on this machine.** Xcode 27 installed
  an iOS 27.0 runtime; `OS:latest` now means 27.0, and there is no iPhone 17 on it, so
  `-destination 'platform=iOS Simulator,name=iPhone 17'` fails with "Unable to find a
  device". Add `,OS=26.5`, or create an iPhone 17 on 27.0. Left for you to decide.
- **Test runs can collide with a live Run session.** `xcodebuild test` on the booted
  device launches its test host into the same data container as a running app and dies
  on Firestore's lock. Run tests on a different device, with their own DerivedData.
- **A fixed sleep after `simctl ui content_size` is not enough.** The app can lag the change by
  seconds, and a screen behind a just-closed sheet can keep the old size until something forces
  a re-layout (toggle the size away and back). Use the self-validating capture in the changelog's
  live-pass note, and confirm the screen with a screenshot before every tap that isn't a
  tab-bar or back button.
- **Count tests from the `.xcresult`.** `xcrun xcresulttool get test-results summary
  --path <bundle>`; a log grep undercounts by whatever line interleaved output mangles.
- **The before/after render harness was throwaway, and Phase 2 will want it.** It
  rendered real views to PNG through a `UIWindow` (so glass, the tab bar and dynamic
  colours resolve as on device), at HEAD via `git archive` and at the working tree, in a
  scratch copy of the repo with its own DerivedData — then diffed the pixels. It
  reproduced the live app's tab-bar contrast to within a tenth (3.08 vs 3.01), which is
  what made it trustworthy. About 150 lines of Swift and 100 of Python, in this session's
  scratchpad; **promote it into `tools/` before Phase 2's evidence table, or rebuild it.**
  Note it needs `.ignoresSafeArea()` on the hosted root, or the status-bar inset pushes
  content down and clips the bottom.
- **Build with the default DerivedData, or one outside the repo**, never
  `-derivedDataPath build/...` and never `CODE_SIGNING_ALLOWED=NO` for an app you will
  sign in to (memory: `build-signing-keychain-trap`).
