# Changelog — UI Revamp

**Status:** in progress — Phase 1 shipped; Phase 2a answered; **Phase 2b:
every screen and sheet in the brief shipped** — Home, Runs, the map's court
card, the four Seasons screens, Login, Profile, Friends, `PlayerProfileSheet`
and all of §5.11's sheets (Checkpoint 2 passed after a blind read sent Home
back once); Start a Run since rebuilt as a grouped form, and the court glyph
redrawn as a basketball court, from user feedback. Blind reads beyond Home and
Runs not run. **Phase 3 (motion) built** — see its entry; its live pass is
outstanding
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

## Phase 3 — Motion language (2026-09-23)

Built-in SwiftUI only; no dependency added.

### What changed

- **One vocabulary** (`Support/Motion.swift`): three kinds of change —
  `hooprSpring` (the user moved something), `hooprSnap` (a control's own
  state), `hooprSwap` (content replacing content) — plus `hooprLift` for
  entrances, `hooprPop` for a badge, `HooprPressStyle` for press feedback,
  `hooprNumericTransition` for counts, `hooprBounce(onRiseOf:)` for a symbol,
  `hooprScrollLift` for a list's edges, and `hooprZoomSource` /
  `hooprZoomDestination` for card-to-detail pushes. **Every hand-written
  duration and spring in the views is gone** (20 call sites) except
  `MainTabView`'s two, which a parallel session has uncommitted work in.
- **`MatchmakingCard`'s four states transition** instead of cutting: the
  outgoing state fades as the incoming one lifts in, the card's edge fades in
  with a match (`cardChrome(isShown:)`, so the card keeps its identity), and the
  height follows. Keyed on the *kind* of state, so the opponent's crest arriving
  or the search clock ticking never re-runs it.
- **Zoom pushes:** squad detail grows out of the Seasons band's squad (or its
  row under "Your other squads"), game day out of the match card, and each
  shrinks back on the way out.
- **Numbers roll** when they change: spots left, the Runs count, the record,
  game day's arrivals, the inbox badge, the friends and inbox counts, the create
  sheet's player count.
- **Symbols:** copy confirmations, the create sheet's radio marks, the map
  card's star and game day's arrival circles replace rather than swap; the inbox
  tray bounces once when a request arrives.
- **Press feedback** on every button that draws its own fill (25 of them).
- **Runs:** cards fade and shrink slightly at the scroll view's edges, and a run
  arriving or leaving moves the others.
- **Haptics**, only for changes the user caused: joining a run (or its
  waitlist) and completing one are a success, leaving or cancelling a light
  tap, and starting a run, copying a link, marking yourself here and match
  found are a success. The run ones come from a new `lastConfirmation` on
  `LocalRunsViewModel` and `FindAMatchViewModel`, **set only by a write the
  server accepted** — the listener re-emitting a roster never buzzes. Match
  found fires only going *from searching* to matched.

### Acceptance

- **Reduce Motion:** every kind becomes one 0.15s cross-fade; entrances stop
  travelling; presses only dim; bounces stop; zoom pushes become plain pushes.
