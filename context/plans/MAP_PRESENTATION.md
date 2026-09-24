# hoopsRN — Map Tab Presentation Plan

**Status:** plan (nothing here is implemented)
**Scope:** `hoopr/Views/Tabs/MapTab.swift`, `MapView.swift`, `CourtRow.swift`,
`CourtGameRow.swift`, `SheetGeometry.swift`, and the sheet-side components they
use. Read `context/MAP_LAYER.md` for the interaction machinery this plan must
not break — it is load-bearing and referenced throughout.
**Why now:** the UI revamp (Phases 1–6) gave the other three tabs a coherent
design language. The map tab kept its functionality and gained glowing pins,
but its presentation still speaks the pre-revamp dialect. This plan brings it
to parity without touching the interaction model.

---

## 1. The language the rest of the app now speaks

The revamp's conventions, evidenced in `HomeTab.swift`, `RunsBand.swift`, and
`Views/Components/`:

1. **Type roles, not point sizes.** Everything renders through
   `.hooprType(.role)` — `numeral / display / title / headline / subhead /
   body / caption / label` (`Support/Typography.swift`). Raw
   `.hooprFont(16)` survives only where a frame can't grow.
2. **Rows on the page, grouped by hairlines.** Home's hot list and the profile
   draw rows directly on the surface with `Divider() + hooprBorder`; cards are
   reserved for things that genuinely float (`StatsCard`, `GameCard`).
3. **Facts are icon + number + unit**, laid out in `FlowLayout`, with the
   number carrying weight and `hooprPrimaryText` while the unit stays
   secondary. The "city · distance" string-in-one-color pattern is gone.
4. **Spacing tokens.** `Spacing.pageMargin / md / lg / …` everywhere;
   `CardChrome` defaults to radius 16 with its own documented shadow/hairline
   recipe.
5. **A brand moment per tab.** Home has the wordmark + ball wash band; Runs has
   the court-emblem wash + week strip. Each tab answers its own question in the
   app's own mark and colour.
6. **Activity is visible.** A busy court glows — `CourtGlowHalo` on Home's hot
   rows, the keyframe halo on the pins (`MAP_LAYER.md`, CourtHeat §).
7. **Motion from the token file.** `.hooprSpring` / `.hooprSnap` (and the rest
   of `Support/Motion.swift`) instead of ad-hoc animations and bare
   `.opacity` transitions.

## 2. Where the map tab diverges

Concrete, in the order a reader notices them:

| # | Divergence | Evidence |
|---|---|---|
| 1 | Raw point sizes in sheet content: `hooprFont(16/13/15/17)` on list rows, search rows, empty states, sheet header | `MapTab.swift` (`searchResultRow`, `emptyStateContent`, `sheetHeader`, `collapsedPeek`); `CourtRow.swift`, `CourtGameRow.swift` |
| 2 | Magic insets: row leading `20`/`8`/`16`, chrome `14`, search-row trailing `Spacing.pageMargin` — three margin dialects on one screen | `CourtRow.swift` (leading 20, trailing 8), `CourtGameRow.swift` (leading 20, trailing 16), `MapTab.swift` (chrome 14) |
| 3 | Run rows in `cardChrome(cornerRadius: 12)` — smaller radius than `CardChrome`'s default 16, and boxed rows where the rest of the app now groups by hairline | `MapTab.swift` (`runRow`) |
| 4 | No activity echo in the lists: Home's hot rows carry the heat dot + `CourtGlowHalo` (the pins' own signal), but the Now segment shows a spots pill only and Nearby/Saved show nothing | `HomeTab.swift` (`hotCourtRow`) vs `CourtGameRow.swift`, `CourtRow.swift` |
| 5 | Plain-text meta ("Durham · 1.2 mi away") instead of the icon-fact shape | `CourtRow.swift`, `CourtGameRow.swift`, `searchResultRow` |
| 6 | Sheet pane swaps use bare `.transition(.opacity)`; no motion vocabulary on the tab's biggest state change | `MapTab.swift` (`sheet`) |
| 7 | Empty states set in raw sizes with a `secondaryText.opacity(0.45)` glyph — an opacity literal no other screen uses | `MapTab.swift` (`emptyStateContent`, `searchEmptyState`) |
| 8 | No brand moment. Every other tab opens with the app's mark in its own colour; the map opens with utility chrome. The sheet — the tab's real surface — has no identity either: an anonymous rounded slab | `MapTab.swift` (whole file) |
| 9 | Sheet corner radius `22` is its own literal, unrelated to any radius token | `MapTab.swift` (`sheet`) |
| 10 | The map-specific components (sheet chrome, rows, peek) aren't represented in the Phase-5 component gallery, so drift like the above has no single place to be caught | `Views/Debug/` |

