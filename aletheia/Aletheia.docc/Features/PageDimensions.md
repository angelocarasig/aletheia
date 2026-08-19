# Page Dimensions

How the app learns the pixel dimensions of chapter page images, and what the reader does with
them. Only continuous (`.infinite`) layout consumes measured sizes today - paged modes size every
cell to the viewport instead.

See <doc:ReaderGeometry> for how a resize compensates once a real size lands.

## The contract

`PageURL.size` is an optional hint, never ground truth:

```swift
struct PageURL: Sendable {
    let index: Int
    let url: URL
    let size: PageSize?
}

struct PageSize: Sendable, Equatable {
    let width: Int
    let height: Int
    let exactness: Exactness

    enum Exactness: Sendable { case exact, ratio }
}
```

- Only bytes-derived dimensions (a header parse or an actual decode) are ever authoritative. A hint
  pre-sizes layout; decode reconciles it.
- Width and height describe the *displayed* image, post EXIF-orientation, in pixels, for the exact
  file the url serves - a hint never transfers across a quality/data-saver variant, since that's a
  different file with different dimensions.
- `.ratio` exists because scraped attributes are frequently viewer-normalised (a site's own reader
  showing `width="700"` with a float height scaled to it) - ratio is trustworthy there, absolute
  pixels aren't. A `.ratio` hint may drive an aspect-ratio placeholder but never a split or a
  texture-size decision.
- `nil` means the source knows nothing, and that's always legal - no source is ever required to
  make an extra request to fill it in.

## Where dimensions actually come from - the tier ladder

Every page resolves its dimensions through the first tier that answers. A source implementation
only ever participates in tiers 0-1; the rest are app-side and source-agnostic.

| Tier | Name | Cost | Grade |
|---|---|---|---|
| 0 | provider-supplied | zero | `.exact` |
| 1 | scrape-supplied | zero | `.ratio` by default, `.exact` if verified once per source |
| 2 | in-band extraction, during the real image download | zero extra requests | authoritative |
| 3 | out-of-band probe, pages outside the prefetch window only | one small ranged request | authoritative |
| 4 | estimation | zero | placeholder |

**Tier 0** is free by definition - the payload a source already fetches states dimensions, and
they're simply plumbed through instead of discarded. **Tier 1**, for HTML sources, is most
reliable from inline JSON hydration state, then explicit `width`/`height` attributes, then
filename/URL patterns, roughly in that order of trust. **Tier 2**, the universal path, extracts
dimensions from the first bytes of the real image download the moment they resolve, via an
incremental `CGImageSource` fed from the byte stream - one request, no cache pollution, no double
fetch. For manga-reality formats (overwhelmingly JPEG, then PNG, then WebP), dimensions resolve
within the first network chunk essentially always. **Tier 3** is only for pages far outside the
prefetch window and never for a single-use signed URL, since probing then re-fetching pays for the
image prefix twice. **Tier 4** falls back to a per-chapter learned ratio, then a per-orientation
constant - see <doc:ReaderGeometry>'s Estimation section for how that estimate feeds the
compensating layout math.

## Per-provider status

Grades: `.exact` = pixel dimensions of the served file; `.ratio` = the ratio is trustworthy, the
pixels aren't; `-` = no dimensions available, tier 2-4 only.

| Source | Dims | Grade |
|---|---|---|
| MangaFire | `width`/`height` per page in its chapter-content response, non-optional | `.exact` |
| NHentai | `width`/`height` per page in its gallery payload | `.exact` |
| Atsumaru | optional `width`/`height` per page | `.exact` when present |
| MangaDex | no per-image dimensions in its API, and a past proposal to add them was rejected | - |
| WeebCentral | no dimensions in its HTML fragment response, no `data-*` hints | - |
| ScansGG, Toonily, MangaBall | no dimensions supplied | - |

For a source with no dimensions, tiers 2-4 apply automatically with no special-casing.

## Technique reference for tiers 2-3

**HEAD is a dead end.** No standard HTTP header carries pixel dimensions - they live only in the
entity body, which HEAD omits, and HEAD is also strictly worse for everything else (some CDNs
reject it outright, bot heuristics score it as scraper-like, it warms no cache). A ranged GET
returns every header HEAD would plus a body prefix, in the same round trip.

**Ranged GET.** The only reliable way to know if range requests are honoured is sending one and
checking for a `206` - `Accept-Ranges` is advisory. A `Content-Range` header on a `206` gives the
full byte size for free. A cold object can return `200` full-body instead of `206`; always handle
that by cancelling after a byte budget.

**Trust nothing about the response.** Manga CDNs routinely serve WebP mislabeled as JPEG - never
branch a parser on `Content-Type` or file extension, sniff the magic bytes instead. Run the
source's own challenge detection on probe responses too, since a Cloudflare interstitial is a
`200` full of HTML.

**Where dimensions live per format** (magic bytes, offsets): PNG's IHDR is mandatory and first (big
-endian width/height at fixed offsets); GIF's canvas size sits right after the header; JPEG
requires walking segments to find the frame marker, with height *before* width, both big-endian -
large embedded thumbnails or ICC profiles can push this deep into the file; WebP has three distinct
sub-formats (VP8/VP8L/VP8X) each with its own bit layout; AVIF/HEIC need a real ISOBMFF box walk
(`ispe` associated via `pitm`/`ipma`, since a naive first-box read can return a thumbnail or a grid
tile) - use ImageIO for this rather than hand-rolling it. A 16KB first read covers effectively all
real manga pages; escalate only on the rare JPEG whose frame marker sits deep.

**EXIF orientation matters.** Values 5-8 mean the displayed width/height are the swap of the
encoded dimensions - ImageIO's raw pixel-width/height keys are pre-orientation, so the orientation
key has to be read and the swap applied explicitly. Store the post-swap, displayed dimensions
everywhere downstream, one convention throughout.

**The incremental probe primitive**, the mechanism behind tier 2:

```swift
let src = CGImageSourceCreateIncremental(opts)  // kCGImageSourceShouldCache: false
// per chunk:
CGImageSourceUpdateData(src, accumulated as CFData, false)  // the whole accumulated buffer, not a delta
if let p = CGImageSourceCopyPropertiesAtIndex(src, 0, opts) as? [CFString: Any],
   let w = p[kCGImagePropertyPixelWidth] as? Int,
   let h = p[kCGImagePropertyPixelHeight] as? Int {
    // dimensions resolved - publish, keep downloading
}
```

Pass the whole accumulated buffer on every update, never a delta. There's no completion callback -
poll after each chunk arrives. The properties dictionary can exist while still lacking the pixel
keys, so check for the keys themselves rather than dictionary-nil. No known case exists of ImageIO
reporting wrong dimensions from partial data - they're literal header fields, either present and
correct or absent.

## Not yet built

Persisting a probed or measured dimension so an offline reopen never re-estimates, and a chapter's
full height map survives a relaunch, is proposed but not implemented - it would be a new migration
(see <doc:aletheia/Schema>), keyed by chapter and page index plus quality/variant (never by the bare URL
when URLs are signed and expiring), and needs flagging before it's built. Double-page spread
detection depends on this - a spread has to be known wide before layout, not after; see
<doc:aletheia/ReaderBacklog>.
