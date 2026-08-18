# Database Writes Under Load

> Note: research only. The write-dispatcher and checkpoint-management plan below isn't built - the
> app currently relies entirely on the configuration already described in <doc:Schema>'s gotchas
> and the default GRDB write queue.

How a bulk writer (library refresh, and eventually downloads) would share one SQLite writer
connection with the small user-initiated writes that need to feel instant.

## The governing facts

There's one write lock per database file, held for the entire write transaction, not just at
commit - so the only two variables that exist are how long each write transaction holds the lock,
and who gets it next. WAL mode fixes reader/writer contention (readers never block) and does
nothing for writer/writer contention - two writers still serialize completely.

SQLite's lock arbitration is unfair by design: the busy handler is a sleep-and-poll ladder, not a
queue, so a waiter that's already slept can lose to a fresh arrival. There's no in-process priority
mechanism at all in SQLite - any fairness has to be built above it. And by default, SQLite folds
the write-ahead log back into the main database file on whichever thread's commit crosses the
checkpoint threshold, while that thread still holds the write lock - an otherwise-fast commit can
occasionally take an order of magnitude longer for this reason alone, invisibly.

**On a serial resource, the duration of the in-flight write transaction is the real latency
floor.** A priority scheme can reorder what's waiting; it can't preempt what's already running. This
is why small transaction units matter more than any queue placed in front of them - if only one
fix gets built, this is the one.

## What's already in place

Most of the standard configuration for this already exists: WAL mode with separate reader
connections, `synchronous = NORMAL` (which is load-bearing - it's what makes a WAL commit an append
with no fsync, rather than the "every commit costs an fsync" folklore that applies to the older
rollback-journal mode), immediate-mode transactions on every write (avoiding a snapshot-invalidation
error class that no busy-timeout setting can rescue), and one transaction per logical unit of bulk
work rather than per row or per whole run. No `busy_timeout` is set, deliberately - a single writer
connection makes an in-process "database is locked" error structurally impossible, so if one is ever
seen, the first suspect should be a second writer connection somewhere, not contention.

What GRDB doesn't offer: any of its concurrency-related configuration knobs are pool-wide, not
per-write, and its writer queue is strict FIFO with no priority hook. Any fairness scheme has to be
built above GRDB, not configured into it.

## The two real gaps

**The checkpoint can fire mid-walk.** A first sync of a large library crosses the checkpoint
threshold repeatedly, and each crossing stalls whichever commit triggered it for tens of
milliseconds while holding the write lock - the single largest latency contributor of anything
described here, and the one no ecosystem survey (below) addresses at all.

**Nothing gives a user-initiated write priority over a bulk one.** A tap that writes today waits
behind however many bulk commits are already queued ahead of it, since the queue is plain FIFO.

## The plan, if built

In order of value:

1. **Take the checkpoint off the bulk writer's critical path.** Raise the automatic threshold high
   enough that nothing lands mid-walk, then run an explicit checkpoint once the run finishes and the
   writer is idle - with a size limit on the log file so it doesn't grow unbounded between explicit
   checkpoints in the meantime.
2. **A two-lane write dispatcher above GRDB** - an actor holding an urgent lane and a bulk lane,
   always draining urgent first. This is the only layer where a priority decision can actually
   exist, converting SQLite's documented lack of fairness into a bound this app controls. No aging
   or fairness lottery needed: user writes are rare and single-row, so the bulk lane can't be
   starved by construction.
3. **A yield point between bulk units** - one check per iteration of the bulk walk: if the urgent
   lane has anything waiting, let it drain before starting the next unit. Simple backpressure with
   no estimation or tuning, since the queue depth is a variable this app can read directly rather
   than infer.

Bulk write concurrency should stay at exactly one connection, which is already true today - adding
more writers against a single-writer database would convert queuing delay into lock contention for
no real throughput gain. Parallelism belongs upstream of the database, in fetching and parsing,
which is already where it lives.

## What the ecosystem does instead

Source-read across several comparable readers: not one of them has a write queue, a priority
scheme, a user-write fast path, or a yield point between batches. Every concurrency-limiting
mechanism found in their update paths throttles source/network requests, never database writes.
What they rely on instead is exactly the baseline configuration described above - WAL, sane
transaction boundaries, one writer. Where contention is acknowledged at all, it's handled at the
job level (refusing to start a second bulk run while one is active), not the database level.

This is a consistent negative result, not evidence the problem doesn't matter - it's evidence that
mature, shipped apps get by on the baseline configuration alone in practice, and the checkpoint
stall in particular is invisible enough that nobody appears to have gone looking for it.

## Rejected approaches

Thread QoS or priority doesn't help - priority governs who gets CPU time, not who holds a database
lock, so a high-priority writer arriving second still waits behind whatever's already running.
Sleeping between bulk writes as a throttle is an open-loop cost paid on every write for a problem
that occurs rarely; a yield point that only acts when something is actually waiting is strictly
better. Adaptive network-style congestion control algorithms exist to let a remote controller infer
contention it can't observe directly - this app's dispatcher would be in the same process as the
queue it's managing and can just read the queue depth instead. SQLite's progress-handler callback
can abort a query but has no mechanism to release a write lock mid-transaction, so it can't serve
as a yield point. Splitting bulk and interactive writes across separate database files would create
separate write locks, but cross-database transactions lose atomicity under WAL and lose foreign keys
across the boundary - only viable for a truly independent side table, not this app's schema.
