# hoopsRN — Database Schema

**Scope:** `firestore.rules`, `firestore.indexes.json`, `firebase.json`, `.firebaserc`
**Verified:** 2026-08-13 @ map-tab

What's stored server-side and what a client may write. Three collections are
live: `users` (one owner per document), `games` (the first shared, multi-user
state), and `friendships` (one document per *pair* of people, written by either
of them). Datastore is Cloud Firestore (Native mode), project `hoopsrn-4f1e9`,
region `nam5`. Rules live in `firestore.rules` at the repo root and are deployed
via the Firebase CLI.

Firebase Auth already provides *identity* (uid, email). The collections below
are app-owned data layered on top of that identity, never a replacement for it.

The three are a progression in **who may write a document**, and each one's
rules are worth reading in that order: `users` has exactly one author;
`games` has many, each confined to their own lane of a shared document;
`friendships` has two, with asymmetric authority spent in a single move.

For how this is wired into the app at runtime, see `USER_PROFILE_WORKFLOW.md`.

---

## `users`

One document per account. **Document ID is the Firebase Auth uid**, so a profile
is addressable without a query and security rules can compare `request.auth.uid`
directly against the document path.

| field | type | required | mutable | notes |
|---|---|---|---|---|
| `id` | string | yes | no | Firebase Auth uid. Duplicates the document ID so the model decodes without optionals. |
| `userName` | string | yes | yes | Display name, 1–50 chars. **Editable and not unique** — despite the name, this is not a handle, and nothing enforces uniqueness. |
| `userNameLower` | string? | no | yes | Lowercased mirror of `userName`, **derived, never independently supplied** — `UserProfileService` writes it in the same field map as `userName`, through `UserProfile.searchKey(_:)`. It exists so player search can do a case-insensitive prefix range, which Firestore can't express over `userName` itself. Absent on profiles provisioned before search existed — **`UserProfileService.backfillSearchKeyIfNeeded` writes it on the first snapshot that arrives without one**, so each account heals itself the next time its owner opens the app. That's the whole migration: the update rule is owner-only, so no client can backfill anyone else, and there are no Cloud Functions on the Spark plan to do it server-side. Until an account's owner has opened a build containing that backfill, that person is **unfindable by name search** — though still findable by user ID, which reads the document directly. |
| `homeCourtId` | string? | no | yes | A `Court.id` from the bundled dataset. Set from the profile screen's court picker. Clearing it **deletes the field** rather than storing null. Courts don't live in Firestore, so there's no server-side reference to validate against — a stale ID resolves to "Unknown court" in the UI. |
| `favoriteCourtIds` | array\<string\>? | no | yes | Starred courts, written with `arrayUnion`/`arrayRemove` so two devices can't clobber each other. Absent on profiles provisioned before favourites existed. Stored inline rather than as a subcollection so it rides the profile listener that's already open. |
| `preferredRadius` | number? | no | yes | Search radius in miles for the nearby courts list. Set from the profile screen's slider. Rules bound **writes** to 1–50, but say nothing about rows already stored — the client coerces anything out of range back to the 5-mile default (see `../DATA_MODEL.md`). A `0` seeded by hand in the console reads as "unset", not as a zero-mile search. |
| `createdAt` | timestamp | yes | no | Server-assigned at creation. |
| `updatedAt` | timestamp | yes | yes | Server-assigned, refreshed on every write. |

### Mutability contract

`id` and `createdAt` are **write-once**. A client may only ever change
`userName`, `userNameLower`, `homeCourtId`, `preferredRadius`, and
`favoriteCourtIds` (plus the `updatedAt` bookkeeping that goes with them).
This is enforced **server-side** in `firestore.rules` via
`diff().affectedKeys().hasOnly([...])`, not merely by client-side discipline —
a hand-crafted request that tries to rewrite `createdAt` is rejected by
Firestore.

```
allow update: if isOwner()
  && request.resource.data.id == resource.data.id
  && request.resource.data.createdAt == resource.data.createdAt
  && request.resource.data.diff(resource.data).affectedKeys()
       .hasOnly(['userName', 'userNameLower', 'homeCourtId',
                 'preferredRadius', 'favoriteCourtIds', 'updatedAt'])
```

Firestore has no field-level ACLs, so field immutability is hand-built by
diffing the incoming document against the stored one.

