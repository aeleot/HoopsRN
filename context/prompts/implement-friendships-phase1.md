# Implement — `friendships` backend (Plan Phase 1)

Build the `friendships` collection and everything under it, with **no UI
changes**. This is Phase 1 of `context/plans/FRIENDS.md` — backend only,
independently shippable and independently revertable, verified by hand
rather than through any screen.

**Read `context/plans/FRIENDS.md` in full before writing anything.** It is
the authoritative spec — the schema, the complete `firestore.rules` block,
every method signature, and the reasoning behind each. This prompt tells you
*how to execute* that plan correctly and in the right order; it does not
restate the design. Where anything here seems to conflict with the plan, the
plan wins — but stop and flag the conflict rather than silently picking a
side, since a conflict means one of the two documents is stale.

---

## Scope

**Build:**
- `hoopr/Models/Friendship.swift` — the model, `Status`, `Direction`,
  `FriendError`, and the helpers (`id(for:_:)`, `otherUid(than:)`,
  `direction(for:)`) — plan §5.
- `hoopr/Services/FriendService.swift` — two listeners, the merge into
  `friends`/`incomingRequests`/`outgoingRequests`, and all five writes
  (`sendRequest`, `acceptRequest`, `declineRequest`, `cancelRequest`,
  `removeFriend`) — plan §5.
- Additions to `hoopr/Models/UserProfile.swift` (`userNameLower`) and
  `hoopr/Services/UserProfileService.swift` (write `userNameLower` alongside
  `userName`; add `profiles(for:)`, `searchProfiles(matching:)`,
  `profile(uid:)`) — plan §1 and §5.
- The `friendships` `match` block appended to `firestore.rules`, and
  `userNameLower` added to the `users` update allowlist — plan §2 and §1.
- Unit tests for `Friendship` decoding, mirroring
  `hooprTests/UserProfileTests.swift` and `GameTests.swift` — see Testing
  below.

**Do not build:** `FriendsTab`, `FriendsViewModel`, any change to
`MainTabView`/`RootView`/`hooprApp.swift`, the "Player ID" profile row, or
the `LocalRunsTab` friends-here badge. Those are Phases 2–4 and depend on
this phase existing first — leave them for a separate pass. Do not touch
`games`, its rules, or `GameService` at all in this phase.

**No Cloud Functions.** If you find yourself reaching for one to solve a
consistency problem, stop — the whole point of the ordered-pair single-
document schema in plan §2 is that it doesn't need one. Re-read §2.

---

## Order of work

Follow this order — it exists to keep the app buildable and the rules
deployed together, not staggered:

1. **`Friendship.swift`** first — nothing else compiles against it until it
   exists.
2. **`UserProfile.userNameLower`** and the three new `UserProfileService`
   methods. Do this before `FriendService`, since name/ID resolution is a
   dependency of testing `FriendService` by hand later, not the reverse.
3. **`FriendService.swift`**, following `UserProfileService.swift` and
   `GameService.swift` as the pattern to imitate — see Conventions below.
   Pay specific attention to the create/accept collision handling in plan
   §2 ("A collision worth naming"): `sendRequest` must catch the
   rules-rejection case where the other person already requested *you*, and
   turn it into an accept rather than surfacing an error.
4. **Build the app** (`xcodebuild … build`) and fix everything before
   touching rules. A backend-only phase should compile clean on its own.
5. **Edit `firestore.rules`** — append the `friendships` block from plan §2
   verbatim, and add `userNameLower` to the `users` update allowlist.
   Run `firebase deploy --only firestore:rules,firestore:indexes --dry-run`
   to compile-check the rules file before touching the live project.
6. **Stop and confirm with the user before the real deploy.** Rules changes
   are live-infrastructure changes to a shared Firebase project the moment
   they're pushed — this is not a step to run unattended. State what
   you're about to deploy and wait for a go-ahead, exactly as you would
   before any other change to shared infrastructure.
7. **Deploy**, then run the manual verification in Testing below.
8. **Write the unit tests.** Last, not first — they should describe the
   code you actually wrote, and decoding tests are cheap to get right once
   the model is settled.

---

## Conventions to match exactly

This codebase has a consistent house style; deviating from it in a new
service is a bug, not a style choice. Before writing `FriendService.swift`,
re-read `hoopr/Services/UserProfileService.swift` top to bottom — it is the
closest analog and the pattern `GameService.swift` also follows. Specifically:

- `@MainActor final class FriendService: ObservableObject`. Subscribes to
  `AuthService.$currentUser` **itself** in `init()`, not driven by a view
  model — see `ARCHITECTURE.md`'s "Session-scoped listeners" section for why.
