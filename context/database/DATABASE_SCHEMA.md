# hoopsRN — Database Schema

**Scope:** `firestore.rules`, `firestore.indexes.json`, `firebase.json`, `.firebaserc`, `firestore-tests/`
**Verified:** 2026-09-20 @ e6968e0

What's stored server-side and what a client may write. Seven collections are
live:
`users` (one owner per document), `games` (the first shared, multi-user state),
`friendships` (one document per *pair* of people, written by either of them),
`squads` (a team, written by its leader and by each member for their own
membership), `squadInvites` (structurally `friendships`, one document per
squad-and-person pair), `matchTickets` (a squad's standing offer to play, and the only
document here whose contested write belongs to *another* squad), and
`seasonGames` (a scheduled match, and the documents a squad's record is derived
from).
Datastore is Cloud Firestore (Native mode), project `hoopsrn-4f1e9`, region
`nam5`. Rules live in `firestore.rules` at the repo root and are deployed via the
Firebase CLI.

Firebase Auth already provides *identity* (uid, email). The collections below
are app-owned data layered on top of that identity, never a replacement for it.

The seven are a progression in **who may write a document**, and each one's rules
are worth reading in that order: `users` has exactly one author; `games` has
many, each confined to their own lane of a shared document; `friendships` has
two, with asymmetric authority spent in a single move; `squads` has a leader plus
every member acting only on their own membership; `squadInvites` returns to
asymmetric authority, spent in one move and answered by a write to a *different*
collection; and `matchTickets` and `seasonGames` break the pattern together —
one commit, written by a squad that owns only half of it, whose three documents
each prove the other two happened in the same transaction.

**A dry-run is not a test.** `firebase deploy --dry-run` proves this file
compiles. Whether a write is actually refused is evaluated in `firestore-tests/`
against the Firestore emulator (`npm run test:rules`), which is also where the
claim race is run. `hooprTests/FirestoreRulesParityTests` is the third leg: it
parses the rules as *text* and fails when a bound mirrored into Swift drifts from
its copy here.

**All seven collections have emulator coverage** as of 2026-09-20 — 141 tests.
The suite was Seasons-only until then; `games.test.mjs`, `friendships.test.mjs`
and `users.test.mjs` backfilled the three original collections, and were
mutation-tested on the way in (three rules deliberately weakened, exactly three
tests failed). See `../gaps/TESTING.md`.

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

`id` and `createdAt` are **write-once** (the rules' own comment listed `email`
alongside them until 2026-08-21, years after that field was removed). A client may only ever change
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

`completed` **is** written, by the host, through the separate completion update
path below — that shipped 2026-09-18. `in_progress` remains declared and never
written by anything.

A run that nobody completes still ages out of both lists once it's past its
visibility grace window (**4h** after tip-off, raised from three on 2026-09-20).
That window is client-side only — no rule mentions it — so the run stays in the
collection, merely unlisted. Retiring it server-side needs a scheduled Function;
see `../ROADMAP.md` §0.

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

## `squads`

A named team that queues together for season matches — the third piece of shared,
multi-user state, and the **first whose subject is a group** rather than a person
or a pair.

That shift is what makes squad-vs-squad play legal under the existing security
model. Every other collection here enforces "a client may only ever write its own
membership," and a match commits three people to a game. It doesn't violate the
rule, because **a match names squad IDs, not player uids**: a leader commits their
squad by writing one identifier they already own, and the rules verify leadership
with a single `get()`. Nobody's uid is written by anybody else anywhere in
Seasons. See `../plans/SEASONS.md` §0.3.

**Document ID is Firestore-generated**, with `id` mirroring it, following `games`.

| field | type | required | mutable | notes |
|---|---|---|---|---|
| `id` | string | yes | no | Mirrors the document ID. |
| `name` | string | yes | yes | 3–24 chars. Bounds mirrored in `Squad.nameLengthRange` and pinned by `FirestoreRulesParityTests`. |
| `nameLower` | string | yes | yes | Lowercased mirror, derived through `Squad.searchKey(_:)` and written in the same field map — the `userNameLower` convention, but **required from the first write** rather than backfilled, because this collection had no rows predating it. |
| `leaderId` | string | yes | no | uid. Always present in `memberIds`, enforced server-side. |
| `memberIds` | array\<string\> | yes | yes | Leader included. Bounded by the format's roster ceiling. Only ever changed by the self-join and self-leave paths, one uid at a time. |
| `format` | string | yes | no | `3v3` today. Allowlisted in the rules; `1v1` and `5v5` exist in `SquadFormat` and are refused at create. |
| `iconKey` | string | yes | yes | SF Symbol name from a 12-entry allowlist. |
| `colorKey` | string | yes | yes | Palette *key*, never a colour — resolved by `Theme.swift` so the crest stays appearance-aware. A stored hex would bypass that entirely. |
| `region` | string | yes | no | The matchmaking pool key. `Court.city` today; see below. |
| `createdAt` | timestamp | yes | no | Server-assigned. |
| `updatedAt` | timestamp | yes | yes | Server-assigned, refreshed on every write. |

