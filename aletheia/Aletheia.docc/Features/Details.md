# Details

`Screens/Details/` - `Model/`, `DetailsScreen`, `Components/`.

The screen has one job that's harder than it looks: work out which series row you mean, then
render it. Most of what follows is about the first half.

## Shape

`DetailsComposer` is the root; it owns seven `@Observable` children, one per feature:

```
Model/
  DetailsComposer.swift              the graph: 7 children, lifecycle, ready/opener/stub/load/cancel
  DetailsComposer+Observation.swift  the one ValueObservation, Stored, the queries, the row writer
  DetailsComposer+Series.swift       title/cover/synopsis/tags/pools + the 4 preference writes
  DetailsComposer+Library.swift      membership, status, collections
  DetailsComposer+Chapters.swift     the list, visibility, open/mark
  DetailsComposer+Sources.swift      origins, ranking, language and scanlator priority
  DetailsComposer+Tracking.swift     links, search, link/unlink/edit/push
  DetailsComposer+Identity.swift     disambiguation candidates, merge matches, reparent/merge
  DetailsComposer+Refresh.swift      the pill, the walk, prime/adopt/join
```

**Data flows down, actions flow in.** One `ValueObservation` emits a `Stored` bundle; the root
hands the same bundle to every child, and each child takes only the part it owns via
`DetailsApplying`, assigning only what actually changed - which is what stops a tracker sync from
redrawing the chapter list. **A child never calls a sibling and never reaches up to the root** -
where an operation genuinely spans two children, it lives on the root instead (`catchUp`,
`attach`/`separate`/`merge`, `refresh`).

Writes carry their own state through `DetailsWriting` - `saving`, `failure`, `clear()` - so a
write in one section leaves the others alone and a failure stays beside the thing that failed.
`saving` is derived, not stored: `Sources` keys it by origin id, `Tracking` by service, so one row
spinning doesn't dim its list.

## The rule the whole screen follows

**The screen renders from the database. The network only ever fills the database.**

`ready` is `applied && !identity.isAmbiguous` - it never waits on a fetch. A single
`ValueObservation` feeds every section (title, covers, origins, chapters, status, library state),
and every write below lands back through it rather than being read back by hand. A library series
opens instantly and offline; so does a source result already owned. Any write redraws the screen
for free - `toggleLibrary`, `setStatus`, `markAll`, chapter progress, a cover finishing its
download, none of them call a reload. There is exactly one path that fetches: `store(into:)`, plus
a deliberate `refresh()`.

## Entry

`SeriesEntry` carries provenance, and each case carries exactly what that route can supply:
`.source(sourceSlug:stub:)` (a slug, title, cover - no row) or `.library(SeriesRecord.ID)` (a row
id, nothing else needed). A library entry never matches and never fetches - it already knows its
row; that isn't a special case, it falls out of having the id. A source entry runs matching first.

## Matching

`SeriesRecord.match(_:from:in:)` runs entirely against the database, before anything reaches the
network, and returns an outcome plus any row carried forward:

- **Tier 1**: `origin.slug + sourceId` against a unique index, so it's 0 or 1 rows. A hit already
  in the library resolves immediately. A hit not in the library is carried forward as `held` and
  matching continues - stopping here would say "not in library" while you own the series under a
  different source, and adding it would silently create a duplicate.
- **Tier 2**: title against the title pool, **in-library rows only**. Non-library rows are
  disposable browse cache; offering them as merge candidates would be offering to merge junk.

A tier-2 match produces disambiguation candidates; no match at all falls through to `settle()`,
which reuses `held` if tier 1 carried one forward, otherwise creates a new row.

## Disambiguation

Shown when matching produces candidates, sorted most-read-first (identical titles make reading
progress the only distinguishing signal). Three exits: pick a candidate (origins reparent onto the
target, held row deleted), "Add as new" (falls to `settle()`), or cancel (clears candidates,
**pops the whole screen** - there's nothing to fall back to, since `seriesId` is still nil at that
point and nothing needs undoing because matching completes before any row is created or any fetch
fires).

