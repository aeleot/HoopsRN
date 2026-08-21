# hoopsRN — Product Overview

**Scope:** —
**Verified:** 2026-08-21 @ 9a81cc2

What the app does today, stated in business terms: what a person can actually
accomplish in it, what it guarantees about their data, and what is deliberately
not built yet. This is the document to hand someone who needs to understand the
product without reading the code.

It owns no source paths, so the drift check can't tell you when it goes stale —
re-read it by hand whenever a feature ships, alongside `GAPS.md`.

---

## What hoopsRN is

A pickup basketball app for the North Carolina Triangle. It answers three
questions a player has before they leave the house: **where can I play, is
anyone playing, and who do I know who plays.**

It is a working iOS application backed by a live Firebase project, not a
prototype. People can create accounts, schedule real games, and add each other
as friends today.

---

## What a user can do today

### Find a court

- **Browse 214 curated courts** across six Triangle cities — Durham (55),
  Raleigh (53), Chapel Hill (43), Cary (26), Apex (22), Morrisville (15) — on a
  map with clustered pins, or as a distance-sorted list.
- **Filter** by lights, two-or-more hoops, and public access.
- **See what a court has** before travelling: hoop count, surface, lighting,
  covered, and a caution flag for restricted access. Only facts the source data
  actually carries are shown — nothing is inferred.
- **Get directions**, handed off to Apple Maps.
- **Star favourites**, which sync to the account and follow the user to any
  device.
- **Revisit recent courts**, kept on the device rather than the account.

Court data ships inside the app. The map is populated instantly, **works with no
network**, and doesn't depend on a third-party service that might be slow or
down.

### Organise a run

- **Schedule a game** at any court: a time, a roster size (2–30), and whether
  it's public or invite-only.
- **See runs near you**, filtered to a search radius the user sets (1–50 miles,
  default 5).
- **Join a run**, or take a **waitlist** place when it's full.
- **Leave** a run, or **cancel** one you host.
- **Copy an invite link** for a private run.

Capacity is enforced on the server, not just in the app: two people taking the
last seat at the same moment cannot both succeed. A run retires from every list
three hours after tip-off.

### Find people

- **Search players** by display name or by exact user ID.
- **Send, accept, decline and cancel friend requests**, and remove friends.
- **See waiting requests** from anywhere in the app — a badge on the profile
  button, and a count in the profile's inbox.
- **View another player's profile**: their name, home court, and join month.

### Manage an account

- Email and password **sign-up, sign-in, and sign-out**.
- **Password reset** by emailed link. The app never sees or stores a password.
- **Edit a display name**, set a **home court**, and set a **search radius**.
- **Choose an appearance** — System, Light, or Dark — stored per device.
- **Copy your user ID**, which is how someone finds you when a name search
  can't.

---

## What the app guarantees

### Security

Access rules live in version control and are enforced **server-side**, so they
hold against a modified client, not just against the app's own screens:

| Data | Who can read it | Who can write it |
|---|---|---|
| Profiles | Any signed-in user | The owner only |
| Games | Anyone, if public; participants only, if private | The host creates and cancels; everyone else may add or remove **only themselves** |
| Friendships | The two people on it, and nobody else | The requester creates; only the recipient can accept; either can delete |

Specific properties worth stating plainly:

- **A player cannot add or remove anyone but themselves** from a game roster.
  This is enforced by a set-difference check in the rules.
- **Nothing private is stored on a profile.** Profiles are readable by any
  signed-in account, so an allowlist restricts what may be written to one at
  all. An email field was removed for exactly this reason: it was stored,
  displayed nowhere, and visible to every other account.
- **Account creation dates and identities are immutable**, pinned server-side
  against hand-crafted requests.
- **Passwords never pass through the app.** Reset happens on Firebase's own
  page; the app only asks for the email to be sent.
- **A run cannot be backdated or scheduled a year out** — timestamps are pinned
  to server time and the window is bounded at 30 days.

**Known limits, stated honestly:** there is no blocking, reporting, or rate
limiting on friend requests. Anyone signed in can find anyone and ask once;
declining is the only recourse, and nothing stops them asking again. A
server-side limit needs infrastructure the project doesn't have yet.

### Accessibility

- **WCAG 2.1 AA contrast** is enforced by an automated test suite rather than
  by review. Every colour pairing the interface actually draws is asserted at
  4.5:1 in **both** light and dark mode, and the build fails if one slips.
- **Dynamic Type** is supported throughout. The design's point sizes scale on
  the system's own curve, so the app renders as drawn at the default size and
  grows properly for readers who need it larger.
- **Light and dark mode** are both first-class. Every colour is defined as a
  role with a value per appearance; there are no fixed colours in the interface
  layer.
- **VoiceOver** labels and values are set on controls, including the ones whose
  meaning is carried by an icon or a badge.

One known exception is tracked in `GAPS.md`: the brand orange fails AA when used
as a *foreground* colour in light mode. It is pinned by a test that will fail
the moment it's fixed, so it cannot be quietly forgotten.

### Reliability

