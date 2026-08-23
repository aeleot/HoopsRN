*Prompt: Implement Invite-Only Join via Shareable Deep Link**

**Context:** hoopsRN already has `isPublic: false` on the `Game` schema, but this currently makes a run completely undiscoverable — nothing else can reach it. The `isPublic` flag is half a feature until invites land. This task completes it by allowing a host to share a private run via URL so recipients can join.

---

### 1. Firestore Rules — Allow Direct Reads for Invites

Update `firestore.rules` to split `read` into `get` (single document by ID) and `list` (query). Anyone signed in may `get` a game by direct reference, but `list` queries stay restricted to public games or games the user is already on.

**`firestore.rules` diff — `games` collection:**

```rules
// OLD (kept for reference):
// allow read: if request.auth != null
//   && (resource.data.isPublic == true
//       || request.auth.uid in resource.data.playerIds);

// NEW:
// Deep-link invites rely on document ID unguessability.
// This is practical security, not cryptographic authorization.
// If you need verified invites later, add an inviteToken field
// and check it here instead.
allow get: if request.auth != null;

allow list: if request.auth != null
  && (resource.data.isPublic == true
      || request.auth.uid in resource.data.playerIds);
```

Leave all other rules (create, update, delete, the membership diff, derived `status`, etc.) untouched.

---

### 2. App URL Scheme & Deep Link Handling

Register `hoopsrn://` as a custom URL scheme in the Xcode project / `Info.plist`. Handle `hoopsrn://game/{gameId}` in `hooprApp.swift` via `.onOpenURL`:

- Parse the `gameId` path component.
- If `AuthService.currentUser == nil`, stash the pending `gameId` (e.g., in `RootViewModel`) and route to `LoginView`. After successful auth, automatically navigate to the invite preview for the stashed `gameId`, then clear the stash.
- If already authenticated, push the `InviteJoinView` onto the navigation stack (or present it modally over `MainTabView`).

---

### 3. Host Share Flow

On any game card or detail where `isPublic == false` and the current user is the host (`hostId == currentUser.id`), add a **Share Invite** button. It generates the string `hoopsrn://game/{gameId}` and presents `UIActivityViewController` so the host can send it via Messages, Mail, etc.

---

### 4. Recipient Join Flow

When a recipient opens the deep link, the app presents an `InviteJoinView` backed by `InviteJoinViewModel`.

**`InviteJoinViewModel.swift` — skeleton to implement:**

```swift
import Foundation
import Combine

@MainActor
final class InviteJoinViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case ready(Game, isAlreadyJoined: Bool)
        case full(Game)          // show waitlist option
        case ended               // past scheduledTime + visibilityGrace
        case notFound            // invalid or deleted gameId
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var isJoining = false
    @Published var errorMessage: String?

    private let gameId: String
    private let gameService: GameService
    private let authService: AuthService

    init(
        gameId: String,
        gameService: GameService,
        authService: AuthService
    ) {
        self.gameId = gameId
        self.gameService = gameService
        self.authService = authService
    }

    /// Fetch the game by direct document ID (the new get-rule path).
    func load() async {
        state = .loading
        errorMessage = nil

        do {
            // NEW method on GameService — see below
            let game = try await gameService.fetchGame(byId: gameId)

            let now = Date()
            guard game.isVisible(at: now) else {
                state = .ended
                return
            }

            if let uid = authService.currentUser?.id {
                let isJoined = game.playerIds.contains(uid)
                if game.status == .full && !isJoined {
                    state = .full(game)
                } else {
                    state = .ready(game, isAlreadyJoined: isJoined)
                }
            } else {
                state = .notFound   // Shouldn't happen — caller guards auth
            }
        } catch let error as GameError where error == .gameNotFound {
            state = .notFound
        } catch {
            state = .error
            errorMessage = "Couldn’t load this run. Please try again."
        }
    }

    /// Add current user to playerIds via existing GameService join path.
    func join() async {
        guard case .ready(let game, false) = state else { return }
        isJoining = true
        defer { isJoining = false }

        do {
            try await gameService.joinGame(id: gameId)
            // After success, the queuedGames listener will pick it up.
            // UI can dismiss back to LocalRunsTab.
        } catch {
            errorMessage = "Failed to join. The run may be full or no longer available."
        }
    }

    /// Add current user to queuedPlayerIds when the run is full.
    func joinWaitlist() async {
        guard case .full = state else { return }
        isJoining = true
        defer { isJoining = false }

        do {
            try await gameService.joinWaitlist(id: gameId)
        } catch {
            errorMessage = "Couldn’t join the waitlist. Please try again."
        }
    }
}
```

**`GameService` additions:**

```swift
// Add to GameService.swift

/// Direct document fetch by ID. Uses the new get-rule that allows
/// any signed-in user to read a single game document.
func fetchGame(byId id: String) async throws -> Game {
    guard currentUser != nil else { throw GameError.notSignedIn }

    let snapshot = try await database
        .collection("games")
        .document(id)
        .getDocument()

    guard let game = try? snapshot.data(as: Game.self) else {
        throw GameError.gameNotFound
    }
    return game
}
```

If `joinWaitlist(id:)` does not already exist on `GameService`, implement it as an update that adds the current user's uid to `queuedPlayerIds` using `arrayUnion`, subject to the existing Firestore rules (membership diff + maxPlayers).

---

### 5. "Private Run" Badge in Queued Games

In the `queuedGames` list (backed by the `playerIds array-contains uid` listener), any `Game` where `isPublic == false` must render a **Private** badge or label next to the court name. This is purely presentational — no model or query changes required.

---

### 6. Edge Cases

| Scenario | Behavior |
|---|---|
| Already on roster | Deep link skips preview and navigates directly to game detail. |
| Game full | Show waitlist option (add to `queuedPlayerIds`). |
| Past `scheduledTime + visibilityGrace` | Show "This run has ended" with no join button. |
| Invalid/deleted `gameId` | Show clean error state with a back button to `LocalRunsTab`. |
| Not signed in | Defer deep link until after login, then auto-navigate. |

---

### Files Expected to Change

- `firestore.rules` — split `read` into `get` + `list` as shown above.
- Xcode project / `Info.plist` — register `hoopr` URL scheme.
- `hoopr/hooprApp.swift` — incoming URL parsing + pending-link stash.
- `hoopr/Services/GameService.swift` — add `fetchGame(byId:)` and `joinWaitlist(id:)` if missing.
- `hoopr/ViewModels/InviteJoinViewModel.swift` — implement the skeleton above.
- `hoopr/Views/InviteJoinView.swift` — new view: preview screen with Join / Waitlist / Ended states.
- Host's game card/detail view — add Share Invite button gated on `isPublic == false && hostId == currentUser.id`.
- `queuedGames` list row — add "Private" badge when `isPublic == false`.

---

### Acceptance Criteria

- [ ] Host can tap **Share Invite** on a private run and send the link.
- [ ] Recipient opening `hoopsrn://game/{gameId}` sees run details and can join.
- [ ] After joining, the run appears in the recipient's `queuedGames` via the existing `playerIds array-contains uid` listener.
- [ ] Runs where `isPublic == false` are visually labeled **Private** in the queued list.
- [ ] Private runs never appear in `publicGames` discovery (list rule unchanged).
- [ ] Deep links survive app cold-start and login flows.
- [ ] Firestore emulator / parity tests updated if the rules-test harness checks rule structure.

---
