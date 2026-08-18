# The v01 Model Bundle

What ships in `Resources/Models/v01/` (gitignored - a fresh clone has no model, and the app
compiles and runs fine with the directory empty; see <doc:PortPlan>), and the defects verification
found in it. This describes the frozen v01 artifact itself, not the Swift port - see
``ModelBundle``, ``Scorer``, and <doc:PortPlan> for what's actually built and shipped.

## What it is

A frozen content-based recommender over a large title catalogue (~303K titles), shipped as flat
little-endian binaries plus a manifest - no model to run, no framework to link. A query blends
three z-scored blocks: tag overlap (weight 0.80, tapered by how many tags the seed has), synopsis
embedding (0.20), and publication era (0.20), then hard-filters on content rating, format, BL/GL
register, and an exclusion bit.

Verification reproduced this from the accompanying handover specification alone, without sight of
a reference implementation, and matched 200/200 golden rankings exactly (worst score delta far
inside tolerance) plus 3017/3017 text-normalisation fixtures and 500/500 hash fixtures. That's the
strongest evidence available that the specification omits nothing load-bearing - effort here
shouldn't go toward re-deriving the algorithm.

Two details in the spec that look fussy and are load-bearing: **casefold is not lowercase** (the
fixture set contains cases like `Straße -> strasse` that naive lowercasing gets wrong without
crashing on anything), and the tie-break on score is total and required (ties are common enough in
the top results that any other ordering breaks parity on a meaningful fraction of seeds).

## Defects found, all upstream (in the bundle, not the Swift port)

**The alias table collapses every name to one row, so disambiguation has no input.** The
specification describes scanning an equal-hash run to collect every candidate when a name is
ambiguous, with an explicit worked example of why resolving a collision by popularity is wrong.
The shipped table has one row per hash - no equal-hash runs exist, so that branch can never
execute; the collision was already resolved at build time by a rule the app can't see or
override. Root cause: the exporter's lookup structure is a dictionary keyed by normalised name,
which structurally cannot hold more than one row per name - a comment sitting right above the code
describes an invariant the code beneath it doesn't hold.

Measured effect: resolving each catalogue row by its own primary title, about 90.5% resolves to
itself and 9.5% resolves to a different row. That's a property of the binary, not of any lookup
code built against it, and no app-side work reduces it - fixing it needs a rebuild on the training
machine. This is the ceiling <doc:Integration> means when it talks about a mis-resolution rate the
app inherits.

**A seed with no tags, no synopsis, and no year divides by zero.** The scoring spec accumulates a
weight total from whichever blocks actually ran, then divides by it - all three blocks are
conditional, and a small number of catalogue rows (dozens, not thousands) satisfy none of them.
Not a crash in Swift; it yields infinities and NaNs that propagate through top-k selection into
arbitrary output. **The Swift port guards against this explicitly rather than waiting for an
upstream fix** - see <doc:PortPlan> §4's projected-mode discussion, since this same failure mode
becomes far more reachable once a seed can be built from local (unweighted, occasionally
tag-sparse) data instead of only from the catalogue's own resolved rows.

**Confidence is undefined when the embedding block didn't run.** The confidence formula divides by
a weight sum that still includes the embedding weight even for the ~38% of rows with no synopsis,
where the embedding term was never computed. Whichever reading is intended (drop the term, or
treat it as zero) needs stating explicitly; the currently-calibrated confidence-band thresholds
assume one of them.

**Cosmetic, recorded so nobody chases them:** a manifest constant for a soft type-boost score isn't
used anywhere the exported scorer can reach it (it only fires on payload text extracted at query
time, which the frozen export path doesn't have - it becomes reachable the moment a payload-based
query, i.e. an unresolved/projected seed, is scored); the stated blend weights sum to 1.2 rather
than 1.0, which is correct since the scoring step divides by the actual used-weight total, but
reads oddly at a glance; some headerless binary files coincidentally match other file formats'
magic bytes and are harmless.

## Shape of the corpus

Roughly 303K rows. About half carry fewer tags than the point at which the tag block reaches full
weight, so for most seeds the blend leans on the embedding and era blocks more than the headline
0.80/0.20/0.20 split suggests. About 38% of rows carry no synopsis at all. Roughly a third of the
catalogue is erotica or pornographic under the bundle's four-tier rating - the content ceiling this
app applies (see <doc:Integration>) is load-bearing on most queries, not a rarely-exercised filter.
The BL/GL register hard-filters into three disjoint pools, so a GL seed can only ever see the GL
pool's candidates - by design, not a bug, but it means a GL seed's results visibly thin out in a
way a general seed's never will.

Embeddings are worth their size: dropping them from scoring changes roughly six of every twenty
results against the full-fidelity ranking, which is a different recommender, not a lighter one.
The era block, by contrast, is roughly as load-bearing as the embedding block for a fraction of a
percent of the total bundle size - the best value in the bundle by a wide margin.

## What's not in the bundle

**The text encoder.** Turning a *new* synopsis into an embedding vector needs a separate model that
didn't ship. Without it, a title that resolves to a catalogue row works fully (the row's vector is
already there); a title that doesn't resolve scores on tags alone, which is 80% of the blend
weight. The weights themselves were tuned on a small number of ratings from one person, all of
which resolved to a catalogue row - so tag-only (projected-mode) quality is genuinely unmeasured by
that metric, not merely untested.

Also absent: an author-signal graph and a franchise-relation graph (built upstream, not shipped,
unused by the scoring engine), and any evaluation harness (see <doc:V02Artifact> for why that
matters for anything beyond shipping v01 as-is).

## The metadata pack

A separate set of files gives each catalogue row a cover URL, authors, synopsis text, and
publication status - needed to *render* a result, not to *rank* one. It's derived straight from the
catalogue (an exact join on catalogue id, verified both directions on a large random sample) rather
than from the fitted model, so it needed no refit and doesn't touch any scoring byte; both halves
verify their own checksums independently. Row order is pinned to the catalogue snapshot the model
was fit against - a newer database snapshot shifts row identity, so the pack has to be regenerated
alongside the model, not on its own schedule.

Two things worth knowing if this pack is ever touched again: cover URLs are the *upstream*
provider's own image URL, not a rehosted one, and only a small fraction are the catalogue's own
hashed path - a sized variant is derivable exactly (a fixed CDN prefix plus urlsafe-base64 of the
raw URL, padding stripped) rather than needing to be stored per size. And the catalogue's ids are
the same ids a linked tracker service already uses for this catalogue - see <doc:Integration> for
what that makes possible.
