# Atsumaru

`atsu.moe`. API lane, the cheapest source in the app - four unauthenticated `GET`s, no
`AuthenticatingSource`, no renderer, no Cloudflare challenge. Search runs against a public
Typesense index; everything else is a plain JSON API.

## Search

Typesense returns a true total (`found`), so pagination is arithmetic rather than the
"a full page probably means more" guess most sources have to make. A blank query is sent as `*`
(match-all) rather than omitted, since an empty `q` errors.

**The collection holds web novels, indistinguishable from comics until the content call.** A novel
has a full chapter listing with every chapter at zero page count, and its content endpoint answers
200 with an empty page list rather than an error - so an unfiltered search opens a reader on
nothing. Every search excludes `medium:!=Novel` rather than including `medium:=Comic`, because a
meaningful slice of comics carry no `medium` field in the index at all - an inclusive filter would
hide them along with the novels. `content()` still throws if a page list somehow comes back empty,
since a novel slipping past the filter should read as "not readable," not as a chapter that
happens to be short.

## Recently Updated is a shelf, not a sort

No field in the search index carries chapter-activity recency, so "recently updated" can't be a
Typesense `sort_by` - it's a separate home-feed endpoint, wired as a `SourcePreset` route rather
than a sort option (see <doc:aletheia/BuildingASource>'s ranked-shelves distinction). Two traps in that one
endpoint: its `types` parameter looks optional but isn't - omitted, the route returns an empty
list rather than everything - and `types` filters on `type` (Manga/Manhwa/Manhua/OEL), not
`medium`, so it does nothing to exclude novels; the shelf's own client-side medium filter is what
actually keeps them out, same as search. "Has more" on this shelf is judged against its raw
returned window, not the novel-filtered count, since the shelf pages itself independently.

## Details, chapters, content

Details resolves from the same search index, filtered to one id, rather than the site's own
two-call detail flow - cheaper, and the index document already carries everything `SeriesDetail`
needs. The chapter listing names each chapter's scanlation group only by id; the group's display
name comes from a separate call, so a full chapter entry needs both in flight together. Content
returns exact page dimensions in the same response as the page URLs - no probing needed, the same
free-dimensions shape as MangaFire's own API.

Cover paths need normalizing before use: the search index and the shelf endpoints spell the same
file two different ways (one with a leading `/static/` segment, one without), so both are reduced
to a bare path and given one consistent prefix rather than resolved verbatim - resolving either
form directly against the CDN gets one of them right and 404s the other.

## Things worth knowing

- **Images are AVIF**, the only source in the app serving it - handled fine by the platform's image
  decoder, and moot for dimensions specifically since those already arrive in the JSON.
- **No language field exists anywhere in the API** - not on the document, the chapter list, or the
  page payload. The source asserts English rather than reading it, since the catalogue is an
  English scanlation aggregator and nothing in the API contradicts that; a genuinely localized
  release would be mislabelled rather than lost.
- **The type vocabulary is the site's own spelling**, including a real misspelling of "Manhwa" -
  filtering happens on the raw id, and only the display label is corrected.
- **Tags are bundled, not fetched live** - a large vocabulary (thousands of tags) shipped as a
  static resource, trading freshness for costing nothing at runtime and letting the taxonomy
  participate honestly in the descriptor's fingerprint (it only changes when the app ships). See
  <doc:aletheia/HighCardinalityFilters>. The bundle's own sensitivity flag is drawn wide (gore and partial
  nudity both carry it) and maps to the suggestive tier only, never the gate - the bundle's
  vocabulary and this app's adult-content vocabulary are deliberately different boundaries.
- **Content rating comes from two fields.** A four-tier rating sourced from MangaBaka is
  authoritative; a separate boolean flag is the fallback for the minority of titles that field has
  never rated. See <doc:aletheia/AdultContent> - this is a rung-1 source, since the rating is a real
  per-item field.
