# hoopsRN — Map Layer

**Scope:** `hoopr/Views/MapView.swift`, `hoopr/Views/Tabs/MapTab.swift`,
`hoopr/Views/Tabs/CourtRow.swift`, `hoopr/Views/Tabs/CourtGameRow.swift`,
`hoopr/Views/Tabs/SheetGeometry.swift`,
`hoopr/Views/Components/CourtBadges.swift`, `hoopr/Support/CourtHeat.swift`,
`hoopr/Support/CourtSearch.swift`
**Verified:** 2026-09-24 @ f30e4b2

The map tab and its bottom sheet — the densest interaction code in the app, and
the part most likely to break subtly when edited. Read this before touching
`MapView.swift` or `MapTab.swift`. The Local Runs tab and the profile are in
`UI_SHELL.md`.

`MapTab` and `MapViewModel` were `FindAMatchTab` and `FindAMatchViewModel` until
2026-09-24 (the tab first, when the third tab stopped being a "Find Match"
placeholder and became Friends; the view model, and its tests, later). Both
names are gone from the code — an older note or commit saying "find a match"
means this.

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

`CourtAnnotation.title` is still populated, now from `Court.displayName`, but
no longer purely for VoiceOver: `configureAsCourt` (below) sets an explicit
`accessibilityLabel` that folds the run count in ("Bethesda Park, 3 runs
today"), which supersedes `title` for VoiceOver whenever it's set. `title`
persists mainly as `CourtAnnotation`'s own record of the name; nothing draws
it, and `subtitle` is gone entirely.

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

**A `countLabel` competes with the glyph for the disc**, and a court with any
runs today wins: `configureAsCourt(color:gameCount:isSelected:)` hides the
basketball glyph and shows the count instead whenever `gameCount > 0`, exact
through 9 then clamped to `"9+"` (`CourtMarkerView.countText(_:)`). This is
deliberately **not** capped at 4 to match `CourtHeat`'s ramp below — the colour
ceilings because it runs out of luma to distinguish with, but the number is a
precise datum on a different channel, and truncating it to match a limitation
of the colour would throw away the exact thing the badge exists to show. Both
branches assign both views unconditionally (`countLabel.isHidden`,
`glyph.isHidden`), because a recycled `MKAnnotationView` otherwise carries the
previous court's badge into a quiet one — the same `prepareForReuse` discipline
that clears both. **The count is the primary activity signal and the colour
reinforces it**, not the reverse: a five-stop ramp roughly 15 luma points apart
per step is not something a reader decodes into a quantity at a glance, and
there's no legend on screen to help them. Whether a court is "active"
(`gameCount > 0`) also feeds `displayPriority`/`zPriority` now — unselected but
active outranks unselected and quiet — so a busy court's pin outranks a quiet
neighbour's when MapKit's collision pass has to drop one; the disc itself
stays 27pt regardless, since collisions resolve *before* `updateUIView`'s
restyle loop runs and a pin that grew when its first run landed would keep its
enlarged footprint until the next region change. `accessibilityLabel` is set
here too — see the `title` note above.

## `CourtHeat` — the pins' heat-map colouring

Added 2026-08-21. Every pin's disc is coloured by **how many runs are still on
the board at that court today** — scheduled for today and not completed or
aged out (`Game.isVisible(at:)`), so the number on a pin, Home's "N today" and
the court card's list always agree (they didn't until 2026-09-24, when a
completed run still counted toward a pin the card then showed empty). An
all-orange scale that *starts* on the
brand orange for nothing scheduled and darkens and reddens in even steps to a
saturated reddish orange for the busiest tier.

**`CourtHeat.swift` is the rule; `Theme.swift` owns the colours** (moved there
2026-09-21). `CourtHeat` turns a game count into a tier — `tier(forGameCount:)`,
clamped at both ends — and exposes `color(forGameCount:)` and
`labelColor(forGameCount:)`, which are the `hooprHeat(tier:)` and
`hooprOnHeat(tier:)` roles for that tier. Nothing about the map's own code
decides what the colours *are*, only what count goes in; Home's hot-court dot
calls the same functions, so "how busy is this court" has one definition.

