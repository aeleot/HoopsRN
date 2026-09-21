# hoopsRN — Accessibility gaps

**Scope:** —
**Verified:** 2026-09-21 @ 29486ac

One tracked failure, pinned by a test that fails the moment it's fixed so it
can't be quietly forgotten.

`Scope: —` because this is a narrative over `Theme.swift` and the view tree,
which `UI_SHELL.md` owns. It can't be diffed, so it's re-read by hand every
pass.

---

## `hooprOrange` fails WCAG AA as a foreground in light mode

It measures **3.17:1** on `hooprBackground` and `hooprSurface` (both pure white
in light mode) and **2.91:1** on `hooprFill` — under the 4.5:1 text floor
everywhere, and under the 3:1 graphic floor on the fill only, by 0.09. Dark
mode is fine (7.15 / 5.79 / 4.74), because the orange is lifted there and the
grounds are dark.

*(Recomputed 2026-09-21 from the values in `Theme.swift`. This page used to say
2.29 / 2.10 and 10.24 / 8.29 / 6.79 — the softened orange's figures from
2026-08-21, before the retune described below. It also said the orange fails the
graphic floor outright; on white it no longer does.)*

**Affected call sites — the census, not a list.** The original enumeration
(`ProfileRow`'s leading symbols, `PlayerAvatar`'s initials, `CourtRow`'s filled
star, `GameCard`'s and `MapTab`'s basketball glyphs, the map's recenter glyph,
`ProfileIdentityBlock`'s avatar ring, `StatsCard`'s three stat icons) was never
the whole set, and it predates whole surfaces. A census on 2026-09-21 finds
**at least 30** direct `.foregroundStyle(Color.hooprOrange)` /
`.tint(Color.hooprOrange)` uses across **15 files** under `Views/`: also Home,
Seasons (`GameDayView`, `MatchmakingCard`, `QueueSheet`), the friends inbox and
`PlayerProfileSheet`, `CreateGameSheet`, `InviteLinkCard`, `LoginView`, and
eight in `ProfileEditSheets`. It's a lower bound — it only matches those two
spellings — and it isn't triaged: some are text, some are glyphs, and a few are
spinner or control tints, which are graphics rather than text. Size the sweep
from the census, not from the list above.

**The tab bar is now this gap's most prominent instance.** Navigation moved to
a native `TabView` whose selected item takes `hooprOrange` via `.tint`, which
colours the glyph *and* its ~10pt label. The old shell's pills never hit this:
they painted the brand as a *fill* with `hooprOnBrand` on top, which passes at
6.61:1. In light mode the selected tab label was written up as reading
**lighter** than the unselected ones, inverting the hierarchy it exists to
signal — *(that was measured against the lighter pre-retune orange; whether it
still holds at 3.17:1 hasn't been looked at on a device)*. Shipped as a
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

**One of them is nearly a hair-trigger.** The first asserts the ratio on
`hooprFill` is under 3.0, and it is 2.91. A retune that nudged the orange a
little darker would fail that test with no readable role having landed, and its
failure message would say one had. The tests assert a threshold, not a figure,
which is also why nothing caught this page's numbers going stale: both pass on
2.29 and on 3.17. Treat that test going red as "go and look", not as proof the
gap closed.

---

## A note on the orange itself

`hooprOrange` was softened — desaturated, same hue — on 2026-08-21 as a pure
taste change, unrelated to this gap and not meant to address it. It moved these
ratios slightly *further* under the floor, from 2.55 / 2.34, because pulling
saturation toward white also pulls a colour's own luminance toward white's.

**It was retuned again the next day, and that moved them the other way.**
2026-08-22 took it to `#EE6730` — a deliberately redder, darker hue (17.4°, down
from 29.6°) — which lifted the light-mode figures to 3.17 / 2.91 and brought the
dark-mode ones down to 7.15 / 5.79 / 4.74. `Theme.swift` records the retune and
says it doesn't touch this gap; that's right about the text floor and no longer
right about the graphic one on white. This page wasn't updated, which is how
its numbers went stale.

So the warning cuts both ways: a retune of the brand colour can worsen this or
half-fix it by accident, and either way it changes numbers this page and the
comments around `ThemeContrastTests` quote. Recompute rather than trust them.

*(Fixed 2026-08-21: the same revert had left `hooprOnBrand` as white on that
orange at 2.55:1 / 2.25:1, on every primary button. It is now black — 8.24:1 /
9.33:1 against the softened orange, **6.62 / 7.15 against the current one** —
with `hooprOnRed` split out for the one label on a red fill, where the required
colour inverts with the appearance.)*

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
