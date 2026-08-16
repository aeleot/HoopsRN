# hoopsRN — UI Shell

**Scope:** `hoopr/Views/RootView.swift`, `hoopr/Views/MainTabView.swift`,
`hoopr/Views/LoginView.swift`, `hoopr/Views/Profile/`, `hoopr/Views/Games/`,
`hoopr/Views/Tabs/LocalRunsTab.swift`, `hoopr/Views/Tabs/FriendsTab.swift`,
`hoopr/Views/Friends/`, `hoopr/Support/Theme.swift`,
`hoopr/Support/Typography.swift`, `hoopr/Support/AppearancePreference.swift`
**Verified:** 2026-08-15 @ map-tab

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
                 ├── mainInterface (header + 3 pill tabs + content ZStack)
                 └── ProfileView   (replaces the above entirely)
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
  button on the right, then a row of three pill tabs. Because its height is
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
- Tabs: Court Map / Local Runs / Friends. Selected pill is glass tinted
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

## `FriendsTab`

Occupies the third tab slot, which was a placeholder (`FindMatchTab`, a centred
`Text` and nothing else) until the `friendships` collection existed to put
behind it.

**This is the one list screen that is *not* built from the `LocalRunsTab`
parts,** and the departure is deliberate. It was that shape once — two
collapsible sections (Requests, Friends) over one `ScrollView` — which fits
Local Runs because its two lists answer one question together ("am I busy, and
what else is on?"). A social screen isn't that. Finding someone is an *action*
and needs a permanently visible control, and requests waiting on you must not
be reachable only by expanding a dropdown. So:

```
VStack
├── toolbar (pinned)   [ 🔍 search field ..... ] [ 📥 inbox • badge ]
└── ScrollView
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
name, since `userName` isn't unique. The home court has a labelled card on the
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
`ProfileCard` with `onEdit: nil`, so these cards can't drift from your own
profile's. Every relationship action lives in its bottom action bar (a
`safeAreaInset`, like `ProfileView`'s Sign Out). It holds a **uid**, never a
snapshot, and reads back through the view model on every render, so a name
landing or the other person accepting updates the open sheet.

Removing a friend is the one action behind a confirmation dialog: a declined
request can be re-sent by the other person, but an unfriend is only undone by
asking again. One write in flight at a time, keyed on the **person** rather than
the friendship — a search result has no friendship document yet.

Names are **not** stored on a friendship — `FriendsViewModel` resolves them
through `UserProfileService.profiles(for:)` and renders the row with a skeleton
until they arrive. A name that fails to resolve leaves the row fully actionable,
retries on the next snapshot, and is healed by `loadProfileIfNeeded(for:)` when
its profile sheet opens.

The **Friends pill in `MainTabView` carries a dot** while a request is
unanswered, read straight off `FriendService` rather than through the view
model — the tab is unmounted when you're not on it, and an inbox you can only
discover by already being on its tab isn't a notification.

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

Orange identity header at **`geo.size.height * 0.14`** — the same fraction
`MainTabView` pins its own header to, so the two screens share a skyline and
the profile doesn't open on a quarter-screen of orange. One row: back button,
avatar, then the `@handle` with the **Auth uid in italics beneath it** — held
well below the handle in size and contrast. The uid row is a button that copies
it to the pasteboard, glyph swapping to a checkmark for 1.6s rather than
raising a toast: quoting the uid is the only reason it's on screen, nobody
retypes 28 characters, and the header has no room for a larger confirmation. At this
height there's no room to stack the back button above the avatar and no need
to, since nothing collides in a single line. Avatar size is `min(56, max(38, height * 0.44))`; it carries the user's
initials, falling back to a person glyph while the first snapshot is in flight
or for a name with no letters in it. The header background is an
`hooprOrange → hooprDarkOrange` gradient under `.ignoresSafeArea(edges: .top)`,
so it bleeds beneath the status bar while content still lays out inside the
safe area.

The handle is **rendered, not stored** — `userName` is a display name (see
`UserProfile`), so the header strips its whitespace and prefixes an `@`. The
uid under it comes from `AuthService`, not the profile document, so it resolves
with the session rather than waiting on a Firestore snapshot.

Below it, the profile is a **card mosaic, not a list** — `ProfileCard`s in two
titled sections, "Your Game" and "Account". The cards interlock: `Home Court`
is a `.feature` card spanning the `Favorites` and `Radius` tiles beside it, and
`Email` runs full width between two pairs of tiles. Card chrome matches
`GameCard` — 16pt radius, `hooprSurface`, 1pt `hooprBorder`, a 6% shadow — so a
card reads the same here as on the Local Runs tab.

**Cards state a floor, never a fixed height.** `ProfileView` owns one
`@ScaledMetric` unit (`tileHeight`, 80pt at the default text size) and derives
`featureHeight = tileHeight * 2 + 12` from it, then hands both to
`.frame(minHeight:maxHeight: .infinity)`. A fixed height was the first attempt
and was wrong: `.frame(height:)` doesn't clip, so a card whose content needed
more room painted *outside* its own frame and over its neighbour — visibly, in
the right-hand column. A floor plus a stretch fixes it from both ends: a card
can't be shorter than its grid unit, it grows when its content needs to, and
because it's stretchable the tallest card in a row pulls the rest up to match.
The seams stay aligned at every Dynamic Type size without this view predicting
how tall any card's text will be.

Passing `onEdit: nil` renders a card read-only — used for `Email` (owned by
Firebase Auth; changing it needs a re-authentication flow this screen doesn't
have), `Joined` (`createdAt` is write-once server-side), and `Favorites`
(starred from the map, so the profile only counts them). A read-only card isn't
a `Button` at all, so there's no disabled state to style. On an editable card
**the whole card is the tap target**; the pencil is the affordance saying so,
not a control in its own right.

`Password` is the one card whose value is a fiction: `••••••••` is a stand-in,
because Auth stores a hash and this app has never held the password. Editing it
opens `ChangePasswordSheet`, which **collects no password either** — it sends a
one-time reset link to the account's address, and the new password is chosen on
that link's page. Being signed in is the authorisation, so no current password
is asked for. The card falls back to read-only when there's no address to send
to, via the same `onEdit: nil` mechanism.

The Sign Out bar is a `safeAreaInset` with a 1pt `hooprBorder` rule along its
top — the grid scrolls underneath it, and without the rule a card is simply cut
off mid-height.

The home-court picker is search-only: with 213 courts an up-front list is noise.
Name matches rank above city-only matches, capped at 25 suggestions.

## Visual conventions

Colours are named by **role** in `Support/Theme.swift`, and every one resolves
per appearance through a `UIColor` dynamic provider. There are no literal
colours in `Views/` — no `.black`, no `Color.white`, no RGB — which is what
keeps a light-only value from creeping back in.

The palette is five source colours — jet `#2D3142`, slate `#4F5D75`, silver
`#BCC0C8`, white, and coral `#EF8354` — with everything else derived from them.
**Light is the flagship.** Light-mode separation is a jet-tinted neutral ramp
plus border and shadow; dark mode is jet at 0dp with white overlays standing in
for elevation, not hand-picked greys.

| Role | Used for |
|---|---|
| `hooprBrand` | Coral. **Only things you can tap that advance you** — primary buttons, the selected tab pill, map pins, the profile header, the favourite star. Identical in both appearances. |
| `hooprBrandDeep` | The far end of the profile header's gradient and the selected map pin. Stops where it does so the header's small italic uid still clears AA at the deep end. |
| `hooprBrandText` | Coral where it has to be *read* — text buttons ("Save", "Done"), links, the wordmark, the avatar initial. Coral itself is 2.61:1 on white; this is the same hue deepened. |
| `hooprOnBrand` | Content on top of coral. **Jet, not white** — white on coral is 2.61:1 and fails AA. |
| `hooprSecondary` | Slate. Everything coral shouldn't do: focus rings, selection controls, sliders, selected chips, decorative glyphs, the waitlist state. |
| `hooprOnSecondary` | Content on a filled slate surface. White in light, jet in dark. |
| `hooprOpen` | Roster under 70%. |
| `hooprFilling` | Roster 70–99%. Hue 46°, deliberately off coral's 18° — at 36° it read brown. |
| `hooprRed` | Errors, Sign Out, destructive actions, the "Restricted" court badge. |
| `hooprBackground` | The page behind everything. Off pure white in light mode so cards can lift. |
| `hooprSurface` | Cards and sheets. White in light; the 1dp rung in dark. |
| `hooprFill` | Field grounds, unselected chips, the empty capacity track. In dark mode it sits *below* the surface — a field is recessed into a card, not raised off it. |
| `hooprBorder` | Rules, dividers, unfocused borders, the sheet's drag handle. |
| `hooprPrimaryText` | Titles, values, primary labels. Jet, not pure black. |
| `hooprSecondaryText` | Labels, captions, unselected tab text. Slate on light, silver on dark. |
| `hooprShadow(opacity:)` | Card and sheet shadows, jet-tinted. Takes the *light-mode* opacity and deepens it in dark mode. |
| `hooprDisabledOpacity` | 0.38, from Material's guidance. One value, replacing scattered `0.4`/`0.5` literals. |

**Two constraints this palette carries.** Coral cannot be darkened: between
roughly 46% and 58% lightness neither a jet nor a white label clears AA, and the
given coral sits just above that band. And in dark mode coral is 4.94:1 on the
0dp ground but 2.97:1 at 24dp, so coral *text* belongs on backgrounds and low
cards — anywhere higher it appears as a fill carrying a jet label.

`hooprElevatedSurface` and `hooprOnError` were both considered and deliberately
left out: nothing draws on them, and each would have pinned a contrast pairing
the app never renders.

**`ThemeContrastTests` pins every pairing the UI actually makes** — text at
4.5:1, graphics and component boundaries at 3:1. It is scoped to real pairings
on purpose; adding a role there without a call site pins a number nobody sees.

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
- `LocalRunsTab` and `FriendsTab` *are* unmounted on tab switches, so anything
  the user chose there belongs in `@AppStorage`, not `@State`. (Only
  `LocalRunsTab` still has such a choice — `FriendsTab`'s collapsibles are
  gone.)
- A list screen is built from the `LocalRunsTab` parts — collapsible section
  header, one shared card, one write in flight — **unless the screen's primary
  job is an action rather than a list**, which is the `FriendsTab` exception:
  search and the inbox are pinned controls, and only the last of those three
  parts survives there. `ProfileView`'s mosaic is for a fixed set of distinct
  entities, not a list.
- One write in flight is keyed by whatever the screen's rows are *about* —
  `pendingGameId` on Local Runs, `pendingUid` on Friends. A friendship ID can't
  key a search result, because a search result has no friendship yet.
- Anything showing another player renders a deliberate subset of their profile.
  `users` is readable whole by any signed-in account, so that subset is a
  display choice, not privacy — don't reach for a field just because it decodes.
- A card's action is resolved once and reused by its button and its
  confirmation dialog. Don't recompute it at tap time.
- Colours come from `Theme.swift`, including the map's `UIColor` marker tint and
  its shadow, which bridge from `Color.hooprBrandDeep` and
  `Color.hooprShadow(opacity:)` rather than restating an RGB or reaching for
  `.black`. A literal colour in a view is a bug — it won't invert.
- `hooprBrand` is for actions. Selection, focus and decoration go to
  `hooprSecondary`. The previous palette had one hue on 52 call sites doing ten
  different jobs, which is how it stopped meaning anything.
- A filled surface and its content are chosen **as a pair**. Moving a fill from
  brand to secondary without moving its label shipped jet-on-slate at 1.94:1.
- Font sizes go through `.hooprFont(...)`. The one deliberate exception is the
  profile avatar's initials and glyph, sized as a fraction of a fixed-diameter
  circle and commented as such.
- Read-only profile fields are expressed by omitting `onEdit`, not by a
  disabled-state flag.
- Profile cards take a **floor** (`minHeight` + `maxHeight: .infinity`) from
  `tileHeight`/`featureHeight`. A `.frame(height:)` there doesn't clip — it
  overflows onto the neighbouring card.

## See also

- `MAP_LAYER.md` — everything inside the map tab.
- `ARCHITECTURE.md` — what's injected into each of these views.
- `database/USER_PROFILE_WORKFLOW.md` — what backs the profile screen.
