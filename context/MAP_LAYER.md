# hoopsRN — Map Layer

**Scope:** `hoopr/Views/MapView.swift`, `hoopr/Views/Tabs/MapTab.swift`,
`hoopr/Views/Tabs/CourtRow.swift`, `hoopr/Views/Components/CourtBadges.swift`,
`hoopr/Support/CourtHeat.swift`
**Verified:** 2026-08-21 @ 0edbeec

The map tab and its bottom sheet — the densest interaction code in the app, and
the part most likely to break subtly when edited. Read this before touching
`MapView.swift` or `MapTab.swift`. The Local Runs tab and the profile are in
`UI_SHELL.md`.

`MapTab` was called `FindAMatchTab` until the third tab stopped being a
"Find Match" placeholder and became Friends — at which point a file named for
matchmaking that renders the court map was purely confusing. Its view model is
still `FindAMatchViewModel`.

---

## The UUID trigger pattern

SwiftUI drives the UIKit map through a one-shot command. It carries a `UUID` and
defines `==` on that ID alone, so a newly constructed trigger is *always*
unequal to the previous one — even for an identical recenter target — which
forces `updateUIView` to run. The `Coordinator` then records the ID it last
handled so the command is applied exactly once.

```swift
struct RecenterTrigger: Equatable {
    let center: CLLocationCoordinate2D
    let id: UUID

    init(center: CLLocationCoordinate2D) {
        self.center = center
        self.id = UUID()
    }

    static func == (lhs: RecenterTrigger, rhs: RecenterTrigger) -> Bool {
        lhs.id == rhs.id
    }
}
```

```swift
if let trigger = recenterTrigger, trigger.id != context.coordinator.lastRecenterId {
    context.coordinator.lastRecenterId = trigger.id
    // …apply
}
```

`RecenterTrigger` is the only one left. Any new imperative map command should
follow this pattern; comparing on the payload instead would silently drop repeat
commands.

**`ZoomTrigger`, `AbsoluteZoomTrigger`, `zoomLevelFromSpan` and
`spanFromZoomLevel` are gone**, along with the `+`/slider/`−` stack that was
their only caller. The vertical zoom slider occupied a 44×180pt column of the
map to duplicate a pinch, and no shipping iOS map app has one. `minDelta` /
`maxDelta` survive as plain constants because the cluster-tap zoom still clamps
against `minDelta`.

## The north bias

Every `setRegion` — the initial region and the recenter trigger both — goes
through `MapView.biasedNorth(_:)` first, which shifts the region's centre south
by `0.12 * span.latitudeDelta`.

`setRegion` centres its target in the map view's **bounds**, but the map runs
edge to edge underneath the floating header and behind the bottom sheet, so a
target centred in the full screen lands below the centre of what's actually
visible between them. Moving the region south moves the target north on screen.
It's `setVisibleMapRect(_:edgePadding:)` without the Mercator-space padding
maths, which `MapView` can't do anyway — it doesn't know the header or sheet
heights.

The 0.12 is sized against `MapTab`'s geometry: a ~0.14-screen-height header and
a sheet at its medium detent (~⅓ of the screen) put the visible gap's centre
around 40% down rather than 50%. Change either of those and this fraction is
what stops matching.

## Annotation diffing

`updateUIView` diffs by `court.id` — set difference in both directions, then
`removeAnnotations` / `addAnnotations` on the delta only. Never reload
wholesale: a full reset drops the current selection and re-animates every pin.

`canShowCallout = false` on the marker view is deliberate — the bottom sheet
owns detail display, so MapKit's callout would be a competing surface.

## `CourtMarkerView`

Pins are a **custom `MKAnnotationView` subclass**, not `MKMarkerAnnotationView`.
Two reasons, and the second is the load-bearing one:

1. The teardrop silhouette is instantly recognisable as stock Apple Maps.
2. `MKMarkerAnnotationView` **draws `annotation.title` beneath itself**. Every
   court in the OSM extract is named `<Place> Basketball Court`, so that
   produced labels wrapping onto three lines — "Long Meadow Park Basketball
   Court #2 / +2 more" — that covered more of the map than the roads did. A
   plain `MKAnnotationView` subclass draws no label at all.

`CourtAnnotation.title` is still populated, now from `Court.displayName`, purely
so VoiceOver has something to read. Nothing renders it, and `subtitle` is gone
entirely.

