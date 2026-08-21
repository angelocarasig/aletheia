# v02: Orihime

What v02 actually became. **Built and running on-device**, not just designed - the resolved-rail lookup,
both live-compute paths, and the on-device text/cover encoders are real, working Swift, verified against
real fixtures from the pack (codename Heuresis/Orihime) rather than assumed from its docs. Not yet offered
to readers as more than an experiment - the grading gate <doc:V02Integration> describes still hasn't run.
v01 keeps running throughout regardless. See <doc:V01Artifact> for what v01 is and <doc:PortPlan> for how
it shipped; see <doc:V02Integration> for the product and infrastructure decisions this pack drives on the
app side.

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

## Three tiers, not one degraded and one full

v01 has a resolved path (exact) and a projected path (tag-only, a deliberately reduced fallback for
whatever didn't resolve). Orihime replaces that two-tier shape with three, discovered once the resolved
path was actually wired up end to end: roughly half the catalogue resolves to a real row with **no**
precomputed rail (the training side only precomputes the seeds it expects to matter, not every row), so
"resolved" and "has an answer ready" turned out to be different things.

- **Rail hit** - a precomputed rail lookup, `rails/rows.npy` + `rails/scores.npy`, answers already
  computed on the training machine. The fast tier, roughly half the catalogue.
- **Resolved, no rail** - a real catalogue row with nothing precomputed for it. Scored live,
  `OrihimeRecommender.liveScore()`, but *without* any on-device encoding: the row's own tag/synopsis/cover
  vectors and year already live in the pack, so this is a direct row-to-row comparison against the whole
  eligible catalogue (`OrihimeScorer.score(seedRow:relatedRows:...)`), same block math as the rail
  builder used, just run on the phone instead of ahead of time. Cheaper than the third tier - nothing to
  encode.
- **Unresolved** - nothing in the catalogue at all. Scored live from the series' own local data (title,
  synopsis, tags, cover, year), `OrihimeRecommender.projected()` - this is the tier that needs the
  on-device text/cover encoders, since a title with no catalogue row has no stored vectors to read.

All three run the **same full blend recipe** (`OrihimeScorer`, `OrihimeBlendSpec` reading
`params/blend.json` at runtime rather than hardcoding its weights) - "resolved" and "unresolved" differ in
where the seed's own evidence comes from, not in what gets computed with it.

## The compute path

Two models run on-device for an unresolved seed, both real and working (`OrihimeTextEncoder`,
`OrihimeCoverEncoder`); a third is still Phase 4, not started, deferred on purpose - see Deferred, below:

- **Text** - `intfloat/multilingual-e5-small`, Core ML, encodes synopsis and title to 384-d. Needs the
  `"query: "` prefix e5 requires, mean-centring (the mean vector ships in the pack), and a **fixed 512
  sequence length** - a dynamic shape falls off the Neural Engine onto CPU silently, which is why this is a
  conversion-time requirement, not a runtime one. Confirmed fixed (not flexible) directly against the real
  `.mlpackage`'s own input spec, not assumed from the tokenizer config.
- **Cover** - MobileCLIP-S0, Apple's own Core ML checkpoint (chosen for exactly this reason), 512-d encoded
  then projected to 128-d.
- **Appeal** *(not built)* - a small classic-ML "student" (linear/logistic parts + gradient-boosted trees,
  ~7 MB), trained to imitate an LLM teacher's appeal questionnaire (tone, premise, romance shape, 56 trope
  flags, 9 sliders) from exactly the inputs an unresolved series has. Would produce the same 80-number
  appeal vector a catalogue title gets. The teacher/student split matters for the gate: candidate side is
  1.0 for a teacher-scored title, 0.5 for a student-scored or tags-only one, 0 if absent; seed side is 0
  whenever a local series has no appeal vector to offer, and the blend **renormalises over the remaining
  blocks** rather than leaving a hole - the same degradation path a thin catalogue title already takes.

**Two real bugs, both found by comparing the encoders' own output against the pack's golden fixtures
(`fixtures/text-encoder.json`, `fixtures/cover-encoder/expected.json`) rather than trusting either
encoder's default behaviour:**

