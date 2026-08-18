# Reader Backlog

What's still missing, dead, or deferred in the reader port. Companion to <doc:Reader>, which holds
the architecture; this file holds the punch list.

## Resolved since this list was last true

**The chapter list is a list of rows, but the app's model is a number line.** The reader used to be
handed a flat list built once at open from the rank-1 chapter row per number - one specific
(origin, scanlator, number) combination. But the app's actual model is that a series is a number
line and any origin may fill any point on it, which is what the source-switch button is for. This
was the reader's biggest structural gap and is now built: ``ChapterFill`` is an actor (slot ->
row) injected into `SeriesPageSource`, and `ReaderViewModel.swap(to:for:)` repoints a chapter at a
different source's copy of the same number, session-only (no schema change, no persistence -
reopening the reader falls back to the ranked default). Read state propagates by number rather
than by row on every write, with the same monotonic guard that stops progress ever regressing, so
swapping to a source you'd read further in on an earlier session doesn't drag it backwards.

This also unblocked the two items that were gated on it:

- **Source icon -> source switcher.** Live. Tapping it now actually changes which source's copy of
  the chapter you're reading.
- **Chapter capsule -> chapter list sheet.** Live - a sheet listing chapters, scrolled to your
  current position, showing what's read.
- **Gearshape -> settings sheet.** Live - side padding, chrome tint, tap-zone layout, flip-sides,
  all through the existing view model setters.

Every overlay control is live.

**Reading direction guessed wrong on first open - fixed.** A series with no explicit orientation
now opens in continuous mode when its tags suggest a webtoon/manhwa/manhua shape, otherwise
left-to-right as before. The guess is non-sticky - the database row stays unknown until the reader
picks a mode explicitly, so tag improvements keep re-applying on future opens, but an explicit pick
always wins permanently.

**Missing-chapters warning - already built, never actually missing.** A forward jump of more than
a chapter renders a warning naming the missing range, via the reader's gap-explanation callback
(confirmed live: `ReaderEngine.onExplainGap`). An explicit jump shows no warning, since you chose
the destination.

**Chapter-change banner - deliberately dropped.** The separator between chapters already names the
one you're entering and the overlay confirms it; a banner would be a third thing saying the same
thing.

## Still open

**Rotation loses your place.** Portrait-only for now; see <doc:Reader>'s "Still open" section - the
three geometry-compensating operations that already exist have no fourth counterpart for a
rotation event.

**Downloads don't exist.** The reader already has the code to read a downloaded chapter off disk;
nothing has ever written one, so that branch has never run.

**Remembering page sizes.** Reopening a chapter re-estimates every page height from scratch rather
than recalling what was measured last time. Tied to double-page spreads below - a spread has to be
known wide *before* layout, so if dimensions are never persisted, spread detection needs them from
somewhere else at open time. See <doc:PageDimensions> for the tier ladder this would plug into.

**Reading history.** Nowhere to review what you've read this week from inside the reader itself
(distinct from the reading-event log that now exists elsewhere in the app - this item is about a
reader-local view, not the underlying data).

**Double-page spreads.** A wide two-page art spread renders squeezed into one page slot instead of
across two. Gated on page-size-before-layout, same as the item above.

## Notes worth keeping

**Scrubber freezing under auto-scroll** was fixed by a general SwiftUI lesson worth restating: a
`@Observable` property read only inside a `Binding(get:)` closure registers no dependency, since
that closure runs outside body evaluation. If the same property happens to be read elsewhere in the
same view's body, the bug hides - auto-scroll exposed it here because it moves the page property
and nothing else, so nothing else was around to trigger the redraw that masked it under manual
scrolling. The fix is reading the property into a local `let` before branching on it.

**A chapter crossed fast enough to never be visibly reported still counts as read.** Chapter
completion used to require a prior visible-page report to know the page count, so a chapter crossed
in milliseconds during a fast scroll was silently never marked read. Completion now carries the
chapter's page count directly from the controller rather than depending on having seen it reported.

**Deleting the manual offset fallback in `flushInvalidation`.** Device logs showed the invalidation
context was always honoured, so the hand-correction fallback never ran - removed rather than kept
as dead weight. `residual` is still logged; a non-zero value now means real drift, not "the
fallback caught it."
