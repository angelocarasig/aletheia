# Rails table has no per-block breakdown or confidence

**Superseded - never sent.** The app dropped the confidence badge and Tags/Story/Era meters entirely
(both v01 and v02) instead of asking for this data - cheaper than a pipeline round-trip plus a real
pack-size cost for a display-only breakdown, and one less thing v02 needs before it can produce a real
`Recommendation`. Kept here as the record of why that data gap exists, not as an open ask.

Follow-up to `V02Questions.md`/`V02MetadataRequest.md` - found while wiring the resolved-rail path up
to the app's `Recommendation` type.

## What's missing

The app's `Recommendation` struct (`aletheia/Recommendations/Models/Recommendation.swift`) has two
fields the rails table can't currently fill:

- `blocks: Blocks { tag: Float, embedding: Float, era: Float }` - a per-block similarity breakdown,
  shown alongside a result so a reader can see *why* something matched (e.g. "tags: 0.8, era: 0.3").
- `confidence: Float` - a display-only 0...1 number, separate from `score`.

`rails/scores.npy` stores exactly one number per candidate - the final blend, after all seven blocks
(tags, synopsis, era, title, format, cover, appeal) are combined. The per-block similarities that went
into that number aren't in the pack anywhere; once they're summed, they're gone. Same for confidence -
nothing in the rails table represents it.

v01 can fill both fields because its own on-device `Scorer` computes the blend itself, block by block,
and keeps each piece around before combining. Orihime's resolved path is a lookup, not a computation -
there's no scorer running on-device to keep intermediate values from.

## The question, not yet a firm ask

Two options, and this genuinely needs your read on the cost before deciding:

1. **Ship per-block similarities alongside `rails/scores.npy`** - e.g. a `rails/block_scores.npy` shaped
   `(seeds, k, 7)` instead of `(seeds, k)`, one column per block. Real cost: this is a real storage
   multiplier on the rails table specifically (currently ~53 MiB) - a 7x column growth would land
   somewhere around that multiple, not free. Worth knowing the actual number before deciding whether
   it's worth it just for a display breakdown.
2. **Ship a single confidence number** (`rails/confidence.npy`, `(seeds, k)`, same shape as `scores.npy`)
   without the full per-block breakdown - much cheaper, answers half the need.

Also worth flagging on the app side, not something to solve on yours: `Blocks` is currently a fixed
3-field struct built around v01's exact 3 blocks (tag/embedding/era). Orihime has 7. Even with per-block
data in hand, the app would need to decide how (or whether) to reshape `Blocks` for a 7-block model -
that's our decision, not blocking this question to you.

## Status

Not blocking anything currently in progress - Phase 2a (rails lookup + content filtering) is done and
verified. This only affects whether Phase 2b (the actual `Recommendation`-producing adapter) ships with
real `blocks`/`confidence` values or a placeholder, honestly zero-filled with a comment saying why,
until this is answered.
