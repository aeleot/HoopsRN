# hoopsRN — Friends gaps

**Scope:** —
**Verified:** 2026-09-21 @ 29486ac

What's unfinished about `friendships` — discovery, requests, and the safety
tooling that was deferred on purpose.

`Scope: —` because this is a narrative over code `database/DATABASE_SCHEMA.md`
and `UI_SHELL.md` own. It can't be diffed, so it's re-read by hand every pass.

**Built and deployed:** the `friendships` collection and its rules, answering
and viewing requests, discovery (search by name prefix or exact ID,
`PlayerProfileSheet`, `InboxSheet` and its badge), and the friends'-public-runs
badge. Only the safety tooling is left, deferred on purpose.

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

Blocking is `../plans/BACKLOG.md` B3; it needs Cloud Functions.

---

## The request collision's client half has never run

The friendship rules are covered by `firestore-tests/friendships.test.mjs` on
every run, including the refused second create when two people request each
other at once. See [`TESTING.md`](TESTING.md).

**The client half has still never run:** whether `sendRequest` catches that
refusal and accepts instead of surfacing a `permission-denied`. Reaching it
needs two accounts sending to each other before either sees the other's
request. It has been reachable from the UI since discovery shipped and still hasn't been done,
and no emulator test can get to it.

---

## Still to build

- **Friends' *private* runs**, which needs a real authorization design and
  overlaps with invite-only games — settle it with the invite decision in
  [`GAMES.md`](GAMES.md) rather than separately.
- **Deferred on purpose:** blocking and reporting, push notifications on
  request and acceptance, unique handles, typo-tolerant search, and mutual-friend
  counts — each needs a Cloud Function or a real search index. Tracked in
  `../plans/BACKLOG.md` Track B.

---

## Live test data

A hand-seeded friendship between the developer's account and `chaseallen122`
exists in the **production** project. Delete it when it stops being useful.

---

## See also

- [`RATE_LIMITING.md`](RATE_LIMITING.md) — the request-spam gap in its wider
  context.
- [`PROFILES.md`](PROFILES.md) — the search key and the privacy question this
  feature keeps running into.
