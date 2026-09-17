# hoopsRN — Rate limiting and abuse gaps

**Scope:** —
**Verified:** 2026-09-16 @ 8209408

What bounds how fast a client can write, what doesn't, and why most of it
can't be fixed without infrastructure the project has deliberately avoided.

`Scope: —` because this is a narrative over `firestore.rules`, which
`database/DATABASE_SCHEMA.md` owns. It can't be diffed, so it's re-read by hand
every pass.

---

## The constraint everything else follows from

Three facts, and they settle the shape of this before any specific gap:

1. **Firestore rules are stateless per request.** A rule can read other
   documents — `get()`, `exists()`, `getAfter()` — but it cannot count how many
   times a uid has written recently. There is no sliding window, no counter, no
   "N per minute" primitive. Anything that looks like a rate limit here has to
   be built out of a *document structure* that makes repetition self-limiting.
2. **There are no Cloud Functions.** `firebase.json` configures Firestore and
   nothing else; there is no `functions` directory anywhere in the repo. So
   there is no server-side code that could run a limiter, sweep abandoned
   state, or moderate anything.
3. **There is no App Check**, and sign-up has no verification step —
   `AuthService.signUp` is a bare `createUser(withEmail:password:)`. Accounts
   are free, unlimited, and scriptable.

Point 3 is what caps the value of everything else: **any limit scoped to a uid
is a speed bump, not a wall**, because a fresh uid costs nothing. Closing that
needs App Check (which ties writes to an attested app install rather than to an
account) or real friction at sign-up. Until then, per-account limits raise
effort; they don't prevent.

---

## What is enforced today

Two kinds of thing actually bound writes, and neither is a counter.

**Structural — one live document per relationship.** The document ID *is* the
relationship, so a duplicate has nowhere to go: `friendships/{pair}`,
`squadInvites/{squadId}_{uid}`, `matchTickets/{squadId}`. This is the strongest
pattern in the ruleset and it costs nothing to enforce, because it isn't
enforced — it's structural.

**Burst-rate floors — comparisons against a pinned timestamp.** Added
2026-09-16 after the review below. Each compares `request.time` against a
timestamp an earlier write already pinned, which a client can only ever push
forward, never back:

| Rule | Floor | Bounds |
|---|---|---|
| `matchTickets` create | `squad().createdAt` ≥ 5s | An account minting disposable squads and queueing each instantly |
| `matchTickets` delete | ticket's own `createdAt` ≥ 5s | The same squad churning its own ticket via delete→recreate |
| `seasonGames` report | 5s since `updatedAt`, **per leader's own field** | A leader toggling their own report to bounce `scheduled`↔`disputed` |

**A cooldown, never a quota — and that distinction is the whole design.** A cap
on *count* needs a stored counter, and a counter a client can decrement is a
counter that defeats itself. A cooldown needs only a timestamp the rules
already pin, so there is nothing to tamper with. `firestore.rules` carries the
full reasoning at each site; `firestore-tests/` boundary-tests all three at 4s
refused / 6s allowed.

---

## What is still open

### Transaction-attempt spam — not fixable in rules

**The sharpest version of the pool-flood vector, and rules genuinely cannot
reach it.** Holding one `open` ticket costs nothing and lasts up to 24 hours. A
modified client — not bound by `ClaimPolicy`'s jitter or backoff, which are
client-side courtesies — can fire commit transactions against every other open
ticket in a region continuously. Attempts that fail leave **no trace**: no
document mutates, no timestamp moves, so there is nothing for a cooldown to
compare against. The floors above bound how fast tickets are *created*; they
do nothing about how fast they are *attempted against*.

The cost is real on both sides: transactions billed against the project, and
contention against legitimate claim attempts on the same tickets. This needs
App Check or a Cloud Function. Nothing in `firestore.rules` can see it.

### Uncapped creation of fresh-ID documents

Collections keyed by a *relationship* are structurally capped. Collections
keyed by a **fresh auto-ID** are not capped at all:

- **`squads`** — unlimited per leader. The 5s floor above bounds how fast a
  fresh squad can *queue*, not how many can exist.
- **`games`** — unlimited runs per host. `Limit.published = 100` on the client
  query means a flood of garbage public runs with near-term `scheduledTime`
  can push real ones out of the visible window for a whole city.
- **`friendships`** — capped per *pair*, uncapped across distinct targets. One
  account can request thousands of strangers in a loop. See
  [`FRIENDS.md`](FRIENDS.md); this is the longest-standing instance.

### No referential integrity on delete

Nothing cascades, because nothing can — rules cannot trigger. A squad
disbanded while its ticket is still `open` leaves that ticket in the pool,
advertising a squad that no longer exists, until `expiresAt` retires it. Found
during the same review; not a throttling gap, but it shares the root cause
(no server).

### No blocking, reporting, or moderation

Named here because it is what people usually mean by "abuse tooling", and it is
a different problem from rate limiting. `PRODUCT_OVERVIEW.md` lists it under
safety tooling; `plans/FRIENDS.md` Phase 5 is the closest thing to a design.

---

## See also

- `../database/DATABASE_SCHEMA.md` — the burst-rate floors in situ, with the
  per-field reasoning for the report cooldown.
- [`FRIENDS.md`](FRIENDS.md) — the friend-request case, unmitigated.
- [`PROFILES.md`](PROFILES.md) — why a per-account stamp needs the private
  subcollection first.
- `../ROADMAP.md` — the infrastructure decision these all wait on.