### No `wins` / `losses` / `gamesPlayed`

**Deliberate, and the single biggest integrity decision in Seasons.** It departs
from `users.completedGameCount`, which `../GAPS.md` already records as
self-reported and forgeable.

A stored counter on a document you control is a number you can type. A squad's
record is instead **derived** — `seasonGames where squadIds array-contains
{squadId} and status == "confirmed"`, counted client-side by `result`. That is
arithmetic over documents *two different leaders had to agree on*. There is
nothing to forge and no cache to reconcile, and disputed or cancelled games are
structurally excluded because they never reach `confirmed`.

Cost: one extra query to show an opponent's record. At tens of squads per city
that is nothing. Revisit only if a standings screen makes it hurt, and then add
the cache as an explicitly-untrusted display field, the way `completedGameCount`
already is.

### Readable by any signed-in account

**Like `users`, unlike `friendships`** — and this is a real privacy decision
rather than an oversight, so it is recorded rather than left to be discovered.

An opponent has to render your crest and name on a match card, and season play is
public by design: records, standings and an opponent's history are the point of
the feature. A participants-only read rule would make the feature's central
screen impossible.

**The create rule's key allowlist is what keeps that safe.** It is exactly the
argument `users` makes: without it a modified client could store anything it
liked — an email, a phone number — on a document every signed-in account can
read, and Firestore has no field-level read ACLs. Anything private about a squad
would belong in a leader-only subcollection, never here.

### Three separate update paths

The same split `users` draws between profile edits and stats, and `games` draws
between roster changes and completion. One write can never smuggle in another
path's fields: a leader's rename can't also change the roster, and a join can't
also change the name.

1. **Leader edit** — `name`, `nameLower`, `iconKey`, `colorKey`, `updatedAt`.
   `memberIds` is absent from the allowlist, so this path cannot change who is on
   the squad no matter what it ships alongside.
2. **Self-join** — the `memberIds` diff is exactly the caller's own uid, added,
   gated on `exists()` of the matching `squadInvites` document and bounded by the
   format's ceiling.
3. **Self-leave** — the mirror image, and closed to the leader.

**The no-duplicates check is not optional.** `memberIds.toSet().size() ==
memberIds.size()` is what stops `['leader','me','me','me','me','me']` — six list
entries, two set entries — from reading as a single addition to the set
comparison, letting one member consume every seat and lock the squad to full. It
is the same hole the `games` rule documents, and the reason a set diff is only a
faithful proxy for a stored list when the list has no duplicates. Exercised in
`firestore-tests/squads.test.mjs`; a rules dry-run cannot reach it.

A leader cannot leave. **Disbanding is their exit**, the way cancelling is a
`games` host's — so there is one answer to "what happens to the squad when the
person who made it goes."

### `region` is a placeholder with a named successor

`Court.city` for v1: the bundled dataset is six Triangle cities and `city` is on
every court. Verified 2026-08-28 — 214 courts, six cities, no empty or `null`
value, casing consistent. **Re-run that check if `courts.json` is regenerated**;
`tools/build_courts.py` and `tools/fetch_city_courts.py` both invalidate it.

A bad region key would silently partition the matchmaking pool into groups that
can never see each other — a failure with no error message. `../plans/SCALE_UP.md`
S1.1 defines the real region key; when it ships, `region` becomes that key and the
pool query is unchanged. The rules deliberately bound it only as a non-empty
string: mirroring a length for a value already scheduled to change would pin down
the one part of the field that isn't decided.

### Access

- **Read:** any signed-in user. See above.
- **Create:** the leader only, as a squad of exactly themselves, with an
  allowlisted format, icon and colour and both timestamps at `request.time`. A
  roster at creation would mean writing other people's uids.
- **Update:** three disjoint paths, above.
- **Delete:** the leader only.

### Indexes

**None.** The listener is a single `memberIds array-contains` filter with no
`order(by:)`; sorting happens client-side on a list a handful of rows long. Same
trade `friendships` makes, and the reason this collection leaves
`firestore.indexes.json` untouched.

---

## `squadInvites`

A leader's standing offer for one person to join one squad. **Structurally
`friendships`**: one document per pair, ID derived from its own content, so a
duplicate is impossible rather than merely deduplicated.

**Document ID is `{squadId}_{uid}`**, and the rules recompute it from the
document's own fields and reject anything else.

