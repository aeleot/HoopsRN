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
`hoopr/Support/Glass.swift`
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

**Selected tabs take `hooprOrange` via `.tint`; unselected stay in the system
grey.** Know what this costs: `.tint` colours the selected item's glyph *and*
its ~10pt label, which paints the brand as a **foreground** on a near-white
glass ground. That is the AA gap `GAPS.md` tracks — roughly 2.55:1 against the
4.5:1 floor — and the tab bar is now its most prominent instance. In light mode
the selected label reads *lighter* than the unselected ones, inverting the
hierarchy it is meant to signal. Shipped as a deliberate product decision;
`ThemeContrastTests.testTabBarSelectionIsATrackedGap` records it in the failing
direction and goes green the day a readable brand role lands.

**The profile button appears on all four tabs and nowhere else.** It is a
shared `ProfileButton` component (`Views/Components/`) with two styles: `plain`
for Home and Runs, and `glass` for the map, where it matches the recenter
control's 46pt glass circle. It owns the notification-dot rule — `hooprRed`, not
brand orange, matching the inbox badge it leads to, and reading `FriendService`
directly rather than a view model so the dot stays live while the profile is
closed. An inbox you can only discover by already being inside it isn't a
notification.

Each tab now names itself, since there is no shared header to do it: Home
carries the `"Let's hoop <name>."` greeting the header used to, and Runs
carries a plain `"Runs"` title. Home's header row centers vertically against
`ProfileButton`, matching Runs; the greeting is pinned to one line and shrinks
(`.minimumScaleFactor`) rather than wrapping, so the button's position never
depends on name length — a name past the 50-character ceiling truncates
rather than wrapping or shrinking to illegibility.

`courtToShowOnMap` is a `@State Court?` handed to `MapTab` as a binding. Home's
hot-court rows write to it and switch tabs; `MapTab` consumes it and writes back
`nil`, so the same court can be sent twice.
## `HomeTab`

The launch tab, added 2026-08-26. The app used to open on the map, which answers
"where can I hoop?" — a question you only have once you've decided to go out. It
can't answer "am I signed up for something tonight?", which is the more common
reason to open the app, so that is what this screen leads with.

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
`hooprPrimaryText` so it outweighs the grey details above it without reaching
for `hooprOrange`, which fails AA as a foreground in light mode.

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

**Rows are `FriendRow`**, a compact ~68pt card (avatar, name, `@handle`, one
trailing control) with the same chrome every card in the app carries. It
replaced the tall `FriendCard`, which put a full-width button under every name
and made twelve friends read as twelve forms. The trailing control is passed in
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
sheet swaps the form for an invite step titled "Run Created" with the same
`InviteLinkCard` the queued card uses. Cancel is dropped there and Create
becomes Done: the run already exists, so offering Cancel would read as
"discard it". The link is repeated on the card in Queued Games, so leaving
without copying costs nothing.

`InviteLink` (in `Support/`) owns the `hoopsrn://game/{id}` format — one
definition, because the create flow holds a bare document ID and the card holds
a whole `Game`. `GameTests` pins the string so the scheme can't move on one
side alone.

## `ProfileView`

**Two panes, one screen.** A `Pane` enum — `.profile`, `.friends` — behind a
segmented control. The pairing isn't arbitrary: both panes answer "who am I in
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
`Support/Glass.swift` wraps the one `#available(iOS 26)` for the whole app and
falls back to `.ultraThinMaterial` below it — the floor is iOS 18. That covers
this header, `GlassChip`, `HooprSearchField`'s glass ground, and the two map
controls in `MAP_LAYER.md`.

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
simply be read. A row is the opposite trade: one field per line, symbol in a
tinted square on the left, label over value, chevron when it leads somewhere,
values free to run the width of the page.

**Rows state no height at all** — the mosaic's `@ScaledMetric` floors
(`tileHeight`, `featureHeight`) are gone with it. A row is as tall as its own
content, which is what lets a value wrap or scale at large Dynamic Type sizes
without a caller predicting it. Nothing interlocks any more, so nothing needs a
floor. Chrome is the app's usual card — 14pt radius, `hooprSurface`, 1pt
`hooprBorder`, a 6% shadow — shared with `ProfileActionRow` through one
`profileRowChrome()` helper so the tappable rows and Sign Out can't drift.

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
`hooprRed`. Errors raised outside a sheet (a profile load, a sign-out) used to
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
| `hooprOrange` | Brand. Selected tab, selected profile pane, primary buttons, focused field borders, map pins, profile row icons and the avatar's ring, slider tint. Lifted in dark mode, where the light-mode orange reads muddy. |
| `hooprDarkOrange` | The map's marker tint, via `UIColor(Color.hooprDarkOrange)`. |
| `hooprRed` | Errors, Sign Out, "Remove home court", and the notification indicators — the inbox badge and the profile button's dot. Lightened in dark mode to hold contrast. |
| `hooprOnBrand` | Content *on top of* the orange — button labels, the selected pane's title, the map pin's glyph. **Black**, and fixed: orange is a light colour in both appearances, so white on it measured 2.55:1 / 2.25:1 — under AA, on every primary button. Black clears 8.24:1 / 9.33:1. |
| `hooprOnRed` | The one label drawn on a solid red fill (the inbox badge's count). The only role here that inverts, because `hooprRed` is deep in light mode and lightened in dark: white passes light and fails dark, black the reverse. |
| `hooprBackground` | The page behind everything. |
| `hooprSurface` | Cards and sheets. Equal to the background in light mode (separation there comes from border + shadow); lifted in dark mode, where a shadow on black conveys nothing. |
| `hooprFill` | Field and button fills, unselected chips, the empty half of a capacity bar. |
| `hooprBorder` | Rules, dividers, unfocused borders, the sheet's drag handle. |
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

`FormGuide` renders the last five results as W/L pills and `NeutralResultPill`
covers everything that isn't a result. Both are fixed-diameter circles, which is
precisely the case `maximumSize` exists for: `ResultPillMetrics` holds the
diameter and the cap together, and `SeasonsAccessibilityTests` measures them
against each other. The neutral pill shipped uncapped once and its glyph rendered
taller than its own circle.

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
  header, one shared card, one write in flight — **unless the screen's primary
  job is an action rather than a list**, which is the Friends exception: search
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
  and glyph, and `ProfileRow`'s leading symbol square.
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
  if a new pairing appears, assert it there rather than eyeballing it. The one
  known exception is `hooprOrange` used as a *foreground* in light mode, which
  fails and is tracked in `GAPS.md`.
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
