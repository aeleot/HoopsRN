# Hoopr — Full Project Context Summary

**Generated:** 2026-07-24 (Updated: 2026-07-24)
**Platform:** iOS (SwiftUI + UIKit interop via MapKit)
**Min Target:** iOS 17.0+
**Architecture:** MVVM with @StateObject/@EnvironmentObject for state propagation
**Persistence:** SwiftData (scaffolded), JSON file-based court cache on disk
**External Data:** OpenStreetMap Overpass API for basketball court discovery
**Build System:** Xcode project (no SPM dependencies, no CocoaPods — pure Apple frameworks)

---

## Project Overview

Hoopr is a basketball court finder iOS app. The current codebase is a **Phase 0 proof-of-concept** that displays nearby basketball courts on an interactive MapKit map, with custom top navigation and three primary tabs (Court Map, Local Games, Find Match) plus a separate Profile icon in the header. Courts are fetched live from the Overpass API (OpenStreetMap), cached locally to disk, and displayed as orange basketball markers. The app was originally spec'd for Google Maps but was implemented with Apple MapKit instead.

---

## Directory Structure

```
hoopr/
├── hooprApp.swift              # App entry point
├── ContentView.swift           # Original Xcode template view (unused in main flow)
├── MainTabView.swift           # Root view — custom header nav + three main tabs
├── Item.swift                  # SwiftData model (Xcode template, unused by app logic)
├── Theme.swift                 # Brand color definitions
├── Models/
│   └── CourtModel.swift        # Court data model
├── Managers/
│   ├── LocationManager.swift   # CLLocationManager wrapper
│   ├── CourtSearchService.swift # Overpass API client + search orchestration
│   └── CourtCache.swift        # Disk-based court cache with bounding box logic
├── Views/
│   └── MapView.swift           # UIViewRepresentable MapKit wrapper
├── Tabs/
│   ├── FindAMatchTab.swift     # Map tab with court markers and controls
│   ├── LocalGamesTab.swift     # Placeholder tab
│   ├── ProfileTab.swift        # Placeholder tab
│   └── FindMatchTab.swift      # Placeholder tab (new)
├── Resources/
│   ├── courts.json             # Bundled fallback court data
│   └── courts_updated.json     # Additional bundled court data
├── Assets.xcassets/            # Asset catalog (AccentColor, AppIcon — both empty)
hooprTests/
│   └── hooprTests.swift        # Unit test scaffold (empty)
hooprUITests/
│   ├── hooprUITests.swift      # UI test scaffold (empty)
│   └── hooprUITestsLaunchTests.swift # Launch screenshot test scaffold
HoopRN_POC_Build_Prompt.txt     # Original design/build specification document
```

---

## File-by-File Breakdown

### `hooprApp.swift` — App Entry Point
**Purpose:** The `@main` entry point for the SwiftUI app lifecycle.

- **`hooprApp`** (struct, conforms to `App`)
  - **`sharedModelContainer`** (computed property → `ModelContainer`): Creates a SwiftData `ModelContainer` with a `Schema` containing `Item.self`. Configured for persistent (not in-memory) storage. Fatal errors on container creation failure.
  - **`body`** (Scene): Returns a `WindowGroup` containing `MainTabView()` as the root view. Injects the `sharedModelContainer` into the environment via `.modelContainer()`.

**Note:** The SwiftData container is scaffolded from the Xcode template. `Item` is the only model in the schema and is not used by any court-related logic.

---

### `ContentView.swift` — Original Template View (Not in Main Navigation Flow)
**Purpose:** The default Xcode SwiftData template view. Not referenced by `MainTabView` — effectively dead code kept from the initial project creation.

- **`ContentView`** (struct, `View`)
  - **`modelContext`** (`@Environment`): SwiftData context for insert/delete.
  - **`items`** (`@Query`): Fetches all `Item` objects from SwiftData.
  - **`body`**: Renders a `NavigationViewWrapper` containing a `List` of items with timestamps. Each item links to a detail view showing its timestamp. Toolbar includes an `EditButton` (iOS) and an "Add Item" button.
  - **`addItem()`**: Creates a new `Item` with the current date and inserts it into the model context (animated).
  - **`deleteItems(offsets:)`**: Deletes items at the given `IndexSet` from the model context (animated).

- **`NavigationViewWrapper`** (fileprivate struct, generic `View`)
  - Platform-adaptive navigation: uses `NavigationSplitView` on macOS with a detail pane showing "Aeleot Big Boss", and renders content directly on iOS.

---

### `MainTabView.swift` — Root View (Custom Top Navigation)
**Purpose:** The actual root view of the app, featuring a custom top navigation bar (replacing standard TabView) with pill-shaped tab buttons and a top-right profile icon.

