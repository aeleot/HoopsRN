# hoopsRN — Product Overview

**Scope:** —
**Verified:** 2026-09-16 @ 8209408

What the app does today, stated in business terms: what a person can actually
accomplish in it, what it guarantees about their data, and what is deliberately
not built yet. This is the document to hand someone who needs to understand the
product without reading the code.

It owns no source paths, so the drift check lists it under *always revisit*
rather than telling you when it went stale — re-read it by hand whenever a
feature ships, alongside `GAPS.md`.

*(Until 2026-09-16 this file sat in a directory whose name contained literal
backslashes, which meant the drift check couldn't see it at all and the
dictionary's link to it was dead. It had gone badly stale in the meantime —
worth knowing if an older copy is ever compared against this one.)*

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
  map, or as a distance-sorted list. **Every pin is one court.** Pins are never
  grouped into a numbered bundle; zoomed out, the map thins itself by drawing
  fewer pins rather than by merging them, so what you see is always individual
  courts you can tap.
- **See how busy a court is today at a glance.** Every pin is coloured on a
  five-step, all-orange scale that starts at the brand orange (nothing
  scheduled) and darkens step by step to a saturated reddish orange (several
  runs booked) — today's game count at that court, not a static rating. This
  reads only games the account could already see elsewhere in the app — a
  public run, or one it's personally on — so it never reveals a private run
  belonging to someone else.
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

### Play a season match

- **Form a squad** — name it, pick a crest from a fixed palette, and invite
  friends to it. Squads are built from people you're already friends with, not
  from strangers.
- **Queue up for a match**, choosing which courts you'll travel to and the
  window you're free in. The app pairs your squad with another queued squad
  nearby, picking a court and a tip-off time both squads actually offered.
- **See the match, and who you're playing**, with the opponent's crest and
  their season record.
- **Mark your squad as arrived** on game day, so both sides can see who's at
  the court.
- **Report who won.** A result only counts once *both* leaders report the same
  winner; if they disagree the match is disputed and counts for nobody until
  someone re-reports. A squad's win-loss record is derived from matches both
  sides agreed on — it is not a number anyone can type.

Matchmaking runs entirely between the two phones involved; there is no server
pairing squads. A match and both squads' queue entries are written in a single
transaction, so two squads that pick each other at the same instant produce one
match rather than two.

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
| Squads | Any signed-in user — an opponent has to be able to see who they're playing | The leader names and disbands it; every member adds or removes **only themselves** |
| Squad invites | The leader who sent it and the person invited | Only a leader may send one, and only to an accepted friend; either side may delete it |
| Queue entries | Any signed-in user — a matchmaking pool is public by definition | The squad's leader creates and withdraws it; it can be spent on a match exactly once |
| Season matches | Any signed-in user — records are the point of the feature | Created only by a write that spends both squads' queue entries; each leader may report **only their own** result, and may never delete a match |

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

Specific to season play:

- **A squad is in at most one live match**, enforced by the server rather than
  by the app: a queue entry can be spent exactly once, and the match and both
  entries are written together or not at all.
- **Forging a win takes two colluding squads**, not one modified client. A
  result is only recorded when both leaders independently name the same winner.

**Known limits, stated honestly:** there is no blocking, reporting, or rate
limiting on friend requests. Anyone signed in can find anyone and ask once;
declining is the only recourse, and nothing stops them asking again.

Queue entries and result reports carry short server-side cooldowns (added
2026-09-16) that bound how fast they can be repeated — but these slow bursts
rather than preventing abuse, and none of them survives someone simply making
a new account, because sign-up has no verification step. Real rate limiting,
blocking and reporting all need infrastructure the project doesn't have yet.

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
the moment it's fixed, so it cannot be quietly forgotten. The orange itself was
softened on 2026-08-21 — a visual-only change, same hue, less saturated — ahead
of a planned broader colour-scheme revision; it does not touch this gap and was
not intended to.

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

**Two suites, in two languages**, and neither can do the other's job. All of it
carries real coverage — there is no scaffold.

| Suite | Tests | What it protects |
|---|---|---|
| **App logic** (`hooprTests`) | 438 across 28 suites | Every stored shape and every rule the app applies before it writes: capacity and scheduling bounds, roster membership, matchmaking's ranking and its claim policy, the matchmaking card's state, result derivation, WCAG contrast, court naming and badges, error classification, reconnection. |
| **Security rules** (`firestore-tests`) | 102 | What the server actually *permits*, evaluated against the Firestore emulator rather than read. Includes the matchmaking race run 15 rounds in both shapes, the atomic match commit, and the rate-limit floors at their exact boundaries. |

Two things are worth calling out. **A rules dry-run is not a test** — it
compiles the file and proves nothing about whether a write is allowed, which is
why the emulator suite exists. And several limits are written **twice**, in the
app and in the server's rules; a parity suite parses the rules file and fails if
either copy moves alone, a mismatch that would otherwise surface as saves
failing in production.

**Not covered:** the emulator suite covers season play only — it was built
during the phase that needed it. The rules for profiles, runs and friendships
have no automated test of what they permit; the friendship rules were validated
by hand once, in August 2026, which proves they were correct that day and
nothing about the next edit. Backfilling those three is the cheapest remaining
assurance work in the project, and is tracked in `gaps/TESTING.md`.

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
- **Notifications are local only.** A scheduled season match sets reminders on
  the device that saw it. There is no push infrastructure, so a friend request
  or a roster change is still visible only when the app is open — and a squad
  member whose app never opens between being matched and tip-off gets no
  reminder at all.
- **Coverage stops at six Triangle cities.** Distances follow the device as of
  August 2026, so someone outside those cities now correctly sees an empty map
  rather than a wrong one — which is a data-coverage problem rather than a
  location one.
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
| **Multi-city scaling** | The current game query doesn't filter by geography, so it doesn't scale past one metro | A geo-partitioned query and a court-data delivery mechanism |

### Warranted — quality and trust

- **Security-rule testing for the original three collections.** The harness
  exists and covers season play; profiles, runs and friendships are still
  unverified.
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

- [`INDEX.md`](INDEX.md) — the technical dictionary this sits alongside.
- [`GAPS.md`](GAPS.md) — the same limitations, at implementation detail, routing
  into [`gaps/`](gaps/).
- [`ROADMAP.md`](ROADMAP.md) — the order the work above would actually be done
  in, and the one infrastructure decision that gates much of it.
- [`plans/`](plans/) — designs for the committed enhancements above.
- [`database/DATABASE_SCHEMA.md`](database/DATABASE_SCHEMA.md) — the security
  model in full.