**A busy court glows** (UI revamp Phase 5, 2026-09-24). From
`CourtHeat.glowsFrom` runs today (3, the top two tiers) a halo swells out
from behind the ring and fades, every two seconds. It is `hooprCourtGlow`,
not the pin's heat colour: the busy tiers are deep reds, and a translucent
deep red over a dark ground barely showed in a render. That role carries its
own per-appearance alpha (see `Theme.swift`), which is why a halo held by a
view needs no re-add when the appearance flips.
`CourtMarkerView` animates it as a keyframe `CAAnimation` sampled from
`Motion.Glow` — the same curve Home's dot draws in SwiftUI — phased off the
clock so every glowing pin pulses together. Three details are load-bearing:
the halo is a view, not a layer, for the dynamic-colour reason above; it
reaches past the pin's `bounds` but collision is computed from `bounds`, so a
glow never costs a neighbour its place; and the animation is kept on
completion, or backgrounding the app would strip it and the pins would come
back still. A running glow is left alone on restyle rather than restarted.
Under Reduce Motion the halo holds still, read on each configure. The count
and the colour already say how busy the court is; the glow never says it alone.

**The fill and its label are one table, and the label is not `hooprOnBrand`.**
The pin's count used to be black on every tier, which is 6.62:1 on the quietest
and only **4.01:1 and 3.43:1** on tiers 3 and 4 — under the 4.5:1 a 12pt bold
label needs, on exactly the courts busy enough to matter. It is black through
tier 2 and **white from tier 3** now (5.24:1 and 6.12:1), the crossover being
where black (4.74) and white (4.43) swap places. `configureAsCourt` sets the
label colour on every call, active or not, for the same recycled-view reason it
sets the text. `ThemeContrastTests.testEveryHeatTierCarriesItsLabel` holds every
tier; `CourtHeatTests` pins where the flip is.

**Stop 0 is `hooprOrange`'s light value, hardcoded** (`EE6730`), not a
reference to the role — the palette is deliberately fixed rather than routed
through the light/dark provider, because it's a data scale read against the
muted basemap in both appearances rather than chrome that should invert.
`CourtHeatTests` pins the hex, which is what catches the two drifting apart if
the brand orange is ever retuned again. (This section said `F79331` until
2026-09-21 — the value before the 08-22 retune, left behind when the test moved
on.)

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