`userNameLower` is on that list but is **not** a field a person edits — it's
derived from `userName` on the way in. The rules allow it without checking the
derivation, so a hand-crafted request could store a `userNameLower` that doesn't
match its own `userName`. The only consequence is that the profile becomes
findable under a name it doesn't display, on its own row — worth knowing, not
worth a rules expression that would have to duplicate `lower()` semantics.

### The two-step rule

Adding a newly editable field takes **two** changes: a write method on
`UserProfileService`, *and* adding the field to `hasOnly([...])` followed by
`firebase deploy --only firestore:rules`. Skipping the redeploy leaves saves
failing with `permission-denied` while the client code looks entirely correct.

**`favoriteCourtIds` shipped without step two and stayed broken**, which is what
this warning is for. The service method and the star UI both landed; the rule
still listed only three fields, so every star tap was rejected server-side. It
was invisible because `toggleFavorite` is optimistic — the star fills in, the
write fails, and the profile listener quietly reverts it. Found in the device
log (`Profile error while saving your favorites: permissionDenied`), not on
screen. If you add a field and it "works" locally, check the log before
believing it.

### Absent vs. null

Absence is the convention, never an explicit null. Clearing a home court writes
`FieldValue.delete()`; provisioning omits any field it has no value for. The rules
follow suit — the `homeCourtId` type check is written to tolerate the field
being absent:

```
&& (!('homeCourtId' in request.resource.data)
    || request.resource.data.homeCourtId is string)
```

### Nothing private lives here

The read rule grants **any signed-in user**, and covers `list` as well as `get` —
that's load-bearing (name resolution on rosters, and the player search in
`plans/FRIENDS.md`), but it means any signed-in account can enumerate every
profile in the app. Firestore has no field-level read ACLs: a document is
readable whole or not at all.

So the contents of `users` are, in practice, visible to every other player, and
the key allowlists on **both** create and update are what hold that line.

**`email` was exactly this mistake.** It was written at provisioning,
denormalized "for display", and read by nothing — the profile screen's Email row
takes its value from `AuthService.currentUser`, not from Firestore. The field
did nothing except expose every account's address to every other account. It was
removed from the model and the write path, purged from the stored documents, and
the create rule gained the allowlist that had previously existed only on update
— without which a modified client could simply write it back.

Firebase Auth still owns the address; it just isn't copied anywhere readable.
Sign-in, signup and password reset all go through Auth and never touch this
collection, so none of them are affected.

Anything genuinely private in future — a blocked-users list, notification
preferences — belongs in an owner-only `users/{uid}/private/…` subcollection,
not here. `homeCourtId` and `favoriteCourtIds` are the fields worth re-examining
on that basis: they're a location pattern attached to a named person, currently
readable by any signed-in stranger.

### Access

- **Read:** any signed-in user — see above. Player names must be resolvable in
  shared contexts (match rosters, court check-ins), and friend discovery is that
  later phase arriving: a name-prefix search over `users` needs no new read
  access, only the indexed `userNameLower` field to search on.
- **Create:** owner only, and the document must carry `id == uid` with a
  1–50 character `userName` — and *only* keys on the allowlist, so a client
  can't seed a field nobody vetted into a world-readable document.
- **Update:** owner only, under the mutability contract above.
- **Delete:** denied outright. Account deletion isn't a supported flow yet.

### Indexes

Still no composite index for `users`. The profile listener and `profile(uid:)`
are single-document reads by ID; the batched `profiles(for:)` lookup filters on
`FieldPath.documentID()`, which is always indexed; and the name search is a lone
single-field range on `userNameLower`, which Firestore auto-indexes. A composite
entry becomes necessary the first time one of those combines with a *second*
field — searching within a city, say. The two indexes that *do* exist belong to
`games`, below.

### Deliberately excluded from v1

Add later as separate, deliberate migrations — only once a feature actually
needs them: `skillLevel`, `preferredPosition`, `height`, `avatarUrl`, and a
separate unique `username` handle.

---

## `games`

One document per scheduled run. **This is the first collection more than one
person writes to**, and the mutability contract is what makes that safe: the
host authors the run, and everyone else may only ever move *themselves* between
its two rosters.

Unlike `users`, the document ID is **generated by Firestore**. There's no
natural key — a person can host many runs — so `id` mirrors the generated ID
purely so the Swift model decodes without a `@DocumentID` wrapper, which would
drag a Firebase type across the vendor boundary into `Models/`.