- **Text tokenizer.** `swift-sentencepiece`'s `tokenOffset` mechanism assumes a generic uniform shift for
  every special token, which is not how XLM-RoBERTa's real id layout works - its `<s>`/`<pad>`/`</s>`/`<unk>`
  ids aren't a uniform offset from the raw SentencePiece model's own ids (confirmed by loading the real
  `.model` file and `tokenizer.json`'s `added_tokens` directly with the `sentencepiece` and `coremltools`
  Python packages, not by trusting either library's docs). Cosine similarity against the golden fixtures sat
  at 0.87-0.95 worst-case with the library's default offset. Fixed by tokenizing with `tokenOffset: 0` (raw
  ids) and hand-remapping to the pack's real ids; worst-case cosine now 0.94, the remaining gap explained by
  the fixtures' own fp16 rounding.
- **Cover crop/scale.** `MLFeatureValue(cgImage:constraint:options:)` with `options: nil` leaves Core ML to
  pick an undocumented default crop/scale strategy. MobileCLIP, like every CLIP-family model, trains on
  resize-shorter-side-then-center-crop, not stretch-to-fit - worst-case cosine against the fixtures was 0.73
  with the default. Fixed with an explicit `.centerCrop` option; worst-case cosine now 0.93.

Both fixes were verified on a real device against the golden fixtures via DEBUG-only probes, since removed
once they'd done their job (their job being exactly this verification, not standing regression coverage -
there's no test target for this app, matching v01's own probe-then-delete precedent in
<doc:V02Integration>).

The live-compute scoring algorithm itself (soft-fill, z-score-over-candidates, the weighted blend, the
per-block gate formulas) was ported line-by-line from the training side's own Python
(`heuresis/blocks/{virtual,base,tags,text,cover,era,format}.py`, `heuresis/blend/blend.py`), not
reimplemented from this doc's prose - the prose had drifted from what the training side actually does in
several places (see `V02Questions.md`, largely resolved this way rather than by a reply). One real gap the
source made explicit rather than papering over: the **title block needs per-word document frequencies
across the whole catalogue**, which the pack doesn't ship (`blend.json`'s own `virtual_seed.title_block`
note says exactly this) - it stays permanently gated off on-device, at gate 0, for the same reason appeal
above stays unbuilt: the pack side doesn't yet expose what it needs.

**The format block is gated off too, for a different, non-pack reason**: no source this app scrapes
reports a series' format (manga/manhwa/manhua/...) at all - confirmed by reading `SourceDTOs.SeriesDetail`,
the type every installed source's scraper actually returns, which has no such field. This isn't a missing
pack file, it's missing app-side data acquisition - would need new scraping work per source before the
block could ever fire on-device.

Compute-unit assignment, decided per model rather than left to `.all`: text and cover encoders run
`.cpuAndNeuralEngine` (both are ANE-shaped workloads, and excluding GPU keeps it free for the UI); the
(unbuilt) student trees would run `.cpuOnly` (an ensemble this small gains nothing from ANE/GPU and more
would only add scheduling overhead). The full-catalogue scoring scan - up to ~300K rows × (384 + 128 + tag
CSR) - is not a Core ML operation at all: plain Accelerate/vDSP on CPU, because batching many seeds at once
(the case that would justify Metal) is unnecessary once results are cached, see <doc:V02Integration>.
Measured on a real device during development (not the file-shape prediction this section used to carry):
roughly 0.2-1s end to end depending on which blocks fire (era's full-catalogue pass is the next most
expensive after the dense synopsis scan), dominated by the scan rather than either encode.

A seed with no synopsis, no cover, **and** no matched tags doesn't get a shelf at all - refuse rather than
rank on nothing, the same discipline v01's own divide-by-zero guard already follows.

## What ships

