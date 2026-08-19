# Section Controls

> Note: The hard rules this research produced (pop-up button for sort, no glass in the content
> layer, active-filter must carry a shape channel not just colour, hide a control with nothing to
> choose) are already promoted into <doc:aletheia/Design>'s "Section controls" section - read that first.
> This page keeps the reasoning and ecosystem evidence behind those rules, plus findings that
> never got promoted. The specific screen this was audited against (Details' Chapters header) has
> since changed shape and no longer matches either the "before" or "after" described below in
> every particular - check the current `DetailsChapters.swift` rather than trusting this page for
> that screen's present layout.

How a section inside a scrolling screen should present its title, its count, and its sort/filter
controls, distilled from an audit of Details' Chapters header plus Apple's guidance and a ten-app
reader-ecosystem survey.

## What Apple actually prescribes

There's no "chip" component in Apple's inventory - the equivalent is a **pop-up button**, a
capsule showing the current selection, labelled with the value rather than an icon (sort has no
standard glyph, which is itself the guidance: sort takes text). In-content placement for
section-scoped controls is directly sanctioned ("filtering a list, make these options available in
the screens they affect"). Liquid Glass is explicitly excluded from the content layer except for
transient interactive elements (a slider thumb mid-drag) - a chip row glass at rest is what the
prohibition covers. A text-labelled action and a symbol-only action should sit in separate
containers, or adjacency reads as one combined control.

Apple's documented pattern for "is a filter active" is a tinted background behind the glyph plus a
filled symbol variant - a numeric badge is not among the platform's own examples (badges are
reserved for notification counts). This app keeps a count anyway, on top of the tint and glyph
channels, since three channels together satisfies the never-colour-alone rule more completely than
either the platform's two-channel version or the plain ecosystem convention of tint-only.

## What the ecosystem agrees on

Across ten surveyed reader apps: sort and filter combine into one surface, and bulk actions live
in an entirely separate cluster - nobody mixes the two. An active filter is a binary appearance
change on the trigger, and essentially nobody shows a count (the two apps that show nothing at all
for an active filter are the survey's most-cited weak point). Reset is immediate and dismissing
everywhere, never staged. A large option vocabulary gets a per-section search field past roughly
15 options - independently arrived at by more than one surveyed app and matched by what this app
already ships.

**Applied filters as a removable chip row with a count** is the strongest single finding, sourced
from filter-heavy e-commerce/real-estate apps outside the reader domain - it's what makes state
visible without opening anything, which the reader-app survey doesn't converge on but the wider
UX literature does.

## What's still an open question

Whether counting an item total in a section header is something Apple's own apps ever do - no
surveyed Apple app pairs an item count with a sort control, so a count there is this app's own
call, not borrowed platform authority. Whether the sort control's persistence should be per-series
or global - every surveyed app that persists sort at all persists it, this app currently does not
for the Chapters header specifically.
