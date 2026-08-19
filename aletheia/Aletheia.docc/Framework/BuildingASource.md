# Building a Source

How a site becomes a `SourceService`.

The decision is made **per capability, not per source** - one source routinely mixes lanes across
its four calls (a source might bundle a large tag file for filters while fetching everything else
live). Walk the tree below once per endpoint you need, and re-walk it whenever a site redesigns:
"requests are signed" is a claim with an expiry date, not a permanent property of a site - a lane
picked because a signature looked unbreakable can turn out to be a few dozen lines of
reimplementable logic once someone re-checks it.

## The three lanes

| Lane | Cost profile | When |
|---|---|---|
| API | stable, cheap; breaks on deliberate versioning | structured endpoints answer plain HTTP |
| plain-HTTP HTML | selector churn on redesigns | data is in the markup of a bare fetch |
| web renderer | unbounded - anti-bot weather, bundler churn | content is client-generated or requests are signed |

Scraping is not a renderer concern - a source can scrape HTML with `SwiftSoup` over
`NetworkService` and never touch `WebRenderer`. The renderer is forced only by execution
(something must actually run JS), not by markup.

Auth and Cloudflare are a layer, not a lane (<doc:SourceAuth>): `AuthenticatingSource` +
``WebAuthCapturer`` compose with any lane below, and the lane choice is unchanged by their
presence.

## Choosing a lane

1. **Auth or Cloudflare wall?** Requests fail without cookies or a pinned user agent -> adopt
   `AuthenticatingSource` first, then continue to the next question unchanged; auth is a layer
   that composes with whatever lane follows, not a lane of its own.
2. **Do structured endpoints answer plain HTTP** (curl with the captured credential, or bare when
   open)? If yes, the payload shape decides the API lane:
   - plain JSON -> `NetworkService.get` straight to DTOs.
   - GraphQL -> one endpoint, query documents; persisted-query hashes can rotate like signed
     tokens.
   - an exposed search backend (Typesense/Algolia-style) -> its own query DSL, facet limits,
     collection-scoped keys.
   - RSS/XML feed -> legacy but stable, sometimes the only steady surface a site has.
3. **If not:** is the full content present in the HTML of a plain fetch?
   - Data shipped as an embedded JSON blob (a framework's hydration state script tag) -> one
     fetch, JSON-decode out of the markup - sturdier than selectors, no renderer needed.
   - Otherwise -> server-rendered DOM scrape with `SwiftSoup` over `NetworkService`.
4. **If the content is client-generated or requests are signed:** a renderer is required. Within
   the renderer lane, prefer in order:
   - network sniffing (tap both `fetch` and `XHR` - some libraries ride `XHR` under the hood).
   - live-module invocation: import the site's own ES module, find the handle **by shape, never
     by name** (export names rotate per deploy), and call its signer directly. Survives key
     rotation better than reverse-engineering the signature by hand.
   - post-render DOM scraping (click-walk plus `outerHTML` dumps) as the last resort - slowest and
     most fragile.

Every lane converges on the same contract: implement `SourceService`.

## The contract, in build order

1. **Descriptor** - declared in code: slug, name, description, icon, languages, `baseURL`,
   referer, filters, one sort axis. `fingerprint` hashes the request-shaping parts and lands on
   `SourceRecord.hash`, so a changed definition is detectable. Cosmetic facts (description, icon)
   stay out of the fingerprint; `Option.sensitivity` is deliberately in - it shapes requests.
2. **`search(query)`** - `SearchQuery -> SearchPage<SeriesStub>`. A `nil` sort resolves to the
   declared `defaultSort` via `resolvedSort(for:)` - never invent a per-source fallback. Declare a
   sort option only for orderings the search endpoint can still apply to a narrowed result set -
   see "Ranked shelves are not sorts" below.
3. **`details(seriesSlug)`** - the canonical slug can differ from the slug the stub was opened
   with; the duplicate guard checks both.
4. **`chapters(seriesSlug)`** - an empty list means the series truly has none; throwing is the
   only way to say "unknown." A source that can cheaply answer "unchanged" adopts
   `RevalidatingSource` (<doc:SourceProtocols> governs when an ability is a protocol vs a
   descriptor field).
5. **`content(seriesSlug, chapterSlug)`** - `[PageURL]`; the referer must ride every CDN request,
   and dimension hints (`PageURL.size`) are attached only when the provider states them, never
   fetched separately.
6. **Register** - add to `Compositor`'s source list; `reconcile` seeds `SourceRecord` at launch.

## Ranked shelves are not sorts

Check this per ordering, before declaring it: does the endpoint that produces this ordering still
honour free text and filters? If not, it's a **shelf**, not a sort.

| | reached by | may ignore user text | user-composable |
|---|---|---|---|
| Sort option | `SortSelection` on a `SearchQuery` the user composed | never | yes |
| Shelf | `SourcePreset`, via a source-defined key | yes - a preset has no user text | no, source-authored |

The failure mode if you get this wrong isn't a crash: the user types a query, picks "Popular," and
the endpoint silently returns the site's global popular list - a confidently wrong result with no
error and nothing in the UI suggesting the text was dropped.

Where this is common: a site's home page carries the rankings (popular-this-week, recently
updated, trending) while its browse page carries the search box, and the two use different
endpoints with different parameters. Reading only the browse page's requests makes a source look
like it can't sort at all - read every page's bundle before concluding a capability is absent.