| field | type | required | mutable | notes |
|---|---|---|---|---|
| `id` | string | yes | no | Mirrors the document ID. Rules pin `id == gameId` at creation. |
| `hostId` | string | yes | no | Organizer's uid. Always present in `playerIds` — enforced server-side, so a run can't outlive its host leaving it. |
| `courtId` | string | yes | no | A `Court.id` from the bundled dataset. Courts aren't in Firestore, so there's nothing to validate against — same caveat as `homeCourtId`. A stale ID renders "Unknown court". |
| `scheduledTime` | timestamp | yes | no | Client-supplied, bounded server-side to `(now, now + 30d)`. |
| `isPublic` | bool | yes | no | `true` = discoverable. `false` = visible only to people already on a roster. |
| `maxPlayers` | int | yes | no | 2–30, bounded by the rules. |
| `status` | string | yes | yes | `open` \| `full` \| `in_progress` \| `completed`. **Derived, never chosen** — see below. |
| `playerIds` | array\<string\> | yes | yes | Confirmed players, host included. Never longer than `maxPlayers`. |
| `queuedPlayerIds` | array\<string\> | yes | yes | Waitlist. Always written as `[]` rather than omitted — the update rule diffs both arrays together, and an absent field would make that arithmetic conditional for no gain. |
| `createdAt` | timestamp | yes | no | Pinned to `request.time`. |
| `updatedAt` | timestamp | yes | yes | Pinned to `request.time` on every write. |

### `status` is derived, not chosen

The rules recompute it from the roster that ships in the same request:

```
request.resource.data.status ==
  (request.resource.data.playerIds.size() >= request.resource.data.maxPlayers
     ? 'full' : 'open')
```

So `open`/`full` can't drift from `playerIds.count`, and a client that computes
it differently is rejected rather than quietly storing a contradiction.
`Game.status(playerCount:maxPlayers:)` is the client's single copy of the same
rule — **changing one without the other turns every write into a
`permission-denied`.**

That's now caught before it ships. `hooprTests/FirestoreRulesParityTests` parses
`firestore.rules`, extracts the comparison and the two status literals out of
`statusMatchesRoster()`, and runs the reconstructed rule against
`Game.status(playerCount:maxPlayers:)` over every roster in
`Game.maxPlayersRange` — plus a couple past the cap, where a `>` / `>=` swap
hides. The same file pins the roster bounds, the scheduling window, the radius
range and the `userName` cap. **Change a bound on one side and a test fails
naming both sides.** It is not a rules evaluator; it only proves the shared
constants still agree.

`in_progress` and `completed` are declared by the schema but **nothing writes
them yet**: the update rule only ever admits `open`/`full`. A run simply ages
out of both lists once it's past its visibility grace window (3h after tip-off).

### The membership diff

The load-bearing check on update. Both rosters are unioned into a set before
and after, and the symmetric difference must contain nothing but the caller:

```
members(after).difference(members(before)).hasOnly([request.auth.uid])
&& members(before).difference(members(after)).hasOnly([request.auth.uid])
```

Two consequences worth stating plainly:

- **A freed slot is not handed to the first waitlisted player.** Promotion means
  writing *someone else's* uid, which this rejects by design. It needs a host
  action or a Cloud Function; neither exists yet.
- **Invite-only runs currently hold only their host.** Nobody else can read
  them, so nobody else can join. Invites are the missing half of that feature.

Everything describing the run itself — court, time, visibility, size, host — is
immutable, so there is no "edit a run" path to secure.

### Access

- **Read:** any signed-in user, for a run that is `isPublic` **or** one they're
  already on. The two client queries are constrained to exactly those shapes, so
  each returns only documents the rule already admits.
- **Create:** the host only, as the sole player, with both timestamps pinned to
  `request.time` and the schedule inside its window.
- **Update:** any signed-in user, restricted to
  `['playerIds', 'queuedPlayerIds', 'status', 'updatedAt']` under the membership
  diff above.
- **Delete:** the host only. **Deliberately unlike `users`**, where deletion is
  denied outright — cancelling a run is a first-class action, whereas account
  deletion is an unsupported flow.

### Indexes

Two composite indexes, the first entries `firestore.indexes.json` has ever
held. Each backs one listener, and each is an equality-or-array-contains plus a
range on `scheduledTime`:

| Query | Index |
|---|---|
| `playerIds array-contains uid`, `scheduledTime > cutoff`, ordered | `(playerIds CONTAINS, scheduledTime ASC)` |
| `isPublic == true`, `scheduledTime > cutoff`, ordered | `(isPublic ASC, scheduledTime ASC)` |

