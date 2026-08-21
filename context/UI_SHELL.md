# hoopsRN — UI Shell

**Scope:** `hoopr/Views/RootView.swift`, `hoopr/Views/MainTabView.swift`,
`hoopr/Views/LoginView.swift`, `hoopr/Views/Profile/`, `hoopr/Views/Games/`,
`hoopr/Views/Tabs/LocalRunsTab.swift`, `hoopr/Views/Friends/`,
`hoopr/Views/Components/ErrorBanner.swift`, `hoopr/Support/Theme.swift`,
`hoopr/Support/Typography.swift`, `hoopr/Support/AppearancePreference.swift`
**Verified:** 2026-08-21 @ da44193

Navigation structure and the visual conventions every screen follows. Read this
before adding a screen, changing how one is presented, or picking a colour or a
font size.

---

## Navigation

There is no `NavigationStack` at the top level and no system `TabView`. The
whole shell is conditional rendering.

```
RootView                    switches on RootViewModel.destination
├── .launching → LaunchScreen
├── .login     → LoginView
└── .main      → MainTabView
                 ├── mainInterface (header + 2 pill tabs + content ZStack)
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
swaps its entire body; `ProfileView` takes an `onBack` closure.

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

- Header is a fixed `geo.size.height * 0.14` bar: greeting on the left, profile
  button on the right, then a row of two pill tabs. Because its height is
  pinned, its type is capped — see "Visual conventions".

**The header floats over the content rather than stacking above it.** The shell
is a `ZStack(alignment: .top)`, not a `VStack`, so the map runs to every edge of
the screen and passes underneath the header and the status bar. The header's
background is clear glass extended past the top safe area, so the status bar
sits on glass rather than directly on the map.

Two consequences, both easy to undo by accident:

- **`.contentShape(Rectangle())` on the header is load-bearing.** A clear fill
  does not hit-test, and the map is now the header's ZStack *sibling
  underneath* rather than a panel below it — so without an explicit hit shape
  every tap and drag on the header reached MapKit and panned the map, tab pills
  included. It's applied twice: on the header itself, and on the extended
  background that covers the status bar.
- **The two list tabs get the header's height back as `safeAreaPadding(.top:)`**,
  applied by `MainTabView`. That's what keeps their content clear of the bar
  while still letting it scroll underneath. `MapTab` deliberately does *not*
  get this — the map is supposed to run under the header — so it reads
  `\.floatingHeaderHeight` from the environment and insets only its own
  floating chrome.
- Greeting reads `userProfileService.currentProfile?.userName`, falling back to
  `"there"` while the first snapshot is in flight.
- Tabs: Court Map / Local Runs. **Friends used to be the third**, and moving it
  into `ProfileView` as a pane is what freed the slot — the shell is written for
  `tabs.count`, so the next one is a case here plus a branch in
  `content(headerHeight:)`.
- **The profile button carries the notification dot**, which the Friends pill
  used to. Friends is inside the profile now, so the control that opens the
  profile is what says something is waiting in it. The dot is `hooprRed`, not
  the brand orange, matching the inbox badge it leads to — this header is
  already orange in places, and a notification has to read as one thing to deal
  with rather than as more brand. It reads `FriendService` directly rather than
  a view model, which is what keeps the dot alive while the profile is closed —
  an inbox you can only discover by already being inside it isn't a
  notification.
- Selected pill is glass tinted
  `hooprOrange`; unselected is `.clear` glass. Neither is an opaque fill any
  more — over a moving map an opaque grey pill reads as a hole punched in the
  bar.

**`MapTab` stays mounted** — it's always in the content `ZStack`, hidden
with `.opacity` + `.allowsHitTesting`, while the other two tabs mount
conditionally. This is deliberate: it preserves map region, zoom, and sheet
state across tab switches. Rebuilding it on selection would reset the map to
`initialRegion` every time. Any future tab with expensive or user-positioned
state should follow the same pattern.

`.ignoresSafeArea(edges: .bottom)` on the shell plus `.clipped()` on the content
is what lets the bottom sheet run to the screen edge.

## `LocalRunsTab`

Two collapsible sections — **Queued Games** (runs you're on) and **Public
Games** (discoverable runs inside your `preferredRadius`) — over a single
`ScrollView`. One scroll gesture stays in charge, and the two are read together
anyway: "am I busy, and what else is on?"

Section expansion is **`@AppStorage`, not `@State`**. This tab is unmounted
whenever another tab is selected, so view state would reopen both sections on
every visit and silently discard the choice. `MapTab` solves the same
problem by staying mounted; that isn't available here without paying for a
permanently live tab.

Cards are `GameCard`, shared by both sections so a run reads identically
wherever it appears — only the primary action differs (Join / Join waitlist /
Leave / Cancel run, resolved by `LocalRunsViewModel.action(for:)`). The action
is resolved **once per row** and handed to both the button and its confirmation
dialog, so a dialog saying "Cancel run" can't perform a join.

Only one roster write is in flight at a time: the acting card shows a spinner
and every other card's button goes inert, so a double tap can't race the
transaction already running.

A card for a run you host that isn't public also carries an `InviteLinkCard` —
the run's `hoopsrn://game/{id}` link, shown in full with a tap that copies it.
Host-only: an invite-only run is the host's to hand out. **The link doesn't
resolve yet** — nothing registers the scheme and nothing handles an incoming
URL, so it's a string to send while the receiving half is built (`GAPS.md` §4).

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

**`InboxSheet`** holds what's waiting: **Requests** (incoming, what the badge
counts) and **Sent** (outgoing, cancel-only). Friend requests are the only kind
of notification today, so there is deliberately **no notification-kind
abstraction** — a second kind costs a second section, and an `InboxItem` enum
for one case would be invented structure.

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
`.glassEffect(.regular, in: .rect)` the shell header floats on, extended past
the top safe area, with the same load-bearing `contentShape` (a clear fill
doesn't hit-test, and content scrolls directly underneath).

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
| `hooprOnBrand` | Content *on top of* the orange — button labels, the selected pane's title. Fixed white: the brand colour it sits on doesn't invert. |
| `hooprBackground` | The page behind everything. |
| `hooprSurface` | Cards and sheets. Equal to the background in light mode (separation there comes from border + shadow); lifted in dark mode, where a shadow on black conveys nothing. |
| `hooprFill` | Field and button fills, unselected chips, the empty half of a capacity bar. |
| `hooprBorder` | Rules, dividers, unfocused borders, the sheet's drag handle. |
| `hooprPrimaryText` | Titles, values, primary labels. |
| `hooprSecondaryText` | Labels, captions, unselected tab text. |
| `hooprShadow(opacity:)` | Card and sheet shadows. Takes the *light-mode* opacity and deepens it in dark mode. |

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
- `MapTab` must stay mounted across tab switches; hide it with opacity,
  don't unmount it.
- `LocalRunsTab` *is* unmounted on tab switches, so anything the user chose
  there belongs in `@AppStorage`, not `@State`. The Friends pane has the same
  problem inside `ProfileView` — its views are rebuilt on every pane switch —
  and solves it by keeping `FriendsViewModel` and every piece of pane state on
  the screen instead.
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
- A court is rendered through `Court.displayName`, never `name`. The stored name
  repeats "Basketball Court" in an app where everything is one.

## See also

- `MAP_LAYER.md` — everything inside the map tab.
- `ARCHITECTURE.md` — what's injected into each of these views.
- `database/USER_PROFILE_WORKFLOW.md` — what backs the profile screen.
