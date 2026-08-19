# Toonily

`toonily.com`. Plain-HTTP HTML scrape (Madara WordPress theme) behind a Cloudflare auth layer -
`SwiftSoup` over `NetworkService`, no renderer. No content path returns JSON; the same theme
templates render both full pages and the AJAX fragment responses used for the chapter list.

## Cloudflare

Conforms to `AuthenticatingSource`, requiring only `cf_clearance` - the same shape as MangaFire.
The site's root serves the Cloudflare interstitial to a plain request, but `robots.txt` is the one
route the edge doesn't gate, so it's used as the health-check URL instead of the root.

## The mature-content gate

Toonily hides adult titles behind a site-wide "Family Mode" cookie rather than marking them
per-item in search results - no implementation of this site reads a per-card adult signal, because
none exists in that markup. The filter declares a select option with two adult-marked states
(Included, Only), and which state is chosen changes the actual request: unticked sends a query
clause that positively excludes adult-flagged posts; Included sends the mature cookie with no
exclusion clause (a mixed, unblurred-at-the-source result set); Only sends both the cookie and a
clause that inverts the exclusion to adult-only. This is the query-gate stamping pattern
(<doc:aletheia/AdultContent> rung 3): the source can't tell per item, so every stub in a gate-open search
inherits the query's own gate state, and it's an honest read in the Only case and a deliberately
conservative one in the Included case (some titles blur that aren't actually adult, which is the
accepted cost of not being able to tell them apart).

**The mature cookie is request-scoped, not part of the stored credential.** It's attached only to
requests where the gate is actually open, so a shut-gate search never accidentally leaks mature
visibility through a cached credential. Detail and chapter requests always send it regardless of
the current search gate, since an adult title's own page has to resolve independent of whatever
gate state a search happened to be in when the user tapped into it.

The stock Madara per-title 18+ overlay this site once had is gone, replaced by the site-wide
toggle - `details()` derives `Classification` from the genre list instead (a genre tagged
Mature/Adult means `.Explicit`), since that per-title overlay signal no longer exists to read.

## Search

Text is sanitized to lowercase alphanumerics before sending - the site's own search chokes on
punctuation. Sort and shelf presets both ride the same GET-form transport as a composed search
(unlike a source whose rankings only exist on a separate, non-composable request shape) - all
seven of the site's own orderings compose with text and filters, so they're declared as sort
options, not shelf presets riding a route key. The declared genre vocabulary is only the ~30 slugs
the site's own search form exposes, not its larger internal taxonomy - genres absent from the
form's own UI aren't declared here either.

Cards are html fragments (not full pages, not JSON) whether they come from a first-page load or a
paginated one. "Has more" is inferred from the fragment's own end-of-results marker, since no page
carries a stated total.

## Details and legacy URLs

The site redesigned its URL structure once (a path segment renamed), and old-style links still
circulate and 301-redirect - the canonical slug used for `SeriesDetail` comes from the response's
final URL after any redirect, not from the slug the request was made with, so a stale bookmark
still lands on the right series row rather than creating a near-duplicate.

## Chapters

No scanlation group attribution exists on this site at all - every chapter entry uses the source's
own name as a synthetic scanlator, the same pattern a source with no per-chapter group information
uses elsewhere. Chapter dates parse three different textual shapes (an absolute date, a relative
"N days ago" string, and a same-day badge whose text is literally the substring "UP" rather than
any recognizable date word) - an unparseable date falls back to a sentinel rather than guessing.

## Images

Cover and page URLs both resolve through a multi-attribute lazy-load chain (several `data-*`
attributes checked in order before falling back to a plain `src`, which usually only holds a
placeholder). Listing covers are downsized variants with a size suffix baked into the filename;
stripping that suffix addresses the full-resolution original directly rather than the thumbnail.
No page carries dimension hints anywhere in the markup, so this source extracts page size from the
downloaded bytes rather than reading it from a response.

A Madara-theme capability exists for AES-encrypted page lists behind a password-derived key, but
has never been observed in use on this specific site - its appearance is treated as a parse
failure rather than a supported path, since building a decrypt for a capability that's never fired
here would be dead code guarded by a branch that never triggers.
