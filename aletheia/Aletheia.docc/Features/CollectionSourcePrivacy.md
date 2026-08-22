# Collection & Source Privacy Settings

User-driven visibility controls at two levels - a collection (Library) and a source (Search) -
independent of how a series or source happens to be tagged. Settings > Collections, Settings >
Sources, and the gearshape on a source's own screen. `Screens/Settings/`.

Distinct from <doc:aletheia/AdultContent>: that system is upstream-driven (what a source or a
result claims about itself) and scoped to search stubs. This one is reader-driven - anything can go
in a private collection or get flagged sensitive, regardless of classification or `adultOnly`.

## The two knobs

| | Collection | Source |
|---|---|---|
| Hide | `hideFromHome` - excludes every member series from every Home area | `hideFromSearch` - tri-state (unset/hidden/shown), excludes the source from global search |
| Lock | `requiresFaceId` - gates the collection's own Library section | `requiresFaceId` - gates the source's own screen |
| Derived blur | yes, cross-collection (below) | no - deliberately simpler, no second mechanism to reason about |

Both live as plain columns on `CollectionRecord`/`SourceRecord` (migration `v1.1.0`, append-only -
see `Migrations.swift`), not a separate settings table - each is a fact about the row it's on, not
a join.

## Hide

`CollectionGate.hiddenFromHome(in:)` mirrors `AdultGate`'s shape exactly: a `Set<SeriesRecord.ID>`
computed once and folded into `HomeViewModel`/`UpdatesViewModel`'s existing exclusion sets. A series
in library carries its Home eligibility from two independent gates now, adult and collection - both
exclude, neither one overrides the other.

`SourceRecord.hideFromSearch` reuses the tri-state shape `AdultBlur` used before it: `unset`
resolves through `hides(adultSource:)`, defaulting to hidden for an `adultOnly` source and shown
otherwise, so an explicit choice always overrides that default in either direction. See
<doc:aletheia/AdultContent>'s "Adult-only sources and global search" for how this composes with the
ten-tap `bypassAdultSources` existence gate.

## Lock

Face ID unlock is session-scoped, in-memory, per item - `Compositor.Privacy`, an `@Observable`
class alongside `Compositor.Downloads`. Unlocking one collection or source doesn't unlock another,
and nothing here is ever persisted; every relaunch starts locked again, the same "a reveal meant for
one session shouldn't still be on tomorrow's" rule `Preferences` already documents elsewhere.
Wraps `LAContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics)` behind
`withCheckedContinuation`, one fresh `LAContext` per attempt. First use of `LocalAuthentication` in
the codebase - needs `NSFaceIDUsageDescription` in `Info.plist`.

A locked collection's Library section renders a `ContentUnavailableView` unlock prompt instead of
its entries - the entries stay in `LibraryViewModel.Section.entries` regardless, so the prompt can
still say how many series are behind it. A locked source's own screen gates the same way. Locked
collection names render through `GlitchText` rather than a plain label or blur, in both the
section header and the category hopper's jump-to picker - scrambles a fraction of characters per
tick rather than the whole string, so it reads as "you don't have this decoded" instead of "same
content, hidden." A name is text, not artwork; blurring it would read like it does on artwork,
which is the wrong claim to make about a name a reader could just read off the hopper anyway.

## Cross-collection blur

Collections only, not sources - the one derived effect in this feature, reusing `.obscured(_:)`
(the same blur+scrim modifier every card type already uses for adult content) rather than
inventing a second blur mechanic.

A series can belong to more than one collection. `LibraryViewModel.blurredSeriesIds` unions
membership across every collection that is `requiresFaceId` and not yet unlocked this session, and
that set is what drives `.obscured` on a card wherever the series is shown. By construction this
only ever fires under a *different* section than the locked one - a locked collection's own section
never renders its entries in the first place, the gate takes over instead. A series in two locked
collections stays blurred everywhere until *both* are unlocked (AND, not OR) - unlocking one alone
still leaves it obscured under any section it reaches through the other.

Tapping a blurred card still navigates through - intentional, not a bug. Face ID here gates a
section's *presentation*, not real access control; the underlying series was never actually hidden,
only cross-listed under a section it also belongs to.

## Superseded

This replaces the old `AdultBlur`/`BlurToggle` manual-reveal system that used to cover Home,
Library, and Search - deleted outright rather than kept alongside the new mechanism. One
consequence worth naming: Home and Search lose blur entirely as a concept now (hard hide is the
only lever left for those two surfaces); only Library keeps a blur, and only as the derived
cross-collection effect above.

## Backup

`hideFromHome`/`requiresFaceId` round-trip through a library backup as a parallel
`collection_settings` list, keyed by name against the same collections `SeriesEntry.collections`
already references - see <doc:aletheia/LibraryBackup>. Source settings don't travel with a backup;
sources are reinstalled independently of what a backup restores.
