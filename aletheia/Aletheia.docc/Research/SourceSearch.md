# Per-Source Search

> Note: much of this research's "Direction" section overlaps with what's now built and documented
> in <doc:BuildingASource> ("Ranked shelves are not sorts," "What the screen shows") - read that
> first rather than this page for the current sort/shelf/preset contract. This page keeps the
> platform-guidance reasoning and the ecosystem evidence specific to the per-source search screen
> (`SearchScreen`'s focused variant, reached from a source's own toolbar) that isn't captured
> elsewhere. Some of what this audit flagged as broken has since changed - `SearchGridViewModel`
> now has a `remove(_ chip:)` method for individually-removable applied filters, which the original
> audit found entirely missing - so verify current behavior against the code before trusting this
> page's "what's wrong" section as still accurate. `.searchable` is still not adopted anywhere in
> the search tree, confirmed current.

The screen reached from a source's own toolbar: a query, one sort, and per-source filter
categories - distinct from the grid screen reached by tapping a preset carousel.

## What Apple's guidance actually says for this shape

Apple's own recent guidance addresses this almost directly: for an app searching across multiple
categories, offer a filter surface behind **one entry point**, and keep filters contextual rather
than a wall of peer options. Two mechanisms are explicitly ruled out on mechanics rather than
taste - scope bars bind to a single `Hashable` value and render as a segmented picker, which can't
express a multi-select tri-state filter set; and search tokens are explicitly documented as *not*
a replacement for a real filtering UI, and have no negation affordance, so a tri-state
include/exclude can't be expressed as a token at all.

Field placement follows an inline, at-the-top pattern - similar to how a music app scopes a
library search inline rather than as app-level search - with the placeholder naming what's being
searched. Material follows placement automatically once `.searchable` is adopted: a toolbar-placed
search field gets glass and scroll-edge effects for free, while one placed in the scroll region
gets standard content styling - that split is mechanical, not a style choice, and matches this
app's content-layer-stays-flat rule already in <doc:Design>. Apple also documents no
preview-before-apply pattern for search filtering generally - live application on change is the
documented default.

Tri-state include/exclude, filter-count badges, and a filter-chip component all have zero direct
Apple guidance or component coverage - whatever ships there is this app's own design decision,
informed by <doc:SelectionLanguage>, not a platform answer.

## What the reader-app ecosystem does with the exact same shape

Four surveyed reader apps carry the identical model (tri-state include/exclude, per-source
vocabularies, hundreds to thousands of options), and they land on genuinely different tri-state
mechanisms - a checkbox glyph swap with no colour channel at all; two apps use a
green/red/neutral cycle (the model this app already ships, via `SearchRefineSheet`'s
`.success`/`.danger`); one refuses tri-state entirely, keeping "include" and "exclude" as two
separate sections. A non-reader comparison (Steam) uses two separate hit targets per row - a
checkbox to include, a distinct glyph to exclude - which is the accessibility-strongest of all of
them, since a cycle requires discovering that a third tap state exists.

On live-vs-staged filtering there's no ecosystem consensus, but **an immediate, non-staged Reset**
is unanimous across every surveyed app - worth treating as a hard rule regardless of whether the
rest of the sheet applies live or on commit.

On large option lists, this app's existing thresholds (search field past a modest count, deferred
search-only mode further out, a render cap that never drops a selected option) already match or
exceed what any surveyed reader app does - most ship nothing better than a long collapsed list.
The one idea worth stealing that isn't built: a *suggested* tier of co-occurring or commonly-paired
options shown before the reader has to search, which gives a meaningful default set instead of a
flat alphabetical wall.

On visible active-filter state, the strongest sourced finding (from filter-heavy commerce apps
outside this domain) is an applied-filter chip row with a count - not a bare count alone, which
several sources call insufficient on its own since it gives neither context nor a way to remove
one filter without reopening the whole sheet.

## Correctness issues found during the original audit

Worth spot-checking rather than trusting as still-current, since the search subsystem has visibly
moved since: `SegmentedSelect`'s getter falling back to the first option so it renders as chosen
even with nothing actually selected; a number field not resyncing after Clear All; `clearFilters()`
not resetting sort; and `activeFilterCount` disagreeing between the inline panel and the sheet
because one counted single-select filters and the other didn't. Several dead-code findings from
the same audit (an unreachable ascending-sort branch, an unused `hidden` flag) were confirmed fixed
by the time this was last reviewed.
