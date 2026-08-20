# Fitting Orihime to This App

What changes about how the app carries a recommendation model, now that there's more than one worth
carrying. Describes product and infrastructure decisions only - see <doc:V02Artifact> for the pack itself.
**Not built.** Everything here is a design, verified against the app's actual code during review, not
shipped code.

## From one bundled model to a picker of downloadable ones

v01 shipped as one thing: bundled inside the app, gitignored, always present, never a choice. That was the
right call when there was exactly one model and no alternative to offer. It stops being the right call the
moment a second, heavier model exists that not every reader will want to carry.

The new shape: Settings gets a model picker, closer to a game's language packs than a version bump. Each
model - v01, Orihime, whatever ships after - is a separate download via Background Assets, switchable,
removable independently of the others. A reader who never touches it keeps the app at its current size;
one who wants Orihime's better matching pays for it once, explicitly, and can remove it later without
losing anything else.

This reverses a deliberate earlier decision on purpose. v01's docs argued hard against "download on first
use" - it turns an always-working feature into one with a permanent "not available yet" state. That
reasoning still holds for a single default model with no alternative. It doesn't hold once the whole point
is reader choice: **the feature ships off by default now** - a reader opts in and picks a model themselves,
rather than the app choosing one for them at install time.

## Each pack is fully isolated, on purpose

Considered and rejected: sharing metadata across packs via content-addressed deduplication (two packs with
byte-identical files reusing one copy on disk). Rejected because it only pays off when two packs are built
from the exact same catalogue snapshot, and model generations don't stay in lockstep - v01 and Orihime
already sit on different monthly dumps, a future model will too, so the common case is "different dump
date, no shared bytes" rather than the reverse. The engineering cost of doing this safely (a shared blob
store, reference-counted deletion so removing one pack can't silently break another still pointing at the
same file) buys a saving that mostly wouldn't trigger.

Instead: **every pack is self-contained.** Its own rails, its own compute pieces, its own metadata if it
needs any beyond what a shared reference pack already provides. Removing a pack means deleting its files,
full stop - nothing to reference-count, nothing that can go stale because another pack changed underneath
it.

## v01 doesn't retire when Orihime ships

The original plan (see the early exchanges that shaped <doc:V02Artifact>) was a straight replace - grade
Orihime, delete v01's rails if it doesn't regress. That's no longer the model. v01 stays a permanently
selectable option in the picker alongside Orihime and whatever comes after, the same way a game doesn't
delete an old language pack just because a better-translated one shipped. The **grading gate still
applies** before Orihime becomes trustworthy at all - a Labeller run (Orihime vs. Protostar) has to clear
before it's offered as more than an experiment, covering both the resolved and the new unmatched-mode path
- but clearing that gate is a prerequisite for offering Orihime, not a trigger for removing v01.

## One cache, one source of truth for "what should this series show"

The compute path is expensive enough (encode, profile, score against the whole catalogue, on the order of
a second) that recomputing it on every `Details` open isn't acceptable, the way a v01 rails lookup always
was. Caching the result surfaced a real design smell first: `SeriesRecord.catalogId` (resolution identity)
and a naive "check catalogId, then check a cache table, then compute" call-site pattern would have made two
independently-invalidated stores that need to agree with each other - exactly the kind of hidden dependency
that drifts silently.

The fix: **one table is now the single source of truth.** `recommendation_cache` holds, per
`(seriesId, packId)`: a fingerprint of the local inputs that produced the result (title pool, synopsis,
tags, cover, year, format), the resolved catalogue id if resolution landed (`NULL` if it didn't - a normal,
common shape, not an error state), and the computed rail itself. A `Details` open does exactly one lookup.
Fingerprint matches → render immediately. Fingerprint mismatch or no row → show whatever's cached (if
anything) while a background recompute runs, then write the new row - the same non-blocking shape
`Details` already uses for chapters loading after metadata (`DetailsComposer+Observation.swift`'s reactive
`apply(_ stored:)`, which already fires on any relevant field change with no new "watch for changes"
plumbing needed).

`SeriesRecord.catalogId` as a standalone column is dropped entirely rather than kept as a mirror - nothing
external depends on it surviving (the library backup format already treats a resolved id as
re-derivable, not something that has to round-trip through a restore), so there's no reason to keep two
places holding the same fact. `Compositor.Impressions.owned()`'s bulk ownership query becomes a join
against the new table instead of a flat scan - not a hot path, the extra join costs nothing that matters.

A seed that resolves to nothing scoreable (no synopsis and no cover) still gets a cache row - an empty
rail, cached the same as any other result, so the app doesn't re-attempt a doomed computation on every
open. This is a schema change (new table, one column removed elsewhere) and needs a proper append-only
migration per the project's migration convention, not an edit to an existing one.

## New infrastructure categories, not extensions of existing ones

Checked directly: this app has no existing Core ML, Vision, or Accelerate/vDSP usage anywhere. Everything
built for v01 - and everything the rails half of Orihime needs - is a memory-mapped file read, the same
loader shape throughout. The compute path is a genuinely different category of work:

- **Core ML inference**, for the text and cover encoders and the appeal student. Models ship precompiled
  (`.mlmodelc`) specifically so the compile cost is paid once at export, not on a reader's first open - the
  same "pay it at launch, not on first interaction" principle v01's own page-warming step already follows.
  Compute-unit assignment is decided per model (see <doc:V02Artifact>), not left to the default.
- **Accelerate/BLAS**, for the full-catalogue scoring scan - deliberately not a Core ML operation, since
  batching many seeds at once (the case that would justify Metal) is unnecessary once results are cached
  per series.
- **Background Assets**, for pack delivery - no entitlement, no extension target exists yet. This is real,
  unstarted work independent of everything else here.

Deployment target is iOS 26.0/26.2 (confirmed from the project file), which is generous headroom for Core
ML conversion options - no constraint from the OS floor.

## Where it surfaces

Unchanged from v01: Details' "Similar Titles" rail is still the surface, still per-open rather than
precomputed or scheduled. What changes is invisible to the reader on a resolved seed and, once the compute
path lands, mostly invisible on an unresolved one too - the difference is a roughly one-second wait
(cached after the first time) rather than an empty section. The picker itself is new Settings surface,
scoped separately from this page.