Mechanism: `SourcePreset` carries an optional source-defined string, `preset.query()` puts it on
the `SearchQuery`, and `search()` reads it to pick a request shape. Opaque to the app, unreachable
from the search UI, invisible to sources that don't set one. This is deliberately not a protocol -
nothing calls it conditionally and there's no `else` branch to write; it's source-authored data
riding a path that already exists. Where a shelf takes a parameter (several popularity windows,
say), each value is its own preset - a preset is a row, and there's no parameterised shelf.

A source with no sortable ordering at all still declares one `supportedSort` option, since the
field is non-optional. Name it after what the endpoint actually does ("Recently Added"); inventing
"Best Match" for an `id DESC` list is not honest.

### What the screen shows

The split above reaches the UI - a preset grid renders only the controls its request can actually
honour:

| Screen | search field | Refine | sort |
|---|---|---|---|
| plain search (no preset) | yes | yes | yes |
| sort preset - hits the ordinary search endpoint | yes | yes | no |
| shelf preset - hits a different endpoint | no | no | no |

A sort preset keeps the field and filters because its endpoint still narrows - "Popular" is the
normal search request with a sort parameter set, so typing into it is a search within Popular, and
a filter applies to it. Only the sort chip goes, since the preset already is one and switching
sort away from it would leave a screen titled Popular showing something else.

A shelf preset loses all three, because none of them can operate on it - rendering a field there
would accept a query and answer with the same list regardless, which is the same "never render an
affordance that can't be operated" rule that applies everywhere else. The controls row is removed
rather than emptied, so there's no band of empty glass above the grid.

The variant not to build: carrying the shelf route only while text and filters happen to be empty,
so the screen silently becomes a search on the first keystroke - the same fault as one selection
meaning two different things depending on unrelated state. Carry the route explicitly; building
the `SearchQuery` by hand anywhere and forgetting to include it lets a shelf preset silently fall
through to an ordinary search.

## Adult content

Full doctrine: <doc:aletheia/AdultContent>. What a new source must implement:

- **Mark option sensitivity.** Any filter option that can pull adult or suggestive content into
  results is declared `.adult`/`.suggestive`. This drives the gate - `allowsAdult(for:)` is one
  shared implementation over these marks, never re-derived per source.
- **Shut means exclude, not omit.** When the gate is shut the request must actively exclude adult
  content; most hosts default an unasked question differently from this app.
- **Stamp every stub.** `SeriesStub.adult` per item where the source can tell; where it can't,
  every stub inherits `allowsAdult(for: query)` - the stable rule for all sources, never a third
  state. The flag is each source's own line and never comparable across sources.
- **An entirely adult catalogue declares `descriptor.adultOnly`** (in the fingerprint) and is
  gate-exempt - no filter could open one, so every stub stamps `true`. Ships `disabled = true` so
  an app update never silently adds an adult source; the global fan-out skips it unless
  `includeAdultSources`. Blur still applies.

## Why the split is per-capability

Forcing a source into its worst lane everywhere because one endpoint needs it wastes the lanes
that didn't need it - a source can genuinely need a renderer for one call and plain JSON for the
other three. The renderer lane especially is a maintenance contract, not a technique: every leg of
it (sniffed bodies going encrypted, rotated export names, click-walks silently truncating) has
broken in production at least once, which is why the lane order above tries the gentlest-failing
option first.