**Layout Structure:**
- **Header section (14% of screen height):** 
  - **First row:** Greeting text + profile icon button
  - **Second row:** Three pill-shaped tab buttons

- **Content area:** ZStack switching between FindAMatchTab, LocalGamesTab, FindMatchTab, or ProfileTab

- **`MainTabView`** (struct, `View`)
  - **`locationManager`** (`@StateObject → LocationManager`): Creates and owns the location manager, injected into child views via `.environmentObject()`.
  - **`selectedTab`** (`@State → Int`): Tracks the currently selected pill tab (0, 1, or 2). Does not affect the profile button state.
  - **`showProfile`** (`@State → Bool`): Separate flag for profile navigation. When `true`, shows ProfileTab and all pill tabs appear deselected (gray).

  **Greeting row:**
  - Text: "Let's go hoop **User1**." (username is bold, size 28pt)
  - Profile button: Circular `person.crop.circle.fill` icon (size 32pt), orange when active, gray otherwise
  - Padding: 24pt horizontal, 12pt bottom

  **Pill tab buttons row:**
  - Three buttons arranged horizontally with 6pt spacing
  - Each button: equal width, 9pt vertical padding, rounded rectangle (10pt radius)
  - **Tab 0:** "Court Map" with `map` icon
  - **Tab 1:** "Local Games" with `list.bullet` icon
  - **Tab 2:** "Find Match" with `figure.run` icon
  - Active tab: orange background, white text
  - Inactive tab (when `showProfile == true`): all gray with secondary text color
  - Padding: 12pt horizontal, 12pt bottom

  **Content rendering logic:**
  - If `showProfile == true`: show ProfileTab
  - Else if `selectedTab == 0`: show FindAMatchTab (with opacity control for state preservation)
  - Else if `selectedTab == 1`: show LocalGamesTab
  - Else if `selectedTab == 2`: show FindMatchTab

  **Tab button behavior:**
  - Tapping any pill tab: sets `selectedTab` to that index, sets `showProfile = false`
  - Tapping profile icon: sets `showProfile = true`

  **State of header height:** 14% of screen (increased from 12% to accommodate profile icon on greeting line)

  **Environment:** Injects `locationManager` as an environment object to all child views.

---

### `Item.swift` — SwiftData Model (Template Scaffold)
**Purpose:** A minimal SwiftData model from the Xcode template. Not used by any court or app logic.

- **`Item`** (final class, `@Model`)
  - **`timestamp`** (`Date`): The only stored property.
  - **`init(timestamp:)`**: Initializer accepting a `Date`.

---

### `Theme.swift` — Brand Color Definitions
**Purpose:** Extends `Color` with the Hoopr brand palette used throughout the app.

- **`Color.hooprOrange`**: `rgb(255, 126, 0)` — Primary accent, used for active pill tabs, profile icon when active, recenter button, map markers.
- **`Color.hooprDarkOrange`**: `rgb(230, 111, 0)` — Darker orange variant (defined but not currently used in views).
- **`Color.hooprRed`**: `rgb(185, 14, 10)` — Warning/destructive accent (defined but not currently used in views).
- **`Color.hooprLightGray`**: `rgb(245, 245, 245)` — Inactive pill tab background color.
- **`Color.hooprBorderGray`**: `rgb(232, 232, 232)` — Divider between header and content.
- **`Color.hooprSecondaryText`**: `rgb(102, 102, 102)` — Inactive tab text and secondary UI text.

---

### `Models/CourtModel.swift` — Court Data Model
**Purpose:** The core data model representing a basketball court.

- **`Court`** (struct, conforms to `Identifiable`, `Sendable`, `Codable`)
  - **`id`** (`String`): Unique identifier. For API-fetched courts, this is a rounded lat/lon string (e.g., `"35.79150,-78.78110"`). For bundled courts, it matches the same format.
  - **`name`** (`String`): Court name (from OSM tags: `name`, `official_name`, `operator`, or fallback `"Basketball Court"`).
  - **`latitude`** (`Double`): Geographic latitude.
  - **`longitude`** (`Double`): Geographic longitude.
  - **`address`** (`String`): Assembled from OSM `addr:housenumber`, `addr:street`, `addr:city` tags. Can be empty.
  - **`occupancyCount`** (`Int?`): Placeholder for future live occupancy data. Always `nil` in POC.
  - **`coordinate`** (computed → `CLLocationCoordinate2D`): Convenience accessor for MapKit compatibility.

---

### `Managers/LocationManager.swift` — Location Services
**Purpose:** Wraps `CLLocationManager` for requesting permissions and tracking the user's location.

