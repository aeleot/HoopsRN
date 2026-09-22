# UI Revamp Prompt — hoopsRN

A paste-ready prompt for an LLM coding agent (e.g. Claude Code). It revamps the
UI of a SwiftUI iOS app that is currently a functional but visually vanilla POC
shell. The goal: a more engaging, dynamic, polished interface — redesigned
screen compositions (Phase 2: a redesign, not a re-skin of today's layouts), a
better color system, better organization, richer motion and materials —
**without breaking the architectural and accessibility invariants the codebase
already enforces, or the utility each feature gives the user**.

---

## The prompt (copy everything below the line into your agent)

---

You are a senior iOS design engineer. Revamp the user interface of **hoopsRN**,
a SwiftUI pickup-basketball app (deployment target **iOS 18.0** — iOS 26 APIs
such as Liquid Glass are availability-gated with a fallback; Xcode project
`hoopr.xcodeproj`). The backend and architecture are solid; the UI is a plain
shell and needs to become engaging, dynamic, and visually distinctive while
staying fully accessible and appearance-aware. This is a **redesign, not a
re-skin**: the layouts of the screens are expected to change (Phase 2), starting
from what each feature is for. Read `CLAUDE.md` and route
through `context/INDEX.md` before touching anything — especially
`context/UI_SHELL.md` (navigation + visual conventions), `context/MAP_LAYER.md`
(map tab), and `context/GAPS.md` (known issues).

### Hard constraints — do not violate these

1. **No literal colors in `Views/`.** Every color comes from a role in
   `Support/Theme.swift`, resolved per appearance through the `UIColor` dynamic
   provider. A literal `.black`, `.white`, or RGB value in a view is a bug.
2. **All type goes through `.hooprFont(_:weight:maximumSize:)`** in
   `Support/Typography.swift`. Use `maximumSize` only where the frame cannot
   grow; never `minimumScaleFactor`.
3. **Every new color pairing must clear WCAG AA**, and you must *assert* it in
   `ThemeContrastTests`, not eyeball it. Note the one deliberately tracked
   exception: `hooprOrange` as a foreground in light mode currently fails (see
   `GAPS.md`) — your color-system work should **fix** this by introducing a
   readable brand-foreground role, not by re-tuning `hooprOrange` itself.
4. **Keep the native `TabView`.** Do not rebuild a hand-rolled tab bar — the
   system one supplies 44pt targets, Dynamic Type, VoiceOver, and correct hit
   testing over MapKit.
5. **Preserve the service / view-model / view split.** No Firebase types outside
   `Services/`; view models take dependencies via `init()`; one write in flight
   per screen, keyed by what its rows are about.
6. **Dynamic Type and accessibility are non-negotiable.** Test at
   `.accessibility3`; fixed-diameter shapes must cap with `maximumSize` and
   there is a test measuring this (`SeasonsAccessibilityTests`).
7. The full unit suite must pass after every phase:
   `xcodebuild test -project hoopr.xcodeproj -scheme hoopr -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:hooprTests`
8. **Purpose over polish.** Every screen and element exists for a reason the user
   cares about: `context/PRODUCT_OVERVIEW.md` states what the product is for and
   `UI_SHELL.md` records why each screen is shaped as it is. Phase 0 writes that
   purpose down as a ledger; every later phase is judged against it. The revamp
   may re-compose, re-rank and restyle how a feature is presented. It may
   **not** remove a capability, add steps to a core task, bury something the user
   has to act on, or present a feature as working when `GAPS.md` says it doesn't
   (the standing example is the invite link that can be sent but not yet opened —
   `context/gaps/GAMES.md`). No animation, effect or celebration may delay a
   task, block input, or be the only carrier of information. Ornament that
   serves no purpose is cut.

### What exists today (build on the tokens and components — not on the layouts)

- Role-based palette in `Support/Theme.swift` (`hooprOrange` brand, `hooprRed`
  errors/notifications, surfaces, text roles, 8 squad-crest fills,
  `hooprShadow(opacity:)`).
- `.hooprGlass(tint:interactive:in:)` in `Support/Glass.swift` — wraps the one
  `#available(iOS 26)` call for the whole app, falling back to
  `.ultraThinMaterial`. **Glass is never called directly; extend this helper.**
- Shared components in `hoopr/Views/Components/`: `CardChrome`, `GlassChip`,
  `HooprSearchField`, `ProfileButton`, `ErrorBanner`, `StatsCard`,
  `CourtBadges`, plus `GameCard`, `FriendRow`, `SquadCrest`, `FormGuide`,
  `MatchmakingCard`.
- Four tabs (Home, Map, Runs, Seasons) in a native `TabView`; Profile replaces
  the tab view rather than stacking.
- Known visual weaknesses to fix: the selected-tab tint is `hooprOrange` on a
  near-white bar (~2.55:1, the tracked AA gap); light and dark surfaces are
  near-identical white; cards separate only by border + shadow; Home, Runs and
  Seasons each open on the same 28pt title + `ProfileButton` row and continue as
  a stack of `cardChrome()` cards, so no screen has a hero and three of the four
  tabs share one composition; no motion language at all; no loading/empty-state
  animation; spacing values are scattered as magic numbers.

### The work — implement in phases, in this order

#### Phase 0 — Audit (no behavior change)

Produce a written inventory: every view file, every color role it touches, every
magic spacing number, every duplicated chrome block. Identify which components
drift from `CardChrome`. Then record the **baseline every later phase is judged
against**, before any of them changes a pixel:

- **Feature purpose ledger.** One row per user-facing *feature*, not per screen —
  "join a run" lives on Runs and on the map's court card. Derive it from
  `context/PRODUCT_OVERVIEW.md`, `UI_SHELL.md`, `MAP_LAYER.md`, the
  `context/gaps/` files and by walking each flow in the simulator; cite the
  source for each row, and mark anything you had to infer as *assumption*.
  Columns: **purpose** (the user's job, in one sentence, in their words);
  **decision it supports** and the one to three facts needed to make it; **core
  task and its cost today** (taps from the tab root to done, counted in the
  simulator); **frequency and moment** (glance or focused; one-handed at the
  court or planning at home); **what the data really is** (a self-reported
  counter and a result two leaders agreed on are not the same claim —
  `UI_SHELL.md` § `HomeTab`); **known gaps** (`GAPS.md` — e.g. the invite link
  that can be sent but not opened, `context/gaps/GAMES.md`); **why it is shaped
  this way today** (the rationale `UI_SHELL.md` records — e.g. Friends is
  action-first, so search stays visible and requests never sit behind a
  disclosure).
- **Before-skeletons.** For every screen, its top-level view tree as an indented
  outline: container primitive, section order, hero element, where the primary
  action sits, and how many bordered/filled containers are drawn in the first
  viewport.
- **Before-screenshots.** Light and dark, default and `.accessibility3`, via
  `xcrun simctl io booted screenshot`, kept outside the repo.

Output: a short markdown audit + a component map + the ledger + the skeletons,
in `context/plans/UI_REVAMP_AUDIT.md`. This drives everything below.

#### Phase 1 — Design tokens: color system + spacing (foundation)

- Extend `Theme.swift` with **elevation roles** (`hooprElevatedSurface`,
  `hooprHoverFill`, `hooprSeparatorStrong`) so light and dark stops diverge
  intentionally instead of being identical white.
- Introduce a **`hooprBrandAccent`** role — a deeper, readable orange that
  clears 4.5:1 as a *foreground* on both `hooprBackground` and `hooprSurface`.
  Migrate the tab-bar tint, selected states, and any small orange text to it,
  fixing the tracked AA gap; then flip
  `ThemeContrastTests.testTabBarSelectionIsATrackedGap` to assert the pairing
  passes and remove the gap note from `GAPS.md`.
- Add a **semantic heat ramp** role (reusing/extending `CourtHeat`'s rule) so
  "how busy is this court" colors one definition everywhere.
- Create `Support/Spacing.swift` with named spacing tokens (page margin, card
  padding, inter-card, chip padding) and migrate the worst magic numbers in
  `Views/` to it.
- **Acceptance:** `ThemeContrastTests` green including new pairings; no visual
  regressions at default text size in either appearance; audit doc updated.

#### Phase 2 — Visual redesign: composition, hierarchy, identity

Every other phase upgrades an *ingredient* — colour, spacing, motion, glass,
libraries, components. None changes what a screen **is**, so run against today's
layouts they yield the same app in better paint. This phase changes the layouts,
starting from what each feature is *for* (the Phase 0 ledger), not from what
looks current. **A re-skin does not satisfy it.** Phases 3–5 act on the
compositions produced here, never the reverse.

**What a re-skin is, so it can't be argued around.** A screen is re-skinned when
its top-level composition survives — same sections in the same order, same
container primitive, same (or no) hero, same primary-action placement — and the
diff is confined to modifiers: colours, radii, materials, padding, shadows,
fonts, animation. Home is the pattern to break:

```
HomeTab.body                       hoopr/Views/Tabs/HomeTab.swift
ScrollView
└── VStack(spacing: 24)
    ├── header          28pt greeting · Spacer · ProfileButton    ← largest type on screen
    ├── Your Stats      12pt caps label → StatsCard               only once hasStats
    ├── Next run        12pt caps label → 17pt court name         ← the actual answer
    ├── Hot right now   12pt caps label → three rows in one card
    └── Friend requests banner                                    only when some are incoming
    every block above is drawn in cardChrome()
```

Home exists to answer "am I signed up for something tonight?" (`UI_SHELL.md` §
`HomeTab`), yet its loudest element is a greeting that carries no information
while the answer is a 17pt line in a box — below the stats card, for anyone who
has stats. Runs and Seasons open on the identical 28pt title + `ProfileButton`
row and run on as the same stack of `cardChrome()` cards. That sameness is what
makes the app read as a POC shell.

**The bar.** Within two seconds, a stranger shown one screenshot can say what the
screen is for and what to tap — and it holds up beside Apple's own iOS 26 apps
(borrow the quality, not the layout: Apple Sports' scoreboard numerals, Apple
Weather's one dominant answer, Apple Maps' full-bleed content under floating
controls).

**2a. Write the design brief before any view code** —
`context/plans/UI_REDESIGN_BRIEF.md`, with the header the other files in
`context/plans/` use (Status / Drafted / Touches; see `APP_SHELL_AND_HOME.md`):

1. **Point of view** — one sentence on what hoopsRN should *feel* like and why it
   suits pickup basketball, then three principles a reviewer could catch a screen
   breaking. "Modern", "clean" and "engaging" are not principles.
2. **Identity motifs** — at most three basketball-native devices (scoreboard
   numerals, court-line geometry, a squad's crest colour as a surface…), each with
   where it appears and the job it does there. A motif that carries no
   information or affordance is decoration; cut it.
3. **Type roles** — named roles in `Support/Typography.swift` as presets over
   `.hooprFont` (constraint 2 holds), starting with a display/numeral tier for
   heroes. Sizes from 31pt up scale on the `.largeTitle` curve
   (`HooprFontMetrics.metricsStyle`), so each display role states its
   `maximumSize` or its reflow.
4. **Layout archetypes** — three to five named compositions (hero + inset list,
   full-bleed content + detent sheet, pinned-header timeline, paged carousel,
   single focused task…) and which screen uses which.
5. **A per-screen entry** for every screen in 2b, derived from its ledger rows:
   the question it answers (the ledger's *decision it supports*); its hero (the
   facts that decision needs); its primary action, placed where the core task is
   cheapest; what is *removed or demoted* (a redesign that removes nothing is a
   re-skin); before- and after-skeletons; the composed first-run, empty, loading
   and error states; and anything that gets *harder* under the new layout, with
   why that is acceptable — the default answer is that nothing does.

Tokens from Phase 1 are the floor, not the ceiling: a role the brief needs goes
in `Theme.swift` with a `ThemeContrastTests` assertion, in this phase.

**Checkpoint 1 — stop.** Show the user the brief and every ledger row marked
*assumption*; wait for a reply before writing any view code.

**2b. One vertical slice, then the rest.** Redesign **Home** end to end — code,
states, both appearances, `.accessibility3` — then **Checkpoint 2**: stop and
show Home's before/after pairs and 2e evidence. One screen done fully first is
what makes the rest derive from a real design rather than from the components.
Then, in this order:

- *Screens* (2e's structural quota applies): Runs (`LocalRunsTab`, `GameCard` —
  the most repeated element); the map's court card and sheet (`MapTab`,
  `CourtRow`, `CourtGameRow`; read `MAP_LAYER.md` first); Seasons (`SeasonsTab`,
  `MatchmakingCard`, `SquadDetailView`, `GameDayView`, `ResultView`; read
  `context/gaps/SEASONS.md` first — behaviours there are capped in ways the code
  doesn't show); `LoginView`; `ProfileView`, the Friends pane and
  `PlayerProfileSheet`.
- *Sheets* (2c and 2d apply, no quota — a form's layout is dictated by its
  fields): `CreateGameSheet`, `QueueSheet`, `CreateSquadSheet`, `InboxSheet`, the
  profile edit sheets.

**2c. Rules** — 2e checks each one.

- **Prominence follows utility.** The ledger's frequency and stakes set the
  weight: what users do most, or most need to notice, is largest and nearest;
  rare setup tasks (change password, edit home court) are quiet but always
  findable. An element that maps to no decision or task in the ledger is cut.
- **One question, one hero.** The first viewport (first screenful, iPhone 17,
  default text size) answers the screen's question without scrolling, and one
  element is visibly the largest and strongest in it.
- **Hierarchy from scale, weight, space and restraint — not boxes.**
  `cardChrome()` stays only where a container earns it: it groups one tappable
  unit or separates interactive content from the page. No card in a card, no
  card per section by default. Brand orange marks the primary action and live
  state; if everything is orange, nothing is.
- **Numbers are content.** Roster counts, spots left, time to tip-off, distance
  and records get the display tier, not 13pt caption text.
- **Layers.** Content is the base layer — edge to edge and scrolling under the
  bars where it is visual (map, crest, hero). What floats above it (bars,
  floating controls, sheets) is the glass layer. No glass on rows in a scrolling
  list; none on glass.
- **States are compositions.** Empty, first-run, loading and error are laid out,
  not a grey sentence — and "nothing here yet" stays distinct from "this failed
  to load" (`hasLoadedGames` / `hasLoadedSquads`).
- **Reflow, don't clip** (constraint 6). A hero's frame and its `maximumSize`
  live in one metrics type and are measured against each other at
  `.accessibility3`, as `ResultPillMetrics` is in `SeasonsAccessibilityTests`.

**2d. Automatic fails** — any one sends the screen back:

- A modifier-only diff (defined above).
- A feature drawn as working when a gap file says it doesn't (the invite link
  that can't yet be opened — `context/gaps/GAMES.md`), or a self-reported counter
  given the weight of a result two leaders confirmed (`UI_SHELL.md` § `HomeTab`).
- Decoration passed off as design: materials or `.hooprGlass` wrapped around
  existing card interiors; gradient, blur or glow whose only job is looks.
- Invented data: placeholder counts, fake avatars, lorem copy, or a figure the
  model can't produce (a live "N here now" — `context/plans/LIVE_HEADCOUNT.md`
  is a plan, not code).

**2e. Acceptance.** Evidence goes in the phase changelog, one row per screen:
hero (before → after), axes changed (n of 5), core-task taps (before → after),
first-viewport containers (before → after), blind-read match (yes/no). None of it
is taste:

- **Structural test.** Compare each screen's after-skeleton with its Phase 0
  before-skeleton on five axes: (1) hero, (2) container primitive, (3) section
  order and grouping, (4) primary-action placement, (5) what moved behind or out
  of disclosure. A screen must change **at least three, one of them the hero**,
  each described in a sentence and visible in the screenshots. At most one tab
  may be marked *keep* (the map, already full-bleed under a detent sheet, is the
  candidate), with written justification against 2c.
- **Utility test.** Walk each core task from the ledger in the simulator, before
  and after: taps from the tab root to done, and whether every capability
  reachable before still is. Step counts don't rise and nothing gets harder to
  reach; a drop is the goal. An exception needs a written reason and the user's
  OK.
- **Variety and boxes.** The four tabs use at least three of 2a's archetypes.
  Containers *drawn* in each first viewport (bordered, filled or shadowed
  rectangles — not call sites) are counted before and after; an increase needs a
  written reason.
- **Squint and blind read.** Downscale each after-screenshot
  (`sips -Z 160 in.png --out out.png`) and name what dominates it. Then a
  fresh-context reviewer (a subagent or new session) shown *only* the brief and
  the before/after pairs — not the diff — names each screen's hero, primary
  action and structural change. Any answer that differs from your table sends
  that screen back.
- **Screenshots and commands.** `xcrun simctl io booted screenshot <path>` (not
  `hooprUITests`, which doesn't launch — `CLAUDE.md`), kept outside the repo;
  full unit suite green; a `ThemeContrastTests` assertion for every new pairing;
  view-model tests for any new derived property, in the shape of
  `HomeViewModelTests` / `LocalRunsViewModelTests`;
  `python3 tools/check_context_drift.py` for docs touched.

**Failure paths**

- A hero needs data the app doesn't have → don't fake or approximate it. Pick a
  hero from data that exists; record the gap in the matching `context/gaps/`
  file.
- A ledger row is an assumption the docs don't settle → design to it, put it on
  Checkpoint 1, never decide it silently.
- An iOS 26-only API (scroll-edge effects, glass) → behind
  `#available(iOS 26, *)` with an iOS 18 fallback that is still a *designed*
  layout; glass only through `Glass.swift`. Run the fallback on an iOS 18 runtime
  if `xcrun simctl list runtimes` shows one; if not, say so in the changelog —
  `context/gaps/CONFIGURATION.md` records that nothing has run below iOS 26.
- A screen can't be reached without a signed-in session → ask the user to sign in
  on the booted simulator once. Never create an account or type credentials
  yourself.
- A layout can't reflow at `.accessibility3` → simplify it (fewer columns, drop
  the ornament); never `minimumScaleFactor`, never a cap below legibility.
- A view model needs to change → presentation-only derived properties, with
  tests; no new reads, writes or service dependencies.
- A screen fails 2e twice → stop and report; the brief, not the code, is wrong
  for it.

**Wait vs stop**

- Wait at Checkpoints 1 and 2, and whenever the brief proposes changing
  navigation topology, removing a feature, or overturning a rationale
  `UI_SHELL.md` records (say why the reason no longer holds).
- Stop and report if a redesign needs a service, model or `firestore.rules`
  change, or would break a hard constraint.

**Out of scope:** services, models, `firestore.rules`; navigation topology (four
tabs in a native `TabView`, `ProfileView` replacing `MainTabView`,
`RootViewModel.destination`); `sheet(item:)` presentation (never `isPresented`);
`UI_SHELL.md`'s **Invariants** list still binds every screen touched (one
`ProfileButton` per tab, one `hooprRed` notification indicator per surface, one
write in flight); motion, new glass treatments and packages — Phases 3–5 add
those on top, but the static layout must already look finished without them.

- **Acceptance:** all of 2e for every screen in 2b; both checkpoints answered;
  the blind read matches your table; full unit suite (constraint 7) green.

#### Phase 3 — Motion language (built-in SwiftUI only — zero new dependencies)

Establish one reusable motion vocabulary and apply it consistently:

- **Choreographed springs:** a single `Animation.hooprSpring` (or equivalent
  token) used for interactive transitions; define enter/exit durations as tokens
  too. Replace instant `.animation(nil)`-style swaps on `MatchmakingCard`'s
  four states with matched content transitions.
- **`matchedGeometryEffect`** for card → detail continuity (e.g., squad crest
  from list into detail, game card into its sheet).
- **SF Symbol effects** (`.symbolEffect(.bounce.up)`, `.pulse`,
  `.variableColor`) on state changes: checkmark after copying the invite link,
  inbox badge, capacity-bar updates.
- **Sensory feedback:** `.sensoryFeedback(.impact, trigger:)` on join/leave
  confirmations and match-found — gated so it never fires during programmatic
  state rebuilds.
- **Scroll effects:** `scrollTransition` / `visualEffect` for card fade-and-lift
  as lists scroll; `scrollEdgeEffect` / `scrollTargetBehavior` on long lists
  (Runs, Friends).
- **Navigation transitions:** iOS 26 `NavigationTransition` (zoom) for
  pushes into `SquadDetailView` / `GameDayView` where the source is a card.
- Empty-state and button press feedback: scale-on-press (`buttonStyle` token),
  `ContentTransition.numericText` for live counts (waitlist numbers, friend
  count).
- **Acceptance:** every animation interruptible and reversible; nothing
  animates on first appearance (only on change); 120Hz-appropriate durations;
  Reduce Motion respected via `@Environment(\.accessibilityReduceMotion)`.

#### Phase 4 — Liquid Glass and materials (iOS 26 native)

- Extend `.hooprGlass` usage deliberately: floating map controls already use it;
  bring the profile top bar, sheet grabber region, and tab-bar-adjacent chrome
  up to the same standard. Phase 2c's layer rule decides what may be glass —
  chrome and controls, not list rows.
- Use **`.glassEffectID`** for source/destination glass continuity (e.g., a
  court card on Home → its map annotation).
- Add a `MeshGradient` hero treatment for the Login screen and the squad hero
  area, driven by the squad crest color so each squad's home screen is
  identifiably its own — built into the Phase 2 hero composition, not laid
  behind the old layout.
- **Acceptance:** `Glass.swift` remains the only place glass APIs are called
  (one `#available(iOS 26)` wrapper); dark and light both verified; no control
  becomes untappable through chrome (preserve the `contentShape` rule).

#### Phase 5 — Rich content libraries (SPM — add one at a time, justify each)

Prefer built-ins from Phases 3–4; add packages only where they do something
built-ins can't. Suggested, in priority order:

1. **`lottie-spm`** (Airbnb) — Lottie animations for: app launch, loading
   skeleton-to-content reveal, empty states ("no runs tonight", "no squad
   yet"), and match-found celebration. Bundle 2–3 lightweight JSON animations
   in the asset catalog; keep total added size < 1 MB.
2. **`Pow`** (Moving Parts) — conditional transitions and effects for banners
   and cards (`ErrorBanner` entrance, inbox arrivals, hot-court rows entering).
   Use `Glare`/`Shine` for the "hot right now" list to make it feel live.
3. **`ConfettiSwiftUI`** — cannon on win confirmation in `ResultView` and on
   streak milestones on Home; must be skippable and must not fire on re-render.
4. **`swiftui-introspect`** — escape hatch ONLY where UIKit access is truly
   required (e.g., tab bar glass edge cases); document each use.

Rules: each package is a separate commit with the justification recorded in
`context/BUILD_AND_CONFIG.md`; every animation view is wrapped so it degrades
gracefully if the package is later removed; no package touches `Services/` or
view models.

#### Phase 6 — Organization and component consolidation

- Finish the Phase 0 audit against the Phase 2 layouts: fold drifted chrome into
  `CardChrome` (only where Phase 2c still wants a card — never re-wrap content in
  chrome to reach a tidy count); one avatar component (`PlayerAvatar` variants
  centralized); one badge component unifying HOSTING/WAITLIST/FULL, inbox count,
  and friend-request pills.
- Build a **hidden Component Gallery screen** (behind a debug flag, e.g.
  triple-tap the version row on Profile) rendering every token, color role,
  type style, button state, card variant, animation, and glass treatment in
  isolation — the single place to judge the design system.
- Update `context/UI_SHELL.md` (visual conventions + invariants) and
  `context/BUILD_AND_CONFIG.md` (dependencies) so docs match code; run
  `python3 tools/check_context_drift.py`.

### Verification — every phase ends with

1. Full unit suite green (command above).
2. New contrast assertions in `ThemeContrastTests` for every new pairing.
3. Manual pass on iPhone 17 simulator: both appearances, Dynamic Type at
   default and `.accessibility3`, Reduce Motion on, VoiceOver sweep of the
   changed screens.
4. No literal colors or `.font(.system(size:))` outside the documented
   exceptions (verify with a repo grep).
5. A short changelog entry per phase: what changed, what was deliberately left
   alone, and why (Phase 2 adds its 2e evidence row for every screen).
6. From Phase 3 on, no screen regresses against its Phase 2 evidence: a later
   phase may not add back chrome layers, cards or glass wrappers Phase 2
   removed, nor add a step to a ledger task.

### Definition of done

The app looks designed, not themed: every primary screen has one clear hero and a
composition that visibly is not today's (the Phase 2 evidence table proves it),
built from what each feature is for — no core task costs more steps than it did,
and nothing is drawn as working that the gap files say isn't. It feels alive:
motion is purposeful and consistent, the brand reads clearly in both appearances
at every text size, busy courts visibly glow, match wins celebrate, and every
screen is built from the same consolidated set of components and tokens — with
the test suite and context docs proving it.