Selection is always required, even at one candidate - merging is irreversible, so it never happens
from a single mistaken tap.

## Create - the only fetch

A library entry can never reach this path (it always carries its row). A source entry with no
match calls `source.details()`; on success, one transaction writes series, origin, titles, covers,
authors, tags, and seeds language priority, then the observation picks it up. Chapters are
deliberately not in that transaction - they land in a second write so the screen can render as
soon as metadata exists.

The duplicate guard checks both `detail.slug` and the stub's original slug, since the details
response's canonical slug can differ from the slug the stub was opened with.

### The cover pool

The search result's own cover (`stubCover`) is part of the pool, added last rather than first or
omitted:

```
pool      = detail.covers (quality descending) + stubCover, if not already present
preferred = primaryCover(among: detail.covers, matching: stubCover) ?? stubCover
```

A source whose details response can return a url that doesn't resolve needs a floor to fall back
to - `stubCover` is the known-good url that was already rendering on screen a moment earlier.
Putting it last means a source with better detail-page artwork still wins on quality; putting it
in the pool at all means there's always a fallback. Pool insert order is row-id order, which is
also the order a preferred-cover-gone recovery walks, so the known-good url being last makes it
the floor of that ladder. Covers are add-only on refresh, which is what makes a bad pool
repairable via a metadata refresh rather than permanent.

A source with several cover variants should request the same superset of fields in both `search()`
and `details()` - if `details()` asks for less than `search()` did, the two calls can disagree
about the same series' artwork.

### `prime()` - the one automatic fetch

Runs inside `observe()`, so both entry cases reach it, and fires at most once per screen. It's the
only automatic fetch a series outside the library will ever get - the background walk only takes
`inLibrary = 1` rows.

The condition is `.source` entry **and** `chaptersFetchedDate` older than
`Constants.Refresh.staleAfter` (currently 3 days) - `.distantPast` is older than any threshold, so
a never-fetched series is subsumed rather than special-cased. It asks every refreshable origin in
a task group, not just one - a stale origin and a fresh one would otherwise render identically,
making a partial refresh invisible. It runs silently over an already-populated chapter list
(`isFetchingChapters` only draws the skeleton while the list is empty), since a stale top-up
showing nothing and new chapters simply appearing is the accepted behavior - a per-origin failure
already surfaces on the source row, which is where that fact belongs.

The threshold is a fixed constant, deliberately not the same preference that controls the
background walk's cadence (which defaults to off) - binding to it would disable this for most
readers.

## Chapters

**A pull-to-refresh takes the series off any running background walk.** If a library run still has
this series queued, `dequeue(series:)` drops it from the pending list and counts it as completed -
truthful, since it was checked, just not by the walk. If the walk is already fetching it, there's
nothing to dequeue and the pull joins the fetch in flight instead. Two different situations need
two different mechanisms, or the same origin gets fetched twice.

**A refresh walks every origin, not just the primary one.** `refresh()` runs every origin whose
source is installed, enabled, and still compiled in, each answering for itself in a task group.
Metadata is fetched per origin too, or skipped entirely for a chapters-only refresh; a metadata
failure is logged and never blocks that origin's chapters. `RevalidatingSource` absorbs most of
the resulting request cost - an origin that hasn't moved answers without a full feed walk. This is
the same unit bulk library refresh calls, so it has to stay one implementation.

`fetchChapters` stamps `origin.chaptersFetchedDate` on any *completed* fetch - including when the
source returns nothing new - but not on throw:

| Source returned | Rows written | `chaptersFetchedDate` | `fetchAttemptedDate` | `fetchError` |
|---|---|---|---|---|
| rows | yes | yes | yes | cleared |
| nothing changed | no | yes | yes | cleared |
| genuinely none | no | yes | yes | cleared |
| threw | no | no | yes | set |

