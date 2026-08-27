# Plan — App Shell, Home Tab, and Map Search

**Status:** proposed, not started
**Drafted:** 2026-08-26 @ 99342fb
**Touches:** `hoopr/Views/MainTabView.swift`, `hoopr/Views/Tabs/` (new `HomeTab.swift`),
`hoopr/Views/Tabs/MapTab.swift`, `hoopr/ViewModels/` (new `HomeViewModel.swift`),
`hoopr/ViewModels/FindAMatchViewModel.swift`, `hoopr/Support/Theme.swift`,
`hoopr/Services/GameService.swift`, `firestore.indexes.json`, `hooprTests/`

> `context/plans/` is not a dictionary entry and carries no `Scope`/`Verified`
> stamp. A plan describes work that hasn't happened; the dictionary describes
> code that has. When a phase below ships, fold what's true into the dictionary
> entries named in "Documentation debt" and strike it from here.

Move navigation from the floating glass header at the top to a native tab bar at
the bottom, add a **Home** tab that opens the app on "what am I doing today"
instead of dropping the user straight into a map, and give the map tab the
search it has been missing. The shell move is the load-bearing change: it is
what frees the top of the map, what gives the Home tab somewhere to live, and
what hands three accessibility problems back to the system to solve.

---

## 1. Why this is worth doing

**The current header is the constraint everything else is fighting.**
`MainTabView.mainInterface` (`MainTabView.swift:66-101`) pins a glass bar to
**14% of screen height** and floats it over the content. Inside that fixed
budget live a 28pt greeting, a 32pt profile button, and a row of tab pills. The
consequences are visible in the code itself:

- The greeting carries `.lineLimit(2).minimumScaleFactor(0.7)`
  (`MainTabView.swift:138-139`) and the pills carry
  `.minimumScaleFactor(0.8)` (line 197) — **type is shrinking to fit a fixed
  bar.** That is precisely the failure mode `BACKLOG.md` §C4 says to fix "by
  floor-plus-stretch, not by adding a `maximumSize` cap to make the problem
  invisible."
