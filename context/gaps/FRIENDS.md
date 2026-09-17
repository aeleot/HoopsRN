# hoopsRN — Friends gaps

**Scope:** —
**Verified:** 2026-09-16 @ 8209408

What's unfinished about `friendships` — discovery, requests, and the safety
tooling that was deferred on purpose. Phases refer to `../plans/FRIENDS.md` §8.

`Scope: —` because this is a narrative over code `database/DATABASE_SCHEMA.md`
and `UI_SHELL.md` own. It can't be diffed, so it's re-read by hand every pass.

**Shipped:** the `friendships` collection and its rules (Phase 1), the Friends
tab's respond-and-view half (Phase 2), and discovery — search by name prefix or
exact ID, `PlayerProfileSheet`, `InboxSheet` with its badge (Phase 3). All
deployed and running.

---

## Anyone can ask anyone, as often as they like

**There is no blocking, no reporting, and no rate limiting on friend
requests.** Anyone signed in can search for anyone and send them a request;
declining (which deletes the edge) is the only recourse, and nothing stops the
same person asking again immediately.

The client bounds the *accidental* case — a 300ms search debounce, a 20-result
cap, one write in flight — but **a modified client isn't bound by any of
that**, and the document-ID-per-pair structure only caps duplicates against the
*same* person. Requests to thousands of *different* uids are uncapped.

This is the longest-standing instance of the pattern in
[`RATE_LIMITING.md`](RATE_LIMITING.md), and the one that matters most, because
its blast radius is a person rather than a query budget. The burst-rate floors
added to `matchTickets` and `seasonGames` on 2026-09-16 were **not** extended
here: a cooldown needs a timestamp on a document the write already touches, and
a first-ever request to a new person has no prior document to compare against.
A per-account stamp would work and needs the private subcollection first — see
[`PROFILES.md`](PROFILES.md).

Phase 5 in `../plans/FRIENDS.md` is the design; it needs Cloud Functions.

---

## Verified by hand once, and never since

The six two-account checks from Phase 1 were validated manually against the
live project on 2026-08-14: a participant can read their own edge; the
recipient can accept while `uidA`/`uidB`/`requestedBy` stay put; a third
account is refused the read; the requester cannot accept their own request;
`isOrderedPair`, `idMatchesPair` and the `request.time` pinning all hold
against a real client write; the three deletes work and a declined pair's
deterministic ID is re-usable afterwards.

**That was a one-time manual pass, not coverage.** `firestore-tests/` now
exists and evaluates the real ruleset against the emulator — but it covers
Seasons only. The `friendships` block still has no automated test, so any
future edit to it, or to the `users` key allowlists, is unverified until
someone repeats those checks by hand. Backfilling `friendships` coverage into
the existing harness is cheap now that the harness is the expensive part; see
[`TESTING.md`](TESTING.md).

**One case has never run at all, by hand or otherwise:** `sendRequest`'s
simultaneous-request collision. Reaching it needs two accounts sending to each
other before either sees the other's request. It is reachable from the UI since
Phase 3 and still hasn't been done.

---

## Still to build

- **Phase 4 — friends' public runs.** `LocalRunsViewModel` gains
  `friendService`, `GameCard` grows an "N friends here" badge. No rules, index,
  or listener — a client-side intersection of two lists the app already holds,
  and `MainTabView` already has `friendService` to pass in. The cheapest
  remaining item in the feature.
- **Friend profile detail.** `../plans/FRIENDS.md` §6 says tapping a friend
  shows name + home court. Not built, and it needs the visibility question in
  [`PROFILES.md`](PROFILES.md) settled first.
- **Friends' *private* runs**, which needs a real authorization design and
  overlaps with invite-only games — settle it with the invite decision in
  [`GAMES.md`](GAMES.md) rather than separately.
- **Deferred on purpose (Phase 5):** blocking and reporting, push notifications
  on request and acceptance, unique handles, typo-tolerant search.

---

## Live test data

A hand-seeded friendship between the developer's account and `chaseallen122`
exists in the **production** project. Delete it when it stops being useful.

---

## See also

- `../plans/FRIENDS.md` — the design behind all of the above.
- [`RATE_LIMITING.md`](RATE_LIMITING.md) — the request-spam gap in its wider
  context.
- [`PROFILES.md`](PROFILES.md) — the search key and the privacy question this
  feature keeps running into.
