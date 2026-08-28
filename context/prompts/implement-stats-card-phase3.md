# Implement — Home stats card, ViewModel + UI (Plan Phase 3)

Build the display layer for participation stats: `HomeViewModel` publishing
them, a new `StatsCard` component, and its conditional placement on Home.
This is Phase 3 of `plans/STATS_CARD_IMPLEMENTATION_PLAN.md`. Phases 1
(schema/rules) and 2 (services/streak calculation) are already complete and
sitting uncommitted in the working tree — do not redo them, and do not touch
the files they own (see Scope).

**Read `plans/STATS_CARD_IMPLEMENTATION_PLAN.md` §6 and §7 before writing
anything**, plus the current `hoopr/ViewModels/HomeViewModel.swift` and
`hoopr/Views/Tabs/HomeTab.swift` in full. The plan's code snippets in those
two sections are illustrative pseudocode written before Phases 1–2 landed —
some of it doesn't match the real APIs in this codebase (`hooprFont`'s actual
signature, the fact that `HomeViewModel` already has a dependency-injected
`userProfileService` and an established one-subscription-per-concern Combine
style). **Where this prompt's Conventions section disagrees with the plan's
snippets, this prompt wins** — it was written against the files as they
actually stand. Where you find a *third* disagreement this prompt didn't
anticipate, stop and flag it rather than silently picking a side.

One framing note carried over from the last change: the schema stores no
win/loss data at all, by deliberate decision — `Game` has no
`winningTeamSize` or equivalent. The stats card shows attendance only
(`Runs` / `Streak` / `Last`). Don't reach for outcome data anywhere in this
phase; it doesn't exist.

---

## Scope

**Build:**
- `hoopr/ViewModels/HomeViewModel.swift` — three new `@Published` properties
  (`completedGameCount`, `participationStreak`, `lastCompletedText`), a
  `hasStats` computed property, a new dedicated Combine subscription to
  `userProfileService.$currentProfile` that publishes them, and a pure
  `nonisolated static func lastCompletedText(for:relativeTo:)` formatter —
  see Conventions for the exact shape of each.
- `hoopr/Views/Components/StatsCard.swift` — new file. Three-column card
  (Runs / Streak / Last), text-only, built on the existing `cardChrome()`
  and `hooprFont` conventions — see Conventions for the exact shape.
- `hoopr/Views/Tabs/HomeTab.swift` — render `StatsCard` conditionally after
  `header`, before `section("Next run")`. Also update the type's doc comment
  (currently lines 3–13), which still says "there is deliberately no stats
  card" — that's now false. Replacement text is in Conventions.
- `hooprTests/HomeViewModelTests.swift` — new tests for the
  `lastCompletedText` static formatter, following the file's existing
  `rankHotCourts` tests as the pattern (pure function, no service
  construction) — see Testing.

**Do not build:**
- Any change to `hoopr/Services/GameService.swift`,
  `hoopr/Services/UserProfileService.swift`, `hoopr/Models/Game.swift`,
  `hoopr/Models/UserProfile.swift`, `firestore.rules`, or
  `firestore.indexes.json`. Phases 1–2 are done and stable; this phase only
  *reads* what they already publish (`GameService` isn't even touched here —
  `HomeViewModel` already wired the completed-games → `refreshStats` trigger
  in Phase 2). If something here seems to require touching one of those
  files, that's a sign this phase's scope is being misread — stop and ask.
- Any SwiftUI view-rendering or snapshot test. Verified absent from this
  project: no ViewInspector, no SnapshotTesting, no `Package.resolved`
  pinning either, and no existing test file renders a view and asserts on
  it. Don't add that infrastructure speculatively as part of this task — it's
  a separate decision with its own tradeoffs. Test the pure formatter logic
  only (see Testing), and verify the view itself by hand on-device.
- A "mark game complete" UI of any kind. That's the still-unbuilt external
  dependency the plan's own §14 flags — without it, `completedGames` stays
  empty for every real account and the card won't appear organically. Not
  this phase's problem to solve; see Testing for how to verify the card
  anyway.
- Any win/loss UI, label, or field. Already covered above — restating
  because it's the most likely accidental scope creep given "Runs" sits next
  to where a win count might otherwise go.

---

## Order of work

1. Add `lastCompletedText(for:relativeTo:)` to `HomeViewModel` first — it's
   pure and has no dependencies, so it can be written and hand-verified
   before anything else changes.
