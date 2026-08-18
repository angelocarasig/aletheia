# Reader Geometry

How the continuous reader keeps your place when content around you changes size.
`Reader/Engine/ReaderController.swift` is the only file this describes.

## The one rule

**Three operations mutate content above the reader. All three must compensate, through the same
anchor.**

| Operation | Where | What moves |
|---|---|---|
| insert a chapter above | `apply(_:for:)` | everything below the insert |
| resize a page above, once its image lands | `record(size:for:)` -> `flushInvalidation()` | everything below that page |
| remove a chapter above, on eviction | `remove(_:)` | everything below the removal |

That's the complete set. A fourth operation that changes extents above the viewport has to join
them or it throws the reader forward or back by whatever it changed.

## The single extent function

`extent(of:width:)` is the sole source of scroll-axis size. The layout, the insert sum, and the
compensation walk all go through it, so `contentSize` and the compensation walk can't disagree -
that disagreement is the class of bug this whole system exists to prevent.

Two things it keeps straight: paged modes size every cell to the viewport (an image ratio is never
the extent there, and a separator has no ratio at all); a separator's height is declared, never
measured (`ReaderSeparatorModel.height` is arithmetic over its slots) - a cell that measures itself
after appearing would land after the geometry walk and drift the compensation.

## Compensation techniques

- **Insert - exact sum.** Sum `extent` over the items being inserted; add to the offset. Exact
  because the layout is a plain stack. Deliberately not read back off `contentSize`, since a
  resize can slip in across the apply-snapshot boundary and corrupt the delta.
- **Resize - fractional anchor.** Bank the delta of anything above, apply on flush. Measured
  against the offset plus any pending adjustment, not the live offset alone, since `sizes` already
  holds the batch's earlier corrections while the layout hasn't re-run yet. A page straddling the
  top edge moves the art by only the fraction above the fold - fractional, not all-or-nothing,
  because that page is the one under the reader's thumb.
- **Remove - anchor by identity.** Hold the item under the reader, drop the chapter, find that
  same item again, restore its position. Identity rather than index, because the index space is
  about to lose a whole chapter. One formula covers above/below/straddling with no reasoning about
  which side the removed chapter was on.

## Why not `setContentOffset`

Resize compensation goes through
`UICollectionViewLayoutInvalidationContext.contentOffsetAdjustment`, so UIKit folds the move into
the same layout pass. `setContentOffset(_:animated: false)` halts deceleration and fires
`scrollViewDidEndDecelerating` - fine for a prepend, which is one discrete event, but resizes fire
repeatedly as images land, and doing this per-image would repeatedly stop a fling mid-scroll.

Two API details worth knowing: `invalidateEverything` is get-only on the base class (it's what
UIKit sets for a bare `invalidateLayout()`) - override it in a subclass to force it. And a full
invalidation is mandatory, since the layout bakes heights into a group's absolute total at
section-provider time, so anything less reuses cached sections and new measurements never land.

## Estimation

Heights are needed before images arrive, in order of preference: the page's real size (from the
source, or measured on load - see <doc:PageDimensions> for where a source-supplied size comes from
and how it's graded), the chapter's learned ratio (median of the first few measured pages,
capped), or a per-orientation constant. Median, not mean, so one double-page spread can't drag
every remaining estimate. Ratios survive chapter eviction on purpose - a chapter that comes back is
laid out correctly on the first pass.

The learned ratio must update inside the resize bracket - when it lands, every unmeasured page in
that chapter changes height at once, and updating outside the bracket reintroduces the jump at
larger amplitude.

## Eviction

`ChapterWindow` evicts the chapter furthest from the one being read, in reading order - not LRU.
`touch(_:)` marks "this is the chapter being read," and is what distance is measured from. LRU
picks the wrong victim under normal scrolling back and forth, since it has no notion of reading
distance. Eviction still needs the remove compensation above - choosing a better victim doesn't
make removal free.

## Reading direction

Derived from reading-order position, never coordinates: `semanticContentAttribute =
.forceRightToLeft` mirrors the layout, and each mode carries its own axis sign. Direction compares
`(slot in order, index in chapter)` - slot in the reading order, not flat item index, since a
prepend shifts every flat index and would report a phantom backward jump.

## Verification

Keep the `reader.layout` log category on when touching any of this. What correct looks like in the
log: an `offset` that moves with its `adjust` value (equal-to-itself means no compensation
happened), `residual 0` (non-zero means the invalidation context was dropped and a fallback ran
instead), and an evict's offset delta matching the removed chapter's extent arithmetic exactly.
Manual check: fling upward through a freshly prepended chapter with a cold image cache - scrolling
must not stutter, must not stop mid-fling, and the art under the thumb must not translate.

A prepend restore moving further than a viewport can otherwise splice the wrong chapter above the
reader silently - the general lesson is that a programmatic offset write invalidates layout, it
doesn't perform it, so anything reading "what's centre-screen now" has to query fresh layout
attributes rather than a cached visible-items set. Three depth counters hold this invariant today:
`navigating` on the engine (gates preload against an in-flight navigation), `mutations` on the
controller (gates the visible-page reporter against an in-flight geometry mutation), and
`!loaded.contains(chapter)` in `apply` (a duplicate section identifier is an uncatchable UIKit
exception, so re-applying a resident chapter is a no-op instead).

## Known open

**Rotation is uncompensated.** There's no `viewWillTransition`/`traitCollectionDidChange` handling
in the reader at all, so rotating is an unanchored relayout.

**Prepend compensation is unverified under right-to-left.** The restore and remove math both
assume flat item 0 sits at the lowest scroll-axis coordinate, which depends on a compositional
layout flag that couldn't be confirmed from documentation alone. If the layout mirrors natively, a
prepend doesn't move existing items at all, correct compensation is zero, and the current math
would throw a right-to-left reader forward by a whole chapter. Settling it needs one device log
under that layout direction.