```
orihime-2-0-0-2026.08/
├── manifest.json
├── rails/            seed_rows.npy, rows.npy, scores.npy - the precomputed answers
├── models/            text-e5-small.mlpackage, cover-mobileclip-s0.mlpackage,
│                       text-tokenizer/ (sentencepiece.bpe.model, tokenizer.json, ...),
│                       student/ (14 .mlmodel files, student-svd.npy, student-linear.npz,
│                       student-boost-tags.npy, student-layout.json) - unread, Phase 4
├── params/            text-synopsis-mean.npy, text-title-mean.npy, cover-projection.npz,
│                       appeal-idf.npy, era-tag-trend.json, blend.json
├── vectors/            synopsis.npy + synopsis-scale.npy + synopsis_gate.npy,
│                       cover.npy + cover-scale.npy, appeal.npy, appeal_gate.npy,
│                       tags/ (vocabulary.json, row_offsets.npy, tag_ids.npy, tag_weights.npy)
├── titles.npy, year.npy, rating.npy, type.npy, register.npy, popularity.npy, excluded.npy
├── relations/          source_row.npy, related_row.npy, relation_kind.npy
├── aliases/            keys.txt, rows.npy, fixtures.json
├── display/            titles/covers/synopsis/authors/status, offsets+blob, metadata.json
└── fixtures/            text-encoder.json, cover-encoder/, student.json, virtual-seed-rails.json
```

One pack, one download, rails and compute shipped together - not a base tier plus an optional add-on. All
arrays flat little-endian, mmap-friendly, same loader architecture as v01. Rough size: ~480 MB (fp16) or
~295 MB (int8, pending a quality check - see Deferred) for the compute pieces, on top of the ~105 MB rails
table.

**Models ship as source `.mlpackage`, not precompiled `.mlmodelc`** - reversed from what this section used
to say. The original plan was precompiled specifically so the compile cost lands once at export time rather
than on a reader's device; that reversed once Background Assets delivery meant there was no Mac-side hop
between the pipeline and the app to run `xcrun coremlcompiler` against. The app compiles each `.mlpackage`
on-device the first time it's needed (`MLModel.compileModel(at:)`, `OrihimeModelCache`) and persists the
result, keyed by pack id and build date, so the cost is paid once per pack per device rather than once at
export - see <doc:V02Integration> for the full reasoning and the cache-staleness lessons that keying
convention already had to learn from elsewhere in this pack.

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

- **Appeal / the student ensemble** (Phase 4). Not started, deliberately split from encoders-plus-scorer
  (Phase 3, done) rather than attempted all at once. The 14 `.mlmodel` student files, `student-svd.npy`,
  `student-linear.npz`, and `student-boost-tags.npy` sit unread in the pack until this phase starts -
  `V02Questions.md` Q1's questions about how they actually chain together are still open, not resolved by
  anything built so far.
- **Title block.** Permanently gated off on-device, not deferred to a later phase - the pack doesn't ship
  the per-word document frequencies it would need, and nothing about that is a compute-path limitation, see
  "The compute path" above.
- **Format block.** Permanently gated off, for a reason that has nothing to do with this pack - no
  installed source reports a series' format at all, see "The compute path" above.
- Whether int8 quantisation of the vector files visibly reshuffles a rail is an open question the
  quality-ablation step (recompute known titles as if unmatched, compare against their real rails) is
  specifically designed to answer before it's decided either way.
- The Labeller grading run (Orihime vs. Protostar) that has to clear before this pack is offered as more
  than an experiment - see <doc:V02Integration> - hasn't happened. `manifest.json`'s `grade` field is still
  `null`.

## Where the earlier preference-learning research fits now

The Bradley-Terry weight-fitting idea and evaluation rebuild (previously this page's whole subject) aren't
dead, they're deferred. Orihime's own cover (0.4) and appeal (0.2) weights are explicitly marked
provisional - hand-set guesses a Labeller run is meant to judge, which is precisely the problem that
research was aimed at. The difference is sequencing: that work needs real labelled data to fit against, and
Orihime's own build sequence (a Labeller grading pass, an ablation measuring unmatched-mode quality) is
what starts generating it. Properly fitting the provisional weights from reader judgment, rather than
hand-tuning them, is the natural next step once that data exists - not a separate track running in
parallel.