| field | type | required | mutable | notes |
|---|---|---|---|---|
| `squadId` | string | yes | no | |
| `uid` | string | yes | no | The invitee. |
| `invitedBy` | string | yes | no | The leader, `== request.auth.uid` at create. |
| `createdAt` | timestamp | yes | no | Server-assigned. |

The authority is asymmetric and spent in one move: the leader creates it, and the
only thing the invitee ever does to *this* document is delete it. **Accepting is a
write to the squad, not to here** — which is the whole reason a squad can gain a
member without anyone writing somebody else's uid.

There is no `status` field. Revoking, declining, and consuming an accepted invite
are all the same operation (delete): absence, never null, exactly as
`friendships` handles decline/cancel/unfriend.

### The friendship gate

Creating an invite requires an **accepted** friendship between inviter and
invitee, checked with an `exists()` plus a `get()` on the ordered pair ID
computed the same way `Friendship.id(for:_:)` computes it.

It costs four lines and it is the difference between "squads are built from your
friends" and "anyone can spam invites at strangers" — which is a live gap on
friend requests themselves (`../GAPS.md`), deliberately not repeated here. A
*pending* request is not enough; all three states are asserted in
`firestore-tests/squads.test.mjs`.

### Where an invite is answered

**In the profile's `InboxSheet`**, alongside friend requests — not on any of
`../plans/SEASONS.md` §5's numbered screens, and not on the Seasons tab either,
which is why it is worth stating. It rendered inline on Squad home at first,
then moved once the inbox existed: both a friend request and a squad invite
are "something waiting on you," and one inbox is where that belongs rather
than two places a person has to remember to check.

Wherever it renders, the same rule holds: without somewhere to *accept*, a
roster could never gain a second member — the self-join rule exists for
exactly this moment, and a squad would be permanently a team of one.
`SquadViewModel` joins `squadInvites` to `SquadService.fetchSquad(id:)` for the
name and crest, because the squads listener only carries squads you are
already on.

### Access

- **Read:** the invitee or the inviting leader. Both client listeners filter on
  one of those two fields against the caller's own uid, so neither ever asks for
  a document this rule doesn't already admit.
- **Create:** the squad's leader only, to an accepted friend, with a matching
  document ID.
- **Update:** `if false`. Immutable — there is nothing here to change.
- **Delete:** either participant.

A second invite to the same person writes the same document ID, falls through to
`allow update: if false`, and is refused. `SquadService.invite` reads the
document back and treats that specific refusal as success, the same move
`FriendService.sendRequest` makes: a duplicate tap from a stale screen is not a
failure.

### Indexes

**None.** Two single-field equality listeners (`uid ==`, `invitedBy ==`), no
ordering.

---

## `matchTickets`

A squad's standing offer to play — the matchmaking pool.

**Document ID is the squad ID**, which structurally enforces one live ticket per
squad. There is no duplicate-entry logic to write because there is nowhere to put
a second row, the same trick `friendships/{pair}` uses.

This is the one collection here **written by somebody who doesn't own the
document**: the *claim* is another squad's leader taking a ticket out of the
pool. Firestore serializing contested single-document transactions is what makes
exactly one of them win, and that guarantee is the entire matchmaker — there is
no server to pair squads (`../plans/SEASONS.md` §0.1), so matchmaking is pull
with a lock rather than push.

| field | type | required | mutable | notes |
|---|---|---|---|---|
| `squadId` | string | yes | no | Mirrors the document ID. |
| `leaderId` | string | yes | no | The only account that may create or delete it. |
| `squadName` | string | yes | no | Denormalized for the pool UI. Pinned to the squad document at create. |
| `memberIds` | array\<string\> | yes | no | Denormalized so the no-shared-players rule is arithmetic on two tickets rather than two more reads. **Pinned to the squad document** — the load-bearing one: a client free to write its own copy could match against a squad it shares players with. |
| `format` | string | yes | no | Equality filter on the pool query. Pinned. |
| `region` | string | yes | no | Equality filter on the pool query. Pinned. |
| `courtIds` | array\<string\> | yes | no | Acceptable courts, 1–8, **ordered by preference**. No duplicates: a preference order can't rank a court against itself. |
| `windowStart` / `windowEnd` | timestamp | yes | no | When they can play. Client-supplied, rules-bounded — `windowEnd > windowStart`, `windowEnd > request.time`, and `windowStart` inside the same 30-day ceiling `games` puts on a run. |
| `wins` / `losses` | int | yes | no | Denormalized **at queue time** for opponent ranking. Display and scoring only — never the record of truth. Derived from confirmed `seasonGames` by the caller; see `squads` above. |
| `status` | string | yes | yes | `open` \| `matched`. **Two states, and the second is terminal** — there is no `claimed`, because there is no gap between claiming and matching for it to name. |
| `claimedBy` | string? | no | yes | The squad that took this ticket out of the pool. On the **home** ticket only — the away squad spends its own, so nobody claimed it. Written in the same commit as `matched`. |
| `claimedAt` | timestamp? | no | yes | Server-assigned, pinned to `request.time`. This document's only change stamp. |
| `matchedGameId` | string? | no | yes | The match this ticket was spent on. **Both tickets carry it, and they carry the same value** — one match, referred to from both squads. Also the proof each ticket's rule checks with `getAfter()`. |
| `createdAt` | timestamp | yes | no | Server-assigned. **Ticket age is what drives relaxation.** |
| `expiresAt` | timestamp | yes | no | Client-supplied, rules-bounded to 15 minutes–24 hours, and queried against — an expired ticket leaves the pool without anything having to delete it. |