- One `ListenerSupervisor(subject: "friends")`, with a **weak** capture in
  `onRetry` (the service owns the supervisor; a strong capture is a cycle).
  Both listener keys (`uidA`, `uidB`) report `recordFailure`/`recordSuccess`
  independently, the same reason `GameService` tracks its two listeners
  separately rather than with one flag.
- `database` is `private lazy var database = Firestore.firestore()` —
  never touched before `FirebaseApp.configure()`.
- Every write is an explicit `[String: Any]` field map. **Never**
  `setData(from:)` on `Friendship` — same reason `UserProfile` never uses it:
  server timestamps must stay server-assigned.
- Reuse `FirestoreFailure.classify(_:)` in a private `mapped(_:)`, and
  `FailureText` for any sentence shared with another service's error
  mapper. Don't hand-roll a second `FirestoreErrorDomain` switch.
- Disambiguate `permission-denied` by `FailureContext.load` vs `.write`,
  matching the reasoning in `UserProfileService.message(for:whileDoing:context:)`
  — a denied read here means the rules aren't deployed (the read rule is
  `isParticipant`, which is *not* open to any signed-in user the way
  `users`'/`games`' read rules are, so word that message differently: a
  denied read on a document you *are* a participant of is a deployment
  problem; you won't get a denied read for a document you aren't a
  participant of, because `FriendService` never queries for documents it
  isn't entitled to see in the first place).
- No `DocumentSnapshot`, `NSError`, or any `FirebaseFirestore` type may
  escape `Services/`. `Friendship` and `FriendError` stay Firebase-free.
- Comments only where the *why* isn't obvious from the code — this
  codebase's existing services comment on rationale, races, and invariants,
  never on what a line does. Match that density, don't under- or over-shoot
  it.
- `sink { [weak self] … }` for every Combine subscription, never
  `assign(to:on: self)` — see `ARCHITECTURE.md`'s invariants list.

---

## Testing

**Unit** — new file, `hooprTests/FriendshipTests.swift`, following
`UserProfileTests.swift`'s shape (decode through the real
`Firestore.Decoder`, not a hand-rolled one):

| Test | Guards |
|---|---|
| decodes the full stored shape | `Timestamp` → `Date` on both date fields |
| decodes pending server timestamps | An unresolved `serverTimestamp()` sentinel reads back null without crashing |
| `Friendship.id(for:_:)` is order-independent | `id(for: "b", "a") == id(for: "a", "b")` |
| `direction(for:)` | Returns `.sent`/`.received` correctly for both `requestedBy` cases while pending, `.mutual` once accepted, regardless of which of `uidA`/`uidB` the caller is |

**Manual, two accounts** — there is no emulator in this repo (see
`GAPS.md`), so this is the real verification for the rules, not a
formality:

1. Send a request A → B. Confirm B can read the document, A can read it, and
   a third signed-in account **cannot** (permission-denied on a direct read
   attempt).
2. B accepts. Confirm the write succeeds for B and would be rejected for A
   (the requester can't accept their own request) — try it and confirm the
   rejection, don't just reason about it.
3. Decline a separate pending request. Confirm the document is gone and a
   fresh request between the same two people is createable afterward at the
   same ID.
4. Cancel an outgoing request, and separately, unfriend an accepted one.
   Both should be plain deletes, available to either participant.
5. **The collision case specifically**: have A send to B and, before B
   responds, have B send to A. Confirm the second call resolves as an
   accept (per the handling built in step 3 of "Order of work"), not a
   surfaced error.
6. Confirm `searchProfiles(matching:)` returns expected results for a
   prefix, and `profile(uid:)` returns the right document for an exact ID
   and `nil` for a nonexistent one.

---

## Definition of done

- `xcodebuild … build` succeeds.
- `firestore.rules` deployed (with the user's confirmation obtained
  beforehand) and all six manual checks above pass against the live
  project.
- New unit tests pass locally.
- Nothing outside the Scope section above was touched — in particular, no
  `MainTabView`/`RootView`/`hooprApp.swift` edits, no `games` changes, no new
  UI.
- Changes are **not committed** — leave them staged/unstaged for review,
  matching how this repo's owner has handled every commit so far in this
  effort.

## Report back

Close with:

1. **Files created/changed**, one line each.
2. **The six manual verification results**, pass/fail — not just "verified,"
   name what each one actually showed.
3. **Anything in `context/plans/FRIENDS.md` that turned out to be wrong**
   once you tried to build it — a signature that didn't quite fit, a
   collision case that behaved differently than described. Flag it plainly;
   don't silently improvise around a stale plan without saying so.
4. **Confirmation that Phases 2–4 were left untouched.**