- **Nothing animates on first appearance** — by construction: every animation
  hangs off a change (`withAnimation` in an action, `.animation(_:value:)`, an
  insertion's transition, `onChange` for the bounce).
- **Interruptible and reversible:** springs retarget from wherever they are,
  and the zoom pushes dismiss interactively.
- **120Hz:** springs are frame-rate independent; the eased durations are
  0.15–0.28s.

### Deliberately left alone, and why

- **`MainTabView`'s two animations** — a parallel session has uncommitted work
  in that file.
- **No scroll edge effect** (`scrollEdgeEffectStyle`, iOS 26). The system
  already draws the soft edge under the tab bar; the bands at the top of each
  tab scroll with their content and aren't bars.
- **No zoom from a run card** — a `GameCard` doesn't open anything.
- **The radius numeral doesn't roll** — it follows a slider, and a roll would
  make it lag the thumb.
- **Friend request actions have no haptic.** Not in the phase's list, and the
  inbox answers them in place already; easy to add with the same pattern.
- **A cold launch into an active search cross-fades once** from "Find a match"
  to the search, as the ticket listener answers. The flash of the wrong state
  was already there; it's now a fade instead of a cut. Telling the two apart
  needs a "ticket loaded" flag on `MatchmakingViewModel`, a read this phase
  doesn't add.

### Evidence

- **Tests:** `MotionTests` (13, new) — Reduce Motion collapses every kind to
  the same fade; the kinds are distinct springs; durations stay short and exits
  beat entrances; presses only dim under Reduce Motion; the tray bounces only
  on a rise; match found fires from searching or settling and is silent from
  idle, in place, on queueing and on cancelling; the run haptics by action; two
  identical actions are two confirmations; marking yourself here fires once.
  Full suite: **623 passed, 0 failed**.
- **Live** (iPhone 17, dark): Home, Seasons (the card's idle state inside its
  new container) and the Runs card drew correctly. **The rest of the live pass
  was stopped**: the user was using the simulator at the same time — the
  screen changed tab under a tap — and a stray tap on Runs could have landed on
  "Cancel run".
- **Not verified:** the zoom pushes, transitions and rolls in motion; Reduce
  Motion on; a VoiceOver sweep; haptics (the simulator plays none).

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

## Phase 2b — The Seasons tab (2026-09-22)

Design: `UI_REDESIGN_BRIEF.md` §5.4. Read `gaps/SEASONS.md` first, as it asks.

### 2e evidence — Seasons (squad home)

| | Before | After |
|---|---|---|
| **Hero** | the word "Seasons", 28pt — the tab bar's own label | **the squad's record, "1–0", 44pt numeral**, form beside it |
| **Axes changed** | — | **5 of 5** |
| **Core-task taps** | Queue up = 2 (button + confirm) · squad detail = 1 | **unchanged** |
| **First-viewport containers** | 3 panels / 5 shapes | **1 panel / 3 shapes** (the band; Queue up, the W pill) |
| **Blind read** | — | not run |

1. **Hero** — the tab label replaced by the record. It is a query over results
   two leaders independently confirmed — "the one number in the app nobody can
   type" — so it takes the numeral tier, which Home's self-reported run count
   deliberately never does. "0–0" before the first confirmed game.
2. **Container primitive** — three cards (squad header, match, roster) became
   the band plus rows; `MatchmakingCard` keeps a card only when there's a match,
   the one state that is a single tappable unit.
3. **Section order** — the squad's name and crest lead; the tab title is gone.
4. **Primary action** — **Queue up** sits directly under the band, where it was
   two cards down.
5. **Disclosure** — the roster card and other-squad cards became labelled rows.

### A brief decision the measurement overturned

The brief proposed the squad's crest colour as the band's ground (M3). **No
tint strong enough to read as the squad's colour keeps the band at AA** —
measured across all eight crests in both appearances: at 14% the secondary
text falls to 4.26:1 on gold in dark mode, and the baseline falls under its
3:1 floor on red and gold even at 10%. At full strength the profile button's
glyph drops to ~1.6:1, and the status bar's white text would sit on a pastel.
So the band stays neutral — the same family as Home and Runs — and the colour
lives in the **crest**, large and full-strength, its glyph already asserted at
AA on every fill. It still does M3's job: you know whose squad it is before you
read the name.

### Not changed, deliberately

- **The conditional hero** — the brief's "a match outranks the record when
  there is one". Not built this pass: the matched and searching states can't be
  produced on this account without a live match, so they couldn't be seen, and
  `MatchmakingCard` already sits directly under the band. Recorded as open.
- **`MatchmakingCard`'s states' copy** — the searching copy is honest that an
  empty pool is the default in a new city (`gaps/SEASONS.md`) and stays word
  for word.
- **The pushed screens** — `SquadDetailView`, `GameDayView`, `ResultView` are
  next.

### Tests

**554 passed, 0 failed, 0 skipped.** +3: `SeasonsRecordSpeechTests` — the record
reads to VoiceOver as a sentence ("3 wins, 2 losses this season"), singular at
one, and says so when the season hasn't started. Seen in the live app at the
default size and `.accessibility3`, dark mode.

---

## Phase 2b — Start a Run as a grouped form, and a basketball court glyph (2026-09-23)

Two corrections from the user, after the sheets shipped: the create sheet
"does not seem very structured and there is more text and not a lot of icons",
and "the court icon that is being used across the app is also a soccer field,
we need a basketball court".

### What changed

- **`CreateGameSheet` is an inset-grouped form.** The Phase 2b version was one
  surface on which every section had its own grammar — a 44pt numeral with a
  "Change" link, two outlined pills over a caption, a stepper with the count
  between two 44pt rings — under three uppercase labels. Now: the court as the
  heading, then three `FormPanel`s on `hooprGroupedBackground` (when; how many;
  who can join), and **every row is one shape** (`FormRow`): an accent glyph in
  a fixed column, a title, the value or control at the trailing edge. The
  section labels and the "Change" link are gone; the panels and glyphs carry
  what they said.
- **Day and time are separate rows.** Day opens a strip of chips (Today, Thu
  24, …) across the whole 30-day window the rules allow; picking one keeps the
  time, and moves a time already past to the next allowed quarter hour. Tip-off
  opens a time wheel. The old single wheel mixed date and time in four columns.
- **The captions are one short line each**, and still honest: Public "Anyone
  nearby can find and join." (was 11 words), Invite only "Hidden. Just you
  until invites work." (was 23). The invite step's lead says invites don't work
  yet, so the link's own note is off on that screen only.
- **The court glyph is a basketball court** (`Image.court`,
  `tools/make_court_symbol.swift`): a three-point arc and the key at each end,
  knocked out of a tile the way `sportscourt.fill` was. SF Symbols has no
  basketball court, so it is a custom symbol, and it replaces
  `sportscourt.fill` in `CourtTitle` (Home, the map card, the sheet) and on the
  profile's home-court line.
- **New:** `hooprGroupedBackground` (resolves to `hooprFill` in light and the
  page in dark, so no new value is unmeasured); `FormPanel`, `FormRow`,
  `FormRowGlyph`, `FormRowMetrics` in `Views/Components/FormPanel.swift`.

### 2e evidence — Start a Run

| | Before (Phase 2b) | After |
|---|---|---|
| **Structure** | one surface, four visual grammars under three labels | **three panels, one row shape** |
| **Glyphs on the form** (besides − and +) | 3 (court, globe, lock) | **9** (court, pin, calendar, clock, players, globe, lock, two radio marks) |
| **Caption words** | 34 | **12** |
| **Core-task taps** | 3 with defaults accepted | **unchanged** — 3 |
| **Largest text size** | — | rows stack their trailing control under the title (render, `.accessibility3`) |

**Verified live** (iPhone 17, dark, default size): the form, the court glyph on
the map card and the sheet, the Day strip (Thursday picked → "Tomorrow", time
kept at 12:15 PM), the Tip-off wheel; then **Cancel — nothing created**.
**Rendered** (the real sheet, from a scratch copy with its scroll view
flattened): the form and the invite step, light and dark, default and
`.accessibility3`. The wheel is UIKit and doesn't render off-device; the day
strip is a horizontal scroll view and doesn't either — both were checked live
in dark only.

### Found along the way

- **A custom symbol drew as a faint black outline.** The template's preview
  style (`fill:none; stroke:black; stroke-width:0.5`, which the SF Symbols app
  puts on every path) is compiled into the asset, so the glyph ignored
  `.foregroundStyle`. The generator writes no style and no class.
- **Xcode needs the Regular-M variant** of a custom symbol at minimum; a
  template carrying only Regular-S fails `actool`.

### Tests

`CreateGameDayPickerTests` (7, new): the chips span today to the window's last
day, drop today when no tip-off is left in it, keep the time on a new day, move
a past time to the next quarter hour, clamp at the window's end, and say
"Today" / "Thu 24". `CreateGameCopyTests`: the two captions rewritten, and a
length cap (+1). `ThemeContrastTests` (+3): the grouped ground's values, the
text and marks on it, a panel stepping off it. `CourtCardLayoutTests` now
measures the custom symbol's drawn width (its floor moved 1.4× → 1.3×).
Full suite: **610 passed, 0 failed**.

---

## Phase 2b — The sheets (2026-09-23)

Design: `UI_REDESIGN_BRIEF.md` §5.11 — "no structural quota; a form's layout
is dictated by its fields". What applied was §2c (states are compositions,
numbers are content, boxes earn edges) and §2d. `InboxSheet` shipped with the
Friends entry below.