### There is deliberately no `updatedAt`

**A resolved conflict between two halves of the plan, recorded as a resolution
rather than just an outcome.** `../plans/SEASONS.md` §1.3's field table omits
`updatedAt`; §2.2's rules snippet lists it inside the claim's `affectedKeys()`.
Both cannot be right.

**The field table won.** `claimedAt` already *is* this document's "when did this
change" stamp, and the commit is the ticket's only mutation — so an `updatedAt`
would be a second name for the same instant, and adding it would mean widening
the commit's `affectedKeys()` allowlist, which is the one place it should stay
narrow. A ticket is ephemeral; it has no edit history worth keeping.

If a later phase makes an `updatedAt` genuinely useful, **reopen that
deliberately** — change the field table, the allowlist and this paragraph
together. Do not let it drift back in as an incidental field on some other write.

### The commit: one transaction, two tickets, one match

```
runTransaction:
  read matchTickets/{theirs}                  ← both reads, before any write
  read matchTickets/{mine}
  guard both status == 'open'
  guard MatchRules still produces a candidate ← re-checked inside the txn
  create seasonGames/{new}
  write theirs: status='matched', claimedBy=mine, claimedAt=<server>, matchedGameId
  write mine:   status='matched',                                     matchedGameId
```

**A ticket is spent exactly once, and that is the whole invariant.** The rules
permit `open` -> `matched` and nothing else, on both update paths, so a squad
cannot be taken out of the pool twice — which is what makes "a squad is in at
most one live match" true on the server rather than only in the client.

#### Two burst-rate floors, added after a rate-limiting review

Rules have no request counter — there is no way to ask "how many times has
this uid written recently" — so nothing here is a quota. What's added instead
is two comparisons against a timestamp an earlier write already pinned, which
a client cannot move backwards:

- **`matchTickets` create** requires `squad().createdAt` to be at least five
  seconds old. Bounds one account minting many disposable squads and queueing
  each the instant it exists, to flood a region's pool past the client's
  `limit(to:)` or multiply how many tickets it can hold open at once.
- **`matchTickets` delete** requires the ticket's own `createdAt` to be at
  least five seconds old. Bounds the case the create-side floor doesn't reach
  — the *same* squad churning its own ticket, which would otherwise be free
  to run as fast as the network allows and would churn every other client's
  pool listener in that region/format on each cycle.

Both cap **burst** rate, not sustained abuse, and neither survives a fresh
account — sign-up has no verification step. A rules-only floor is what's
achievable without new infrastructure; App Check or a Cloud Function would be
needed for anything stronger. `firestore-tests/match-tickets.test.mjs` tests
both with a brand-new document (0s, refused) and a six-second-old one
(allowed) — which pins the floor to somewhere in (0, 6], not to five.

#### Why it is one commit, and what the two-step version got wrong

This used to be three writes: claim the opponent's ticket, create the game, then
mark both tickets `matched`. The claim was a transaction against a **single
document**, and it leaned on Firestore serializing contested writes to one
document. That guarantee holds. It is the wrong guarantee.

Two squads that pick *each other* claim two **different** tickets. Nothing
serializes them, both claims win, and both clients go on to create a match. Both
squads then have two live matches against each other, and the app asks a leader
to cancel the one they didn't want — when only one was ever intended. In a
region with two squads queued, that is not an edge case: it is what normally
happens.

Reading and writing **both** tickets in one transaction is the fix, and it is
the same guarantee applied to the pair that actually needs it. The two mutual
commits now share a read set, so exactly one lands and the other is retried onto
a ticket that is already spent, where the in-transaction guard turns it into a
quiet loss. `firestore-tests/claim-race.test.mjs` races both shapes — two squads
on one ticket, and two squads on each other — fifteen rounds each, and asserts
exactly one match exists at the end.

Losing is expected, not exceptional, and is never surfaced to the user —
`ClaimPolicy.isUserFacing` is a pure function so that stays tested.

#### Each document proves the other two

