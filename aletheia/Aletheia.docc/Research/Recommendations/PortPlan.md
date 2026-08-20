# Porting v01 Into the App

The path from "binaries on disk" to a working `Recommender` in the app graph. This describes
infrastructure only - the loader, the two text primitives, the scorer, the payload encoder, the
vocabulary mapping, and the protocol - not the UI surface or the policy for choosing which title
to use as a seed.

**Shipped and live.** ``Compositor`` owns a `recommender: Recommender`, currently a
`V01Recommender`. The code lives at `Recommendations/` (`Contract/`, `Bundle/`, `Engine/`,
`Models/`), mirroring `Network/Sources/` against `Providers/Sources/`, plus
`Providers/Recommenders/V01Recommender.swift`. The Details screen surfaces it as a "Similar
Titles" rail and sheet, one child on `DetailsComposer` (`DetailsComposer+Recommendations.swift`).

## What's in scope, and what isn't

In scope: bytes reaching the device, a loader, the normalisation and hashing primitives, the
scorer, the payload encoder, the vocabulary mapping, and the protocol that lets a second model
replace this one. Out of scope: every UI surface, and the *policy* for turning a library series
into a seed (which titles to offer, what to do with an ambiguous name, whether a reader can
correct a bad match) - that's a product judgement with no fixture to check it against, unlike
everything in scope.

## Decisions that shaped the port

