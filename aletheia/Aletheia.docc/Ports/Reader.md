# Reader Port

Tracking the port of alethia-v2's reader engine into `Reader/` (engine) and `Screens/Reader/`
(host). Reference repo: `/Users/admin/Repositories/alethia-v2/apps/ios`. Durable findings that
came out of this port graduated into <doc:ReaderGeometry> and <doc:LiquidGlass> - read those for
the compensation rules and glass mechanics rather than this file.

## What v2 actually was

Two separate things called "the reader" in v2, and the split mattered for scoping the port: an
**engine** (the paging surface, ~4.7k LOC, generic over a data-source protocol, knowing nothing
about series/sources/GRDB) and a **host** (everything user-facing, ~6.8k LOC, entirely
app-specific). The engine's only real dependency was Kingfisher - a Texture/AsyncDisplayKit fork
and a local `Core` package were both declared but **dead** (zero symbols referenced anywhere),
confirmed by stripping both from `Package.swift` and getting a clean build. The port never touched
Texture.

## The decision: modernised UIKit, not SwiftUI-first

Three options were weighed. A pure SwiftUI rebuild (`ScrollView` + lazy stacks +
`.scrollPosition(id:)`) was investigated seriously and rejected on two hard gaps: **zoom has no
SwiftUI API at all** (confirmed against the SDK's own documentation and a symbol-level search of
`SwiftUI.swiftinterface` - the only zoom-adjacent API on iOS 26 exists on `WebView`, because that
wraps `WKWebView`), and **batch prepend is documented-unreliable for chapter-sized batches** -
Apple's own `ScrollPosition` documentation promises to keep an item "visible" on reorder, not
pixel-stationary, and multiple open forum threads report exactly this glitching through iOS 26 with
no fix. A variant that designed prepend out (an anchored reload instead of a seamless splice) was
considered and rejected too, since seamless backwards scrolling into the previous chapter was a
hard product requirement.

What shipped is `UICollectionViewDiffableDataSource` + `UICollectionViewCompositionalLayout`, one
section per chapter - keeping exact offset control and `performBatchUpdates` prepend semantics,
which is what every other shipping iOS comic reader surveyed (Aidoku, Suwatte, Mankai, Paperback)
also converges on at the scroll surface, each independently. This is confirmed as what actually
shipped: ``ChapterWindow``, ``ReaderController``, and the compensation machinery described in
<doc:ReaderGeometry> are exactly this design, live in `Reader/Engine/`.

Zoom is a `UIScrollView` inside the cell (`PageCell`), using two iOS 17.4+ properties
(`transfersHorizontalScrollingToParent = false`, `contentAlignmentPoint`) that remove the manual
gesture-arbitration and centering math v2 needed.

## What ported and what didn't

Of v2's 66 user-facing features, 56 needed no schema change at all and were phase 1. Sessions/
history and external trackers both needed new tables and were deliberately deferred to later
phases - both have since landed as real subsystems (reading history, and AniList/MyAnimeList/
MangaBaka tracking; see <doc:Trackers>). Double-page spreads and six of nine tap-zone layouts
remain deferred - confirmed still absent from `ReaderConfiguration` today.

Bugs found in v2 and deliberately not ported: a `scrollToPage(animated: true)` no-op that
deadlocks every subsequent navigation in continuous mode; a failed preload that permanently
poisons a chapter id with no path back to a ready state; double-page padding placed on the wrong
side for forward insertions; Kingfisher cancellation delivered as failure to a reused cell with no
URL/token check; `layoutSubviews` unconditionally clobbering an active zoom transform on every
neighbor-image completion; and page image requests carrying no auth headers at all, while the
download path already got this right. That last one was fixed on the way in - the port's own
`ReaderScreen` stub already applied the referer modifier correctly from day one.

## Invariants carried forward

- Update the page-index mapping before the collection-view batch update, never after - the reverse
  order crashes.
- Capture a scroll anchor before a layout change, never after - captured-after yields stale
  coordinates.
- On a config change, query the visible page under the *old* reading mode before restoring under
  the new one.
- Cache URL strings for the chapter page cache, never `UIImage` - image memory belongs to the
  image cache, not a second one.
- Empty pages from a fetch is an error, not a valid empty chapter.
- Single-flight concurrent loads of the same chapter, fanning one error out to every waiter.
- `UIUpdateLink` (iOS 18+) for auto-scroll, not `CADisplayLink` and not a timer - frame
  synchronised, no drift, auto-suspends in the background, respects ProMotion.
- Windowing to a handful of resident chapters is mandatory regardless of framework choice - a
  full-resolution decoded page is commonly ~11MB, and the device jetsam budget doesn't leave room
  for holding a whole long series in memory at once.

## Still open

- **Rotation is unhandled.** No `viewWillTransition`/`traitCollectionDidChange` anywhere in the
  reader - confirmed absent from `Reader/` today. Portrait-only for now, kept in the backlog.
- **Downloads don't exist yet.** The reader already has the code path to read a downloaded chapter
  off disk (`SeriesPageSource`), but nothing has ever written one, so that branch has never run. A
  `ChapterDownloader` following `CoverDownloader`'s actor-plus-sweep pattern is the planned shape;
  no schema change needed, since `ChapterRecord.path` and the asset-storing infrastructure already
  exist.
- **Double-page spreads.** Deferred - needs page dimensions known before layout (see
  <doc:PageDimensions>), which the tier-0/1 contract now supports for sources that carry them, but
  the spread-detection and pagination logic itself isn't built.
- **Six of nine tap-zone layouts.** Left/Right split, edge zones, and Kindle shipped; the rest are
  normalised rects away from being a data change rather than a code change.
