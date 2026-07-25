# Hoopr — Full Project Context Summary

**Generated:** 2026-07-24
**Platform:** iOS (SwiftUI + UIKit interop via MapKit)
**Min Target:** iOS 17.0+
**Architecture:** MVVM with @StateObject/@EnvironmentObject for state propagation
**Persistence:** SwiftData (scaffolded), JSON file-based court cache on disk
**External Data:** OpenStreetMap Overpass API for basketball court discovery
**Build System:** Xcode project (no SPM dependencies, no CocoaPods — pure Apple frameworks)

---

## Project Overview

Hoopr is a basketball court finder iOS app. The current codebase is a **Phase 0 proof-of-concept** that displays nearby basketball courts on an interactive MapKit map, with three-tab navigation (Find a Match, Local Games, Profile). Courts are fetched live from the Overpass API (OpenStreetMap), cached locally to disk, and displayed as orange basketball markers. The app was originally spec'd for Google Maps but was implemented with Apple MapKit instead.

---

## Directory Structure

```
hoopr/
├── hooprApp.swift              # App entry point
├── ContentView.swift           # Original Xcode template view (unused in main flow)
├── MainTabView.swift           # Root view — three-tab TabView
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
│   └── ProfileTab.swift        # Placeholder tab
├── Resources/
│   └── courts.json             # Bundled fallback court data (10 courts in Cary, NC)
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

### `MainTabView.swift` — Root View (Tab Navigation)
**Purpose:** The actual root view of the app, containing a three-tab `TabView`.

- **`MainTabView`** (struct, `View`)
  - **`locationManager`** (`@StateObject → LocationManager`): Creates and owns the location manager, injected into child views via `.environmentObject()`.
  - **`selectedTab`** (`@State → Int`): Tracks the currently selected tab (0, 1, or 2).
  - **`init()`**: Configures `UITabBarAppearance` on iOS:
    - Opaque white background with light gray (#E8E8E8) shadow/border.
    - Inactive tab icons/labels: black at 60% opacity, 13pt semibold font.
    - Applied to both `standardAppearance` and `scrollEdgeAppearance`.
  - **`body`**: `TabView` with a custom `Binding` that wraps `selectedTab` — the setter calls `withAnimation(nil)` to disable tab-switch animation. Contains three tabs:
    - **Tab 0:** `FindAMatchTab()` — "Find a Match" with map icon
    - **Tab 1:** `LocalGamesTab()` — "Local Games" with list.bullet icon
    - **Tab 2:** `ProfileTab()` — "Profile" with person.circle icon
  - Tint color: `Color.hooprOrange`.
  - Injects `locationManager` as an environment object to all child views.

---

### `Item.swift` — SwiftData Model (Template Scaffold)
**Purpose:** A minimal SwiftData model from the Xcode template. Not used by any court or app logic.

- **`Item`** (final class, `@Model`)
  - **`timestamp`** (`Date`): The only stored property.
  - **`init(timestamp:)`**: Initializer accepting a `Date`.

---

### `Theme.swift` — Brand Color Definitions
**Purpose:** Extends `Color` with the Hoopr brand palette used throughout the app.

- **`Color.hooprOrange`**: `rgb(255, 126, 0)` — Primary accent, used for active tab tint, recenter button, map markers.
- **`Color.hooprDarkOrange`**: `rgb(230, 111, 0)` — Darker orange variant (defined but not currently used in views).
- **`Color.hooprRed`**: `rgb(185, 14, 10)` — Warning/destructive accent (defined but not currently used in views).
- **`Color.hooprLightGray`**: `rgb(245, 245, 245)` — Subtle background tint (defined but not currently used in views).
- **`Color.hooprBorderGray`**: `rgb(232, 232, 232)` — Border/divider color (defined but not currently used in views, though its UIColor equivalent is used in `MainTabView.init()`).
- **`Color.hooprSecondaryText`**: `rgb(102, 102, 102)` — Secondary text color (defined but not currently used in views).

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
  - **`defaultLocation`** (static): Fallback coordinates `(35.7915, -78.7811)` — Cary, NC area.
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
    - `prefetchRadiusMiles = 20.0` — fetch a 20-mile radius around the visible center.
    - `milesPerLatDegree = 69.0` — conversion factor for lat/lon math.
    - `gridSize = 2` — subdivide into a 2x2 grid (4 parallel requests).

  **Methods:**
  - **`ensureCoverage(for:)`**: The main entry point, called whenever the map region changes.
    1. **In-memory check:** If `loadedBox` fully contains the visible region, returns immediately (no work).
    2. **Disk cache check:** If `cache.find(covering:)` returns a hit, loads those courts instantly. If the cached data is older than 7 days, also triggers a background network refresh (without showing the spinner).
    3. **Network fetch:** If no coverage exists, calls `prefetch()` with the spinner visible.

  - **`prefetch(centeredAt:showSpinner:)`** (private): Cancels any existing prefetch task. Computes a bounding box ~20 miles in each direction from center (adjusting longitude for latitude-based distortion via `cos(lat)`). Spawns an async `Task` that:
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

- **`CourtAnnotation`** (final class, `NSObject`, `MKAnnotation`)
  - **`court`** (`Court`): The court this annotation represents.
  - **`coordinate`** (computed): Delegates to `court.coordinate`.
  - **`title`** (computed): Returns `court.name`.
  - **`subtitle`** (computed): Returns `court.address` or `nil` if empty.

- **`MapView`** (struct, `UIViewRepresentable`)
  - **Properties:**
    - `courts: [Court]` — courts to display as annotations.
    - `initialRegion: MKCoordinateRegion` — map's starting region.
    - `recenterTrigger: Binding<RecenterTrigger?>` — set to trigger a map recenter animation.
    - `zoomTrigger: Binding<ZoomTrigger?>` — set to trigger a zoom in/out.
    - `onRegionChange: ((MKCoordinateRegion) -> Void)?` — callback when the user pans/zooms the map.
    - `onMarkerTap: ((Court) -> Void)?` — callback when a court marker is tapped.

  **UIViewRepresentable Methods:**
  - **`makeUIView(context:)`**: Creates an `MKMapView`, sets the coordinator as delegate, enables user location and compass, sets the initial region, registers `MKMarkerAnnotationView` with reuse identifier `"court"`.
  - **`updateUIView(_:context:)`**: Called on every SwiftUI state change.
    - **Annotation diffing:** Computes the diff between existing `CourtAnnotation` IDs on the map and the new `courts` array. Removes annotations no longer in the data, adds new ones — avoids full reload for smooth UX.
    - **Recenter handling:** If `recenterTrigger` has a new `id` (compared to `lastRecenterId`), animates the map to the trigger's center with a 0.05-degree span.
    - **Zoom handling:** If `zoomTrigger` has a new `id`, scales the current region's span by 0.5 (zoom in) or 2.0 (zoom out), clamped between 0.005 and 60.0 degrees.

  **`Coordinator`** (final class, `NSObject`, `MKMapViewDelegate`):
  - **`lastRecenterId`** / **`lastZoomId`** (`UUID?`): Tracks which triggers have been processed to avoid re-executing.
  - **`debounceWorkItem`** (private `DispatchWorkItem?`): Debounce handle for region change callbacks.
  - **`mapView(_:viewFor:)`**: Returns `nil` for user location annotations. For `CourtAnnotation`, returns an `MKMarkerAnnotationView` with:
    - Tint: orange (`rgb(1.0, 0.494, 0)`)
    - Glyph: `basketball.fill` SF Symbol
    - Callout enabled
  - **`mapView(_:didSelect:)`**: On annotation selection, calls `parent.onMarkerTap` with the court.
  - **`mapView(_:regionDidChangeAnimated:)`**: Debounces region changes by 400ms, then calls `parent.onRegionChange` with the new region. Prevents excessive API calls while the user is scrolling.

---

### `Tabs/FindAMatchTab.swift` — Map Tab (Primary Feature)
**Purpose:** The main app screen. Displays the MapKit map with court markers and floating control buttons.

- **`FindAMatchTab`** (struct, `View`)
  - **`locationManager`** (`@EnvironmentObject`): Injected from `MainTabView`.
  - **`courtSearch`** (`@StateObject → CourtSearchService`): Owns the court search service for this tab's lifetime.
  - **`recenterTrigger`** / **`zoomTrigger`** (`@State`): Trigger values passed as bindings to `MapView`.
  - **`initialRegion`** (private static): Centered on `(35.7915, -78.7811)` (Cary, NC) with 0.1-degree span.

  **`body`**: A `ZStack` (bottom-trailing alignment) containing:
  1. **`MapView`**: Full-screen map (ignores top safe area). Wired with:
     - `onRegionChange` → `courtSearch.ensureCoverage(for:)`
     - `onMarkerTap` → prints court name and address to console
  2. **Floating control buttons** (bottom-right `VStack`, 12pt spacing, 16pt padding):
     - **Loading spinner**: Visible when `courtSearch.isSearching`. White rounded rectangle with shadow.
     - **Zoom controls**: Two-button vertical stack (plus/minus) in a white rounded rectangle with shadow. Each button triggers the corresponding `ZoomTrigger`.
     - **Recenter button**: Orange rounded rectangle with white `location.circle.fill` icon. Calls `recenterMap()`.

  - **`recenterMap()`** (private): If location authorization is `.notDetermined`, requests permission first. Otherwise, recenters on the user's location (or `defaultLocation` fallback).

  **`onAppear`**: Triggers initial `courtSearch.ensureCoverage(for: initialRegion)` so courts load when the tab first appears.

---

### `Tabs/LocalGamesTab.swift` — Placeholder Tab
**Purpose:** Stub tab for the future "Local Games" feature (showing nearby pickup games).

- **`LocalGamesTab`** (struct, `View`)
  - **`body`**: Full-screen white background with centered "Local Games" text (18pt bold, black). No functionality.

---

### `Tabs/ProfileTab.swift` — Placeholder Tab
**Purpose:** Stub tab for the future user profile feature.

- **`ProfileTab`** (struct, `View`)
  - **`body`**: Full-screen white background with centered "Profile" text (18pt bold, black). No functionality.

---

### `Resources/courts.json` — Bundled Fallback Court Data
**Purpose:** Static JSON file containing 10 basketball courts in the Cary, NC area. Used as a fallback when all Overpass API endpoints fail.

**Format:** Array of objects with fields: `id` (lat/lon string), `name`, `latitude`, `longitude`, `address`.

**Courts included:**
1. Downtown Cary Basketball Court
2. White Deer Park Courts
3. Bond Park Basketball
4. Hemlock Bluffs Courts
5. Walnut Creek Park
6. Highcroft Ridge Park
7. Carpenter Park
8. Ridgecrest Elementary Courts
9. Preston Park Basketball
10. Cary Tennis Center Courts

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
- 5 hardcoded demo courts (actual implementation uses Overpass API + 10 bundled courts)
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
- 10 bundled fallback courts in Cary, NC instead of 5 in San Francisco
- Default location is Cary, NC instead of San Francisco

---

## Data Flow Summary

```
App Launch
  └─ hooprApp creates SwiftData ModelContainer
  └─ hooprApp renders MainTabView
       └─ MainTabView creates LocationManager (@StateObject)
       └─ MainTabView injects LocationManager via .environmentObject
       └─ Tab 0 (FindAMatchTab):
            └─ Creates CourtSearchService (@StateObject)
            └─ onAppear → courtSearch.ensureCoverage(for: initialRegion)
            └─ MapView renders MKMapView
                 └─ onRegionChange (debounced 400ms) → courtSearch.ensureCoverage()
                      ├─ In-memory box covers region? → return (no work)
                      ├─ Disk cache covers region? → load cached courts, optionally refresh if >7 days
                      └─ No coverage → prefetch from Overpass API
                           ├─ Compute 20-mile bounding box around center
                           ├─ Subdivide into 2x2 grid
                           ├─ Fetch each cell in parallel (try 3 API mirrors)
                           ├─ Merge + deduplicate by coordinate ID
                           ├─ If all fail → load bundled courts.json
                           ├─ Save to disk cache
                           └─ Update @Published courts → MapView re-renders annotations
                 └─ onMarkerTap → print to console
            └─ Zoom buttons → ZoomTrigger → MapView scales region
            └─ Recenter button → requestLocationPermission or RecenterTrigger → MapView animates to center
