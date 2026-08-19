# Selection Language

How the app marks "this is the chosen one."

## The standard

One vocabulary, four meanings, no substitutions:

| Meaning | Marker | Colour | Where it applies |
|---|---|---|---|
| chosen option (persisted preference, exclusive) | trailing `checkmark` plus glass tint on the row; on artwork, a corner `checkmark.circle.fill` badge | `.brand` | preferred title, preferred cover, synopsis/metadata origin, tap-zone layout, mode/dim/status menus |
| current position (session/navigation, not stored) | container fill `Palette.brand.opacity(0.15)`, no glyph | `.brand` | current chapter, active (session-swapped) source |
| membership (non-exclusive toggle) | leading `checkmark.circle.fill` / `circle` | `.brand` / `.muted` | collections, multi-select filters |
| finished / complete (fact, not choice) | `checkmark` | `.secondary`, never `.brand` | finished chapters, in-library badges |

## Supporting rules

- **Star is reserved for a future favorites feature** (a boolean, non-exclusive per item) and
  never marks a chosen preference. A star on a preferred cover would read as "one of my
  favorites," not "the cover being displayed" - the platform reserves the glyph for exactly that
  distinction, and this app follows it.
- **Amber never marks selection.** Amber is the attention colour; a chosen option is not a
  warning.
- **Commit is instant for preferences, staged only for multi-edit or irreversible surfaces.**
  Disambiguation (an irreversible merge) and a reorder sheet keep explicit Cancel/confirm;
  everything else applies on tap. A jump list (chapter list, source switcher) dismisses on select;
  a preview-in-place picker (tap zones, covers) stays open.
- **Chrome tells the truth.** An instant-apply sheet closes with Close, never "Done" - "Done" only
  where a staged commit exists, paired with Cancel. The glyph beside it is a separate question
  (see the Sheets rules in <doc:aletheia/Design>): `xmark`, except on a full-height sheet with its own
  backdrop artwork, which takes `chevron.down`.
- **Automatic is a first-class option**, not a side effect of clearing something. A preference
  picker leads with an "Automatic" row that shows what automatic currently resolves to (the title
  text, or a cover thumbnail, from origin priority) and carries the checkmark when no pin is set.
  This is what makes pinned-vs-automatic visible, rather than a state the reader has to infer.
- **Saving feedback is one dialect:** whole-surface dim to `0.6` while a write is in flight. No
  inline spinner replacing a glyph.
- **Feedback channels.** Selection changes carry `.sensoryFeedback(.selection)` on the choice
  itself. Custom rows carry `.accessibilityAddTraits(.isSelected)`. State never rides on colour
  alone - the fill-only "current" marker is legal specifically because position isn't state; a
  screen reader still gets the current chapter through its label.

## Why fill-without-glyph means "current"

The underlying split is: a persistent highlight marks where you are, a checkmark marks what you
chose. Session position (a page you're on, a source you swapped to for this visit) is where you
are; a stored preference is what you chose. Using the same glyph for both would make a temporary,
session-only state look exactly as durable as a saved one.
