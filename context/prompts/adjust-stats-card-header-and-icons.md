# Task: Give the Home stats card a header and per-stat icons

## Goal

`StatsCard` (shipped uncommitted in Phase 3 of
`plans/STATS_CARD_IMPLEMENTATION_PLAN.md`) currently renders as three bare
text columns with no label identifying the card and no visual accent. When
this is done, the card sits under a "YOUR STATS" header — using the exact
same treatment Home already gives "NEXT RUN" and "HOT RIGHT NOW" — and each
of the three stats (Runs / Streak / **Last Run**) carries a small tinted icon
beside its label. `"Last"` alone doesn't say last *what*; `"Last Run"` reuses
the app's own vocabulary for a game session (`LocalRunsViewModel`, `GameCard`,
the "NEXT RUN" section already on this same screen) so the column reads on
its own rather than depending on the card's header for context. No data,
ViewModel, or subscription logic changes; this is a View-layer-only visual
pass.

## Context

- This reverses a specific, deliberate decision from the Phase 3 prompt
  (`context/prompts/implement-stats-card-phase3.md`), which said: *"Not
  wrapped in the `section(_:content:)` helper — unlike 'Next run' and 'Hot
  right now', this card has no uppercase title label, matching the plan's
  original design."* That's being overturned on purpose here — don't read
  the old prompt as still-binding guidance for this task.
- The header is **not** new code inside `StatsCard.swift`. `HomeTab.swift`
  already has a private `section(_:content:)` helper that both "Next run"
  and "Hot right now" use for their uppercase labels (kerned, bold,
  `hooprSecondaryText`, auto-uppercased). The correct fix is to wrap the
  existing `StatsCard(...)` call in that same helper — see Output below.
  This keeps `StatsCard` itself reusable and header-less as a component,
  matching how it's a plain data-in view today; the header is Home's
  labeling convention, not the card's.
- Icons will use `Color.hooprOrange` as their tint, which is `hoopr`'s brand
  accent and the only sensible choice for "give it more impact." Be aware
  this adds a new call site to an **already-tracked** accessibility gap:
  `context/GAPS.md`'s "`hooprOrange` fails WCAG AA as a *foreground* in
  light mode" entry lists every current icon/glyph use of orange-as-foreground
  by name. Read that entry before writing the icon code — not to fix it (out
  of scope here) but because Output below requires adding this card to that
  list, matching the doc's existing discipline of recording every affected
  call site rather than letting new ones go unlisted.

## Input

- `hoopr/Views/Components/StatsCard.swift` — current full contents:

  ```swift
  import SwiftUI

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

- `hoopr/Views/Tabs/HomeTab.swift` — the call site to change (current):

  ```swift
  if viewModel.hasStats {
      StatsCard(
          completedCount: viewModel.completedGameCount,
          participationStreak: viewModel.participationStreak,
          lastCompletedText: viewModel.lastCompletedText
      )
  }
  ```

  And the existing `section(_:content:)` helper it should reuse (already in
  the same file, ~line 97):

  ```swift
  @ViewBuilder
  private func section<Content: View>(
      _ title: String,
      @ViewBuilder content: () -> Content
  ) -> some View {
      VStack(alignment: .leading, spacing: 8) {
          Text(title.uppercased())
              .hooprFont(12, weight: .bold, maximumSize: 16)
              .kerning(0.6)
              .foregroundStyle(Color.hooprSecondaryText)

          content()
      }
  }
  ```

- Constraints:
  - No new dependencies, no new `@Published` properties, no ViewModel
    changes. `HomeViewModel` already publishes exactly what `StatsCard`
    needs; this task doesn't touch it.
  - No new Theme/Typography tokens — `hooprOrange`, `hooprSecondaryText`,
    `hooprPrimaryText`, `hooprBorder`, and `hooprFont(_:weight:)` already
    cover everything this needs.
  - Icons are SF Symbols via `Image(systemName:)`, matching every other
    icon in the app (no custom asset icons anywhere in `hoopr/Views/`).

## Output

- **`hoopr/Views/Tabs/HomeTab.swift`** — wrap the existing `StatsCard` call
  in `section(_:)`, title `"Your Stats"` (the helper uppercases it for
  display, matching `"Next run"` → `"NEXT RUN"`):

  ```swift
  if viewModel.hasStats {
      section("Your Stats") {
          StatsCard(
              completedCount: viewModel.completedGameCount,
              participationStreak: viewModel.participationStreak,
              lastCompletedText: viewModel.lastCompletedText
          )
      }
  }
  ```

  The `if viewModel.hasStats` gate must stay **outside** `section(...)`, not
  inside it — the header must disappear along with the card, not sit above
  an empty one. (The example above already has this right; don't hoist the
  condition.)

- **`hoopr/Views/Components/StatsCard.swift`** — add a `symbol:` parameter
  to the private `stat` helper and pass one per call. Exact shape to match:

  ```swift
  private func stat(symbol: String, label: String, value: String) -> some View {
      VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 4) {
              Image(systemName: symbol)
                  .hooprFont(11)
                  .foregroundStyle(Color.hooprOrange)
                  .accessibilityHidden(true)
              Text(label)
                  .hooprFont(11, weight: .bold)
                  .foregroundStyle(Color.hooprSecondaryText)
          }
          Text(value)
              .hooprFont(15, weight: .semibold)
              .foregroundStyle(Color.hooprPrimaryText)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
  }
  ```

  And the three call sites in `body`, in this exact order — icon choices are
  fixed, not a matter of taste, chosen to avoid colliding with existing
  meanings elsewhere in the app (`"calendar"` already means "Joined" in
  `ProfileView`; `"basketball.fill"` already means "a run" everywhere else,
  which is why it's reused here rather than avoided). The third label also
  changes from `"Last"` to `"Last Run"` — see Goal for why:

  ```swift
  stat(symbol: "basketball.fill", label: "Runs", value: "\(completedCount)")
  Divider().overlay(Color.hooprBorder)
  stat(symbol: "flame.fill", label: "Streak", value: "\(participationStreak) wks")
  Divider().overlay(Color.hooprBorder)
  stat(symbol: "clock.fill", label: "Last Run", value: lastCompletedText)
  ```

  Check the rendered width on-device once "Last Run" is in place — it's two
  words where the other two columns are one, and the column is narrower now
  that it also carries an icon. If it wraps or crowds the value below it,
  reduce the icon+label `HStack`'s `spacing` before considering a shorter
  label; don't silently revert to `"Last"` without flagging that the two-word
  label doesn't fit.

- **`context/GAPS.md`** — add `StatsCard`'s three icons to the "Affected"
  list in the `hooprOrange` WCAG AA accessibility entry (search for
  `**`hooprOrange` fails WCAG AA as a *foreground*`**`). Append to the
  existing "Affected:" sentence rather than starting a new bullet — match
  the entry's own pattern of dated inline updates (see how the tab-bar
  consequence was appended to that same entry on 2026-08-26).