**The model bundle ships inside the app**, gitignored rather than committed (a single file inside
it exceeds GitHub's per-file size ceiling), because the compressed size clears the cellular
download ceiling comfortably and the alternative (download on first use) converts an always-working
feature into one with a permanent "not available yet" state on every consuming surface. A fresh
clone or CI build has no model directory at all and still compiles cleanly - the loader's absent
path is the ordinary state on any machine but one with the bundle populated, not a handled edge
case.

**The port targets v01 exactly as shipped, defects included** (see <doc:V01Artifact>) - its
fixtures are proven reachable, the model can't currently be rebuilt from this machine, and a
corrected bundle isn't available at any price right now. Fixes land later as a rebuilt bundle, not
as a client-side workaround.

**Both a resolved and a projected seed path ship.** Resolution can't be guaranteed for any given
title, and a reader is expected to open the feature on titles the catalogue may not cleanly
resolve. A projected seed runs on the tag block alone - no embedding (the text encoder wasn't
exported) and no era (the app has no local year field) - so where a resolved seed blends three
score components, a projected one blends one. This makes the bundle's own divide-by-zero hazard
(triggered when nothing scoreable is available for a seed) far more reachable than in resolved
mode, since any series whose local tags fail to map onto the bundle's tag vocabulary can hit it -
and `series_tag` being written once at series creation and never refreshed means that's not a rare
path. **The Swift port guards this explicitly**: refuse the query and say why, rather than rank
nonsense.

**The engine returns catalogue identity only, never a `SeriesRecord`** - it never opens the
database, which is what keeps the seed-selection policy out of the engine and the engine out of
the persistence layer.

**A recommendation carries its own display metadata** (cover, authors, synopsis, publication
status), shipped as an additive pack beside the scoring bundle - a recommendation is usually a
series the reader doesn't already own, so it can't be rendered from the local database the way an
owned series can.

## What shipped, measured

- Golden ranking fixtures: exact match, tiny score delta well inside tolerance.
- Text fixtures: full pass on both normalisation and hashing.
- Alias resolution: roughly 90% self-resolution, matching the ceiling <doc:V01Artifact> records.
- Cold load: on the order of tens of milliseconds to map and parse; the memory-mapped bundle is
  never read fully into memory (hundreds of MB resident at launch isn't survivable on a phone).
- A steady-state query: tens of milliseconds.
- Both resolution paths live: an exact tier through a MangaBaka tracker link, a name-vote tier
  across the title pool otherwise, projection when neither lands.

## The API shape

```swift
Payload(titles: [String], tags: [String], synopsis: String?) -> RecommendationSet
```

The app builds the payload from `TitleRecord`'s pool and `series_tag`; the engine resolves or
projects, scores, filters, and returns rows. It never sees a `SeriesRecord`.

A few properties of the result type are deliberate rather than incidental: `catalogId` is the only
field ever safe to persist, since row indices move between bundle snapshots and a persisted row
index would silently point at a different series after a rebuild. `score` is not a 0-1 value and
isn't comparable across separate queries - each block is z-scored over the whole catalogue within
one query, so it runs to roughly plus-or-minus a handful of standard deviations and means nothing
thresholded in isolation; `confidence` is the 0-1, display-only value. Seed-level facts (which
blocks actually ran, how much of the model was used) live once on the result set rather than
repeated on every individual recommendation.

The one genuinely hard primitive is name normalisation, since Swift has no built-in casefold
function - the port resolved this with `.folding(options: .caseInsensitive)`, which performs full
case folding (the same behavior as the reference implementation's casefold, unlike simple
lowercasing), verified against the full fixture set with no special-case table needed.

## Warming

Nothing is computed or cached at launch - a cold start memory-maps the bundle files, parses the tag
vocabulary, and confirms one index is sorted, all in the tens-of-milliseconds range. The cost a
reader actually feels is the *first* query, which pays a real page-fault cost touching the
embedding file for the first time - several times slower than a steady-state query. Rather than
letting that land on whichever series is opened first, the app deliberately touches those pages
during launch (reading one byte per memory page, not running an actual query) so the cost is paid
once, during a launch phase that already shows progress, rather than on the reader's first
interaction with the feature.

## Why there's no Metal

The embedding block was profiled as the dominant cost in a query and initially looked GPU-shaped.
Two things removed the case: parallelising the same block across CPU cores got most of the
available speedup with no new machinery, and it was confirmed there will never be a batch/"for
you"/library-wide scoring path - recommendations are always something asked for right now, never
precomputed - which removed the argument that would have justified a GPU implementation's
complexity (a device, a queue, a shader, a buffer lifecycle, a second implementation of the same
arithmetic to keep in permanent agreement with the CPU one). See <doc:aletheia/Metal> for the full research,
kept as a written standard in case a genuine GPU-shaped need appears later.

## The loader's fail-fast, exercised for real

``ModelBundle/load(in:)`` refuses to start if a manifest declares a file that isn't in the bundle - a
deliberate choice, meant to catch a broken or mismatched deploy rather than let it through as a warning.
It wasn't written with any particular future case in mind, but it became load-bearing sooner than expected:
reusing this pack's metadata half without its (large) scoring binaries, for <doc:V02Artifact>, needed a
manifest trimmed to declare only what's actually present - see <doc:V01Artifact> for the trimmed export
itself. The alternative, a loader that tolerates a declared-but-missing file, was considered and rejected -
weakening the fail-fast to solve one packaging problem would also stop it from catching a genuinely broken
bundle, which is a worse trade than fixing the export upstream instead.

## A resolver built for a defect that hadn't been fixed yet

``AliasIndex/tally(for:)`` scans every candidate in an equal-hash run and votes across a whole title pool,
even though the shipped v01 table can only ever return one candidate per name - the comment above the
function says so, citing the known upstream defect directly. That branch sat dormant through v01's entire
life: nothing in the fixture set or the live bundle ever had a real collision to exercise it. It got
exercised for the first time by <doc:V02Artifact>'s alias table, which deliberately preserves collisions
instead of collapsing them (60,585 keys naming more than one series, up to 190 for a franchise name) - and
the existing voting logic handled it correctly with no changes needed, because it was written against what
the specification always said should happen, not against what the shipped v01 bundle happened to allow.

## Deferred, none blocking the port

The alias-table collapse (fix is a training-machine rebuild, not a client change); the
divide-by-zero guard for the ~72 affected catalogue rows (the Swift guard already ships regardless
of when an upstream fix lands); the undefined-confidence case for rows with no synopsis; the
type-boost constant being reachable only from the payload (projected-mode) path rather than dead
as an earlier read of the manifest assumed; `series_tag` having no provenance or per-tag weight
column; the lack of any evaluation harness for measuring a weight or algorithm change, which
<doc:V02Artifact> is what actually needs it; and no local format field to answer the bundle's type
filter for a resolved seed.
