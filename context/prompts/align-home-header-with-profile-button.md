# Task: Realign the Home header with the profile button

## Goal

On the Home tab, the greeting text ("Let's go hoop {name}.") vertically
aligns with `ProfileButton` the same way "Runs" already aligns with its
`ProfileButton` on the Local Runs tab — text sits centered against the
button's height rather than pinned to its top edge. The greeting always
renders as one line, at every realistic name length, and is never
clipped/truncated.

## Context

- `HomeTab`'s header (`HomeTab.swift`'s `header` property, ~line 92-104)
  currently uses `HStack(alignment: .top)` with
  `.fixedSize(horizontal: false, vertical: true)` on the greeting `Text`,
  which lets the text grow to a second line rather than truncate for a long
  name. `LocalRunsTab`'s header (`LocalRunsTab.swift`'s `header` property,
  ~line 89-103) uses `HStack(alignment: .center)` for the same text+button
  pairing, and its title never wraps because "Runs" is a fixed four-character
  string.
- `ProfileButton`'s tap target is a fixed 44×44pt frame (`ProfileButton.swift`);
  the 28pt bold greeting text's own line height is shorter than that, so
  under today's `.top` alignment the text sits high against the button
  rather than centered against it — that's the visual mismatch being fixed.
  Switching to `.center` alone will visibly push the greeting down, which is
  the "move the header down a bit" the requester described.
- A prior manual attempt at this (outside this session) was reported as
  "really buggy." The likely cause: switching alignment to `.center` alone,
  without also pinning the greeting to a single line, lets a long `userName`
  (up to 50 characters — see `firestore.rules`'s `userName.size() <= 50`)
  wrap to two lines under `.center` alignment, which unpredictably shifts the
  button's vertical position relative to the text frame to frame as
  `greetingName` changes. Forcing a single line via `.lineLimit(1)` +
  `.minimumScaleFactor` removes that instability at the root, rather than
  patching alignment around it.
- `greetingName` is `UserProfile.userName` verbatim (`HomeViewModel.swift`,
  ~line 114), capped at 50 characters by `firestore.rules` and
  `UserProfile.validate(userName:)` (`UserProfile.swift`, ~line 116) — so the
  shrink-to-fit path below has to handle up to a 50-character name, not just
  typical short ones.
- Decided with the requester up front: long names shrink to fit rather than
  wrap to a second line or truncate with an ellipsis — chosen specifically
  because it's the only option that keeps the greeting both one line *and*
  fully visible, which were both explicit requirements.

## Input

- File: `hoopr/Views/Tabs/HomeTab.swift`
- Current `header` (verbatim):

  ```swift
  private var header: some View {
      HStack(alignment: .top) {
          Text("Let's go hoop \(Text(viewModel.greetingName).fontWeight(.bold)).")
              .hooprFont(28, maximumSize: 40)
              .foregroundStyle(Color.hooprPrimaryText)
              .fixedSize(horizontal: false, vertical: true)

          Spacer(minLength: 8)

          ProfileButton(friendService: friendService, action: onOpenProfile)
              .offset(x: 8)
      }
      .padding(.top, 8)
  }
  ```

- Reference — `LocalRunsTab`'s header, the pattern being matched for
  alignment (not for padding structure — see Constraints):

  ```swift
  private var header: some View {
      HStack(alignment: .center) {
          Text("Runs")
              .hooprFont(28, weight: .bold, maximumSize: 40)
              .foregroundStyle(Color.hooprPrimaryText)

          Spacer(minLength: 8)

          ProfileButton(friendService: friendService, action: onOpenProfile)
              .offset(x: 8)
      }
      .padding(.horizontal, 20)
      .padding(.top, 8)
      .padding(.bottom, 4)
  }
  ```

- Constraints:
  - Don't touch `LocalRunsTab.swift` — it's the reference, not part of the
    change.
  - Don't move horizontal padding into `header` the way `LocalRunsTab` has
    it. `HomeTab`'s horizontal padding is applied once, on the outer
    `VStack` in `body`, and covers every section on the screen (stats card,
    "Next run", "Hot right now", the friend request banner). Duplicating
    `.padding(.horizontal, 20)` onto `header` alone would double that
    padding for the header row specifically. Match `LocalRunsTab` on
    **alignment**, not on **padding structure** — those are separate, and
    only the first is what "align with the profile button" is asking for.
  - No ViewModel changes. `greetingName` is already exactly what's needed.
  - No new Theme/Typography tokens.

## Output

- **`hoopr/Views/Tabs/HomeTab.swift`** — modify `header`:
  - `HStack(alignment: .top)` → `HStack(alignment: .center)`.
  - On the greeting `Text`: replace
    `.fixedSize(horizontal: false, vertical: true)` with `.lineLimit(1)` and
    `.minimumScaleFactor(0.65)` — the line limit is what makes `.center`
    alignment stable (see Context), and the scale factor is what keeps a
    long name fully visible without a second line. `0.65` is a starting
    value, not a fixed requirement — see Decision Rules below for what to do
    if it looks wrong on-device.
  - Leave `.padding(.top, 8)` as-is unless the on-device check in Test Cases
    below shows the row still needs a nudge — see Decision Rules.
- **No test changes.** This mirrors the earlier stats-card header change:
  `hooprTests/` has no view-rendering coverage, and this is a
  `View`-body-only change. Verify by hand on-device per Test Cases below.
- Success criteria:
  - `xcodebuild … build` succeeds.
  - `xcodebuild … test -only-testing:hooprTests` still passes at its current
    count.
  - The three manual checks in Test Cases below pass on a real simulator
    run.

## Decision Rules

- If `0.65` as the `minimumScaleFactor` floor makes a long (near-50-character)
  name unreadably small next to the button, raise the floor (e.g. `0.75`)
  rather than abandoning shrink-to-fit for that case — shrink-to-fit was
  chosen specifically over wrapping or truncating, so a smaller-but-legible
  line beats a second line or an ellipsis for this task.
- If, after switching to `.center` and single-lining the text, the row still
  doesn't look "moved down" against the button (e.g. because the button's own
  glyph padding already centers visually), adjust `.padding(.top, 8)` upward
  slightly rather than changing the alignment strategy again — the alignment
  change is the structural fix; padding is the fine-tune.
