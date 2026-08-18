# MangaBall

`mangaball.net`. An aggregator of aggregators - two form-encoded JSON endpoints plus two HTML
scrapes, mixing lanes across its four contract calls (see <doc:BuildingASource>). No unguarded
health-check route exists (every HTML route is large, the API 403s without a credential), so
`robots.txt` serves as the ping target instead.

## Auth

Conforms to `AuthenticatingSource` with three requirements: a session cookie, a CSRF token read
from a meta tag and sent as a request header, and an optional Cloudflare clearance cookie - this
tenant serves no visible challenge today and may never mint one even to a real browser, so
`cf_clearance` is held and sent only if a challenge ever actually starts issuing one, rather than
being waited on (which would time out every capture on a tenant that never grants it). The
challenge/capture URL is a 404 error page rather than the root, since a redirect response sets the
session but carries no body - only a real 200 HTML page holds the CSRF token to extract.

**A stale token and a WAF block produce the same 403 status with a JSON body**, which the default
Cloudflare-challenge heuristic can't distinguish - `isChallenge` reads the response body text
instead: a WAF-block message means retry is pointless (replaying the same blocked body is a
guaranteed second block), a CSRF-failure message means the credential genuinely needs refreshing.

## The WAF word trap

The site's WAF blocks a small set of literal words as a false-positive SQL-injection rule - live
since the tenant's own deploy, and hit by ordinary genre vocabulary (LITRPG titles are full of the
trigger word). Plurals and embedded forms don't trigger it, so a search is sanitized by dropping
only the exact denied tokens, leaving everything else - including words that merely contain a
denied substring - untouched. If a search still comes back blocked after sanitizing (nothing was
actually removed), that means an unknown trigger word is live: this is logged loudly and the
request fails outright, rather than silently returning an empty page that would read as an honest
zero-result and hide the coverage loss. If sanitizing did remove something, the retry runs and
degrades silently - a warning on a query that ultimately succeeded would read as a false failure
to the reader.

## Search

A POST endpoint carrying filters as `filters[...]` form fields, including two independent
AND/OR modes (one for included tags, one for excluded). The response's own alternate-title, tag,
and author fields are ignored here, since they're truncated to three entries each - the full sets
come from the HTML detail scrape instead. `Accept-Encoding` is deliberately never set on these
requests: `URLSession` supplies and transparently decodes its own, where an explicit header would
make the raw compressed bytes something this source has to handle itself, and the chapter listing
in particular can be well over a megabyte raw for a long-running series.

## Adult gate

The gate is a cookie (`show18PlusContent`), sent only when the search query's adult option is
selected - the site marks no tag as adult on its own, so there's no server-side tag-based
narrowing the way a tag-vocabulary source might have; opening the gate is the only way to surface
those results at all. The cookie is request-scoped, not part of the stored credential, so a search
made with the gate shut never leaks adult visibility through a cached credential, and every
non-search request (details, chapters, content) always sends it, since an adult title already in
the library must keep resolving regardless of whatever gate state the last search happened to be
in.

`Classification` on the details page has no rating field to read at all - it's derived entirely
from the tag set, and an untagged or unmatched series reads as `.Unknown` rather than defaulting
safe. That default matters because `details()` runs on every metadata refresh and would otherwise
be capable of silently un-blurring an adult series the moment a refresh landed with an empty or
unparsed tag read.

## Chapters

One unpaginated payload per series, deliberately fetched with no language narrowing - narrowing
server-side would drop chapter rows that exist only in other languages, which is exactly the
information the app's own language-priority ranking needs to have. The payload's own translation
count is a proxy for total translations, not total chapters, so it offers nothing usable for
`RevalidatingSource`.

**Chapter numbers get a sanity ceiling.** Upstream parsing can occasionally produce a garbage
chapter number (an HTML entity decoding to a large digit string, surviving as a real numeric
value among otherwise-normal chapter numbers) - left unfiltered, a single bad row like that would
become the highest-ranked chapter, mark the whole series as read the moment it's opened, and push
a wildly wrong number to any linked tracker. The ceiling scales with the series' own median
chapter number rather than being a fixed cutoff, so a genuinely long-running series with real
four-digit chapter numbers isn't wrongly truncated.

**A chapter's language code needs mapping, not defaulting.** The site spells Japanese and Korean
with non-ISO codes in some contexts - a chapter in a language this app doesn't model is dropped
entirely rather than falling back to English, since defaulting would mislabel real
non-English content as English instead of simply omitting what can't be displayed correctly.

**Scanlator naming reads from two different shapes on the same field.** A real registered
scanlation group carries a database object id and its own real name; most rows on this
aggregator instead carry the *upstream site's own slug* as the group's "id" field, with a
decorative, frequently-changing codename in the name field - since this string keys the
scanlator-priority rows and has to stay stable across fetches, the upstream slug is preferred over
the decorative name whenever the id field doesn't look like a real database id.

## Content

Page URLs are parsed out of a single inline JavaScript array assignment in the chapter page's
HTML - there are no `<img>` tags or lazy-load attributes to select instead, so a missing match is
treated as an unconditional parse failure. The URLs point at varying CDN hosts across at least two
different apex domains and mix file extensions within a single chapter; nothing about them is
validated beyond being parseable, and no dimensions are ever present, so page size is only known
once the bytes themselves arrive.

## Vocabulary

The full tag list (content/format/genre/origin/theme, all serialized onto the same two tag-mode
request arrays) is hardcoded from the site's own taxonomy rather than fetched live, since it
changes only a handful of times a year and never removes existing ids - a stale local copy costs a
missing filter option, never a broken request. Sensitivity marking is this app's own judgment, not
the site's - the site marks nothing as adult in its own taxonomy at all.
