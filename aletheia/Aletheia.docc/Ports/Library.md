# Library Port

Tracking the port of alethia-v2's Library feature into `Screens/Library/`. Feature parity needed
zero schema changes - everything v2's Library does, minus trackers, resolves against tables and
views that already existed.

## Why `RichfulEntryView` collapsed three query engines into one

v2 routed between two different fetch paths because its main library view silently dropped status
and classification and couldn't sort by chapter count, plus a third, separate path duplicating
everything again for its Home screen. `RichfulEntryView` here already carries the library
membership gate, publication and classification filters, chapter-count and unread-count sorts, a
download-aware cover resolution v2 never had, and already sorts unavailable/disabled sources last.
One view, no dual path, no five-query stitch in application code.

## What shipped

Filters, sort, and the collections chip strip are all built (`LibraryFilterSheet`,
`LibrarySortSheet`, `LibraryCollections`, `LibraryActions`) - six collapsible filter sections
(sort, tags, sources, quick filters, metadata, dates), applying immediately with no separate Apply
step, matching the source design. The collections strip mirrors the useful part of v2's design:
each chip's count is scoped to what the current filters already show, not a global total.

## Decisions carried into the design, not just left as open questions

- **No selection mode, no bulk actions.** With only "add to" and "remove from" a collection, that
  didn't earn a toolbar slot on its own - collection membership is reachable from a series' own
  Details screen instead. Revisit if bulk remove-from-library, mark-read, or download ever land.
- **No separate collection detail screen.** A collection is a subset of the library, and the grid
  already renders subsets by filtering - a second, pushed screen showing the same subset with a
  decorative header would just be two ways to see the same thing. Tapping a chip filters; that's
  the whole interaction. Edit and delete live on the chip's own context menu.
- **Collection chips are single-select**, matching v2. A chip's count reads as "how many of what
  I'm looking at are in here," which only stays legible against one active collection at a time.
- **Filters are global, not scoped per collection.** Scoping them per chip would mean tapping a
  chip silently changes a reader's other active filters - a worse surprise than the one that would
  fix. The actual problem in v2 wasn't scope, it was invisibility (one undifferentiated dot for any
  combination of active filters); the fix is a visible, removable chip row for active filters,
  matching the same conclusion reached independently for source search (see <doc:aletheia/SourceSearch>).
- **Reading status is a filter and a sort field, not the primary grouping.** No shelves - the grid
  stays flat, and status (reading/completed/paused/dropped/planning, a reader-facing state with no
  v2 counterpart at all) sits alongside tags and sources in the filter panel rather than splitting
  the grid into sections.
- **The unread badge stays red**, deliberately, against the instinct that a HIG passage about
  ambient-data badges (weather, stock prices, dates) prohibits it. It doesn't apply here: those
  examples are all ambient facts that exist whether or not you act on them, where an unread count
  is the opposite - it counts items awaiting you and goes to zero once you deal with them, the same
  semantic Apple's own Mail app badges red. See <doc:aletheia/Design>'s Cards, grids, and artwork section.
- **No grid density control.** `gridColumns` is read by every grid and written by nothing yet - not
  worth a control until there's a settings surface it belongs in.

## Still open

- **`.searchable` adoption.** The plan was to replace the hand-rolled `Searchbar` with SwiftUI's
  own `.searchable`, scoped inline under the title (an explicitly sanctioned pattern for an app
  with more than one distinct search scope - here, browsing a source versus filtering what's
  already owned). Not yet adopted; the custom `Searchbar` component is still what's in place.
- **Indexes for the common library query shape.** The library screen filters on library membership
  and then sorts by one of several dates on every keystroke, and nothing currently covers that
  access pattern specifically; a compound index was recommended but is a migration, not a code
  change, and needs flagging before it's added (see <doc:aletheia/Schema>).
- **Cards, grids, and artwork rules** (no glass/tint on cards, `ConcentricRectangle` for nested
  artwork, `.tappable` over `NavigationLink`, `screenMargin` gutter, five load states with a real
  error branch) are the target Library should match against the rest of the app - see
  <doc:aletheia/Design>'s Cards section for the current statement of those rules, since Library was
  historically the outlier on several of them (a 12pt gutter instead of the app-wide 16, no error
  state, `NavigationLink` instead of `.tappable`).
