# Hoopr — UI Shell

**Scope:** `hoopr/Views/RootView.swift`, `hoopr/Views/MainTabView.swift`,
`hoopr/Views/LoginView.swift`, `hoopr/Views/Profile/`, `hoopr/Views/Games/`,
`hoopr/Views/Tabs/LocalRunsTab.swift`, `hoopr/Support/Theme.swift`,
`hoopr/Support/Typography.swift`, `hoopr/Support/AppearancePreference.swift`
**Verified:** 2026-08-13 @ map-tab

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

## `MainTabView`

- Header is a fixed `geo.size.height * 0.14` slab: greeting on the left, profile
  button on the right, then a row of three pill tabs, with a 1pt
  `hooprBorder` rule along the bottom and `zIndex(1)` so it stays above the
  map. Because the slab's height is pinned, its type is capped — see
  "Visual conventions".
- Greeting reads `userProfileService.currentProfile?.userName`, falling back to
  `"there"` while the first snapshot is in flight.
- Tabs: Court Map / Local Runs / Find Match. Selected pill is `hooprOrange` on
  `hooprOnBrand`; unselected is `hooprFill` on `hooprSecondaryText`.

**`FindAMatchTab` stays mounted** — it's always in the content `ZStack`, hidden
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
every visit and silently discard the choice. `FindAMatchTab` solves the same
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

## Starting a run

`CreateGameSheet` is presented from the court detail card in `FindAMatchTab`.
**Both entry points the feature calls for — a map pin and a nearby-list row —
already converge on that card**, so one "Start Run" button there covers both
without duplicating a control in the list.

The form collects four fields: when, public or invite-only, and roster size.
Everything else the `games` schema stores — host, status, both rosters, both
timestamps — is derived by `GameService` on the write path, so none of it
appears in the UI.

## `ProfileView`

Orange identity header at **`geo.size.height * 0.14`** — the same fraction
`MainTabView` pins its own header to, so the two screens share a skyline and
the profile doesn't open on a quarter-screen of orange. One row: back button,
avatar, then the `@handle`. At this height there's no room to stack the back
button above the avatar and no need to, since nothing collides in a single
line. Avatar size is `min(56, max(38, height * 0.44))`; it carries the user's
initials, falling back to a person glyph while the first snapshot is in flight
or for a name with no letters in it. The header background is an
`hooprOrange → hooprDarkOrange` gradient under `.ignoresSafeArea(edges: .top)`,
so it bleeds beneath the status bar while content still lays out inside the
safe area.

The handle is **rendered, not stored** — `userName` is a display name (see
`UserProfile`), so the header strips its whitespace and prefixes an `@`.

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
have), `Joined` (`createdAt` is write-once server-side), `Favorites` (starred
from the map, so the profile only counts them), and `Password` (a `••••••••`
stand-in — Auth stores a hash and this app never sees a password; the card is
here ahead of the reset flow, which is unbuilt). A read-only card isn't a
`Button` at all, so there's no disabled state to style. On an editable card
**the whole card is the tap target**; the pencil is the affordance saying so,
not a control in its own right.

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

| Role | Used for |
|---|---|
| `hooprOrange` | Brand. Selected tab, primary buttons, focused field borders, map pins, profile header, slider tint. Lifted in dark mode, where the light-mode orange reads muddy. |
| `hooprDarkOrange` | The map's marker tint, via `UIColor(Color.hooprDarkOrange)`. |
| `hooprRed` | Errors, Sign Out, "Remove home court". Lightened in dark mode to hold contrast. |
| `hooprOnBrand` | Content *on top of* the orange — button labels, the profile avatar. Fixed white: the brand colour it sits on doesn't invert. |
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
- `FindAMatchTab` must stay mounted across tab switches; hide it with opacity,
  don't unmount it.
- `LocalRunsTab` *is* unmounted on tab switches, so anything the user chose
  there (section expansion) belongs in `@AppStorage`, not `@State`.
- A card's action is resolved once and reused by its button and its
  confirmation dialog. Don't recompute it at tap time.
- Colours come from `Theme.swift`, including the map's `UIColor` marker tint,
  which bridges from `Color.hooprDarkOrange` rather than restating its RGB. A
  literal colour in a view is a bug — it won't invert.
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