- **`LocationManager`** (final class, conforms to `NSObject`, `ObservableObject`, `CLLocationManagerDelegate`)
  - **`userLocation`** (`@Published → CLLocationCoordinate2D?`): The user's most recent known location. `nil` until a location update arrives.
  - **`authorizationStatus`** (`@Published → CLAuthorizationStatus`): Current authorization state. Initialized to `.notDetermined`, updated from delegate.
  - **`manager`** (private `CLLocationManager`): The underlying Core Location manager.
  - **`defaultLocation`** (static): Fallback coordinates `(35.7915, -78.7811)` — Durham, NC area.
  - **`init()`**: Sets self as delegate, sets `desiredAccuracy` to `.best`, reads initial `authorizationStatus`.
  - **`requestLocationPermission()`**: Calls `requestWhenInUseAuthorization()`.
  - **`startUpdatingLocation()`**: Starts continuous location updates.
  - **`stopUpdatingLocation()`**: Stops location updates.

  **Delegate Methods (CLLocationManagerDelegate):**
  - **`locationManager(_:didUpdateLocations:)`**: Takes the last coordinate from the locations array and sets `userLocation` on the main actor.
  - **`locationManagerDidChangeAuthorization(_:)`**: Updates `authorizationStatus` on the main actor. If authorized (`.authorizedWhenInUse` or `.authorizedAlways`), automatically starts updating location.
  - **`locationManager(_:didFailWithError:)`**: Silently ignores errors — the map remains functional with the default center.

---

### `Managers/CourtSearchService.swift` — Court Search & API Client
**Purpose:** Orchestrates court discovery: checks in-memory state, disk cache, and network (Overpass API) in that order. Manages parallel grid-based fetching and fallback to bundled data.

- **`CourtSearchService`** (class, `ObservableObject`)
  - **`courts`** (`@Published → [Court]`): The current set of courts to display, sorted alphabetically by name.
  - **`isSearching`** (`@Published → Bool`): Whether a network fetch is in progress (drives the loading spinner).
  - **`lastError`** (`@Published → String?`): Error message if no courts were found.
  - **`prefetchTask`** (private `Task?`): The currently running prefetch task. Cancelled and replaced on each new fetch.
  - **`loadedBox`** (private `BoundingBox?`): The in-memory bounding box of the currently loaded court set.
  - **`cache`** (private `CourtCache`): Disk-based cache instance.
  - **`overpassEndpoints`** (private): Three Overpass API mirror URLs tried in order:
    1. `overpass-api.de`
    2. `overpass.kumi.systems`
    3. `overpass.private.coffee`
  - **Constants:**
    - `prefetchRadiusMiles = 15.0` — fetch a 15-mile radius around the visible center.
    - `milesPerLatDegree = 69.0` — conversion factor for lat/lon math.
    - `gridSize = 2` — subdivide into a 2x2 grid (4 parallel requests).

  **Methods:**
  - **`init()`**: On startup, calls `cache.loadMostRecent()`. If successful, loads those courts into memory and sets `loadedBox` so rapid startup doesn't trigger network fetches.
  
  - **`ensureCoverage(for:)`**: The main entry point, called whenever the map region changes.
    1. **In-memory check:** If `loadedBox` fully contains the visible region, returns immediately (no work).
    2. **Disk cache check:** If `cache.find(covering:)` returns a hit, loads those courts instantly and updates `loadedBox`. If the cached data is older than 7 days, also triggers a background network refresh (without showing the spinner).
    3. **Network fetch:** If no coverage exists, calls `prefetch()` with the spinner visible.

  - **`prefetch(centeredAt:showSpinner:)`** (private): Cancels any existing prefetch task. Computes a bounding box ~15 miles in each direction from center (adjusting longitude for latitude-based distortion via `cos(lat)`). Spawns an async `Task` that:
    1. Optionally shows the loading spinner.
    2. Calls `fetchCourtsInParallel(bbox:)`.
    3. Sorts results alphabetically.
    4. Saves to disk cache (if non-empty).
    5. Updates published properties on the main actor.

  - **`fetchCourtsInParallel(bbox:)`** (private async): Subdivides the bounding box into a 2x2 grid using `bbox.subdivide(gridSize:)`. Fetches each cell concurrently via `withTaskGroup`. Merges and deduplicates results by court `id`. If all API calls failed and no courts were found, falls back to `loadBundledCourts()` filtered to the bounding box.

  - **`loadBundledCourts()`** (private): Loads and decodes `courts.json` from the app bundle as `[FallbackCourt]`, then maps each to a `Court` (with `occupancyCount: nil`).

  - **`fetchCourts(bbox:)`** (private async throws): Performs a single Overpass API request for one bounding box cell.
    - Constructs an Overpass QL query searching for nodes and ways with `sport=basketball`.
    - Tries each of the three mirror endpoints in order. Uses `POST` with `application/x-www-form-urlencoded`, 15-second timeout, custom `User-Agent: "Hoopr iOS App"`.
    - On success, decodes the response on a detached task (`.userInitiated` priority).
    - Parses `OverpassElement` objects: extracts lat/lon from either direct properties or `center` (for way elements). Deduplicates by rounded coordinate string. Assembles name from `name` / `official_name` / `operator` tags (fallback: "Basketball Court"). Builds address from `addr:housenumber`, `addr:street`, `addr:city`.

  **Private Supporting Types:**
  - **`FallbackCourt`** (struct, `Decodable`): Simplified court shape matching the bundled `courts.json` format.
  - **`OverpassResponse`** (struct, `Decodable`): Top-level API response with `elements` array.
  - **`OverpassElement`** (struct, `Decodable`): An OSM node or way with `type`, `id`, optional `lat`/`lon`, optional `center`, optional `tags` dictionary.
  - **`OverpassCenter`** (struct, `Decodable`): Center point for way-type elements with `lat`/`lon`.