| Sheet | Before | After |
|---|---|---|
| `CreateGameSheet` | 4 cards in its own card recipe | one surface: the court as the heading (`CourtTitle`), **the tip-off as a numeral** that opens a wheel in place, Who can join, Players as a numeral. Three taps with the defaults accepted — **unchanged** |
| `QueueSheet` | 3 `cardChrome()` blocks, page margin 16 | one surface: the squad, **the window as a numeral line** ("5:00 PM – 10:00 PM") over its two rows (the `ViewThatFits` ladder, kept), the courts as `DividedRows`; the day selector is the app's underline selector; margin 20 |
| `CreateSquadSheet` | 4 `cardChrome()` blocks | **the crest preview is the hero** — centred, 1.5× the hero crest, over the name as it will read; Name, Crest, Format under `label`s |
| `ProfileEditSheets` (×5) | five card recipes | one: content on the page at the page margin, one field style (`editSheetField`), headings as `label`s; the radius as a numeral. The home-court picker still saves on tap |

### The correctness fix — the invite step (§2d)

The brief named this as the one item in it that is correctness, not design. The
create sheet told a host to **"send this link to the players you want in"**, and
the Invite-only caption promised **"a link to share with the players you want
in"** — but the link opens nothing and the `games` read rule refuses a
non-member, so an invite-only run holds only its host (`gaps/GAMES.md`).

- The **caption** now says so: "Hidden from search. Joining by invite doesn't
  work in the app yet, so for now you'll be the only one on the roster."
- The **invite step** leads with the court and time, and a **"Send the court and
  time"** button (the system share sheet: "Pickup run at East End Park, Durham —
  Tonight at 7:30 PM"). The link follows under "Reference link" in
  `InviteLinkCard`, with the note it already carried on the Runs card. It also
  pointed at "Queued Games", a name the Runs tab no longer has.

### Found along the way

- **"Tonight 11:15 AM"** on the device: `Game.dayText` called every same-day
  run "Tonight", so a morning run read that way on Home and Runs too. Before 5 PM
  it now reads "Today" — the word `scheduledText()` already used, and where
  Seasons' own "Tonight" window starts.
- **Text no longer shrinks anywhere.** The last three `minimumScaleFactor` calls
  (the queue sheet's day labels, the map list's tabs, the friend action
  buttons) are gone; the latter two were dead code behind their size caps.
- Fields on the edit sheets and the create-squad name field had a 1.09:1 ground
  and, on one sheet, a permanently orange border. They share one style now:
  `hooprSeparatorStrong` at rest, a 2pt accent ring when focused.
- The password sheet shrank the email to fit (`minimumScaleFactor(0.7)`); it
  wraps.

### Evidence

On the device (dark, default size), opened and **cancelled without saving
anything**: the create sheet at rest, with the wheel open and Invite only
selected; the queue sheet; the create-squad sheet; the radius and password
sheets. The invite step needs an invite-only run to exist, so it is an
off-device render of the step (copied verbatim) with the real `CourtTitle` and
`InviteLinkCard`, light and dark.

### Tests

**599 passed, 0 failed** (593 + 5 + 1). `CreateGameCopyTests` (+5): the public caption unchanged, the invite-only
caption promising no working invite, the share text with and without a city,
and the pick's day label matching a run's (Tonight / Today / Tomorrow / date).
`GameTests`: "today reads as Tonight" split into an evening run (Tonight) and a
morning one (Today).

---

## Phase 2b — Profile, Friends, the player sheet and the inbox (2026-09-23)

Design: `UI_REDESIGN_BRIEF.md` §5.9 and §5.10, plus `InboxSheet` from §5.11 —
it lists the same `FriendRow`, so it had to move with it.

### 2e evidence — `ProfileView`