2. Add the three `@Published` properties and `hasStats`.
3. Add the dedicated stats subscription in `init` (Conventions has the exact
   shape — don't fold this into the existing `greetingName` subscription).
4. Build (`xcodebuild -project hoopr.xcodeproj -scheme hoopr -destination
   'platform=iOS Simulator,name=iPhone 17' build`) and confirm it compiles
   clean before touching the View layer.
5. Write `StatsCard.swift`.
6. Wire it into `HomeTab.swift`; update the stale doc comment.
7. Write the `HomeViewModelTests.swift` additions — last, once the formatter
   is settled, not before.
8. Run the full suite (`xcodebuild … test`) and confirm 0 failures. The
   suite was at 208 tests passing before this phase; expect that plus
   whatever you add for `lastCompletedText`.
9. Do the manual on-device check in Testing — this is the only way to see
   the card at all, given point 3 of "Do not build" above.

---

## Conventions to match exactly

### The stats subscription

A **separate** subscription from the existing `userProfileService
.$currentProfile` one that drives `greetingName` (around line 94 currently)
— this file's established style is one subscription per concern
(`authService` → uid, `friendService` → count, `courtService` → rebuild,
etc.), and stats is its own concern. Don't extend the greeting sink to also
set stats fields.

Bare Swift tuples aren't `Equatable`, so `.removeDuplicates()` needs a small
wrapper type:

```swift
private struct ProfileStats: Equatable {
    let count: Int
    let streak: Int
    let lastCompletedAt: Date?
}
```

```swift
userProfileService.$currentProfile
    .map { profile in
        ProfileStats(
            count: profile?.completedGameCount ?? 0,
            streak: profile?.participationStreak ?? 0,
            lastCompletedAt: profile?.lastCompletedAt
        )
    }
    .removeDuplicates()
    .receive(on: DispatchQueue.main)
    .sink { [weak self] stats in
        self?.completedGameCount = stats.count
        self?.participationStreak = stats.streak
        self?.lastCompletedText = Self.lastCompletedText(for: stats.lastCompletedAt)
    }
    .store(in: &cancellables)
```

**The `?? 0` / `nil` defaults are load-bearing, not incidental** — cover both
of these explicitly:
- **Lazy init**: `completedGameCount`/`participationStreak` are `Int?` on
  `UserProfile`, absent until the account's first `refreshStats` write. A
  brand-new or pre-migration profile must read as `0`/`0`/`"—"`, not crash
  and not show stale placeholder text.
- **Sign-out**: `UserProfileService.stopObserving()` sets `currentProfile =
  nil` on sign-out (confirmed in the current source). This subscription must
  reset to the same `0`/`0`/`"—"` defaults when `profile` is `nil` — the
  `?? 0` inline in the `map` already does this, but don't lose it if you
  restructure. Without it, signing out and back in as a different account
  would flash the previous account's stats for one frame.

### `lastCompletedText`

`nonisolated static`, same shape as `rankHotCourts` — pure, testable without
constructing a service:

```swift
nonisolated static func lastCompletedText(for date: Date?, relativeTo now: Date = Date()) -> String {
    guard let date else { return "—" }
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Today" }
    if calendar.isDateInYesterday(date) { return "Yesterday" }
    return lastCompletedDateFormatter.string(from: date)
}

private static let lastCompletedDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("MMMd")
    return formatter
}()
```

Two deliberate choices, both worth a short comment in the code, not just
here:
- **`Calendar.current`, not UTC.** This is different from
  `Game.calculateStreak`'s `Calendar(identifier: .iso8601)` +
  `TimeZone(identifier: "UTC")` on purpose — that one buckets weeks for a
  server-trusted count that has to agree across devices; this one is
  displaying a single date to the person looking at their own phone, the
  same reasoning `Game.scheduledText(relativeTo:)` already uses
  `Calendar.current` for.
- **No year, ever** (`"MMMd"`, not `"MMMdyyyy"` or `"EEEMMMd"`). A completion
  from last year still reads as e.g. `"Aug 15"`. This is a simplification,
  not an oversight — don't add a year-conditional without checking with the
  user first, since it changes the visual width of the "Last" column.

### `StatsCard.swift`

```swift
import SwiftUI

/// Three-column summary of participation stats — Home's one historical
/// card. Text-only, built on `cardChrome()` so it reads as the same surface
/// as every other card on the screen.
struct StatsCard: View {
    let completedCount: Int
    let participationStreak: Int
    let lastCompletedText: String

    var body: some View {
        HStack(spacing: 16) {
            stat(label: "Runs", value: "\(completedCount)")
            Divider().overlay(Color.hooprBorder)
            stat(label: "Streak", value: "\(participationStreak) wks")
            Divider().overlay(Color.hooprBorder)
            stat(label: "Last", value: lastCompletedText)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .cardChrome()
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .hooprFont(11, weight: .bold)
                .foregroundStyle(Color.hooprSecondaryText)
            Text(value)
                .hooprFont(15, weight: .semibold)
                .foregroundStyle(Color.hooprPrimaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

`.overlay(Color.hooprBorder)` on both `Divider()`s matches how
`hotCourtsCard` draws its row dividers in `HomeTab.swift` — don't leave the
bare system-colored default. Exact padding/spacing values above may be
adjusted for visual balance once it's on a real device; the API usage
(`cardChrome()`, `hooprFont`, the color tokens) is the actual contract, not
the pixel values.

### HomeTab integration

Not wrapped in the `section(_:content:)` helper — unlike "Next run" and "Hot
right now", this card has no uppercase title label, matching the plan's
original design:

```swift
header

if viewModel.hasStats {
    StatsCard(
        completedCount: viewModel.completedGameCount,
        participationStreak: viewModel.participationStreak,
        lastCompletedText: viewModel.lastCompletedText
    )
}

section("Next run") {
    ...
```

### The stale doc comment

`HomeTab.swift`'s type doc comment currently ends with: *"There is
deliberately no stats card: nothing records that a run happened yet, so
'runs this week' and a streak have no honest source."* Replace the whole
comment with:

```swift
/// The Home tab: what you're committed to, then where the action is.
///
/// The app used to open on the map. The map answers "where can I hoop?" — a
/// question you only have once you've already decided to go out. It can't
/// answer "am I signed up for something tonight?", which is the more common
/// reason to open the app at all, so that answer is what this screen leads
/// with.
///
/// The stats card is the one historical note on an otherwise forward-looking
/// screen — participation stats sourced from the profile snapshot
/// `HomeViewModel` already holds, not computed here. It's hidden entirely
/// until `hasStats` is true, so a brand-new account sees the same screen it
/// always has. See `HomeViewModel`.
```

---

## Testing

**Unit** — additions to `hooprTests/HomeViewModelTests.swift`, matching its
existing `rankHotCourts` tests: pure function, fixed `Date`s, no service
construction.

| Test | Guards |
|---|---|
| `nil` date → `"—"` | the lazy-init / brand-new-account default |
| today's date → `"Today"` | |
| yesterday's date → `"Yesterday"` | |
| two days ago → the formatted month/day string, not `"Today"`/`"Yesterday"` | the boundary between the two relative cases and the absolute fallback |
| a date from over a year ago → still just month/day, no year | pins the deliberate no-year simplification so it can't drift in silently |

**Manual, one device** — there's no completion-marking UI yet (see Scope),
so the only way to see the card is to hand-edit a profile document in the
Firebase console:

1. Pick a signed-in test account's `users/{uid}` document. Set
   `completedGameCount: 12`, `participationStreak: 3`, and `lastCompletedAt`
   to today's server timestamp. Relaunch Home. Confirm the card renders
   with `"12"` / `"3 wks"` / `"Today"`.
2. Clear those three fields (or use a different, untouched account).
   Confirm the card is absent entirely — not just empty, gone — and the rest
   of Home lays out exactly as it did before this phase.
3. Sign out of the account from step 1 and into the account from step 2 (or
   vice versa) without force-quitting. Confirm the card's visibility and
   values update to the newly-signed-in account rather than holding onto
   the previous one for a frame.

---

## Definition of done

- `xcodebuild … build` succeeds.
- `xcodebuild … test` succeeds, 0 failures, including the new
  `lastCompletedText` tests.
- All three manual checks above pass on a real simulator run — not just
  reasoned about.
- Nothing outside Scope was touched — in particular, no edits to
  `GameService.swift`, `UserProfileService.swift`, `Game.swift`,
  `UserProfile.swift`, `firestore.rules`, or `firestore.indexes.json`.
- Changes are **not committed** — left staged/unstaged for review, matching
  how this whole effort has been handled so far.

## Report back

Close with:

1. **Files created/changed**, one line each.
2. **The three manual verification results**, pass/fail — name what each one
   actually showed, not just "verified."
3. **Anything in `plans/STATS_CARD_IMPLEMENTATION_PLAN.md` §6/§7, or in this
   prompt's Conventions section, that didn't fit once you actually built
   it.** Flag it plainly rather than silently improvising past it.
4. **Confirmation that Phases 4–5** (manual cross-device testing, rules-parity
   coverage for the new profile/game fields, and the `ARCHITECTURE.md` /
   `BUILD_AND_CONFIG.md` / `DATA_MODEL.md` doc updates) **were left
   untouched.**
