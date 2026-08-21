# Orihime needs its own display metadata

Follow-up to `V02Questions.md` - a new, separate gap found while designing Phase 2 (the resolved-rail
lookup), not part of that earlier round.

## What's missing

Orihime's pack ships no title text, cover, synopsis, or author/artist data - `titles.npy` is a plain
`int64` catalogId per row (confirmed directly: values match v01's known catalogId range, min 1, max
599817), not a title-text blob. Rating/type/register/year/popularity are all numeric-only too. There is
nothing in the pack a reader could actually read on a rail card.

v01 solves the same problem with an optional companion metadata pack, keyed by the same row order as
its scoring arrays:

```
meta-covers.bin / meta-covers.blob       - per-row cover URL fragment (offsets + utf8 blob)
meta-synopsis.bin / meta-synopsis.blob   - per-row synopsis text (offsets + utf8 blob)
meta-status.bin                          - per-row publication status, one byte, small enum
meta-people.bin / meta-people.blob       - shared name pool + per-row author/artist pointer ranges
```

(`aletheia/Recommendations/V01/CatalogMetadata.swift` if useful reference for the exact shape the app
already reads.) v01 also needs title text itself - a `titles.bin` offsets array + `titles.blob` utf8
blob, parallel to its `ids.bin` catalogId array.

## The ask

Orihime should carry the same kind of data as its own, independent files in the pack - **not** a join
against v01's metadata by catalogId. Confirmed with the prompter directly: Orihime should not depend on
v01's pack being present or byte-compatible for anything it displays.

Concretely, keyed by the same row order `titles.npy`/`rating.npy`/etc already use:

- primary display title (text)
- cover (whatever reference/URL form the pipeline already produces for v01's covers - same
  imgproxy-style URL fragment is fine if that's what's already available)
- synopsis (text)
- authors / artists (name lists)
- publication status

Format is the pipeline's call - matching v01's offsets+blob shape is convenient (the app already has a
working reader for exactly that shape) but not required if something else is more natural to produce
from the training-side data. Whatever's simplest on your end is fine; the app-side reader is small
either way.

## Exact numbers to build against

- Row count: **302,894**, same as `titles.npy`'s shape and `manifest.json`'s `corpus.titles` - every
  new file should be exactly this many rows, same order, no gaps.
- `titles.npy` is sorted ascending by catalogId (confirmed directly) - not required of the new files,
  just context in case it affects how you'd generate row order.
- Please add a version number for this metadata addition the same way v01's own metadata pack has
  `metadataVersion` (`aletheia/Recommendations/V01/ModelManifest.swift`'s `MetadataManifest`) - so the
  app can refuse a future incompatible rebuild explicitly instead of silently misreading it. Doesn't
  need to match v01's numbering, just needs to exist and bump on any shape/format change.
- Same discipline as `corpus.catalogue_sha256` already gives the rails/vectors: if these files are
  generated from a specific catalogue snapshot, a hash the app can check against `corpus.catalogue_sha256`
  (or a note that it's guaranteed to already match, if it's produced in the same build step) would avoid
  a repeat of the alignment work v01's metadata pack needed.

## Status, not blocking anything urgent

Not blocking Phase 2's actual rail-lookup and scoring logic, which needs no display data - that part is
proceeding now regardless. This only blocks the step after it: mapping a filtered rail candidate to
something a reader can actually see on screen.
