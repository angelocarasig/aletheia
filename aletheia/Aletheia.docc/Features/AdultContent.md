# Adult Content

How a search result answers "is this adult?", and what a source does when its host won't say.

Scope is search stubs only. A series already in the library carries `origin.classification` on
disk, so every other surface already has a real answer and isn't part of this.

Two mechanisms, deliberately separate: a **gate** decides whether adult results come back at all
(driven by which filter options the user ticks), and a **preference** decides whether what came
back is blurred. The gate is retrieval, the preference is presentation, and the preference never
touches a request.

## The flag

`SeriesStub.adult` is a non-optional `Bool`. An optional would smuggle "unknown" back in as a
third state and force every call site to re-decide what to do about it - the source answers once,
so the rest of the app never has to.

**Pornographic only. Erotica is not adult.** Where a source draws the same four-tier line, safe,
suggestive, and erotica are all `false` and only pornographic is `true`. Where a source draws its
line somewhere else, it reports its own line faithfully - the flag is never comparable between
sources.

`Classification` (Safe/Suggestive/Explicit/Unknown, for a stored series) is a different concept
and doesn't merge with this: it folds erotica into `.Explicit`, which is exactly the distinction
the gate needs to keep separate.

## Vocabulary

One word per layer:

| Layer | Word |
|---|---|
| declared on a filter option | `Sensitivity` (`Option.sensitivity`: `.none`/`.suggestive`/`.adult`) |
| a fact about a result, and the gate | `adult` (`SeriesStub.adult`, `allowsAdult(for:)`, `blurAdultContent`) |
| presentation | `obscured` (`SourceCard.obscured`, `PageSection.obscured`) |

A provider's own words (`"pornographic"`, `"Hentai"`, option ids) stay at the boundary - each
source maps them to this vocabulary on the way in, and nothing downstream sees the wire values.

## The rule

**`adult` is a claim, not a guess.** A source returns `true` only when it knows, and `false` only
when it can guarantee. If it can guarantee neither, it shapes its request until it can.

Stop at the first rung that holds:

| Rung | The source can... | What it returns |
|---|---|---|
| 1 | label per item - a field, a chip, an 18+ ribbon | the item's own answer |
| 2 | not label, but filter server-side | constrain the request, stamp the whole batch |
| 3 | neither | `true` for everything |

Rung 2 is the interesting one: a per-item field isn't the only way to know a per-item fact. If the
host filters server-side, the request already determined the answer - ask for clean titles and
every result is clean. The set is homogeneous by construction, so a per-set fact honestly fills a
per-item field. A rung-2 source must **always** send its rating parameter, including when nothing
is ticked - omitting it is what makes the batch unknowable.

Rung 3 is deliberately unpleasant: every card in that grid blurs and the source looks broken. The
alternative - returning `false` because checking was inconvenient - silently breaks the one
promise the preference makes. A wrongly blurred cover costs one tap; a wrongly unblurred one costs
the reason the setting exists.

A user who selects clean and adult ratings in one query gets a genuinely mixed batch - a rung-2
source collapses to rung 3 for that one query and stamps `true`. Self-inflicted, reversible, rare.
Nothing here blocks anything: selecting an adult rating still returns adult results, marked, not
withheld.

## The gate

`SourceService.allowsAdult(for query: SearchQuery) -> Bool` lives in a protocol extension beside
`resolvedSort(for:)`, since resolving a `FilterSelection`'s option ids back to `Option` values
needs `descriptor`, which the extension has. One implementation; every source calls it.

Only *included* options count - excluding an adult tag isn't a request for adult content, so a
multi-select's excluded array never feeds the check, only its included set (and a single-select's
chosen option). Text and number filters have no options and can never open the gate.

`Sensitivity` is a three-state enum rather than two bools (`adult: true, nsfw: false` would be
nonsense, and an enum makes it unrepresentable):

