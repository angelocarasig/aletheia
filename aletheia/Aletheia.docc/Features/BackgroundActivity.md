# Background Activity

Two operations run in the background and report live progress: chapter downloads and library
refresh. Both live under `Composition/` as `@Observable` classes on `Compositor` -
``Compositor/Downloads`` and ``Compositor/Refresh`` - built on the same shape. A third,
``Compositor/Metadata``, runs on a much slower schedule and deliberately has no live surface at
all - see its own section below.

## The rules

- **Live task state is in-memory only.** Neither operation writes to `reading_event`/
  `reading_session` - those are the reader's own reading, not refresh bookkeeping. The only durable
  output is real data: chapter rows from refresh, `chapter.path` plus files from downloads.
- **Live tasks never become feed rows.** Progress evaporates on completion; only the result lands
  anywhere durable.
- **The live-surface vocabulary is fixed**: current item name, x of N, a determinate bar, cancel.
- **Per-item state lives on the item too.** A downloading chapter shows its state on its own row in
  Details; a refreshing series marks its own library card. This is affordable specifically because
  Observation invalidates whichever surface reads the changed property, and both `active`
  (refresh) and the download index change per-item rather than per-tick, with `LazyVGrid` only
  evaluating visible cells - the blast radius stays a handful of cheap view bodies, not the whole
  grid.
- **iOS surfaces progress in-app, not in notifications**, with one exception: a run that finished
  while the app wasn't open posts one grouped notification. Never per series, never for a run that
  was watched - the live surface already told that story. Silence is the correct outcome for
  "nothing new." Authorization is requested as `.provisional`, so nothing ever interrupts to ask;
  a run replaces its own notification by identifier rather than stacking.

## Where it surfaces

- **The Activity tab's Now section** sits above everything else, always present. An idle row
  settles to a fact ("Library - Checked 2h ago", "Downloads - N chapters stored"); a running
  operation takes its row over with the live vocabulary. Controls (cancel, a chevron into the
  queue) exist only while they're operable.
- **The download queue is its own pushed screen** (``DownloadQueueScreen``), never a tab - per-row
  progress, per-item cancel.
- **Failures are one Now-section row that opens a list**, not dismissable entries. `fetchError` is
  a column, true until the source succeeds, so a dismiss control would either hide something still
  true or need a third "acknowledged" state. One card per *origin*, not per series - a series can
  be healthy on one source and dead on another. Each card carries the reason, when it was last
  tried, a route into Details, and a retry that joins the same per-origin unit a walk would use, so
  retrying while a walk is checking that origin joins the fetch rather than racing it. The list is
  observed, not fetched once - a row disappears on its own the moment that source next answers
  successfully; there's no dismiss button because the list empties itself.

## The background task

Both operations run inside a `BGContinuedProcessingTask` (iOS 26) - the platform's answer to
"user-initiated work must survive leaving the app," scoped specifically to finite work with a
system-drawn progress affordance the user can cancel from. It isn't a scheduled-maintenance API;
that's a separate mechanism (below).

`Compositor.Refresh` and `Compositor.Downloads` each own a `ContinuedTask` wrapper
(`Utilities/ContinuedTask.swift`) that submits the request, ticks scaled progress, and registers a
cancel handler. Progress is reported as a scaled integer (`completed * scale + drift`) rather than
a raw fraction, with an asymptotic drift function nudging the reported value toward (but never
reaching) a ceiling between real ticks - a run that hasn't finished a unit in a while still shows
forward motion rather than going silent, which matters because the system expires a task that
reports nothing for roughly 30 seconds. Finishing always reports a real, non-drifted value.

Library refresh additionally schedules a `BGProcessingTaskRequest` for periodic automatic checks,
re-armed at the end of every run and at launch (never only on backgrounding, which risks the
schedule silently lapsing if that hook is ever missed). The interval is tracked by two separate
timestamps: one for "when was the library last checked" (moves for any run, including a manual
pull-to-refresh) and one purely for the *scheduling anchor* (moves only for an automatic run) -
conflating them would mean an active user who refreshes by hand keeps pushing their automatic
schedule out forever. Since the system may simply never run the scheduled task and gives no
signal when it doesn't, `catchUp()` also checks the interval on every app launch and runs
immediately if a check is overdue.