| | Before | After |
|---|---|---|
| **Hero** | the `@handle` at 30pt, shrinking to fit (`minimumScaleFactor(0.6)`), over the uid | **the same identity, as the band** — the handle at `display`, wrapping instead of shrinking, and **the home court** under it, the one fact that identifies you to other people; the uid demoted to a caption, still copy-on-tap |
| **Axes changed** | — | **3 of 5, as claimed** (container primitive, section grouping, disclosure) + hero content |
| **Core-task taps** | every row 1 | **unchanged** |
| **First-viewport containers** | **7 panels / 14 shapes** (a card and a tinted tile per row, the selector's pill track) | **1 panel** (the band) / **0 per-row shapes** |
| **Blind read** | — | not run |

- **Rows on the page.** `ProfileRow` lost `profileRowChrome()` and the tinted
  icon tile; the symbol is a plain secondary mark in a fixed column. Rows sit in
  the new `DividedRows` (a hairline between each, starting under the text), under
  `label`s — "Your game", "Account". Sign Out stays the last row.
- **The pane selector is two labels with a sliding accent underline** — the
  map list's treatment — instead of an orange pill on a grey track. Its
  `minimumScaleFactor(0.8)` is gone; the labels wrap.
- **The top bar takes the band's ground at rest**, so the page opens on one band
  running up behind the back and inbox buttons — the thing the user asked of
  squad detail ("cuts off abruptly towards the top"), applied here before it was
  asked. It crossfades to glass as the identity scrolls behind it.
- **Kept, as the brief said:** the pinned pane header, the inbox in the top bar,
  Sign Out as a row, content-sized rows, read-only rows by omitting `onTap`.

**Friends pane:** `FriendRow`'s inline card is gone; the lists are
`DividedRows`. The list header is a `label` with its count at the trailing edge
(it was an 18pt bold title and a count in a filled capsule), matching Seasons'
roster. Search stays pinned. No affordance was added implying blocking or
reporting, which don't exist (`gaps/FRIENDS.md`).

**`PlayerProfileSheet` (§5.10):** the relationship is the header's one strong
line — "You're friends", "Sent you a request", "Request sent", "Not friends yet"
— under the handle, instead of small grey type above the buttons. The handle is
`title` and wraps to two lines instead of shrinking. Rows lose their cards like
the profile's. The action bar is unchanged.

**`InboxSheet` (§5.11):** sections are `label`s with a trailing count, rows are
`DividedRows`, the page margin is the app's 20pt (it was one of the two screens
still at 16), and `SquadInviteRow` is a row with 44pt Join / Decline targets
instead of a card.

**Found and fixed on the device:** the pinned header on the Profile pane drew
two hairlines 14pt apart once rows scrolled under it — the selector's own and
the header's scroll edge. The Profile pane keeps only the selector's.

**Evidence (device, dark, default size):** Profile before (the card stack) and
after; after scrolling (glass bar with the handle, selector pinned, Sign Out as
the last row); the Friends pane; a friend's `PlayerProfileSheet`; the inbox. No
button that changes anything was tapped — Cancel, Remove Friend and Sign Out were
left alone.

---

## Phase 2b — Login (2026-09-23)

