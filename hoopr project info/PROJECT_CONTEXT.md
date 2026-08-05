# Hoopr — Project Context

**Updated:** 2026-08-04
**Platform:** iOS (SwiftUI + UIKit interop via MapKit)
**Min Target:** iOS 17.0+
**Architecture:** MVVM — Services owned at the app level, injected into ViewModels
**Auth:** Firebase Auth (email/password)
**Court Data:** Curated bundled dataset (`courts.json`), built offline via `tools/build_courts.py`
**Build System:** Xcode project with Firebase SPM dependency

---

## Project Overview

Hoopr is a basketball court finder and pickup-game coordinator for iOS. Users sign in with Firebase Auth, then land on an interactive MapKit map showing nearby basketball courts as orange markers. Courts are loaded instantly from a bundled dataset — no runtime API calls. Tapping a court pin slides up a detail card with the court name and address.

The app gates all content behind authentication: `RootView` checks Firebase session state and shows either a launch screen, the login/signup flow, or the main tabbed interface.

---

## Directory Structure

```
hoopr/
├── hooprApp.swift                  # @main entry point, Firebase init, service ownership
├── GoogleService-Info.plist        # Firebase project configuration
├── Models/
│   ├── Court.swift                 # Court model with access level, surface, lighting metadata
│   └── AuthenticatedUser.swift     # App-side user representation (no Firebase types leak out)
├── Services/
│   ├── AuthService.swift           # Firebase Auth wrapper — sign in/up/out, session listener
│   ├── CourtService.swift          # Loads bundled courts.json dataset on init
│   └── LocationService.swift       # CLLocationManager wrapper for user location
├── ViewModels/
│   ├── RootViewModel.swift         # Gates app between launching → login → main
│   ├── LoginViewModel.swift        # Login/signup form state, validation, error messaging
│   ├── FindAMatchViewModel.swift   # Court list from CourtService, map recenter logic
│   └── ProfileViewModel.swift      # User email display, sign-out
├── Views/
│   ├── RootView.swift              # Top-level view switching on auth state
│   ├── LoginView.swift             # Email/password login and signup form
│   ├── MainTabView.swift           # Custom header with pill tab bar + content switching
│   ├── MapView.swift               # UIViewRepresentable MKMapView with zoom slider support
│   └── Tabs/
│       ├── FindAMatchTab.swift     # Map tab — markers, zoom slider, court detail card
│       ├── FindMatchTab.swift      # Placeholder tab
│       ├── LocalGamesTab.swift     # Placeholder tab
│       └── ProfileTab.swift        # User email + sign-out button
├── Support/
│   └── Theme.swift                 # Brand color palette (hooprOrange, hooprRed, etc.)
├── Resources/
│   ├── courts.json                 # Versioned bundled court dataset (v1, Durham + Raleigh)
│   └── courts_updated.json         # Extended court dataset (135 courts, 15mi radius of Durham)
├── Assets.xcassets/                # Accent color and app icon (both empty)
hooprTests/
│   └── hooprTests.swift            # Unit test scaffold (empty)
hooprUITests/
│   ├── hooprUITests.swift          # UI test scaffold
│   └── hooprUITestsLaunchTests.swift
tools/
│   └── build_courts.py            # Offline script to regenerate courts.json from OSM data
```

---

## Architecture

### Service Layer

Three long-lived services are created as `@StateObject` in `hooprApp` and injected downward:

- **`AuthService`** — The only file that imports `FirebaseAuth`. Exposes `currentUser: AuthenticatedUser?` and `hasLoadedInitialState: Bool`. Translates Firebase errors into `AuthError` cases so no Firebase types escape into the rest of the app.

- **`CourtService`** — Loads courts from the bundled `courts.json` on init. No runtime API calls. Published `courts: [Court]` is consumed by `FindAMatchViewModel`.

- **`LocationService`** — CLLocationManager wrapper. Publishes `userLocation` and `authorizationStatus`. Used by `FindAMatchViewModel` for map recentering.

### ViewModel Layer

Each view that needs logic has a corresponding ViewModel:

- **`RootViewModel`** — Combines `currentUser` and `hasLoadedInitialState` to decide between `.launching`, `.login`, and `.main` destinations.

- **`LoginViewModel`** — Owns form fields, mode toggle (sign-in vs sign-up), busy state, and human-readable error messages for every `AuthError` case.

- **`FindAMatchViewModel`** — Subscribes to `CourtService.$courts` via Combine. Provides `recenterTarget()` which handles the location-permission-not-yet-granted edge case.