---

### `Managers/CourtCache.swift` — Disk-Based Court Cache
**Purpose:** Persists fetched court data to the app's Documents directory so previously loaded areas don't require network requests on subsequent visits.

- **`BoundingBox`** (struct, `Codable`, `Sendable`)
  - **Properties:** `south`, `north`, `west`, `east` (all `Double`) — geographic bounds.
  - **`contains(_ region:)`**: Returns `true` if this box fully contains an `MKCoordinateRegion` (all four edges are within or on the boundary).
  - **`subdivide(gridSize:)`**: Splits the bounding box into a `gridSize × gridSize` grid of smaller `BoundingBox` values. Used for parallel API fetching.

- **`CachedRegion`** (struct, `Codable`, `Sendable`)
  - **`box`** (`BoundingBox`): The geographic area this cache entry covers.
  - **`courts`** (`[Court]`): The courts within this region.
  - **`timestamp`** (`Date`): When this cache entry was created.

- **`CourtCache`** (final class)
  - **`fileURL`** (private): Path to `court_cache.json` in the app's Documents directory.
  - **`regions`** (private `[CachedRegion]`): In-memory array of all cached regions.
  - **`maxRegions = 10`**: Maximum number of cached regions kept (LRU by timestamp).
  - **`cacheExpirationDays = 30`**: Cached regions older than 30 days are ignored by `find()`.
  - **`init()`**: Resolves the Documents directory URL, appends `court_cache.json`, calls `load()`.

  **Methods:**
  - **`loadMostRecent()`**: Returns the most recent non-expired `CachedRegion` from disk, without filtering by bounding box. Used on app startup to load any previously cached courts instantly.
  - **`find(covering:)`**: Returns the most recent non-expired `CachedRegion` whose bounding box fully contains the given `MKCoordinateRegion`. Filters by 30-day expiration, then picks the newest by timestamp.
  - **`save(box:courts:)`**: Appends a new `CachedRegion` with the current timestamp. If the count exceeds `maxRegions`, trims to the 10 most recent. Calls `persist()`.
  - **`load()`** (private): Reads and decodes `[CachedRegion]` from `court_cache.json`. Logs via `os.Logger`. Silently handles missing file or decode failures.
  - **`persist()`** (private): Encodes the regions array as JSON and writes atomically to `fileURL`. Logs byte count.
  - **`clear()`**: Empties the in-memory array and deletes the cache file from disk. Intended for debugging/testing.

---

### `Views/MapView.swift` — MapKit UIViewRepresentable Wrapper
**Purpose:** Bridges UIKit's `MKMapView` into SwiftUI, handling annotations, user interaction, zoom/recenter triggers, and region change callbacks.

- **`RecenterTrigger`** (struct, `Equatable`)
  - **`center`** (`CLLocationCoordinate2D`): Target center for the recenter animation.
  - **`id`** (`UUID`): Unique ID so SwiftUI detects new trigger values. Equality is based solely on `id`.

- **`ZoomDirection`** (enum): `.zoomIn` or `.zoomOut`.

- **`ZoomTrigger`** (struct, `Equatable`)
  - **`direction`** (`ZoomDirection`): Which direction to zoom.
  - **`id`** (`UUID`): Unique trigger ID. Equality is based solely on `id`.

