# hoopsRN — Accessibility gaps

**Scope:** —
**Verified:** 2026-09-21 @ 1a2710d

What is still open about accessibility: one colour-only cue, the pairings the
test suite doesn't pin, and the checks that have never been run live.

`Scope: —` because this is a narrative over `Theme.swift` and the view tree,
which `UI_SHELL.md` owns. It can't be diffed, so it's re-read by hand every
pass.

---

## The form guide's order is colour-only by default

Seasons' last-five form is five dots, green for a win and red for a loss (the
user's call, 2026-09-22). To a red-green colour-blind reader two fills differ
only in lightness. WCAG accepts that as a second cue at 3:1 between them, and
**no pair reaches it while both dots clear 3:1 on the band**: 1.95:1 in light
and 2.25:1 in dark at best (`ThemeContrastTests` pins the gap). So with default
settings that reader gets the **counts** from the record numeral beside the dots
but not the **order**. VoiceOver reads the order. iOS's *Differentiate Without
Color* marks each played dot with a ✓ or ✕, and that is the fix today. Squad
detail's history list does not have this gap: every row spells its result out
("Won", "Lost") beside the dot. If it
should hold without the setting, the next step is a shape cue drawn always
(for example a hollow loss dot). That's a design call, not a retune. Detail in
`UI_SHELL.md` → *The crest and the form guide*.

---

## What the suite does not assert

Not failures — pairings the interface draws that no test pins, so nothing would
catch a later retune breaking them. Measured by hand on 2026-09-21:

- **`ErrorBanner`'s red text on its 8% red wash** — 5.82:1 light, 6.96:1 dark.
- **Glass chrome over the moving map** — the filter chips' labels, the recenter
  glyph, the search field. A translucent surface has no fixed ground to
  measure; the fallback tint's 0.55 opacity is justified in a comment in
  `Glass.swift`, not asserted.
- **What the iOS 26 tab bar finally paints.** The system adjusts a tint before
  drawing it, so the value the code hands over is not the value on screen, and
  `testTabBarSelectionClearsAA` can only assert the nominal one. Sampled from
  the live app, the selected item (`hooprBrandAccent`) measures **5.32:1 in
  light** (`#AF3706` on `#EDEDED`) and 4.98:1 in dark (`#FF8C68` on `#3A3A3A`).
  Re-sample from a screenshot whenever the tint changes.
- **The busy-court glow and the confetti** are decorative, with nothing drawn on
  them, so they assert no pairing — but the confetti falls across the result
  band's text for about a second.

---

## What is not a gap

Stated so it isn't re-investigated: the pairings that carry text — the text
roles on every surface, the brand accent on every ground a mark sits on
(including both orange washes), red on every surface, the crest glyphs, every
heat tier against its label, badges on their washes — are asserted at 4.5:1 in
**both** appearances by `ThemeContrastTests`, and the build fails if one slips.
Dynamic Type is supported throughout, light and dark are both first-class, and
VoiceOver labels are set on controls whose meaning is carried by an icon or a
badge — including the Seasons crest-vs-crest row, where the *row* carries the
label because two decorative glyphs otherwise say nothing. Every filled button
has a 44pt target (`HooprButtonStyle`), and every `RunStatus` badge and button
role is asserted on the grounds it's drawn on.

---

## Live pass, 2026-09-25: what was checked, and what still isn't

The UI revamp (2026-09-21 → 24) rebuilt every screen. On 2026-09-25 the
simulator pass was run (iPhone 17, iOS 26.5), each screen below in **dark and
light, at the default size and `.accessibility3`**: Home, Runs, Map with its
court card, Seasons, squad detail, Profile (both panes), the inbox and the
Start a Run sheet. It found — and fixed — three defects: the court card's
action buttons broke mid-word at `.accessibility3`, every text field's
placeholder read under AA (1.5:1 in light), and the Runs card's two buttons sat
20pt apart. **Reduce Motion** was checked on the squad push (a plain slide with
it on; the zoom with it off, frame by frame from a screen recording).

Found and **not fixed**:

- Profile at `.accessibility3`: the identity block scrolls up *through* the
  pinned glass bar and the status bar, so its handle, court and user ID ghost
  behind the bar's own title. Glass is translucent by design; a more opaque bar
  would be a change to the material.
- The inbox's sent-request row at `.accessibility3` truncates the name
  ("chaseall…") because the Cancel button doesn't yield; the buttons could sit
  under the name at those sizes.

Still to do:

- **A VoiceOver sweep.** The simulator tool's accessibility-tree read wasn't
  available, so nothing about labels, order or traits was checked live — Home's
  band as one element that opens Runs, the inbox's blocked squad invite
  reading its reason, the gallery's controls.
- **Game day, the result screen and Login**, which need a live match or a
  sign-out. The busy-court glow and the win confetti too: nothing in the test
  account is busy or won.
- **Haptics**, which only a physical device plays, and **iOS 18**, the floor —
  only 26.5 and 27.0 runtimes are installed.

---

## See also

- `../UI_SHELL.md` — the visual conventions, the role table, and the invariant
  that orange is a fill or a mark and never both.
- `../PRODUCT_OVERVIEW.md` — the accessibility claims made to a non-technical
  reader.