The view is a shadowed `ring` (surface-coloured) containing a `disc`
containing either the basketball glyph or a cluster count. **Colours are set as
UIView `backgroundColor`s, never `CALayer.backgroundColor`** — a `UIColor` from
a dynamic provider only re-resolves on a trait change when a view holds it; a
layer colour freezes at whichever appearance was current when it was assigned.
That reasoning used to apply only to `Theme.swift`'s roles; since the heat map
(below) the disc's colour is a fixed, non-dynamic `UIColor` bridged fresh from
`CourtHeat` on every configure call, so the dynamic-provider case no longer
applies to *this* colour specifically — the rule about setting it on the view
rather than the layer still does, because `configureAsCourt`/`configureAsCluster`
re-set `disc.backgroundColor` on every call anyway (selection changes, a game
being booked), and a layer colour would still need the same re-assignment.

Because a circle marks its spot with its centre rather than a tip,
`centerOffset` is `.zero` and `collisionMode` is `.circle`. Courts are 34pt,
clusters 38pt so a group reads as "more than one" before you've read its number.

## `CourtHeat` — the pins' heat-map colouring

Added 2026-08-21. Every pin's disc is coloured by **how many games are
scheduled at that court today**, not by the fixed brand orange: a light,
white-leaning sky blue for nothing scheduled, climbing through two close warm
ambers, and landing on a deep red for the busiest tier. `CourtHeat.swift` owns
the five-stop lookup (`color(forGameCount:)`, clamped at both ends); nothing
about the map's own code decides what the colours *are*, only what count goes
in.

**Selection no longer changes a pin's colour.** It used to swap to
`hooprDarkOrange`; now the heat colour is drawn regardless of selection, and a
selected pin is set apart purely by the existing scale-up (1.25×) and raised
collision priority in `configureAsCourt`. Conflating "selected" with "busy"
would have made a cool, quiet court flash warm the moment you tapped it — the
opposite of what the colour is supposed to mean.

**Where the count comes from.** `FindAMatchViewModel.gameCountsByCourt` (see
`ARCHITECTURE.md`) buckets `GameService`'s `queuedGames` + `publicGames` by
court for the current calendar day, and publishes it as
`gameCountByCourtID: [String: Int]`. `MapTab` threads that straight into
`MapView`, which is the only thing that ever calls `CourtHeat`:

- `MapView.heatColor(for:)` looks up a single court's own count.
- `MapView.heatColor(forCluster:)` walks a `MKClusterAnnotation`'s
  `memberAnnotations`, sums each member court's count, and colours the cluster
  disc by that **sum** — not by how many courts got folded together. A cluster
  of five quiet courts stays the quiet blue; two courts with three games each
  make a two-court cluster read as busy as the four-tier ceiling. The member
  count MapKit hands back still drives the number printed on the disc; it just
  no longer drives the colour under it.

**No new read, no rules change.** The two arrays this sums are exactly what
`GameService`'s existing listeners already deliver — public runs, plus runs the
signed-in user is personally on. A pin's colour can therefore never reveal a
private run this account isn't part of; it can only ever show what the read
rule already let this account see. See `PRODUCT_OVERVIEW.md` for the
user-facing description.

**Why colour has to be re-applied on every `updateUIView`, cluster views
included.** `viewFor` only runs when MapKit creates or recycles a view, but a
pin's count can change with no annotation being added, removed, or reselected —
someone just booked a game. `updateUIView`'s restyle loop used to skip
`MKClusterAnnotation`s entirely (it only matched `CourtAnnotation`); it now
branches on both, because a cluster's colour is exactly as live as a solo
pin's.

## Basemap suppression

`MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)` plus
`pointOfInterestFilter = .excludingAll`, and on the map view itself:
`showsCompass`, `showsScale`, `showsTraffic`, `showsBuildings` all off,
`pitchButtonVisibility = .hidden`, `selectableMapFeatures = []`.

**That is as far as MapKit goes.** Road labels, highway shields and
neighbourhood names have no API and cannot be hidden. Removing those means
leaving Apple's tiles entirely — either an `MKTileOverlay` with
`canReplaceMapContent = true` (keeps every line of this file's annotation and
clustering code) or a port to MapLibre Native, which supports `pmtiles://`
directly as of iOS 6.10.0. Neither is done; don't re-litigate the muting
options above without knowing this is the ceiling.

## Timing constants