- The pills are 12pt text in a ~40pt-tall row. Apple's floor is
  [44×44pt hit targets](https://developer.apple.com/design/tips/) and 11pt text
  minimum; the pills clear the text floor and miss the target floor.
- `contentShape(Rectangle())` at `MainTabView.swift:94` is load-bearing, not
  decoration — without it every tap on the header fell through to MapKit. A
  hand-rolled bar over a map has to re-solve hit-testing that the system solves
  for free.

**A native tab bar deletes all three problems at once.** It is 44pt-compliant,
Dynamic Type-aware, VoiceOver-labelled, and hit-tested by the system. It also
unlocks the iOS 26 affordances hoopr currently cannot use: badges, a search
role, and `TabBarMinimizeBehavior`.

**Second: opening on the map is the wrong first screen.** The map answers
"where can I hoop?" — a question the user only has once they've decided to go
out. It cannot answer "am I already signed up for something tonight?", which is
the more common reason to open the app. Today that answer is one tab away and
invisible on launch. Strava hit the same wall and split its old Feed/Explore
into **Home / Maps / Record / Groups / You**, moving stats out of the map
entirely ([Cycling Weekly](https://www.cyclingweekly.com/news/product-news/a-new-look-for-strava-app-with-updates-to-the-navigation-bar-498270)).

**Third: the map has no search, and the code already admits it.**
`FindAMatchViewModel.swift:52-53` declares `@Published var searchText: String = ""`
documented as "Text typed into the map's search bar. Debounced into the rebuild
below." **Nothing reads it and there is no debounce.** `emptyStateDetail`
(line 370) tells the user to "Pan the map and tap Search here" — a button that
does not exist. There are 214 courts across six cities and the only way to
reach one is to pan to it.

---

## 2. Scope

**In scope**

- Replace the hand-rolled header with a native `TabView` tab bar at the bottom.
- Three tabs: **Home**, **Map**, **Runs**. Profile stays an icon, not a tab.
- A new Home tab, built in two passes: free data first, history-backed stats
  second.
- Inline court search inside the map's bottom sheet.
- The colour work the tab bar forces (see §5).

**Explicitly out of scope for now**

- Any change to the map's gesture/detent state machine
  (`MapTab.swift:577-621`). It is tested, subtle, and correct; this plan insets
  it, it does not rewrite it.
- The `LocationService.homeLocation` hardcoded-Durham gap (`GAPS.md:436-437`).
  Home-tab distances inherit whatever that returns.
- Attendance confirmation (§6, Phase 4 discusses why this matters).
- iPad/landscape. This plan is iPhone-portrait, same scope note as
  `BACKLOG.md` §C4.

---

## 3. The shell

### 3.1 Tab set

| Tab | Symbol | Contents |
|---|---|---|
| **Home** | `house.fill` | New. Next run, stats, hot courts. |
| **Map** | `map.fill` | Today's `MapTab`, insets adjusted, search added. |
| **Runs** | `calendar` | Today's `LocalRunsTab`, unchanged. |

Three tabs, single-word labels, filled SF Symbols — all three straight from
[HIG Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars):
"keep in mind that it's generally easier to navigate among fewer tabs", "Use
single words whenever possible", "Prefer filled symbols or icons for
consistency with the platform."

`MainTabView.swift:18-21` already anticipates this: *"Adding the next one means
adding a case here and a branch in `content(headerHeight:)` — nothing else in
the header is written for a fixed count."*

### 3.2 Why Profile is not a tab

The user's call, and the HIG agrees for a different reason: *"Use a tab bar to
support navigation, not to provide actions."* Profile is a destination, but it
is a **rare** one — home court, radius, appearance, sign-out, friends. Spending
25% of the tab bar on a screen visited once a week, while the friend-request
badge already solves discoverability, is a bad trade.

So Profile stays a button, and per the request it appears **on every tab except
itself**:

- **Home and Runs** get a real `.toolbar` trailing item inside their
  `NavigationStack`. This is a straight upgrade — they currently borrow the
  floating header and get nothing else from it.
- **Map** keeps a floating glass button, top-trailing, because the map must run
  edge to edge. Match the recenter button exactly — 46×46 glass circle,
  `MapTab.swift:242-254` — so the two floating controls read as one family.

Keep the existing red badge dot and its `hasUnansweredRequests` logic verbatim
(`MainTabView.swift:159-170, 235-237`); only its container changes. Its comment
about red-not-orange stays true and should move with it.

### 3.3 What happens to the greeting

`Text("Let's go hoop \(userName).")` is the app's only piece of voice. It does
not disappear — it becomes the **Home tab's large title**, where it has a full
line of width instead of 14% of the screen minus a profile button, and can stop
scaling itself down to 70%.

### 3.4 MapTab must stay mounted

`MainTabView.swift:112-113` keeps MapTab alive via `.opacity`/`.allowsHitTesting`
specifically to preserve map region and sheet state. **SwiftUI's `TabView`
already does this** — tab content is retained after first appearance. Drop the
opacity hack and let the system own it. `LocalRunsTab`'s
`@AppStorage("localRuns.queuedExpanded"/"localRuns.publicExpanded")`
(`LocalRunsTab.swift:14-15`) exists because that tab currently *unmounts*; once
under `TabView` it stays mounted, so the `@AppStorage` becomes cross-launch
persistence rather than a workaround. Leave it — it is strictly better this way,
but note it in `UI_SHELL.md` so the next reader knows why it is there.

### 3.5 `floatingHeaderHeight` goes away

The `@Entry var floatingHeaderHeight` environment key
(`MainTabView.swift:248-250`) exists solely to tell MapTab how far down to push
its chrome. With no floating header, MapTab's chrome insets from the **safe
area** like everything else. Delete the key and its read at `MapTab.swift:67`.

---

## 4. The map tab

The bottom tab bar collides with the custom bottom sheet. That is the only real
structural problem in this plan, and it has a clean answer.

### 4.1 Sheet insets

The sheet's height budget shrinks by the tab bar. In `MapTab.swift:97-98`:

```swift
mediumHeight   = containerHeight / 3          // → (containerHeight - tabBarHeight) / 3
expandedHeight = containerHeight * 0.78       // → (containerHeight - tabBarHeight) * 0.78
```

and the **collapsed** detent's peek pill (`collapsedPeek`, lines 287-312) now
rests just above the tab bar instead of at the screen edge.

The floating chrome already insets itself by
`max(0, sheetHeight - sheetOffset)` (lines 189-191) — that arithmetic is
unchanged, it just operates on smaller numbers. Do **not** touch
`sheetDragGesture`, `resistance(_:)`, `nextDetent`, or the `Detent`/`SheetState`
machine. They are described as invariants in `MAP_LAYER.md` §Invariants and
they are correct.

### 4.2 Do not convert the sheet to a native `.sheet`

Tempting — `presentationDetents` plus `presentationBackgroundInteraction` is the
Apple Maps pattern — but a native sheet **covers the tab bar**. HIG permits that
("The exception is when a modal view covers the tab bar, because a modal is
temporary and self-contained"), but hoopr's sheet is not temporary: it is the
court list, up almost all the time. Covering the tab bar with it means the user
cannot leave the map without dismissing the sheet first. Keep the custom sheet.

### 4.3 Search goes inline in the sheet, not in the tab bar

The HIG offers three placements: a search tab, a toolbar, or inline. **Inline is
the right one here**, and
[HIG Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields)
describes hoopr's exact situation: *"Place search as an inline field when its
position alongside the content it searches strengthens that relationship... This
pattern is useful if your app has more than one search field and if location
plays a critical role in the scope of your search."*

hoopr has two search fields already — the home-court picker
(`ProfileEditSheets.swift:156-194`) and player search
(`FriendsPane.swift:38-88`). A global search tab would have to answer "courts or
players?", which is a worse experience than two scoped fields that each know
what they search.

**Placement:** directly under the drag handle in `sheetHeader`
(`MapTab.swift:414-428`), above the Nearby/Favorites/Recent segments. Reuse
`ProfileEditSheets.swift:156-194`'s field chrome — magnifying glass, clear
button, orange focus ring — so the two court searches look identical.

**Matcher:** reuse the logic at `ProfileEditSheets.swift:100-112` — name
`localizedCaseInsensitiveContains` first, then city-only matches. Lift it out of
that file into a shared pure function so both call sites share one definition
and one test. Note the known bug it carries: it matches full `name`, not
`displayName` (`GAPS.md:148`). Fix it in the lift, and both callers get the fix.

**Scope behaviour:** while `searchText` is non-empty, search **all** courts, not
just the active segment. HIG: *"Default to a broader scope and let people refine
it as they need."* A search that silently only looks at Favorites is a search
that appears broken.

**What search does *not* do:** it does not re-filter the map pins. Searching
narrows the **list**; tapping a result calls the existing
`select(_:recenter: true)` (`MapTab.swift:636-647`), which selects the pin and
flies the map to it. That reuses plumbing that already works and keeps a single
meaning for what the map shows.

**Wiring:** revive `FindAMatchViewModel.searchText` (line 52) — the property is
already declared and documented for exactly this. Add the 300ms debounce its
comment promises, copying the shape from `FriendsViewModel`'s debounce
(`FriendsViewModel.swift:290`). Delete the stale "Pan the map and tap Search
here" copy at `FindAMatchViewModel.swift:370` and replace it with an
empty-search-result string.

### 4.4 Filter chips

Unchanged in behaviour, but they lose the header above them and now inset from
the safe area. Three chips — Lit, 2+ hoops, Public — still fit one row.

---

## 5. The colour problem the tab bar creates

**This is the highest-risk detail in the plan and it is easy to miss.**

Today `hooprOrange` is only ever used as a **background**, with
`hooprOnBrand` (black) drawn on it — 9.17:1, passing comfortably. A native tab
bar inverts that: the selected tab's glyph and label are drawn **in** the accent
colour, on glass. That is the pairing `ThemeContrastTests.testBrandAsForegroundIsATrackedGap`
already pins as a **known failure** — 2.55:1 light / 2.34:1 dark, recorded in
`GAPS.md:110-135`.

`hooprDarkOrange` does not rescue it either. It is currently painted nowhere,
so it looks like a free answer, but at `rgb(214, 93, 43)` on white it measures
**≈3.85:1** — clears AA Large (3.0), fails AA normal text (4.5). Tab bar labels
are ~10pt. They need 4.5.

### The recommendation: a monochrome tab bar

Do not tint the tab bar with the brand at all. Selected =
`hooprPrimaryText`, unselected = `hooprSecondaryText`. Both already pass in both
appearances and both are already tested.

This is not a workaround, it is what the HIG asks for: *"Avoid applying a
similar color to tab labels and content layer backgrounds. If your app already
has bright, colorful content in the content layer, prefer a monochromatic
appearance for tab bars."* The map's content layer is **literally a field of
orange heat pins** (`CourtHeat` runs `EE6730 → BF2010`). An orange tab bar over
it would be the exact collision that sentence describes.

### If brand tint is wanted anyway

Then a **new** role is required — neither existing orange works. A starting
value of roughly `#B4491E` measures ≈5.4:1 on white, with headroom to tune. Add
it as `hooprOrangeText`, give it an assertion in `ThemeContrastTests`, and note
that this is the token that finally closes the `GAPS.md` tracked gap — which
means `testBrandAsForegroundIsATrackedGap` (line 158) will start **failing on
purpose**, exactly as its own message instructs. Replace it in the same commit.

---

## 6. The Home tab

### 6.1 What a home screen is for

Research across the comparable apps converges on one thing: **a home screen
answers "what next?", not "how good am I?"** Strava's redesign is the cleanest
statement of it — Home is the feed, and every personal stat moved into a
separate **You** tab. Stats belong on Home only as far as they motivate the next
outing.

So the ordering below is deliberate: commitment first, then momentum, then
opportunity.

### 6.2 The cards

**1. Next run** — the hero, and the reason the tab exists.

Court name, `scheduledText` ("Today, 6:30 PM"), roster "6/10", and the run's
badge. If the user is on nothing, this becomes a call to action — "No runs lined
up" plus a **Find a court** button that switches to the Map tab.

*Data: free.* `GameService.queuedGames` is already sorted by `scheduledTime`
(`GameService.swift:159`); take the first. `Game.scheduledText(relativeTo:)` and
`rosterText` already exist. Reuse `GameCard` (`Views/Games/GameCard.swift`) —
it is documented as state-free and already renders exactly this.

**2. This week** — a row of stat tiles.

Runs this week · week streak · courts played. **This is the only card that
needs new data** — see §6.3.

**3. Hot right now** — the top three courts by today's game count.

*Data: free, and this is the nice one.*
`FindAMatchViewModel.gameCountsByCourt(queued:published:now:)`
(`FindAMatchViewModel.swift:278-293`) is **`nonisolated static` and pure** —
explicitly written that way for testability. Home can call it directly against
`GameService`'s two published arrays. No new listener, no new query, no new
model. Render rows with the existing `CourtRow`, tint by `CourtHeat.color(forGameCount:)`
so a court's colour means the same thing here as on the map. Tapping one
switches to Map with that court selected and recentered.

**4. Friend requests** — render only when `friendService.incomingRequests` is
non-empty. Opens `InboxSheet`. *Data: free.*

### 6.3 The honest constraint: there is no history

**Nothing in hoopr records that a run happened.** Two facts, both verified:

1. `Game.status` declares `inProgress` and `completed`, but **nothing ever
   writes them** (`Game.swift:14`). A run just ages past `visibilityGrace` and
   vanishes.
2. Both listeners are windowed to the future —
   `.whereField(scheduledTime, isGreaterThan: cutoff)` at
   `GameService.swift:158` and `:178`, where `cutoff = now - 3h`.

So "games played this week" and any streak **cannot** be computed from what the
client currently holds. What they need:

**The good news — no rules change is required.** The `games` read rule
(`firestore.rules:116-119`) admits any document where
`request.auth.uid in resource.data.playerIds`, **with no date bound at all**.
The date window is a client-side choice in the query, not a server-side
restriction. A past-games query is already legal:

```
games
  .whereField(playerIds, arrayContains: uid)
  .whereField(scheduledTime, isLessThan: now)
  .whereField(scheduledTime, isGreaterThan: windowStart)
  .order(by: scheduledTime)
```

This needs a **composite index** (`firestore.indexes.json`) but not a rules
edit. Fetch it once on Home appearance — a `getDocuments`, not a listener; past
games do not change.

**Do not store a counter on the profile.** The `users` update rule
(`firestore.rules:58-77`) uses
`diff(resource.data).affectedKeys().hasOnly([...])`, so any new field means a
rules change *and* a `FirestoreRulesParityTests` update. Worse, a client-written
streak is forgeable by anyone with the SDK. Deriving it from the games query
costs one read and cannot be faked.

### 6.4 Two things to be honest about in the copy

**"Played" is a claim the data cannot support.** Nobody confirms attendance. All
the query proves is that the user was **on the roster** of a run whose time has
passed. Label it accordingly — **"Runs this week"**, not "Games played". If a
truer number is wanted later, that is an attendance-confirmation feature, and it
should be scoped on its own rather than smuggled in behind a stat tile.

**Make the streak weekly, not daily.** Pickup basketball is not a daily
activity; a daily streak would break for almost every user in week one, and a
streak that always reads 0 is worse than no streak. The habit-design literature
is consistent here — set a low bar and match the activity's natural cadence, and
weekly streaks work better for products with weekly rhythms
([Trophy](https://trophy.so/blog/when-your-app-needs-streak-feature),
[makeit.tools](https://www.makeit.tools/blogs/how-to-design-an-effective-streak-2)).
Duolingo's own writeup describes lowering the bar as the change that actually
grew streaks ([Duolingo blog](https://blog.duolingo.com/improving-the-streak)).

So: **"weeks in a row with at least one run."** One run in a week keeps it. Show
it only once it is ≥2 — a streak of 1 is not an achievement, and displaying it
teaches the user that the number is noise.

---

## 7. Phases

Each phase is independently shippable and independently revertable.

### Phase 0 — Decisions

Settle before writing code, because each one changes the shape of the rest:
tab labels, monochrome vs branded tab bar (§5), and whether Phase 4 ships at all
given §6.4.

### Phase 1 — Shell move only

Native `TabView` at the bottom. Three tabs, but **Home renders a placeholder** —
no new features in this phase. Delete the floating header, the
`floatingHeaderHeight` key, and the `.opacity` mount hack. Add the profile
button to each tab's toolbar and the map's floating chrome. Inset the map sheet
(§4.1). Apply the tab bar colour decision (§5).

*Ship-check:* every screen at the largest accessibility text size — the greeting
and tab labels must **stretch, not shrink**; nothing should hit
`minimumScaleFactor`. VoiceOver across the tab bar announcing selection state.
Both appearances. Confirm the map still holds its region across a tab switch and
back, and that the sheet's three detents and the peek pill all clear the tab
bar.

### Phase 2 — Home tab, free data only

Next run, hot courts, friend requests (§6.2 cards 1, 3, 4). No new queries, no
new services, no new model. **The "This week" card is not built in this phase.**
Change the launch tab to Home.

*Ship-check:* an account with a run tonight and an account with none — both
should get a useful screen. Tapping a hot court must land on the map with that
pin selected and centred.

### Phase 3 — Map search

Lift the matcher out of `ProfileEditSheets.swift`, fix the
`name`/`displayName` bug in the lift, wire `searchText` with a 300ms debounce,
add the field to `sheetHeader`, replace the stale empty-state copy.

*Ship-check:* search a court in another city — it must appear in the list even
though it is far outside the radius, and selecting it must fly the map there.
Search while Favorites is the active segment and confirm the scope broadens.

### Phase 4 — History and stats

The past-games query, the composite index, the streak derivation, the "This
week" card.

*Ship-check:* seed an account with runs across three past weeks including a
skipped week, and confirm the streak resets at the gap and not before. Verify
the query returns nothing for a brand-new account without erroring.

### Phase 5 — Polish, later, not now

`TabBarMinimizeBehavior` so the tab bar recedes as the court list scrolls; a tab
bar badge on Runs when a run starts within the hour.

---

## 8. Testing

New assertions, in the style of the suites that already exist:

- **`ThemeContrastTests`** — an assertion for whatever the tab bar selection
  colour resolves to, in both appearances. If §5's fallback is taken,
  `testBrandAsForegroundIsATrackedGap` must be replaced in the same commit.
  `UI_SHELL.md` states this as an invariant.
- **Court matcher** — a new suite for the lifted matcher: name before city,
  `displayName` matching (the `GAPS.md:148` fix), limit behaviour, empty query.
- **Streak derivation** — write it as a pure `nonisolated static` function over
  `[Game]` and a reference date, mirroring
  `gameCountsByCourt(queued:published:now:)`. Test the gap reset, the
  same-week-twice case, and the week boundary against `Calendar.current`.
- **`FirestoreRulesParityTests`** — only if §6.3's advice is ignored and a
  profile counter is added.

`BUILD_AND_CONFIG.md` carries the coverage table; update it. Tests run scoped:

```bash
xcodebuild test -scheme hoopr -only-testing:hooprTests
```

---

## 9. Risks and honest limitations

- **The sheet insets are the real risk.** `MapTab` is 670 lines of tuned
  geometry and the detent maths threads through chrome insets, peek opacity, and
  rubber-banding. Changing two constants is the intent; verify all three detents
  and the collapsed pill on the smallest supported device, where
  `containerHeight/3` minus a tab bar is tightest.
- **Home's stats depend on a query nobody has run in production.** The rules
  permit it and the index is cheap, but the read volume grows with a user's
  history and there is no pagination in the design. Bound the window to the
  streak's needs (~12 weeks), not "all time".
- **The streak may simply not be worth shipping.** If real usage is roughly one
  run a fortnight, a weekly streak reads 0 or 1 forever and becomes a reminder
  of failure. Phase 4 is deliberately last so this can be judged against real
  data rather than assumed.
- **Distances on Home inherit the hardcoded-Durham bug** — everything measures
  from `LocationService.homeLocation` (`GAPS.md:436-437`). Home does not make
  this worse, but it puts a wrong number on the first screen instead of the
  second.
- **`FindAMatchViewModel` is misnamed** and this plan gives it a second consumer
  (Home calls its static counter). `GAPS.md:443-445` already wants it renamed to
  match `MapTab`; doing it in Phase 2 is cheap and gets cheaper than doing it
  later.

---

## 10. Open questions

1. **Does Home replace the Runs tab eventually?** If Home's next-run card grows
   a list, Runs becomes redundant and the tab bar drops to two. Worth watching,
   not worth pre-deciding.
2. **Does the map keep Nearby/Favorites/Recent once search exists?** Search may
   absorb Recent entirely. Keep all three through Phase 3 and revisit with usage.
3. **Should the launch tab be sticky?** Opening on Home is right for a cold
   launch; a user who was on the map 30 seconds ago may disagree.
4. **Attendance confirmation** — the feature that would make "games played"
   truthful. Related to `plans/LIVE_HEADCOUNT.md`, which builds `checkins/{uid}`
   but states "Headcount is present-tense only" (line 79) and names
   `checkinHistory` as future work (line 300). If check-in history ships there,
   it is a **better** source for §6.3 than the games query.

---

## 11. Documentation debt

| Entry | Change |
|---|---|
| `UI_SHELL.md` | Rewrite the Navigation tree and `MainTabView` sections for the tab bar; add Home; record why `LocalRunsTab`'s `@AppStorage` survives (§3.4); drop `floatingHeaderHeight` and the `contentShape` note; update the colour-role table if a token is added. |
| `MAP_LAYER.md` | New sheet insets and detent arithmetic; the search field in `sheetHeader`; chrome now insets from safe area, not `floatingHeaderHeight`. |
| `DATA_MODEL.md` | Only if Phase 4 adds a model. The query alone needs no entry. |
| `BUILD_AND_CONFIG.md` | New index in `firestore.indexes.json`; the new test suites in the coverage table. |
| `GAPS.md` | Strike the dead `searchText` and the stale "Search here" copy (Phase 3); strike or restate the brand-as-foreground gap (§5); strike `FindAMatchViewModel`'s rename if done. |
| `PRODUCT_OVERVIEW.md` | "What a user can do today" gains a home screen and court search. |
| `INDEX.md` | Add this plan to the `| Plan | Status |` table (lines 56-69). |

---

## See also

- `context/UI_SHELL.md` — the current shell, and its Invariants list.
- `context/MAP_LAYER.md` — the map's detent state machine and its Invariants.
- `context/GAPS.md` — the brand-as-foreground gap, the dead `searchText`, the
  hardcoded Durham origin, the `FindAMatchViewModel` rename.
- `context/plans/BACKLOG.md` — §C4 accessibility audit, which Phase 1 partly
  discharges; Track A (Queue Up), which would want a home-screen entry point.
- `context/plans/LIVE_HEADCOUNT.md` — `checkins/{uid}`, the better long-term
  source for attendance-backed stats.
- [HIG — Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars)
- [HIG — Search fields](https://developer.apple.com/design/human-interface-guidelines/search-fields)
- [Apple — UI design dos and don'ts](https://developer.apple.com/design/tips/)
- [Weber — Rules for building user interfaces](https://weberdominik.com/blog/rules-user-interfaces/)
