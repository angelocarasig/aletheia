# Metrics

How a stat/aggregate query is written against SQLite in this app.

This is the reference behind <doc:Schema>'s rule that metric queries go flat against base tables
rather than through a view.

## Views are macro expansion, and this app's views are aggregation fences

A SQLite view reference is a FROM-clause subquery that the flattening optimizer tries to inline.
When it flattens, cost is zero - but several things block flattening entirely: a window function
anywhere in the view, `LIMIT` inside combined with a join/aggregate/`WHERE` outside, an aggregate
view, a recursive CTE. A non-flattened view runs as a co-routine or gets fully materialized into an
indexless transient table, and predicate push-down doesn't pass through `LIMIT` and is restricted
around aggregates.

`best_chapter` contains a `ROW_NUMBER() OVER (...)` window function - a predicate on its partition
key can push through into the window subquery and use an index, but a predicate on anything else
can't, and either way it's a co-routine over a temp B-tree rather than a flattened join.
`entry_view`/`richful_entry_view` carry correlated aggregate subqueries per row, with the same
consequence. **Metric queries are written flat against base tables** for this reason - the one
sanctioned exception is an unread-backlog count through `best_chapter`, because its ranking
semantics are the view's whole reason to exist and duplicating them elsewhere would drift.

## SARGable date predicates

Wrapping a column in a function for a range filter (`WHERE date(lastReadDate) >= ...`) makes any
index on that column unusable. Range-filter on the raw column; bucket only in `SELECT`/`GROUP BY`:

```sql
WHERE occurredDate >= :cutoff          -- index range scan, cutoff bound from Swift
GROUP BY date(occurredDate, 'localtime')
```

`'localtime'` and `'now'` are legal at read time but can never appear in an index, partial-index,
or generated-column definition - bind cutoffs from Swift instead. GRDB stores `Date` as UTC text
in a lexicographically-ordered format, so both text range predicates and `date()` bucketing work
correctly against it; `substr(col, 1, 10)` is a cheaper UTC day-bucket than calling `date()` when
timezone conversion isn't actually needed.

`generate_series` doesn't exist on iOS's system SQLite - it's a loadable extension compiled only
into the CLI shell, and GRDB links the system library. Generate a date spine in Swift instead.

## Index techniques

- **Covering index** is the target for every stat query - `EXPLAIN QUERY PLAN` should show a
  covering-index search. `COUNT(*)` is always O(N) since SQLite stores no row counts, but scans
  the smallest covering index by default.
- **Partial indexes** (`WHERE inLibrary = 1`, `WHERE progress >= 1`) collapse index size to the
  interesting rows. Matching is strict and mechanical - the query's `WHERE` must imply the index's
  `WHERE` by exact term matching (`progress >= 1` won't reliably match a query written as
  `progress >= 1.0`), and the index's own `WHERE` can't reference subqueries, other tables, bound
  parameters, or non-deterministic functions.
- **Expression indexes** must match the query text exactly as written. A virtual generated column
  (added via `ALTER TABLE`; `STORED` is not addable that way) plus an ordinary index on it is more
  robust, since it's readable and produces the same plan without needing textual matching.
- **DESC indexes** are unnecessary for a single-direction sort - SQLite scans ascending indexes
  backwards for free. Only a mixed-direction `ORDER BY` needs one.

## Reading `EXPLAIN QUERY PLAN`

| Output | Verdict |
|---|---|
| `SEARCH ... USING COVERING INDEX` | target state |
| `SCAN t USING COVERING INDEX` | acceptable - linear but narrow |
| `SCAN t` | acceptable only on small/bounded tables |
| `USE TEMP B-TREE FOR ORDER BY/GROUP BY` | smell - an index could provide the order |
| `... USING AUTOMATIC COVERING INDEX` | loud smell - a permanent index is missing |
| `MATERIALIZE n` over an unbounded source | a fence was hit - restructure the query |

Run `PRAGMA optimize` after migrations and periodically - it fills SQLite's own statistics table
and is self-limiting since SQLite 3.46. Verify a plan holds both with and without those statistics
present, since per-device statistics can produce a per-device plan.

## GRDB observation interplay

`ValueObservation` tracks a region (table, columns, sometimes specific rowids), not values. An
aggregate query with a date-range `WHERE` effectively observes the whole table, so every write to
that table re-runs the fetch - but column granularity is real, and an observation that never reads
a given column isn't woken by writes to it. Prefer one observation per screen over one per tile:
GRDB nesting observations breaks transaction atomicity, so every read for a screen belongs inline
in one `tracking` closure returning one `Equatable` struct, deduplicated with
`.removeDuplicates()` - which filters the notification, not the fetch, so it saves a render, not a
database round trip. `DatabasePool` plus async scheduling keeps the fetch off the main thread even
when the write that triggered it happened there. `WITHOUT ROWID` tables are invisible to
`ValueObservation`, which rules them out for anything that needs to be observed for display.

## Performance reality check

Scans run at roughly 400 MB/s of page bytes on typical hardware; with covering or partial indexes,
essentially every plausible tile query in an app at this scale lands under 10ms. The
over-engineering line for this kind of data sits around a million rows scanned per refresh -
meaningfully more than this schema is likely to hold for a long time. On-the-fly aggregation is
correct at this scale: no triggers, no materialized rollup tables, no summary caching. Revisit
only if a measured query exceeds roughly 30ms on-device or a table passes roughly 500k rows - the
escape hatch then is a watermark-based rollup table, purely additive on top of what exists.

One platform caveat: iOS pins the SQLite version to the OS release, and past OS versions have
shipped real regressions (a severe insert regression in one release, fixed in the next) - check
`sqlite_version()` when debugging an anomaly that looks version-specific.