- **`AbsoluteZoomTrigger`** (struct, `Equatable`)
  - **`level`** (`Double`): Absolute zoom level (0.0 to 1.0 range). Used for slider-based zoom control.
  - **`id`** (`UUID`): Unique trigger ID.

- **`CourtAnnotation`** (final class, `NSObject`, `MKAnnotation`)
  - **`court`** (`Court`): The court this annotation represents.
  - **`coordinate`** (computed): Delegates to `court.coordinate`.
  - **`title`** (computed): Returns `court.name`.
  - **`subtitle`** (computed): Returns `court.address` or `nil` if empty.

- **`MapView`** (struct, `UIViewRepresentable`)
  - **Constants:**
    - `minDelta = 0.01` — most zoomed-in span (0.01 degrees ≈ 1 km)
    - `maxDelta = 5.0` — most zoomed-out span (5 degrees ≈ 555 km)
  
  - **Static methods for zoom/span conversion:**
    - **`zoomLevelFromSpan(_:)`**: Converts `MKCoordinateSpan` to a 0.0–1.0 zoom level using logarithmic scaling between `minDelta` and `maxDelta`.
    - **`spanFromZoomLevel(_:)`**: Converts a 0.0–1.0 zoom level back to `MKCoordinateSpan`.
  
  - **Properties:**
    - `courts: [Court]` — courts to display as annotations.
    - `initialRegion: MKCoordinateRegion` — map's starting region.
    - `recenterTrigger: Binding<RecenterTrigger?>` — set to trigger a map recenter animation.
    - `zoomTrigger: Binding<ZoomTrigger?>` — set to trigger a zoom in/out.
    - `absoluteZoomTrigger: Binding<AbsoluteZoomTrigger?>` — set to trigger an absolute zoom level change (used by slider).
    - `onRegionChange: ((MKCoordinateRegion) -> Void)?` — callback when the user pans/zooms the map.
    - `onMarkerTap: ((Court) -> Void)?` — callback when a court marker is tapped.
    - `onMarkerDeselect: (() -> Void)?` — callback when a marker is deselected.
    - `onZoomLevelChange: ((Double) -> Void)?` — callback when zoom level changes (used to sync slider).

  **UIViewRepresentable Methods:**
  - **`makeUIView(context:)`**: Creates an `MKMapView`, sets the coordinator as delegate, enables user location and compass, sets the initial region, registers `MKMarkerAnnotationView` with reuse identifier `"court"`.
  - **`updateUIView(_:context:)`**: Called on every SwiftUI state change.
    - **Annotation diffing:** Computes the diff between existing `CourtAnnotation` IDs on the map and the new `courts` array. Removes annotations no longer in the data, adds new ones — avoids full reload for smooth UX.
    - **Recenter handling:** If `recenterTrigger` has a new `id` (compared to `lastRecenterId`), animates the map to the trigger's center with a 0.05-degree span.
    - **Zoom handling:** If `zoomTrigger` has a new `id`, scales the current region's span by 0.75 (zoom in) or 1.4 (zoom out), clamped between `minDelta` and `maxDelta`.
    - **Absolute zoom handling:** If `absoluteZoomTrigger` has a new `id`, sets the map span to the exact zoom level specified.

  **`Coordinator`** (final class, `NSObject`, `MKMapViewDelegate`):
  - **`lastRecenterId`** / **`lastZoomId`** / **`lastAbsoluteZoomId`** (`UUID?`): Tracks which triggers have been processed to avoid re-executing.
  - **`debounceWorkItem`** (private `DispatchWorkItem?`): Debounce handle for region change callbacks.
  - **`mapView(_:viewFor:)`**: Returns `nil` for user location annotations. For `CourtAnnotation`, returns an `MKMarkerAnnotationView` with:
    - Tint: orange (`rgb(1.0, 0.494, 0)`)
    - Glyph: `basketball.fill` SF Symbol
    - Callout disabled (`canShowCallout = false`)
  - **`mapView(_:didSelect:)`**: On annotation selection, calls `parent.onMarkerTap` with the court.
  - **`mapView(_:didDeselect:)`**: On annotation deselection, waits 50ms then checks if map has any selected annotations. If not, calls `parent.onMarkerDeselect`.
  - **`mapView(_:regionDidChangeAnimated:)`**: Debounces region changes by 200ms, then calls `parent.onRegionChange` with the new region and `parent.onZoomLevelChange` with the new zoom level. Prevents excessive API calls while the user is scrolling.

---

### `Tabs/FindAMatchTab.swift` — Map Tab (Primary Feature)
**Purpose:** The main app screen. Displays the MapKit map with court markers and floating control buttons (zoom, recenter).

