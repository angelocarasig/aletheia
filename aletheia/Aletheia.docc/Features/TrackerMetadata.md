# Tracker Metadata

Whether AniList or MyAnimeList may supply series metadata - synopsis, classification,
publication - alongside a content source, and how that's stored without a tracker becoming an
``OriginRecord``.

## Why not an origin

`origin` is the chapter-provenance and fetch unit, not a metadata table - metadata rides along on
it. Admitting a chapter-less tracker row into it would fork the meaning of `sourceId IS NULL`
across every site that currently reads it as "this source was removed" (roughly eighteen call
sites at the time this was evaluated), none of which would fail loudly. A tracker origin would
render as a disconnected source, count toward "failing sources" inconsistently across three
different screens that each count it a different way, and satisfy the "more than one origin"
guard that enables removing the real source - taking the actual chapters with it while leaving a
library entry that can never be read again. None of this is theoretical risk assessment; it was
worked through concretely enough to be rejected outright.

## The `metadata` table

`MetadataRecord` is a supplier-owned bundle either an `origin` or a `series_tracker` can own,
never both:

```
metadata
  id
  seriesId       FK -> series           not null, cascade
  originId       FK -> origin           nullable, set null
  trackerId      FK -> series_tracker   nullable, set null
  supplier       text not null
  synopsis
  classification
  publication
  fetchedDate
  CHECK (originId IS NULL OR trackerId IS NULL)
  UNIQUE (seriesId, supplier)
```

`origin` itself carries no synopsis/classification/publication/fetch-date columns - it's purely
chapter-provenance and fetch state, as <doc:aletheia/Schema> describes. `title.originId`/`cover.originId`
point at `metadataId` instead, and the two series-level preference FKs
(`preferredSynopsisId`/`preferredClassificationId`/`preferredPublicationId`) target `metadata.id`.

**The CHECK is "at most one," not "exactly one," and that's load-bearing.** Exactly-one would
force `ON DELETE CASCADE` on both supplier FKs, and cascading is precisely the bug this avoids -
removing a source would delete its synopsis and silently clear a reader's pin. At-most-one lets
both FKs go `SET NULL`, so a metadata row outlives its supplier exactly like a `cover`/`title` row
already does. A supplier-less row can never win *automatic* resolution (which goes
preference -> highest-priority origin -> any), since a row with no origin has no priority - it's
reachable only by an explicit pin, which is what makes a tracker supplying classification safe:
nothing silently unblurs a series, since a tracker row can never be chosen automatically.

**`supplier` is the durable identity the foreign key isn't.** `"source:<sourceSlug>:<originSlug>"`
or `"tracker:<trackerSlug>"`, computed by one function on `MetadataRecord`, never composed at a
call site. It survives its supplier being removed and re-adopts the same row (rather than
duplicating) when that source comes back, via `UNIQUE(seriesId, supplier)`. The origin slug in the
key isn't decoration - without it, two origins from the same source on the same series would both
key identically and the second origin's metadata would silently never store. With the slug the
collision is structurally impossible, since a source's slug already resolves to at most one origin
per series.

## Classification and publication

Both mapped per service, abstaining (writing nothing, never defaulting to Safe) rather than
guessing where a tracker has no real signal for it:

- **AniList**: `isAdult == true` maps to Explicit; the `Ecchi` genre maps to Suggestive; otherwise
  abstain. `status(version:2)` maps to `Publication` - the whole reason to want AniList for this
  field, since it's the only supplier that can express hiatus as a real state rather than an
  absence a reader has to infer from a source simply going quiet. The *unversioned* `status` field
  defaults to a version that has no hiatus case at all - always request version 2.
- **MyAnimeList**: `nsfw == "black"` or a `Hentai`/`Erotica` genre maps to Explicit; `nsfw ==
  "gray"` or `Ecchi` maps to Suggestive; otherwise abstain. The genre arm exists because MAL's
  `nsfw` field alone under-reports - a title can carry MAL's own `Erotica` genre while `nsfw`
  stays at its lowest tier.

Tags land through the same `TagRecord.attach(_:to:in:)` idiom a source already uses, filtered
before they land: AniList tags are gated on a minimum rank and both spoiler flags (`isGeneralSpoiler`,
`isMediaSpoiler`) - a large share of series carry at least one spoiler tag, and roughly a fifth of
all tag instances are marked as one, so rendering them unfiltered would spoil a meaningful slice of
any library. MAL's genres are a small closed vocabulary and pass through whole. Neither tags nor
authors carry per-supplier provenance - a tag is a fact about the series regardless of who said it,
so every writer (source or tracker) goes through the one shared attach function with no second
mechanism.

## Prose stays live for MyAnimeList, stored for AniList

`Tracker.storesProse` carries this rule in the type system: `true` for AniList, `false` for
MyAnimeList. A service that answers `false` never has its synopsis written into a `metadata` row -
it displays live on the candidate screen and never enters the pool or the search index. This
follows from reading MyAnimeList's developer agreement literally: its clause reaching "any other
data communicated from the API" covers altering their prose (stripping attribution boilerplate,
blending it with another supplier's description), which this app treats as a real constraint,
while accepted as fine is mapping their small closed vocabularies (status, nsfw) onto this app's
own enums - a lookup with no authorship left to misattribute. AniList's terms carry no equivalent
restriction on downstream use of what their API returns, so its synopsis stores normally (as plain
text - both trackers' raw prose needs cleaning before display; AniList ships HTML with
attribution/notes boilerplate, MAL's plain text often ends in an attribution line of its own).

Neither service's terms block ingesting metadata in general - the concern that mattered was
volume/mass-collection (fetching what a reader personally holds is not that) and, for MyAnimeList
specifically, altering what came back rather than displaying it as sent.

## The search index

Tracker synopsis text enters `SeriesFTS5View` unfiltered, same as a source's. Since MyAnimeList
prose never gets stored in the first place, only AniList text can reach the index, and AniList's
terms carry no restriction against that. The reasoning for including it at all: the index feeds a
search bar where recall is what matters, and it feeds merge-candidate narrowing, where a merge
always requires explicit confirmation, so extra candidates cost a glance rather than a mistake.

## Cover behavior

Neither tracker's covers are large enough to displace a source's - both trackers cap resolution
well below what a typical device display wants, so tracker covers are pool material and grid
thumbnails only, never a series' preferred cover. A tracker's cover URL can go stale silently -
the file the URL points to can be swapped upstream with the old URL still serving the previous
image indefinitely rather than 404ing - so a stored tracker cover URL is only ever safely treated
as a pool entry that gets re-read and compared on refresh, not trusted as permanently correct.

## Reparenting bug this closed

Merging two series used to sweep pool rows (title, cover) by matching on `originId` before
deleting the losing series - which meant a pool row whose source had *already* been removed
(`originId IS NULL`, exactly the state `SET NULL` exists to produce) matched nothing, moved
nowhere, and was cascaded away by the merge's delete a few lines later. Merging two series could
silently delete every cover and title whose source had since been removed, including pinned ones.
The fix sweeps once per table on `seriesId` rather than per-row on `originId`, outside the
per-origin loop; `metadata` is a third table in that same sweep and needed no rule of its own.

## Deliberately not built

A manual delete affordance for an orphaned pool row (pools stay add-only by design - see
<doc:aletheia/Schema>'s history-table exception for the general shape of that tradeoff). Author identity
merging (name-order and romanization variants of the same person read as distinct rows today, and
naive token-matching is unsafe since it would also merge two different people who happen to share
name tokens). Refreshing a tracker's metadata row after the initial link - it's fetched once when
linked, not kept current automatically.