Three documents, three separate rule evaluations of one commit, and `getAfter()`
is what stops any of them standing alone:

- **`seasonGames` create** demands that *both* tickets end the commit `matched`
  and carrying this `gameId`, and that the home ticket's `claimedBy` is the away
  squad. So a match cannot be created without spending both tickets.
- **Each `matchTickets` update** demands that the match named in
  `matchedGameId` exist after the commit, be `scheduled`, and cast this squad in
  the role the ticket claims. So a ticket cannot be spent except by a write that
  really is making that match.

Written one at a time, every one of them is refused. That is deliberate: a
half-commit is exactly how a squad ends up out of the pool with no match, or in
a match while still in the pool.

`claimedAt` is **pinned to `request.time`**, not requested, so the one change
stamp this document carries cannot be backdated.

#### Three windows closed, not one

The two-step design needed recovery machinery that no longer has anything to
recover:

- **A claimer dying between the claim and the game** left a ticket wedged
  `claimed`. `MatchRules.staleClaim = 90s` was the recovery, enforced in four
  places that had to agree. Gone: nothing is ever spoken for without being
  spent.
- **A claimer dying between the game and the tickets** left a spent ticket
  looking claimable, so a third squad re-matched a squad that already had a
  game. The fix was a second writer on the `matched` transition — each leader
  closing their own ticket off their own `seasonGames` listener. Gone with the
  window.
- **Two matches for one pair**, which this file previously recorded as
  unpreventable in rules "because rules cannot query". That framing was wrong:
  it never needed a query, only a read set wide enough to contend.

**A spent ticket is not deleted**, and nothing cleans it up — it ages out on
`expiresAt`, up to 24 hours later. Two consequences worth stating, because both
were bugs:

- **The UI must not read a spent ticket as a live search.** `MatchTicket.isSearching`
  is that question, and it is the only one the searching state may ask.
- **Queueing again is a delete-then-create.** A `setData` over a spent ticket is
  an *update* to the rules, and no update path admits it, so a squad would be
  refused for hours. `MatchmakingService.queue` reads the ticket, deletes it if
  it is spent, and then creates — all leader-only writes, so no new permission.

### Record proximity is a gate, not only a score

Another place the plan reads two ways, resolved here. §2.1 lists record proximity
only under *soft* rules — signals weighted into a score. But the same section's
relaxation paragraph names "the record-proximity tolerance" as something
relaxation widens, and a tolerance nothing enforces is not a tolerance.

**It is implemented as a gate**, deliberately generous: win percentages may be
0.35 apart at relaxation 0, and fully open at relaxation 1. So it changes *when*
an uneven match happens, never *whether* — the reading that leaves both sentences
true. It is also weighted into the score, at 0.35, so among legal matches the
closer record still ranks higher.

This is the hook a real skill rating (Elo / TrueSkill) plugs into later —
`../plans/SEASONS.md` §7 names it as a Phase 8 once there is a corpus of
confirmed games.

### Not part of `presence/{uid}`

`../plans/BACKLOG.md` A2 proposes `queueEntries/{uid}` for solo Queue Up and
flags that it overlaps `checkins/{uid}`, calling for a unified `presence/{uid}`.
**That unification stands for the two player-level ephemerals. `matchTickets` is
not part of it**, and the reason is recorded here so nobody folds them together
to save a rules block: its subject is a squad rather than a person, its lifecycle
is a two-party negotiation rather than a self-declaration, and its ID space is
squad IDs. Two different subjects in one collection is a worse trade than two
rules blocks.

### Access

- **Read:** any signed-in account, like `squads` — because that is what a pool
  *is*. Every queued client watches the same one and the winner of a
  one-document race gets the match. The pool query filters on region, format,
  status and expiry, all of which the read rule already admits.
- **Create:** the squad's leader only, with the four denormalized fields pinned
  to the `squads` document and `status == 'open'`. `claimedBy`, `claimedAt` and
  `matchedGameId` are absent at create — absence, never null.
- **Update — the home ticket:** any leader of a *different* squad, on an `open`
  ticket, touching only `status`, `claimedBy`, `claimedAt` and `matchedGameId`,
  and only in a commit that creates the match it names. Authorized by one
  `get()` against `squads/{claimedBy}` and one `getAfter()` against the match.
- **Update — the claimer's own ticket:** its own leader, `open` -> `matched`
  with `matchedGameId`, in that same commit. Without this half a squad could
  take an opponent out of the pool while staying in it themselves.
- **Delete:** the leader only. A delete rather than a status — absence, never
  null, the same move `friendships` makes. Also how a squad re-queues after a
  match: the spent ticket is deleted and a fresh one created, because no update
  path will overwrite one. An abandoned ticket ages out on `expiresAt` without
  anyone removing it.

