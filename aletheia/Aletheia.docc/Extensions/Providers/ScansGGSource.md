# Scans.gg

`scans.gg`. API lane - plain public JSON on a separate API host, no key, no signing, no Cloudflare
challenge, no HTML parsing. Every series and chapter is keyed by integer id; there are no string
slugs (the record column is still a string, so this changes nothing structurally, just means
stored rows aren't human-readable at a glance).

## Search can't rank, and ranking can't search

The browse endpoint that accepts free text and filters always returns newest-first - there's no
sort parameter it honours. The site's actual rankings (a windowed "popular" ordering, a
recently-updated feed) live on separate request shapes that ignore text and filters entirely.
Binding either to a `SortSelection` would silently discard whatever the user typed, so this source
declares a single honest sort option ("Recently Added") and ships the rankings as
`SourcePreset` shelves instead, reached through `SearchQuery.route` rather than through sort (see
<doc:BuildingASource>'s "ranked shelves are not sorts"). The route string is a small source-owned
enum encoded as plain text (`"latest"`, `"popular:daily"`) - `search()` switches on it before
building any request.

The "latest" shelf paginates properly and can express its own filter parameter, but a separate,
much larger gap applies to it specifically - see below.

## Adult content: tags, not the rating field

The API's own content-rating field is close to useless as a classification signal - the bulk of
the catalogue was imported in one batch and stamped with the same default rating regardless of
actual content, so thousands of hentai-tagged series report themselves as the "safe" tier. Both
the gate and the per-item stamp are derived from the series' own tags instead, against a
hardcoded set of tag ids marked adult (`Hentai`, `Erotica`, `Smut`, `Adult`, `Lolicon`, `Shotacon`)
and a separate suggestive set. `SeriesDetail.classification` takes whichever signal is stronger
between the raw rating and the tag set, rather than trusting the rating alone - an empty tag list
reads as unknown, not automatically safe.

The exclusion mechanism (`excluded_tags`, a JSON array of tag ids) reaches the browse endpoint and
the popular shelves, so a shut gate sends the hard-adult tag ids there and gets back a clean,
still-full result window - "shut means exclude, not omit" (<doc:AdultContent>) held exactly.
**It does not reach the recently-updated/chapters route at all.** That shelf is over-fetched (a
larger page than the shelf actually displays) and hard-adult-tagged rows are dropped client-side
before trimming to the display count - the only shelf in this source that needs that treatment,
since every other request shape honours the exclusion server-side.

The 49-entry tag vocabulary (id, name, sensitivity) is hardcoded from the site's own bundle rather
than fetched, and is read three separate ways: filter options, the id-to-name lookup `details()`
needs, and the adult/suggestive sets that drive both the gate and the per-item stamp. A tag
renamed or re-ided upstream, or an entirely new adult tag added, would silently break all three at
once, since the API accepts unknown filter values without complaint - this is the one vocabulary
in this source worth periodically diffing against the live `/tags` endpoint.

## Chapters, groups, and ordering

The chapter listing for a series returns every scanlation group's releases interleaved,
unpaginated. Rows carry only a group id, not its name - the name comes from a separate groups
endpoint, fetched once per `chapters()` call and joined locally, since the chapter route's own
"include group details" flag is a no-op. Response order tracks upload time, not chapter number -
a chapter numbered earlier can be uploaded and returned after a later one, so `number` is the only
ordering worth trusting downstream.

Timestamps arrive as a bare `"yyyy-MM-dd HH:mm:ss"` string with no timezone marker, and the site's
own client treats it as UTC - parsed with an explicit UTC-locked formatter rather than the shared
ISO8601 decoder, which would fail the whole response on the first timestamp it couldn't parse.

## Content

Page paths and their sort position arrive together, but **no dimensions** - this source has to
extract page size from the downloaded bytes rather than reading it from the API, unlike a source
whose response states width and height directly.

## What would bite

- Path-style ids in a URL (`/series/2593`) are silently ignored by the API and return the
  unfiltered list with a success status rather than an error - only query parameters actually
  filter, so a malformed request fails as *wrong data*, not as a visible failure.
- An unrecognized value for the popular shelf's time window falls back to a default window
  silently rather than erroring, so a typo there also produces plausible-looking wrong data instead
  of a visible failure.
- Every list route paginates and caps differently, and each ignores the other routes' paging
  parameters without complaint - nothing here generalizes from one endpoint to the next.
