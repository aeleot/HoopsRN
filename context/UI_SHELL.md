# Hoopr — UI Shell

**Scope:** `hoopr/Views/RootView.swift`, `hoopr/Views/MainTabView.swift`,
`hoopr/Views/LoginView.swift`, `hoopr/Views/Profile/`, `hoopr/Support/Theme.swift`
**Verified:** 2026-08-07 @ 2d483bb

Navigation structure and the visual conventions every screen follows. Read this
before adding a screen, changing how one is presented, or picking a colour.

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
  `hooprBorderGray` rule along the bottom and `zIndex(1)` so it stays above the
  map.
- Greeting reads `userProfileService.currentProfile?.userName`, falling back to
  `"there"` while the first snapshot is in flight.
- Tabs: Court Map / Local Games / Find Match. Selected pill is `hooprOrange` on
  white text; unselected is `hooprLightGray` on `hooprSecondaryText`.

**`FindAMatchTab` stays mounted** — it's always in the content `ZStack`, hidden
with `.opacity` + `.allowsHitTesting`, while the other two tabs mount
conditionally. This is deliberate: it preserves map region, zoom, and sheet
state across tab switches. Rebuilding it on selection would reset the map to
`initialRegion` every time. Any future tab with expensive or user-positioned
state should follow the same pattern.

`.ignoresSafeArea(edges: .bottom)` on the shell plus `.clipped()` on the content
is what lets the bottom sheet run to the screen edge.

## `ProfileView`

Orange identity header at **3/12 of the screen height**, with the back button
flowing above the avatar rather than overlaid — at this height an overlay
collides with the avatar on shorter devices. Avatar size is
`min(88, max(56, height * 0.40))` so it still fits when 3/12 is under 200pt.
The header background uses `.ignoresSafeArea(edges: .top)` so orange bleeds under
the status bar while content still lays out inside the safe area.

Below it, four `ProfileFieldRow`s. Passing `onEdit: nil` renders a row read-only
— used for `email` (owned by Firebase Auth; changing it needs a re-authentication
flow this screen doesn't have) and `Date Joined` (`createdAt` is write-once
server-side). Editable rows get a 44pt tap target around a 16pt glyph.

The home-court picker is search-only: with 213 courts an up-front list is noise.
Name matches rank above city-only matches, capped at 25 suggestions.

## Visual conventions

Six colours in `Support/Theme.swift`, all literal RGB:

| Colour | RGB | Used for |
|---|---|---|
| `hooprOrange` | 255, 126, 0 | Brand. Selected tab, primary buttons, focused field borders, map pins, profile header, slider tint. |
| `hooprDarkOrange` | 230, 111, 0 | Declared but **unused**. |
| `hooprRed` | 185, 14, 10 | Errors, Sign Out, "Remove home court". |
| `hooprLightGray` | 245, 245, 245 | Field and button fills. |
| `hooprBorderGray` | 232, 232, 232 | Rules, dividers, unfocused borders, the sheet's drag handle. |
| `hooprSecondaryText` | 102, 102, 102 | Labels, captions, unselected tab text. |

Beyond the palette: fonts are always `.system(size:weight:)` with literal point
sizes — no Dynamic Type text styles. Backgrounds are `Color.white` and primary
text is `.black`, written directly rather than as semantic colours.

**The app is light-mode only.** There is no `@Environment(\.colorScheme)`
anywhere, no `prefers-color-scheme` handling, and the literal colours won't
adapt. Adding dark mode is a palette-wide change, not a per-screen one.

---

## Invariants

- Top-level screen selection lives in `RootViewModel.destination`. Don't add a
  fourth presentation path around it.
- `ProfileView` is presented in place of `MainTabView`, never inside it.
- `FindAMatchTab` must stay mounted across tab switches; hide it with opacity,
  don't unmount it.
- Colours come from `Theme.swift`. The map's `UIColor` marker tint is the one
  duplicate and should be reconciled, not copied.
- Read-only profile fields are expressed by omitting `onEdit`, not by a
  disabled-state flag.

## See also

- `MAP_LAYER.md` — everything inside the map tab.
- `ARCHITECTURE.md` — what's injected into each of these views.
- `database/USER_PROFILE_WORKFLOW.md` — what backs the profile screen.