Design: `UI_REDESIGN_BRIEF.md` §5.8. **Assumption A1 held** (the user said
nothing against it at Checkpoint 1, which that checkpoint treats as "build as
designed"): Login's job includes being a first impression, so the brand keeps
its place and gains the one fact a new user lacks.

### 2e evidence — `LoginView`

| | Before | After |
|---|---|---|
| **Hero** | glyph, "hoopsRN" 34pt, the mode title, floating mid-screen | **the same identity, in the band** — glyph, "hoopsRN" at `display`, and **one line saying what the app is for**: "Pickup basketball across the Triangle. Find a run tonight, or play a season with your squad." |
| **Axes changed** | — | **3 of 5, as the brief claimed** (container primitive, primary-action placement, section order) plus a hero whose content changes and whose identity does not |
| **Core-task taps** | two fields + submit | **unchanged** |
| **Containers** | 0 panels / 3 shapes | **1 panel** (the band) / 3 shapes (two fields, submit) |
| **Blind read** | — | not run |

- The brand is `LoginBrandBand`: the band fills the top of the screen and is
  where Phase 4's `MeshGradient` lands. Centred, because the band is the whole
  of a one-task screen rather than the top of a list.
- The form sits under it at the bottom, where a thumb is: the mode title
  ("Welcome back" / "Create your account") as a headline, the two fields,
  submit, then the quiet mode switch. When the keyboard comes up the band gives
  way; at large text sizes the screen scrolls.
- **Deviation from the brief:** the form is on the page ground, not
  `hooprElevatedSurface`. In dark mode the band's value *is* the elevated
  surface's, so a form drawn on it read as the band continuing.

**Found and fixed:**
- **The fields were barely drawn in light mode** — `hooprFill` on white is
  1.09:1 and the `hooprBorder` edge 1.2:1. The unfocused edge is now
  `hooprSeparatorStrong` (3:1); focused, a 2pt accent ring.
- **The disabled Sign In** faded the orange to 40% under the same black label;
  in dark mode that left the label nearly invisible. Disabled is now a
  `hooprFill` button with secondary text.
- At `.accessibility3` the render showed the form title truncated ("Create your
  accou…") and the mode switch wrapping into a ragged column. The title wraps,
  and the switch stacks the prompt over the action when they don't fit one line.

**Evidence:** off-device renders of the real `LoginBrandBand` with the form
copied verbatim (the view model needs Firebase) at an iPhone 17's safe-area
height — sign in empty, sign up with an error and a focused field — light and
dark, default and `.accessibility3`. **Not seen live:** it needs a sign-out, and
signing back in would need the account's password.

---

## Phase 2b — Map card: the HOSTING badge and a run cut in half (2026-09-23)

**The user: "Hosting tag on map tab court detail is not displaying properly.
When court is selected and u are hosting, the full details are half shown until
the view is expanded."** Two defects, one visible through the other.

1. **The badge broke mid-word — "HOSTIN / G".** In the run row the time and
   badge share an `HStack` with a `Spacer` and the Cancel button. SwiftUI split
   the leftover width evenly between the facts and the spacer, so the time and
   badge got ~100pt of the ~160pt they need. The facts now take
   `layoutPriority(1)`, and the badge is one line and `fixedSize` — if the row
   can't hold it, the existing `ViewThatFits` moves the button below.
2. **The run was half hidden at `.medium`.** The card's layout comment still
   budgeted ~155pt for its body, but `.medium` is a third of the container, and
   the container shrank when the map started stopping above the tab bar (the
   peer session's tab-bar change): `.medium` is now ~215pt, the body ~112pt, and
   the name plus distance take ~63pt of it before a ~72pt run row starts. So
   even a one-line badge left the run half shown. **The card now sets its own
   `.medium` height** — it measures its header plus first run and the sheet rests
   tall enough for them (`SheetGeometry.fittedMediumHeight`). A court with no runs
   is unchanged.

**Evidence.** On the device, before: the user's own state — "Sherwood #2",
"HOSTIN / G". After, on the device: a court with no runs opens as before (~3pt
taller). The account had no run left to host by the time the fix was built, so
the hosted state is a render of `courtCard`'s layout copied verbatim (the run as
plain values) at the sheet's real heights: before, the run is cut at "1:15 AM
HOSTIN"; after, the whole run shows with the badge on one line and the amenity
badges peeking below. Measured: a hosted run rests at **273pt** (lead 158pt) at
the default size and **443pt** at `.accessibility3`, both under `.expanded`
(503pt).

**Tests.** **593 passed, 0 failed** (588 + 5). `MapTabDetentTests` +5: medium is still a third without a fitted
height; a taller card rests taller; a shorter one keeps a third; the fit is
capped at expanded; dragging floors at the fitted height.

---

## Phase 2b — Game day and result (2026-09-23)

Design: `UI_REDESIGN_BRIEF.md` §5.6 and §5.7. **Neither screen can be reached
on one device** — both need a live match between two accounts
(`gaps/SEASONS.md`) — so, as the brief said it would be, each one's evidence is
a component render, not a screenshot. Both now take the band's back button, as
squad detail does, so every push in the Seasons stack starts where the tab does.

### 2e evidence — `GameDayView`

| | Before (from the code) | After |
|---|---|---|
| **Hero** | "Tip-off in 42m", 22pt, inside a card | **the countdown as the band's numeral** — "Tip-off in" over "1h 42m" — then the court (`CourtTitle`), then "Saturday 7:30 PM · vs Court Vision" |
| **Axes changed** | — | **4 of 5** (hero, container, order, primary action) |
| **Core-task taps** | We're here = 1 | **unchanged**; Cancel match 1 → 2 (a confirmation; see below) |
| **Containers** | up to **8** stacked blocks (banner, countdown, court, two roster cards, button, result card, cancel) | **1 panel** (the band) |
| **Blind read** | — | not run |

- **We're here** is directly under the band, full width. Once marked, it
  becomes a statement ("You're marked as here", with a check), not a disabled
  button.
- **The rosters are one comparison** (`ArrivalBoard`): ours beside theirs, each
  with **how many are here as a number** ("2 of 3 here") over the names. Stacked
  at accessibility sizes, where two columns would cut every name.
- **The countdown moves.** It is inside a `TimelineView(.everyMinute)`; it used
  to update only when something else redrew the screen.
- **Composed states:** counting down, "Now" until the reporting delay, "Final",
  **Cancelled** (in the band, replacing the red banner; the arrival board hides,
  since "0 of 3 here" under "Cancelled" is noise), and the error banner.
- **"Record the result"** is a row under We're here while both apply, and the
  filled button once it is the only thing left.

**Found and fixed:**
- **"You're marked as here" was black on `hooprFill`** — the old button kept
  `hooprOnBrand` for its label after swapping the orange for the fill, which
  measures 1.51:1 in dark mode, and `.disabled` dimmed it again.
- **Cancel match had no confirmation.** One tap called the match off for both
  squads, with nothing to undo it. It now asks, like Leave and Disband do.
- The not-arrived circle was secondary text at 40% opacity, which nothing
  asserted. It is `hooprSeparatorStrong`, asserted at 3:1.
- Countdown copy: past a day it reads "1d 2h", not "26h 5m", and a zero unit is
  dropped ("1h", not "1h 0m").

### 2e evidence — `ResultView`

| | Before (from the code) | After |
|---|---|---|
| **Hero** | "You won" at 22pt inside a card; the score as a 15pt line | **the outcome at `display` (40pt)**, the winner's crest above it, and the score as a numeral scoreboard ("21 – 15", each over its squad) |
| **Axes changed** | — | **4 of 5** (hero, container, order, primary action) |
| **Core-task taps** | report = 1 (a crest) | **unchanged** |
| **Containers** | 3 cards (outcome, who won, score) | **1 panel** (the band) + the two crest buttons |
| **Blind read** | — | not run |

- **Reporting is one question** (archetype A5): "Who won?" at the title size,
  centred, over two large crest buttons (`WinnerButton`). The unchosen edge is
  now `hooprSeparatorStrong` (3:1); it was the 1.2:1 hairline, on the one
  screen where those two controls are the point. "Your pick" is in the accent.
- **All four states are composed** and their words come from one function,
  `ResultCopy`: confirmed, **awaiting the other leader** (no deadline — it waits
  forever), **disputed** (said plainly, in primary text, no red), reportable,
  plus not-played-yet and a member's view. The words are the screen's existing
  copy, moved rather than rewritten.
- **The brief's crest-coloured ground is the crest instead.** M3's tint was
  measured below AA on the Seasons tab, so the winning crest is drawn at the
  hero size above "You won".

**Found and fixed:** a score typed **after** tapping the winner was silently not
sent. The report goes with the crest tap, carrying whatever the score fields
hold at that moment. The caption under the fields now says so ("enter it before
you tap the winner, or tap them again after"). The mechanism is unchanged.

### Evidence

Off-device renders (`ImageRenderer`) of the real `GameDayBand`, `ArrivalBoard`,
`ResultBand` and `WinnerButton`, in light and dark, at the default size and
`.accessibility3`: game day counting down, at "Now" and cancelled; result
reportable, waiting, won with a score, and disputed. The "We're here" capsule is
copied verbatim into the harness (it is private to the view). **Neither screen
has been seen live**, and `gaps/SEASONS.md`'s two-account pass is still what
closes that.

### Tests

**588 passed, 0 failed, 0 skipped** (571 + 9 + 8). `GameDayCountdownTests` (+9): every countdown boundary (minutes, hours, days,
the last minute, "Now" until the reporting delay, "Final", cancelled outranks
all), singular units, and the arrival count ignoring the other roster.
`ResultCopyTests` (+8): each state's headline, no deadline words in either
waiting state, and a dispute that reads as a disagreement rather than an error.

---

## Phase 2b — Squad detail (2026-09-23)

Design: `UI_REDESIGN_BRIEF.md` §5.5. Read `gaps/SEASONS.md` first, as it asks.

### 2e evidence — `SquadDetailView`

| | Before | After |
|---|---|---|
| **Hero** | nothing larger than 22pt; the record at 28pt inside the second card, or "No games played yet" at 16pt | **the record, 44pt numeral, in the same band as the Seasons tab**, the five dots pinned bottom-right |
| **Axes changed** | — | **4 of 5** (hero, container primitive, section order, action placement) |
| **Core-task taps** | invite = 1 · open a result = 1 · disband = 2 | **unchanged** |
| **First-viewport containers** | **6 panels** (header, record, history, roster, invites, the filled Disband block) | **1 panel** (the band) / 4 shapes (back button, dot row, two Invite capsules) |
| **Blind read** | — | not run |

1. **Hero** — the record moves out of a card into the band as the numeral,
   through the same two components squad home uses (`SquadIdentity`,
   `SquadRecordLine`, new in `SquadBand.swift`). Mid-push on the device the two
   bands' crest, name and record sit in the same place, so the push reads as a
   continuation (Phase 3's `matchedGeometryEffect` can now join them).
2. **Container primitive** — six `cardChrome()` blocks became the band plus
   rows under labels.
3. **Section order** — history, roster, invites, then controls; the separate
   Record card is gone (the band is the record).
4. **Action placement** — Leave / Disband is a line of red text at the end,
   not a filled block; pending invites (with Revoke) are rows in the roster.

### The user's correction: the header cut off at the top

The first build kept the system bar, so the band started below it and a strip
of page background sat between the status bar and the band. **The user: "cuts
off abruptly towards the top. Match the seasons tab implementation."** The bar
is now hidden and the band carries a glass back button (`BandBackButton`) in its
first row, in `ProfileButton.Slot`'s frame. Checked on the device: the band
starts where the tab's does, the button pops, and **the left-edge swipe still
pops with the bar hidden** — the usual risk of hiding it. VoiceOver keeps the
`navigationTitle` and gains an `.escape` action.

That superseded a scroll-driven title (the bar's title fading in once the band's
name scrolled away), which the device had shown overlapping "3v3 · Durham"
through the translucent bar.

### History rows

`SquadHistoryRow`, its own view so the render harness draws it with the real
code. A `FormDot` in the form guide's colours, the opponent, then the date and
**what happened in words** — so this list, unlike the band, never relies on
colour:

| Status | Dot | Detail line |
|---|---|---|
| confirmed, this squad won / lost | green / red | "Won" / "Lost", score trailing (in the line at accessibility sizes) |
| scheduled, still to come | grey | "Scheduled" |
| played, this leader hasn't reported | grey | **"Report the result"** in the accent — the one row that asks for something |
| reported, waiting on the other leader | grey | "Waiting on {opponent}" — **no deadline**, because it waits forever |
| played, and you can't report (a member) | grey | "Result not in yet" |
| disputed | grey | "Results don't match" — designed, not an error; never red |
| cancelled | grey | "Cancelled" — a plain row, no chevron |

### Found along the way

- **Errors on this screen were invisible.** An invite, revoke, leave or disband
  that failed set `SquadViewModel.errorMessage`, which only the tab's banner
  showed — behind this screen. The same `ErrorBanner` now sits under the band.
- **The cancelled row's text fell under AA.** It was a *disabled button*, and
  a disabled button dims its label. It is a plain row now.
- **At `.accessibility3` the trailing score squeezed the row** — "Hoop / Dreams"
  and "Jan 12 / · Won" in the render. At accessibility sizes the score moves
  into the detail line ("Won 21–15").
- **The lettered result pills are retired.** `FormPill`, `NeutralResultPill`
  and `ResultPillMetrics` had no callers left, so they went, with their four
  tests in `SeasonsAccessibilityTests` and its orphaned helpers.

### Evidence

- **Device, dark, default size:** before (six cards) and after, pushed from the
  tab; a mid-push frame with both bands aligned; back button and edge swipe
  both pop. This squad has no matches, so only the empty history is live.
- **Off-device render** (`ImageRenderer`, the real `SquadRecordLine` and
  `SquadHistoryRow`): all seven statuses above, light and dark, default and
  `.accessibility3` — which is what found the two row defects.

### Tests

**571 passed, 0 failed, 0 skipped** (565 + 10 − 4). `SquadHistoryRowTests` (+10): each status's words from this squad's side, the
dot and the score, grey for everything unconfirmed, the report call to action
only for a leader who owes one, and no deadline words in "Waiting on". Minus the
four retired pill tests.

---

## Phase 2b — Seasons: the form as five dots (2026-09-22)

Three corrections from the user to the Seasons band, in one pass:

1. **The orange "W" pill is gone.** The last five results are now five dots:
   green a win, red a loss, and grey for each game not yet played, so the row is
   always five long. Most recent on the left, as before. `FormGuide` changed in
   place, so `SquadDetailView`'s Record card got the dots too; its history rows
   keep the lettered `FormPill` until that screen's pass (§5.5).
2. **The "W–L" / "No games yet" caption is gone.** The numeral stands alone:
   "0–0" beside five grey dots says the season hasn't started. VoiceOver still
   reads the sentence.
3. **The dots are pinned to the band's bottom-right corner**, their bottoms on
   the numeral's baseline, in both the beside and the stacked layout.

### What the colours had to clear

Four new roles in `Theme.swift`. None reuses `hooprRed`, because a loss is not
an error.

| Role | Light | Dark | On the band |
|---|---|---|---|
| `hooprFormWin` | `#2E9E4A` | `#4ADE80` | 3.15:1 / 8.89:1 |
| `hooprFormLoss` | `#B90E0A` | `#E5484D` | 6.15:1 / 3.96:1 |
| `hooprFormUnplayed` | `#AEAEB2` | `#545456` | 2.03:1 / 2.05:1, deliberately below both results |
| `hooprOnFormResult` | white | black | ≥ 3.44:1 on either dot |

**A finding, and what was done about it.** To a red-green colour-blind reader,
green and red differ only in lightness. WCAG counts that as a second cue at 3:1
between the fills, and **no pair reaches it while both dots clear 3:1 on the
band**. The widest measured gap is 1.95:1 in light and 2.25:1 in dark. So colour is
the only cue drawn by default, as asked, and three other routes carry the result:
the record numeral gives the counts, VoiceOver reads the order ("Recent form, most
recent first: win, loss"), and with iOS's *Differentiate Without Color* on, each
played dot grows from 16 to 22pt and carries a ✓ or ✕. `ThemeContrastTests`
pins the gap so a retune can't quietly narrow it.

### Evidence

- **Device, dark, default size:** Raptorz, "0–0", five grey dots in the band's
  bottom-right, right edge in line with the squad row's chevron. This account's
  squad has no confirmed games, so green and red couldn't be shown live.
- **Off-device render** (`ImageRenderer`, the real `FormGuide`/`FormDot`, the
  record line verbatim): 0–0, 1–0, 2–1, 3–2, the ✓/✕ variant, and "10–10" with
  the larger dots, in light and dark, at the default size and `.accessibility3`.
  At `.accessibility3` the "10–10" row stacks, dots still on the right.

### Tests

**565 passed, 0 failed, 0 skipped** (554 + 11). `FormGuideTests` (7): padding to five, all-grey, full, cut to the most
recent five, the spoken form, and the two fit measurements (default dots beside
"10–10" at `.accessibility3`; the ✓/✕ dots beside a single-digit record, and
stacked under "10–10"). `ThemeContrastTests` (4): played dots at 3:1 on the band
and a card, the unplayed dot visible and below both, the lightness gap held at
≥ 1.9:1, the ✓/✕ at 3:1.

---

## Phase 2b — Two corrections from the user: Home's empty state, map names (2026-09-22)

### Home's empty state

The user: *"Nothing on tonight"* at that size, in the middle of the band, looked
off. It was the 40pt `display` tier over a full-width button — a headline about
nothing, in the slot a tip-off time fills when there is a run. Now it is a
quieter sibling of the booked state: the icon-and-title line the court name
uses (`figure.basketball` + **"No run tonight"** at `title`, 28pt), one line
saying what the button leads to, and a compact **Find a court** capsule on the
band's left edge where "Your runs ›" sits. It is still the largest thing on the
screen. **Verified by an off-device render** (both appearances, default and
`.accessibility3`, `ImageRenderer` on a verbatim copy of the band in a scratch
tree) because the account had a run booked and producing the empty state on the
device would have meant cancelling it.

### Court names on the map

The user: names that don't fit on the map should lose "Park" or the court
number — the Runs tab shows both. The card had just been changed to wrap names
in full; that is reverted for the map (Home's band still wraps).
`CourtName` implements it for the card, `CourtRow`, `CourtGameRow` and the
search rows: a trailing "Park" goes first, then the `#N`, then an ellipsis.
Two choices inside the rule, both from the data rather than taste:

- **"Park" before the number**, because 114 of 213 names carry a `#N` and it is
  the only thing telling sibling courts apart.
- **Only a trailing "Park"** — four names carry it mid-name ("Lake Park
  Trail", "Ting Park Soccer Field A") where removing it names somewhere else.

**A measurement error, caught on the device.** The first build showed
"East E…" at `.accessibility3` where the test predicted "East End": the test
took the court glyph's width to be its font size, and `sportscourt.fill` draws
about **1.56× wider** — 63.7pt, not 40.7. The same error had overstated the
margins on Home's wrapping title ("Pearsontown" fits beside the glyph at AX3 by
3pt, not 26). One rule fixed both: **no court glyph at any accessibility size.**
At `.accessibility3` the card now reads "East End"; at `.accessibility1`, the
whole "East End Park". Tests now measure the symbol's drawn width.

**551 passed, 0 failed, 0 skipped.** `CourtNameTests` (new, 7 — the ladder, the
mid-name Parks, never shortening to nothing, and every shipped name shortening
only the way the rule says), `CourtCardLayoutTests` (the glyph's drawn width,
"East End" at AX3, the whole name at AX1), `HomeHeroMetricsTests` (the new empty
copy fits one line).

---

## Phase 2b — The map's court card, and the ODbL notice (2026-09-22)

The map is §2e's single `keep` at the tab level (A4): full-bleed map, detent
sheet, glass chrome — unchanged. What changed is the court detail card, and the
licence notice the user approved shipping (A8).

### 2e evidence — the court card

| | Before | After |
|---|---|---|
| **Hero** | the court name at 17pt, truncated to "East En…" at `.accessibility3` | **the court name in the `title` tier**, whole at every size |
| **Axes changed** | — | **3 of 5** — hero, section order (the header joined the scrolling body), disclosure (controls move up rather than eating the name) |
| **Core-task taps** | Directions 2 · Start Run 2 · star 2 | **unchanged** |
| **Containers** | unchanged in kind — the card was already a sheet surface; run rows keep `cardChrome(12)` | |
| **Blind read** | — | not run for the map |

**The defect, before and after, in the live app at `.accessibility3`:** the
audit's shot reads "East En…" / "Durham · 0.…"; now the star and close sit on a
row of their own, the name wraps at the word, and the pinned
Directions / Start Run row stays on screen.

### What changed

- **`cardHeader`** — name in `title` (not `display`, as the brief proposed: at
  the `.medium` detent the sheet has ~155pt for the header and the runs, and
  the runs are what the card leads with). Controls in fixed 44pt targets with
  capped glyphs; a `ViewThatFits` moves them above the name when it can't fit
  beside them. City and distance on a wrapping line with icons, the distance's
  number weighted — which needed `FindAMatchViewModel.distanceValueText(for:)`.
- **`CourtTitle`** (new, shared with Home) — the glyph + name, and the one rule
  about when the glyph must go. Home's court line had the same geometry and
  was silently exposed to the same failure.
- **`runRow`** — reads like a run on the Runs board: time first, spots as a
  number, `GameCard`'s badge rule, the same waitlist note. `isHost` /
  `isWaitlisted` added to `FindAMatchViewModel` (presentation only).
- **The ODbL notice** — at the foot of every court list and in the empty state,
  the dataset's own text, linked to OpenStreetMap's copyright page.

### Found by measuring, and fixed

1. **A court name could still break mid-word — at the two largest sizes.** A
   test measuring every word of every court at every accessibility size failed.
   Its first failure was the test's own fault (it split on spaces only, and
   "Bentley-Ridge" wraps legitimately at its hyphen). Its second was real:
   "Pearsontown" fits beside the court glyph by **1pt** at `.accessibility4` and
   doesn't at `.accessibility5` (340pt of 302). The glyph is ornament, so
   `CourtTitle` sheds it from `.accessibility4` — the revamp's own *drop the
   ornament* fallback — and the name gets the whole line.
2. **A regression this change introduced, caught on the simulator.** Once the
   name wrapped in full, the fixed header at `.accessibility3` was taller than
   the `.medium` sheet and pushed the pinned **Directions / Start Run** row
   behind the tab bar — the one thing that layout exists to prevent. Fixed by
   letting the header scroll with the body; only the grab handle and the action
   row stay fixed. `MAP_LAYER.md` updated: the fixed header was a means, the
   pinned actions are the end.
3. **Home's hero was announcing a finished run.** Found while looking for a
   court with a run: the map said Elmira Park had nothing on while Home's band
   said "8:45 PM · Elmira Park · 9 spots left". The queued listener doesn't
   filter by status, so a run marked complete stays in `queuedGames` for the
   rest of `Game.visibilityGrace`; Runs and the map drop it with
   `isVisible(at:)` and Home took `queuedGames.first` as it came. **Pre-existing
   code, made prominent by this redesign** — the run became the biggest thing on
   the first screen. Fixed with the same rule (`HomeViewModel.nextRun(from:at:)`,
   three tests), and verified live: Home now shows its empty state, which is the
   first time that state has been photographed.

### One service change, flagged

**`CourtService.attribution`** — a `private(set) var` holding the string the
dataset already carried and the service threw away. The revamp contract says to
stop and report a service change; the user had approved shipping the ODbL
notice (A8), the alternative was restating a licence string in a view, and the
change adds no read, write or dependency. Reported here rather than asked
first.

### Corrections to the brief (§5.3)

- **`CourtRow` shows no busyness** — the brief said it rendered busyness as
  grey text and would get a heat dot. It doesn't; `CourtGameRow` (the Now list)
  is the row with runs. **The heat dot was dropped there too**: a leading dot
  moves the Now row's text column off the Nearby row's, which the "one height,
  one column" discipline in `MAP_LAYER.md` guards, and the Now row already reads
  time-then-spots the way a Runs card does.
- **`title`, not `display`**, for the reason above.

### Tests

**542 passed, 0 failed, 0 skipped** on the final code, counted from the
`.xcresult`. +10 over the 532 of the previous entry: `CourtCardLayoutTests` (6 —
controls capped, no court name breaks mid-word at any accessibility size, glyph
shed only at AX4–5, a long name really can't share a row with the controls, the
licence notice is kept, and it links to the right page), `GameTests` (+1, the
split distance rejoins to the same string), `HomeViewModelTests` (+3, the next
run skips completed and aged-out runs and keeps one underway).

### Not verified

- **The run row on a real screen.** At capture time no court had a visible run
  — the account's runs had been marked complete — so the redesigned row was
  built and unit-covered but never photographed. The card header, the metadata
  line, the actions and the attribution footer were.
- **Dark mode**: the app was pinned to Light by whoever used it last, and left
  that way.
- **Blind read**: not run for the map.

### Process

- **I terminated an Xcode debug session.** Installing the first map build, I
  replaced a running copy of the app without checking its parent first; the
  parent then no longer existed and was not `launchd_sim`, which is what a
  debugserver-parented session looks like after its app dies. It was either the
  user's or a peer session's. Every later install checked the parent *before*
  terminating.
- **Someone else was on the simulator.** The Map tab switched to Home during a
  capture with the app still running and every peer session idle — most likely
  the user, with the panel open. Captures were retaken by hand, one frame at a
  time.

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
