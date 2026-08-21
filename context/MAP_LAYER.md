# hoopsRN — Map Layer

**Scope:** `hoopr/Views/MapView.swift`, `hoopr/Views/Tabs/MapTab.swift`,
`hoopr/Views/Tabs/CourtRow.swift`
**Verified:** 2026-08-13 @ map-tab

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
so VoiceOver has something to read. Nothing renders it.

The view is a shadowed `ring` (surface-coloured) containing a `disc` (brand
orange) containing either the basketball glyph or a cluster count. **Colours are
set as UIView `backgroundColor`s, never `CALayer.backgroundColor`** — a
`UIColor` from `Theme.swift`'s dynamic provider only re-resolves on a trait
change when a view holds it; a layer colour freezes at whichever appearance was
current when it was assigned.

Because a circle marks its spot with its centre rather than a tip,
`centerOffset` is `.zero` and `collisionMode` is `.circle`. Courts are 34pt,
clusters 38pt so a group reads as "more than one" before you've read its number.

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
private enum SheetState: Equatable {
    case list
    case collapsed
    case detail(court: Court, returningTo: RestState)
}
```

`.detail` **carries the rest state it came from**, so dismissing a court
restores whatever the sheet was showing beforehand — a pin tapped while the
sheet was collapsed returns to collapsed, not to the list. `restState` and
`selectedCourt` are the accessors; `RestState` is the two-case subset (`.list`,
`.collapsed`) that a drag can settle into.

Sheet height is `UIScreen.main.bounds.height / 3`. Collapsing offsets it by its
full height — the sheet leaves the screen entirely and the floating `collapsedPeek`
pill is what remains, fading in only over the last 40% of the travel
(`peekOpacity`) so it never competes with the sheet it replaces.

**Drag ownership.** The handle claims any drag (`minimumDistance: 0`). Inside
the list, `sheetDragGesture(fromHandle: false)` only claims a drag that is
downward *and* starts with the list at the top (`listScrollOffset <= 1`, fed by
`onScrollGeometryChange`); otherwise the gesture returns without setting
`sheetDrag` and the scroll view keeps it. Once the sheet is dragging,
`.scrollDisabled(sheetDrag != 0)` stops the list scrolling underneath.

Other constants: `tapSlop` 6pt — a handle drag shorter than this is treated as a
tap and toggles the sheet; `collapseThreshold` 60pt, applied to
`predictedEndTranslation` so a flick settles the same way a long drag does;
`headerHeight` 52, `peekBottomInset` 28. Overshoot is rubber-banded through
`resistance(_:)`, an exponential ease toward a 40pt limit.

## Distances and location

`NearbyCourt` pairs a court with its distance, computed **once when the list is
built** (in a Combine `CombineLatest` over both `courtService.$courts` and
`userProfileService.$currentProfile`), never during scroll. Radius comes from
`userProfile.preferredRadius` (defaults to 5 miles if unset); the list is sorted
nearest-first.

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
- `zoomLevelFromSpan` and `spanFromZoomLevel` must remain exact inverses.
- Distances are computed once when the nearby list is built (in `CombineLatest`),
  not during scroll. The radius comes from the profile's `preferredRadius`.
- The initial region, list distances, and the recenter target all read
  `FindAMatchViewModel.homeLocation`, which forwards to
  `LocationService.homeLocation`. Keep the single anchor.

## See also

- `UI_SHELL.md` — why this tab stays mounted while the other two don't.
- `COURT_DATASET.md` — where the annotations' data comes from.
- `DATA_MODEL.md` — `Court` fields, including the ones the sheet doesn't show.