- `.none` - ordinary option.
- `.suggestive` - racy, never pornographic. Tinted; gate stays shut.
- `.adult` - necessarily returns pornographic content. Tinted and opens the gate.

`.adult` is reserved for options where ticking them *necessarily* returns pornography - a rating
tier that names it, or a tag that's pornographic by definition. `Sensitivity` enters
`SourceDescriptor.fingerprint`, since it decides which URL gets built.

**The gate is not the label.** `allowsAdult` decides what the source asks for; what a stub is
stamped with comes from the request the source actually built - the two only coincide when the
request is one-sided. A rung-1 source uses the gate only to shape the request; its stamp still
comes from the item's own field.

## Default requests

Omitting the rating parameter is never correct - every source excludes adult content
deliberately, on every request, and sends something different only once the gate opens. A source
whose accidental "clean by default" behavior turned out to be luck (inheriting a value from
somewhere the app doesn't control, rather than sending its own exclusion) is a latent version of
this bug even while it happens to look correct.

For a renderer-backed source specifically: express the gate in the URL, never in local storage
that the request doesn't carry, unless the site offers no URL equivalent - anything written to a
persistent store outlives the request that wrote it, with no clean way to observe what's in there
or when it went stale.

## Presentation

**Blur, never hide.** Hiding is already what the gate does - a preference that also hid things
would be a second mechanism doing the first one's job, and nothing on screen could distinguish
"filtered out by preference" from "this source returned nothing."

| | Governs | Mechanism |
|---|---|---|
| The tick | retrieval - what comes back | filter options marked `.adult` |
| The preference | presentation - how it looks | blur on `stub.adult` |

Enabling "always show adult content" and ticking nothing still shows nothing - the preference must
never feed request-building, or the tick stops being the gate.

The reveal switch sits beside the sort control, shown only when the current query could return
adult results (the gate is open) - with the gate shut nothing in the grid can be blurred, so a
switch would control nothing. It's per-search state, not persisted - a new search starts blurred
again. Blur covers the cover art only; the title stays legible, so a blurred card is still
identifiable. `.suggestive` tints a filter row and does nothing else - no result is ever blurred
for it.

## Adult-only sources and global search

A catalogue that's entirely pornographic breaks the "no tick, no adult results" invariant - there's
no filter that could open a gate, because there's nothing to separate. `SourceDescriptor.adultOnly`
(defaulted `false`, in the fingerprint) is the escape hatch: exempt from the gate, and every stub
stamps `adult`. Not persisted to the database - every consumer already holds a descriptor, and this
ships and dies with the source. Not disabled by default; badged `18+` on its row rather than given
a separate section.

Global search is the one surface that fans out over every source with no filter UI of its own, so
a tick can't be the gate there - `Preferences.Key.includeAdultSources` (default `false`,
persisted) is the ask instead. An included source's results are then blurred by
`blurAdultContent` like anything else. There's deliberately no way to ask for adult content from
global search itself - go to the source and use its filters. An excluded source stays silent
otherwise, which reads as broken search, so the control row carries an "N sources hidden" count.
Hiding a source from search is a discovery decision, never a data one - a library series whose
origin points at an excluded source must not lose its chapters because the preference flipped.

## Open

A source can still ignore the gate - neither the helper nor a field on `SearchQuery` is
compiler-enforced, so a new source that never calls `allowsAdult` returns adult content forever
with nothing complaining. <doc:aletheia/BuildingASource> is the standing checklist that's supposed to catch
this; treat it as load-bearing, not advisory.

**Global search ignores `disabled`.** `SearchScreen` builds its fan-out from
`compositor.registry.sources`, the raw compiled-in array with no database read - disabling a
source in Settings doesn't stop it from returning results in global search, even though
`BestChapterView` and the Sources screen both honour the flag. Not the same bug as the adult gate
(`adultOnly` is a descriptor fact needing no database; `disabled` is a row), so the fix is a
different shape - either the fan-out reads `SourceRecord` itself, or the registry gains a
disabled-aware accessor.
