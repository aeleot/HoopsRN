# hoopsRN — UI Shell

**Scope:** `hoopr/Views/RootView.swift`, `hoopr/Views/MainTabView.swift`,
`hoopr/Views/LoginView.swift`, `hoopr/Views/Profile/`, `hoopr/Views/Games/`,
`hoopr/Views/Tabs/LocalRunsTab.swift`, `hoopr/Views/Tabs/HomeTab.swift`,
`hoopr/ViewModels/HomeViewModel.swift`, `hoopr/Views/Friends/`,
`hoopr/Views/Components/ErrorBanner.swift`,
`hoopr/Views/Components/ProfileButton.swift`,
`hoopr/Views/Components/HooprSearchField.swift`,
`hoopr/Views/Components/CardChrome.swift`,
`hoopr/Views/Components/GlassChip.swift`,
`hoopr/Views/Components/StatsCard.swift`, `hoopr/Views/Seasons/`,
`hoopr/Support/Theme.swift`,
`hoopr/Support/Typography.swift`, `hoopr/Support/AppearancePreference.swift`,
`hoopr/Support/Glass.swift`, `hoopr/Support/Spacing.swift`
**Verified:** 2026-09-20 @ 349d309

Navigation structure and the visual conventions every screen follows. Read this
before adding a screen, changing how one is presented, or picking a colour or a
font size.

---

## Navigation

The shell is a native `TabView` with a bottom tab bar. `RootView` above it is
still conditional rendering; `ProfileView` below it still replaces rather than
stacks.

```
RootView                    switches on RootViewModel.destination
├── .launching → LaunchScreen
├── .login     → LoginView
└── .main      → MainTabView
                 ├── TabView (bottom bar) — Home · Map · Runs · Seasons
                 └── ProfileView   (replaces the above entirely)
                     ├── top bar: back · handle-on-scroll · inbox
                     ├── Profile pane  (identity + field rows)
                     └── Friends pane  (search + friends list)
```

`.launching` exists so the login screen never flashes at a user whose cached
session is about to restore — `RootViewModel` holds there until
`AuthService.hasLoadedInitialState` is true. The three cases crossfade with a
0.2s `.easeInOut` keyed on `destination`.

**`ProfileView` replaces `MainTabView` rather than rendering inside it** — it
owns its own header and back button, so presenting it as a sheet or pushing it
into a stack would give it two. `MainTabView` holds a `showProfile` flag and
swaps its entire body; `ProfileView` takes an `onBack` closure. That is also
what makes the profile the one screen with no tab bar and no profile button:
there is nothing behind it.

Edit flows *within* the profile are `.sheet(item:)` bound to
`ProfileViewModel.editingField`, so adding an editable field means adding an
`EditableField` case and a branch in `editSheet(for:)` — not a new screen.

Two edits sit **outside** that enum, each with its own `@State` + `.sheet(isPresented:)`:
appearance (device-local, never touches Firestore) and the password reset (a
Firebase Auth action, not a document write). Neither shares `editingField`'s
in-flight or failure handling, and the password reset carries its own
`isSendingPasswordReset` / `didSendPasswordReset` / `passwordResetError` for
that reason — routing its error through `errorMessage` would also print it in
the screen's bottom bar, which only hides itself while an `editingField` sheet
is up.

## `MainTabView`

A native `TabView` with four `Tab` items — **Home** (`house.fill`), **Map**
(`map.fill`), **Runs** (`calendar`), **Seasons** (`trophy.fill`) — selected
through a private `Screen` enum. Named `Screen` and not `Tab` because
`SwiftUI.Tab` is the builder it uses.

**Four is the practical ceiling, and the fourth label was decided by
measurement.** `TabBarLabelTests` renders all four at `.accessibility3` and
asserts "Seasons" is the widest and still fits its share of a 320pt bar — which
is what settled "Seasons" over the shorter "Squad". The measurement turned up
something worth keeping: `UITabBar` **clamps its own content size category**, so
at accessibility sizes the labels render at ~10pt and the system offers the
large-content-viewer HUD instead of growing them. That clamp is UIKit's, not
ours, so the test asserts the outcome rather than the clamp. A fifth tab, or a
longer label, fails there instead of on somebody's phone.

**This replaced a hand-rolled floating glass header on 2026-08-26**, and the
reasons are worth keeping because they are the argument against rebuilding one:

- The old header was pinned to `geo.size.height * 0.14`. Its pills were ~40pt
  tall against Apple's 44pt floor, and both the greeting and the pill labels
  carried `minimumScaleFactor` — type shrinking to fit a fixed bar, which is
  exactly what `BACKLOG.md` §C4 says to stop doing.
- It needed `.contentShape(Rectangle())` on a clear fill purely so taps stopped
  falling through to MapKit. A system tab bar is hit-tested by the system.
- It needed a `\.floatingHeaderHeight` environment key to tell `MapTab` how far
  to inset its chrome. That key is gone.

**Tab state is the system's now.** The old shell kept `MapTab` permanently
mounted behind `.opacity` + `.allowsHitTesting` to preserve map region and
sheet state across switches. `TabView` retains tab content after first
appearance, so that hack is gone and the behaviour is unchanged.

**Selected tabs take `hooprBrandAccent` via `.tint`; unselected stay in the
system grey.** `.tint` colours the selected item's glyph *and* its ~10pt label,
so the brand is drawn as a **foreground** on a near-white glass ground — which
the filled `hooprOrange` fails as (3.17:1 on white). That was the AA gap
`GAPS.md` used to track, with the tab bar as its most prominent instance: in
light mode the selected label read *lighter* than the unselected ones, inverting
the hierarchy it exists to signal. **It closed on 2026-09-21** when the tint
moved to `hooprBrandAccent` (`#B8400F`, 5.56:1 on white); dark is unchanged,
because there the accent *is* `hooprOrange`.

**iOS 26 adjusts a tint before it paints it**, so the number to trust is the
rendered one, not the nominal one. Sampled from the live app, `hooprOrange`
rendered as `#E55E27` on the `#EDEDED` selection pill in light mode — **3.01:1**,
the real figure; the "roughly 2.55:1" this paragraph used to quote was the
nominal value for an orange since retuned — and as `#FF8F6A` on `#3A3A3A` in
dark (5.09:1). With the accent, the **live app measures 5.32:1 in light**
(`#AF3706` on `#EDEDED`) and 4.98:1 in dark, sampled from screenshots.
`ThemeContrastTests.testTabBarSelectionClearsAA` asserts the nominal value on the
grounds this code controls; the rendered figure has to be re-measured from a
screenshot whenever the tint changes.

**The bar itself is opaque, not the system's default floating glass** — set
in `MainTabView.configureTabBarAppearance()` via `UITabBarAppearance`
(`configureWithOpaqueBackground()`, `backgroundColor = hooprFill`,
`selectionIndicatorTintColor = hooprHoverFill`), applied to
`UITabBar.appearance()` in `init()` since SwiftUI's `TabView` still bridges to
`UITabBarController` on iPhone. `.toolbarBackground(Color.hooprFill, for:
.tabBar)` / `.toolbarBackgroundVisibility(.visible, for: .tabBar)` sit
alongside it as the SwiftUI-native path to the same result. `hooprFill` (the
existing "filled but unemphasised region" role) is what gives the bar its own
presence against whatever's behind it — translucent chrome was reading as no
bar at all — and `hooprHoverFill` behind the selected item is the same
"selected without being loud" role a pressed row already uses. Added
2026-09-22.

**The profile button appears on all four tabs and nowhere else.** It is a
shared `ProfileButton` component (`Views/Components/`) with one appearance — the
map's glass variant is gone — and one position, `ProfileButton.Slot`: the 44pt
frame 12pt below the safe area with its trailing edge on the page margin, so
switching tabs never moves it (2026-09-22; before, Seasons and the map each
placed it a few points off Home). It owns the notification-dot rule — `hooprRed`, not
brand orange, matching the inbox badge it leads to, and reading `FriendService`
directly rather than a view model so the dot stays live while the profile is
closed. An inbox you can only discover by already being inside it isn't a
notification.

Each tab names itself in its band's `label` row, beside `ProfileButton` in its
shared `Slot` — "Tonight", "Runs", "This season". (Home's `"Let's hoop
<name>."` greeting, which shrank to fit with `minimumScaleFactor`, was removed
in the UI revamp, assumption A2; **no text in the app shrinks to fit any more**
— the last three `minimumScaleFactor` calls went on 2026-09-23.)