### Indexes

One composite, on `(region ASC, format ASC, status ASC, expiresAt ASC)` — the
pool query.

**`status == 'open'`**, which is the whole of it: a ticket is in the pool or it
is spent. The query used to be `status in ['open', 'claimed']`, so the scanner
could see tickets wedged by a claimer that crashed and re-take them after 90
seconds. With the commit atomic there is nothing to wedge, so the middle state
and the recovery it needed are both gone. **The index is unchanged** — an
equality filter and an `in` filter on the same field read the same composite.

---

## `seasonGames`

A scheduled squad-vs-squad match — the document the whole feature exists to
produce, and the one a squad's record is derived from.

**Document ID is Firestore-generated**, with `id` mirroring it, following
`games`.

| field | type | required | mutable | notes |
|---|---|---|---|---|
| `id` | string | yes | no | Mirrors the document ID. |
| `format` / `region` | string | yes | no | Copied from the home ticket and pinned to it. |
| `homeSquadId` | string | yes | no | **The squad whose ticket was claimed** — so the court and window are theirs. |
| `awaySquadId` | string | yes | no | The squad that committed the match. Its own ticket is spent in the same transaction. |
| `squadIds` | array\<string\> | yes | no | `[home, away]`, in that order. The `array-contains` query field, and the reason one listener serves both squads. The rule pins the exact array, order included. |
| `homeLeaderId` / `awayLeaderId` | string | yes | no | Denormalized, and **verified against `squads` at create**. See below. |
| `homeSquadName` / `awaySquadName` | string | yes | no | Denormalized so history survives a disbanded squad. Verified against `squads` at create, so they can't be invented. |
| `courtId` | string | yes | no | Must be in the home ticket's `courtIds`. |
| `scheduledTime` | timestamp | yes | no | Must fall inside the home ticket's window, and be in the future. |
| `status` | string | yes | yes | `scheduled` \| `cancelled` \| `confirmed` \| `disputed`. |
| `arrivedPlayerIds` | array\<string\> | yes | yes | Self-add only, both squads in one array, one-directional. `[]` at create. |
| `homeReport` / `awayReport` | string? | no | yes | The squad ID each leader says won. **Each pinned to its own leader**, in both directions. May be overwritten or cleared — that is how a dispute is resolved. |
| `homeScore` / `awayScore` | int? | no | yes | Optional and cosmetic. Set by whichever leader is reporting; never read by the record. |
| `result` | string? | no | yes | The winning squad ID, written **only** when both reports agree, and only equal to both of them. |
| `cancelledBySquadId` | string? | no | yes | Written by the cancelling leader, as their own squad. |
| `createdBy` | string | yes | no | uid of the leader who committed the match. |
| `createdAt` / `updatedAt` | timestamp | yes | — | Server-assigned. |
| `confirmedAt` | timestamp? | no | yes | Server-assigned, and only on the write that confirms. |

### What authorizes naming another squad

This is the document that makes squad play legal, so the question is worth
answering directly: **two spent tickets, proved rather than asserted.** The
create rule reads *both* tickets with `getAfter()` and requires each to end this
commit `matched` and naming this `gameId`, the home ticket's `claimedBy` to be
the away squad, and the caller to be `awayLeaderId` and the away ticket's
leader. Each ticket can only go `open` -> `matched`, so only one commit can ever
spend a given ticket — and the authority traces back to an offer each leader
made by queueing.

Reading the away ticket is the half that used to be missing. Proving the home
ticket had been claimed said nothing about whether the away squad was still in
the pool, which is how one squad ended up in two matches at once.

Nobody's uid is written by anybody else. `homeLeaderId` is a **copy of a fact**
verified against `squads/{homeSquadId}`, not an assertion about a person.

### The denormalized leader IDs are why later writes are free

Cancel costs **zero document accesses**, because both leader IDs are already on
the document. Phase 6's reports will be the same. That is the entire payoff for
denormalizing them — and exactly why they are verified once, at create, and
immutable afterwards.

A forged `homeLeaderId` would hand the away side the home leader's own write
paths: their cancel, and later their report. That single condition in the create
rule is what stands between the two.

### What the rule costs

**Three document accesses** — the home ticket, and both squads. Rules `get()`s
against the same path within one evaluation are cached, so the repeated ticket
reads are free. Three of the ten the platform allows.

### Readable by any signed-in account

Like `squads` and `matchTickets`, and unlike `games`, which gates on `isPublic`
or roster membership. Season play is public by design and a squad's record is a
query over these documents, so gating them would make records unreadable by the
people a record is *for*.

### No delete, ever

A squad's record is a query over these documents, so **a deletable match is a
forgeable record** — which is the whole thing the derived-record design exists
to prevent. Cancelling is the exit, and it is an update rather than a delete
because a cancelled match is still history both squads should see. A cancelled
match is structurally excluded from the record because it never reaches
`confirmed`.