- **`FindAMatchTab`** (struct, `View`)
  - **`locationManager`** (`@EnvironmentObject`): Injected from `MainTabView`.
  - **`courtSearch`** (`@StateObject → CourtSearchService`): Owns the court search service for this tab's lifetime.
  - **`recenterTrigger`** / **`zoomTrigger`** / **`absoluteZoomTrigger`** (`@State`): Trigger values passed as bindings to `MapView`.
  - **`zoomLevel`** (`@State → Double`): Current zoom slider position (0.0–1.0). Synced with map zoom via `onZoomLevelChange` and `isDraggingSlider`.
  - **`isDraggingSlider`** (`@State → Bool`): Flag to prevent feedback loop between slider and map zoom.
  - **`selectedCourt`** (`@State → Court?`): Currently selected court for the bottom card.
  - **`initialRegion`** (private static): Centered on Durham, NC `(35.7915, -78.7811)` with 0.1-degree span.
  - **`cardHeight`** (computed): 1/3 of screen height.

  **`body`**: A `ZStack` (bottom alignment) containing:
  1. **`MapView`**: Full-screen map (ignores top safe area). Wired with:
     - `onRegionChange` → `courtSearch.ensureCoverage(for:)`
     - `onMarkerTap` → sets `selectedCourt` and animates card in
     - `onMarkerDeselect` → clears `selectedCourt` and animates card out
     - `onZoomLevelChange` → syncs slider (if not being dragged)
  
  2. **Floating control buttons** (top-right `VStack`):
     - **Loading spinner**: Visible when `courtSearch.isSearching`. White rounded rectangle with shadow.
     - **Zoom controls**: Vertical stack (plus/minus) in a white rounded rectangle with shadow.
       - Plus button: triggers `ZoomTrigger(direction: .zoomIn)`
       - Slider (rotated -90°): syncs with `zoomLevel`, blue tint. On drag start/end, sets `isDraggingSlider` flag.
       - Minus button: triggers `ZoomTrigger(direction: .zoomOut)`
     - **Recenter button**: Orange rounded rectangle with white `location.circle.fill` icon. Calls `recenterMap()` to center on Durham.

  3. **Court card** (bottom, 1/3 height): Slides up from bottom on marker tap.
     - Header: Drag handle (rounded rectangle)
     - Court info: Basketball icon + name + close button
     - Address: Secondary text below name (if present)
     - Spring animation (response: 0.3-0.35, damping: 0.85)

  **Key methods:**
  - **`recenterMap()`**: Sets `recenterTrigger` to Durham's coordinates. Simplified (no location permission check) — always defaults to Durham.
  - **`courtCard(court:)`** (ViewBuilder): Builds the bottom sheet card for a selected court.

  **State preservation:** FindAMatchTab is kept always mounted (via opacity toggle in MainTabView) to preserve `@StateObject` across tab switches.

  **`onAppear`**: Triggers initial `courtSearch.ensureCoverage(for: initialRegion)` so courts load when the tab first appears.

  **Zoom sync logic:** The slider and map zoom stay in sync via:
  - `isDraggingSlider` flag prevents feedback loop
  - Map zoom changes → `onZoomLevelChange` callback (only if not dragging slider)
  - Slider drag → `onChange(of: zoomLevel)` → `AbsoluteZoomTrigger` (only if dragging)

---

### `Tabs/LocalGamesTab.swift` — Placeholder Tab
**Purpose:** Stub tab for the future "Local Games" feature (showing nearby pickup games).

- **`LocalGamesTab`** (struct, `View`)
  - **`body`**: Full-screen white background with centered "Local Games" text (18pt bold, black). No functionality.

---

### `Tabs/FindMatchTab.swift` — Placeholder Tab (New)
**Purpose:** Stub tab for the future "Find Match" feature (game matchmaking).

- **`FindMatchTab`** (struct, `View`)
  - **`body`**: Full-screen white background with centered "Find Match" text (18pt bold, black). No functionality.

---

### `Tabs/ProfileTab.swift` — Placeholder Tab
**Purpose:** Stub tab for the future user profile feature.

- **`ProfileTab`** (struct, `View`)
  - **`body`**: Full-screen white background with centered "Profile" text (18pt bold, black). No functionality.

---

### `Resources/courts.json` — Bundled Fallback Court Data
**Purpose:** Static JSON file containing basketball courts in the Durham/Cary, NC area. Used as a fallback when all Overpass API endpoints fail.

**Format:** Array of objects with fields: `id` (lat/lon string), `name`, `latitude`, `longitude`, `address`.

---