What is **not** divergent — keep: the fitted `.medium` card height, the pinned
action row, the run-row read order (time → spots → standing), glass chrome over
the map, the recenter placement, and the pin system itself (glow, count, heat).

## 3. The plan — six passes, smallest first

Each pass is one commit-sized unit, independently verifiable. Passes 1–3 are
mechanical; passes 4–6 are where the tab starts to *look* designed.

### Pass 1 — Typography and spacing tokens (mechanical)

- Migrate every raw `hooprFont` in the sheet's content to `.hooprType`:
  list/search row names → `.subhead` semibold, meta → `.body` secondary,
  count header → `.label`, empty-state title/detail → `.headline`/`.body`.
  Keep `maximumSize` only where the frame can't grow (chips, pills, handle).
- Replace all magic insets with `Spacing` tokens. Rows align to
  `Spacing.pageMargin` on both sides like every other list in the app; the
  divider indent follows the text, not a literal `20`.
- Replace the `opacity(0.45)` glyph with a role colour at full alpha
  (`.secondaryText` is the app's quiet; a one-off alpha is a literal colour in
  disguise).
- No layout change. If a row's height or a header's position moves, that's a
  bug, not a refresh.

### Pass 2 — One court row

`CourtRow` (Nearby/Saved), `CourtGameRow` (Now), and `searchResultRow` are
three drawings of "a court, tappable." Fold them into one `CourtListRow`
component with a small configuration surface (activity style: none / next-run;
trailing: star / none) in `Views/Components/`:

- Name via the shared `CourtName` rule; meta as the icon-fact shape (map-pin +
  city, location + distance) on a wrapping `FlowLayout`, matching Home's
  detail line.