## Concurrency: the host gate

``HostGate`` (`Network/HostGate.swift`, an actor) is the single place request concurrency is
bounded, keyed by `url.host()` and sitting inside `NetworkService` so every request path - search,
details, chapters, page downloads, `AuthRequester` - funnels through it with no call site able to
bypass it or forget to pass a key.

Two limits at different layers, both fixed constants rather than user settings:

- **3 requests in flight per host.** Several sources are Cloudflare-fronted scrapes rather than a
  published API, and reader page prefetch runs *outside* this gate (through Kingfisher's own
  session), so the true concurrent load at a host can exceed 3 when prefetch overlaps a refresh.
- **6 origins in flight for a library walk**, regardless of host - six across four hosts keeps
  every individual host inside its cap.

Chapter downloads land on the host cap exactly: pages within a chapter download serially (one
request at a time), so N chapters downloading concurrently is N requests at that chapter's host -
which is why chapter concurrency is capped at 3 per source. Adding page-level parallelism inside a
chapter would put more than 3 requests at a 3-slot gate for no benefit, since the extra requests
would simply queue at the gate rather than actually running concurrently.

Two paths stay outside `HostGate`: Kingfisher (reader prefetch and cover display run on their own
session) and WebKit `WebPage` renders (auth capture). Any "requests per host" figure is therefore
a floor, not an exact count.

## Cancellation and failure

Cancel is per-scope: a whole refresh run, or per-chapter/per-series for downloads. Cancelling
mid-run keeps whatever already finished - both operations are idempotent per unit, so partial
completion is just progress, never corruption.

**Cancellation is its own outcome, never a failure.** `OriginRefresher` and `ChapterDownloader`
both catch `CancellationError`/`NetworkError.cancelled` ahead of their general error path and
write nothing - the unit was never asked and never answered, so its dates and error column stay
exactly as they were. Folding a cancellation into the general failure path would log it, count it,
and stamp `fetchError` - technically harmless only if the write itself also gets cancelled by
coincidental timing, which is not a property to depend on.

**Failure is current status, never a run log.** Two columns on `origin` carry it:
`fetchAttemptedDate` (stamped on every attempt) and `fetchError` (set on failure, cleared on
success). A source row shows a failing badge, the stored reason, and "Last tried <relative>" -
deliberately *last tried* rather than *failing since*, since one column can't honestly claim a
first-seen date. Recovery leaves no trace, deliberately - there's no browsable history of past
failures, only whether one is true right now. The run itself continues past individual failures;
one dead source doesn't stop a library-wide walk.

## Metadata refresh

A third background operation, but a different shape from the two above: it re-checks a series'
synopsis, classification, publication, and covers - every source plus every linked tracker, no
chapter fetch - and it never runs inside a `BGContinuedProcessingTask` or shows a live row
anywhere. It's pure background maintenance: a `BGProcessingTaskRequest` on its own interval
preference (weekly/biweekly/monthly, off by default, configured from its own settings screen), or
triggered on demand from Details for one series at a time (its own pill there, independent of the
chapter-refresh pill).

The scheduled walk runs oldest-checked-first (`MIN(metadata.fetchedDate)` per series, nulls
first) rather than always starting from the same place, since the OS can cut a `BGProcessingTask`
off at any point and a truncated run has to be cumulative. Three skip preferences (completed,
unread, not-started) can narrow it. A dead tracker account fails only that account's row, not the
whole run, through the same retry wrapper every other tracker call already uses. Same silence
rule as refresh/downloads: a notification only fires if the run finished while the app wasn't
open.

## Progress granularity

Downloads count pages for a chapter's own progress bar (`store`'s `(done, total)` callback is
already available with no extra plumbing) and chapters for everything above that level - the
queue summary and the background task's reported progress. Byte-level progress within a single
page isn't tracked; a page is a few hundred KB, so a byte-granular bar for it would mostly flicker
rather than inform.