**Radius is not in either query.** Courts live in the bundled dataset, not in
Firestore, so there are no coordinates server-side to filter on — the distance
filter is a client-side join in `LocalRunsViewModel`. Doing it server-side would
mean geohashing every run on write.

Deploy both alongside the rules:

```bash
firebase deploy --only firestore:rules,firestore:indexes
```

### Deliberately excluded from v1

Invites (the other half of invite-only), waitlist promotion, host-run controls
for `in_progress`/`completed`, recurring runs, and any per-run chat.

---

## `friendships`

One document per **pair** of people — not one per person, and not a mirrored
subcollection under each. A friendship and a pending request to become one are
the same document at different `status` values.

**Document ID is `{uidA}_{uidB}` where `uidA < uidB`**, lexicographically on the
raw uid strings. Firebase uids are ASCII alphanumeric, so Swift's `<` and the
rules language's `<` agree, which is what lets the rules recompute the ID from
the document's own content and reject a client that picked a different one.

That derived ID is the whole design. Without it, A could create `A_B` while B
independently created `B_A` for the same relationship, and the two copies would
drift out of sync — the classic mirrored-graph problem, normally solved with a
Cloud Function that fans a write out to both sides. Here there is structurally
only one legal document for a given pair, so there's nothing to keep in sync and
no function to run. (The project is on the Spark plan; see `../GAPS.md`.)

| field | type | required | mutable | notes |
|---|---|---|---|---|
| `uidA` | string | yes | no | Lexicographically first of the pair. |
| `uidB` | string | yes | no | Lexicographically second. Rules require `uidA < uidB` and `uidA != uidB`. |
| `requestedBy` | string | yes | no | Who initiated, always one of the two. **Distinct from the pair order**, which is arbitrary — this is the single source of truth for which side is waiting on which. |
| `status` | string | yes | yes | `pending` \| `accepted`, and nothing else. |
| `createdAt` | timestamp | yes | no | Pinned to `request.time`. |
| `updatedAt` | timestamp | yes | yes | Pinned to `request.time`, refreshed on the one legal transition. |

**There is no `id` field**, and this is the one place the schema deliberately
departs from `games`. A game's ID is generated by Firestore, so it has to be
mirrored into the document for the Swift model to see it; a friendship's ID is
*derived* from two fields already in the document, so `Friendship.id` is a
computed `"\(uidA)_\(uidB)"` instead. The create rule's key allowlist —
`hasOnly(['uidA', 'uidB', 'requestedBy', 'status', 'createdAt', 'updatedAt'])` —
has no `id` in it, so writing one is rejected outright.

### Two authors, asymmetric authority

`games` lets many people write one document, each confined to their own lane.
`friendships` is the same idea with a much smaller state space, and the lanes
are *unequal*:

- The **requester** spends their entire authority at `create` time. They choose
  the pair, and that's the last write they get.
- The **recipient's** only legal move is flipping `pending` → `accepted`.

```
&& incoming().diff(resource.data).affectedKeys().hasOnly(['status', 'updatedAt'])
&& resource.data.status == 'pending'
&& incoming().status == 'accepted'
// The requester already spent their one move by creating the doc; only
// the *other* participant may move it to accepted.
&& request.auth.uid != resource.data.requestedBy
```

`uidA`, `uidB` and `requestedBy` are additionally pinned equal to their stored
values, so an update can only ever be the recipient answering — there's no
"re-point this friendship at someone else" path to secure.

### Decline, cancel and unfriend are one operation

All three are a plain `delete`, available to either participant. That's why
there is **no `declined` or `cancelled` status**: absence, never a tombstone —
the same convention that gives `games` no `cancelled` status either. The client
keeps three separate method names (`declineRequest`, `cancelRequest`,
`removeFriend`) purely so call sites and logs stay honest about the situation;
they all route to one private `deleteEdge`.

Re-requesting after a decline works for free: the delete frees the deterministic
ID, and a fresh `create` at the same ID is legal again.

### The simultaneous-request collision

If A and B each try to friend the other before seeing the other's request, the
second write lands against a document that already exists. Firestore evaluates a
`setData` against `allow create` only when the document is absent and against
`allow update` when it isn't, so the second one falls through to the tighter
update allowlist and is **rejected** — its `requestedBy` doesn't match what's
stored.

