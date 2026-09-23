# hoopsRN — Accessibility gaps

**Scope:** —
**Verified:** 2026-09-21 @ 1a2710d

What is still wrong with accessibility. The one tracked *colour* failure this
page used to carry — brand orange as a foreground in light mode — **closed on
2026-09-21**, and is recorded once at the bottom so it isn't rediscovered. What
is left is layout: three surfaces that break at `.accessibility3`.

`Scope: —` because this is a narrative over `Theme.swift` and the view tree,
which `UI_SHELL.md` owns. It can't be diffed, so it's re-read by hand every
pass.

---

## Three surfaces break at `.accessibility3`

Found by looking at screenshots rather than code: the Phase 0 audit of the UI
revamp (`plans/UI_REVAMP_AUDIT.md` §7.4) captured every screen at the largest
size the app is tested at, and the first two fail rules `UI_SHELL.md` already
states; the third turned up in Phase 1's live pass, the first time a run-populated
screen was photographed. Neither is a design question — both are defects against today's
conventions. Both live on screens Phase 2 recomposes, so they will close *as
bugs* when those layouts change; they are recorded here so they aren't
re-found, or counted as features, in the meantime.

~~**`StatsCard` breaks words mid-word.**~~ **Closed 2026-09-22.** The three
columns were each given an equal third of the card — 93pt at the default size,
when "Yesterday" needs 92, and 116pt one step up — so the labels broke as
"Ru / ns", "Str / eak", "Last / Run". The columns now hug their content and a
`ViewThatFits` switches the card to one stat per row only when the row can't
fit (from `.accessibility1` up). `StatsCardMetrics` measures both sides of that
switch and `HomeViewModelTests` pins them, including that even the widest value
fits one line of the stack at the largest size. Seen at `.accessibility3` in the
live app. (`Views/Components/StatsCard.swift`.)

~~**The map's court card truncates both of its own lines.**~~ **Closed
2026-09-22.** The name rendered as "East En…" and the metadata line as
"Durham · 0.…", because the star and close buttons scaled with the text and took
the width the name needed. Now the controls sit in fixed 44pt targets with
capped glyphs, the court glyph is dropped at every accessibility size, and a
name that still doesn't fit sheds a trailing "Park" and then its court number
before any letters are cut (`CourtName` — the user's rule for the map; the Runs
tab shows the full name). At `.accessibility3` the card reads "East End", not
"East En…". The header also scrolls with the card's body, so the pinned action
row can't be pushed below the `.medium` fold. `CourtNameTests` and
`CourtCardLayoutTests` pin it. Seen in the live app at `.accessibility3`.

**`GameCard` — and Home's next-run card, which copies it — collapses.** Three
things at once, seen on a real populated card: the **HOSTING badge breaks
mid-word** ("HOSTI / NG"), because it is an unconstrained capsule on a 11pt caps
label with nowhere to wrap to; the **court name is cut to "Long Meado…"**, because
the badge has taken the width the name needs and the name is `lineLimit(2)`; and
the **details row breaks mid-word** ("1 / 10 pla…", "0.8 / mi", "Invite / only"),
because it is a plain `HStack` with no `ViewThatFits` ladder — `UI_SHELL.md` says
so itself, as the reason the friends line got its own row. `GameCard` is the app's
most repeated element and the Runs tab's whole content, so this is the defect at
the largest scale of the three. (`Views/Games/GameCard.swift` `header` and
`details`; `HomeTab.nextRunCard`.) Not caused by Phase 1 — the badge's padding is the
same 8 × 4 it always was.

Reproduce all three with
`xcrun simctl ui booted content_size accessibility-extra-large`; the third needs at
least one run on the account.

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
  drawing it, so the value the code hands over is not the value on screen.
  Sampled from the live app, `hooprOrange` rendered as `#E55E27` on a `#EDEDED`
  selection pill in light mode (**3.01:1**) and as `#FF8F6A` on `#3A3A3A` in dark
  (5.09:1). `testTabBarSelectionClearsAA` can only assert the nominal value.
  After the move to `hooprBrandAccent`, the **live app measures 5.32:1 in
  light** (`#AF3706` on `#EDEDED`) and 4.98:1 in dark (`#FF8C68` on `#3A3A3A`),
  sampled the same way as the "before" figures. The dark figure is the old 5.09
  within sampling noise, as it should be — the dark tint is identical by
  construction. A harness render of a real `TabView` had predicted 5.43 / 5.21,
  and at HEAD had reproduced the live 3.01 / 5.09 as 3.08 / 5.21, which is what
  made it worth trusting before the app could be run.

---

## Fixed, and worth remembering

**Brand orange failed AA as a foreground in light mode (closed 2026-09-21).**
`hooprOrange` measures 3.17:1 on white and 2.91:1 on `hooprFill`, under the
4.5:1 a mark needs — and 2.78:1 on its *own* 12% wash, which is where a run's
HOSTING badge draws it, and the figure nobody had measured. It was reached for
as a foreground 49 times across 22 files, because it is the brand colour.

The fix was a second role, not a retune. `hooprBrandAccent` is `hooprOrange`'s
hue and saturation deepened until it clears 4.5:1 on every ground a mark sits on
(`#B8400F` in light; in dark it is the same value as `hooprOrange`, which
already cleared it). The 49 marks moved to it — text, glyphs, focus rings and
selection strokes, the capacity bar, spinner / slider / date-picker tints, the
tab bar's selected item — and the 21 fills that carry `hooprOnBrand` stayed
`hooprOrange`. `BrandMarkUsageTests` reads `Views/` and fails if a view draws
`hooprOrange` in `foregroundStyle`, `tint` or `stroke` again.

Two things worth keeping from how it went:

- **The gap lasted as long as it did because the tests pinned the *failure*.**
  `testBrandAsForegroundIsATrackedGap` asserted the ratio was *under* a
  threshold, so it passed on 2.29 and on 3.17 alike, and this page's numbers
  drifted stale without anything going red. A test that asserts a defect is a
  test that cannot tell you the defect changed. Both are gone, replaced by
  assertions that the accent clears.
- **Measure the ground a mark actually sits on.** Every earlier figure was
  orange against the page, which is the ground it is *not* drawn on: the badge
  and the icon tiles sit on a wash of orange, darker and more orange than the
  card, and that is what measured 2.78.

**A second, unrelated failure turned up in the same pass:** the map pin's count
was `hooprOnBrand` (black) on every heat tier — 6.62:1 on the quietest, only
**4.01:1 and 3.43:1** on tiers 3 and 4, under the 4.5:1 a 12pt bold label
needs, on exactly the courts busy enough to matter. Nothing asserted it because
the ramp lived outside `Theme.swift`. It is white from tier 3 now
(`hooprOnHeat(tier:)`), and every tier is held by
`testEveryHeatTierCarriesItsLabel`.

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
label because two decorative glyphs otherwise say nothing.

---

## See also

- `../UI_SHELL.md` — the visual conventions, the role table, and the invariant
  that orange is a fill or a mark and never both.
- `../PRODUCT_OVERVIEW.md` — the accessibility claims made to a non-technical
  reader.
- `../plans/UI_REVAMP_AUDIT.md` — where both reflow defects were found, with the
  screenshots that show them.
