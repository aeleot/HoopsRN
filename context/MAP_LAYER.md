# hoopsRN — Map Layer

**Scope:** `hoopr/Views/MapView.swift`, `hoopr/Views/Tabs/MapTab.swift`,
`hoopr/Views/Tabs/CourtRow.swift`, `hoopr/Views/Components/CourtBadges.swift`,
`hoopr/Support/CourtHeat.swift`
**Verified:** 2026-08-26 @ 8ad0041

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
map to duplicate a pinch, and no shipping iOS map app has one. `maxDelta` went
with them, and `minDelta` followed on 2026-08-22: its last caller was the
cluster-tap zoom clamp, which died with clustering (below). **There is no
programmatic zoom left in the map at all** — only `setRegion` for the initial
region and the recenter trigger, both at fixed spans.

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

The 0.12 is sized against `MapTab`'s geometry: the chrome above and a sheet at
its medium detent (~⅓ of the usable height) put the visible gap's centre around
40% down rather than 50%. Change either of those and this fraction is what stops
matching. It was tuned against a ~0.14-screen-height floating header that no
longer exists; the sheet still dominates the calculation, so it was left alone
when the shell moved — worth re-checking if the top chrome grows.

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
containing the basketball glyph. **Colours are set as
UIView `backgroundColor`s, never `CALayer.backgroundColor`** — a `UIColor` from
a dynamic provider only re-resolves on a trait change when a view holds it; a
layer colour freezes at whichever appearance was current when it was assigned.
That reasoning used to apply only to `Theme.swift`'s roles; since the heat map
(below) the disc's colour is a fixed, non-dynamic `UIColor` bridged fresh from
`CourtHeat` on every configure call, so the dynamic-provider case no longer
applies to *this* colour specifically — the rule about setting it on the view
rather than the layer still does, because `configureAsCourt` re-sets
`disc.backgroundColor` on every call anyway (selection changes, a game being
booked), and a layer colour would still need the same re-assignment.

Because a circle marks its spot with its centre rather than a tip,
`centerOffset` is `.zero` and `collisionMode` is `.circle`. **Courts are 27pt**,
cut 20% from 34pt when clustering was removed (below) — with every court drawn
individually, a smaller circle is what keeps a dense block legible, because
MapKit hides a pin whose circle collides with a higher-priority neighbour's and
a smaller circle survives that test at more zoom levels. The glyph's symbol
point size was scaled with it (15 → 12) so it keeps its share of the disc.
There is no second diameter any more; `layOut()` takes no parameter.

## `CourtHeat` — the pins' heat-map colouring

Added 2026-08-21. Every pin's disc is coloured by **how many games are
scheduled at that court today**: an all-orange scale that *starts* on the
brand orange for nothing scheduled and darkens and reddens in even steps to a
saturated reddish orange for the busiest tier. `CourtHeat.swift` owns the
five-stop lookup (`color(forGameCount:)`, clamped at both ends); nothing about
the map's own code decides what the colours *are*, only what count goes in.

**Stop 0 is `hooprOrange`'s light value, hardcoded** (`F79331`), not a
reference to the role — the palette is deliberately fixed rather than routed
through `Theme.swift`'s light/dark provider, because it's a data scale read
against the muted basemap in both appearances rather than chrome that should
invert. `CourtHeatTests` pins the hex, which is what catches the two drifting
apart if the brand orange is ever retuned again.

The scale was rebased onto the brand orange on 2026-08-22. It previously
opened on a near-white cream (`FDECD8`) so a quiet court receded into the map;
starting at the brand orange makes an unbooked court read as a *court* first
and a quiet one second. The tradeoff is named rather than hidden: the whole
ramp now occupies the top half of the old lightness range, so "nothing today"
and "one game" differ by one even step rather than the pale-to-saturated jump
they used to. The three middle stops are a straight linear RGB interpolation
between the two ends, which is what keeps those steps even (~19 luma apiece,
hue walking 30° → 10°); two tests assert that shape.

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

`MapView.heatColor(for:)` looks up a single court's own count, and since
clustering was removed that is the only lookup there is — one pin, one court,
one number. (`heatColor(forCluster:)`, which summed counts across a group's
members, is gone with it.)