- **50ms delay** in `didDeselect` before calling `onMarkerDeselect`, then a
  re-check of `mapView.selectedAnnotations`. Tapping pin-to-pin deselects the
  old pin *before* selecting the new one; without the delay the sheet would
  close and immediately reopen.

---

## `MapTab` — the sheet state machine

```swift
private enum Detent { case collapsed, medium, expanded }

private enum SheetState: Equatable {
    case rest(Detent)
    case detail(court: Court, returningTo: Detent)
}
```

**Two orthogonal axes, deliberately not merged.** `Detent` is how far up the
sheet sits; `SheetState` is what it's showing. `.detail` carries the detent to
fall back to, so dismissing a court restores whatever the sheet was at
beforehand — a pin tapped while the sheet was collapsed returns to collapsed.

Three accessors do the work, and mixing them up is the bug this shape invites:

- `detent` — what a drag settles into, and what a dismiss restores.
- `displayDetent` — where the sheet actually renders. **A detail card always
  shows at `.medium`, whatever it will restore to.** Without this, a court
  tapped while the list sits collapsed inherits the collapsed offset and the
  card renders entirely off-screen.
- `selectedCourt` — `nil` unless `.detail`.

**Geometry comes from the tab, not the screen.** `containerHeight` is fed by
`onGeometryChange`, seeded at 852 so the first frame is sensible before geometry
lands; `mediumHeight` is a third of it and `expandedHeight` 0.78 of it.
`UIScreen.main` is deprecated on iOS 26 and is no longer read anywhere.

Between medium and expanded the sheet **grows and shrinks** — `sheetHeight`
tracks the finger, so the top edge moves and the bottom stays put. Only heading
to or from `.collapsed` does it **offset** instead, leaving the screen entirely;
the floating `collapsedPeek` pill is what remains, held at zero opacity until
the sheet is 60% gone and fading in over the last 40% of the travel
(`peekOpacity`) so it never competes with the sheet it replaces.

**Drag ownership.** The handle claims any drag (`minimumDistance: 0`). Inside
the list, `sheetDragGesture(fromHandle: false)` uses an 8pt minimum and only
claims a drag that is downward *and* starts with the list at the top
(`listScrollOffset <= 1`, fed by `onScrollGeometryChange`); otherwise it returns
without setting `sheetDrag` and the scroll view keeps it. Once the sheet is
dragging, `.scrollDisabled(sheetDrag != 0)` stops the list scrolling underneath.

**One detent per gesture.** `nextDetent(from:projecting:)` steps a single
position against `predictedEndTranslation` — so a flick settles the same way a
long drag does, and a hard fling from expanded can't skip past medium and off
the bottom of the screen.

Other constants: `tapSlop` 6pt — a handle drag shorter than this is a tap, which
toggles between medium and collapsed; `detentThreshold` 60pt; `peekBottomInset`
28. Overshoot is rubber-banded through `resistance(_:)`, an exponential ease
toward a 40pt limit, applied only past the collapsed extreme. Every settle
animates on the same `.spring(response: 0.35, dampingFraction: 0.85)`.

## Map chrome

Everything floating over the map is **Liquid Glass** (`.glassEffect`): the
filter chips, the recenter button, and the collapsed peek pill. An *active*
filter chip tints the same glass with `Color.hooprOrange` rather than swapping to
an opaque fill, so it reads as the same object lit up instead of a different one.

The sheet is deliberately **not** glass. Small chrome you look past can be
translucent; a list of courts is something you read, and reading it against a
moving map is worse in every way than reading it against a surface.

The map `.ignoresSafeArea()` — it *is* the screen, running under the status bar,
the app's floating header and the home indicator. So `mapOverlay` insets itself
by `floatingHeaderHeight` (an `@Environment` value published by the shell, see
`UI_SHELL.md`) plus 10pt, and by `max(0, sheetHeight - sheetOffset)` at the
bottom so the chrome stays clear of the sheet at any detent. The trailing
`Spacer` in that `VStack` is load-bearing: it holds the stack at full height so
the row stays pinned to the top of a bottom-aligned `ZStack`.

The recenter button is the **only map control left** — see the zoom-stack note
above.

## The court detail card

Reached from a pin tap or a list row, both through `select(_:recenter:)`.
It carries the court's `displayName`, a `city · distance` line, the same
`CourtBadges` the list row shows, and two buttons:

- **Directions** — hands the court to Maps via `MKMapItem.openInMaps`, driving
  mode. The app knows where courts are and nothing about how to get to one.
