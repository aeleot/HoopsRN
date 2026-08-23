# Plan — Friends

**Status:** Phases 1–3 shipped (1–2 on 2026-08-13, 3 on 2026-08-15, branch
`map-tab`); Phases 4–5 proposed
**Drafted:** 2026-08-13 @ 5a1f834
**Touches:** `firestore.rules`, `hoopr/Models/`, `hoopr/Services/`,
`hoopr/ViewModels/`, `hoopr/Views/Tabs/`, `hoopr/Views/Profile/`,
`hoopr/Views/MainTabView.swift`, `hoopr/Views/RootView.swift`,
`hoopr/hooprApp.swift`

> `context/plans/` is not a dictionary entry and carries no `Scope`/`Verified`
> stamp. A plan describes work that hasn't happened; the dictionary describes
> code that has. When a phase below ships, fold what's true into the
> dictionary entries named in "Documentation debt" and strike it from here.

## Context

You asked whether a Friends tab is reasonable to build. Short answer: yes —
more than reasonable, it's a good next feature. Three things line up in its
favor:

1. **There's a dead tab slot waiting for it.** The tab bar already has three
   pills — Court Map / Local Runs / **Find Match** — and the third one is a
   literal placeholder: `FindMatchTab.swift` renders a centered `Text("Find
   Match")` and nothing else (confirmed by reading the file; also called out
   in `context/GAPS.md`). It's not a stub for a feature in progress, it's an
   empty slot that's already wired into navigation. You confirmed reusing it
   rather than redesigning the header or burying this in the profile screen.
2. **The hard part — mutual state written by two different people — already
   has a proven answer in this codebase.** `games` is the first (and only)
   collection more than one person writes to, and its rules solve exactly
   this problem for roster membership: each participant may only ever move
   *themselves* in a shared document, never the other person, enforced by a
   symmetric-difference check server-side, no Cloud Function required. A
   friendship is the same shape (two uids, each with limited authority over
   one shared document) with a smaller state space (one status flag instead
   of two roster arrays), so the same pattern applies directly and is
   actually simpler to write.
