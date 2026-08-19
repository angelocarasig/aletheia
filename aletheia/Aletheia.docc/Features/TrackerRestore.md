# Tracker Restore

Rebuilds a reader's library from a tracker's list rather than from a backup file: pull everything
on AniList/MyAnimeList/MangaBaka, auto-match each entry against installed sources, and commit only
what the reader confirms.

A **link** is the `series_tracker` row joining one of our series to one remote entry (see
<doc:Trackers>). This feature only ever creates links; it never pushes or pulls progress after the
fact - that's what linking itself already does.

## Scope

- Pick one signed-in tracker whose service can answer a whole-list pull, and which installed
  sources to search against.
- Pull the tracker's entire list in one request-driven walk, session-only - nothing is written
  until a row is individually saved.
- Auto-search every entry across the selected sources, auto-select an exact title match, let the
  reader pick otherwise from a candidate grid.
- Commit one row at a time: create the series, join the library, fetch chapters, mark progress up
  to where the tracker says the reader is, link the tracker. One write path, reused per row - not
  a bulk transaction.
- Surface an entry already linked locally before running it through search at all, rather than
  attempting a duplicate create.
- A paginated, filterable queue (Remaining / Already Linked / Saved / Failed pills) rather than a
  progress bar.

Out of scope: exporting a library back out, restoring more than one tracker in a session, or
re-running restore against a tracker already fully processed (every prior save shows up in the
Already Linked pill, which is correct but not free - nothing skips the pull itself).

## Where a tracker's list comes from

`BulkListingTracker` is an opt-in protocol (the same shape as `AuthenticatingSource`/
`RevalidatingSource` on the source side, see <doc:aletheia/SourceProtocols>) rather than a new required
method on `TrackerService`:

```swift
protocol BulkListingTracker: TrackerService {
    func list(token: String) async throws -> [TrackerListEntry]
}
```

All three tracker services conform, each against a different real endpoint - a GraphQL media-list
query for AniList, a paged REST list for MyAnimeList, and MangaBaka's own list endpoint. Each
implementation has its own pagination quirks; see <doc:Trackers> and <doc:TrackerMangaBaka> rather
than assuming this document's summary generalizes.

`TrackerListEntry` is the shared shape: remote id, title, cover, total chapters, progress, a raw
status string in the tracker's own vocabulary, and an adult flag. Status stays raw rather than
mapped here, since a restore session pulls from exactly one tracker and the mapping is only
knowable at commit time.

## The commit chain

One write path, run once per Save tap:

1. Fetch the picked candidate's full detail from its source.
2. Create the series and origin - or attach to one that already exists - and join the library, the
   same calls Details' own "add a source" flow makes.
3. Fetch chapters for real.
4. Mark progress, monotonically, up to the tracker's own reported progress.
5. Link the tracker, with status resolved from the tracker's raw status string.

**Step 2 carries an existence check.** A restore row can resolve to a series already known
locally - duplicated on the tracker's own list, or simply because the reader already had the
series before running restore at all. Creating it a second time would trip the origin table's
unique constraint. The fix looks up the origin by source and slug (checking both the detail
response's own slug and the candidate stub's) before writing, and attaches to what's found instead
of re-creating - the same idiom Details already uses for "attach a source to an existing series."

## The already-linked pill

A second, earlier guard: before any search runs, every pulled entry is checked against
`series_tracker` for an existing row. A hit is marked already-linked and never enters search,
select, or save - it renders a flat "already in your library" state with no controls, in its own
filter pill. This is deliberately a second guard rather than a substitute for the commit-time
check - it catches the common case cheaply and visibly, but can't catch same-session duplication
(two different tracker entries resolving to the same source series via search), which the
commit-time check still exists for.

## The queue screen

Setup picks a tracker (gated to signed-in trackers whose service supports a bulk list) and which
installed sources to search. The queue is a paginated list:

- Filter pills - Remaining / Already Linked / Saved / Failed, each stating its own count.
- Pagination over whichever pill is active, not the master list - a row that leaves Remaining
  (Save, Skip) is simply gone from that pill's count on its next render.
- Per-row states: idle, searching, found (ambiguous or auto-selected), not found, search failed,
  saving, saved, skipped, already-linked.
- A row leaving its current pill animates explicitly around the mutation itself, not left to
  whatever transaction happens to be active when an await returns - a save in flight still needs
  its own visible state, since the button-visibility guard that hides actions during a save must
  not also hide the fact that something is happening.

## Settings placement

Settings -> Data & Storage -> Backup & Restore -> Import -> Restore from Tracker, presented as a
sheet rather than a push - restore is a self-contained process with its own setup step and queue,
and closing it from the queue two levels deep should end the sheet rather than pop back through
setup first. Backup & Restore also carries an Export section for library export; see
<doc:aletheia/LibraryBackup>.

## Not built

- Restoring from a tracker a second time doesn't skip the pull itself - every entry still gets
  fetched and checked against `series_tracker` even when the whole list was already linked last
  time.
- No progress indicator for the pull itself beyond the Start button's own loading state - a large
  account can take real wall time walking pages before the queue even opens.
- Library export.