- **Start Run** — presents `CreateGameSheet` for that court. One button covers
  both entry points because both converge here. See `UI_SHELL.md`.

**There is no address row, deliberately.** In this dataset `address` is the city
and state — "Durham, NC" — which the metadata line above it already says. It's
still passed to Maps by `openDirections(to:)`, where it does work.

The card and the row show the same badges on purpose: before that, tapping a
court to learn more about it showed you *less* than the row you tapped it from.
`CourtBadges` is the shared view and the **only** definition of what those chips
say — `CourtRow` carried a private duplicate until 2026-08-21 that had already
drifted from it. Its "Restricted" chip is the odd one out, outlined in red
rather than filled, because every other label says what a court *has* while that
one says you may not get on it.

## Distances and location

`NearbyCourt` pairs a court with its distance, computed **when the list is
rebuilt**, never during scroll. Four Combine subscriptions — the dataset, the
radius (`preferredRadiusMiles`), favourites, and recents — each call `rebuild()`,
which re-ranks through `ranked(courts:from:)`. Radius comes from
`userProfile.preferredRadius` (defaults to 5 miles if unset); the list is sorted
nearest-first.

The detail card is the exception: it holds a bare `Court` with no precomputed
figure — a map pin never had a `NearbyCourt` — so it calls
`distanceText(for:)`, one `CLLocation.distance(from:)` against the same origin.
That's safe per render; the whole-dataset sort is not.

**Distances and the recenter button both use the hardcoded Durham location, not
the device's.** `FindAMatchViewModel.homeLocation` forwards to
`LocationService.homeLocation` (35.9940, −78.8986) — the app-wide anchor the
Local Runs radius filter also reads, so swapping it for a profile-owned value
moves every distance in the app at once. `recenterTarget()`
requests location permission on the first tap only — so MapKit can draw the blue
user dot — but returns the hardcoded point regardless, which is why the map no
longer blocks on a permission prompt. Swapping `homeLocation` for a profile-owned
value is the intended future change; the initial region, every list distance, and
the recenter target all read it, so the pipeline follows with no other edits.

`FindAMatchViewModel.select(_:)` records the court as recently viewed; the
sheet's own `select(_:recenter:)` does the visible work.

The court detail card carries the **"Start Run"** button, which presents
`CreateGameSheet` for that court. Both selection paths — a map pin and a
nearby-list row — already open this card, so one button serves both. See
`UI_SHELL.md`.

---

## Invariants

- Imperative map commands go through a UUID-identified trigger struct with `==`
  on the ID, and the `Coordinator` records the last-handled ID. Don't compare on
  payload.
- Annotations are diffed by `court.id`. Never `removeAnnotations(mapView.annotations)`.
- Every `setRegion` goes through `biasedNorth(_:)`. Centring on the raw region
  puts the target under the sheet.
- A `.detail` state renders at `.medium` regardless of the detent it restores
  to. Reading `detent` where `displayDetent` belongs renders the card
  off-screen.
- Sheet geometry derives from `containerHeight`, fed by `onGeometryChange`.
  Don't reintroduce `UIScreen.main` — it's deprecated on iOS 26.
- Distances are computed on `rebuild()`, not during scroll. The radius comes
  from the profile's `preferredRadius`, via `preferredRadiusMiles`.
- The initial region, list distances, and the recenter target all read
  `FindAMatchViewModel.homeLocation`, which forwards to
  `LocationService.homeLocation`. Keep the single anchor.
- A pin's colour comes from `CourtHeat`, never from `hooprOrange`/
  `hooprDarkOrange` directly, and never changes on selection. A cluster's
  colour is `CourtHeat` over the **sum** of its members' counts, not their
  member count. Both `viewFor` and `updateUIView`'s restyle loop must handle
  `MKClusterAnnotation`, not just `CourtAnnotation` — a restyle loop that only
  matches one silently stops recolouring the other the moment counts change
  without an annotation being added or removed.

## See also

- `UI_SHELL.md` — why this tab stays mounted while the other two don't.
- `COURT_DATASET.md` — where the annotations' data comes from.
- `DATA_MODEL.md` — `Court` fields, and the `displayName` derivation every
  court label on this screen goes through.
- `ARCHITECTURE.md` — `FindAMatchViewModel`'s dependencies and the
  cross-collection joins, including `gameCountsByCourt`.
- `PRODUCT_OVERVIEW.md` — the heat map described in product terms.
