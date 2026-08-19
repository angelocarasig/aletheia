# Activity History

The reading-event log: two append-only tables that record what was read, independent of whether
the series or chapter that produced the record still exists in a resolvable state.

## The schema

``ReadingEventRecord`` (`reading_event`) is one row per chapter completion: `kind`, `seriesId`
(no foreign key), `seriesTitle` (a snapshot), `chapterNumber`, `occurredDate`, `localDayKey`.
``ReadingSessionRecord`` (`reading_session`) is one row per reading sitting: `seriesId` (no
foreign key), `seriesTitle`, `pagesRead`, `chaptersRead`, `startedDate`, `endedDate` (never null),
`localDayKey`.

Both tables are the schema's stated exception to the foreign-key convention (see <doc:aletheia/Schema>) -
history must survive the launch purge and series merges, so joins back to `series` are
best-effort and the snapshot columns are what keep a row readable when the join fails. A series id
isn't even stable long-term: a merge or attach hard-deletes the losing row, and the reading events
that pointed at it would otherwise become permanently unjoinable.

**A session row is inserted complete, never opened and later closed.** `endedDate` is `NOT NULL`
by construction, which makes a stranded open session unrepresentable at the schema level rather
than a bug to guard against at write time - there's no row that can exist half-written if the app
is killed mid-session.

`kind` on `reading_event` exists so a second event type could be added without a new table, but
carries exactly one case today (`chapterCompleted`). Resist pre-declaring a second kind nothing
writes yet - an unused case is exactly the kind of thing that quietly rots into dead UI.

## Why this and not a management log

A parallel idea - logging library-management moments (a series added, a source merge, a chapter
deleted) the same way reading is logged - was considered and rejected. Preventive fixes at the
point of the mutation beat a record of what happened after the fact: a merge that might lose data
is better served by a merge flow that can't lose data than by a log entry explaining that it did.
Every surveyed consumer reading app that keeps any kind of activity log keeps it for reading, not
for management actions - a management log is closer to an admin audit trail, which is not what
this app is.

The one carve-out this doesn't rule out is a purge ledger - a record of what the launch purge
removed, with no UI, purely as a debugging aid if a removal is ever disputed. Not built.

## What consumes it

``StatsViewModel`` reads both tables to drive Reading Activity's charts and heatmap.
``ReaderViewModel`` is the writer - it records a `reading_event` on chapter completion and closes
out a `reading_session` on the reader's own lifecycle boundaries (open, background, close).
`HistoryScreen` exists in the project but is still a placeholder (`Text("History")`) - nothing in
the schema or the write path assumes a particular screen ends up owning this data, so where it
surfaces beyond the current stats charts is still an open question.

## Retention

Kept indefinitely, with no automatic trim. A user-facing clear action is the only retention
control under consideration; nothing enforces a ceiling on row count today.
