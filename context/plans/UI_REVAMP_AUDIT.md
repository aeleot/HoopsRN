# Audit — UI Revamp, Phase 0

**Status:** complete — this is the baseline every later phase is judged against.
64 before-screenshots captured (§7.2); three run-populated states could not be
(§7.3, A9). **§9 records what Phase 1 changed** against these numbers; §§1–8 are
left as measured on 1a2710d.
**Drafted:** 2026-09-21 @ 1a2710d
**Covers:** every file under `hoopr/Views/`, plus `hoopr/Support/Theme.swift`,
`hoopr/Support/Typography.swift`, `hoopr/Support/Glass.swift`,
`hoopr/Support/CourtHeat.swift`

> `context/plans/` carries no `Scope`/`Verified` stamp and is not read by
> `tools/check_context_drift.py`. This file is a **measurement of the code as it
> stands on 1a2710d**, not a design. Nothing here proposes a change; §8 states
> what the measurements imply, and the design decisions they feed live in
> `UI_REDESIGN_BRIEF.md` (Phase 2a).

Phase 0 of `UI_REVAMP_PROMPT.md`, in the order that prompt asks for it:

| § | Deliverable | What it is |
|---|---|---|
| [§2](#2--component-map) | Component map | Every view file, what chrome it draws, and where it drifts from `CardChrome` |
| [§3](#3--colour-role-census) | Colour census | Every role each view file touches, counted |
| [§4](#4--spacing-census) | Spacing census | Every magic number in `Views/`, counted and clustered |
| [§5](#5--feature-purpose-ledger) | Feature purpose ledger | One row per user-facing feature — the baseline for 2c's "prominence follows utility" |
| [§6](#6--before-skeletons) | Before-skeletons | Every screen's top-level view tree, hero, and container count |
| [§7](#7--before-screenshots) | Before-screenshots | Where they live and what they show |

---

## 1 — How this was measured

- **Static counts** (§2–§4) come from `tools/`-style scanning of `hoopr/Views/`
  with comments stripped, so a ratio quoted in a doc comment can't inflate a
  count. The script is not committed — it is 60 lines of `re` over the view
  tree, and its output is reproduced below rather than its source.
- **Tap counts** (§5) are walked in the iPhone 17 simulator on iOS 26.5 and
  cross-checked against the call sites. A tap is a discrete touch that advances
  the task; typing is counted separately because it is not a tap and its cost
  is a different kind.
- **Container counts** (§6) are reported as **two** numbers, because one number
  hides the distinction that matters:
  - **Panels** — bordered, filled or shadowed rectangles that group *content*:
    cards, banners, sheet surfaces, segmented-control grounds. This is the
    number 2c's "no card in a card, no card per section by default" is about.
  - **Total shapes** — panels plus every filled or bordered control: buttons,
    chips, badge pills, count capsules, row icon tiles, field grounds. This is
    the visual-noise number.

  Both exclude data graphics (the capacity bar's track), avatars and crests
  (circles that *are* the content), and the system tab bar. Counted from the
  **light / default-text-size** screenshot, first screenful only, at the data
  state §7.3 records.
- **Screenshots** (§7) are `xcrun simctl io booted screenshot`, kept outside the
  repo. `hooprUITests` does not launch on this project (`CLAUDE.md`), so there is
  no automated capture.

Everything the docs did not settle is marked **assumption** and repeated in
§5.3, which is the list Checkpoint 1 has to answer.

---

## 2 — Component map

### 2.1 The chrome recipe, and its three copies

`CardChrome.swift` defines the app's card: `hooprSurface` fill, a 1pt
`hooprBorder` stroke, and a `hooprShadow(opacity: 0.06)` at radius 8, y+2. Its
own doc comment says it exists because a fifth hand-rolled copy "is well past
where a design system starts drifting."

**There are still three copies of that recipe, and they have already drifted:**

| Where | Radius | Corner style | Extras | Verdict |
|---|---|---|---|---|
| `Components/CardChrome.swift` `cardChrome(cornerRadius:)` | 16 (default) | sharp `RoundedRectangle` | — | the definition |
| `Profile/ProfileRow.swift` `profileRowChrome()` | 14 | **`.continuous`** | `.contentShape` | drifted: different radius *and* different corner geometry |
| `Friends/FriendRow.swift` (inline, lines 56–64) | 14 | sharp | — | drifted: different radius, and not a shared helper at all |

Same fill, same stroke, same shadow, three spellings. `FriendRow`'s is inline
and named nothing, so nothing points at it; `profileRowChrome()` at least has a
name and a reason (rows want a `contentShape` and the continuous curve), but the
reason is undocumented as a *departure*.

**A fourth, weaker family:** the "bordered fill" treatment — `hooprFill`
background plus a 1pt `hooprBorder` stroke, no shadow — used for secondary
controls. It appears in `GameCard.completeButton` (radius 10),
`InviteLinkCard` (radius 12), `ResultView.winnerButton` (radius 14, stroke
widens to 2 and turns `hooprOrange` when chosen), and
`CreateGameSheet.visibilityOption`. No component owns it.

**A fifth:** `MapTab`'s sheet draws its own surface —
`hooprShadow(opacity: 0.08)`, radius 12, y **−4** — because it lifts *upward*
rather than downward. That one is a genuine exception and should stay one; it is
listed so a later phase doesn't fold it in by accident.

### 2.2 What each file draws

`cc` = `cardChrome()` call sites, `gl` = `hooprGlass` call sites,
`sys` = `.font(.system(` (documented exceptions only), `msf` =
`minimumScaleFactor` uses.

| File | Lines | cc | gl | sys | msf | Chrome it draws |
|---|---:|---:|---:|---:|---:|---|
| `Components/CardChrome.swift` | 30 | — | — | — | — | **the definition** |
| `Components/CourtBadges.swift` | 106 | 0 | 0 | 0 | 0 | filled + outlined capsules |
| `Components/ErrorBanner.swift` | 75 | 0 | 0 | 0 | 0 | own recipe: `hooprRed.opacity(0.08)`, radius 10, no border |
| `Components/GlassChip.swift` | 36 | 0 | 1 | 0 | 0 | glass capsule (tinted when active) |
| `Components/HooprSearchField.swift` | 137 | 0 | 1 | 0 | 0 | two grounds: `hooprFill` and glass |
| `Components/ProfileButton.swift` | 59 | 0 | 0 | 0 | 0 | none — a glyph + `hooprRed` dot |
| `Components/StatsCard.swift` | 41 | 1 | 0 | 0 | 0 | `cardChrome()` |
| `Friends/FriendActionControls.swift` | 130 | 0 | 0 | 0 | 1 | filled + bordered capsules |
| `Friends/FriendRow.swift` | 140 | 0 | 0 | 0 | 0 | **inline copy of `cardChrome`, radius 14** |
| `Friends/FriendsPane.swift` | 261 | 0 | 0 | 0 | 0 | count capsule on `hooprFill` |
| `Friends/InboxSheet.swift` | 198 | 0 | 0 | 0 | 0 | count capsule on `hooprFill` |
| `Friends/PlayerAvatar.swift` | 58 | 0 | 0 | 2 | 0 | circle (documented `.system` exception) |
| `Friends/PlayerProfileSheet.swift` | 239 | 0 | 0 | 0 | 1 | identity band on the page colour; `safeAreaInset` action bar |
| `Friends/SquadInviteRow.swift` | 60 | 1 | 0 | 0 | 0 | `cardChrome()` |
| `Games/CreateGameSheet.swift` | 285 | 0 | 0 | 0 | 0 | four hand-rolled cards (surface + border) |
| `Games/GameCard.swift` | 272 | 1 | 0 | 0 | 0 | `cardChrome()` + badge pill + bordered secondary button |
| `Games/InviteLinkCard.swift` | 96 | 0 | 0 | 0 | 0 | bordered fill, radius 12 |
| `LoginView.swift` | 155 | 0 | 0 | 0 | 0 | field grounds + a 52pt filled button |
| `MainTabView.swift` | 204 | 0 | 0 | 0 | 0 | none — the system tab bar |
| `MapView.swift` | 404 | 0 | 0 | 0 | 1 | UIKit marker: ring + disc + shadow |
| `Profile/ProfileEditSheets.swift` | 535 | 0 | 0 | 0 | 1 | five sheets, each with its own card recipe |
| `Profile/ProfileIdentity.swift` | 260 | 0 | 1 | 0 | 2 | glass top bar; avatar ring |
| `Profile/ProfileRow.swift` | 215 | 0 | 0 | 1 | 1 | **`profileRowChrome()` — second copy of the recipe** |
| `Profile/ProfileView.swift` | 579 | 0 | 0 | 0 | 1 | pane selector on `hooprFill`; pinned header |
| `RootView.swift` | 106 | 0 | 0 | 0 | 0 | none |
| `Seasons/CreateSquadSheet.swift` | 327 | 4 | 0 | 1 | 0 | `cardChrome()` ×4 + icon/colour grids |
| `Seasons/FormGuide.swift` | 102 | 0 | 0 | 0 | 0 | fixed-diameter pills (capped — `ResultPillMetrics`) |
| `Seasons/GameDayView.swift` | 247 | 4 | 0 | 0 | 0 | `cardChrome()` ×4 + three full-width buttons |
| `Seasons/MatchmakingCard.swift` | 307 | 1 | 0 | 0 | 0 | `cardChrome()`, four states inside it |
| `Seasons/QueueSheet.swift` | 671 | 3 | 0 | 0 | 1 | `cardChrome()` ×3 + day chips + court rows |
| `Seasons/ResultView.swift` | 336 | 3 | 0 | 0 | 0 | `cardChrome()` ×3 + two bordered crest buttons |
| `Seasons/SeasonsTab.swift` | 447 | 3 | 0 | 0 | 0 | `cardChrome()` ×3 (+1 per extra squad) |
| `Seasons/SquadCrest.swift` | 87 | 0 | 0 | 1 | 0 | circle (documented `.system` exception) |
| `Seasons/SquadDetailView.swift` | 468 | 5 | 0 | 0 | 0 | `cardChrome()` ×5 + outcome badges |
| `Tabs/CourtGameRow.swift` | 134 | 0 | 0 | 0 | 0 | none — a row inside the sheet |
| `Tabs/CourtRow.swift` | 92 | 0 | 0 | 0 | 0 | none — a row inside the sheet |
| `Tabs/HomeTab.swift` | 393 | 5 | 0 | 0 | 1 | `cardChrome()` ×5 |
| `Tabs/LocalRunsTab.swift` | 220 | 0 | 0 | 0 | 0 | section headers + a 1pt rule; cards come from `GameCard` |
| `Tabs/MapTab.swift` | 1142 | 1 | 2 | 0 | 1 | sheet surface, glass chrome, run rows on `cardChrome` |
| `Tabs/SheetGeometry.swift` | 131 | — | — | — | — | pure arithmetic, no views |

**Totals:** 32 `.cardChrome(…)` call sites across 12 files (35 textual matches,
less the definition and two doc-comment mentions); 5 `hooprGlass` call
sites across 4 files; 58 `RoundedRectangle(cornerRadius:)` constructions across
21 files; 6 `.font(.system(` uses, all of them the documented fixed-shape
exceptions (`PlayerAvatar` ×2, `SquadCrest`, `ProfileRow`'s symbol square,
`CreateSquadSheet`'s icon grid) — **no undocumented violation of constraint 2**.
Zero literal colours in `Views/`: **constraint 1 holds today**, and the only
match a grep for `.black`/`.white`/`Color(red:` finds is a comment in
`MapView.swift:91` explaining why the value is bridged from the theme.

### 2.3 Components that exist, and the ones that don't

Shared and used: `CardChrome`, `GlassChip`, `HooprSearchField`, `ProfileButton`,
`ErrorBanner`, `StatsCard`, `CourtBadges`, `GameCard`, `FriendRow`,
`SquadCrest`, `FormGuide`, `MatchmakingCard`, `PlayerAvatar`, `ProfileRow`,
`SquadMemberRow`, `SquadInviteRow`, `CourtRow`, `CourtGameRow`,
`InviteLinkCard`, `FriendActionControls`.

**Three jobs are done in more than one place with no component:**

1. **Badges and count pills.** `GameCard` and `HomeTab` each build the
   HOSTING/WAITLIST/FULL pill inline from the same recipe (11pt bold, h8/v4, a
   `Capsule` at 12% of the tint) — two copies, and `HomeTab`'s own comment says
   it is mirroring `GameCard`'s priority order by hand. Separately,
   `LocalRunsTab`, `FriendsPane` and `InboxSheet` each build a section-count
   capsule on `hooprFill`, and `SquadDetailView` builds outcome badges. Five
   spellings of "a small pill with a number or a word in it."
2. **Avatars.** `PlayerAvatar` exists and is used by `FriendRow`,
   `SquadMemberRow` and `PlayerProfileSheet` — but `ProfileIdentityBlock` draws
   its own 72pt avatar with an orange ring, and `ProfileTopBar` draws a small
   one. Three avatar implementations, one of them a component.
3. **The full-width primary button.** `HomeTab` (44pt), `MapTab` (44 and 48),
   `SeasonsTab` (vertical padding 14), `LoginView` (52), `GameCard` (42),
   `GameDayView`, `MatchmakingCard` (capsule) and `ProfileEditSheets` (52) each
   build "filled `hooprOrange`, `hooprOnBrand` label, rounded" from scratch, at
   **six different heights and four different corner radii**.

### 2.4 Uppercase section labels — one idea, six spellings

`HomeTab` uses `Text(title.uppercased())` at 12pt bold with `kerning(0.6)`.
`MapTab`, `QueueSheet`, `SquadDetailView` (×4), `GameDayView`, `ResultView`,
`SeasonsTab` (×2), `MatchmakingCard`, `CreateSquadSheet` and `CreateGameSheet`
use `.textCase(.uppercase)` at **13pt** semibold with no kerning. Same device,
two sizes, two weights, one of them kerned.

---

## 3 — Colour role census

Counts are call sites with comments stripped. `hooprDarkOrange` appears **zero**
times in `Views/` — it is reached only from `MapView`'s UIKit marker tint via
`UIColor(Color.hooprDarkOrange)`, which is why it shows as absent here.

*(The per-file table in §2.2 reports `SH` counts doubled, because the scanner
matched `Color.hooprShadow` and `hooprShadow(opacity:)` separately. The totals
below are the corrected ones; a file showing `SH2` has one shadow, not two.)*

| Role | Uses | Where the weight is |
|---|---:|---|
| `hooprSecondaryText` | 165 | everywhere — the app's default non-title colour |
| `hooprPrimaryText` | 82 | titles and values |
| `hooprOrange` | **73** | brand, and the gap below |
| `hooprFill` | 38 | field grounds, unselected chips, secondary buttons |
| `hooprBackground` | 33 | one per screen, plus dots and rings |
| `hooprRed` | 31 | errors, destructive actions, notification dots |
| `hooprBorder` | 29 | hairlines |
| `hooprOnBrand` | 26 | labels on orange |
| `hooprShadow(_:)` | 5 | 3 of them **are** the three chrome copies; the others are the map sheet's upward lift and the UIKit marker's ring |
| `hooprSurface` | 8 | almost all of it is inside `cardChrome` |
| `hooprOnRed` | 2 | the inbox badge, the game-day arrival mark |
| `hooprSquad(_:)` | 2 | crest fills |
| `hooprOnCrest` | 1 | the crest glyph |

**The two findings that matter:**

- **`hooprSurface` is used 8 times and `hooprBackground` 33.** That is not a
  preference for the page colour; it is that surfaces are only ever reached
  *through* `cardChrome()`. There is no elevation vocabulary at all — one
  surface, one page, and in light mode they are the same white. Every
  "raised" thing in the app is raised by a 1pt hairline and a 6% shadow.
- **73 uses of `hooprOrange` against 26 of `hooprOnBrand`.** So roughly two
  thirds of brand uses are *not* a label on an orange fill — they are orange
  drawn as a foreground or a thin graphic. `gaps/ACCESSIBILITY.md` censused "at
  least 30" direct `foregroundStyle`/`tint` uses across 15 files and called it a
  lower bound; measured against the whole role, the honest figure is **73 total
  uses, of which at most 26 are the passing filled case.** The single most
  prominent instance is `MainTabView.swift`'s one `.tint(Color.hooprOrange)`.

Per-file role counts are in the table in §2.2's companion data; the four files
carrying the most orange are `ProfileEditSheets` (12), `MapTab` (7),
`HomeTab` (6) and `CreateGameSheet` (6).

---

## 4 — Spacing census

### 4.1 `.padding(…)` literals in `Views/`

| Value | Uses | | Value | Uses |
|---:|---:|---|---:|---:|
| 2 | 4 | | 14 | 22 |
| 3 | 3 | | **16** | **52** |
| 4 | 16 | | 18 | 1 |
| 5 | 1 | | **20** | **39** |
| 6 | 3 | | 22 | 1 |
| **8** | **23** | | 24 | 5 |
| 9 | 3 | | 28 | 1 |
| 10 | 11 | | 32 | 9 |
| 11 | 1 | | 38 | 1 |
| **12** | **31** | | 40 | 3 |
| | | | 60 | 1 |

**231 numeric padding literals. Four values (8, 12, 16, 20) carry 145 of them**
— so there is a de-facto scale, it is just not written down anywhere, and the
other 86 uses are the drift around it. The singletons (5, 11, 18, 22, 28, 38,
60) are where a value was chosen to make one specific thing line up.

### 4.2 `spacing:` literals

`0`×23, `2`×16, `3`×8, `4`×15, `5`×3, `6`×18, `7`×1, `8`×29, `10`×35, `12`×42,
`14`×15, `16`×18, `20`×2, `22`×1, `24`×2 — **230 uses across 15 distinct
values.** `12` and `10` together are a third of them and mean the same thing in
practice (gap between rows in a card).

### 4.3 `cornerRadius:` literals

| Radius | Uses | What it's on |
|---:|---:|---|
| 2.5 | 3 | the three sheet drag handles |
| 4 | 3 | skeleton placeholders |
| 5 | 1 | one skeleton |
| **10** | **20** | buttons, `ErrorBanner`, small pills |
| 11 | 2 | `HomeTab`'s friend-request icon tile |
| **12** | **18** | fields, `InviteLinkCard`, sheet buttons |
| **14** | **12** | `profileRowChrome`, `FriendRow`, map card actions, `ResultView` |
| (16) | — | `cardChrome`'s default, passed implicitly |

**Four radii in real use (10/12/14/16) with no rule about which is which** —
`GameCard`'s card is 16 and its own buttons are 10; `MapTab`'s card actions are
14; `FriendRow`'s card is 14 and `HomeTab`'s is 16, and the two draw the same
kind of object.

### 4.4 Page margin — the one inconsistency that is visible on screen

| Screen | Title/header inset | Content inset |
|---|---:|---:|
| Home | 20 | 20 |
| Runs | **20** | **16** |
| Seasons | 20 | 20 |
| Profile | 20 (`ProfileView.pageMargin`) | 20 |
| Map court card | 20 | 20 |
| Map sheet list | — | 16 |
| `InboxSheet` | 16 | 16 |
| `PlayerProfileSheet` | 20 | 20 |
| `QueueSheet` | 16 | 16 |
| `GameDayView` / `ResultView` | 16 | 16 |
| `ProfileEditSheets` | 16 and 20 in the same file | mixed |

`ProfileView` is the **only** file in the app with a named margin
(`private static let pageMargin: CGFloat = 20`). Everything else restates the
number. On the Runs tab the mismatch is directly visible: the word "Runs" is
inset 20pt and the cards under it are inset 16pt, so the title hangs 4pt to the
left of the content it introduces.

### 4.5 Fixed heights

`42` (`GameCard`'s primary button), `44` (`HomeTab`'s CTA, `ProfileButton`'s hit
target, `MapTab`'s search-empty CTA), `46` (the map's recenter circle), `48`
(`MapTab`'s card actions, the home-court search field), `52` (`LoginView`'s
fields and button, `ProfileTopBar`), `32`/`34`/`38` (avatars, chips, tiles).
Seven button heights for what is, in ledger terms, three kinds of button.

---

## 5 — Feature purpose ledger

One row per user-facing **feature**, not per screen: "join a run" lives on Runs
*and* on the map's court card, and appears once. Every row cites where its
purpose comes from; anything the docs don't settle is marked **assumption** and
listed again in §5.3.

**Reading the columns.** *Core task and its cost* counts taps from the tab root
(or, for features behind the profile, from any tab root) to the task being done,
walked in the simulator on a real signed-in account. Where the last tap is a
**write** — Create a run, Queue up, Accept a request, report a winner — the walk
stopped one tap short and that tap was counted from the call site rather than
performed: this audit changes no data on the user's account. Typing is counted separately — it is a different kind
of cost and a redesign can't remove it. *What the data really is* exists because
2d makes it an automatic fail to give a self-reported counter the weight of a
mutually-confirmed one.

### 5.1 Runs — the product's centre of gravity

---

**F1 · Know whether I'm playing tonight**

- **Purpose:** "Am I signed up for something tonight, and where?"
- **Decision:** whether to go out, and when to leave. Facts needed: **which
  court**, **what time**, **am I actually in or on the waitlist**.
- **Core task and cost:** open the app → read it. **0 taps**, but it is the
  *third* block down for an account with stats, and its answer ("Bethesda Park",
  "Tonight 7:00 PM") is set at 17pt under a 12pt all-caps label, below a 28pt
  greeting that carries no information.
- **Frequency and moment:** highest frequency of anything in the app — it is the
  stated reason the app opens on Home rather than the map. A glance, one-handed,
  often on the way out of the door.
- **What the data really is:** a real `games` document the account is on the
  roster of. Trustworthy. The badge (HOSTING/WAITLIST/FULL) is derived from the
  roster, not stored.
- **Known gaps:** none for the reading path. The run it points at may be
  invite-only and therefore held only by its host (`gaps/GAMES.md`).
- **Why it is shaped this way:** `UI_SHELL.md` § `HomeTab` — Home exists because
  the map "can't answer 'am I signed up for something tonight?', which is the
  more common reason to open the app." The card is **read-only on purpose**:
  join/leave/cancel "are decisions that belong on Runs," so the card's only
  action is to navigate there.
- **Source:** `UI_SHELL.md` § `HomeTab`; `HomeTab.swift:62–95`,
  `nextRunCard` 137–199.

---

**F2 · Join a run**

- **Purpose:** "There's a game I can get into — put me on it."
- **Decision:** is this run worth my evening? Facts needed: **how far**, **what
  time**, **is there room** (and, since 2026-09-18, **do I know anyone on it**).
- **Core task and cost:** Runs tab → `Join` on the card = **1 tap**. From the
  map: pin or list row → `Join` on the run row = **2 taps**. Both resolve the
  same `LocalRunsViewModel.action(for:)`, so the button can never differ between
  the two surfaces.
- **Frequency and moment:** high; focused rather than glanced — it is a
  commitment. Usually planning at home.
- **What the data really is:** a server-enforced capacity write. Two people
  taking the last seat cannot both succeed (`PRODUCT_OVERVIEW.md`).
- **Known gaps:** a full run gives a **waitlist** place that **never
  promotes** — when someone leaves, the seat is not handed on
  (`gaps/GAMES.md`). Nothing on the card says so, which is the one place this
  feature currently over-promises.
- **Why it is shaped this way:** `UI_SHELL.md` § `LocalRunsTab` — one shared
  `GameCard` for both sections "so a run reads identically wherever it appears";
  the action is resolved **once per row** and handed to both the button and its
  dialog; **one roster write in flight at a time**.
- **Source:** `UI_SHELL.md` § `LocalRunsTab`; `GameCard.swift`,
  `MapTab.runRow` 920–971.

---

**F3 · Host a run**

- **Purpose:** "Nobody's playing at my court tonight — I'll put one on the
  board."
- **Decision:** when, who can see it, how many. Facts needed: **which court**
  (already chosen by arriving here), **when**, **public or invite-only**.
- **Core task and cost:** Map → select a court → `Start Run` → `Create` =
  **3 taps** with every default accepted (`CreateGameViewModel` defaults to a
  computed tip-off, `isPublic = true`, `Game.defaultMaxPlayers`). Changing the
  time or the roster adds taps inside the sheet.
- **Frequency and moment:** low frequency, high stakes — it is the write the
  cold-start problem depends on. Focused, planning at home.
- **What the data really is:** a real document; host, status, rosters and
  timestamps are all derived on the write path, so the form asks only the four
  things it can't derive.
- **Known gaps:** a **private run's invite link can be copied but not opened**
  (`gaps/GAMES.md`), so an invite-only run in practice holds only its host. The
  create sheet's invite step and `InviteLinkCard` both present the link as
  usable. **This is the standing 2d example** and the redesign must not draw it
  as working.
- **Why it is shaped this way:** `UI_SHELL.md` § Starting a run — both entry
  points (pin, list row) converge on the court card, "so one 'Start Run' button
  there covers both." A public run dismisses on save; a private one swaps the
  form for an invite step where Cancel is dropped and Create becomes Done,
  because "the run already exists."
- **Source:** `UI_SHELL.md` § Starting a run; `MapTab.cardActions` 984–1024,
  `CreateGameSheet.swift`.

---

**F4 · Leave, cancel, or close out a run**

- **Purpose:** "I can't make it" / "this isn't happening" / "that one's done."
- **Decision:** none to support — these are executions, not choices. What they
  need is **certainty about what is irreversible**.
- **Core task and cost:** Leave = **1 tap** (Runs). Cancel (host) = **2 taps**
  (button + confirmation). Mark complete (host, after tip-off) = **2 taps**.
- **Frequency and moment:** low. Leave is often one-handed at short notice;
  cancel and complete are deliberate.
- **What the data really is:** completion is **one-way** — the rule refuses a
  second write — and it **freezes the roster**. It also carries **no attendance
  claim**: `canComplete` doesn't consult the roster, so a host who turned up
  alone can still record the run (`gaps/GAMES.md`, decided 2026-09-18).
- **Known gaps:** no un-complete path; no `in_progress`; no automatic
  completion — an unmarked run just ages out 4h after tip-off.
- **Why it is shaped this way:** `UI_SHELL.md` § `LocalRunsTab` — "Mark
  complete" is deliberately **not** an `Action` case, because a host after
  tip-off must be offered *both* it and "Cancel run" and one-of-N can't express
  that. It is drawn **secondary** (bordered over `hooprFill`), not destructive,
  because "completing takes nothing away."
- **Source:** `UI_SHELL.md` § `LocalRunsTab`; `GameCard.completeButton`
  211–252.

---

### 5.2 Courts, people, seasons, account

---

**F5 · Find a court to play at**

- **Purpose:** "Where can I hoop, and what's it like when I get there?"
- **Decision:** which court to travel to. Facts needed: **how far**, **is it any
  good** (hoops/surface/lights/covered), **can I actually get on it**
  (Restricted).
- **Core task and cost:** Map tab → read pins, or `Nearby` → a row → the card =
  **1–2 taps**. Directions = **2 taps** (select, `Directions`). Star a
  favourite = **2 taps**. A named court by search = **2 taps + typing**.
- **Frequency and moment:** medium. Both moments — planning at home, and
  one-handed standing outside a locked gate.
- **What the data really is:** a bundled, curated 214-court dataset. Only facts
  the source carries are shown; **nothing is inferred** (`PRODUCT_OVERVIEW.md`).
  Works with no network.
- **Known gaps:** coverage stops at six Triangle cities, so outside them the map
  is correctly empty (`gaps/ASSETS_AND_DATA.md`). The ODbL attribution the data
  requires **is not displayed anywhere** — an outstanding licensing obligation,
  and the one gap in this ledger that a redesign could actually close.
- **Why it is shaped this way:** `MAP_LAYER.md` — badges are shed before the
  name is truncated; **a caution is never the badge that gets dropped**; the
  card is never poorer than the row it was tapped from; there is deliberately no
  address row.
- **Source:** `MAP_LAYER.md` §§ court detail card, `CourtRow`;
  `gaps/ASSETS_AND_DATA.md`.

---

**F6 · See where the action is**

- **Purpose:** "Is anyone playing anywhere tonight?"
- **Decision:** where to go when I have no plan. Facts needed: **which courts
  have runs today** and **how many**.
- **Core task and cost:** Home → read the three "Hot right now" rows =
  **0 taps**; tapping one opens the map with that court selected (**1 tap**).
  On the map: the `Now` segment, plus the pins' own count badge and heat colour.
- **Frequency and moment:** medium; a glance.
- **What the data really is:** **scheduled runs today, not live occupancy.** It
  sums only games this account could already see — public runs plus ones it is
  personally on — so a pin can never leak a private run. The colour ceilings at
  4+ while the pin's *number* stays exact through 9, because "the colour runs
  out of luma and the number doesn't."
- **Known gaps:** **there is no live headcount and the app cannot answer "is
  anyone there right now"** (`plans/LIVE_HEADCOUNT.md` is a plan, not code).
  2d makes inventing one an automatic fail.
- **Why it is shaped this way:** `UI_SHELL.md` § `HomeTab` — Home's hot list
  calls `FindAMatchViewModel.gameCountsByCourt` directly so "a court's colour
  means the same thing here as on the map," and reads **nothing new**.
  `HomeTab.gameCountText` says "4+" at the ceiling rather than the true count,
  so a row can't promise a distinction the pin can't draw.
- **Source:** `UI_SHELL.md` § `HomeTab`; `MAP_LAYER.md` § `CourtHeat`;
  `CourtHeat.swift`.

---

**F7 · Find people and add them**

- **Purpose:** "Is my friend on here?"
- **Decision:** whether this is the right person. Facts needed: **name**,
  **handle** (two friends can share a display name), **our current relationship**.
- **Core task and cost:** any tab → `ProfileButton` → `Friends` → the search
  field → a result's control = **4 taps + typing**. It is the deepest core task
  in the app and the only one behind a screen that replaces the tab bar.
- **Frequency and moment:** bursty — heavy in the first week, rare after.
  Focused.
- **What the data really is:** a `userNameLower` prefix range, plus a direct
  document read when the text is uid-shaped. An exact ID match ranks first; the
  signed-in user is dropped.
- **Known gaps:** **no blocking, no reporting, no rate limiting** — anyone can
  ask anyone, repeatedly, and declining is the only recourse
  (`gaps/FRIENDS.md`). Mutual-friend counts are **impossible**, not omitted:
  `friendships` is participants-only.
- **Why it is shaped this way:** `UI_SHELL.md` § Friends — this is the one list
  screen deliberately *not* built from the `LocalRunsTab` parts, because
  "finding someone is an **action** and needs a permanently visible control."
  The subtitle is **always the handle**, never the home court.
- **Source:** `UI_SHELL.md` § Friends; `FriendsPane.swift`.

---

**F8 · Deal with what's waiting on me**

- **Purpose:** "Someone asked me something — answer it."
- **Decision:** accept or decline. Facts needed: **who**, **what kind of
  request**.
- **Core task and cost:** any tab → `ProfileButton` → inbox → `Accept` =
  **3 taps**.
- **Frequency and moment:** low but **must not be missable** — it is the only
  thing in the app that another person is blocked on.
- **What the data really is:** real `friendships` and `squadInvites` documents;
  only the recipient can accept.
- **Known gaps:** **notifications are local only** — there is no push, so a
  request is visible only when the app is open (`PRODUCT_OVERVIEW.md`). The red
  dot is the entire notification system.
- **Why it is shaped this way:** `UI_SHELL.md` § `ProfileView` — the inbox
  moved into screen chrome because "the one place social notifications collect
  was only visible on the pane you had to already be on to see it." The badge is
  `hooprRed`, not brand orange, because "orange is the brand and is everywhere
  on this screen." **Invariant: one notification indicator per surface.**
- **Source:** `UI_SHELL.md` §§ `ProfileView`, Friends; `ProfileButton.swift`.

---

**F9 · Form and run a squad**

- **Purpose:** "Get my people into a team that has a name and a record."
- **Decision:** who's on it. Facts needed: **who's already on**, **who I can
  invite** (accepted friends only), **am I the leader**.
- **Core task and cost:** Seasons → `Create a squad` → `Create` = **2 taps +
  typing**. Inviting: Seasons → squad header → the invite row's button =
  **3 taps** per person.
- **Frequency and moment:** once, then rarely. Focused.
- **What the data really is:** every member adds or removes **only
  themselves**; the leader names and disbands.
- **Known gaps:** **no kicking a member and no leader transfer** — a squad whose
  leader goes inactive can only be left and rebuilt (`gaps/SEASONS.md`). Only
  the **primary** squad gets the live match card and the queue control.
- **Why it is shaped this way:** `UI_SHELL.md` § `SeasonsTab` — squad invites
  moved out of this tab to the profile inbox, because a leader could invite but
  there was nowhere to *accept*. More than one squad is legal, so the others get
  rows rather than being silently dropped.
- **Source:** `UI_SHELL.md` § `SeasonsTab`; `gaps/SEASONS.md`.

---

**F10 · Get a match**

- **Purpose:** "Find us someone to play."
- **Decision:** when and where we'll travel. Facts needed: **the window**,
  **which courts**, and — while searching — **is anything happening**.
- **Core task and cost:** Seasons → `Queue up` → confirm = **2 taps**, because
  `primeDefaults()` seeds the sheet with today, a 5–10pm window and the
  account's favourite courts already selected (observed: "3 of 8" pre-checked).
  Changing any of that adds taps. Then it is a wait, rendered as one of four
  states in place.
- **Frequency and moment:** low. Focused, planning.
- **What the data really is:** **matchmaking runs entirely between the two
  phones involved**; there is no server pairing squads. A match and both queue
  entries are written in one transaction, so two squads picking each other
  produce one match.
- **Known gaps:** **an empty pool is the default experience in a new city**, not
  the edge case (`gaps/SEASONS.md`). The searching state's copy is honest about
  this and must stay honest. `settlingGrace` (20s) bounds *match found* so it
  can't spin forever.
- **Why it is shaped this way:** `UI_SHELL.md` § `SeasonsTab` — "screens 5, 6
  and 8's waiting are **states**, not destinations," because they differ by one
  sentence. `MatchTicket.isSearching` is the only question the searching state
  may ask.
- **Source:** `UI_SHELL.md` § `SeasonsTab`; `MatchmakingCard.swift`;
  `gaps/SEASONS.md`.

---

**F11 · Show up to a match**

- **Purpose:** "Where and when, and is the other squad actually coming?"
- **Decision:** leave now or not. Facts needed: **time to tip-off**, **which
  court**, **who's arrived**.
- **Core task and cost:** Seasons → the match card → read; `We're here` =
  **2 taps**.
- **Frequency and moment:** rare, and the one moment in the app that is
  definitely one-handed, outdoors, possibly in sun.
- **What the data really is:** arrival is self-reported per member. Game day
  stops rendering a match three hours after tip-off.
- **Known gaps:** reminders are **local notifications scheduled by a client
  that's open** — a squad member whose app never opens between the match landing
  and tip-off gets nothing (`gaps/SEASONS.md`).
- **Why it is shaped this way:** `UI_SHELL.md` § `SeasonsTab` (the pushes carry
  the `SeasonGame` value, not an ID).
- **Source:** `GameDayView.swift`; `gaps/SEASONS.md`.

---

**F12 · Record who won**

- **Purpose:** "We won — make it count."
- **Decision:** which squad won. Facts needed: **the two squads**, **what the
  other leader said**.
- **Core task and cost:** Seasons → match card → `Report result` → a crest =
  **3 taps**. The write fires on the crest tap; the score is optional and adds
  typing.
- **Frequency and moment:** rare. Often at the court, immediately after.
- **What the data really is:** **the one number in the app nobody can type.** A
  result counts only when both leaders report the same winner; a disagreement is
  a *designed* outcome, not an error. This is the contrast 2d turns into an
  automatic fail: a squad's record and Home's `completedGameCount` must not be
  drawn with the same authority.
- **Known gaps:** a match awaiting one leader's report **waits forever** — no
  timeout, no forfeit, no nudge. A dispute has **no arbiter and no expiry**. A
  mutually-agreed *wrong* result is **permanent**. And the live two-person flow
  **has never been exercised on two real devices** (`gaps/SEASONS.md`), so
  `ResultView`'s own rendering is, strictly, unseen.
- **Why it is shaped this way:** `UI_SHELL.md` § Reporting a result — the two
  crest buttons are "the only place a `SquadCrest` is not decorative," so they
  carry explicit labels. Reachable from game day *and* from any history row,
  because game day stops rendering three hours after tip-off.
- **Source:** `UI_SHELL.md` § Reporting a result; `ResultView.swift`;
  `gaps/SEASONS.md`.

---

**F13 · See how we're doing**

- **Purpose:** "What's our record, and are we on a run?"
- **Decision:** none directly — this is the payoff the rest of Seasons exists
  for. Facts: **W–L**, **last five**.
- **Core task and cost:** Seasons → read = **0 taps** (record and `FormGuide`
  are on the squad header); full history = **1 tap** into squad detail.
- **Frequency and moment:** medium, a glance, and the thing people screenshot.
- **What the data really is:** a **query over mutually-confirmed matches**, not
  a stored counter — "a number nobody can type."
- **Known gaps:** **no standings or leaderboards** — a record exists per squad
  and there is nowhere to compare it (`gaps/SEASONS.md`).
- **Why it is shaped this way:** `database/DATABASE_SCHEMA.md` — `squads` stores
  no `wins`/`losses` deliberately, at the cost of one extra read.
- **Source:** `UI_SHELL.md` § `SeasonsTab`; `SeasonsTab.recordText` 178–181.

---

**F14 · Track my own participation**

- **Purpose:** "Have I actually been playing?"
- **Decision:** none — this is a personal activity summary. Facts: **runs
  completed**, **streak**, **last run**.
- **Core task and cost:** Home → read = **0 taps**, hidden entirely until
  `completedGameCount > 0`.
- **Frequency and moment:** a glance, low stakes.
- **What the data really is:** **self-reported counters on `users/{uid}`, which
  the owner writes** — the same forgeability `database/DATABASE_SCHEMA.md`
  records. They move only when a host marks a run complete by hand, so the
  streak reflects the runs a host *recorded*, not the runs that happened. 2d
  makes giving these the weight of a confirmed result an automatic fail.
- **Known gaps:** no automatic completion (needs a Cloud Function), so the
  numbers under-count by construction.
- **Why it is shaped this way:** `UI_SHELL.md` § `HomeTab` — gated on `hasStats`
  so "a brand-new account sees no card at all rather than a row of zeros," and
  nothing refreshes it by hand: the card appearing is a consequence of the
  listener, not of the tap.
- **Source:** `UI_SHELL.md` § `HomeTab`; `StatsCard.swift`; `gaps/GAMES.md`.

---

**F15 · Manage my account**

- **Purpose:** "Change my name / my court / how far I'll travel / how it looks."
- **Decision:** rare setup choices. Facts: the current value.
- **Core task and cost:** any tab → `ProfileButton` → a row → edit = **3 taps +
  typing** (the home-court picker saves on tapping a suggestion; name and radius
  have a `Save`). Copy my uid = **2 taps**. Sign out = **2 taps** + a scroll.
- **Frequency and moment:** rare. 2c says these stay quiet but always findable.
- **What the data really is:** an allowlisted subset; **nothing private is
  stored on a profile**, and appearance is a *device* preference, not an account
  one.
- **Known gaps:** **no account deletion**, no social sign-in, and sign-up has
  **no verification step at all** (`gaps/PROFILES.md`). `Password` is the one
  row whose value is a fiction — the app has never held a password.
- **Why it is shaped this way:** `UI_SHELL.md` § `ProfileView` — the orange
  header slab was removed because it "spent the most valuable real estate on the
  page restating something the user already knows"; rows replaced a card mosaic
  because a card's *height* was carrying meaning its content didn't; **rows
  state no height at all**; Sign Out is the last row, not a pinned bar.
- **Source:** `UI_SHELL.md` § `ProfileView`; `ProfileEditSheets.swift`.

---

**F16 · Get into the app**

- **Purpose:** "Let me in."
- **Decision:** sign in or sign up. Facts: none beyond the two fields.
- **Core task and cost:** two fields + **1 tap**.
- **Frequency and moment:** once, then never — `.launching` exists so the login
  screen never flashes at a returning session.
- **What the data really is:** **passwords never pass through the app**; reset
  happens on Firebase's own hosted page.
- **Known gaps:** no verification, no social login, and the reset page is
  unbranded (`gaps/PROFILES.md`).
- **Why it is shaped this way:** not recorded in `UI_SHELL.md` beyond the
  `RootViewModel.destination` switch. **Assumption:** the screen's job is a
  first impression as much as a form — it is the only screen a brand-new user
  sees before anything else, and the only one with no data on it.
- **Source:** `LoginView.swift`; `UI_SHELL.md` § Navigation.

---

### 5.3 Assumptions — the list Checkpoint 1 must answer

Each of these is something the ledger needed and the docs don't settle. They are
designed *to* rather than decided silently, per the prompt's failure paths.

| # | Assumption | Why it matters to Phase 2 |
|---|---|---|
| A1 | **`LoginView`'s job includes being a first impression**, not just collecting two fields. | It is the only screen with no data, so it is the only one where a `MeshGradient` hero (Phase 4) would be carrying nothing but tone. If the answer is "it's a form, keep it plain", Phase 4's login treatment is cut. |
| A2 | **Home's greeting is worth keeping at all.** `UI_SHELL.md` records *why it is one line and centred*, never why it exists. | 2c's "an element that maps to no decision or task is cut" points straight at it. Demoting it is the single biggest change available on Home. |
| A3 | **Runs' two sections are read in one pass** ("am I busy, and what else is on?"). Recorded as the reason they share a scroll view, but never measured against a user. | If true, Runs keeps one scroll and gains a hero. If false, the two lists want different weights, which changes the archetype. |
| A4 | **The map tab is the "keep" candidate** under 2e's at-most-one-tab rule. | It is already full-bleed content under a detent sheet with floating glass chrome — the only screen in the app that already obeys 2c's layer rule. Phase 2 needs the user's agreement that this is the one tab allowed to keep its composition. |
| A5 | **Seasons' no-squad hero state is the right model for the whole app**, not an exception. | It is the one composition in the app with a real hero (crest → 22pt line → one action). Phase 2a's archetypes would be derived partly from it. |
| A6 | **"Spots left" matters more than "N/M on the roster."** The card states `rosterText` and draws a capacity bar; nobody has said which number the decision actually turns on. | 2c says numbers get the display tier. Which number gets it is this question. |
| A7 | **The waitlist's non-promotion should be visible on the card.** Today nothing says a waitlist place never moves up. | Saying it is arguably *new information in the UI*, which is in scope for a redesign; not saying it arguably draws a feature as working that `gaps/GAMES.md` says isn't. |
| A8 | **The ODbL attribution has to land somewhere in this revamp.** | It is an outstanding licensing obligation (`gaps/ASSETS_AND_DATA.md`) and the map/profile redesigns are the only realistic homes for it. Out of scope unless the user says otherwise. |
| A9 | **Phase 2's evidence table may compare a populated after-shot with an empty before-shot.** The account has no runs, so `GameCard`, Home's next-run card and the heat ramp have no populated before-image (§7.3). | Either the user creates the data, or every screen that shows a run is judged on its empty state only. The first is a write to their live account; the second silently flatters the redesign. It cannot be decided by the model. |
| A10 | **Light mode's page ground stays pure white.** Phase 1 added `hooprElevatedSurface`, but in light it *is* white — nothing is lighter — so a raised surface there is carried by `hooprShadow` alone. *(Added after Phase 1.)* | If the redesign wants depth in light mode from the fill, the page ground has to drop off white, which re-tunes `hooprFill` and `hooprBorder` on every screen and overturns the recorded decision in `ThemeContrastTests.testCardSeparatesFromBackgroundInDarkMode`. The role is ready either way; the ground is a brief decision, and it changes every screen's look. |

---

## 6 — Before-skeletons

The top-level view tree of every screen, as it stands on 1a2710d. Each carries
the four things 2e's structural test compares against: **container primitive**,
**section order**, **hero**, **primary-action placement** — plus the
first-viewport container count under §1's rule.

Read these as the *left-hand column* of the Phase 2 evidence table. A screen
whose after-skeleton differs from its before-skeleton on fewer than three of
those axes has been re-skinned, not redesigned.

### 6.1 Home — `Views/Tabs/HomeTab.swift`

```
HomeTab.body
ScrollView                                          [.background hooprBackground]
└── VStack(alignment: .leading, spacing: 24)        [h20, bottom 32]
    ├── header          HStack — 28pt "Let's hoop <name>." · Spacer · ProfileButton
    │                   lineLimit(1) + minimumScaleFactor(0.65)   ← largest type on screen
    ├── [hasStats] "YOUR STATS"  12pt caps → StatsCard            3 text columns in a card
    ├── "NEXT RUN"      12pt caps → nextRunCard | noRunCard       ← the screen's actual answer
    ├── "HOT RIGHT NOW" 12pt caps → hotCourtsCard                 3 rows in one card
    └── [requests > 0]  friendRequestBanner                       card, radius 14
```

- **Container primitive:** `cardChrome()`, five call sites, one per block.
- **Hero:** the greeting. It is the largest type on the screen (28pt vs the next
  run's 17pt) and it carries **no information** — the user knows their own name.
- **Primary action:** there isn't one. Every element is navigation; the only
  filled button on the screen is inside the *empty* state ("Find a court").
- **First-viewport containers (measured):** **3 panels / 4 shapes** — stats
  card, next-run card, hot card, plus the "Find a court" button inside the
  empty next-run card. With a run scheduled the button is replaced by a badge
  pill and a capacity track (4 shapes, unchanged); with a friend-request banner
  it is **4 panels / 6 shapes**.
- **The pattern to break, stated plainly:** the screen exists to answer "am I
  signed up for something tonight?", and that answer is set at 17pt, inside a
  box, under a 12pt all-caps label, **below** the stats card for anyone who has
  stats. The loudest thing on it is a greeting.

### 6.2 Runs — `Views/Tabs/LocalRunsTab.swift`

```
LocalRunsTab.body
ScrollView                                          [.background hooprBackground]
└── LazyVStack(alignment: .leading, spacing: 0)     [bottom 32]
    ├── header          HStack — 28pt bold "Runs" · Spacer · ProfileButton   [h20]
    ├── [error]         ErrorBanner                                          [h16]
    ├── section "Queued Games"
    │   ├── sectionHeader   18pt bold title · count capsule · chevron (rotates)  [h16 v16]
    │   └── [expanded] VStack(spacing: 12) of GameCard                       [h16]
    ├── Rectangle 1pt hooprBorder                    full-bleed rule
    └── section "Public Games"    — identical shape
```

`GameCard` itself:

```
GameCard                                            cardChrome(), padding 16
├── header     basketball glyph · court name 16pt · time 14pt · [badge pill]
├── details    HStack — roster · distance · [lock]        13pt grey, plain HStack
├── [friends]  "N friends here"                           13pt primary
├── capacity   5pt capsule track + fill
├── [host+private] InviteLinkCard                         bordered fill, radius 12
├── [action]   primary button, 42pt, radius 10
└── [canComplete] secondary button, 42pt, bordered fill
```

- **Container primitive:** `GameCard`'s `cardChrome()` — this is the most
  repeated element in the app.
- **Hero:** none. The largest type is the word "Runs" (28pt), which is the tab
  label restated; the next largest is a section header (18pt). The content tops
  out at 16pt.
- **Primary action:** inside the first card, roughly 240pt down the page.
- **First-viewport containers (measured, empty):** **0 panels / 2 shapes** —
  the two "0 runs" count capsules and nothing else. The whole screen is a title,
  two section headers and two grey sentences. With runs on it the count is
  roughly **2 panels / 7 shapes** (two `GameCard`s, their badge pills, capacity
  tracks and primary buttons) — **not captured**, see §7.3.
- **Note for 2e:** the title is inset 20pt and the cards 16pt (§4.4), so the
  heading hangs left of the content it introduces.

### 6.3 Map — `Views/Tabs/MapTab.swift`

```
MapTab.body
ZStack(alignment: .bottom)                          [.background hooprSurface]
├── MapView                    full-bleed, ignoresSafeArea(.top/.horizontal)   ← base layer
├── mapOverlay   VStack(alignment: .trailing, spacing: 10)   [top 8, bottom = sheet + tabBar]
│   ├── searchRow      HooprSearchField(.glass) + ProfileButton        [h14]
│   ├── [!focused] filterChips   horizontal ScrollView of GlassChip
│   └── Spacer                                       load-bearing
├── recenterButton             46pt glass circle, bottom-trailing
├── sheet                      hooprSurface, shadow(0.08, r12, y−4), SheetGeometry
│   ├── .rest    → sheetHeader (handle + "N courts nearby") → listTabs (Now|Nearby|Saved)
│   │               → courtList of CourtRow / CourtGameRow
│   ├── .detail  → courtCard: handle → cardHeader (fixed) → scroll (runRows + CourtBadges)
│   │               → cardActions (pinned: Directions | Start Run)
│   └── searching→ sheetHandle → searchPane (Recent as the empty state)
└── collapsedPeek              glass pill, fades in over the last 40% of travel
```

- **Container primitive:** none for the content — the map *is* the content. The
  sheet is a single surface; rows inside it are dividers, not cards (except the
  detail card's `runRow`, which is `cardChrome(12)`).
- **Hero:** the map itself, edge to edge, under floating glass chrome.
- **Primary action:** "Start Run", pinned at the bottom of the detail card
  specifically so it can't fall below the fold.
- **First-viewport containers (measured):** **1 panel / 6 shapes** — the sheet,
  plus the glass search field, three filter chips and the recenter circle. The
  lowest panel count in the app, because the content is the map rather than a
  stack of cards.
- **This is the only screen already obeying 2c's layer rule**, and the reason
  A4 proposes it as 2e's single permitted *keep*.

### 6.4 Seasons — `Views/Seasons/SeasonsTab.swift`

Two states over one scroll view.

```
SeasonsTab.body  →  NavigationStack → ScrollView
└── VStack(alignment: .leading, spacing: 16)        [h20, bottom 32]
    ├── header      HStack — 28pt bold "Seasons" · Spacer · ProfileButton
    ├── [error]     ErrorBanner
    ├── (A) no squad → emptyState
    │        VStack(spacing: 14): SquadCrest(hero 64) · "Play a season" 22pt bold
    │                           · 15pt copy (maxWidth 320) · filled CTA
    └── (B) squad    → squadHome
             ├── squadHeader   card — crest(64) · name 22pt · format·region · record · FormGuide · chevron
             ├── MatchmakingCard  card — one of {idle, searching, settling, matched}
             ├── rosterCard    card — "ROSTER" caps · rosterText · member rows
             ├── [n>1] otherSquads — caps label + one card(12) per squad
             └── "Create another squad"   bare text button
```

- **Container primitive:** `cardChrome()`, three call sites plus one per extra
  squad.
- **Hero:** **state (A) has a real one** — crest → 22pt line → one action, and
  it is the only composition in the app built that way (hence A5). **State (B)
  does not:** the largest type is "Seasons" (28pt), and the squad's own name
  (22pt) sits inside a card below it.
- **Primary action:** (A) the filled CTA, centred. (B) "Queue up", two cards
  down, inside `MatchmakingCard`.
- **First-viewport containers:** **(A) 0 panels / 1 shape** (the CTA; the crest
  is content) — the lightest screen in the app, and **not captured**: this
  account has a squad, so state (A) is unreachable without leaving it.
  **(B) measured: 3 panels / 5 shapes** — squad header, matchmaking card, roster
  card, plus the "Queue up" button and one `FormGuide` pill.

### 6.5 Login — `Views/LoginView.swift`

```
LoginView.body
VStack(spacing: 0)                                  [h28, .background hooprBackground]
├── Spacer
├── brand      VStack(spacing: 8) — basketball.fill 44pt orange
│                                 · "hoopsRN" 34pt bold      ← largest type in the app
│                                 · mode title 15pt          [bottom 32]
├── fields     VStack(spacing: 12) — Email, Password (52pt, hooprFill, radius 12,
│                                    border turns hooprOrange on focus)
├── [error]    13pt hooprRed
├── submit     52pt filled button, radius 12, disabled at 40% opacity   [top 24]
├── mode switch  14pt, "Sign up" in hooprOrange                         [top 20]
└── Spacer, Spacer                                  ← two, so the block sits above centre
```

- **Container primitive:** field grounds and one filled button.
- **Hero:** "hoopsRN" at 34pt — **the app's only real typographic hero.**
- **Primary action:** the 52pt button, directly under the fields.
- **First-viewport containers (measured):** **0 panels / 3 shapes** — two field
  grounds and one button. The whole screen is one viewport by construction.
- **Verified at `.accessibility3`:** reflows correctly — the mode-switch row
  wraps to two lines, nothing clips, nothing is cut off. The only screen in the
  app whose full composition fits in one screenshot at that size.

### 6.6 Profile — `Views/Profile/ProfileView.swift`

```
ProfileView.page
ScrollView                                          [.background hooprBackground]
│  ⇧ safeAreaInset(.top): ProfileTopBar — 52pt, glass, back · (avatar+handle on scroll) · inbox
└── LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders])
    ├── ProfileIdentityBlock       72pt avatar (orange ring) · @handle 30pt · uid (copies on tap)
    │                              [h20, top 8, bottom 22]            ← scrolls away
    └── Section
        ├── header (PINS)  paneSelector — two pills on hooprFill, radius 14
        │                  [+ FriendsSearchField on the Friends pane]
        └── body
            ├── .profile → VStack(spacing: 22) of ProfileRow / ProfileActionRow
            │              (profileRowChrome — the second copy of the card recipe)
            └── .friends → FriendsPaneContent — FriendRow list, or search results
```

- **Container primitive:** `profileRowChrome()` — one row per field, plus the
  pane selector's filled ground.
- **Hero:** the `@handle` at 30pt. **This screen already has a hero**, and it
  got one by deleting the orange header slab that used to sit here.
- **Primary action:** none — it is a settings column. The inbox (the one thing
  that can be *waiting*) is in the top bar, opposite the back chevron.
- **First-viewport containers (measured):** **7 panels / 14 shapes** — the pane
  selector's ground and six `ProfileRow`s, plus the selected pill and each row's
  filled icon tile. **The highest shape count in the app**, and it comes from
  the rows: every field is a card with a tinted square in it. (The top bar draws
  no edge at rest — `barProgress` is 0 until the identity block scrolls.)

### 6.7 The pushed Seasons screens

All three are the same composition: a `ScrollView` over a `VStack(spacing: 16)`
of `cardChrome()` cards under an inline `navigationTitle`.

| Screen | Cards, in order | Hero | Primary action |
|---|---|---|---|
| `SquadDetailView` | crest header · record · history · roster · [leader] invites · controls | none — the nav title is 17pt | scattered: invite buttons mid-page, leave/disband last |
| `GameDayView` | [cancelled] · [error] · countdown · court · [notif note] · your roster · their roster · buttons | the countdown, *inside* a card | "We're here", after two roster cards |
| `ResultView` | [error] · outcome · [canReport] who-won · score | the two crest buttons, inside a card | the crest buttons, one card down |

- **First-viewport containers:** `SquadDetailView` **measured: 5 panels /
  8 shapes** (crest header, record, history, roster, invites — plus the W form
  pill, the outcome badge and two Invite buttons). `ResultView` in its
  *confirmed* state **measured: 1 panel / 1 shape** — one card at the top and
  roughly 600pt of empty page below it. `GameDayView` **not captured** (needs a
  live match).
- **`SquadDetailView` is the app's card-stack pattern at its limit:** six
  `cardChrome()` blocks in a single column, each with its own uppercase label,
  and nothing on the screen larger than 22pt.
- **`ResultView` is the opposite failure, and just as structural:** the screen
  that delivers the app's one trustworthy number renders it as two lines of
  13pt body text inside a card, on an otherwise blank page. "You won" is the
  most emotionally loaded string in the product and it is set smaller than the
  word "Seasons" on the tab it came from.

### 6.8 Sheets

2b applies 2c and 2d to these but sets **no structural quota** — a form's layout
is dictated by its fields.

| Sheet | Shape | Container primitive | Note |
|---|---|---|---|
| `CreateGameSheet` | `NavigationStack` → `ScrollView` → 4 hand-rolled cards; toolbar Cancel/Create | its own card recipe (not `cardChrome`) | swaps the form for an invite step on a private run |
| `QueueSheet` | `NavigationStack` → intro + window card + courts | `cardChrome()` ×3 | `ViewThatFits` on the three time chips — they broke mid-word at `.accessibility3` |
| `CreateSquadSheet` | preview + name + crest grids + format + region note | `cardChrome()` ×4 | the crest preview is the one crest that is *feedback* |
| `InboxSheet` | Requests · Squad invites (omitted when empty) · Sent | `FriendRow` + count capsules | page margin 16, unlike the profile's 20 |
| `PlayerProfileSheet` | sideways identity band · read-only rows · `safeAreaInset` action bar | `ProfileRow(onTap: nil)` | band is laid out sideways because a sheet opens at a height it must live within |
| `ProfileEditSheets` (×5) | name · home court · radius · password · appearance | **five different card recipes, margins 16 *and* 20 in one file** | the home-court picker saves on tapping a suggestion, with no Save button |

---

## 7 — Before-screenshots

**Location, deliberately outside the repo:**

```
/private/tmp/claude-501/-Users-aeleot-Documents-hoopr-hoopr/<session>/scratchpad/shots/before/
```

Four variants per screen — `light`/`dark` × `default`/`a11y3` — named
`<screen>-<appearance>-<size>.png`. Captured with
`xcrun simctl io booted screenshot` on **iPhone 17, iOS 26.5**, the app built
from 1a2710d.

```bash
xcrun simctl ui booted appearance light|dark
xcrun simctl ui booted content_size large|accessibility-extra-large
xcrun simctl io booted screenshot <path>
```

`accessibility-extra-large` is `UIContentSizeCategory.accessibilityExtraLarge`,
which is SwiftUI's `.accessibility3` — the size constraint 6 names.

### 7.1 Four environment findings worth recording

These cost real time and will cost it again for whoever runs Phase 2's
after-screenshots.

1. **`CLAUDE.md`'s orphaned-`hoopr` note is real, and its cause is a stale
   `debugserver`.** A `hoopr` process from an Xcode run on 2026-09-20 23:24 was
   still holding the Firestore LevelDB `LOCK` in the app's data container. It
   survived a full simulator shutdown/boot and ignored `kill -9`, because its
   **parent and tracer was a leftover `debugserver`** — a traced process ignores
   SIGKILL until the tracer detaches. `simctl launch` and `simctl terminate`
   both hung against it with no output.

   `CLAUDE.md` prescribes deleting the LOCK sentinel; **that was not
   sufficient here** — the orphan still owned the bundle id, so SpringBoard kept
   handing launches to it. What worked was killing the *debugserver*:

   ```bash
   ps -o pid,ppid,stat,command -p "$(lsof 2>/dev/null | awk '/firestore.*LOCK/{print $2; exit}')"
   # PPID is the debugserver. Kill that, and the app goes Z immediately.
   ```

   Worth folding into `CLAUDE.md`'s troubleshooting note: check `PPID` and the
   `X` (traced) flag in `STAT` before reaching for the sentinel.

2. **The orphan was also rendering the *old* bundle**, so the first round of
   screenshots was of code that is not on `HEAD` — and it ignored both
   `simctl ui appearance` and edits to `appearance.preference`, because it was
   pinned to dark by the preference it had read at launch in September. Any
   screenshot taken while an orphan is alive is worthless; check the PID against
   a fresh `simctl launch` before trusting one.

3. **The simulator's location decides whether the map has anything on it.** A
   fresh device sits in San Francisco, which is outside the six-city dataset, so
   the map renders correctly empty — *"No courts within 14 miles"* — which is
   `gaps/ASSETS_AND_DATA.md`'s coverage behaviour working, not a bug. Set it
   before capturing anything on the Map tab, and relaunch afterwards, because
   `MapView.initialRegion` is read once in `makeUIView`:

   ```bash
   xcrun simctl location booted set 35.9940,-78.8986   # downtown Durham
   ```

   The court **list** updates live from the new fix; the **map region** does not
   until the app is relaunched or the recenter control is tapped. That split is
   `MAP_LAYER.md`'s `initialFix` one-shot behaving as documented, and it is
   confusing in exactly the way that costs ten minutes.

4. **Editing `Library/Preferences/<bundle>.plist` directly does not reach a
   running app.** `cfprefsd` caches it. The value survives on disk and the app
   never sees it. `appearance.preference` was temporarily set to `system` for
   this capture (so the app follows `simctl ui appearance`) **and must be
   restored to `dark`, which is what this simulator had**; the write only takes
   effect while the device is shut down.

### 7.2 Captured — 64 shots, 16 screens and states

| # | Screen / state | File stem |
|---|---|---|
| 1 | `LoginView` — sign-in | `login` |
| 2 | Home — stats, no run scheduled | `home` |
| 3 | Runs — both sections empty | `runs-empty` |
| 4 | Map — Nearby list, Durham | `map-nearby` |
| 5 | Map — court detail card, no runs | `map-courtcard` |
| 6 | Seasons — squad home, `MatchmakingCard` idle | `seasons-squadhome` |
| 7 | `SquadDetailView` — record 1–0, two history rows | `squad-detail` |
| 8 | `ResultView` — **confirmed** state | `result-confirmed` |
| 9 | Profile pane | `profile-pane` |
| 10 | Friends pane — two friends | `friends-pane` |
| 11 | `InboxSheet` — no requests, one sent | `inbox-sheet` |
| 12 | `PlayerProfileSheet` — an existing friend | `playerprofile-sheet` |
| 13 | `CreateGameSheet` — the form | `creategame-sheet` |
| 14 | `QueueSheet` — window + court multi-select | `queue-sheet` |
| 15 | `CreateSquadSheet` — crest grids | `createsquad-sheet` |
| 16 | `HomeCourtPickerSheet` — empty search | `homecourt-sheet` |

Each × `{light,dark}` × `{default,a11y3}`.

### 7.3 What is *not* in the before-shots, and why it matters

**The account has no runs anywhere** — not queued, not public, none at any court
today. So the three compositions the redesign most needs to beat were captured
only in their empty state:

- **`GameCard` is in none of these screenshots.** It is the app's most repeated
  element and 2b's first named target after Home, and there is no before-image
  of it. *(Partly closed 2026-09-21: Phase 1's render harness draws real
  `GameCard`s from synthetic `Game`s — a hosted private run, a joinable public
  run, a waitlisted full run — at HEAD, in both appearances, in the scratchpad's
  `renders/before/`. They are **component** renders, not screens: no tab bar, no
  scroll, no neighbouring cards. Good enough to compare a redesigned card
  against; not a substitute for a populated Runs screen.)*
- **Home's "next run" card** — the answer the screen exists to give — was
  captured as its call-to-action empty state, not as a run.
- **"Hot right now"** and the map's **Now** segment were both captured empty,
  and every map pin is at `CourtHeat` stop 0. The heat ramp's other four stops
  are not photographed.

Two more states are unreachable on this account rather than absent from it:
**Seasons' no-squad hero** (the account has a squad) and **`GameDayView`**
(needs a live match).

Filling these needs a real write to the live Firebase project on the user's
account, which is a decision for them rather than a capture step. Recorded here
so Phase 2's evidence table doesn't compare an after-shot of a populated card
against a before-shot of an empty one — that would flatter the redesign for the
wrong reason.

### 7.4 Two reflow defects the `.accessibility3` shots caught

Neither is a Phase 2 design question; both are existing bugs against
`UI_SHELL.md`'s own invariants, found by looking at the before-shots.

1. **`StatsCard` breaks words mid-word at `.accessibility3`.** Its three columns
   are a fixed `HStack` with two `Divider`s and no `ViewThatFits` ladder, so at
   that size the labels render as "Ru / ns", "Str / eak" and "Last / Run".
   `UI_SHELL.md` names this exact failure — *"Where a row of chips stops
   fitting, `ViewThatFits` takes a column instead of squeezing them: the queue
   sheet's three time chips broke mid-word at `.accessibility3` until it did"* —
   and `StatsCard` never got the same treatment. Visible in
   `home-light-a11y3.png`.

2. **The map's court card truncates both of its own lines at `.accessibility3`.**
   `cardHeader`'s name shows as "East En…" and the metadata line as
   "Durham · 0.…", because the star and close buttons scale with the text and
   take the width the name needs. The name is `lineLimit(2)` but never reaches a
   second line — the `HStack` runs out of width first. Visible in
   `map-courtcard-light-a11y3.png`. `MAP_LAYER.md`'s rule for `CourtRow` is
   *"badges are shed, the name is not"*; the card has no equivalent ladder.

Both are Phase 2 work by default — the screens they live on are being
recomposed — but they are defects against today's rules, not new requirements,
and they should be recorded as closed rather than as features when they go.

## 8 — What the measurements say

Not a design — the design is Phase 2a's job. These are the conclusions the
numbers above force, each one traceable to a section.

### 8.1 The colour system has one surface, not a set of elevations

`hooprSurface` is reached 8 times and almost always through `cardChrome()`
(§3). In light mode it **equals** `hooprBackground` — a deliberate decision
(`ThemeContrastTests.testCardSeparatesFromBackgroundInDarkMode` pins the 1.00:1
explicitly), but it means every "raised" thing in the app is raised by a 1pt
hairline and a 6% shadow, and there is no vocabulary for a second level at all.
That is why the app reads flat: not too few colours, **too few grounds**.
Phase 1's `hooprElevatedSurface` / `hooprHoverFill` / `hooprSeparatorStrong`
land here.

### 8.2 Brand orange is doing two incompatible jobs

73 uses, of which at most 26 are the passing filled case (§3). The rest are
orange drawn as something you *read* — and that is the tracked AA failure, at
**3.17:1** on white where 4.5:1 is the floor (`gaps/ACCESSIBILITY.md`). The
census here is larger than that page's "at least 30" because it counts the role,
not two spellings. Phase 1's `hooprBrandAccent` is what splits the two jobs.

### 8.3 The spacing scale exists but is not written down

231 padding literals, 145 of them on four values (§4.1); 230 `spacing:` uses
across 15 values (§4.2); four live corner radii with no rule (§4.3). The
scale is real — it is just re-typed at every call site, which is why the Runs
tab's title and its cards disagree by 4pt (§4.4) and why the same kind of
button exists at six heights (§4.5). `Support/Spacing.swift` is Phase 1's job.

### 8.4 Three copies of one card, and three jobs with no component

The chrome recipe has drifted into three spellings at two radii and two corner
geometries (§2.1); badges, avatars and the primary button each exist in three
to six hand-rolled copies (§2.3); the uppercase section label has two sizes and
two weights (§2.4). Phase 6 consolidates — but **only where 2c still wants a
card**, and never by re-wrapping content in chrome to reach a tidy count.

### 8.5 Three of four tabs are the same composition, and none of them has a hero

Home, Runs and Seasons all open on a 28pt title + `ProfileButton` row and
continue as a single column of `cardChrome()` cards (§6.1, §6.2, §6.4). On all
three the largest type on the screen carries **no information**: a greeting, the
word "Runs", the word "Seasons". The app's only real heroes are on the three
screens nobody looks at twice — `LoginView`'s 34pt wordmark, the profile's 30pt
handle, and the Seasons **empty** state.

That is the finding the whole revamp turns on, and it is structural rather than
stylistic: **no amount of colour, motion, glass or spacing work changes it.**
Only Phase 2 does.

### 8.6 The constraints the code already keeps

Stated so Phase 2 doesn't spend effort re-establishing them:

- **Zero literal colours in `Views/`** (§2.2). Constraint 1 holds.
- **Zero undocumented `.font(.system(`** — all six uses are fixed-shape glyph
  exceptions `UI_SHELL.md` already names. Constraint 2 holds.
- **`minimumScaleFactor` survives in 11 places** (10 SwiftUI modifiers across 9
  files, plus one `UILabel.minimumScaleFactor` on the map's count badge), and
  `UI_SHELL.md`'s invariant says **never**. Home's greeting (0.65 — the deepest
  floor in the app) and the profile's pane selector (0.8) are the two that
  matter; the rest sit inside fixed-height chrome where the alternative is a
  broken frame. A redesign that demotes the greeting removes the worst of them
  for free.
- **One `hooprGlass` definition, five call sites**, all chrome. Constraint's
  layer rule already holds — Phase 4 extends it rather than introducing it.
- **`ResultPillMetrics` + `SeasonsAccessibilityTests`** is the pattern 2c's
  reflow rule asks every new hero to follow. It exists and it works.

### 8.7 What the screenshots change

Measured container counts (§6, from the light / default shots) land differently
from the estimates the code suggested, and both directions matter:

| Screen | Panels | Total shapes |
|---|---:|---:|
| Map | **1** | 6 |
| Runs (empty) | **0** | 2 |
| Login | 0 | 3 |
| Home | 3 | 4 |
| Seasons — squad home | 3 | 5 |
| `SquadDetailView` | 5 | 8 |
| **Profile** | **7** | **14** |
| `ResultView` (confirmed) | 1 | 1 |

- **The boxiest screen in the app is the profile, not Home.** Seven panels and
  fourteen filled shapes in one screenful, because `ProfileRow` gives every
  field a card *and* a tinted icon tile. `UI_SHELL.md` records the row as the
  fix for a card mosaic whose heights carried meaning — it fixed that and kept
  the card.
- **The emptiest are Runs and `ResultView`**, and they are empty in the way
  that reads as unfinished rather than calm: Runs on this account is a title,
  two collapsed-looking headers and two grey sentences; `ResultView` is two
  lines of 13pt body text with 600pt of nothing under them.
- **§8.5 stands and gets sharper.** Three tabs share one composition *and* the
  two screens at the extremes of the container count are both failures of the
  same kind — nothing on either is sized to what it is worth.

### 8.8 The baseline is green

Constraint 7, measured on 1a2710d before anything changed:

```
xcodebuild test -project hoopr.xcodeproj -scheme hoopr \
  -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:hooprTests
** TEST SUCCEEDED **   463 passed, 0 failed, 0 skipped, 28 suites
```

*(An earlier draft of this section said 462 and that `CLAUDE.md`'s 463 had
drifted. **It hadn't.** The figure came from counting `Test case … passed` lines
in the build log, and one line — `CourtTests.testFallsBackToTheStoredName…` — had
its prefix eaten by interleaved output, so the grep skipped it. The `.xcresult`
says 463, which is what `CLAUDE.md` says. Count from `xcresulttool get
test-results summary`, not from the log.)*

**Measured under Xcode 26.x. Xcode auto-updated to 27.0 (27A266a) partway
through this session**, which wiped the in-repo `build/DerivedData`, briefly
made every `xcrun` call fail on the license agreement, and shut the simulator
down twice mid-capture. It also installed an **iOS 27.0** runtime alongside
26.5. Nothing below iOS 26 is installed, so `gaps/CONFIGURATION.md`'s note that
**nothing has been run below iOS 26** still holds and Phase 4's iOS 18 fallback
still cannot be exercised here. The figure above is a pre-update baseline;
Phase 1 re-runs it under 27.0 first.

**Build note — corrected 2026-09-21.** An earlier draft of this section blamed
`com.apple.provenance` for a `CodeSign … nanopb_nanopb.bundle` failure and
recommended `CODE_SIGNING_ALLOWED=NO`. **Both halves were wrong, and following
the recommendation cost a login-debugging session.**

- **The cause** is that the repo sits on a File Provider–backed volume, so
  anything written *inside* it — including `-derivedDataPath build/DerivedData` —
  is stamped with `com.apple.FinderInfo`, which `codesign` rejects on SPM's
  resource bundles ("resource fork, Finder information, or similar detritus not
  allowed"). `xattr -cr` doesn't hold; the stamp returns mid-build.
  `com.apple.provenance` is not the blocker: a bundle built outside the repo
  carries it and signs fine.
- **The fix** is to build with the default DerivedData, or point
  `-derivedDataPath` at `/tmp` or a scratchpad — never inside the repo.
- **`CODE_SIGNING_ALLOWED=NO` is not a workaround for an app that will be
  installed and run.** It yields a `linker-signed` binary with no
  `application-identifier` entitlement, so `securityd` denies every keychain
  access group and Firebase Auth fails with `-34018` only *after* a correct
  password, because the SDK touches the keychain once the server has accepted
  the credentials. A wrong password still says "Incorrect email or password",
  which is why it reads as a password problem. It is fine for a `test` run that
  never signs in.
- **Check any build you intend to run:** `codesign -dvvv <app>` should show
  `flags=0x2(adhoc)`, not `linker-signed`, and `otool -s __TEXT __entitlements
  <app>/hoopr` should show an `application-identifier`.

---

## 9 — After Phase 1

Re-run of §§2–4's censuses on the working tree after Phase 1 (2026-09-21).
Sections 1–8 stay as measured on 1a2710d; this is the delta against them, and
the narrative lives in `UI_REVAMP_CHANGELOG.md`.

| Measure | Phase 0 (1a2710d) | After Phase 1 |
|---|---:|---:|
| `hooprOrange` uses in `Views/` | 73 | **25** — every one a fill carrying `hooprOnBrand`, the glass tint, or a wash |
| `hooprBrandAccent` uses in `Views/` | — | **52** |
| Views drawing `hooprOrange` as a mark (text / glyph / stroke / tint) | 49 sites, 22 files | **0** — asserted by `BrandMarkUsageTests` |
| Tracked AA failures | 1 (two tests pinning it *failing*) | **0** |
| Roles in `Theme.swift` | 14 | 21 |
| Numeric `.padding(…)` literals in `Views/` | 231 | **172** |
| — of which `16` / `20` | 52 / 39 | 24 / 16 |
| Numeric `spacing:` literals | 230 | 219 |
| `Spacing.*` token uses | — | **70**, across 18 files |
| Literal colours in `Views/` | 0 | 0 |
| `.font(.system(` in `Views/` | 5 documented exceptions | 5, same |
| `minimumScaleFactor` in `Views/` | 11 | 11 — untouched, on purpose |
| `hooprTests` | 463 tests, 28 suites | **481, 30** |

### What the roles table looks like now

Added: `hooprBrandAccent`, `hooprElevatedSurface`, `hooprHoverFill`,
`hooprSeparatorStrong`, `hooprHeat(tier:)`, `hooprOnHeat(tier:)`,
`hooprHeatMaxTier`. `hooprOrange` is now a **fill** and never a mark; the
reasoning, and the measured ratio for every ground, is on the role in
`Theme.swift`. The three elevation roles are defined and asserted but **not yet
drawn anywhere** — they are the floor Phase 2's brief builds on, and adopting
them belongs with the compositions that want them.

### What §8 said, and where it stands

| §8 finding | Status |
|---|---|
| 8.1 One surface, not a set of elevations | **Tokens added, not adopted.** Light mode's page ground is still pure white — a documented, test-pinned decision that Phase 1 does not overturn. Whether it moves is a Phase 2a brief question (see A10 below). |
| 8.2 Brand orange is doing two incompatible jobs | **Closed.** Split into `hooprOrange` (fill) and `hooprBrandAccent` (mark). |
| 8.3 The spacing scale exists but is not written down | **Written down** (`Support/Spacing.swift`). 59 padding literals and 11 spacing literals migrated; the Runs tab's 16-vs-20 inset — the one *visible* inconsistency — fixed. Four screens still inset 16: `InboxSheet`, `QueueSheet`, `GameDayView`, `ResultView`. |
| 8.4 Three copies of one card, three jobs with no component | **Untouched — Phase 6.** `profileRowChrome()` and `FriendRow`'s inline recipe are still there, and the badge and primary-button duplication is if anything one line longer: both run badges now carry a `wash` beside their `foreground`. |
| 8.5 Three of four tabs share one composition, none has a hero | **Untouched — Phase 2. This is the finding the whole revamp turns on**, and no token work touches it. |
| 8.6 Constraints the code already keeps | **Still kept**, re-verified: no literal colours, the same 5 `.font(.system` exceptions, the same 11 `minimumScaleFactor`. |

### Findings Phase 1 added

1. **A real AA failure nobody had listed.** The map pin's count was black on
   every heat tier — 4.01:1 and 3.43:1 on tiers 3 and 4. Fixed
   (`hooprOnHeat(tier:)`), asserted for every tier.
2. **The HOSTING badge measured 2.78:1**, worse than the 3.17 the gap docs
   quoted, because it sits on a wash of orange rather than on the card.
3. **The tab bar's real on-screen figure was 3.01:1 in light**, not the "~2.55"
   the docs said; iOS 26 adjusts a tint before painting it.
4. **A new assumption for Checkpoint 1 — A10.** *Does light mode's page ground
   move off pure white?* Phase 1 defines `hooprElevatedSurface` so that a raised
   surface is a name a view can use, but in light mode it *is* white, because
   nothing is lighter — the lift comes from `hooprShadow`. If the redesign wants
   depth in light mode from the fill, the page ground has to drop, which
   re-tunes `hooprFill` and `hooprBorder` on every screen and overturns
   `testCardSeparatesFromBackgroundInDarkMode`'s recorded decision. It cannot be
   a token-phase side effect.

---

## See also

- `UI_REVAMP_PROMPT.md` — the brief this audit is Phase 0 of.
- `../UI_SHELL.md` — the rationale column of §5, and the invariants every
  redesigned screen still has to keep.
- `../MAP_LAYER.md` — why the map is the one tab that may be kept (§6.3, A4).
- `../gaps/ACCESSIBILITY.md` — the tracked AA failure §8.2 measures.
- `../gaps/GAMES.md` — the invite link and the waitlist, the two things a
  redesign must not draw as working.
- `../PRODUCT_OVERVIEW.md` — the purposes §5 cites.
