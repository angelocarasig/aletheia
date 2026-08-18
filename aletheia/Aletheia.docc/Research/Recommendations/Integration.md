# Fitting the Recommender to This App

What the app has that the v01 engine (<doc:V01Artifact>) needs, what it lacks, and how the two
were reconciled. The infrastructure and Details-screen surface this describes are built - see
<doc:PortPlan> for the as-shipped record; this page is the reasoning behind the shape it took.

## The identity problem turned out smaller than expected

A recommender trained off-device normally can't be reached from a library like this one - its
items are catalogue ids, a local series knows source slugs, and the only bridge would be a tracker
link, which this app's own tracker-metadata rules already forbid seeding automatically from a
third party's cross-reference (see <doc:Trackers>). Most of a library would be permanently
unreachable under that constraint.

The v01 bundle sidesteps this by resolving on names instead, and the app happens to hold exactly
the input it wants: `TitleRecord` is already a series-level pool of alternate titles, one row per
name, populated from whichever suppliers described the series. No new table, no mapping, no
tracker link required, and it works for a series from any source.

What this doesn't fix is the alias table's own collapse (<doc:V01Artifact>) - about 9.5% of the
catalogue is reachable only as some other series, and that ceiling sits above anything a client can
do about it.

**A linked tracker series resolves exactly, with no ambiguity.** The catalogue's ids turn out to be
the same ids a MangaBaka tracker link already uses, so a series with a MangaBaka link resolves
straight to its catalogue row with no name normalisation, no hashing, and none of the alias table's
collapse. This doesn't change the linking policy - nothing is auto-linked, and it uses a link the
reader already confirmed to identify a catalogue row, not the reverse - but it makes linking to
MangaBaka worth something beyond tracking progress, and it's why the app resolves through a link
first and only falls back to name matching when there isn't one.

## Fields the engine wants that the app doesn't have

Only one actually blocks a resolved-seed query. A local year field doesn't exist (chapters carry
per-chapter publish dates, not a series year), but this has no impact once a seed resolves, since
the era block reads the catalogue's own year for that row, not anything local - it only matters for
an unresolved (projected) seed. A local format/type field doesn't exist either; for a resolved seed
the honest default is the catalogue row's own type. Per-tag weighting doesn't exist -
`series_tag` is a bare join table with no weight column, so every local tag enters scoring at a
flat weight, which the bundle's own specification explicitly permits.

The larger issue isn't any single field - it's that the local tag pool is known-stale.
`series_tag`/`series_author` are written once at series creation and never touched by a later
refresh (see <doc:TrackerMetadata>), so a series' tags reflect whichever source happened to create
it and are never corrected. That substrate is what an unresolved (projected) seed runs on, and it
was already a live gap independent of recommendations; it becomes load-bearing the moment
tag-based-only recommendations are in play.

A second, unrelated normalisation also exists and must not be conflated with the one the tag
vocabulary needs: `TagRecord.normalizedName` collates case-insensitively for the app's own lookup
needs, which is a different function from the bundle's own name-normalisation routine (NFKD,
strip marks, casefold, collapse whitespace). Any lookup into the bundle's tag vocabulary has to go
through the bundle's own normaliser, not the database column - a mismatch here is a silent miss,
not an error.

## Two vocabulary collisions

`Orientation` already means something else in this app - reading direction, a user preference set
from the reader's own mode picker. The bundle's BL/GL axis is an unrelated concept and needed its
own name; it ships as ``RegisterAxis``, which collides with nothing.

`Classification` is four values in this app but not the same four values the bundle uses. This
app's classification deliberately collapses erotica and pornographic into one `Explicit` tier (see
<doc:AdultContent>), so mapping a local classification onto the bundle's four-rung ladder is lossy
in one direction and a real choice in the other - `Explicit` maps to the bundle's most permissive
matching rung (pornographic) rather than silently excluding erotica results from an Explicit
reader. The recommendation ceiling itself is derived from the app's existing adult gate rather than
offered as a new control, since this app already treats the gate (what's retrieved) and the blur
preference (how it's shown) as the only two mechanisms and deliberately doesn't add a third.

## Where it surfaces

Home is explicitly ruled out (see <doc:HomeScreen>) - every commercial app that promoted
recommendations above a reader's own resume drew documented backlash, and that finding held under
review. Details is the natural fit instead: the engine is seed-shaped (it answers "given this one
title"), and Details is the one screen where the reader has already supplied that seed just by
being there - which is where the shipped surface (a "Similar Titles" rail below the chapter list,
with its own detail sheet) actually lives. Search and Sources are a weaker fit, since a search
result is a stub with no local row and would only ever run in the unmeasured projected mode.
Nothing here needed precomputing or a background job - it's a per-open query, not a rail that
needs a schedule.

## Switchable models

The pattern for swapping recommendation models already exists in this app and isn't a package -
it's the same shape as the source-plugin framework (<doc:SourceProtocols>): a `Sendable` protocol,
a static descriptor carrying identity and capability, concrete implementations owned by
composition, and opt-in refinement protocols cast at the call site rather than baked into the base
contract. A future model that can additionally encode raw text isn't a parameter on the existing
protocol, it's a capability - the same discipline the source framework already enforces.

## Schema

A seed-based recommendation needs no schema change - read the series' title pool, resolve to a
row, run the engine over memory-mapped files, render. Nothing is persisted, nothing is observed.
That stops being true the moment any of these get built: caching a resolved catalogue id per
series (only the catalogue id is safe to persist - row indices aren't stable across a bundle
rebuild), remembering a reader's correction when the resolver picks the wrong series (likely for
roughly the 9.5% ceiling above), or adding tag provenance/weight columns to `series_tag` (already
independently worth doing, per <doc:TrackerMetadata>). Any of those is a flagged schema change
under the standard rule (<doc:Schema>).
