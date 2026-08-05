# Firebase Database Implementation Plan

**Created:** 2026-07-25
**Purpose:** Step-by-step plan for migrating court data and user profiles to Firebase Firestore
**Status:** Not started

---

## Current State

- Firebase iOS SDK (Auth + Firestore) already added via SPM and configured
- `GoogleService-Info.plist` configured (project: `hoopsrn-4f1e9`)
- `FirebaseApp.configure()` called in `hooprApp.swift`
- `AuthManager` handles sign-in/sign-up via FirebaseAuth — no Firestore user profile yet
- Court data flows from: Overpass API → disk cache (`court_cache.json`) → bundled fallback (`courts.json`)
- `courts_updated.json` has enriched data with real addresses and descriptive names
- User profile values are hardcoded dummies (`"User1"`, rating 1000, etc.)

---

## Implementation Steps

### 1. Firestore Data Models

- [ ] **Create `HooprUser` model** (`Models/HooprUser.swift`)
  - Codable struct with fields: `uid`, `email`, `displayName`, `createdAt`, `favoriteCourts: [String]`, `playerBuild`, `rating`, `gamesPlayed`
  - Use `@DocumentID` from `FirebaseFirestoreSwift` for the Firestore document ID
  - Add computed `initials` property

- [ ] **Update `Court` model** (`Models/CourtModel.swift`)
  - Add `@DocumentID` support and `FirebaseFirestoreSwift` import
  - Keep existing fields (`id`, `name`, `latitude`, `longitude`, `address`, `occupancyCount`) compatible

### 2. Firestore Service Layer

- [ ] **Create `FirestoreService`** (`Managers/FirestoreService.swift`)
  - Centralized Firestore read/write access
  - Methods:
    - `fetchCourts(in region:)` — query `courts` collection by lat/lon range
    - `saveCourt(_ court:)` / `saveCourts(_ courts:)` — batch write courts
    - `createUserProfile(uid:email:displayName:)` — write new user doc on sign-up
    - `fetchUserProfile(uid:)` — read user profile document
    - `updateUserProfile(uid:fields:)` — partial update (display name, build, etc.)

### 3. Seed Local Court Data to Firestore

- [ ] **Write a one-time seed function** that reads `courts_updated.json` (enriched names + addresses) and uploads each court as a document to the `courts` collection
  - Use the court `id` (lat/lon string) as the Firestore document ID to prevent duplicates
  - Can be a temporary function in the app, a standalone Swift script, or a manual Firebase console import

- [ ] **Run the seed** against the Firebase project (`hoopsrn-4f1e9`)

- [ ] **Set Firestore security rules:**
  ```
  users/{uid}  → read/write if request.auth.uid == uid
  courts/{id}  → read if request.auth != null; write if false (admin-only seeded data)
  ```

### 4. Update `CourtSearchService` to Read from Firestore

- [ ] **Replace Overpass API as primary data source**
  - Change `fetchCourts(bbox:)` to query Firestore `courts` collection where `latitude` is between `bbox.south`/`bbox.north` AND `longitude` is between `bbox.west`/`bbox.east`

- [ ] **Keep Overpass API as optional secondary source** for discovering new courts not yet in the DB, or remove entirely

- [ ] **Keep local disk cache** (`CourtCache`) as an offline/fast-startup fallback
  - Firestore has built-in offline persistence, but the existing cache provides instant startup before Firestore initializes

- [ ] **Keep bundled `courts.json` as last-resort fallback** for when both Firestore and cache miss

### 5. Update `AuthManager` for User Profiles

- [ ] **On sign-up:** After `Auth.auth().createUser()` succeeds, create a `HooprUser` document in Firestore at `users/{uid}`

- [ ] **On sign-in:** After auth succeeds, fetch the user's Firestore profile and expose it as a published property (`@Published var hooprUser: HooprUser?`)

- [ ] **On auth state change:** When the listener fires with a signed-in user, load their Firestore profile automatically

- [ ] **On sign-out:** Clear `hooprUser` to `nil`

### 6. Update UI to Use Real Data

- [ ] **`MainTabView.swift`** — Replace `userName = "User1"` with `authManager.hooprUser?.displayName ?? "User"`

- [ ] **`ProfileTab.swift`** — Replace hardcoded dummy values:
  - `userName` → `authManager.hooprUser?.displayName`
  - `userRating` → `authManager.hooprUser?.rating`
  - `playerBuild` → `authManager.hooprUser?.playerBuild`
  - `gamesPlayed` → `authManager.hooprUser?.gamesPlayed`

- [ ] **Verify sign-out** clears profile data and returns to `LoginView`

### 7. Firestore Security Rules

- [ ] **Deploy to Firebase console:**
  ```javascript
  rules_version = '2';
  service cloud.firestore {
    match /databases/{database}/documents {
      match /users/{uid} {
        allow read, write: if request.auth.uid == uid;
      }
      match /courts/{id} {
        allow read: if request.auth != null;
        allow write: if false;
      }
    }
  }
  ```

### 8. Offline Persistence (Optional)

- [ ] **Verify Firestore offline persistence** — enabled by default in the iOS SDK; confirm courts load when offline from Firestore's local cache

- [ ] **Decide on `CourtCache` fate** — keep as a separate fast-startup layer, or rely solely on Firestore's built-in offline cache and remove it

---

## Recommended Execution Order

```
1. Data Models (HooprUser + Court update)
2. FirestoreService (read/write layer)
3. Seed court data to Firestore
4. Deploy security rules
5. Wire CourtSearchService to Firestore
6. Wire AuthManager to Firestore user profiles
7. Update UI (MainTabView + ProfileTab)
8. Offline persistence decision
```

---

## Firestore Collection Schema

### `courts/{id}`

| Field           | Type     | Example                          |
|-----------------|----------|----------------------------------|
| `id`            | string   | `"35.79150,-78.78110"`           |
| `name`          | string   | `"Halifax Park Outdoor Court"`   |
| `latitude`      | number   | `35.7937171`                     |
| `longitude`     | number   | `-78.6384228`                    |
| `address`       | string   | `"Foxgate Drive, Raleigh, NC"`   |
| `occupancyCount`| number?  | `null`                           |

### `users/{uid}`

| Field           | Type     | Example                  |
|-----------------|----------|--------------------------|
| `uid`           | string   | `"firebase-uid-string"`  |
| `email`         | string   | `"user@example.com"`     |
| `displayName`   | string   | `"John Doe"`             |
| `createdAt`     | timestamp| `2026-07-25T12:00:00Z`   |
| `favoriteCourts`| [string] | `["35.79150,-78.78110"]` |
| `playerBuild`   | string   | `"Slasher"`              |
| `rating`        | number   | `1000`                   |
| `gamesPlayed`   | number   | `0`                      |

---

## Files to Create

- `Models/HooprUser.swift`
- `Managers/FirestoreService.swift`

## Files to Modify

- `Models/CourtModel.swift` — add Firestore decoding support
- `Managers/CourtSearchService.swift` — swap Overpass API for Firestore queries
- `Managers/AuthManager.swift` — add Firestore user profile on sign-up/sign-in
- `MainTabView.swift` — use dynamic username from Firestore
- `Tabs/ProfileTab.swift` — use real user profile data from Firestore