**No new read, no rules change.** The two arrays this sums are exactly what
`GameService`'s existing listeners already deliver — public runs, plus runs the
signed-in user is personally on. A pin's colour can therefore never reveal a
private run this account isn't part of; it can only ever show what the read
rule already let this account see. See `PRODUCT_OVERVIEW.md` for the
user-facing description.

**Why colour has to be re-applied on every `updateUIView`.** `viewFor` only
runs when MapKit creates or recycles a view, but a pin's count can change with
no annotation being added, removed, or reselected — someone just booked a game.
So `updateUIView` walks every `CourtAnnotation` on screen and re-runs
`configureAsCourt`, which re-applies both the heat colour and the selection
styling.

## There is no clustering

**Removed 2026-08-22.** MapKit's automatic clustering folded nearby courts into
a numbered disc. The number was the problem: it counted *member annotations*,
so it read as a court count while sitting on a disc whose colour meant
games-today — two different quantities in one badge, and the count was the
misleading one. "3" on a pin in a park with three adjacent courts said nothing
about whether anyone was playing there.

It could not be tuned into something honest. MapKit exposes **no public
radius/distance control** over when it clusters; the only lever is
`MKAnnotationView.clusteringIdentifier` (`nil` opts a view out entirely), and
a court's own view size has no effect on clustering at all — that's the
separate `collisionMode` mechanism. An attempt to gate `clusteringIdentifier`
on a zoom threshold also ran into the fact that it lives on the *view*, not the
annotation, and MapKit only reads it when creating a fresh view — so already
clustered courts kept their view and never split, no matter how far you zoomed.
Forcing a full `removeAnnotations`/`addAnnotations` on each threshold crossing
did work, but it bought a zoom-dependent split for a badge that still lied.
Both of those mechanisms are gone; don't reintroduce either without re-reading
this paragraph.