`courtToShowOnMap` is a `@State Court?` handed to `MapTab` as a binding. Home's
hot-court rows write to it and switch tabs; `MapTab` consumes it and writes back
`nil`, so the same court can be sent twice.
## `HomeTab`

The launch tab, added 2026-08-26. The app used to open on the map, which answers
"where can I hoop?" — a question you only have once you've decided to go out. It
can't answer "am I signed up for something tonight?", which is the more common
reason to open the app, so that is what this screen leads with.

> **Stale as of 2026-09-22 — the composition below is the pre-redesign one.**
> UI revamp Phase 2b rebuilt this screen: the greeting is gone, the run's
> tip-off time is the hero as a display numeral in a full-bleed band, the five
> `cardChrome()` call sites are zero, and the stats card is one caption line.
> The *reasons* recorded here still hold — why Home exists, why the next-run
> card is read-only, why the hot list reads nothing new, why the stats are
> gated — and only the shapes changed.
>
> **Since then (2026-09-23, at the user's request):** the band opens on the
> app's mark — `HooprWordmark`, the app icon's basketball beside "hoopsRN" —
> opposite the profile button, in the row every tab already gives that button;
> the day label moved down onto the time (and is dropped over "No run
> tonight", which says it). The band's ground is the brand orange at the
> band's own luminance (`HeroWash`, `hooprBrandWash`), like Login's and the
> squad bands', so no ratio on it moved. The HOSTING pill on it is an 8% wash,
> not a card's 12%: at 12% it measured 4.44:1 on the band in dark mode.
> **The ball on its way off the page** (the user's design, same day):
> `HomeBandBall` draws the app icon's basketball two thirds of the band's
> width across, centred on its trailing edge so only the left half shows in
> the band's right third, tilted, with the profile button on top. It is
> `hooprBrandWatermark` — the orange at a pressed row's luminance — so what
> runs across it (the detail line, a long court name, the profile button, the
> arrow) reads as it does on a pressed row, asserted on the colour
> itself. **The whole band opens Runs** (2026-09-24, the user's call), wherever
> it is pressed except the profile button and the empty state's "Find a court",
> which keep their own destinations; the arrow at the last row's end is the
> cue, and replaced a "Your runs ›" line whose words were the only target. The HOSTING pill can't reach it (first on its line, text capped) and
> would fail over it; the test says so. This entry is restamped when the rest
> of Phase 2b lands; until then see `plans/UI_REVAMP_CHANGELOG.md` § Phase 2b
> and `plans/UI_REDESIGN_BRIEF.md` §5.1.

Cards, in order — commitment, then opportunity:

- **Next run** — the soonest run you're on. Read-only on purpose: `GameCard`
  carries join/leave/cancel and the invite link, which are decisions that belong
  on Runs, so Home draws its own compact card whose only action is to navigate
  there. It reuses `LocalRunsViewModel.Listing` for the court join and distance
  formatting, and mirrors `GameCard`'s badge priority (HOSTING → WAITLIST →
  FULL) so a run reads the same on both screens. With nothing scheduled it
  becomes a call to action pointing at the map.
- **Hot right now** — the three courts with the most games today, dotted with
  `CourtHeat.color(forGameCount:)` so a court's colour means the same thing here
  as on the map. Tapping one opens the map with that court selected.
- **Friend requests** — rendered only when there are incoming ones.

**It reads nothing new.** Every value comes off listeners the app already keeps
open: `GameService`'s two arrays, `CourtService.courts`, the profile snapshot,
and `FriendService`. The hot list calls
`FindAMatchViewModel.gameCountsByCourt(queued:published:)` directly — it is
`nonisolated static` and pure, so Home shares the map's counting rule instead of
restating it. No extra Firestore read, no rules change.

**The stats card shipped, and this entry said it hadn't for longer than it
should have.** `StatsCard` (`Views/Components/StatsCard.swift`) leads the tab
with three text columns — Runs, Streak, Last Run — fed from the profile's
`completedGameCount`, `participationStreak` and `lastCompletedAt`. It is
**gated on `HomeViewModel.hasStats`** (`completedGameCount > 0`), so a
brand-new account sees no card at all rather than a row of zeros.

**The pipeline behind it is now complete end to end** (2026-09-18).
`GameService`'s third listener publishes `completedGames` (`status ==
completed`, ordered by `completedAt`), `HomeViewModel` recalculates the three
numbers off that snapshot and writes them back through
`UserProfileService.refreshStats` — the one write on this screen, placed here
because both services are already held for the subscriptions above rather than
by giving either a dependency on the other. The step that was missing, a write
of `status: completed`, is the host's "Mark complete" control on `GameCard`
(see `LocalRunsTab` below). So `hasStats` now turns true on a real account the
first time a host marks one of their runs complete, rather than only on data
seeded by hand.

**Nothing refreshes the card by hand, and nothing should.** The completion
write lands, the `completedGames` listener echoes it, and `HomeViewModel`
recalculates off that snapshot — the card appearing is a consequence of the
listener, not of the tap. A second write path to force it would double-count.

**They remain self-reported profile counters.** They are stored on
`users/{uid}`, which the owner writes, so they carry exactly the forgeability
`database/DATABASE_SCHEMA.md` records for `completedGameCount` — unlike a
squad's record, which is derived from documents two leaders had to agree on.
Read them as a personal activity summary, not as a competitive claim.

`HomeViewModel.rankHotCourts` is `nonisolated static` and pure, pinned by
`HomeViewModelTests`. Its tie-break on `displayName` is load-bearing: a
`[String: Int]` has no stable iteration order, so without it the list reshuffles
between rebuilds while showing identical numbers.

## `LocalRunsTab`

> **Stale as of 2026-09-22 — the composition below is the pre-redesign one.**
> UI revamp Phase 2b rebuilt this screen: the two collapsible sections are one
> list ordered by tip-off, the runs you're on carry a rail instead of a
> section, a band states how many runs are on, and `GameCard` leads with the
> time and states spots left instead of drawing a capacity bar. **The
> "collapsible section header" clause of the Invariants list no longer holds
> for this tab** — the shared card and the one-write-in-flight clauses do.
> Confirmed with the user before it was written. The *reasons* recorded below
> still hold; the shapes changed. Restamped when the rest of Phase 2b lands;
> until then see `plans/UI_REVAMP_CHANGELOG.md` § Phase 2b and
> `plans/UI_REDESIGN_BRIEF.md` §5.2.
>
> **Reworked again 2026-09-23, at the user's request** ("very plain, very
> grey", and the header "does not make sense"). The band's copy — "3 games on
> the schedule" under a "Tonight"/"Coming up" eyebrow, over "You're suited up
> for all 3" — is gone. The band is **the week** (`RunsWeekStrip`): today and
> the six days after it, a dot per run, filled in the accent where you're on
> it and a ring where you could join; today in an orange disc; a day with runs
> scrolls the board to its heading. The band reads top to bottom (the user's
> layout, compact): "This week" over the week's count ("3 runs", `title`) in
> the profile button's row, then — only when there is one — a waitlist place
> or runs after the week as facts with glyphs (`RunsBandStat`), and the week
> strip last, closing the band. There is no "you're in" line: the strip's
> filled dots say it. The band's ground is the brand fade with the court
> half off its trailing edge (`RunsBandCourt`, in `hooprBrandWatermark`) —
> Home's ball, as Runs' emblem. **The board is grouped under a heading per
> day** ("Today", "Tomorrow", the weekday, then the date), so `GameCard` no
> longer repeats the day; its court name leads with the court glyph.

Two collapsible sections — **Queued Games** (runs you're on) and **Public
Games** (discoverable runs inside your `preferredRadius`) — over a single
`ScrollView`. One scroll gesture stays in charge, and the two are read together
anyway: "am I busy, and what else is on?"

Section expansion is **`@AppStorage`, not `@State`**. It was written when a tab
switch unmounted this tab entirely and view state would reopen both sections on
every visit. Under the native `TabView` the tab stays mounted, so `@State` would
now survive a switch — but `@AppStorage` still earns its keep by carrying the
choice across launches, which `@State` never did.

Cards are `GameCard`, shared by both sections so a run reads identically
wherever it appears — only the primary action differs (Join / Join waitlist /
Leave / Cancel run, resolved by `LocalRunsViewModel.action(for:)`). The action
is resolved **once per row** and handed to both the button and its confirmation
dialog, so a dialog saying "Cancel run" can't perform a join.

Only one roster write is in flight at a time: the acting card shows a spinner
and every other card's button goes inert, so a double tap can't race the
transaction already running.

**A card shows "N friends here" when any of your friends are on its roster or
waitlist** — the one piece of social proof on the card, and the point of
`plans/FRIENDS.md` Phase 4: you can see a run is worth joining without changing
how you join it. It gets **its own line rather than a fourth `detail` chip**
(that row is a plain `HStack` with no `ViewThatFits` ladder, so a fourth entry
overflows at accessibility sizes) and **rather than the header badge** (that
slot is at most one badge about *your own* relationship to the run — HOSTING →
WAITLIST → FULL — and who else is here is a different question, so folding them
into one chain would mean a run you host could never show it). It's drawn in
`hooprPrimaryText` so it outweighs the grey details above it. (It avoided
orange when `hooprOrange` failed AA as a foreground; that constraint went with
`hooprBrandAccent`, so it stands as a hierarchy choice.)

The intersection is a `nonisolated static` on `LocalRunsViewModel`, resolved
once per rebuild alongside the distance rather than per row during scroll, and
it **widens nothing**: it reads the roster of a run already on screen. A
friend's *private* run stays invisible — that needs the authorization design
`plans/FRIENDS.md` §4 defers.

**A host gets a second control on their own run once it has started: "Mark
complete".** It is deliberately *not* a `LocalRunsViewModel.Action` case —
`action(for:)` returns exactly one thing to offer and a host already gets
"Cancel run", so after tip-off the card has to show both, which one-of-N can't
express. It's gated on `LocalRunsViewModel.canComplete(_:currentUserId:now:)`, a
`nonisolated static` pure predicate: host, `now >= scheduledTime`, and not
already completed. The roster isn't consulted — there's no attendance concept,
so a host who turned up alone may still record that the run happened.

It's drawn as a **secondary** control below the primary button — bordered over
`hooprFill` like `InviteLinkCard`, the card's other host-only affordance — not a
second primary and not destructive. Completing takes nothing away, and drawing
it in `hooprRed` beside "Cancel run" would make two very different outcomes look
alike. It shares `pendingGameId` with the roster writes, so while either is in
flight neither is tappable.

**The card disappears once the write lands, and that's correct.**
`Game.isVisible(at:)` excludes `completed`, so `rebuild()` drops the run from
both lists the moment the listener echoes it — it has moved to the Home stats
card. That's why the confirmation dialog says so ("It moves to your stats and
leaves this list"): without it, the disappearance reads as a deletion. The
dialog also has to name the two things that can't be taken back — the write is
one-way, since the rule refuses a document already `completed`, and it freezes
the roster, since the roster clause only admits a run whose status is
`open`/`full`.

**Runs tab only.** The map's court card renders its rows from the same `Action`,
and since completion isn't a case of it, that surface gets nothing — intended,
and what keeps the blast radius off `FindAMatchViewModel`.

A card for a run you host that isn't public also carries an `InviteLinkCard` —
the run's `hoopsrn://game/{id}` link, shown in full with a tap that copies it.
Host-only: an invite-only run is the host's to hand out. **The link doesn't
resolve yet** — nothing registers the scheme and nothing handles an incoming
URL, so it's a string to send while the receiving half is built (`GAPS.md` §4).

## `SeasonsTab`

> **Stale as of 2026-09-22 — the composition below is the pre-redesign one.**
> UI revamp Phase 2b rebuilt this tab: the 28pt "Seasons" title is gone, the
> squad's crest, name and **record** sit in a full-bleed band like Home's and
> Runs', the record set as the screen's numeral with its form beside it, and the
> roster and other squads are rows rather than cards. `MatchmakingCard` keeps
> its card only in its matched state. The band is neutral rather than the
> squad's colour, for a measured contrast reason recorded in `SeasonsTab`. The
> reasons below — squad invites living in the inbox, other squads getting rows,
> the four matchmaking states being states rather than destinations — still
> hold. Restamped when Phase 2b lands; see `plans/UI_REVAMP_CHANGELOG.md`.

The fourth tab: squads, matchmaking, and the record that comes out of them. One
`NavigationStack` over a scroll view, with two sheets and three pushes.

**Screens 5, 6 and 8's "waiting" are *states*, not destinations.** Squad home
has one card that matters right now — *find a match*, *searching*, *match
found*, or *next match* — and `MatchmakingCard` swaps its contents in place
rather than pushing. Making them separate screens would mean navigating between
views that differ by one sentence.

**The state is decided by `MatchmakingViewModel.phase`, a `nonisolated static`
pure function**, and it is worth knowing why it is not simply "is there a
ticket". Nothing deletes a ticket once it has been spent on a match; it ages out
on `expiresAt`, up to a day later. Reading any non-nil ticket as *searching*
meant that the moment a match stopped being live — played and confirmed, called
off, or aged past its window — the card fell back to a search nobody had
started, with a timer counting up from when the squad first queued and a "Cancel
search" button that cancelled nothing. `MatchTicket.isSearching` is the only
question the searching state may ask.

*Match found* is the fourth state and covers a real gap rather than a cosmetic
one: the match and both tickets are written in one transaction but reach the
client on two listeners, so for a few hundred milliseconds the ticket is spent
and the match hasn't arrived. Without it the card blinks through *find a match*
— the wrong answer, and an offer to queue that would be refused.

**It is also bounded, by `MatchmakingViewModel.settlingGrace` (20s).** Nothing
re-evaluates `phase` once the ticket itself stops changing, so if the match
never arrives — `matchedGameId` pointing at a document this client can't see,
which rules make narrow but a hand-edited or otherwise corrupted ticket can
still produce — *match found* had no way out at all: a permanent spinner, with
no cancel control on it. Past the grace period `phase` falls back to *find a
match*, which is what lets a leader queue again instead of being stuck behind a
match that will never resolve.

**Queue up is gated on `canQueue`, not on being the leader.** One live match at
a time: a leader with a match scheduled is shown the match, and the queue
re-opens once it is over.

| Surface | File | Presentation |
|---|---|---|
| No squad — hero empty state | `SeasonsTab` | inline |
| Squad home — crest, record, form, the one live card, roster | `SeasonsTab` | inline |
| Create squad | `CreateSquadSheet` | `sheet(item:)` |
| Queue up — window chips and court multi-select | `QueueSheet` | `sheet(item:)` |
| Searching · match found · next match | `MatchmakingCard` | states of squad home |
| Game day — countdown, court, both rosters, arrival | `GameDayView` | push |
| Result — who won, and what the two reports say | `ResultView` | push |
| Squad detail — record, form, history, roster, controls | `SquadDetailView` | push |

Pushes carry the `SeasonGame` **value**, not an ID to look back up — it is
already `Hashable` and already in hand at every call site. The stack and its
`Route` enum belong to `SeasonsTab`, so `GameDayView` and `SquadDetailView` take
an `onOpenResult` closure rather than reaching for the path, the same way
`MatchmakingCard` takes `onOpenGameDay`.

**Squad detail hides the navigation bar and carries its own back button**
(`BandBackButton`, the user's call, 2026-09-23). With the bar showing, the band
started below it and the bar's strip of page background sat between the status
bar and the band — "cuts off abruptly towards the top". Hidden, the band starts
at the safe area exactly where the tab's does, and the back button sits in the
band's first row in `ProfileButton.Slot`'s frame, mirrored to the leading edge.
Verified on the device: the left-edge swipe still pops with the bar hidden, the
button pops, and mid-push the two bands' crest, name and record line up. The
screen keeps its `navigationTitle` for VoiceOver and adds an `.escape` action.
`GameDayView` and `ResultView` do the same since their redesign (2026-09-23), so
every push in the Seasons stack opens on a band that starts where the tab's does.

**Squad invites are no longer answered here.** They used to render inline on
squad home — a leader can invite from squad detail, but without somewhere to
*accept*, a roster could never gain a second member, which is the only thing
the self-join rule exists for — and moved to the profile's `InboxSheet`
alongside friend requests once that inbox existed, on the same "everything
waiting on you belongs in one place" reasoning. See the Friends section's
`InboxSheet` entry below.

**The `seasonGames` listener is pointed from this tab**, at every squad the user
is on rather than only the primary one — screen 9's history reads off the same
listener, so a secondary squad's detail view would otherwise show an empty
season. See `ARCHITECTURE.md`'s session-scoped listeners.

### Reporting a result

Screen 8 renders three states off `SeasonGame.reportOutcome`, and **a
disagreement is a designed outcome rather than a failure**: "Results don't
match" is a card explaining that nobody's record moves until the two leaders
agree, not an error banner. Whoever was wrong reports again — the same write
path, called a second time.

The two crest buttons are the only place a `SquadCrest` is not decorative, so
they carry explicit labels naming the squad and the action. Reachable from game
day once tip-off has passed, and from any history row — which matters because
game day stops rendering a match three hours after tip-off, and a result
reported the next morning would otherwise have nowhere to go.

## Friends — a pane of `ProfileView`

Held the third tab slot until the shell needed it back; it's the Friends pane of
the profile now. `Views/Tabs/FriendsTab.swift` is gone and its two halves live
in `Views/Friends/FriendsPane.swift` as **`FriendsSearchField`** and
**`FriendsPaneContent`**. `ProfileView` owns the scroll view, the page margin
and every piece of presentation state.

**The inbox is not here.** It was a second button beside the search field, and
it moved to the profile's top bar — see `ProfileTopBar` for why. What's left in
the pane header is one control doing one thing, which is why it's a field now
rather than a toolbar.

**Both halves are stateless** — they render what `FriendsViewModel` holds and
report intent through closures. That's load-bearing, not tidiness: the toolbar
pins as a section header while the list scrolls in the section body, so any
state held *between* them would be stranded. `isInboxPresented`,
`presentedPlayer`, `pendingRemoval` and the search `@FocusState` are all
`ProfileView`'s, and so are the sheets they raise.

**This is the one list screen that is *not* built from the `LocalRunsTab`
parts,** and the departure is deliberate. It was that shape once — two
collapsible sections (Requests, Friends) over one `ScrollView` — which fits
Local Runs because its two lists answer one question together ("am I busy, and
what else is on?"). A social screen isn't that. Finding someone is an *action*
and needs a permanently visible control, and requests waiting on you must not
be reachable only by expanding a dropdown. So:

```
ScrollView (ProfileView's)
├── pinned section header  [ 🔍 search field .......................... ]
└── section body
    ├── query empty → Friends list
    └── query typed → Results (idle / searching / results / empty / failed)
```

No `@AppStorage` here any more — there are no collapsible sections left to
remember, so the keys `friends.requestsExpanded` and `friends.friendsExpanded`
are gone. The `ErrorBanner` + `isRecovering` retry treatment is unchanged.

**Search** is one field for two lookups. `FriendsViewModel` debounces the text
by 300ms, then always runs a `userNameLower` prefix range and — only when the
text is uid-shaped (`looksLikeUserId`: 20–128 ASCII alphanumerics) —
*additionally* a direct document read. Running both rather than routing between
them means a wrong guess never costs the user a result; a display name is never
uid-shaped, so ordinary typing never pays for the extra read. An exact ID match
ranks first, duplicates collapse, and **the signed-in user is dropped** from
results. Clearing the field restores the friends list in the same frame —
`reactToQueryEdit` handles that undebounced, so an empty field never sits on
stale results.

**Rows are `FriendRow`** — avatar, name, `@handle`, one trailing control — **on
the page, not in a card** (UI revamp Phase 2b, 2026-09-23): the lists put them
in `DividedRows`, a hairline between each starting under the name
(`FriendRow.textInset`). It replaced the tall `FriendCard`, which put a
full-width button under every name and made twelve friends read as twelve
forms; the card chrome it kept until the revamp was an inline, unnamed copy of
the card recipe. The trailing control is passed in
as a `@ViewBuilder`, so one row serves the friends list, the search results and
both inbox sections without a mode flag.

The subtitle is **always the handle**, never the home court. A subtitle that's a
court on one row and a handle on the next means two different things in one
column — and the handle is what distinguishes two friends who share a display
name, since `userName` isn't unique. The home court has a labelled row on the
profile.

**`InboxSheet`** holds what's waiting: **Requests** (incoming friend requests,
what the badge counts), **Squad invites** (incoming, Join/Decline inline via
`SquadInviteRow`), and **Sent** (outgoing friend requests, cancel-only — a
squad's own sent invites are revocable from squad detail instead, not here).
Squad invites used to render inline on Squad home, where a leader could invite
from squad detail but there was nowhere to *answer* one; they moved here once
there was a dedicated inbox for "something's waiting on you," which the
Seasons tab no longer is. **The squad invites section is omitted rather than
shown empty**, unlike the two friend sections — a squad invite is rare enough
that a standing "nothing here" placeholder would outweigh the one time it has
something to say.

**Join is absent, not dimmed, when you're already on a squad.** A person is on
one squad at a time, so `SquadInviteRow` drops the Join button and puts the
reason where the roster line was ("You're on Rim Reapers. Leave it to join or
start another squad."; a leader is told to disband instead). Absent rather than
disabled because `hooprPress` adds nothing to a disabled state, and a greyed
capsule would leave the reason to be guessed — and because this sheet has no
error banner, so a refusal reported after the tap would land on the Seasons
tab behind it. Decline stays. The same rule is why the Seasons tab has no
"Create another squad" button. See `gaps/SEASONS.md` for what's app-only about it.

Two kinds of notification now, not one, and the design call still holds: a
second kind cost one more section rather than a shared `InboxItem`
abstraction, which is still invented structure for two cases rather than
shared structure. `ProfileButton`'s badge (wired in `MainTabView`) now reads
`squadService.incomingInvites` alongside `friendService.incomingRequests`, so
it's live whether or not the Seasons tab has been opened this session.

**`PlayerProfileSheet`** shows another player: name, home court, joined. That's
a *display* decision, not an access control — `users` is readable whole by any
signed-in account (see `database/DATABASE_SCHEMA.md`), so leaving
`favoriteCourtIds` and `preferredRadius` off the screen doesn't make them
private; it just declines to amplify them. Friend counts and mutual friends
aren't omitted but *impossible*: `friendships` is participants-only. It reuses
`ProfileRow` with `onTap: nil`, so these rows can't drift from your own
profile's. Its identity band is the page colour with an orange-ringed avatar —
it followed `ProfileView`'s orange gradient before that header was retired, and
it follows the replacement for the same reason: a profile should read as a
profile wherever it appears. The band is laid out sideways rather than stacked
because a sheet opens at a height it has to live within. Every relationship
action lives in its bottom action bar (a `safeAreaInset`). It holds a **uid**,
never a snapshot, and reads back through the view model on every render, so a
name landing or the other person accepting updates the open sheet.

Removing a friend is the one action behind a confirmation dialog: a declined
request can be re-sent by the other person, but an unfriend is only undone by
asking again. One write in flight at a time, keyed on the **person** rather than
the friendship — a search result has no friendship document yet.

Names are **not** stored on a friendship — `FriendsViewModel` resolves them
through `UserProfileService.profiles(for:)` and renders the row with a skeleton
until they arrive. A name that fails to resolve leaves the row fully actionable,
retries on the next snapshot, and is healed by `loadProfileIfNeeded(for:)` when
its profile sheet opens.

Waiting requests are announced in two places, both outside this pane: the
**profile button in `MainTabView`** carries a red dot, and the **inbox in
`ProfileTopBar`** carries a red count badge. The pane selector deliberately
carries neither — it had a dot while the inbox lived inside the pane it selects,
and keeping it would now point at a place the requests aren't.

## Starting a run

`CreateGameSheet` is presented from the court detail card in `MapTab`.
**Both entry points the feature calls for — a map pin and a nearby-list row —
already converge on that card**, so one "Start Run" button there covers both
without duplicating a control in the list.

The form collects four fields: when, public or invite-only, and roster size.
Everything else the `games` schema stores — host, status, both rosters, both
timestamps — is derived by `GameService` on the write path, so none of it
appears in the UI.

A **public** run dismisses the sheet on save; it arrives in Local Runs on the
listener that's already open. A **private** one doesn't — `createGame` returns
the new document ID, `CreateGameViewModel.inviteLink` is set from it, and the
sheet swaps the form for an invite step titled "Run Created". Cancel is dropped
there and Create becomes Done: the run already exists, so offering Cancel would
read as "discard it".

**The invite step leads with what works** (UI revamp Phase 2b, brief §5.11 — a
correctness fix): the link opens nothing and an invite-only run holds only its
host (`gaps/GAMES.md`), so the step says so under its title ("Invites don't work
yet, so send your players the court and time"), shows the court and time in a
panel, and offers **"Send the court and time"** through the system share sheet
(`CreateGameViewModel.shareText`: "Pickup run at East End Park, Durham —
Tonight at 7:30 PM"). The link sits last in that panel as a reference, in the
same `InviteLinkCard` the Runs card uses — with its "doesn't work yet" note
switched off **here only**, because the line under the title has just said it;
on the Runs card nothing else does. The Invite-only option on the form says the
same before the run exists ("Hidden. Just you until invites work."); it used to
promise "a link to share with the players you want in". `CreateGameCopyTests`
pins both.

**The form is an inset-grouped form** (rebuilt 2026-09-23, the user's call: the
Phase 2b version was "not very structured", with "more text and not a lot of
icons"). The court is the heading (`CourtTitle`, over its address with a pin),
on `hooprGroupedBackground`; under it, three `FormPanel`s — **when** (Day,
Tip-off), **how many** (Players), **who can join** (Public, Invite only). Every
row is the same shape, `FormRow`: an accent glyph in a 28pt column, a title,
and the value or control at the trailing edge, stacking under the title at the
largest text sizes. **Day** opens a strip of chips — Today, Thu 24, … — for
every day the rules allow (30 on), and picking one keeps the time
(`CreateGameViewModel.tipOff(on:keepingTimeOf:within:)`, which moves a time
already past to the next quarter hour the rules allow). **Tip-off** opens a
time wheel. One picker is open at a time and neither by default, so the three
taps with the defaults accepted are unchanged. **Players** is `− n +` at the
trailing edge with the format ("5-on-5") under the title, one adjustable element
to VoiceOver. **Public / Invite only** are two option rows with a radio mark and
one short line each. A same-day time before 5 PM reads "Today", from 5 PM
"Tonight" — `Game.dayText(for:)`, shared with Home and Runs.

`InviteLink` (in `Support/`) owns the `hoopsrn://game/{id}` format — one
definition, because the create flow holds a bare document ID and the card holds
a whole `Game`. `GameTests` pins the string so the scheme can't move on one
side alone.

## `ProfileView`

**Two panes, one screen.** A `Pane` enum — `.profile`, `.friends` — behind two
labels with a sliding accent underline (the map list's Now / Nearby / Saved
treatment; it was an orange pill on a grey track until the revamp). The pairing isn't arbitrary: both panes answer "who am I in
this app", one about your own settings and one about the people attached to
them, and it's what lets a friend request be visible from the same place you go
to change your home court. The screen holds **two view models** for that reason,
`ProfileViewModel` and `FriendsViewModel`, both `@StateObject` — the friends one
lives here rather than in the pane so search text and results survive a trip
through the Profile pane and back.

**One scroll view owns the whole page:**

```
ScrollView
└── LazyVStack(pinnedViews: .sectionHeaders)
    ├── ProfileIdentityBlock          ← scrolls away
    └── Section
        ├── header: pane selector (+ friends search on that pane)    ← pins
        └── body:   field rows, or the friends list
      ⇧ safeAreaInset(.top): ProfileTopBar
```

The top bar is a **`safeAreaInset`, not a `ZStack` overlay** — that's what makes
the scroll view treat it as safe area, so the pinned section header stops
underneath it instead of sliding up under the status bar.

**The inbox lives in that bar**, trailing, opposite the back chevron. It was a
button beside the Friends pane's search field, which meant the one place social
notifications collect was only visible on the pane you had to already be on to
see it. Screen chrome is the honest home for it: reachable from either pane,
never scrolls, and its badge is the profile's notification indicator rather than
one pane's. The badge is `hooprRed` — the one thing on the screen asking to be
dealt with, in the colour the app reserves for exactly that; orange is the brand
and is everywhere on this screen, so a badge in it would say "waiting" no louder
than the row icons beside it.

**There is no orange header any more.** It was a fixed `0.14` slab of
`hooprOrange → hooprDarkOrange` under the status bar, and it spent the most
valuable real estate on the page restating something the user already knows,
in the app's loudest colour, permanently. The identity is *content* now:
`ProfileIdentityBlock` sets a 72pt avatar, the `@handle` at 30pt and the uid
underneath on the page background, and it scrolls past like anything else.
Orange survives as the avatar's ring and the row icons — an accent, not a
ground.

What replaces it is `ProfileTopBar`: a 52pt bar holding a back chevron that is
always there, plus a glass background and a small avatar + handle that fade in
only once the identity block is gone. The fade is driven by two measurements —
`onScrollGeometryChange` for the offset, `onGeometryChange` for the block's
height, since that height moves with the reader's text size — crossing 0→1 over
the last 32pt of the block's travel (`barProgress`). The glass is the same
surface the shell header floats on — `.hooprGlass(interactive: false, in: .rect)`
— extended past the top safe area, with the same load-bearing `contentShape` (a
clear fill doesn't hit-test, and content scrolls directly underneath).
`interactive: false` because this is chrome, not a control: it has nothing to
respond to a touch with.

**Glass is never called directly.** `.hooprGlass(tint:interactive:in:)` in
`Support/Glass.swift` wraps the `#available(iOS 26)` for the whole app and
falls back to `.ultraThinMaterial` below it — the floor is iOS 18. That covers
this header, `GlassChip`, `HooprSearchField`'s glass ground, `BandBackButton`,
and the two map controls in `MAP_LAYER.md`. Glass shapes that sit side by side
are grouped with `HooprGlassGroup` (iOS 26's `GlassEffectContainer`, the
content unchanged below it) — the map's filter chips, since glass can't sample
other glass (UI revamp Phase 4). The map's sheet stays deliberately opaque: it
holds rows you read (`MAP_LAYER.md`).

The handle is **rendered, not stored** — `userName` is a display name (see
`UserProfile`), so it strips whitespace and prefixes an `@`. The uid comes from
`AuthService`, not the profile document, so it resolves with the session rather
than waiting on a Firestore snapshot. The uid is a button that copies it to the
pasteboard, its glyph swapping to a checkmark for 1.6s rather than raising a
toast: quoting the uid is the only reason it's on screen, and nobody retypes 28
characters.

**The Profile pane is one column of rows, not a card mosaic.** `ProfileRow`
replaced `ProfileCard`, and the mosaic went with it. That layout sized every
card to its slot — a `.feature` `Home Court` spanning two tiles, `Email` full
width between two pairs — which meant a card's *height* carried meaning its
content didn't, and a long court name had to shrink to fit a tile rather than
simply be read. A row is the opposite trade: one field per line, a symbol on
the left, label over value, chevron when it leads somewhere, values free to run
the width of the page.

**Since UI revamp Phase 2b the rows sit on the page** (`UI_REDESIGN_BRIEF.md`
§5.9). Each field used to carry its own card *and* a tinted icon tile — 7 panels
and 14 shapes in one screenful, the boxiest screen in the app. Now the rows are
grouped under `label`s ("Your game", "Account") inside `DividedRows`, the symbol
is a plain secondary mark in a fixed 28pt column, and the identity above is the
screen's band: the handle at `display`, the home court under it (the one fact
that identifies you to other people), the uid demoted to a caption. At rest the
top bar takes the band's ground, so the page opens on one band rather than a
bar, a strip of page and then the block.

**Rows state no height at all** — the mosaic's `@ScaledMetric` floors
(`tileHeight`, `featureHeight`) are gone with it. A row is as tall as its own
content, which is what lets a value wrap or scale at large Dynamic Type sizes
without a caller predicting it. Nothing interlocks any more, so nothing needs a
floor. `ProfileRow` and `ProfileActionRow` share `ProfileRowSymbol`, so the
tappable rows and Sign Out keep one leading column.

A row's `detail` (the home court's city) is a trailing fragment on the *value*
line, set off with a middot — and it's dropped **whole** rather than truncated
alongside the value. `ViewThatFits` offers the pair first and the bare value
second, so a wide row reads "Bethesda Park · Durham" and a narrow one reads one
cleanly truncated name. Laid out as a plain `HStack` both halves end in an
ellipsis, which is worse than either.

Values are **one line, truncating with an ellipsis** rather than wrapping. That
makes every row the same height without any of them stating one, and it's why
`homeCourtName` resolves through `Court.displayName`: "Bethesda Park Basketball
Court" is "Bethesda Park" on a row already labelled Home Court, and the words it
drops are the ones that push a real name past the width.

Passing `onTap: nil` renders a row read-only — `Email` (owned by Firebase Auth;
changing it needs a re-authentication flow this screen doesn't have), `Joined`
(`createdAt` is write-once server-side), and `Favorites` (starred from the map,
so the profile only counts them). A read-only row isn't a `Button` at all, so
there's no disabled state to style.

`Password` is the one row whose value is a fiction: `••••••••` is a stand-in,
because Auth stores a hash and this app has never held the password. Tapping it
opens `ChangePasswordSheet`, which **collects no password either** — it sends a
one-time reset link to the account's address, and the new password is chosen on
that link's page. Being signed in is the authorisation, so no current password
is asked for. The row falls back to read-only when there's no address to send
to, via the same `onTap: nil` mechanism.

**Sign Out is the last row, not a bar.** It was a `safeAreaInset` with a rule
along its top; a pinned bar over a page that already scrolls to the bottom is a
permanent reminder of the one action nobody comes here for — and it made no
sense at all under the Friends pane. It's a `ProfileActionRow` tinted
`hooprRed`, the last row of the Account group. Errors raised outside a sheet (a profile load, a sign-out) used to
surface in that bar and now lead the Profile pane, where they're read before
the fields they're about.

Edit flows are unchanged: `.sheet(item:)` on `ProfileViewModel.editingField`,
with appearance and the password reset outside it — see "Navigation" above.
Every sheet on the screen, both panes', is applied in `body` around a `page`
property, which is the only reason `body` and the page are separate.

The home-court picker is search-only: with 214 courts an up-front list is noise.
Name matches rank above city-only matches, capped at 25 suggestions.

## Visual conventions

Colours are named by **role** in `Support/Theme.swift`, and every one resolves
per appearance through a `UIColor` dynamic provider. There are no literal
colours in `Views/` — no `.black`, no `Color.white`, no RGB — which is what
keeps a light-only value from creeping back in.

| Role | Used for |
|---|---|
| `hooprOrange` | Brand **fill** — primary buttons, selected chips and pills (the selected profile pane, the queue sheet's day selector, the format chip), the tint on active glass, and the 12–14% wash behind a badge. **A fill, never a mark:** as a foreground it is 3.17:1 on white, 2.91:1 on `hooprFill`, and 2.78:1 on its own wash. Lifted in dark mode, where the light-mode orange reads muddy. |
| `hooprBrandAccent` | Brand **mark** — orange drawn as something *read*: text ("Sign up", a sheet's "Done", the HOSTING badge), glyphs, focus rings and selection strokes, the capacity bar, spinner / slider / date-picker tints, and the tab bar's selected item. `hooprOrange`'s own hue and saturation, deepened in light mode (`#B8400F`) until it clears 4.5:1 on every ground it is drawn on; in dark mode it *is* `hooprOrange`'s dark value, which already does. **Never a fill** — black on it is 3.78:1. `BrandMarkUsageTests` fails if a view draws `hooprOrange` in `foregroundStyle`, `tint` or `stroke`. |
| `hooprDarkOrange` | The map's marker tint, via `UIColor(Color.hooprDarkOrange)`. |
| `hooprRed` | Errors, Sign Out, "Remove home court", and the notification indicators — the inbox badge and the profile button's dot. Lightened in dark mode to hold contrast. |
| `hooprOnBrand` | Content *on top of* the orange — button labels, the selected pane's title, the map pin's glyph. **Black**, and fixed: orange is a light colour in both appearances, so white on it measured 2.55:1 / 2.25:1 — under AA, on every primary button. Black clears 8.24:1 / 9.33:1. |
| `hooprOnRed` | The one label drawn on a solid red fill (the inbox badge's count). The only role here that inverts, because `hooprRed` is deep in light mode and lightened in dark: white passes light and fails dark, black the reverse. |
| `hooprFormWin` / `hooprFormLoss` | The form guide's played dots — green a win, red a loss (the user's call, 2026-09-22). Each clears the 3:1 graphic floor on the band and on a card, in both appearances; win on the light band (3.15:1) sets how light the green can go. `hooprFormLoss` is a role of its own rather than `hooprRed`: a loss is a result, not an error, and dark mode's error red sits too close to the win green in lightness (1.62:1 against 2.25:1). |
| `hooprFormUnplayed` | A form slot not yet played. **About 2:1, deliberately below the played dots** — a placeholder, not a third kind of result. |
| `hooprOnFormResult` | The ✓ / ✕ drawn on a played dot when *Differentiate Without Color* is on. White in light mode, black in dark (the dark dots are light colours), like `hooprOnRed`. |
| `hooprBackground` | The page behind everything. |
| `hooprSurface` | Cards and sheets. Equal to the background in light mode (separation there comes from border + shadow); lifted in dark mode, where a shadow on black conveys nothing. |
| `hooprFill` | Field and button fills, unselected chips, the empty half of a capacity bar. |
| `hooprSquadWash(_:)` / `hooprBrandWash` | A crest colour, or the brand orange, **at the hero band's own luminance** — scaled toward black in dark mode, mixed toward white in light, in linear light. The ground of the squad bands, game day's band and Login's (`HeroWash`). Contrast depends only on luminance, so every ratio on the band holds unchanged: the brief measured a *tint* out of the band in Phase 2b (M3), and this is the answer that passes. Dark reads as the squad's colour (a maroon, a navy); **light is necessarily faint**, because near white sRGB has almost no room for colour at that luminance. `ThemeContrastTests` asserts the luminance match, a visible cast in dark, and every band pairing on every wash and on the mixes the mesh draws between wash and band. |
| `hooprGroupedBackground` | The ground of an inset-grouped form — `CreateGameSheet` — whose `FormPanel`s are `hooprSurface`, so the page steps *down* around them: `hooprFill`'s value in light, the page's black in dark. Resolves to those proven values on purpose, so every pairing drawn on it is already asserted; `ThemeContrastTests` pins that and that a panel steps off it in both appearances. |
| `hooprBorder` | Rules, dividers, unfocused borders, the sheet's drag handle. Deliberately faint (1.2:1 on white) — a hairline that tidies a card's edge, not a boundary. |
| `hooprElevatedSurface` | A surface raised one level above a card — a card inside a sheet, a popover. **Dark carries the lift in the fill** (`#242426`, one visible step above a card and one below a field); **light cannot** — nothing is lighter than white — so it *is* white there and the lift comes from `hooprShadow`. Defined and asserted in Phase 1, not yet drawn anywhere. Whether light mode's page ground moves off pure white is a design decision the role does not make. |
| `hooprHoverFill` | A row or control being touched or hovered, drawn over a card. Light `#ECECEC` matches the pill the iOS 26 tab bar draws behind its selected item (`#EDEDED`, sampled). Dark is deliberately no lighter than `#2E2E30` — primary text, secondary text and the accent must keep clearing 4.5:1 on it, and the accent is the ceiling. Not yet drawn anywhere. |
| `hooprSeparatorStrong` | A line that has to be *seen* — a component boundary at the 3:1 WCAG 1.4.11 asks of one, on every ground in both appearances. Where `hooprBorder` is faint on purpose. Drawn as every hero band's baseline, the Login fields' unfocused outline, `WinnerButton`'s edge, game day's not-yet-arrived circle and the create sheet's unselected radio — each where a boundary has to be seen, not merely tidied. |
| `hooprHeat(tier:)` / `hooprOnHeat(tier:)` | The "how busy is this court today" ramp — five fixed fills, each paired with the label that reads on it. **One table**, so a fill and its label can't be retuned apart: black through tier 2, white from tier 3, where black stops clearing 4.5:1 (it was 4.01 and 3.43 on the two deepest, on the map pin's count). Fixed, not appearance-aware, on purpose — a data scale read against the map's own basemap. Views call `CourtHeat`, which owns the count-to-tier rule. |
| `hooprPrimaryText` | Titles, values, primary labels. |
| `hooprSecondaryText` | Labels, captions, unselected tab text. |
| `hooprShadow(opacity:)` | Card and sheet shadows. Takes the *light-mode* opacity and deepens it in dark mode. |
| `hooprOnCrest` | The glyph at the centre of a squad crest. **Black, and a role of its own rather than a reuse of `hooprOnBrand`** — the two resolve alike today but answer different questions, and borrowing the brand role is exactly the mistake the inbox badge made before `hooprOnRed` existed: it passed by luck, under a name that promised something else. |
| `hooprSquad(_:)` | The eight crest fills, by allowlisted key. Every one is light enough in both appearances that `hooprOnCrest` clears the 4.5:1 *text* floor on it — stricter than the 3:1 a glyph needs, so an initial or a record could be dropped into the disc later without re-litigating the palette. |

### The crest and the form guide

`SquadCrest` is **one view with a size parameter, not five drawings**. Five named
sizes (`hero` 64, `card` 44, `row` 32, `pool` 24, `inline` 20) and every
proportion inside — glyph, hairline — derives from that one number, so a new size
can't disagree with the others. Its glyph deliberately keeps
`.font(.system(size:))` rather than `hooprFont`: it is locked inside a frame that
can't grow, and a name always sits beside it, so it never needs to scale.

**The crest is `accessibilityHidden` almost everywhere, on purpose** — it is
rendered beside the squad's name, and announcing it too would read the squad
twice. Two exceptions earn a label: `CreateSquadSheet`'s preview, the one crest
that is *feedback* rather than decoration, and the result screen's two winner
buttons, where the crest is the control. Where a crest carries the meaning alone
— the match card's crest-vs-crest row — the **row** gets the label, not the
crest.

`FormGuide` renders the last five confirmed results as **five dots** — green a
win, red a loss, grey for a game not yet played, most recent on the left — so the
row is always five long (the user's call, 2026-09-22; it replaced W/L letter
pills). **Colour is the only cue drawn by default, and that is measured, not
overlooked:** WCAG accepts lightness as a second cue at 3:1 between the two
fills, and that isn't reachable while both dots clear 3:1 on the band (1.95:1
light, 2.25:1 dark at best). So the record numeral beside the dots gives the
counts, VoiceOver reads the order, and with iOS's *Differentiate Without Color*
on each played dot grows (16 → 22pt) and carries a ✓ or ✕. `ThemeContrastTests`
pins every one of those numbers, and `FormGuideTests` covers the padding and the
spoken form.

**The lettered pills are gone.** `FormPill` (W/L) and `NeutralResultPill` (!, –, ·)
were retired on 2026-09-23 when squad detail's history moved to the same dots:
each history row is a `FormDot` (green, red, or grey for anything unconfirmed)
beside the result **spelled out** — "Won", "Lost", "Results don't match",
"Cancelled" — so the list never relies on colour. The neutral pill's history is
worth keeping: it shipped with no `maximumSize` in a fixed 28pt circle and its
glyph rendered taller than the circle; a dot carries no glyph to overflow.

**On squad home the dots are pinned to the band's bottom-right corner** (the
user's call, 2026-09-22): the record numeral holds the left edge with no caption,
the dots hold the right, and their bottoms sit on the numeral's baseline. A
`ViewThatFits` moves them beneath the numeral, still right-aligned, only when
they don't fit beside it. They do fit beside even a "10–10" at `.accessibility3`.
The larger *Differentiate Without Color* dots stack at that size (366pt of
362pt, measured in `FormGuideTests`). Squad detail draws the same line — the
crest row and the record line are shared components (`SquadIdentity`,
`SquadRecordLine` in `SquadBand.swift`), so the push opens on the band that was
tapped.

Type goes through `.hooprFont(_:weight:maximumSize:)` in
`Support/Typography.swift`, never `.font(.system(size:))`. The design's literal
point sizes are kept and scaled with `UIFontMetrics` against whichever text
style's default size is nearest, so Dynamic Type works while the default text
size still renders exactly what was drawn. `maximumSize` caps the scaling where
a frame can't grow (the pinned header, fixed-height buttons, 44pt hit targets);
omit it wherever the layout can reflow.

**Appearance follows the device by default, and can be pinned.**
`AppearancePreference` (System / Light / Dark) is stored in `UserDefaults` — a
device preference, not an account one — read by `hooprApp` and applied with
`.preferredColorScheme` at the window root so it reaches sheets too. It's edited
from the Appearance row on the profile screen, which is why that row sits
outside `ProfileViewModel.EditableField`: nothing about it touches Firestore.

### Motion

**One vocabulary, in `Support/Motion.swift`** (UI revamp Phase 3). A change
says what *kind* of change it is and the file decides how it moves:
`.hooprSpring` for something the user moved (a selection sliding, a panel
opening, the map's sheet on a detent), `.hooprSnap` for a control's own state
(a radio, a chip, a count, a press), `.hooprSwap` for content replacing content
(the matchmaking card's states, the create sheet's invite step). Entrances use
`.hooprLift` — fade in while rising 8pt, with a quicker fade out for what they
replace — and small things on top of others use `.hooprPop`. **No view writes
its own duration or spring**; the one exception left is `MainTabView`, which a
parallel session owns.

**Reduce Motion turns every kind into the same 0.15s cross-fade**, stops
entrances travelling, stops pressed buttons shrinking and symbols bouncing, and
turns the zoom pushes back into ordinary pushes. The static members read
`UIAccessibility.isReduceMotionEnabled`, because an action closure has no
environment; `MotionTests` pins the rules through the pure functions.

**Nothing animates on first appearance.** Every animation hangs off a change —
`withAnimation` in an action, `.animation(_:value:)` keyed on a value, a
transition on an insertion — so a screen draws in its final state the first
time.

What it's used for:

- **Press feedback:** `.buttonStyle(.hooprPress)` on every button that draws
  its own fill — it shrinks to 97% and dims while held.
- **Live counts roll:** `hooprNumericTransition(_:)` on spots left, the Runs
  count, the record, arrivals on game day, the inbox badge and the friends and
  inbox counts. Not on the radius numeral, which tracks a slider and must not
  lag it.
- **Symbols:** the invite link's and the user ID's copy glyph, the create
  sheet's radio marks, the map card's star and game day's arrival circles swap
  with `.symbolEffect(.replace)`; the inbox tray bounces once when a request
  *arrives* (`hooprBounce(onRiseOf:)`), not when one is answered.
- **Card to detail:** squad detail zooms out of the band's squad or its row,
  and game day out of the match card (`hooprZoomSource` /
  `hooprZoomDestination`, iOS 18's zoom navigation transition).
- **Lists:** Runs' cards fade and shrink slightly as they cross the scroll
  view's edges (`hooprScrollLift`), and a run arriving or leaving moves the
  others rather than jumping them.
- **Haptics** (`.sensoryFeedback`), only for changes the user caused: joining
  a run, joining a waitlist or marking one complete is `.success`; leaving or
  cancelling is a light impact; starting a run, copying a link, marking yourself
  here and a search turning into a match are `.success`. The run haptics hang off
  `lastConfirmation` on `LocalRunsViewModel` and `FindAMatchViewModel`, which
  only a write the server accepted sets — a roster changing under the listener
  never buzzes. Match found is keyed on the card going *from searching* to
  matched, so opening the tab onto an existing match is silent.

### Hero washes

`HeroWash` (`Views/Components/HeroWash.swift`, UI revamp Phase 4) is a band's
ground with colour in it: a static, linearly interpolated `MeshGradient` from a
wash into the plain `hooprHeroBand`, which is always drawn underneath so the
colour fades *in* over it when a squad loads. **It carries identity, never
decoration** — the squad's colour on Seasons, squad detail and game day (*whose
squad, which of mine is playing*), the brand's on Login (*what app is this*).
Home carries the brand's (the user's call, 2026-09-23: the home page wanted
"some sort of design" and the logo), with the wordmark above it. Runs and
Profile have no owner colour and stay plain; `ResultView` stays
plain too, because its hero is the winner's crest and a band in one squad's
colour would read as the answer.

### The status bar scrim

The band screens — Home, Runs, Seasons, squad detail, game day, result — have
no bar: the band is the header and it scrolls. `hooprStatusBarScrim()` puts the
status bar's own strip in the page colour, solid behind the clock and fading
over its lower quarter, so scrolled content passes under it rather than under
the clock and battery. **At rest it's invisible** — the band starts below the
status bar — and it sizes itself from its view's position on screen (62pt on
iPhone 17). iOS 26's scroll edge effect was tried first and draws nothing
without real bar content.

### The court glyph

A court is marked with **`Image.court`** (`Views/Components/CourtSymbol.swift`):
a basketball court from above — a three-point arc and the key at each end, the
centre circle, the half-court line — knocked out of a filled tile. **SF Symbols
has no basketball court**; the app used `sportscourt.fill` until 2026-09-23,
and the user pointed out it is a soccer pitch. It is a custom symbol
(`Assets.xcassets/hoopr.court.fill.symbolset`), drawn by
`tools/make_court_symbol.swift` — regenerate it there, never edit the SVG — so
it sizes with `.hooprType(_:)`, sits on a text baseline and takes
`.foregroundStyle` as the system glyph did. It draws about **1.36× wider than
its point size** (the old glyph was 1.56×), which `CourtCardLayoutTests`
measures. Drawn by `CourtTitle` (Home's band, the map's court card, the create
sheet), the profile's home-court line, and the create sheet's invite step.

### Spacing

Named in `Support/Spacing.swift`, in two layers: a **scale** on a 4pt grid
(`hairline` 2, `xs` 4, `sm` 8, `md` 12, `lg` 16, `xl` 20, `xxl` 24, `xxxl` 32) and
the **roles** views should reach for — `pageMargin` (20), `cardPadding` (16),
`interCard` (16), `interRow` (12), `section` (24), and the `Pill` and `Chip`
paddings. The values were already the app's; what was missing was a name, and
the absence is how the Runs tab came to inset its title 20pt and its cards 16.
That tab now uses `pageMargin` throughout — the one intentional layout change
of Phase 1.

**Fixed points, not `@ScaledMetric`.** Text reflows and never shrinks; the space
around it is deliberately not what grows with it, or a reader at
`.accessibility3` loses a third of the width to margins.

**What is not on the scale, on purpose:** corner radii (four in use — 10, 12,
14, 16 — with no rule about which is which), fixed control heights (seven, for
three kinds of button), `ProfileView`'s 10pt row gap, and `Chip`'s 14 × 9, which
is optically tuned against its 13pt label. They are composition decisions.

**Every screen now insets its content `Spacing.pageMargin` (20).** The last
four at 16 — `InboxSheet`, `QueueSheet`, `GameDayView`, `ResultView` — moved
with their Phase 2b redesigns on 2026-09-23.

---

## Invariants

- Top-level screen selection lives in `RootViewModel.destination`. Don't add a
  fourth presentation path around it.
- `ProfileView` is presented in place of `MainTabView`, never inside it.
- Tab content keeps its state across switches, and that is `TabView`'s job now
  rather than an opacity trick. Don't reintroduce a hand-rolled tab bar: the
  system one is what supplies 44pt targets, Dynamic Type, VoiceOver and hit
  testing over the map. The Friends pane still has the rebuild problem inside
  `ProfileView` — its views are rebuilt on every pane switch — and solves it by
  keeping `FriendsViewModel` and every piece of pane state on the screen.
- The profile button appears on every tab and never on `ProfileView`. It is
  `ProfileButton`, not a per-screen copy, because the badge rule belongs in one
  place.
- A list screen is built from the `LocalRunsTab` parts — collapsible section
  header *(**withdrawn 2026-09-22** for `LocalRunsTab` itself: Phase 2b
  replaced disclosure with rank — one list ordered by tip-off, ownership drawn
  as a rail. The other two clauses stand)*, one shared card, one write in
  flight — **unless the screen's primary job is an action rather than a list**,
  which is the Friends exception: search
  is a pinned control and the inbox is screen chrome, so only the last of those
  three parts survives there. `ProfileView`'s rows are a fixed set of distinct fields, not a
  list.
- One write in flight is keyed by whatever the screen's rows are *about* —
  `pendingGameId` on Local Runs, `pendingUid` on Friends. A friendship ID can't
  key a search result, because a search result has no friendship yet.
- Anything showing another player renders a deliberate subset of their profile.
  `users` is readable whole by any signed-in account, so that subset is a
  display choice, not privacy — don't reach for a field just because it decodes.
- A card's action is resolved once and reused by its button and its
  confirmation dialog. Don't recompute it at tap time.
- Colours come from `Theme.swift`, including the map's `UIColor` marker tint,
  which bridges from `Color.hooprDarkOrange` rather than restating its RGB. A
  literal colour in a view is a bug — it won't invert.
- Font sizes go through `.hooprFont(...)`. The deliberate exceptions are sized
  as a fraction of a fixed shape and commented as such: `PlayerAvatar`'s initial
  and glyph, `SquadCrest`'s glyph, and `FormDot`'s ✓ / ✕. (`ProfileRow`'s
  symbol left the list with its tinted square in the Phase 2b revamp; it now
  scales through `hooprFont` up to a cap that fits its column.)
- Read-only profile fields are expressed by omitting `onTap`, not by a
  disabled-state flag.
- Profile rows are sized by their content. Don't give one a fixed height:
  `.frame(height:)` doesn't clip, so a row whose text needs more room paints
  over its neighbour. This is what the old card mosaic's `minHeight` floors
  existed to work around.
- The Friends pane's two halves stay stateless. Anything they'd hold between
  them would be stranded — the search field pins as a section header while the
  list scrolls in the section body.
- There is **one** notification indicator per surface, and it's `hooprRed`: the
  profile button on the shell, the inbox badge on the profile. Don't add a
  third that points at a screen the requests don't live on.
- Every colour pairing the UI draws clears WCAG AA, and `ThemeContrastTests`
  holds the line. Contrast is arithmetic on two resolved colours, not taste —
  if a new pairing appears, assert it there rather than eyeballing it. Measure
  the ground a mark *actually* sits on: HOSTING's orange text is on a 12% orange
  wash, not on the card, and that is what took it to 2.78:1 while a check
  against the card said 3.17.
- **Orange is a fill or a mark, never both.** `hooprOrange` fills a surface that
  carries `hooprOnBrand`; anything *read* in orange — text, a glyph, a stroke, a
  spinner or control tint — is `hooprBrandAccent`. `BrandMarkUsageTests` reads
  `Views/` and fails on `hooprOrange` inside `foregroundStyle`, `tint` or
  `stroke`; it never fires on a fill, so a new orange button is free.
- A mark and the wash behind it are two colours. A badge draws its
  mark in `hooprBrandAccent` over a wash of `hooprOrange`; sharing one tint
  between them dulls the wash the moment the mark is deepened.
- A label drawn on the heat ramp is `hooprOnHeat(tier:)`, never `hooprOnBrand`.
- Spacing that means "the page margin", "a card's padding" or "the gap between
  cards" is a `Spacing` role, not a literal.
- A court is rendered through `Court.displayName`, never `name`. The stored name
  repeats "Basketball Court" in an app where everything is one.
- Text locked in a frame that can't grow carries `maximumSize`; text that can
  reflow doesn't. **Never `minimumScaleFactor`** — a hand-rolled header full of
  it is what the native tab bar was adopted to stop needing. Where a row of
  chips stops fitting, `ViewThatFits` takes a column instead of squeezing them:
  the queue sheet's three time chips broke mid-word at `.accessibility3` until
  it did.
- A decorative glyph is `accessibilityHidden` **only** while the thing it stands
  for is named beside it. When a glyph carries meaning alone, label the element
  that contains it — a label on a hidden view is silent, and the hidden view is
  usually right.
- An empty list gets a sentence saying why it's empty, and "nothing here yet"
  is a different sentence from "this failed to load". `hasLoadedGames` /
  `hasLoadedSquads` exist so the two can be told apart.

## See also

- `MAP_LAYER.md` — everything inside the map tab.
- `ARCHITECTURE.md` — what's injected into each of these views.
- `database/USER_PROFILE_WORKFLOW.md` — what backs the profile screen.