That rejection is the correct signal, not a bug. `FriendService.sendRequest`
catches the `permission-denied`, re-reads the document, and if it finds a
pending request from that same uid, calls `acceptRequest` instead of surfacing
an error — asking someone who has already asked you is, in substance, saying
yes. A duplicate send from the *same* requester lands in the same path and
resolves as a no-op.

**Consequence worth naming:** a genuine `permission-denied` here (an undeployed
ruleset) reaches the same code path. It's told apart by the re-read also
failing, in which case the original write error is surfaced unchanged.

### Access

- **Read:** the two participants only — including while it's still a pending
  request. **Deliberately unlike `users` and `games`**, whose read rules admit
  any signed-in user: nobody else may know a friendship or a request exists.
- **Create:** the requester only, as one of the pair, with the ID matching the
  ordered pair, `status == 'pending'`, and both timestamps at `request.time`.
  Nobody can fabricate a request on someone else's behalf or insert a third
  party into a pair they aren't part of.
- **Update:** the *other* participant only, and only `pending` → `accepted`.
- **Delete:** either participant, at any status.

Because the read rule is participants-only, a denied **read** means something
different here than on `users`/`games`: both client listeners filter on the
caller's own uid, so they never ask for a document the caller isn't a
participant of. A refusal therefore still points at an undeployed ruleset — the
conclusion matches the other two collections even though the reasoning doesn't.

### Indexes

**None, and none are needed.** The two listeners are single-field equality
filters (`uidA == uid`, `uidB == uid`) with no `order(by:)`.

Two listeners rather than one because which side of the pair you are depends on
a lexicographic comparison with the *other* person's uid — half your friendships
store you in `uidA` and half in `uidB` — and Firestore can't express `uidA == me
OR uidB == me` in a single query. The two streams are merged client-side, where
the sort also happens: a server-side sort on either stream alone would be
meaningless after the merge. No document can satisfy both queries, since
`uidA != uidB` is enforced at creation, so the merge is a concatenation rather
than a deduplication.

Contrast with `games`' two composite indexes, which exist only because those
queries combine an equality or array-contains filter *with* a range and order on
`scheduledTime`. Friendship queries never do that.

### Deliberately excluded from v1

Blocking and reporting, push notifications on request/acceptance, mutual-friend
counts or anything else needing a fan-out, and **letting friends see each
other's private runs** — that last one needs a real authorization design (a
`get()` cross-check into `friendships` from the `games` rule, or something
denormalized onto the game document) and overlaps with the still-unbuilt
invite-only-games work in `../GAPS.md`. Surfacing which *public* runs a friend
is already on needs none of that: it's a client-side intersection of two lists
the app already holds.

---

## Invariants

- Each collection's document ID is fixed by its own rule and never client-chosen
  freely: `users` is the Auth uid (and `id` duplicates it), `games` is generated
  by Firestore (and `id` mirrors it), `friendships` is `{uidA}_{uidB}` in
  lexicographic order (and is **not** stored as a field — it's derived).
- `Game.status` is derived from the roster on both sides of the wire. The
  client helper and the rules expression must stay identical.
- A client may only ever add or remove **itself** from a run's rosters.
- A friendship's requester spends their authority at `create`; only the other
  participant may accept, and either may delete.
- `userNameLower` is derived from `userName` and written in the same field map.
  Never write one without the other.
- `queuedPlayerIds` is always written, `[]` when empty — the one place the
  "absent, never null" convention is deliberately not applied.
- `users` is world-readable to signed-in accounts, so **nothing private goes in
  it** — both its create and update rules carry a key allowlist to enforce that.
  Private per-user data belongs in an owner-only subcollection.
- `id`, `createdAt` are write-once, enforced server-side. So are
  `uidA`, `uidB` and `requestedBy` on a friendship.
- Every new editable field needs both a service write method and a rules
  redeploy. One without the other is a silent failure.
- Absent, never null. Clearing a field deletes it, and a status that would mean
  "gone" (declined, cancelled, unfriended) deletes the document instead.
- Reads on `users` and `games` stay open to any signed-in user; reads on
  `friendships` are participants-only. Writes stay confined to the one lane
  each rule grants the caller.

## See also

- `USER_PROFILE_WORKFLOW.md` — the runtime behaviour on top of this schema.
- `../DATA_MODEL.md` — the Swift side of the contract.
- `../BUILD_AND_CONFIG.md` — the Firebase CLI surface and deploy command.
- `../plans/FRIENDS.md` — why `friendships` is shaped this way, and the UI
  phases still unbuilt on top of it.
