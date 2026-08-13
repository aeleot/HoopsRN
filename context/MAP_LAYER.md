# Hoopr — Map Layer

**Scope:** `hoopr/Views/MapView.swift`, `hoopr/Views/Tabs/FindAMatchTab.swift`,
`hoopr/Views/Tabs/CourtRow.swift`, `hoopr/Views/Tabs/FindMatchTab.swift`
**Verified:** 2026-08-13 @ map-tab

The map tab and its bottom sheet — the densest interaction code in the app, and
the part most likely to break subtly when edited. Read this before touching
`MapView.swift` or `FindAMatchTab.swift`. `FindMatchTab` is still a placeholder
label; the Local Runs tab moved to `UI_SHELL.md`.

---

## The UUID trigger pattern

SwiftUI drives the UIKit map through three one-shot commands. Each carries a
`UUID` and defines `==` on that ID alone, so a newly constructed trigger is
*always* unequal to the previous one — even for an identical recenter target or
zoom level — which forces `updateUIView` to run. The `Coordinator` then records
the ID it last handled so the command is applied exactly once.

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

`ZoomTrigger` (stepped, `.zoomIn`/`.zoomOut`) and `AbsoluteZoomTrigger` (slider,
a 0…1 level) are the same shape with their own `lastZoomId` /
`lastAbsoluteZoomId`. Any new imperative map command should follow this pattern;
comparing on the payload instead would silently drop repeat commands.

## Annotation diffing

`updateUIView` diffs by `court.id` — set difference in both directions, then
`removeAnnotations` / `addAnnotations` on the delta only. Never reload
wholesale: a full reset drops the current selection and re-animates every pin.

`canShowCallout = false` on the marker view is deliberate — the bottom sheet
owns detail display, so MapKit's callout would be a competing surface.

The marker tint is a hardcoded `UIColor(red: 1.0, green: 0.494, blue: 0)`
duplicating `Color.hooprOrange` rather than deriving from it (see `GAPS.md`).

## Zoom conversion

Zoom is a log scale between spans of **0.01°** (`minDelta`, level 1.0 = closest)
and **5.0°** (`maxDelta`, level 0.0 = widest). `zoomLevelFromSpan` and
`spanFromZoomLevel` are exact inverses, which is what keeps the slider and the
map agreeing after a pinch. Changing one without the other desynchronises them.

Stepped zoom multiplies the current span by **0.75** (in) or **1.4** (out),
clamped to the same bounds. The slider is a plain `Slider` rotated −90° so up is
zoom-in.

## Timing constants

- **200ms debounce** on `regionDidChangeAnimated` before reporting the zoom
  level up, so a pan doesn't fire a callback per frame.
- **50ms delay** in `didDeselect` before calling `onMarkerDeselect`, then a
  re-check of `mapView.selectedAnnotations`. Tapping pin-to-pin deselects the
  old pin *before* selecting the new one; without the delay the sheet would
  close and immediately reopen.
- **`isDraggingSlider` guard** in `onZoomLevelChange`: while the finger is on
  the slider, map-driven zoom updates are ignored. Without it the map's reported
  level fights the value the user is dragging.

---

## `FindAMatchTab` — the sheet state machine

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