- If ambiguity arises about how far down is "a bit" — there's no numeric
  target given — match `LocalRunsTab`'s vertical rhythm (`.padding(.top, 8)`
  there too) as the default target, since that's the tab explicitly named as
  the reference.

## Error Handling

- If `.minimumScaleFactor` is applied without `.lineLimit(1)` on the same
  `Text`, SwiftUI has nothing to scale against and the modifier is a no-op —
  both must land together, not `.minimumScaleFactor` alone.
- If a name is short (the common case), `.minimumScaleFactor(0.65)` never
  engages — SwiftUI only shrinks when the untruncated line would overflow the
  available width, so short greetings render at the full 28pt exactly as they
  do today. Don't add a separate short-name/long-name code branch; the single
  `Text` modifier chain already covers both.
- If `viewModel.greetingName` is still the fallback `"there"` (pre-profile-load
  state), it's short and behaves like any other short name — no special case
  needed.

## Wait vs. Stop

- **Wait for input if:** the rendered header, seen live on-device with a long
  test name, looks visually wrong in a way this prompt didn't anticipate (the
  shrunk text reads as awkwardly small, the button and text still don't look
  aligned) — pause and show a screenshot before iterating through several
  scale-factor values unreviewed.
- **Stop and report if:** `LocalRunsTab.swift`'s `header` no longer matches
  the Input snippet above (alignment, padding, or structure changed since
  this prompt was written) — that means the reference this task is matching
  against has moved, not that the approach is wrong.

## Chain-of-Thought

Before editing `HomeTab.swift`, explain:
1. Why switching to `.center` alignment alone (without also single-lining the
   text) would reproduce the "buggy" behavior from the earlier manual
   attempt.
2. Why `.lineLimit(1)` + `.minimumScaleFactor` is the mechanism chosen over
   wrapping or truncation, given the up-to-50-character `userName` ceiling.
3. What visually changes for a short greeting (the common case) versus a
   near-50-character one, under the new code.

Then make the change.

## Model Recommendation

**Sonnet** — a single-file, single-property visual tweak, but the
shrink-to-fit interaction with Dynamic Type and the "why did the last attempt
break" root-causing are worth more care than a one-line fix.

## Test Cases

1. **Short name (common case).** With a normal-length `userName` (e.g.
   "Alex"), the header renders "Let's go hoop **Alex**." on one line,
   vertically centered against `ProfileButton`, sitting visibly lower than
   it does today — matching how "Runs" centers against the button on the
   Local Runs tab.
2. **Long name (edge case).** With a `userName` at or near the
   50-character ceiling, the greeting still renders as a single line —
   smaller text, not a second line and not an ellipsis — and remains fully
   readable.
3. **Dynamic Type.** With the system text size turned up (Settings →
   Accessibility → larger text, or the simulator's equivalent), the header
   still reads as one line for a short name and doesn't clip the profile
   button off the trailing edge.
