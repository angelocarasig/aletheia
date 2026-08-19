# NHentai

`nhentai.net`. API lane - the v2 JSON API covers search, detail, tags, and pages in two
unauthenticated calls; no scrape, no renderer. Adult-only: `descriptor.adultOnly = true`.

See <doc:AdultContent> for what that flag means for the gate and presentation.

## Search and gallery codes

`/api/v2/search` (not the sibling "get all galleries" route, which ignores `query` entirely)
requires a non-empty query - an idle browse or a preset sends the literal string `*` as a
match-all, which collapses every preset, idle browse, and real search onto one code path. Sort
options (`popular`, `date`, and three windowed `popular-*` variants) compose with the query string
directly, unlike a source whose ranked shelves can't take free text.

The search index can't match a bare gallery code (`query=671147` returns nothing). An all-digit
query with no other filters is resolved client-side instead: fetched directly through the gallery
detail endpoint, falling back to the metadata archive for a deleted id, and only falling through to
ordinary text search if neither resolves.

## Details, chapters, and content - one call each, or fewer

A gallery is a single book, not a chaptered series - `chapters()` returns exactly one synthetic
`ChapterEntry` whose slug is the gallery id itself, and no revalidation is needed since a gallery
is immutable once posted. The detail endpoint (`?include=images,tags`) returns cover, tags, and
the full `pages[]` array - title, dimensions, and per-page path and extension - in one
unauthenticated call, so `details()` and `content()` both read off the same response shape.

**Page and cover paths are used exactly as the API returns them, never reconstructed.** Extensions
differ per page within a single gallery, and the API sometimes emits a doubled extension on a
cover path - the only form guaranteed correct is the one the API gave. Dimensions arrive with the
page list itself, so this source needs no dimension probing at all.

A gallery no longer reachable through the API (404, taken down) falls back to a static metadata
archive keyed by `id % 100` sharding, which mirrors the same tag/title shape but carries no page
list - a taken-down gallery is browsable as metadata but not readable.

## Title handling

The API's own "pretty" title field is not used directly - it collapses certain punctuation pairs
in ways that can eat real title text. Titles are instead derived by stripping bracket/paren/brace
groups (which carry event, circle, and language annotations) from the composite title field. Where
the result carries a vertical-bar separator (the archive convention for an original-language title
paired with its translation), the half that leads is whichever matches the gallery's own tagged
language - the other becomes an alternate title.

Tag names arrive lowercased and are cased on the way in: a short, vowel-less, all-letter token is
treated as an acronym and uppercased (with a short exception list for real acronyms containing a
vowel or digit, and an inverse list for vowel-less ordinary words), everything else gets simple
title-casing. This matters because the shared tag pool keys on a case-insensitive name and
whichever source writes a tag first owns its display string.

## Vocabulary

Tag, artist, character, parody, and group namespaces are bundled as a static JSON resource rather
than fetched live, since nhentai's own per-namespace enumeration endpoint is both large and tightly
rate-limited. Filter option ids are the tag names themselves (not numeric ids), since the search
grammar addresses tags by name - selections encode as `scope:"name"` / `-scope:"name"` terms joined
onto the query string.

## Cloudflare

A real browser load always earns `cf_clearance` through a silent managed challenge - no visible UI
under normal operation, but WebKit capture still runs it and reliably mints the cookie every time
(a plain `curl` never runs the JS check and so never earns the cookie, but that's not evidence the
gate is off). `AuthenticatingSource` conformance requires only `cf_clearance`, no session cookie -
there's no login here, only the Cloudflare clearance.

`interactive: true` is the one deliberate difference from a source whose challenge stays silent
under all conditions: Cloudflare's under-attack mode replaces the silent check with a visible
Turnstile the reader has to complete, and only an interactive capture sheet can survive that. The
cost is a brief auto-dismissing sheet flash on ordinary captures too (first use, or an occasional
clearance refresh), traded for not going dark the moment the tenant escalates.

The site's own root HTML is Cloudflare-gated for non-JS clients and 403s a plain request even when
the API itself answers fine unauthenticated - this source overrides its health-check URL to the
API root rather than the site root, so a healthy API doesn't read as a down source.
