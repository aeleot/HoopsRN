# User Stats Card Implementation Plan

## Overview

This plan outlines all changes required to add a user stats card to the Hoopr home page. The card will display completed games, participation streak, and last active date. Currently, the app has no completion mechanism or historical tracking—this plan addresses both.

---

## 1. Justification

**Problem:** The HomeTab and HomeViewModel explicitly avoid showing stats because "nothing records that a run happened yet." Both game listeners are windowed to the future only.

**Value:** 
- Increases user retention by surfacing engagement metrics
- Provides credibility (shows the user is an active player)
- Foundation for future features (leaderboards, achievements, matchmaking by experience)

---

## 2. Scope

### In Scope
- Tracking game completion (fields on Game model)
- Calculating user stats (games played, streak, last active date)
- Displaying stats in a minimal card on Home tab
- Firestore rules and indexes for completion tracking
- Service and ViewModel logic to publish stats

### Out of Scope
- UI for marking a game complete (admin/host endpoint separate)
- Win/loss tracking (requires additional game state)
- Leaderboards or competitive rankings
- Historical data backfill for existing games

---

## 3. Data Model Changes

### Game Model

Add one optional field to track completion:

```swift
@Field(name: "completedAt") var completedAt: Timestamp?
```

**Semantics:**
- `completedAt`: Timestamp when the game was marked complete. When non-nil, `status` must equal `.completed`.

There's no way to record who won, so completion carries no outcome data — it
means "the player attended," full stop. No `winningTeamSize` or other
win/loss metadata is stored.

**Status Values:** Add a new `.completed` case to `Game.Status` enum.

### UserProfile Model

Add three optional fields to denormalize stats (computed once per game completion, not on-the-fly):

```swift
@Field(name: "completedGameCount") var completedGameCount: Int?
@Field(name: "participationStreak") var participationStreak: Int?
@Field(name: "lastCompletedAt") var lastCompletedAt: Timestamp?
```

**Semantics:**
- `completedGameCount`: Total games the user has completed (as player or host).
- `participationStreak`: Consecutive weeks with at least one completed game. Resets to 0 if a week passes with no new completions. Default 0 for new users.
- `lastCompletedAt`: Timestamp of the user's most recent game completion.

**Why denormalize?** Fetching the user's entire game history every time they open Home would be expensive. Denormalization keeps the data consistent across devices and enables efficient publishing from ViewModel.

---

## 4. Firestore Schema & Security

### Collection Structure

