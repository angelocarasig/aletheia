# v02: Orihime

What v02 actually became. **Not built in the app yet** - this describes the pack as designed and under
construction on the training-machine side (codename Heuresis/Orihime), verified against this app's actual
code during integration review, not shipped. v01 keeps running throughout regardless of what happens
here. See <doc:V01Artifact> for what v01 is and <doc:PortPlan> for how it shipped; see <doc:V02Integration>
for the product and infrastructure decisions this pack drives on the app side.

## What it is

A successor to the v01 catalogue-similarity engine, same ~303K-title catalogue, a richer blend, and a
capability v01 never had: a full-quality answer for a title that doesn't resolve, not just a degraded one.

The blend adds four blocks to v01's three (tags 0.8, synopsis 0.2, era 0.2): title (0.2, shared rare
words), format (0.1, always on), cover (0.4, **provisional**), appeal (0.2, **provisional**), plus a
popularity prior (0.1) added after the blend and z-scored. Score is `Σ(gate × weight × z) / Σ(gate ×
weight)` - weights are relative, not absolute, so tags at 0.8 is still roughly half the pull on a fully-gated
pair even with four more blocks in the mix. Rail length grew from v01's k=20 to k=60. The two provisional
weights (cover, appeal) are hand-set guesses a Labeller grading run is meant to judge before they're
trusted - exactly the sliders a future preference-fitting pass would tune, see the closing note below.

## Two modes, not one degraded and one full

v01 has a resolved path (exact) and a projected path (tag-only, a deliberately reduced fallback for
whatever didn't resolve). Orihime keeps the resolved path - a precomputed rail lookup, `rails/rows.npy` +
`rails/scores.npy`, answers already computed on the training machine - but replaces the projected path
entirely. An unresolved seed now runs the **same full blend** live, on the phone, from the series' own
local data (title, synopsis, tags, cover, year, format) instead of a cheaper substitute. Resolved is the
fast tier; unresolved is the general one computing the identical recipe, not a fallback.

## The compute path

Three models run on-device for an unresolved seed:

- **Text** - `intfloat/multilingual-e5-small`, Core ML, encodes synopsis and title to 384-d. Needs the
  `"query: "` prefix e5 requires, mean-centring (the mean vector ships in the pack), and a **fixed 512
  sequence length** - a dynamic shape falls off the Neural Engine onto CPU silently, which is why this is a
  conversion-time requirement, not a runtime one.
- **Cover** - MobileCLIP-S0, Apple's own Core ML checkpoint (chosen for exactly this reason), 512-d encoded
  then projected to 128-d.
- **Appeal** - a small classic-ML "student" (linear/logistic parts + gradient-boosted trees, ~7 MB),
  trained to imitate an LLM teacher's appeal questionnaire (tone, premise, romance shape, 56 trope flags, 9
  sliders) from exactly the inputs an unresolved series has. Produces the same 80-number appeal vector a
  catalogue title gets. The teacher/student split matters for the gate: candidate side is 1.0 for a
  teacher-scored title, 0.5 for a student-scored or tags-only one, 0 if absent; seed side is 0 whenever a
  local series has no appeal vector to offer, and the blend **renormalises over the remaining blocks**
  rather than leaving a hole - the same degradation path a thin catalogue title already takes.

Compute-unit assignment, decided per model rather than left to `.all`: text and cover encoders run
`.cpuAndNeuralEngine` (both are ANE-shaped workloads, and excluding GPU keeps it free for the UI); the
student trees run `.cpuOnly` (an ensemble this small gains nothing from ANE/GPU and more would only add
scheduling overhead). The final step - scoring the virtual seed against every catalogue vector,
~300K × (384+128+80) - is not a Core ML operation at all: plain Accelerate/BLAS on CPU, because batching
many seeds at once (the case that would justify Metal) is unnecessary once results are cached, see
<doc:V02Integration>. Budget: encode ~50-150ms, student ~ms, full-catalogue scan ~100-300ms warm - a
prediction from file shapes and access patterns, not yet a measurement (see Deferred, below).

A seed with no synopsis **and** no cover doesn't get a shelf at all - refuse rather than rank on nothing,
the same discipline v01's own divide-by-zero guard already follows.

## What ships

```
orihime-2-0-0-2026.08/
├── manifest.json
├── rails/            seed_rows.npy, rows.npy, scores.npy - the precomputed answers
├── models/            text-e5-small.mlmodelc, text-tokenizer.model,
│                       cover-mobileclip-s0.mlmodelc, student-trees.mlmodelc,
│                       student-linear.npy, student-layout.json
├── params/            text-mean.npy, cover-projection.npy, appeal-idf.npy, blend.json
├── vectors/            synopsis.npy, cover.npy, appeal.npy, appeal_gate.npy,
│                       tags/ (vocabulary.json, row_offsets.npy, tag_ids.npy, tag_weights.npy)
├── titles.npy, year.npy, rating.npy, type.npy, register.npy, popularity.npy, excluded.npy
├── relations/          source_row.npy, related_row.npy, relation_kind.npy
├── aliases/            keys.txt, rows.npy, fixtures.json
└── fixtures/            text-encoder.json, cover-encoder/, student.json, virtual-seed-rails.json
```