**What replaces it: nothing.** `viewFor` never sets `clusteringIdentifier`,
which is what keeps MapKit from grouping at all. `CourtMarkerView` shrank 20%
instead (above), and MapKit's own collision handling — `collisionMode =
.circle` plus `displayPriority` — thins dense areas by *hiding* overlapping
pins rather than merging them. So a visible pin always means exactly one court,
and its colour always means that court's games today. The cost is honest and
worth naming: at wide zooms most courts are simply not drawn, and there is no
badge telling you how many were dropped.

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

**`containerHeight` is the usable height, not the full one.** The same
`onGeometryChange` also reads `safeAreaInsets.bottom` into `tabBarInset` — both
in one `SheetMetrics` value, so neither lags a frame behind the other — and
subtracts it. This is load-bearing and easy to undo: `MapView` calls
`.ignoresSafeArea()`, which makes the whole `ZStack` full-height, so without the
subtraction the sheet is sized and positioned against a screen taller than the
one the user can reach and its last rows render underneath the tab bar.

`SheetMetrics` lives at file scope and is explicitly `nonisolated` because
`onGeometryChange` needs a `Sendable` value — nested in the view, or left to the
module's default main-actor isolation, its `Equatable` conformance is
actor-isolated and won't compile.

**The sheet's content stops above the tab bar; its surface does not.** The
content frame stays `sheetHeight` and is lifted by `.padding(.bottom,
tabBarInset)`, while the background is drawn `sheetHeight + tabBarInset` tall
and top-anchored. The tab bar floats with transparent margins around it, so a
sheet that ended where its content does would show a band of map between the
two.

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
the tab bar and the home indicator. `mapOverlay` insets itself by 8pt at the top
(the old `floatingHeaderHeight` environment key is gone along with the header
that published it) and by `max(0, sheetHeight - sheetOffset) + tabBarInset` at
the bottom, so the chrome stays clear of both the sheet at any detent and the
tab bar the sheet sits on. The trailing
`Spacer` in that `VStack` is load-bearing: it holds the stack at full height so
the row stays pinned to the top of a bottom-aligned `ZStack`.

The recenter button is the **only map control left** — see the zoom-stack note
above. The profile button sits on its own row above the filter chips, in
`ProfileButton`'s `glass` style so it matches the recenter control; moving the
tabs to the bottom freed the whole top of the map, so there is no longer a
reason to crowd three controls into one line.

`courtToSelect` is a `Court?` binding the shell writes when a Home hot-court row
is tapped. `MapTab` consumes it in `.onChange`, clears it so the same court can
be sent twice, and routes it through the same `select(_:recenter:)` a list row
uses rather than reaching into the sheet's state machine.

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

The card and the row draw the same badges from the same place on purpose:
before that, tapping a court to learn more about it showed you *less* than the
row you tapped it from. `CourtBadges` is the shared view and the **only**
definition of what those chips say — `CourtRow` carried a private duplicate
until 2026-08-21 that had already drifted from it. Its "Restricted" chip is the
odd one out, outlined in red rather than filled, because every other label says
what a court *has* while that one says you may not get on it.

**The row may show fewer of them than the card, and only ever fewer.** Since
2026-08-22 the badges sit beside the court's name rather than on their own line
(see "`CourtRow` — one height for every court" below), so a long name and a
well-equipped court can't both fit. `CourtBadges` takes an optional `limit` and
`CourtRow` walks a `ViewThatFits` ladder — all badges, then 2, then 1, then
none — picking the widest arrangement that fits. The card never passes a limit.
The old invariant still holds in the direction that mattered: the card is never
the *poorer* of the two.

`amenities(for:limit:)` is where the narrowing lives, and it has one rule worth
knowing before touching it: **a caution is never the badge that gets dropped.**
"Restricted" is emitted last for display, so a plain `prefix` would shed exactly
the chip a player most needs. Cautions are kept first and the leftover slots
filled with features, then re-emitted in display order. `CourtBadgesTests` pins
this.

## `CourtRow` — one height for every court

**Every row in the nearby list is exactly as tall as every other**, and that is
a constraint the layout is built around rather than a happy accident. Badges
used to sit on their own line under the metadata, so a court with amenities was
a full line taller than one without and the list scrolled in uneven jumps.

Three things together produce the uniform height, and removing any one of them
brings the variance back:

1. **Badges moved beside the name**, collapsing every row to two lines.
2. **The name is `lineLimit(1)`.** Wrapping is the other way a row grows.
3. **`badgeLineHeight` floors the name line.** A court with *no* badges would
   otherwise be a couple of points shorter than one with them, because a badge
   capsule (11pt text + 4pt padding each side) is slightly taller than a 16pt
   name. It's a `@ScaledMetric(relativeTo: .caption2)` rather than a literal 21
   because the badges scale with Dynamic Type — a fixed floor stops matching the
   moment the reader leaves the default text size, which is exactly when uneven
   rows read worst. `.caption2` is the style `Typography.swift` maps 11pt onto,
   so the floor tracks the badge's own curve instead of guessing at one.

The width tradeoff that falls out of this is handled by the `ViewThatFits`
ladder described under the detail card above: **badges are shed, the name is
not.** A badge is a fact you can still get by tapping through; the name is how
you know which court the row is. "George Watts Playground" reads in full with
one badge rather than truncating to "George Watts Playgro…" with two.

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
- `containerHeight` must stay net of `tabBarInset`. The map ignores the safe
  area, so the `ZStack` is full-height and nothing else subtracts the tab bar
  for you.
- Distances are computed on `rebuild()`, not during scroll. The radius comes
  from the profile's `preferredRadius`, via `preferredRadiusMiles`.
- The initial region, list distances, and the recenter target all read
  `FindAMatchViewModel.homeLocation`, which forwards to
  `LocationService.homeLocation`. Keep the single anchor.
- **`viewFor` never sets `clusteringIdentifier`.** That is the whole mechanism
  keeping the map unclustered — one visible pin is always exactly one court.
  Setting it reintroduces numbered group discs and the count-vs-colour
  ambiguity they carried; see "There is no clustering" before you do.
- A pin's colour comes from `CourtHeat`, never from `hooprOrange`/
  `hooprDarkOrange` directly, and never changes on selection.
  `updateUIView`'s restyle loop must keep re-running `configureAsCourt` over
  the on-screen annotations — a loop that skips it silently stops recolouring
  pins the moment counts change without an annotation being added or removed.

## See also

- `UI_SHELL.md` — why this tab stays mounted while the other two don't.
- `COURT_DATASET.md` — where the annotations' data comes from.
- `DATA_MODEL.md` — `Court` fields, and the `displayName` derivation every
  court label on this screen goes through.
- `ARCHITECTURE.md` — `FindAMatchViewModel`'s dependencies and the
  cross-collection joins, including `gameCountsByCourt`.
- `PRODUCT_OVERVIEW.md` — the heat map described in product terms.