### `Assets.xcassets/` — Asset Catalog
- **AccentColor.colorset:** Empty (no custom accent color configured).
- **AppIcon.appiconset:** Empty (no app icon set).
- **Contents.json:** Standard Xcode asset catalog root with `"author": "xcode"`.

---

### `hooprTests/hooprTests.swift` — Unit Test Scaffold
**Purpose:** Default Xcode test file. Contains empty `testExample()` and `testPerformanceExample()` methods. No actual tests written.

---

### `hooprUITests/hooprUITests.swift` — UI Test Scaffold
**Purpose:** Default Xcode UI test file. Contains a `testExample()` that launches the app (no assertions) and a `testLaunchPerformance()` that measures app launch time.

---

### `hooprUITests/hooprUITestsLaunchTests.swift` — Launch Screenshot Test
**Purpose:** Captures a screenshot on app launch for each UI configuration. Runs for each target app configuration (`runsForEachTargetApplicationUIConfiguration = true`).

---

### `HoopRN_POC_Build_Prompt.txt` — Original Build Specification
**Purpose:** The design document / prompt used to build the Phase 0 POC. Specifies:
- Three-tab navigation with orange/red/black/white color scheme
- Google Maps integration (actual implementation uses MapKit instead)
- 5 hardcoded demo courts (actual implementation uses Overpass API + bundled courts)
- Location permission handling
- Recenter FAB button
- MVVM architecture
- Detailed UI specs (colors, typography, spacing, shadows)
- Phase 1 roadmap: Firestore, real-time occupancy, court detail sheets, game queue

**Deviations from spec in actual implementation:**
- MapKit used instead of Google Maps (no external dependencies)
- Overpass API used for live court data instead of hardcoded courts
- Disk-based JSON caching added (not in spec)
- Parallel grid-based fetching with multiple API mirrors added
- Bundled fallback courts in Durham/Cary, NC instead of San Francisco
- Custom top navigation (pill tabs) instead of standard bottom TabView

---

## Court Data Flow

### Overview
Hoopr uses a **three-tier loading strategy** to minimize API calls and provide instant court display:

```
Tier 1: In-Memory Cache
  └─ Fastest. Persists during current app session.
  └─ Tracks bounding box to avoid redundant network calls.

Tier 2: Disk Cache (Documents folder)
  └─ Medium. Persists across app launches.
  └─ Returns instant results from previous sessions.
  └─ Auto-refreshes in background if data > 7 days old.

Tier 3: Network (Overpass API)
  └─ Slowest. Live OpenStreetMap data.
  └─ Uses 3 mirrors for redundancy.
  └─ Parallel grid-based fetching (4 concurrent requests).

Fallback: Bundled courts.json
  └─ Ensures app remains functional if all APIs fail.
```

### Detailed Data Flow

**1. App Launch**
- `CourtSearchService.init()` calls `cache.loadMostRecent()`
- If successful: instantly loads those courts into memory (no network call)
- If failed: map starts empty, waits for `onAppear` to trigger coverage check

**2. FindAMatchTab appears (`onAppear`)**
- Calls `courtSearch.ensureCoverage(for: initialRegion)` (centered on Durham, NC)
- CourtSearchService checks three tiers:
  1. **In-memory hit?** If `loadedBox` contains the region → return (no work)
  2. **Disk cache hit?** If a cached region covers the map area → load instantly, optionally refresh if stale
  3. **Network miss** → fetch from Overpass API

**3. User pans/zooms map**
- `MapView.regionDidChangeAnimated()` fires
- Debounce timer (200ms) prevents rapid-fire calls
- Calls `courtSearch.ensureCoverage(for: newRegion)`
- Repeats tiers 1–3 above for new region

**4. Network fetch (Tier 3 detailed)**

   a. **Compute fetch area:**
   - Create 15-mile radius bounding box around visible region center
   - Adjust longitude for latitude-based distortion (using `cos(lat)`)

   b. **Parallel grid fetch:**
   - Subdivide bounding box into 2×2 grid (4 cells)
   - Launch 4 concurrent network requests via `withTaskGroup`
   - Each request tries 3 Overpass API mirrors in order:
     1. `overpass-api.de/api/interpreter`
     2. `overpass.kumi.systems/api/interpreter`
     3. `overpass.private.coffee/api/interpreter`
   - Query: `node["sport"="basketball"]` OR `way["sport"="basketball"]`
   - Response format: JSON with `elements` array (nodes and ways)

   c. **Parse & merge:**
   - Extract lat/lon from each element (direct or `center` field)
   - Round to 5 decimals to create stable court ID (e.g., `"35.79150,-78.78110"`)
   - Deduplicate by ID across all 4 cells
   - Extract name from tags: `name` → `official_name` → `operator` → fallback to "Basketball Court"
   - Build address from: `addr:housenumber` + `addr:street` + `addr:city`

   d. **Save to disk cache:**
   - Create `CachedRegion` with bounding box, courts array, and timestamp
   - Append to `~Documents/court_cache.json`
   - Keep max 10 regions (LRU: discard oldest if limit exceeded)

   e. **Update UI:**
   - Sort courts alphabetically
   - Set `@Published courts` property
   - MapView observes change → re-renders annotations
   - Diff annotations: only add/remove changed markers (no flicker)