One pack, one download, rails and compute shipped together - not a base tier plus an optional add-on. All
arrays flat little-endian, mmap-friendly, same loader architecture as v01. Rough size: ~480 MB (fp16) or
~295 MB (int8, pending a quality check - see Deferred) for the compute pieces, on top of the ~105 MB rails
table. Models ship precompiled (`.mlmodelc`, not raw `.mlpackage`) so the compile cost is paid once at
export time, not on whichever reader opens the feature first.

## Gaps found and fixed during integration

None of these were assumed correct - each was checked against this app's actual code before being
accepted, and two were genuinely missing until this review surfaced them.

- **Alias collisions, preserved rather than collapsed.** v01's defect (<doc:V01Artifact>) was one row per
  name-hash with no way to disambiguate a collision. Orihime's alias table doesn't dedupe at all -
  1,172,114 entries over ~1.09M distinct keys, 60,585 keys naming more than one series (up to 190 for a
  franchise name), duplicates left adjacent for a caller to scan. The app's own `AliasIndex.tally()`
  already votes across a whole title pool instead of taking the first match - built for exactly this fix
  before v01's table ever had a real collision to exercise it.
- **Normalisation mismatch, caught before it shipped.** An early build of the alias table used NFKC, which
  keeps diacritics; the app's resolver (and v01's own spec) uses NFKD with combining marks stripped, which
  doesn't. Silently different match rates on any accented name. Corrected to match exactly, verified with a
  77-case fixture set (crafted edge cases plus 60 real sampled titles), regenerated every pack build from
  the same function that builds the keys rather than a hand-maintained spec.
- **Id width confirmed, not assumed.** `CatalogID` is `Int32` in the Swift port; the pack's `titles.npy` is
  declared `int64` on disk. Checked: the catalogue's max id today is 599,817, nowhere near Int32's ceiling.
  Kept as `Int32`; anything above range is now a validation error rather than a silent trap.
- **Content filtering moved from build-time-only to query-time.** `rating.npy` (four-tier, matches
  `ContentCeiling` exactly) and `type.npy` (matches `CatalogFormat`) were added so a reader's content
  settings filter correctly per query, rather than relying solely on the single ceiling the rails were
  computed under (`suggestive`/comics-only, recorded in the manifest as `rails_ceiling` - stricter reader
  settings still filter down fine; a looser one can't surface anything the rails never considered).
- **Metadata-snapshot alignment, verified with numbers.** Confirmed the catalogue behind Orihime and the
  catalogue behind v01's metadata pack are byte-identical - same sqlite hash, id sets equal in both
  directions, 0 of 147,855 recommendable ids missing metadata today. `manifest.json`'s
  `corpus.catalogue_sha256` is what lets the app enforce this going forward instead of assuming it holds
  after the next monthly rebuild.
- **A trimmed metadata export, for a loader that fails on purpose.** `ModelBundle.load` refuses to start if
  any file its manifest declares is missing from the bundle - deliberate, not a bug. Reusing v01's display
  data without its (large) scoring binaries needed a manifest that only declares what's actually present.
  See <doc:PortPlan> for the fix.
- **Tag vocabulary was missing entirely, and blocked the tag block for the compute path.**
  `vectors/tags/tag_ids.npy` referenced a numeric tag space with no name-to-id dictionary anywhere in the
  pack, so a local series' free-text tags had no way to map into it. Added
  `vectors/tags/vocabulary.json` (2,560 entries). Mapping is normalised exact-name matching only, same
  normalisation discipline as aliases - no fuzzy matching in this version. Common genre/theme tags, which
  carry most of the block's signal, match this way; source-specific or obscure tags simply don't
  contribute. Whether that's sufficient is something the quality ablation measures, not something assumed
  going in. (Unlike v01's `tagvocab.json`, there's no ancestor-hierarchy decay here - Orihime's tag block is
  flat weighted overlap, so that machinery has no equivalent to port.)
- **Year/era data was missing entirely for the compute path.** The rails table never needed it - era was
  already baked into a resolved seed's precomputed score - but an unresolved seed scored live does. Added
  `year.npy` (`int16`, `-32768` sentinel for unknown; the era block's gate goes to 0 when absent, same
  renormalisation the appeal block relies on).

## Deferred, none blocking the current build order

Cold-load and steady-state numbers for the compute path are a prediction from file shapes, not a
measurement - owed once the Swift loader exists, held to the same standard v01's own numbers were (tens of
milliseconds, verified on-device, not assumed). Whether int8 quantisation of the vector files visibly
reshuffles a rail is an open question the quality-ablation step (recompute known titles as if unmatched,
compare against their real rails) is specifically designed to answer before it's decided either way.

## Where the earlier preference-learning research fits now

The Bradley-Terry weight-fitting idea and evaluation rebuild (previously this page's whole subject) aren't
dead, they're deferred. Orihime's own cover (0.4) and appeal (0.2) weights are explicitly marked
provisional - hand-set guesses a Labeller run is meant to judge, which is precisely the problem that
research was aimed at. The difference is sequencing: that work needs real labelled data to fit against, and
Orihime's own build sequence (a Labeller grading pass, an ablation measuring unmatched-mode quality) is
what starts generating it. Properly fitting the provisional weights from reader judgment, rather than
hand-tuning them, is the natural next step once that data exists - not a separate track running in
parallel.
