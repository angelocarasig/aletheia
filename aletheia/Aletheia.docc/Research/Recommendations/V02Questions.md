# Questions for the Orihime v2.0.0 pack, before Swift-side design starts

Everything below comes from directly inspecting the real `orihime-2-0-0-2026.08` pack (file headers,
`.npy` shapes/dtypes, `manifest.json`, `params/blend.json`) - not from `V02Artifact.md`'s prose, which
turned out to disagree with the real pack in several places. Numbered by how much they block Swift work.

**Status:** most of the blocking questions (3, 4, 6) got answered directly rather than by reply - by
reading the training side's own Python source (`~/Repositories/heuresis`) and the real `.mlpackage`/pack
files during implementation. Each is marked below. 1, 2, and 5 are still genuinely open; 7 and 8 were
always informational.

## 1. Which student inference path is real?

`models/student/` has **14 separate `.mlmodel` files**: `student-premise`, `student-protagonist`,
`student-ship`, `student-tone`, `student-world`, and 9 `student-slider-*` (`comedy`, `darkness`,
`fanservice`, `gore`, `pace`, `power_fantasy`, `rise`, `romance`, `tragedy`).

Separately, the same directory has `student-svd.npy` (`f4`, shape `(96, 909)`), `student-linear.npz`
(containing `flag_weights` `f4 (56, 3496)` and `thresholds` `f4 (56,)`), and `student-boost-tags.npy`
(`i8`, 500 entries). `student-layout.json` describes a 909-dim dense feature vector
(`synopsis[384]+flag, title[384]+flag, cover[128]+flag, type_one_hot[6], year_scaled, year_unknown,
popularity, tag_count`) with a scaler mean/scale.

- Do the 14 `.mlmodel` files run directly on some input, or does the app build the 909-dim dense vector,
  project it through `student-svd.npy` to 96-dim, and feed *that* into something?
- What consumes `student-linear.npz`'s 56×3496 weight matrix - neither 909 nor 96 matches 3496, so
  what produces that input?
- What does `student-boost-tags.npy` (500 int64 entries) represent, and where does it plug in?
- Is `student-layout.json` a complete contract for building the input vector app-side, or is a step
  missing that we can't see from the files alone?
- `params/blend.json`'s own params still name this block `student_trees`. Stale label, or a hint that a
  tree-based path exists that supersedes the 14 `.mlmodel` files?

## 2. `appeal.npy` breaks the manifest's own dtype claim

**Not yet answered - not yet needed either.** Appeal is still Phase 4, unbuilt (see `V02Artifact.md`
Deferred), so nothing app-side reads `appeal.npy` yet, regardless of how this resolves.

`manifest.json`'s top-level `vectors_dtype` says `"int8 with per-file *-scale.npy"`. That's true for
`vectors/cover.npy` and `vectors/synopsis.npy` (both `i1` with matching `*-scale.npy` files), but
`vectors/appeal.npy` is actually `f2` (float16), shape `(302894, 80)`, and there's no
`appeal-scale.npy` anywhere in the pack.

Intentional (appeal genuinely ships fp16, the manifest note just doesn't apply to every vector), or is
an int8-plus-scale version missing and expected?

## 3. The real scoring algorithm isn't what the doc describes

**Answered, by reading the source directly.** The full algorithm - candidate filter, per-block soft-fill,
z-score over the candidate set, weighted blend, popularity prior - was ported line-by-line from
`heuresis/blocks/{virtual,base,tags,text,cover,era,format}.py` and `heuresis/blend/blend.py`, not from a
written-out spec. No pool-of-200 step exists in the real algorithm for a virtual/live-compute seed - that
turned out to be `explain()`'s own diagnostic-pool parameter (the top-N shown for a breakdown UI, not a
pre-filter that runs before scoring), not part of the scoring math itself. See `V02Artifact.md`'s "The
compute path" for what actually shipped.

`params/blend.json`'s `scoring` section describes a candidate **pool** (top-200 by raw blended
similarity, before z-scoring) and a **soft-fill** rule ("candidates without evidence for a block get
the block's mean similarity"). Neither appears anywhere in `V02Artifact.md`'s "The compute path"
section, which describes a simpler per-candidate gate-and-renormalise - the same shape v01's `Scorer`
already uses.

Can you write out the full scoring algorithm end to end - pool selection, z-scoring, soft-fill, final
blend - the way `V01Artifact.md`/`PortPlan.md` documented v01's `Scorer.swift` port? This is the single
biggest gap between the doc and what actually needs implementing.

## 4. Is the Core ML text encoder's input shape actually fixed?

**Answered.** Confirmed fixed (not flexible) directly against the real `.mlpackage`'s own input spec via
`coremltools`, not inferred from the tokenizer config. `OrihimeTextEncoder` tokenizes/pads to exactly 512
every time.

`V02Artifact.md` says text-e5-small needs "a fixed 512 sequence length" for Core ML/ANE reasons.
`text-tokenizer/tokenizer_config.json` confirms `model_max_length: 512`, but that's the tokenizer's
own config - not proof the exported `.mlpackage` graph itself has a fixed (non-flexible) input shape.

Can you confirm the actual Core ML input shape spec baked into `text-e5-small.mlpackage` - fixed 512,
or flexible with a documented max? Changes how the Swift-side tokenizer/padding logic needs to work.

## 5. Debug artifact leaked into the shipped `.mlpackage`

`models/text-e5-small.mlpackage/executorch_debug_handle_mapping.json` (128KB) sits inside the shipped
package. Looks like export tooling leaked ExecuTorch debug metadata into a Core ML bundle, not
something the app needs. Can this be stripped from the next build, or is it actually required for
something?

## 6. `manifest.json` isn't shape/offset-typed like v01's

**Answered, by building against it as-is.** `pack_schema: 2`'s shape/dtype-from-each-`.npy`'s-own-header
approach is what shipped (`NumpyHeader.parse`) - no request went back to change the manifest convention,
this was workable and simple enough on its own that it wasn't worth asking for v01's convention instead.

v01's `manifest.json` declares per-array `offset`/`count`/`dtype` so `ModelBundle` can slice mmap'd
files directly. Orihime's `files` dict (264 entries) is only `{bytes, sha256}` per file - shape/dtype
have to come from each `.npy`'s own self-describing header at load time instead. That's a genuinely
different loader strategy, not just new array names, so worth confirming before it's built:

Deliberate for `pack_schema: 2`, or should shape/dtype be added to `manifest.json` to match v01's
convention? Either is workable app-side - just want to build the one that's actually intended.

## 7. Size estimates in the doc are stale (informational, not blocking)

`V02Artifact.md` estimated ~105MB for the rails table; the real `rails/` directory is 53MB. The
compute pieces (`models/` + `vectors/` + `params/`) total ~488MB unpacked, closer to the doc's fp16
estimate (~480MB) than its int8 estimate (~295MB) - makes sense once `appeal.npy` turned out to be
fp16 rather than int8. Real `.aar` (compressed): 387MB. No action needed beyond confirming real numbers
if you have better ones once the pack is final - will update the doc either way.

## 8. Grading gate status

`manifest.json`'s `grade` field is `null`. Confirming: is a Labeller grading run still pending before
this pack should be offered as more than an experiment, per `V02Artifact.md`'s "Deferred" section? Want
to make sure the app-side picker keeps Orihime hidden/experimental-only until that lands, rather than
assuming it's already cleared.

---

If any of the above is based on a wrong premise about how the pack works, say so directly - these are
all inferred from reading files, not from anything you've confirmed.