**games/** (existing)
- New fields: `completedAt`, `status: "completed"`
- New composite index (see below)

**users/** (existing UserProfile documents)
- New fields: `completedGameCount`, `participationStreak`, `lastCompletedAt`

### Firestore Rules: Two Separate Update Paths

**Path 1: Roster Changes (existing, unchanged)**
- Any player can join/leave/cancel a game
- Write includes `playerIds`, `waitlistIds`, `status: "queued"/"public"`

**Path 2: Game Completion (new, host-only)**
- Only the game host can mark a game complete
- Write includes `completedAt`, `status: "completed"` — attendance only, no outcome data
- Separate validation from roster changes

**Path 3: Profile Stat Updates (new, service-only)**
- Only the app backend service can update user stats
- Write includes `completedGameCount`, `participationStreak`, `lastCompletedAt`

### New Firestore Index

Add to `firestore.indexes.json`:

```json
{
  "collectionGroup": "games",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "playerIds", "arrayConfig": "CONTAINS" },
    { "fieldPath": "status", "order": "ASCENDING" },
    { "fieldPath": "completedAt", "order": "DESCENDING" }
  ]
}
```

This enables efficient queries like: "Find all games where the user participated, status is completed, ordered by most recent."

---

## 5. Service Layer Changes

### GameService

**Add a third listener for completed games:**

```swift
@Published private(set) var completedGames: [Game] = []

// In init or setup:
// Listen to games where status == "completed", ordered by completedAt DESC, limit to last 30 days
```

This listener is independent of `queuedGames` and `publicGames`. It fetches only games the current user participated in (where `playerIds` contains their ID) with status "completed".

**Rationale:** Separates concerns—queued/public listeners show what's coming; completed listener shows what happened. Easy to test, easy to extend (e.g., add filtering by time range).

### UserProfileService

**Add a stats-calculation method:**

```swift
/// Recalculates participation stats from the user's completed games and writes back to profile.
func refreshStats(for userId: String, using completedGames: [Game]) async throws {
    let count = completedGames.count
    let streak = Self.calculateStreak(from: completedGames)
    let lastDate = completedGames.first?.completedAt
    
    try await db.collection("users").document(userId).updateData([
        "completedGameCount": count,
        "participationStreak": streak,
        "lastCompletedAt": lastDate
    ])
}

/// Pure function for testability: given a list of completed games (assumed sorted by completedAt DESC),
/// calculate the current participation streak (consecutive weeks with at least one game).
nonisolated static func calculateStreak(from games: [Game]) -> Int {
    // Implementation: group games by ISO week, count consecutive recent weeks
    // Resets to 0 if current week has no games and it's been >1 week since the last game
}
```

**Integration Point:** GameService or a separate stats-sync timer triggers `refreshStats()` after the completed-games listener fires.

---

## 6. ViewModel Changes

### HomeViewModel

Add properties to store and publish stats:

```swift
@Published private(set) var completedGameCount = 0
@Published private(set) var participationStreak = 0
@Published private(set) var lastCompletedText = "—"  // "Today", "Yesterday", "Completed", or "—"

// Computed property for conditional visibility:
var hasStats: Bool { completedGameCount > 0 }
```

**Subscription logic:**

1. Subscribe to `userProfileService.$currentProfile`
2. When profile changes, extract `completedGameCount`, `participationStreak`, `lastCompletedAt`
3. Format `lastCompletedAt` as a relative date string (Today, Yesterday, date, or empty)
4. Publish these values

**No direct subscription to completed games array:** The ViewModel reads from the profile snapshot, which is the source of truth. This keeps concerns clean and ensures the stats card always shows what Firestore says, not a stale local cache.

---

## 7. UI Component: Stats Card

### New Component: StatsCardView

Location: `Views/Components/StatsCard.swift`

```swift
struct StatsCard: View {
    let completedCount: Int
    let participationStreak: Int
    let lastCompletedText: String
    
    var body: some View {
        HStack(spacing: 16) {
            stat(label: "Runs", value: "\(completedCount)")
            Divider()
            stat(label: "Streak", value: "\(participationStreak) wks")
            Divider()
            stat(label: "Last", value: lastCompletedText)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardChrome()
    }
    
    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .hooprFont(11, weight: .bold)
                .foregroundStyle(Color.hooprSecondaryText)
            Text(value)
                .hooprFont(15, weight: .semibold)
                .foregroundStyle(Color.hooprPrimaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

**Design Notes:**
- Text-only, reuses existing `cardChrome()` styling
- Three columns: Runs | Streak | Last
- Minimal, doesn't distract from "Next run"
- Uses existing hooprFont modifiers

### Integration into HomeTab

In HomeTab, add the stats card after the header, before "Next run":

```swift
var body: some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            header
            
            // NEW: Stats card (conditional)
            if viewModel.hasStats {
                StatsCard(
                    completedCount: viewModel.completedGameCount,
                    participationStreak: viewModel.participationStreak,
                    lastCompletedText: viewModel.lastCompletedText
                )
            }
            
            section("Next run") { ... }
            section("Hot right now") { ... }
            ...
        }
    }
}
```

**Visibility:** Only shown if `completedGameCount > 0` (no stats section for brand-new users).

---

## 8. Testing Strategy

### Unit Tests

**1. Streak Calculation (`HomeViewModelTests.swift`)**
- Pure function tests for `calculateStreak(from:)`
- Test cases: no games, single game, consecutive weeks, gap in weeks, current week

Example test:
```swift
func testStreakResetsAfterWeekWithoutGames() {
    let games = [
        // Last week (7 days ago)
        Game(id: "1", completedAt: Date(timeIntervalSinceNow: -7 * 86400), ...),
        // Two weeks ago
        Game(id: "2", completedAt: Date(timeIntervalSinceNow: -14 * 86400), ...),
    ]
    
    let streak = HomeViewModel.calculateStreak(from: games)
    XCTAssertEqual(streak, 0)  // Resets because current week has no games
}
```

**2. ViewModel Stats Publishing (`HomeViewModelTests.swift`)**
- Mock UserProfileService with a profile containing stats
- Verify ViewModel publishes stats when profile changes
- Verify `hasStats` computed property works

**3. Stats Card Rendering (`StatsCardTests.swift`)**
- Render with various stat values (0, 1, 52)
- Verify text is displayed correctly
- Verify conditional visibility (e.g., card appears only when hasStats is true)

### Integration Tests

**1. Rules Parity Test (`FirestoreRulesParityTests.swift`)**
- Verify Game model's `.completed` status matches Firestore rules
- Verify UserProfile stats fields are writable only by service account
- Verify a non-host user cannot set `completedAt`

**2. Service Integration (`GameServiceTests.swift`)**
- Mock Firestore listener for completed games
- Verify completedGames array publishes correctly
- Verify listener is independent of queuedGames/publicGames

**3. UserProfileService Stats Test (`UserProfileServiceTests.swift`)**
- Mock a set of completed games
- Call `refreshStats()`
- Verify the profile document in Firestore was updated with correct counts and streak

---

## 9. Implementation Sequence

### Phase 1: Schema & Firestore (1-2 days)
1. Add `completedAt` to Game model
2. Add `.completed` case to Game.Status enum
3. Add `completedGameCount`, `participationStreak`, `lastCompletedAt` to UserProfile model
4. Update Firestore rules with two separate update paths (roster changes vs. completion)
5. Add new composite index to `firestore.indexes.json`
6. Deploy rules and wait for index to build (~5 min)

### Phase 2: Services & Streak Logic (2-3 days)
1. Add pure `calculateStreak()` function to HomeViewModel (testable, no dependencies)
2. Write unit tests for streak logic
3. Add completed-games listener to GameService
4. Extend UserProfileService with `refreshStats()` method
5. Wire up profile refresh when completed games arrive
6. Write service integration tests

### Phase 3: ViewModel & UI (1-2 days)
1. Add stats properties to HomeViewModel
2. Subscribe to profile snapshot, publish stats
3. Write ViewModel tests
4. Create StatsCard component
5. Integrate stats card into HomeTab (conditional visibility)
6. Write UI tests

### Phase 4: Testing & Validation (1-2 days)
1. Manual testing on device (add test games to Firestore with `completedAt`)
2. Rules parity tests
3. Cross-device consistency (open on two phones, mark game complete, verify both update)
4. Edge cases (timezone boundaries, week transitions)

### Phase 5: Documentation & Polish (1 day)
1. Update context dictionary (add stats card to ARCHITECTURE.md)
2. Add comments to streak calculation
3. Document the two-path Firestore rule strategy in BUILD_AND_CONFIG.md
4. Review code for consistency with existing patterns

---

## 10. Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| **Timezone issues at week boundaries** | Use ISO 8601 week numbering (Mon–Sun) and UTC timestamps. Test at week boundaries. |
| **Profile sync lag** | Stats are written atomically to the profile; ViewModel reads from profile snapshot (not from games array). Small delay is acceptable. |
| **Firestore rules mismatch** | Write rules parity tests that enforce Game.Status.completed must match `status: "completed"` in rules. |
| **Streak calculation ambiguity** | Define exactly what "a week with a game" means: ISO week, or 7-day rolling window? Document and test edge cases. |
| **No completion data initially** | Feature ships gracefully: stats card only shows for users with `completedGameCount > 0`. New users see no card. |
| **Listeners fire out of sync** | Use profile snapshot as the authoritative source, not the games array. Profile is updated last. |

---

## 11. Future Work

These extensions are out of scope but unblocked by this plan:

1. **Completion UI** — Host-only button to mark game complete
2. **Win/Loss Tracking** — Not built here; the schema currently stores no outcome data at all. Would need its own fields on `Game`/`UserProfile` and its own rules path.
3. **Leaderboards** — Query top users by completedGameCount or participationStreak
4. **Weekly Digest** — Email or push with stats from the past week
5. **Achievements** — Badges for milestones (5 runs, 4-week streak, etc.)
6. **Multiplayer Streaks** — "You and X played together 5 times this month"

---

## 12. Documentation Debt

When this feature ships, update:

1. **context/ARCHITECTURE.md**
   - Add Stats Card section under Home tab
   - Explain three independent listeners (queued, public, completed)
   - Note the denormalization strategy

2. **context/BUILD_AND_CONFIG.md**
   - Document the two-path Firestore rule strategy
   - Explain when to add new composite indexes
   - Note that stats require a separate completion mechanism

3. **context/DATA_MODEL.md**
   - Add Game.completedAt and Game.Status.completed
   - Add UserProfile stats fields
   - Explain streak calculation

4. **Code comments**
   - Add comment to HomeViewModel.calculateStreak() explaining ISO week logic
   - Add comment to UserProfileService.refreshStats() noting this is the source of truth for stats

---

## 13. Critical Files for Implementation

Prioritized by implementation order:

1. `hoopr/Models/Game.swift` — Add completedAt, .completed status
2. `hoopr/Models/UserProfile.swift` — Add completedGameCount, participationStreak, lastCompletedAt
3. `firestore.rules` — Add two-path rule for game completion
4. `firestore.indexes.json` — Add composite index for completed games query
5. `hoopr/Services/GameService.swift` — Add completedGames listener
6. `hoopr/Services/UserProfileService.swift` — Add refreshStats() method
7. `hoopr/ViewModels/HomeViewModel.swift` — Add stats properties, streak calculation
8. `hoopr/Views/Components/StatsCard.swift` — NEW component
9. `hoopr/Views/Tabs/HomeTab.swift` — Integrate stats card
10. `hooprTests/HomeViewModelTests.swift` — Streak and stats tests
11. `hooprTests/UserProfileServiceTests.swift` — Service integration tests
12. `hooprTests/FirestoreRulesParityTests.swift` — Rules validation
13. `context/ARCHITECTURE.md` — Update Home tab section
14. `context/BUILD_AND_CONFIG.md` — Document completion strategy
15. `context/DATA_MODEL.md` — Document new fields

---

## 14. External Dependencies

**CRITICAL:** This plan assumes a separate completion mechanism already exists or will be built separately:

- **Cloud Function** that hosts call to mark a game complete, OR
- **Admin endpoint** that the app backend hits, OR
- **Host UI** in the app that only the host can see

Without this, the completed-games listener will query correctly but return an empty result set. Stats will show "Runs: 0" for all users.

**Action:** Confirm with the product/infrastructure team that a game-completion pathway exists before shipping this feature. The data model and rules are ready; the orchestration is not.

---

## Summary

This plan is production-ready and follows established patterns in the codebase:

- **Three listeners** parallel GameService's existing pattern
- **Denormalized stats** mirror how search keys are backfilled on UserProfile
- **Pure functions** allow testing without Firebase
- **Rules with separate paths** follow the discipline used for existing roster changes
- **Conditional UI visibility** is consistent with how the app handles empty states

Total estimated effort: **7–12 days** (phases 1–5, accounting for testing and deployment).