- **`ProfileViewModel`** — Subscribes to `AuthService.$currentUser` for the email display. Exposes `signOut()`.

### View Layer

- **`RootView`** — Switches between `LaunchScreen`, `LoginView`, and `MainTabView` based on `RootViewModel.destination`, with a crossfade animation.

- **`LoginView`** — Email/password form with mode toggle, field focus management, orange accent CTA, and inline error display.

- **`MainTabView`** — Custom header layout (not a system `TabView`): shows a greeting with the user's name (derived from email), a profile button, and a horizontal pill-style tab bar. Content area switches between `FindAMatchTab`, `LocalGamesTab`, `FindMatchTab`, and `ProfileTab`.

- **`MapView`** — `UIViewRepresentable` wrapping `MKMapView`. Features:
  - Annotation diffing (add/remove only what changed)
  - `RecenterTrigger` / `ZoomTrigger` / `AbsoluteZoomTrigger` — UUID-based trigger pattern for imperative map actions
  - Zoom level conversion (log-scale between 0.01° and 5.0° span)
  - `onMarkerTap` / `onMarkerDeselect` / `onZoomLevelChange` callbacks
  - Debounced region change reporting (200ms)
  - Orange basketball markers with `canShowCallout: false` (detail card handles display)

- **`FindAMatchTab`** — Main map screen with:
  - Vertical zoom slider (rotated `Slider` between +/− buttons)
  - Orange recenter button using `LocationService`
  - Bottom court detail card (slides up on pin tap, dismissible via × or deselect)
  - Court card shows basketball icon, name, and full address

---

## Court Data Model

`Court` is a rich model with fields beyond name/location:

| Field | Type | Notes |
|-------|------|-------|
| `id` | `String` | Stable UUID from build script, not coordinate-derived |
| `name` | `String` | Court name |
| `latitude` / `longitude` | `Double` | Coordinates |
| `address` | `String` | Full street address |
| `city` | `String` | City name |
| `hoops` | `Int?` | Number of hoops, if known |
| `surface` | `String?` | Court surface type |
| `isLit` | `Bool?` | Whether the court has lighting |
| `isCovered` | `Bool?` | Whether the court is covered/indoor |
| `access` | `Access` | `.public`, `.school`, or `.restricted` |
| `osmType` / `osmId` | `String?` / `Int64?` | OSM provenance for dedup in future builds |

`CourtDataset` wraps the array with `version`, `generated` date, `attribution`, and `cities`.

---

## Authentication Flow

```
App Launch
  └─ FirebaseApp.configure() via AppDelegate
  └─ AuthService adds Firebase state listener
  └─ RootViewModel waits for hasLoadedInitialState
       ├─ Session restored → destination = .main → MainTabView
       └─ No session → destination = .login → LoginView
            └─ User enters email + password
            └─ LoginViewModel.submit() → AuthService.signIn/signUp
            └─ Firebase listener fires → currentUser set → .main
```

---

## Data Flow (Map)

```
MainTabView
  └─ FindAMatchTab(courtService, locationService)
       └─ FindAMatchViewModel subscribes to courtService.$courts
       └─ MapView renders [Court] as CourtAnnotation markers
            └─ onMarkerTap → selectedCourt set → courtCard slides up
            └─ onMarkerDeselect → selectedCourt nil → card dismissed
       └─ Zoom slider ↔ absoluteZoomTrigger ↔ MapView span
       └─ Recenter button → viewModel.recenterTarget() → RecenterTrigger
```

---

## Brand Colors (Theme.swift)

| Name | RGB | Usage |
|------|-----|-------|
| `hooprOrange` | 255, 126, 0 | Primary accent, CTAs, active states, markers |
| `hooprDarkOrange` | 230, 111, 0 | Darker variant |
| `hooprRed` | 185, 14, 10 | Errors, sign-out button |
| `hooprLightGray` | 245, 245, 245 | Input field backgrounds, inactive pills |
| `hooprBorderGray` | 232, 232, 232 | Borders, dividers, card drag handle |
| `hooprSecondaryText` | 102, 102, 102 | Subtitles, secondary labels |

---

## What's Next

- **LocalGamesTab** and **FindMatchTab** are empty placeholders
- **Court detail card** has name/address only — no metadata (hoops, surface, lighting) displayed yet
- **No occupancy/check-in system** — the `Court` model has the fields but nothing populates them at runtime
- **No app icon** configured in asset catalog
- **No real tests** — test files are Xcode scaffolds
- **`courts_updated.json`** is a larger dataset (135 courts) not yet wired into `CourtService`
- **User profile** shows only email and sign-out — no display name, avatar, or preferences