3. **The one genuinely open question — how do you find another person to
   friend — has a real answer given what's already true about this app.**
   `userName` is explicitly a non-unique display name today
   (`context/DATA_MODEL.md`), and the `users` read rule is already open to
   any signed-in user ("player names must be resolvable in shared contexts
   ... in later phases" — this is that later phase). So a name-prefix search
   is both sufficient and requires no new read access, just a new indexed
   field to search on.

Nothing here requires Cloud Functions (the project is on the Spark plan —
confirmed by `context/GAPS.md`, which names waitlist promotion, not this, as
"the first thing that requires the Blaze plan") and **`games`' rules and
schema are untouched.** The one place this plan does touch `games`-adjacent
UI is a read-only, client-side cross-reference — surfacing which already-
visible public runs a friend is on — covered in §4; it needs no new rule,
query, or index, and is a materially different (and much smaller) thing than
letting a friend see a *private* run they aren't on, which stays out of
scope. This is a clean, additive feature: one new collection, one repurposed
tab, one small enhancement to a list that already exists.

---

## 1. Discovery: search by name, resolve by uid

Add `userNameLower: String` to `UserProfile` — a lowercased mirror of
`userName`, written by `UserProfileService` alongside it on every create and
update (never independently edited; it's derived, not a second field a user
fills in). Search query:

```swift
db.collection("users")
  .whereField("userNameLower", isGreaterThanOrEqualTo: prefix)
  .whereField("userNameLower", isLessThan: prefix + "\u{f8ff}")
  .limit(to: 20)
```

A single-field range filter — Firestore auto-indexes it, no
`firestore.indexes.json` entry needed. No rules change for *read* (already
open); the *write* allowlist on `users` needs `userNameLower` added, per the
two-step rule.

Duplicate names are resolved by the human, not the schema: search returns a
picker of profiles, the person taps the right one, and everything downstream
(the friendship doc, the graph) keys on `uid`, never on name. A name collision
is cosmetic.

**Rejected:** open substring/fuzzy search (needs Algolia or a Cloud Function,
neither available); share-link-by-uid as the *primary* mechanism (solves "add
this exact known person," not "find someone whose first name I remember" —
worth adding later as a precision aid, not as v1's only path).

**Search by ID, alongside search by name.** Cheaper than the name path, not
harder: `users` documents are already keyed by uid, so an exact-ID lookup is
a direct `document(uid).getDocument()` — no query, no index, no rules change.
`UserProfileService` gains a third one-shot method,
`profile(uid:) async throws -> UserProfile?`, and the search bar routes to it
when the typed text looks like an ID rather than a name (length/character-set
heuristic — Firebase uids are ~28-character alphanumeric strings, display
names in practice aren't) rather than requiring a separate input mode.

This only works if a person can learn someone else's ID to type it in. Add a
read-only **"Player ID"** row to `ProfileView`'s existing card grid — same
`onEdit: nil` pattern as `Email`/`Joined` — showing the signed-in user's own
`uid` with a copy affordance, so it's something people can actually share
out-of-band (text, in person) rather than a value that only ever exists
server-side.

---

## 2. Schema: one document per pair, symmetric-authority rules

**Collection: `friendships/{uidA}_{uidB}`**, where `uidA < uidB`
(lexicographic on the raw uid strings — Firebase uids are ASCII alphanumeric,
so Swift's `<` and the rules language's `<` agree). Tying the ID to the pair,
not letting the client pick one, is what prevents A creating `A_B` while B
independently creates `B_A` for the same relationship — there is structurally
only one legal document for a given pair.

| field | type | required | mutable | notes |
|---|---|---|---|---|
| `uidA` | string | yes | no | Lexicographically first of the pair. |
| `uidB` | string | yes | no | Lexicographically second. |
| `requestedBy` | string | yes | no | Must equal `uidA` or `uidB`. Who initiated — distinct from the pair order, which is arbitrary. |
| `status` | string | yes | yes | `pending` \| `accepted` only. No `declined`/`cancelled` value — those delete the document instead, matching the "absence, never null" convention `games`/`users` already follow (there's no `cancelled` game status either; cancelling deletes). |
| `createdAt` | timestamp | yes | no | Server-assigned. |
| `updatedAt` | timestamp | yes | yes | Server-assigned, refreshed on the one legal transition. |

**The rule, by direct analogy to `games`' membership diff:** on `games`, two
different uids may each mutate one shared document, but only their own lane
of it (their own membership, never someone else's). Here the "lane" is
smaller — one status flag — so the rule is simpler: the requester spends
their entire authority at `create` time; the *only* thing the other
participant's `update` may ever do is flip `pending` → `accepted`.

```
match /friendships/{friendshipId} {
  function isSignedIn() { return request.auth != null; }
  function incoming() { return request.resource.data; }

  // The two participants, always in a fixed lexicographic order, so a given
  // pair of people can only ever be represented by one document — without
  // this, A could create `A_B` while B independently created `B_A` for the
  // same friendship, and the two copies would drift out of sync.
  function isOrderedPair() {
    return incoming().uidA < incoming().uidB;
  }

  // Ties the document ID to its own content instead of trusting the client
  // to pick a consistent one — the same role `incoming().id == gameId` plays
  // on `games`, just derived instead of client-chosen.
  function idMatchesPair() {
    return friendshipId == incoming().uidA + '_' + incoming().uidB;
  }

  function isParticipant(data) {
    return request.auth.uid == data.uidA || request.auth.uid == data.uidB;
  }

  // A friendship isn't public like `users` or `games` — only the two people
  // on it may know it exists, including while it's still a pending request.
  allow read: if isSignedIn() && isParticipant(resource.data);

  allow create: if isSignedIn()
    && isOrderedPair()
    && idMatchesPair()
    && incoming().keys().hasOnly(['uidA', 'uidB', 'requestedBy', 'status',
                                  'createdAt', 'updatedAt'])
    && incoming().keys().hasAll(['uidA', 'uidB', 'requestedBy', 'status',
                                 'createdAt', 'updatedAt'])
    && incoming().uidA is string && incoming().uidB is string
    && incoming().uidA != incoming().uidB
    // Only the requester may create the edge, and only as one of its own
    // two participants — nobody can fabricate a request on someone else's
    // behalf or insert a third party into a pair they're not part of.
    && incoming().requestedBy == request.auth.uid
    && isParticipant(incoming())
    && incoming().status == 'pending'
    && incoming().createdAt == request.time
    && incoming().updatedAt == request.time;

  allow update: if isSignedIn()
    && isParticipant(resource.data)
    // Who the two people are, and who asked, can never change after
    // creation — an update can only ever be the recipient answering.
    && incoming().uidA == resource.data.uidA
    && incoming().uidB == resource.data.uidB
    && incoming().requestedBy == resource.data.requestedBy
    && incoming().diff(resource.data).affectedKeys().hasOnly(['status', 'updatedAt'])
    && resource.data.status == 'pending'
    && incoming().status == 'accepted'
    // The requester already spent their one move by creating the doc; only
    // the *other* participant may move it to accepted.
    && request.auth.uid != resource.data.requestedBy
    && incoming().updatedAt == request.time;

  // Either participant may remove the edge outright. While pending that's
  // the recipient declining or the requester cancelling; once accepted
  // that's either side unfriending — all three are the same operation
  // (delete), distinguished client-side only for wording/logging.
  allow delete: if isSignedIn() && isParticipant(resource.data);
}
```

Client always writes with `document(id).setData(fields)` — no transaction.
Firestore evaluates a `setData` against `allow create` when the doc doesn't
exist yet and against `allow update` when it does, so a second `create`-shaped
write against an existing doc falls through to the tighter `update` allowlist
automatically. There's no read-modify-write race here the way there is for
`games`' roster capacity, so this is simpler than `GameService.mutateRoster`.

**A collision worth naming, not solving in the rules:** if A and B each try
to friend the other before seeing the other's request, the second `create`
lands against an existing doc and is rejected by `update` (its `requestedBy`
doesn't match what's stored). That rejection is the *correct* signal, not a
bug — `FriendService.sendRequest` should catch it, re-fetch the existing
document, and if it finds an incoming pending request from that same uid,
call `acceptRequest` instead of surfacing an error. Call this out explicitly
in Phase 1 so it's tested rather than discovered later as a confusing
permission-denied.

Re-requesting after a decline works for free: decline deletes the doc, which
frees the deterministic ID for a new `create`.

---

## 3. Unfriend / decline / cancel

All three are the same rules-level operation — delete the edge, allowed to
either participant. `FriendService` still exposes three named methods
(`cancelRequest`, `declineRequest`, `removeFriend`), all routing to one
private `deleteEdge(_:)`, purely so call sites and logging stay honest about
which situation they're in. No re-confirmation flow, no notification beyond
the other party losing the row on their next snapshot — there's no push
infrastructure to notify through yet.

---

## 4. `games`: friends' public runs are in scope, private ones aren't

**In scope: "which public runs is a friend already on."** This needs no new
rule, query, or index — `GameService.publicGames` is already a fully-resolved
live list any signed-in user can read in full, and `FriendService.friends`
is already a live list of uids. Cross-referencing them is a client-side
computation, not a backend feature:

```swift
func friendUids(in game: Game) -> Set<String> {
    Set(game.playerIds + game.queuedPlayerIds).intersection(friendUids)
}
```

`LocalRunsViewModel` gains a `friendService: FriendService` dependency and
exposes this per row; `GameCard` grows an optional "N friends here" badge in
the Public Games section of `LocalRunsTab`. Joining is the existing `Join` /
`Join waitlist` action already on that card — nothing about *how* you join
changes, only that you can now see it's worth joining. Sorting friend-
occupied runs to the top of the section is a reasonable follow-on, not a
requirement of the first cut.

**Out of scope: a friend's *private* run.** Today, `isPublic: false` makes a
run invisible under the `games` read rule to anyone not already on its
roster — friendship doesn't factor in, and can't without a rules change (a
`get()` cross-check into `friendships` from the `games` rule, or something
denormalized onto the game document). That's a genuine authorization
decision — who gets to see an invite-only run — not a small addition, and it
overlaps with `GAPS.md`'s separate, still-unbuilt "Next steps #4"
(invite-only games via a share link). Confirmed with you as out of scope for
this plan; revisit alongside that design, not as an extension of this one.

No `FriendService` reference from `GameService` or vice versa either way —
the cross-reference above lives in the view model layer, one level above
both services, so neither service gains a dependency on the other.

---

## 5. Client architecture

**`hoopr/Models/Friendship.swift`** — Firebase-free, mirrors `Game.swift`'s
shape:

```swift
struct Friendship: Identifiable, Sendable, Codable, Hashable {
    enum Status: String, Sendable, Codable {
        case pending
        case accepted
    }
    let id: String            // "{uidA}_{uidB}", mirrored from the doc ID like Game.id
    let uidA: String
    let uidB: String
    let requestedBy: String
    let status: Status
    let createdAt: Date?
    let updatedAt: Date?
}

extension Friendship {
    /// What this edge looks like from `uid`'s side. Computed, not stored —
    /// `requestedBy` is the single source of truth; storing "sent" on one
    /// person's copy and "received" on the other's is exactly the two-copies-
    /// that-can-drift shape §2 rejects the mirrored-subcollection model for.
    enum Direction {
        case sent       // uid is requestedBy, awaiting the other participant
        case received   // the other participant is requestedBy, awaiting uid
        case mutual     // status == .accepted
    }

    func direction(for uid: String) -> Direction {
        guard status == .pending else { return .mutual }
        return requestedBy == uid ? .sent : .received
    }

    static func id(for uid1: String, _ uid2: String) -> String {
        uid1 < uid2 ? "\(uid1)_\(uid2)" : "\(uid2)_\(uid1)"
    }
    func otherUid(than uid: String) -> String { uid == uidA ? uidB : uidA }
}

enum FriendError: Error, Equatable {
    case notSignedIn
    case cannotFriendSelf
    case requestNotFound
    case permissionDenied
    case indexRequired
    case network
    case unknown(String)
}
```

**`hoopr/Services/FriendService.swift`** — `@MainActor final class
FriendService: ObservableObject`. Follows `UserProfileService`/`GameService`
closely, which is the house pattern: subscribes to `AuthService.$currentUser`
itself (session-scoped, not screen-scoped), owns one
`ListenerSupervisor(subject: "friends")`, reuses `FirestoreFailure.classify`
in a private `mapped(_:)`, disambiguates `permission-denied` by
`FailureContext.load` vs `.write` the same way both existing services do.

**Two listeners, not one** — the same reason `GameService` needs two:
`uidA == uid` and `uidB == uid` are structurally different equality filters,
because which side of the pair "I" am depends on lexicographic comparison
with the *other* uid. A single query can't express "uidA == me OR uidB ==
me," so both run and are merged client-side (no overlap is possible — a doc
can never satisfy both).

```swift
private enum ListenerKey { static let uidA = "uidA"; static let uidB = "uidB" }
```

Published, derived from the merge on every snapshot:
- `friends: [Friendship]` — `status == .accepted`, sorted by `updatedAt`
  descending client-side (no server-side `order` — see §7).
- `incomingRequests: [Friendship]` — `status == .pending && requestedBy != observedUID`.
- `outgoingRequests: [Friendship]` — `status == .pending && requestedBy == observedUID`.

Writes: `sendRequest(to:)`, `acceptRequest(_:)`, `declineRequest(_:)`,
`cancelRequest(_:)`, `removeFriend(_:)` (the last three → `deleteEdge`).
`sendRequest` rejects `otherUid == observedUID` client-side before touching
the network, computes `Friendship.id(for:_:)`, and handles the collision
from §2.

**Name resolution stays in `UserProfileService`, not `FriendService`.**
`Friendship` docs carry only uids — never denormalized names, matching how
`Game` never denormalizes court names (`courtId` is joined client-side).
`UserProfileService` already owns the `users` collection, so it gains two
one-shot (non-listener) methods:

```swift
func profiles(for uids: [String]) async throws -> [UserProfile]  // whereField(FieldPath.documentID(), in:), chunked at 30
func searchProfiles(matching prefix: String) async throws -> [UserProfile]
func profile(uid: String) async throws -> UserProfile?            // exact-ID lookup, see §1
```

This keeps "one service, one collection" literal — `FriendService` never
imports anything about `users`. Both are one-shot fetches, not listeners:
live-updating names while the tab is sitting open isn't worth a third
listener, and both are re-run whenever the underlying uid set changes.

---

## 6. Friends tab

`hoopr/Views/Tabs/FriendsTab.swift` **replaces** `FindMatchTab.swift`
(deleted). `hoopr/ViewModels/FriendsViewModel.swift` composes `FriendService`
+ `UserProfileService`, resolves display profiles through `profiles(for:)`,
drives search through `searchProfiles(matching:)` (debounced), and adopts
`LocalRunsViewModel`'s exact one-write-in-flight pattern —
`@Published private(set) var pendingFriendshipId: String?`, mirroring
`LocalRunsViewModel.pendingGameId` (`LocalRunsViewModel.swift:78`): the
acting card spinners, every other card's button goes inert.

UI pattern: extend `LocalRunsTab`'s proven two-collapsible-sections-over-one-
`ScrollView` shape to three sections, plus a pinned, always-visible search bar
above them (an action surface, not a list section):

- **Search bar** (top, pinned). Empty → sections render normally below it.
  Non-empty → results from `searchProfiles` replace the sections, each row an
  "Add" button.
- **Requests** (incoming only) — defaults **expanded**
  (`@AppStorage("friends.requestsExpanded")`, default `true`), badge count in
  the header like `LocalRunsTab`'s `countText`. This is what answers "pending
  requests needing a response": they can't collapse away by default.
- **Friends** — defaults expanded. Cold-start empty state points at the
  search bar above ("Search above to find people you play with") rather than
  a bare blank list. Clicking on the player will show their profile (only certain fields: name, home court)
- **Sent** (outgoing, pending) — defaults **collapsed**
  (`@AppStorage("friends.sentExpanded")`, default `false`); lower priority,
  cancel-only.

All three share one new `FriendCard`, mirroring `GameCard`'s chrome: name +
action(s) that vary by context (Accept/Decline · Remove · Cancel · Add).

**Rejected:** `ProfileView`'s card-mosaic pattern — that fits a small fixed
set of distinct entity types ("Your Game" / "Account"), not a variably-sized
list of like items, which is what `GameCard`/`LocalRunsTab` is built for.

`FriendsTab` unmounts on tab switch (it's not the permanently-mounted map
tab), so its `@AppStorage`-backed section state is required, matching
`LocalRunsTab`'s documented invariant.

**Injection chain** (`hooprApp` → `RootView` → `MainTabView`):

- `hoopr/hooprApp.swift`: add `@StateObject private var friendService:
  FriendService`, built in `init()` alongside `gameService`
  (`_friendService = StateObject(wrappedValue: FriendService(authService:
  authService))`), passed into `RootView(...)`.
- `hoopr/Views/RootView.swift`: add `private let friendService:
  FriendService` + init param, threaded into `MainTabView(...)` in the
  `.main` case and into the `#Preview`.
- `hoopr/Views/MainTabView.swift`: add `private let friendService:
  FriendService` + init param; change the `tabs` array's third entry
  (`MainTabView.swift:17`) from `("Find Match", "figure.run")` to
  `("Friends", "person.2.fill")`; replace `if selectedTab == 2 {
  FindMatchTab() }` (`MainTabView.swift:147-149`) with `if selectedTab == 2 {
  FriendsTab(friendService: friendService, userProfileService:
  userProfileService) }`; update the `#Preview`.
- Delete `hoopr/Views/Tabs/FindMatchTab.swift`.
- `MainTabView.swift` also passes `friendService` into the existing
  `LocalRunsTab(...)` call (`MainTabView.swift:139-144`), for the friends'-
  public-games cross-reference in §4 — that's a separate addition from the
  three bullets above, tracked as its own phase (§8, Phase 4) since it
  touches `LocalRunsTab`/`LocalRunsViewModel` rather than the new tab.

---

## 7. Indexes

**No new `firestore.indexes.json` entries.** Both `FriendService` listeners
are single-field equality filters (`uidA == uid`, `uidB == uid`) with no
`order(by:)` — sorting happens client-side after the two streams merge, since
a server-side sort on either stream alone would be meaningless post-merge.
The `userNameLower` prefix-range query is a lone single-field range, also
auto-indexed. The batched `profiles(for:)` lookup needs no index — document
ID is always indexed. Contrast with `games`' two composite indexes, which
exist only because those queries combine an equality/array-contains filter
*with* a range-and-order on `scheduledTime` — friendship queries never do
that.

---

## 8. Phases

Each phase is independently shippable and independently revertable.

### Phase 0 — Decisions

This document: the `uidA`/`uidB`/`requestedBy`/`status` schema on the
ordered pair, the `friendships` rules block, `userNameLower` prefix search
plus exact-ID lookup for discovery, the two-listener split, repurposing the
"Find Match" slot, friends'-*public*-games as an in-scope client-side
cross-reference, and the explicit non-goals (no Cloud Functions, no visibility
into a friend's private runs).

### Phase 1 — Backend only, no UI ✅ shipped

> Built as described, with two corrections worth carrying forward: `Friendship.id`
> is **computed** rather than stored (§5's `let id: String` contradicts §2's key
> allowlist, which has no `id` — see `../DATA_MODEL.md`), and the write methods
> take a friendship ID `String` rather than a `Friendship`. Rules deployed. The
> six manual two-account checks are **still outstanding**.


- `Models/Friendship.swift`, `FriendError`
- `Services/FriendService.swift` — two listeners, five write methods,
  including the create/accept collision handling from §2
- `UserProfile.userNameLower`; `UserProfileService` writes it on
  create/update, gains `profiles(for:)` and `searchProfiles(matching:)`
- `firestore.rules`: new `friendships` match block; add `userNameLower` to
  the `users` update allowlist
- `firebase deploy --only firestore:rules,firestore:indexes` — the two-step
  rule applies; skipping this makes every friend request fail
  `permission-denied` while the client looks correct, the same way
  `favoriteCourtIds` broke silently once already
- Verify by hand with two test accounts: send, accept, decline, cancel,
  unfriend; confirm a third uid can't read or write someone else's edge;
  confirm the simultaneous-request collision resolves to an accept, not an
  error

Ship-check: nothing in the app changes visually, nothing regresses.

### Phase 2 — Friends tab: respond and view only ✅ shipped

> Built as described. `FindMatchTab.swift` deleted; `FindAMatchTab.swift`
> renamed to `MapTab.swift` at the same time, since "Find A Match" naming the
> court map next to a Friends tab was the confusion that prompted it. Section
> keys are `friends.requestsExpanded` and `friends.friendsExpanded`. The
> Friends empty state deliberately doesn't reference the not-yet-built search
> bar; §6's copy applies from Phase 3.


`FriendsTab` replaces `FindMatchTab`. Requests + Friends sections only
(accept / decline / remove). No search, no send-request UI yet — sending is
already verified working in Phase 1; its UI ships next. Full injection chain
wired through `hooprApp` → `RootView` → `MainTabView`.

Ship-check: two accounts, two simulators — one accepts/declines a request
seeded via Phase 1's manual verification, the other sees the friendship
appear/disappear live.

### Phase 3 — Discovery UI ✅ shipped

> Built, with §6's layout superseded. **No backend change at all**: Phase 1
> already shipped every service method this needed, so `firestore.rules`,
> `firestore.indexes.json`, `FriendService`, `UserProfileService`, `Friendship`
> and `UserProfile` are untouched. Deltas from §6 as written:
>
> - **The collapsible sections are gone.** §6 planned a search bar above three
>   collapsibles (Requests / Friends / Sent). Shipped instead: a pinned toolbar
>   (search field + badged inbox button) over a single list, with requests moved
>   into `InboxSheet` — the surface future social notifications land in. A
>   dropdown you must expand to learn something is waiting on you is the wrong
>   shape for the one screen whose job is to tell you that. Both `@AppStorage`
>   keys were deleted.
> - **Rows are keyed on the person, not the edge.** §5's
>   `pendingFriendshipId` became `pendingUid`, because a search result has no
>   friendship document to key on. The friendship ID is recomputed with
>   `Friendship.id(for:_:)` at write time.
> - **`FriendCard` was replaced by `FriendRow`** — a compact ~68pt card with one
>   trailing control supplied by the caller, rather than a tall card with
>   full-width buttons.
> - **`PlayerProfileSheet` shows name, home court and joined** (§6 said "name,
>   home court"; `createdAt` was added as a low-cost legitimacy signal). It
>   reuses `ProfileCard` with `onEdit: nil`.
> - **Search runs both lookups rather than routing between them.** §1 proposed
>   a heuristic that *routes* to the ID path; shipped runs the name query always
>   and adds the ID read only when the text is uid-shaped, so a wrong guess
>   costs one document read instead of every result.
> - **The Friends pill in `MainTabView` carries a badge dot** — not in §6, added
>   because an inbox discoverable only from its own tab isn't a notification.
>
> The "Player ID" row on `ProfileView` (§1) already shipped in Phase 2 as the
> copyable uid under the handle, so it needed nothing here.

Ship-check: two accounts, two simulators — search by name, send, see the
incoming request land live on the other device, accept, see it move into
Friends on both sides. Also verify search by ID (§1) and the copyable uid on
the profile screen. **Still outstanding** — verified single-account so far
(search, profile sheet, inbox, row menu, self-exclusion); the two-account half
needs a second signed-in device.

### Phase 4 — Friends' public games

`LocalRunsViewModel` gains `friendService`; `GameCard`'s Public Games rows in
`LocalRunsTab` show a "friends here" badge per §4. No rules, index, or new
listener — purely a client-side join of two lists both already published by
Phase 1/2's services. Independently shippable from Phase 3: it doesn't need
search or the ability to send requests, only an existing friends list.

Ship-check: two accounts already friended (from Phase 1/2 testing), one
joins a public run, the other sees the badge appear on that run in Local
Runs without a refresh.

### Phase 5 — Later, not now

- Blocking / reporting abusive users
- Push notifications on incoming request / acceptance
- Hardened discovery: unique handles, fuzzy/typo-tolerant search, a
  third-party search index — explicitly deferred already in
  `database/DATABASE_SCHEMA.md`'s "Deliberately excluded from v1"
- Share-link-by-uid as a discovery precision aid alongside search
- **Friends' *private* runs** — needs a real authorization design (§4), and
  overlaps with `GAPS.md`'s separate, still-unbuilt invite-only-games work.
  Not an extension of Phase 4; a different feature that happens to share a
  sentence with it in the original ask.
- Mutual-friend counts or other social-graph features needing a Cloud
  Function or expensive client-side fan-out

---

## Testing

Follow `hooprTests/UserProfileTests.swift` and `GameTests.swift` — decode
`Friendship` through the real `Firestore.Decoder`, pin the client-side rules
mirror the way `FirestoreRulesParityTests` does for `Game.status` (there's
one shared constant worth pinning here too: none, actually — this schema has
no numeric bound mirrored in both places the way roster size or radius is,
so no new parity test is needed unless one gets added later). Manual
two-account verification is the only way to see the other side of a
friendship, same as `games`' roster testing today; there's still no
emulator setup in the repo, so rules logic itself stays manually verified,
consistent with the existing gap noted in `GAPS.md`.

## Documentation debt

When phases ship, update rather than let the dictionary drift:

| Entry | Change |
|---|---|
| `database/DATABASE_SCHEMA.md` | The `friendships` collection, its rules, `userNameLower` on `users`. |
| `DATA_MODEL.md` | `Friendship` and `FriendError`. |
| `UI_SHELL.md` | Replace the "Find Match" tab description with the real Friends tab; strike the placeholder note; document the "Player ID" profile row and the Public Games "friends here" badge. |
| `ARCHITECTURE.md` | `FriendService` added to the ownership table. |
| `GAPS.md` | Strike "`FindMatchTab` is a placeholder label."; note friends'-private-runs visibility as a named, still-open next step alongside invite-only games. |

## See also

- `database/DATABASE_SCHEMA.md` — the conventions this collection follows
  (absence-not-null, the two-step rule, explicit field maps).
- `ARCHITECTURE.md` — the vendor boundary `FriendService` operates inside,
  and the session-scoped-listener pattern it follows.
- `UI_SHELL.md` — the tab-mount and `@AppStorage` invariants `FriendsTab`
  must follow.
- `plans/LIVE_HEADCOUNT.md` — the other proposed-but-unbuilt plan in this
  repo, for format reference.