**Where the count comes from.** `MapViewModel.gameCountsByCourt` (see
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
// SheetGeometry.swift — file-scope, nonisolated, pulled out of MapTab entirely
enum SheetDetent: Equatable, CaseIterable { case collapsed, medium, expanded }

enum SheetState: Equatable {
    case rest(SheetDetent)
    case detail(court: Court, returningTo: SheetDetent)
}

struct SheetGeometry: Equatable {
    let containerHeight: CGFloat
    // mediumHeight, expandedHeight, sheetHeight(detent:drag:),
    // sheetOffset(detent:drag:), rubberBanded(_:), nextDetent(from:projecting:)
}
```

**Both types and the detent arithmetic moved out of `MapTab` into
`SheetGeometry.swift`, `nonisolated`, specifically so they could be tested** —
this was the densest interaction code in the app with no coverage at all until
`MapTabDetentTests`. `MapTab` keeps the gestures, the animation and the state
variable; `SheetGeometry` (a plain struct built fresh from `containerHeight`)
answers only "where does the sheet sit, given a detent and a finger position."
`SheetState.detent`/`.displayDetent`/`.selectedCourt` are computed properties on
the enum itself now, callable with no view in scope.

**Two orthogonal axes, deliberately not merged.** `SheetDetent` is how far up
the sheet sits; `SheetState` is what it's showing. `.detail` carries the detent
to fall back to, so dismissing a court restores whatever the sheet was at
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

**A court card sets its own `.medium` height** (2026-09-23,
`SheetGeometry.fittedMediumHeight` → `restingMediumHeight`). Since the map
stopped above the tab bar, a third of the container is ~215pt on an iPhone 17,
which left the card's scroll body ~112pt: the name and distance (~63pt), then
**half a run** (~72pt) — "the full details are half shown until the view is
expanded", the user's report. The card now measures its lead (header plus the
first run, or "No runs here today") and rests at handle + lead + a 12pt gap +
action row, never below a third and never above `.expanded`. Measured: a
hosted run rests at 273pt (lead 158pt), 443pt at `.accessibility3`; a court with
no runs stays at ~215pt. Every drag and rubber-band limit measures from
`restingMediumHeight`, so a taller card drags exactly like the list.

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

Everything floating over the map is **Liquid Glass**: the filter chips, the
recenter button, and the collapsed peek pill. An *active* filter chip tints the
same glass with `Color.hooprOrange` rather than swapping to an opaque fill, so it
reads as the same object lit up instead of a different one.

**Every glass surface goes through `.hooprGlass(tint:interactive:in:)`**
(`Support/Glass.swift`), never `.glassEffect` directly. `glassEffect` is iOS 26
and the app's floor is 18, so the modifier holds the one `#available` and falls
back to `.ultraThinMaterial` — translucent, because these all float over a moving
map, and an opaque fill would turn a chip into a panel. The tint rides on top of
the material so the "same object lit up" rule survives the fallback.

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

The chrome is **two rows**: a search field with the profile button inline, then
the filter chips. It was three — the profile button had a row to itself — and
folding it into the search row is what pays for the field. Note the honest
arithmetic: the new chrome is ~106pt against the old ~110pt, so this buys about
4pt. It is **not** reclaimed map, and shouldn't be described as such; what
changes is that the top row stops being decoration and becomes the screen's
primary control.

The recenter button is still the **only map control** — see the zoom-stack note
above — but it no longer shares the chip row. It floats bottom-right, just above
the sheet, because it is a frequent casual tap and the top of a large phone is
the part you cannot reach one-handed. Moving it also hands the chips back the
~60pt of width it was occupying. It hides at `.expanded` and while searching;
see **Invariants**.

The search field is `HooprSearchField` in its `glass` ground — the same
component Friends and the home-court picker use on `hooprFill`. Focusing it
raises the sheet to `.expanded` and swaps the sheet's contents for results;
**Recent** lives there as the empty state rather than as a segment.

**The matching itself is `CourtSearch.matches(_:query:limit:)`**, an in-memory
substring scan with no debounce anywhere that calls it — 214 rows resident in
memory beats a round trip on both latency and availability, and a keystroke
here costs a pass over an array rather than a network request. It searches
**both** `Court.name` and `Court.displayName`: the stored name still carries
"Basketball Court," `displayName` has stripped it, and a query can match either
spelling ("basketball" only hits the stored form; "Park #2" only hits the
stripped one), so checking one field alone silently drops real hits. Name
matches rank ahead of city matches so typing a court's own name doesn't bury it
under every other court in the same town, capped at 25 results, and a blank
query returns nothing rather than the whole dataset. Three call sites share it
rather than each rolling their own: this search field, `QueueSheet`'s court
picker (`MatchmakingViewModel.searchCourts(matching:)`), and the profile's
home-court picker — which is why it lives in `Support/` rather than as a
private helper on `MapViewModel`.

`courtToSelect` is a `Court?` binding the shell writes when a Home hot-court row
is tapped. `MapTab` consumes it in `.onChange`, clears it so the same court can
be sent twice, and routes it through the same `select(_:recenter:)` a list row
uses rather than reaching into the sheet's state machine.

## The court list: Now / Nearby / Saved

Three segments, added when the sheet's list grew a way to answer "is anyone
playing" instead of only "what's near me." **Recent isn't a fourth** — it moved
to the search field's empty state (below) when `.now` took its slot, which is
why `MapViewModel.ListTab` has exactly three cases.

- **Now** — courts with a run scheduled today, soonest tip-off first. The
  segment's whole reason to exist, and the map's answer, in list form, to the
  question the pins' heat colour and count only gesture at.
- **Nearby** — every court inside the profile's `preferredRadius`, nearest
  first. What the list used to be, unconditionally.
- **Saved** — favourites. Was `favorites`; renamed for the segment's width
  budget, not its meaning.

**`Now` renders `CourtGameRow`, not `CourtRow`.** `CourtRow` answers "what is
this court like" — hoops, surface, lights; `CourtGameRow` answers "can I play
here soon," so the tip-off time and open-slot count take the space the badges
had. It's **one row per court, not per run** — a court with three runs today is
still one place to walk to, so extra runs are summarised ("+2 more today")
rather than listed, and the row opens the same detail card every other
selection does, where the actual runs and their buttons live. This keeps the
one-place-either-tab-acts-on-a-run invariant intact: `CourtGameRow` itself
carries no Join/Leave button.

**The initial segment is chosen once, not defaulted or kept reactive.**
`chooseInitialTabIfNeeded()` opens on `.now` if it has anything the first time
`GameService` finishes loading, `.nearby` otherwise, and never touches
`selectedTab` again on its own — a segment swapping under the user's thumb the
moment somebody else books a run would be worse than opening on the "wrong"
one. It deliberately doesn't run on `onAppear`: `@Published` replays its
current (empty) value to a fresh subscriber regardless of what has actually
loaded, so an appear-time check would resolve to `.nearby` on every cold
launch — precisely the failure this segment exists to fix.

`gameCountByCourtID` (the pins' own source, see `CourtHeat` below) and
`activeCourts`/`listedCourts` are two different derivations over the same
`GameService` arrays, kept separate because they answer different questions at
different grains: the pins want a same-day count without caring which runs;
`.now` wants the actual `Game` values, sorted, to render rows and act on them.

## The court detail card

Reached from a pin tap or a list row, both through `select(_:recenter:)`.
It carries the court's `displayName`, a `city · distance` line, **today's
runs at that court, if any — with the same Join/Leave/Cancel actions the Runs
tab offers**, and finally the same `CourtBadges` the list row shows, plus two
buttons:

- **Directions** — a large secondary button (`HooprButtonStyle`), which hands the court to Maps via `MKMapItem.openInMaps`, driving
  mode. The app knows where courts are and nothing about how to get to one.
  Two constructions behind one `#available`: `MKMapItem(location:address:)` on
  iOS 26, which carries the court's street address into the Maps callout, and
  `MKMapItem(placemark:)` below it, which carries only the coordinate. **The
  route is identical either way** — the address is a label, not an input.
- **Start Run** ("Add a run" once the court has one) — a large primary button
  presenting `CreateGameSheet` for that court. One button covers both entry
  points because both converge here. See `UI_SHELL.md`.

**Runs lead the card and `CourtBadges` moved below them** — a card that opened
with amenity badges put the surface material ahead of the thing a
"find a game right now" tab actually exists to answer. `viewModel.gamesToday(at:)`
filters to `Game.isVisible(at:)`, same cutoff the `Now` segment and the pin
counts use, so a run that finished two hours ago is gone from all three rather
than sitting here with a stale Join button. Each run row's action comes from
`MapViewModel.action(for:)`, which calls straight through to
`LocalRunsViewModel.action(for:)` rather than restating the rule — the map and
the Runs tab must never offer a different button for the same run. One write
in flight at a time via `pendingGameId`, the same `GameCard`/`LocalRunsTab`
convention: the acting row shows a spinner and every other row's button goes
inert. This is the **only** place besides the Runs tab either surface performs
a roster action from — the `Now` segment's own rows carry no buttons and route
here instead. The card body scrolls and the action row below it is pinned, so
"Start Run"/"Directions" never end up below the fold behind a long list of
today's games — or behind a long court name.

**The action row is measured, and stacks at accessibility sizes** (live pass,
2026-09-25). Phase 6's `HooprButtonStyle` grows with the text size where the
old buttons were a fixed 48pt with capped labels, so at `.accessibility3`
"Directions" broke mid-word ("Dire/cti…") beside "Start Run", and the sheet's
fitted height — which had assumed a 48pt row — left "No runs here today." below
the fold. From the accessibility sizes up the buttons stack, Start Run first,
and `cardActionsMeasuredHeight` feeds `cardFittedHeight` in place of the old
constant (which remains only as the height before first layout).

**The header scrolls with the body, since 2026-09-22 (UI revamp Phase 2b).** It
used to be a fixed band above the scroll, and that only held while the name was
capped at two lines — which is what truncated it to "East En…" at
`.accessibility3`. The name now wraps in full (the `title` role, via the shared
`CourtTitle`), and a fixed header that tall exceeded the `.medium` sheet and
pushed the pinned action row below the fold. The pinned row is what's
load-bearing, so the header gives way: at the top of the scroll it reads as it
always did.

**Court names on the map fit one line and shed parts rather than wrap** (the
user's call, 2026-09-22 — the full name is one tap away and is what the Runs
tab shows). `CourtName` is the rule, used by the card header, `CourtRow`,
`CourtGameRow` and the search rows: a name that doesn't fit sheds a trailing
"Park", then its `#N` court number, and only then is cut with an ellipsis.
"Park" goes first because the number is what tells sibling courts apart
("Long Meadow Park #1" and "#3"), and only a *trailing* "Park" goes — four names
carry it mid-name ("Lake Park Trail") where it is part of the place. In
`CourtRow` the badges are still shed before the name is touched. The card's star
and close buttons are fixed 44pt targets with capped glyphs, and `CourtTitle`
drops its court glyph at every accessibility size, where the name needs the
width more — measured with the symbol's drawn width, which is about 1.56× its
font size. At `.accessibility3` "East End Park" reads "East End".
`CourtNameTests` and `CourtCardLayoutTests` pin the rule.

**Each run row reads like a run on the Runs board** — time first as the row's
rank, spots left as a number, the same HOSTING / WAITLIST / FULL badge
(`RunStatus`'s one priority ladder, drawn by `HooprBadge`) and the same
waitlist-doesn't-promote note, with a compact `HooprButtonStyle` action —
the row's action button now has the 44pt tap target it lacked. It stays a
compact row rather than a `GameCard` because every run here is at *this* court.

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
knowing before touching it: **a warning is never the badge that gets dropped.**
Each chip is an `Amenity` with a kind — *feature* (hoops, lit, surface),
*notice* ("School": a school court is normally playable after hours, so it is
an outlined chip in secondary text, not red) or *caution* ("Restricted": red
outline, you may not get on). The warning is emitted last for display, so a
plain `prefix` would shed exactly the chip a player most needs. Warnings are
kept first and the leftover slots filled with features, then re-emitted in
display order. A school court's chip is spoken with its caveat ("School court,
may be closed during school hours") and the court card adds a plain sentence
under its chips (`Court.Access.caveat`) — 32 of the 214 courts were drawing no
chip at all before, and read as ordinary public courts. `CourtBadgesTests` pins
all of this.

### The data's licence notice

The court data is derived from OpenStreetMap under the ODbL, and **the notice is
shown at the foot of every court list and in the empty state** — the dataset's
own string, `CourtService.attribution`, linked to OpenStreetMap's copyright
page. At the end of the list rather than pinned, because it must be findable
without taking the room a court row would at `.medium`. Until 2026-09-22 the
string was decoded and discarded (`gaps/ASSETS_AND_DATA.md`).

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

**Distances follow the device.** `MapViewModel.homeLocation` forwards to
`LocationService.homeLocation`, which returns the last accepted fix and falls
back to Durham (35.9940, −78.8986) until one lands or if permission is denied.
A new fix replaces the anchor only once it is `significantMove` (100m) from the
last, so GPS jitter doesn't re-sort four surfaces to say the same thing —
distances render to a tenth of a mile, so anything smaller is invisible churn.

That anchor is the one every distance in the app reads, including the Local Runs
radius filter and Home's hot list, which is what stops two screens disagreeing
about how far away the same court is. `HomeViewModel` reads it *per rebuild*
rather than capturing it at init for exactly that reason.

`recenterTarget()` still doesn't block on the permission prompt — asking and then
waiting would leave the map motionless under a finger that just tapped a button.
It moves to whatever anchor is current and the fix, if granted, arrives through
`$coordinate` a moment later. It also restarts updates when permission is already
granted, since a session that never saw an authorization *change* never triggered
the delegate.

`MapView.initialRegion` is read only in `makeUIView`, so a fix arriving after the
map exists cannot reach it that way. `initialFix` is the one-shot that does:
`MapTab` turns it into a single `RecenterTrigger` — and therefore through
`biasedNorth(_:)` — guarded so it never fires over an active selection.

**Coverage consequence:** the dataset is six Triangle cities. Now that location
is real, a user outside it sees an empty map rather than a Durham one. That is
correct behaviour exposing a data-coverage gap, not a location bug.

`MapViewModel.select(_:)` records the court as recently viewed; the
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
- The court card's `.medium` is **fitted, not a fraction** — don't hard-code a
  height budget for the card again; the ~155pt the card's comments once assumed
  went stale the moment the container shrank. If you add something to the card
  that must be seen without scrolling, put it inside the measured lead in
  `courtCard`.
- A `.detail` state never renders `.collapsed` — that is the bug `displayDetent`
  exists for. It otherwise keeps the detent it will restore to, so tapping a
  court from a full-height list doesn't shrink the sheet under the reader's
  thumb. `MapTabDetentTests` pins both halves.
- The sheet's arithmetic lives in `SheetGeometry.swift`, alongside `SheetDetent`
  and `SheetState` — all `nonisolated`. Keep it pure — that is the only reason the detent machine is testable
  at all, after a long stretch with no coverage.
- Sheet geometry derives from `containerHeight`, fed by `onGeometryChange`.
  Don't reintroduce `UIScreen.main` — it's deprecated on iOS 26.
- `containerHeight` must stay net of `tabBarInset`. The map ignores the safe
  area, so the `ZStack` is full-height and nothing else subtracts the tab bar
  for you.
- **The keyboard lands in the bottom safe area, which means it feeds
  `tabBarInset` and shrinks every detent.** That is load-bearing and correct —
  the sheet lifts above the keyboard for free — so do **not** add
  `.ignoresSafeArea(.keyboard)`. Two consequences are handled deliberately: the
  chip row is dropped while the search field is focused (at ~95pt of chrome room
  two rows do not fit), and a downward fling cannot settle to `.collapsed` while
  focused, which would otherwise hide the sheet behind a live keyboard.
- The recenter button is hidden at `.expanded` and while searching. Its inset
  would place it on top of the filter chips, and at that detent the visible map
  is a sliver.
- Distances are computed on `rebuild()`, not during scroll. The radius comes
  from the profile's `preferredRadius`, via `preferredRadiusMiles`.
- The initial region, list distances, and the recenter target all read
  `MapViewModel.homeLocation`, which forwards to
  `LocationService.homeLocation`. Keep the single anchor. It follows the device
  now; `initialFix` is the one-shot that moves the map to the first fix, and it
  must never fire over an active selection.
- **`viewFor` never sets `clusteringIdentifier`.** That is the whole mechanism
  keeping the map unclustered — one visible pin is always exactly one court.
  Setting it reintroduces numbered group discs and the count-vs-colour
  ambiguity they carried; see "There is no clustering" before you do.
- A pin's colour comes from `CourtHeat`, never from `hooprOrange`/
  `hooprDarkOrange` directly, and never changes on selection.
- **A pin's count label comes from `CourtHeat.labelColor(forGameCount:)`, never
  `hooprOnBrand`.** Black is 4.01:1 and 3.43:1 on the two deepest tiers; the
  label is white from tier 3. `configureAsCourt` sets it on every call.
  `updateUIView`'s restyle loop must keep re-running `configureAsCourt` over
  the on-screen annotations — a loop that skips it silently stops recolouring
  pins the moment counts change without an annotation being added or removed.
- **A pin's *number* is the primary activity signal; the colour reinforces it.**
  `configureAsCourt` sets the count label and the glyph unconditionally on both
  branches, or a recycled view carries the previous court's badge. The disc
  stays 27pt: MapKit resolves collisions before the restyle loop runs, so a pin
  that grew when its first run was booked would keep its old footprint until the
  next region change. Activity is expressed through `displayPriority` instead,
  which *is* re-read on the next collision pass — so a busy court outranks a
  quiet neighbour when their circles collide.
- The count is exact through 9 then `9+`, deliberately outliving `CourtHeat`'s
  cap of 4. The colour ceilings because it runs out of luma; the number doesn't,
  and truncating it to match would discard what the badge exists to show.

## See also

- `UI_SHELL.md` — why this tab stays mounted while the other two don't.
- `COURT_DATASET.md` — where the annotations' data comes from.
- `DATA_MODEL.md` — `Court` fields, and the `displayName` derivation every
  court label on this screen goes through.
- `ARCHITECTURE.md` — `MapViewModel`'s dependencies and the
  cross-collection joins, including `gameCountsByCourt`.
- `PRODUCT_OVERVIEW.md` — the heat map described in product terms.
