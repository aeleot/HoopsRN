# Changelog — UI Revamp

**Status:** in progress — Phase 1 shipped; **Phase 2a drafted, stopped at
Checkpoint 1** (`UI_REDESIGN_BRIEF.md` §7); Phases 2b–6 not started
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