- **Broken connections heal without a relaunch.** A dropped live listener
  re-attaches on an escalating retry, and returning to the app jumps the queue.
  A user sees "Try again" rather than a list that is silently empty.
- **Failures say which kind they are.** The app distinguishes a
  configuration problem from a genuine refusal and words them differently, so a
  deployment issue doesn't read as a permissions bug.
- **A broken install announces itself.** If the bundled court data can't be
  read, the app says so instead of showing an empty map.

### Test coverage

**99 automated tests across eight suites**, all carrying real coverage — no
scaffold:

| Area | Tests | What it protects |
|---|---|---|
| Games | 21 | Stored shape, capacity, scheduling bounds, roster membership, run visibility |
| Profiles | 17 | Stored shape, search-radius handling, name validation |
| Friend discovery | 16 | Search behaviour, result merging, relationship direction |
| Failure handling | 15 | Reconnection schedule, per-listener recovery, error classification |
| Friendships | 10 | Stored shape, pair identity, request direction |
| Accessibility | 8 | WCAG AA contrast, light and dark |
| Court naming | 6 | Display-name derivation across every screen |
| Client/server parity | 6 | That the app's rules and the server's rules still agree |

The parity suite is worth calling out: several limits are written **twice**, in
the app and in the server's rules. It parses the rules file and fails if either
copy moves alone — a mismatch that would otherwise surface as saves failing in
production.

**Not covered:** the security rules themselves have no automated test of what
they permit. The constants are pinned; the behaviour is not. The friendship
rules were validated by hand once, in August 2026. This is the most significant
gap in the project's assurance and is the top-listed item in `GAPS.md`.

---

## What the app does not do yet

Stated plainly, because a feature that half-exists is worse than one that
doesn't:

- **Invite links can be sent but not opened.** A host can copy a link for a
  private run; a recipient who taps it gets nothing. The receiving half — URL
  handling and the access decision behind it — is unbuilt, so an invite-only run
  currently holds only its host.
- **Waitlists don't promote.** When someone leaves a full run, the freed seat is
  not handed to the first person waiting. This is a deliberate consequence of
  the rule that nobody may write another player's name onto a roster.
- **No live occupancy.** The app knows about *scheduled* runs, not who is at a
  court right now.
- **No notifications.** A friend request or a roster change is visible only when
  the app is open. There is no push infrastructure.
- **Distances are measured from a fixed point in Durham**, not the player's
  actual location. Location permission is requested only so the map can show a
  blue dot.
- **Friends can't see each other's private runs**, and there are no in-app run
  details beyond a card — no player names on a roster, no per-run screen.
- **No account deletion**, no social sign-in, and no host controls for marking a
  run in-progress or complete.
- **The app ships with a placeholder icon**, and the court data's required
  attribution is not yet displayed — an outstanding licensing obligation.

---

## Future enhancements

### Committed — designed, not yet built

These have written designs in `context/plans/` and known implementation paths.

| Enhancement | Value | What it needs |
|---|---|---|
| **Working invite links** | Makes invite-only runs actually usable — today they're a dead end | URL handling, plus a deliberate decision on whether an unguessable link is sufficient authorisation |
| **Friends' runs surfaced** | "Three friends are on this run" is the strongest reason to join one | Client-side only; no backend work |
| **Live court headcount** | Answers "is anyone there *now*", the question the app can't currently answer at all | A new check-in collection and its rules |
| **Queue Up matchmaking** | Turns the app from a scheduler into a way to find a game | The largest item on the roadmap |
| **Multi-city scaling** | The current game query doesn't filter by geography, so it doesn't scale past one metro | A geo-partitioned query and a court-data delivery mechanism |

### Warranted — quality and trust

- **Automated security-rule testing.** The highest-value work not yet done. The
  rules carry the project's most consequential logic and nothing verifies what
  they permit.
- **Device location.** One well-isolated change — every distance in the app
  reads a single value, so pointing it at the device moves all of them.
- **Push notifications**, which would make friend requests and roster changes
  useful rather than merely visible.
- **Safety tooling** — blocking, reporting, and rate limiting. Needed before any
  meaningful growth in users.
- **A private profile area**, so preferences and saved courts stop being
  readable by every signed-in account.
- **Server-side run lifecycle** — automatic completion and waitlist promotion,
  both of which need infrastructure the project has deliberately avoided so far.

### Speculative — worth considering

- Player profiles with skill level and position, and rosters that show names.
- Recurring runs.
- Per-run chat.
- Unique handles, so a display name isn't the only way to identify someone.
- Court ratings and photos.

### A note on sequencing

Several items above are gated on the same decision: **whether the project takes
on server-side infrastructure.** Waitlist promotion, automatic run completion,
rate limiting, push notifications, and a real search-key migration all need code
running with administrative credentials, which the current plan has none of.
That is one decision unlocking six features, and it is worth making
deliberately rather than arriving at by accident.

---

## See also

- `INDEX.md` — the technical dictionary this sits alongside.
- `GAPS.md` — the same limitations, at implementation detail.
- `plans/` — designs for the committed enhancements above.
- `database/DATABASE_SCHEMA.md` — the security model in full.