```

---

## Key Architectural Patterns

1. **Three-tier court loading:** in-memory → disk cache → network. Minimizes API calls and provides instant loading for previously visited areas.
2. **Parallel grid fetching:** Bounding box subdivided into 4 cells fetched concurrently. Partial failures are tolerated — shows whatever courts were retrieved.
3. **Multi-mirror API resilience:** Three Overpass API endpoints tried sequentially per cell. Rate-limiting on one mirror doesn't block the app.
4. **Debounced region changes:** 400ms debounce in the MapView coordinator prevents rapid-fire API calls during scrolling.
5. **Annotation diffing:** Instead of removing/re-adding all annotations on each update, the MapView computes the diff and only adds/removes what changed.
6. **Trigger-based imperative actions:** Recenter and zoom use UUID-identified trigger structs. Setting a new trigger value causes `updateUIView` to detect the new UUID and execute the map animation exactly once.

---

## Current State / What's Missing

- **LocalGamesTab** and **ProfileTab** are empty placeholders.
- **No user authentication or profiles.**
- **No backend / Firestore integration** — all data is from Overpass API or bundled JSON.
- **No court detail view** — marker taps only print to console.
- **No occupancy/check-in system** — `occupancyCount` is always `nil`.
- **No app icon or accent color** configured in the asset catalog.
- **No real tests** — test files are Xcode scaffolds with no assertions.
- **`ContentView.swift` and `Item.swift`** are leftover Xcode template code, not used in the active navigation flow.
- **SwiftData** is initialized but not used for any app-specific data.
