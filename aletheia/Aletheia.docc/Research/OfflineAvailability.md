# Offline Availability

What "available" means once a chapter's bytes are on disk.

> Note: parts of this are shipped, parts aren't. See the status marked on each section below.

## The problem (shipped fix)

Two halves of the app used to disagree about what makes a chapter readable. The content path was
already download-aware - `SeriesPageSource.pages(for:)` resolves a local path before it judges the
origin's source at all - but the listing path (``BestChapterView``) inner-joined `source` and
filtered on `disabled = 0 AND installed = 1`, so a downloaded chapter whose source had since been
disabled, uninstalled, or disconnected vanished from every chapter list before its local path was
ever checked. Not a storage leak - the row kept its path, and the sweep kept the file - just
unreachable, which is arguably worse than deleting it: the storage is spent and the reader gets
nothing for it.

**Shipped.** `BestChapterView` now `LEFT JOIN`s `source` and accepts
`(src.id IS NOT NULL AND src.disabled = 0 AND src.installed = 1) OR c.path IS NOT NULL` - a
disconnected origin (`sourceId IS NULL`) survives too, since an inner join would have dropped it
before the `WHERE` got a say. Ranking itself is untouched: an available source still outranks a
download-only one at equal priority, since a downloaded chapter only outranks a live one when its
origin already outranked the alternative - the user's own ordering, and there's nothing to correct
there.

## Per-row download markers (shipped)

A chapter row is `(originId, slug)`, and `path` is a column on that row - chapter 44 from two
different origins is two rows with two independent paths. Downloading one stamps that row alone,
so if ranking later shifts and a different row becomes the winner for that slot, the slot can read
"not downloaded" while the bytes are still on disk, owned by the row that isn't currently winning.
Nothing is lost, and the sweep correctly keeps files any row still references - the marker simply
moved with the winner.

Marking the row rather than the slot is deliberate: both Download and Delete act on a specific
row's file, and marking the slot instead would make Download either a no-op or a silent duplicate,
and Delete reach across to a file the winning row doesn't own. The source switcher
(``ReaderSourceSwitcher``) is where this is made legible - `ChapterSlot.Option.downloaded` (from
`row.path != nil`) marks which alternatives have local bytes, since that's the screen a reader
reaches for after "my download vanished," and it already renders per-row state. It's a snapshot
built once per sheet open, so a download completing while the sheet is open leaves the badge stale
until reopened - live-updating it would mean the sheet observing the download queue for a surface
that only lives a few seconds.

`path IS NOT NULL` means "finished," not "the file exists" - the column can go stale if a file
disappears outside the app's own bookkeeping. A stale path resurrects a chapter that then fails to
open (the reader degrades to `.unavailable`), and the storage sweep clears the column on its next
pass.

## What's still open: preferring a download when the network is gone

Relaxing the listing predicate fixed the disappearance, but it doesn't make the reader *prefer* a
downloaded chapter when the network is unreachable - if a live copy holds the top rank and a
download sits below it, being offline changes nothing today. The two states a chapter-in-a-slot
can be in:

- **Copy A**: available source, not downloaded - better online (fresher, and it works).
- **Copy B**: unavailable source, downloaded - the only one that works offline.

The ranking view can't know which one to prefer, since there's no network state in a SQL view and
putting one there would be a mistake. The shape this wants is a **fallback ordering**, not a
filter or a sort key: A wants to win normally, B wants to exist ranked below it and get used when A
fails. The mechanism already exists in a different guise - the reader's chapter-slot machinery
(``ChapterFill``) already lets a slot be served by a row other than the winner, built for the
manual source switcher. Walking down the slot automatically on a fetch failure, rather than only
on a manual switch, would make this and the source switcher one mechanism instead of two - but
that walk isn't wired up yet.

Two smaller open questions worth carrying alongside it: whether a download should survive a source
being explicitly disabled (currently the reasoning that keeps it available after a source is
uninstalled would say yes, since disabling isn't the same as deleting the download), and that
unread counts will start including download-only chapters from a disabled source once this is
built, which is correct but a number some readers will see move.
