# hoopsRN — Accessibility gaps

**Scope:** —
**Verified:** 2026-09-16 @ 8209408

One tracked failure, pinned by a test that fails the moment it's fixed so it
can't be quietly forgotten.

`Scope: —` because this is a narrative over `Theme.swift` and the view tree,
which `UI_SHELL.md` owns. It can't be diffed, so it's re-read by hand every
pass.

---

## `hooprOrange` fails WCAG AA as a foreground in light mode

It measures **2.29:1** on `hooprBackground` and `hooprSurface` and **2.10:1**
on `hooprFill` — under the 4.5:1 text floor *and* the 3:1 graphic floor. Dark
mode is fine (10.24 / 8.29 / 6.79), because the orange is lifted there and the
grounds are dark.

**Affected call sites:** `ProfileRow`'s leading symbols, `PlayerAvatar`'s
initials (genuinely text), `CourtRow`'s filled star, `GameCard`'s and
`MapTab`'s basketball glyphs, the map's recenter glyph,
`ProfileIdentityBlock`'s avatar ring, and `StatsCard`'s three stat icons.

**The tab bar is now this gap's most prominent instance.** Navigation moved to
a native `TabView` whose selected item takes `hooprOrange` via `.tint`, which
colours the glyph *and* its ~10pt label. The old shell's pills never hit this:
they painted the brand as a *fill* with `hooprOnBrand` on top, which passes at
6.61:1. In light mode the selected tab label now reads **lighter** than the
unselected ones, inverting the hierarchy it exists to signal. Shipped as a
deliberate product decision, with the numbers known: `hooprDarkOrange` reaches
only ~3.85:1 — it clears the graphic floor and still misses the text one — and
a monochrome bar passes but drops the brand from the app's most-seen control.

**The fix** is a second brand role — a deepened orange for marks that are
*read* rather than filled — plus a sweep of those call sites. A starting value
of roughly `#B4491E` measures ~5.4:1 on white and is the cheapest honest fix.
The reverted palette had exactly this and called it `hooprBrandText` (`git show
a6e5668:hoopr/Support/Theme.swift`), tuned to 42% lightness for 4.99:1 — but
that value is coral, not orange, so it can't be lifted verbatim.

**Both failures are pinned in the failing direction.**
`ThemeContrastTests.testBrandAsForegroundIsATrackedGap` and
`testTabBarSelectionIsATrackedGap` assert the *current, failing* ratios, so
they break the moment someone fixes the colour — which is the signal to add the
real assertions in the same change that adds the role.

---

## A note on the orange itself

`hooprOrange` was softened — desaturated, same hue — on 2026-08-21 as a pure
taste change, unrelated to this gap and not meant to address it. It moved these
ratios slightly *further* under the floor, from 2.55 / 2.34, because pulling
saturation toward white also pulls a colour's own luminance toward white's.

Worth knowing before assuming a future retune of the brand colour fixes this
for free — it can just as easily make it worse.

*(Fixed 2026-08-21: the same revert had left `hooprOnBrand` as white on that
orange at 2.55:1 / 2.25:1, on every primary button. It is now black — 8.24:1 /
9.33:1 — with `hooprOnRed` split out for the one label on a red fill, where the
required colour inverts with the appearance.)*

---

## What is not a gap

Stated so it isn't re-investigated: contrast across every pairing the interface
actually draws is asserted at 4.5:1 in **both** appearances by
`ThemeContrastTests`, and the build fails if one slips. Dynamic Type is
supported throughout, light and dark are both first-class, and VoiceOver labels
are set on controls whose meaning is carried by an icon or a badge — including
the Seasons crest-vs-crest row, where the *row* carries the label because two
decorative glyphs otherwise say nothing.

---

## See also

- `../UI_SHELL.md` — the visual conventions and the tab bar this lands on.
- `../PRODUCT_OVERVIEW.md` — the accessibility claims made to a non-technical
  reader, and this exception stated alongside them.