### The double-booking window, and why there isn't one

This section used to describe a window and a repair. The window was the gap
between writing the match and marking the tickets: a client that died in it left
a spent ticket looking claimable, so a third squad re-matched a squad that
already had a game. The repair was a second writer on the `matched` transition —
each leader closing their own ticket off their own `seasonGames` listener — and
it left duplicate matches possible but rare.

**Both are gone.** The match and both tickets are written in one transaction, so
there is no instant at which one exists without the others, nothing to reconcile
afterwards, and no second writer to admit. `SeasonGame` documents are created by
exactly one write, which also spends exactly the two tickets that authorize it.

What replaced the repair is the mutual demand described under `matchTickets`
above: the create rule reads **both** tickets with `getAfter()` and requires each
to be `matched` and to name this `gameId`. Proving only that the *home* ticket
had been claimed — which is all the old rule did — said nothing about whether
the away squad was still in the pool, and that omission is what let one squad
appear in two matches.

`SeasonGameService.duplicateGames` and the card's "more than one match
scheduled" line are **kept as a tripwire**, not as a workflow. They should now
be unreachable; if either ever fires, an invariant above has been lost and the
rules are the first place to look.

### Arrival

`arrivedPlayerIds` is the `games` self-only membership pattern verbatim, and
one-directional — added, never removed, the same way marking a run `completed`
has no undo. The caller must be on one of the two rosters, checked with two
`get()`s against `squads` (cached alongside the create rule's three if a write
ever needs both), and refused once the match leaves `scheduled`. The
no-duplicates check is not optional here either, for the reason `squads`
documents.

Both squads read the same array off the same listener — the moment a squad
sees they're first to the court.

**Local notifications, not push.** `NotificationService` schedules the T-60,
T-0 and T+90 reminders (plan §4) the moment a client's own listener sees a
match land; there is no server to fire them for a client that never opens
between the match being made and tip-off. Named in `../GAPS.md`, not fixed —
real push needs FCM and a Cloud Function, the same Blaze-plan requirement the
matchmaker itself is built around not having.

### Reporting, and why a record is trustworthy

`../GAPS.md` records the ceiling the rest of the app accepts:
`completedGameCount` is self-reported, and a modified client could misreport its
own stats. A competitive record cannot inherit that unchanged, because the whole
point of the number is that **other people believe it**.

**Mutual confirmation** raises the ceiling as far as a serverless design allows,
and it is three rules:

1. Each leader writes **only their own** report field — `homeReport` for
   `homeLeaderId`, `awayReport` for `awayLeaderId`, pinned in both directions.
   The other leader's key is simply absent from that caller's
   `affectedKeys().hasOnly` list, which is the same "a client may only ever
   write its own lane" principle `games` and `squads` build on, applied to a
   report instead of a roster slot.
2. **`status` is derived from the two reports, never chosen.** Both in and
   agreeing is `confirmed`; both in and disagreeing is `disputed`; one in leaves
   the match `scheduled`. `result` is only accepted when it equals *both* stored
   reports, and `confirmedAt` is pinned to `request.time` on that same write —
   so a client claiming an agreement the other leader never made is refused
   rather than believed.
3. A disagreement is a **designed outcome, not an error**. A disputed match
   counts for nobody, and either leader may overwrite or clear their own report
   and enter it again, which is how a dispute gets resolved — by two people
   talking, which is what actually happens at a court.

**Re-touching your own already-present field floors at five seconds** —
`request.time >= resource.data.updatedAt + duration.value(5, 's')`, checked
only once that field already exists on `resource.data`. Added after a
rate-limiting review: nothing else stops a leader clearing and re-entering
their own report as fast as the network allows, bouncing the match between
`scheduled` and `disputed` and churning the opponent's listener on every
cycle. It has to be scoped to *one leader's own field*, not the document —
a document-wide floor breaks the ordinary case point 1 describes, two
different leaders each reporting for the first time within moments of each
other, since the second leader's first-ever report would be refused for the
crime of arriving promptly. `firestore-tests/results.test.mjs` pins both: the
concurrent-first-report case unfloored, and a same-leader re-touch floored at
the 4s/6s boundary.

So forging a win takes two colluding squads rather than one lying client. That
is not cryptographic integrity and this schema does not claim it is; it is the
standard a rec-league scoresheet meets.

**Reportable from `scheduled` and `disputed` only.** `confirmed` is deliberately
excluded: a leader able to re-report a match both sides already settled could
turn their own loss back into a dispute unilaterally, which is *weaker* than the
scoresheet standard above and is not what the recovery path in point 3 needs.
`cancelled` is excluded because a called-off match has no result.

