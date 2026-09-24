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

## Never checked live: VoiceOver, Reduce Motion, `.accessibility3`

The UI revamp (2026-09-21 → 24) rebuilt every screen, and **no VoiceOver sweep
and no Reduce Motion pass of the rebuilt app has been done on a device.** What
exists is unit coverage (`MotionTests`, `CelebrationTests`, the layout-metric
suites) and off-device renders of individual components at `.accessibility3`.
Still to do on the simulator, each changed screen in both appearances:

- a VoiceOver sweep — Home's band is one element that opens Runs; the inbox's
  blocked squad invite reads its reason; the gallery's controls;
- Reduce Motion on — zoom pushes become plain pushes, the glow holds still, no
  confetti;
- `.accessibility3` on Home, Runs, Seasons, the map card, and the result screen;
- haptics, which only a physical device plays.

---

## See also

- `../UI_SHELL.md` — the visual conventions, the role table, and the invariant
  that orange is a fill or a mark and never both.
- `../PRODUCT_OVERVIEW.md` — the accessibility claims made to a non-technical
  reader.