This distinction is the entire mechanism that lets the chapters section tell "no chapters" from
"not fetched yet," and the empty state says which one it is - a landed fetch that found nothing
reads "No Chapters," a fetch that never ran reads "No Chapters Yet" with a pull-to-refresh hint.
The empty state carries no action of its own, since refresh already exists twice on this screen
(pull-to-refresh, and Refresh Chapters in the actions menu) and a third copy would be the
duplicated-bulk-action anti-pattern.

**The chapter-fetch pill is per origin and outlives the view model.** One row per origin,
source-named: queued (accepted but not yet talking to the host), checking (a spinner), then a
result (`+N`, a minus-circle for "up to date," a warning triangle with the reason, or a stopped
glyph if cancelled). It clears itself a few seconds after landing. State lives in the shared
refresh unit rather than the screen's own view model, so reopening a Details screen mid-fetch
rebuilds the pill's rows from what's actually still in flight rather than going idle while a fetch
it started keeps running silently underneath. An origin that finished while the screen was closed
can't be rebuilt this way (its result lived only in the closed screen), so it's simply omitted -
only origins still in play appear. Cancelled is not a failure: nothing is stamped, since the
origin was never asked and never answered.

The source row in the sources section is the durable status for a failing origin - a badge plus
the reason and when it was last tried, read straight from `fetchError`/`fetchAttemptedDate`, so it
survives the app being killed and clears itself the next time that source answers. No separate run
log is kept on either side.

**Language priorities are seeded, never inferred.** `create()` and every `fetchChapters` write
call the seeding routine (insert-or-ignore, English > Japanese > Chinese > Korean), so all rows
exist for every series and the ranking view's language tier never depends on a row being absent.
The language-order sheet lists only chapter-present languages, and a commit swaps the slots those
languages already hold - languages the series doesn't have keep their seeded positions untouched.

## Reader targeting

The chapter-ranking view merges chapters across all origins, so the chapter tapped may not belong
to the origin that opened the screen - reading a chapter resolves its source from that chapter's
own origin, never from the screen's current route. Opening a chapter writes both
`chapter.lastReadDate` and `series.lastReadDate` - the latter matters because the launch purge
deletes every non-library series whose `lastReadDate` is still `.distantPast`.

## Source availability

Four states, because each needs a different answer from the user:

| State | Meaning | Detected by |
|---|---|---|
| available | normal | - |
| disabled | turned off in settings | `source.disabled` |
| missing | no longer ships in the app | `source.installed == false` |
| disconnected | `origin.sourceId` is null | legacy only, shouldn't occur |

Removing a source marks its row instead of deleting it, so the row survives with its name,
`baseURL`, and referer intact rather than nulling every origin's `sourceId` (which is what
`disconnected` records, and why it should no longer happen in practice). A degraded origin still
displays - only fetching and opening a chapter switch off, since both need live code from the
registry that a tombstoned row doesn't have. Chapter rows gate on their own `canRead` fact.

## Known edge cases

- Disambiguation repeats - a "not the same" answer isn't stored, so a title clash prompts on every
  open.
- A cover refade can occur when a download completes, since the image cache key changes from a
  remote URL to a file URL and replays the fade; the resolved artwork is memoised per screen so
  this only happens once, on the transition itself.
- `prime()` is once per screen - a fetch that throws won't retry until the screen is reopened.
- A non-library series reached from reading history stays stale: history carries no foreign key by
  design, so a reading event outlives its series and routes to it by row id without going through
  `prime()`'s gate. Considered correct - reviewing what was read isn't the same intent as checking
  for new chapters, and pull-to-refresh is available on the screen this routes through.
- A removed series keeps its downloaded files - removal touches only library membership, not the
  chapter's stored path, so a disk sweep still finds a row pointing at the bytes.
- Two never-opened copies of an identically-titled series are genuinely indistinguishable in
  disambiguation (no progress, no read date) - the row degrades to chapter count and added date,
  and no layout fixes that.