- **Activity echo:** the Now configuration leads with the heat dot +
  `CourtGlowHalo` (the same two views Home's hot rows draw), so the list and
  the pins state the same fact the same way. Nearby/Saved rows may add the
  quiet dot (no halo) when a court has runs today — parity with the pins at a
  glance, capped at the `CourtHeat.maxTier` ceiling Home uses.
- The Now row keeps its time + spots column; the spots pill stays the filled
  `HooprBadge` (`CourtGameRow`'s current treatment is the standard — don't
  regress it).
- Uniform row height discipline (`badgeLineHeight` floor) survives the merge;
  a test pins it, as `CourtRow`'s comment records.

### Pass 3 — Sheet chrome and motion

- Extract a `SheetHeader` component: handle + title, used identically by the
  list pane, the detail card, and the search pane. Today the three panes draw
  the handle separately and the search pane skips the title — one component
  makes them the same object.
- Route the pane swap through the motion tokens: content transitions on
  `.hooprSpring` with a short move-and-fade instead of bare opacity (per
  `Motion.swift`'s vocabulary — match what the revamp used elsewhere; don't
  invent a new curve here).
- Sheet radius becomes a named constant beside the sheet code (22 is fine as a
  value; what it must not be is an anonymous literal three uses deep).
- The peek pill (`collapsedPeek`) gets the same treatment: `.hooprType`, token
  padding, and — new — **a live heat dot**: when any court in the current
  filter has runs today, the pill leads with the glowing dot and its label
  reads "3 courts live" instead of "116 courts nearby". The collapsed state of
  the tab is its most-seen frame; right now it says nothing the map doesn't.

### Pass 4 — Detail card to the new row language

The card's structure is right — runs lead, badges follow, actions pinned, the
fitted `.medium` preserved. What ages it is that each run sits in its own
mini-card:

- Render the runs as **rows grouped by hairline** (leading-aligned dividers,
  the Home hot-list shape) instead of `cardChrome(12)` boxes. The run's
  standing badge, waitlist note, and the one-write-in-flight button behavior
  carry over unchanged — only the chrome changes.
- The "No runs here today" lead line stays; set in `.body` secondary it
  already matches.
- Re-measure after the change: `cardLeadHeight` drives the fitted medium, so
  the sheet must still rest tall enough to show the first run whole. The
  invariant is the *outcome* (first run visible at `.medium`), not the current
  numbers.

### Pass 5 — Empty and loading states

Match the tone the other tabs set: a structured empty state (icon in a role
colour, title in `.headline`, one explanatory line in `.body`) for all three
segments and for search — and separate **loading from empty** the way Home
does with `hasLoaded`: "Checking what's on…" while `GameService` hasn't
answered, the empty sentence only after it has. The pinned "Start a run" CTA
in the Now empty state stays exactly where it is.

### Pass 6 — The tab's brand moment

The map is the hero; the brand should enter through the sheet, not over the
canvas. Two moves, both small:

1. **`SheetHeader` title in the tab's voice.** "116 courts nearby" is data;
   the header that carries it can carry the brand's warmth — an
   `hooprBrandAccent` glyph (the court symbol, via `CourtSymbol`) beside the
   count, the same accent-with-icon pattern RunsBandStat and Home's open state
   use. No wash, no band: a mark, not a mural.
2. **The peek pill is the tab's wordmark** (Pass 3): it's the first thing seen
   on every cold open of the tab, and it should read as the app's own
   sentence about the map — live, warm, and specific.

Explicitly rejected: a `HeroWash` band over the map (the map *is* the design;
dimming it to brand it costs the thing the tab is for), and any new floating
logo in the chrome (the wordmark belongs to Home).

### Pass 7 — Gallery, docs, drift

- Add the map's components (`CourtListRow`, `SheetHeader`, the peek, the
  detail card's run row) to the Phase-5 component gallery so the next drift is
  visible in one place.
- Update `context/MAP_LAYER.md`'s "Map chrome" and "court detail card"
  sections and run `tools/check_context_drift.py`.

## 4. Invariants this plan must not break

From `MAP_LAYER.md`, all load-bearing:

- The detent state machine: `SheetState` / `displayDetent` semantics, the
  fitted `.medium` (`cardFittedHeight`), `containerHeight` net of
  `tabBarInset`, keyboard-feeds-detents behavior.
- Drag ownership (handle vs. list top), one detent per gesture, tap-slop.
- The UUID trigger pattern for `RecenterTrigger`; annotation diffing by
  `court.id`; `biasedNorth(_:)` on every `setRegion`.
- `viewFor` never sets `clusteringIdentifier`; pin colours/labels come only
  from `CourtHeat` / `CourtHeat.labelColor`; the restyle loop in
  `updateUIView` keeps calling `configureAsCourt`.
- One write in flight (`pendingGameId`); roster actions resolve through
  `MapViewModel.action(for:)` → `LocalRunsViewModel.action(for:)`.
- The recenter button's hide rules (`.expanded`, searching); the chip row drops
  while focused; no `.ignoresSafeArea(.keyboard)`.
- `CourtRow`'s uniform-height discipline and the `ViewThatFits` badge ladder
  (a caution badge is never the one shed).
- No literal colours in views; new pairings asserted in `ThemeContrastTests`;
  Dynamic Type pass at `.accessibility3` (the card header's give-way order —
  name sheds "Park", then number — must survive Pass 2's row merge).

## 5. Verification

After each pass:

1. `xcodebuild test -project hoopr.xcodeproj -scheme hoopr -destination
   'platform=iOS Simulator,name=iPhone 17' -only-testing:hooprTests` — green.
2. New/changed pairings asserted in `ThemeContrastTests` (the filled spots
   pill and any peek tint especially).
3. Simulator pass: both appearances, default and `.accessibility3`, the four
   detents × {list, detail, search}, a segment switch, a live join, a
   favorite toggle.
4. The detail card still rests tall enough to show its first run whole at
   `.medium` (the original complaint this layout fixed).

## 6. Out of scope

- Basemap styling beyond the existing muting (custom tiles / MapLibre —
  `MAP_LAYER.md` names the ceiling).
- Reintroducing clustering or zoom controls (removed, documented, gone).
- Anything touching `Services/`, view models' join logic, or Firestore.