**5. Fallback (if all APIs fail)**
- Load `courts.json` from app bundle
- Filter to the requested bounding box
- Return whatever subset was found
- If courts.json unavailable → return empty array, show "No courts found" error

**6. Cache expiration**
- Disk cache entries expire after 7 days
- When user revisits expired area, `ensureCoverage` still loads cached courts instantly
- But also triggers background refresh (without spinner) to get fresh data
- Merged results replace the stale cache entry

### Key Constants & Formulas

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `prefetchRadiusMiles` | 15.0 | Fetch area around visible region center |
| `milesPerLatDegree` | 69.0 | Convert lat/lon degrees to miles |
| `gridSize` | 2 | Create 2×2 grid for parallel fetching |
| `maxRegions` | 10 | Max cached bounding boxes on disk |
| `cacheExpirationDays` | 30 | Ignore cached regions older than this |
| `staleThresholdDays` | 7 | Trigger background refresh if cache older than this |
| `debounce` | 200ms | Delay before calling `onRegionChange` callback |
| `minDelta` | 0.01° | Most zoomed-in span (≈1 km) |
| `maxDelta` | 5.0° | Most zoomed-out span (≈555 km) |

### Zoom Level Mapping

Zoom slider (0.0–1.0) ↔ Map span (0.01°–5.0°) via logarithmic scaling:

```
zoomLevel = 1.0 - (log(delta) - log(0.01)) / (log(5.0) - log(0.01))
delta = exp(log(0.01) + (1.0 - zoomLevel) × (log(5.0) - log(0.01)))
```

- Slider at 0.0 = most zoomed out (5.0° span)
- Slider at 1.0 = most zoomed in (0.01° span)
- Slider drag synced with map via `isDraggingSlider` flag (prevents feedback loop)

---

## Navigation & State Architecture

### Tab Navigation
- **3 pill-shaped tab buttons:** Court Map (index 0), Local Games (1), Find Match (2)
- **1 profile icon button:** Top-right corner, separate from tab row
- **State machine:**
  - `selectedTab` (Int): 0, 1, or 2 (only updated by pill tabs)
  - `showProfile` (Bool): true/false (only updated by profile button)
  - **Logic:** If `showProfile == true`, show ProfileTab; else show tab at `selectedTab` index
  - **Button highlighting:** Pills only highlight if `!showProfile && selectedTab == index`

### View Lifecycle
- **FindAMatchTab** stays mounted via `.opacity()` to preserve `@StateObject(courtSearch)` across tab switches
- **LocalGamesTab**, **FindMatchTab**, **ProfileTab** conditionally rendered (recreated on each tab switch)
- **Benefit:** Court search state persists even if user navigates away and back

---

## Recent Changes (2026-07-24)

1. **Profile icon moved to top-right corner** — Added circular `person.crop.circle.fill` button to greeting row in MainTabView header. Separate navigation from tab pills.
2. **Tab renamed:** "Find a Match" → "Court Map"
3. **New tab added:** "Find Match" (replaces Profile in tab row) with `figure.run` icon
4. **Username styling:** "User1" in greeting is now bold (via Text concatenation)
5. **Recenter button simplified:** Always defaults to Durham, NC. Removed location permission check.
6. **Header height adjusted:** Increased from 12% to 14% of screen height to accommodate profile icon on greeting line
7. **New file:** FindMatchTab.swift (placeholder view)

---

## Current State / What's Missing

- **LocalGamesTab** and **FindMatchTab** and **ProfileTab** are empty placeholders.
- **No user authentication or profiles.**
- **No backend / Firestore integration** — all data is from Overpass API or bundled JSON.
- **No court detail view** — marker taps open a bottom card but no additional details.
- **No occupancy/check-in system** — `occupancyCount` is always `nil`.
- **No app icon or accent color** configured in the asset catalog.
- **No real tests** — test files are Xcode scaffolds with no assertions.
- **`ContentView.swift` and `Item.swift`** are leftover Xcode template code, not used in the active navigation flow.
- **SwiftData** is initialized but not used for any app-specific data.