- **No test changes.** This repo has no view-rendering/snapshot test
  infrastructure (`hooprTests/HomeViewModelTests.swift` only covers pure
  `HomeViewModel` logic), and this task touches no logic — only `View`
  bodies. Verify by hand on-device per Test Cases below, the same way Phase
  3's card placement was verified.

- Success criteria:
  - `xcodebuild … build` succeeds.
  - `xcodebuild … test -only-testing:hooprTests` still passes at whatever
    count it's currently at — this task adds zero new test methods and
    should break none.
  - The three manual checks in Test Cases below pass on a real simulator
    run.

## Decision Rules

- If the exact header string ever needs to change from `"Your Stats"`,
  that's a one-word edit to the `section("Your Stats")` call — nothing else
  depends on the literal string.
- If a future screen wants to reuse `StatsCard` without a header, it still
  can — the header lives in `HomeTab`'s wrapping, not in the component. Keep
  it that way; don't fold an optional header parameter into `StatsCard`
  itself for a need that doesn't exist yet.
- If SF Symbol rendering looks off for any of the three glyphs once seen
  on-device (wrong optical weight next to the 11pt label, wrong baseline
  alignment), fix the icon's `hooprFont` size only — don't change which
  three symbols are used without checking with whoever asked for this
  first, since `basketball.fill` / `flame.fill` / `clock.fill` were chosen
  deliberately to avoid colliding with existing icon meanings elsewhere.

## Error Handling

- If `Image(systemName:)` is given a symbol name that doesn't exist on the
  deployment target's SF Symbols version, it silently renders as nothing
  (empty space) rather than crashing or showing a placeholder glyph — this
  will look like a layout bug, not a build error. All three names here
  (`basketball.fill`, `flame.fill`, `clock.fill`) are stable, pre-iOS-15 SF
  Symbols, so this shouldn't trigger — but confirm all three actually render
  in the simulator screenshot before calling this done, don't just trust
  that the symbol name compiles.
- If wrapping `StatsCard` in `section(_:)` changes the outer `VStack`'s
  spacing in a way that reads as too tight or too loose next to "Next run"
  below it, that's expected and matches how "Next run" and "Hot right now"
  already space against each other — don't add extra padding to compensate
  without comparing against how those two already look stacked.

## Wait vs. Stop

- **Wait for input if:** the rendered icons or header, seen live on-device,
  look visually wrong in a way this prompt didn't anticipate (spacing,
  sizing, an icon reading as the wrong metaphor) — pause and show a
  screenshot before iterating on alternatives, rather than guessing through
  several icon/size changes unreviewed.
- **Stop and report if:** `HomeTab.swift`'s `section(_:content:)` helper has
  changed shape or been removed since this prompt was written (check it
  still matches the Input snippet above before relying on it) — that would
  mean this prompt is stale against the current file, not that the approach
  is wrong.

## Chain-of-Thought

Before editing either file, explain:
1. Why the header is added by wrapping the existing `section(_:)` call in
   `HomeTab.swift` rather than adding title-rendering code inside
   `StatsCard.swift`.
2. Why `hooprOrange` is an acceptable icon tint here despite the known
   contrast gap, and confirm the `GAPS.md` update is part of this same
   change, not a follow-up.
3. Why each icon is marked `.accessibilityHidden(true)` — what a VoiceOver
   user would hear if it weren't.

Then make the changes.

## Model Recommendation

**Sonnet** — single-file-plus-one-call-site visual change with no new
architecture, but touching an accessibility-tracked color and a
documentation update means it's worth more care than a pure one-line fix.

## Test Cases

1. **Card visible.** With `completedGameCount > 0` (see
   `context/prompts/implement-stats-card-phase3.md`'s Testing section for
   how to hand-set this on a real profile), Home shows a "YOUR STATS" header
   in the same style as "NEXT RUN," directly above the three-column card.
   Each column shows its icon (basketball/flame/clock) immediately to the
   left of its label — "Runs", "Streak", "Last Run" — tinted orange, sized to
   sit comfortably beside the 11pt label text without crowding it or
   wrapping the two-word "Last Run" label.
2. **Card hidden.** With the three profile fields cleared, neither "YOUR
   STATS" nor the card renders — confirm the header disappears with the
   card, not just the card's content.
3. **VoiceOver.** Swipe through the card with VoiceOver on; each stat reads
   as its label and value only (e.g. "Runs, 12") — the icon must not be
   announced as a separate element ("basketball, image" or similar).