**Not before tip-off.** The rule requires `request.time >= scheduledTime` — a
match cannot be reported before it has been played.

**The write is a transaction, and the race is the reason.** A plain update
writing only the caller's own field leaves a hole: two leaders reporting within
moments of each other each read "no report yet" from their own client's cache,
each write only their own field, and neither write ever runs the do-these-agree
check against the state that actually landed — both reports stored, `result`
never set, nothing failing to say so. `SeasonGameService.reportResult` reads the
document inside a transaction and lets Firestore's retry serialize the pair, the
same way every other contested single-document write here is handled. See
`GameService.mutateRoster` for the shape.

`firestore-tests/results.test.mjs` evaluates all of this against **two distinct
authenticated leaders**, which is the only way to test a rule whose entire
subject is two different people agreeing or disagreeing.

### The record is a query

`seasonGames where squadIds array-contains {squadId} and status == 'confirmed'`,
counted client-side by `result`. See `squads` above for why it is not a stored
field. An unplayed squad reads as 0.5 rather than as a squad that loses
everything — `SeasonGame.record(for:in:)` and `MatchTicket.winPercentage` agree
on that.

Disputed and cancelled matches are **structurally excluded** because they never
reach `confirmed`, which is also why the reporting rule may never write
`cancelled` and the cancel rule may never write `confirmed`.

### Access

- **Read:** any signed-in user.
- **Create:** the away leader, on a claim they won, with the court and time
  drawn from the home ticket and both squads' leaders and names verified.
  `result`, the reports, the scores, `cancelledBySquadId` and `confirmedAt` are
  absent from the key allowlist, so a match cannot be born already won.
- **Update (cancel):** either leader, from `scheduled` only, as their own squad.
- **Update (arrival):** any member of either roster, self-add only, from
  `scheduled` only. See "Arrival" above.
- **Update (report):** either leader, **their own report field only**, from
  `scheduled` or `disputed`, and only after `scheduledTime`. Costs zero document
  accesses. See "Reporting" above.
- **Delete:** never.

### Indexes

Two composites:

- `(squadIds CONTAINS, scheduledTime ASC)` — the listener, which uses
  `array-contains-any` so a person still on more than one squad (the app stops a
  second one now, but doesn't remove existing ones) gets all their matches from
  one query. The same index serves `array-contains`.
- `(squadIds CONTAINS, status ASC)` — `SeasonGameService.fetchRecord(for:)`, the
  one-off read of **another** squad's record. An `array-contains` combined with
  an equality on a second field needs its own composite; without it the read
  fails `failed-precondition` and an opponent's record renders as 0–0 with only
  a log line to say why.

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
- A squad's record is **never stored**. `wins`/`losses` on a `matchTicket` are a
  queue-time display copy; the record of truth is a query over confirmed
  `seasonGames`. Never write one onto `squads`.
- `matchTickets` carries **no `updatedAt`** — `claimedAt` is its change stamp, and
  the claim is its only mutation. Reopen that deliberately or not at all.
- A squad's roster changes one uid at a time, and only the caller's own — with a
  no-duplicates check, without which a set diff is not a faithful proxy for a
  stored list.
- A squad's leader can never be removed, themselves included. Disbanding is their
  exit.
- `squads` and `matchTickets` are world-readable to signed-in accounts, so the
  same rule `users` follows applies: **nothing private goes in them**, and the
  create rules' key allowlists are what enforce it.
- A `seasonGame` can never be deleted. A deletable match is a forgeable
  record, and the record is a query over exactly these documents.
- A `seasonGame`'s `status` is derived from its two reports, never chosen —
  agreement is `confirmed`, disagreement is `disputed`, one report is still
  `scheduled` — and `result` is only ever a value **both** stored reports name.
  Each report field is writable by its own leader alone. Mirrored in
  `SeasonGame.reportOutcome`; the two copies must stay identical, the same way
  `Game.status` and its rules expression must.
- The leader IDs denormalized onto a `seasonGame` are verified against `squads`
  at create and immutable after, because every later write trusts them for free.
- A ticket goes `open` -> `matched` and nowhere else, on both update paths. That
  single transition is what makes "one live match per squad" a server fact
  rather than a client convention, and `FirestoreRulesParityTests` pins it on
  both sides of the boundary.
- A match and the two tickets that authorize it are written in **one**
  transaction, and each of the three proves the other two with `getAfter()`.
  Any write that moves one without the others is refused — which is the point,
  not a limitation.
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
- `../plans/SEASONS.md` — why `squads`, `squadInvites` and `matchTickets` are
  shaped this way, the matchmaker's design, and the phases still unbuilt.
- `../../firestore-tests/README.md` — the emulator suite that evaluates these
  rules, and why a dry-run isn't one.
