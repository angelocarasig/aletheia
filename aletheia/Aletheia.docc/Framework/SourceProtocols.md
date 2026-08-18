# Source Protocols

How a source declares it can do something the base contract doesn't require.

``Network/Sources/Contract`` holds the base contract; ``Network/Sources/Protocols`` holds the
opt-ins.

## The rule

**Static facts go on `SourceDescriptor`. Behaviour goes in a protocol.**

"Supports tag filtering," "serves these languages," "has a search box" are facts - they belong on
the descriptor, they take part in its `fingerprint`, and the UI needs them without instantiating
anything. "Can tell you what changed without being asked per series" is behaviour, and behaviour
is what a protocol is for.

Getting this backwards produces protocols nothing ever casts to.

A third case the rule above doesn't cover: source-authored data that isn't a static fact and isn't
behaviour either - it rides the path the request already takes. A ranked shelf endpoint
(`popular={window}`, a date-sorted feed) that ignores free text and filters isn't a sort option
and doesn't need a protocol; it's an opaque string on `SourcePreset`, carried onto `SearchQuery` by
`preset.query()` and read by `search()`. Sources that don't set one never see it.

## The discipline

**The base contract must always be able to do the whole job.** An opt-in may only ever make
something faster or unlock something extra. It may never be the thing that makes a source work.

The test: if a source conforming to the base contract alone would be broken without the opt-in,
it's not an opt-in, and the capability belongs in `SourceService` itself.

Two consequences:

- Every opt-in adds an `as? any X` branch at the call site - a path that only runs for a subset of
  sources, which is where untested bugs live. Two opt-ins is clean. Six is a smell.
- A caller must always have a working `else`. If writing that branch is awkward, the split is
  wrong.

## What exists

| Protocol | Buys | Conformers |
|---|---|---|
| `AuthenticatingSource` | credential caching, proactive refresh, challenge detection, single-flight capture, retry-once | `MangaFireSource`, `MangaBallSource`, `NHentaiSource`, `ToonilySource` |
| `RevalidatingSource` | answering "nothing changed" from the first response instead of walking a paginated feed | `MangaDexSource` |

Both follow the same shape: refine `SourceService`, add one requirement, and where an answer needs
more than a value can carry, a small enum owned by the protocol's own file rather than a shared
DTO.

`RevalidatingSource`'s shortcut has a real caveat: `stored` counts local rows, and matches the
server's total only while nothing was dropped in parsing and nothing was deleted upstream. Where a
parser drops some upstream chapters and upserts never delete, the counts can diverge permanently,
and the shortcut simply stops firing - it fails cheap in that direction. It fails silently in the
other: one chapter deleted and one added between refreshes leaves the total unchanged, so the
change is missed. There's no clean fix short of a source stating its complete set, which is the
rejected `ReconcilingSource` idea below - so the tradeoff is either keep the shortcut knowing its
failure modes, or delete it and always walk the feed.

## Candidates, not yet justified

Recorded so the shape is on hand when the forcing case arrives - not a roadmap. Each names the
problem it would solve rather than the feature it would be.

- **`UpdatingSource`** - one request reporting what changed across many series, instead of one
  `chapters()` call per origin. The largest scaling win available if it's ever needed.
- **`DescramblingSource`** - a transform over page bytes after download, before decode: pages stay
  URLs, the source declares what to run over them, the reader stays ignorant. The one candidate
  that fails the discipline test above - a source needing it would be broken without it - so if it
  ever lands it argues for widening the base contract instead.
- **`ThrottlingSource`** - per-source rate limits instead of one global stagger, since a
  fast-tolerant source and a scrape-fragile one shouldn't share a ceiling.
- **`AccountSource`** - acting as a user (follows, reading lists, server-side progress), as
  opposed to `AuthenticatingSource`, which is only about getting past a wall.
- **`CursorPaginatedSource`** - for a keyset-paginated source, when one appears; every current
  source is page-numbered.
- **`ResolvingSource`** - mapping an old slug to its current one, so a site restructure repairs an
  origin instead of stranding it.

Deliberately not pursued: a protocol for "needs `WebRenderer`" (an implementation detail of how a
source fetches, not a contract with the app), and one for declaring page dimensions (already
solved - `PageURL.size` is optional and needs no declaration).

### Why `ReconcilingSource` doesn't exist

The idea was a source promising its chapter list is complete, so rows that vanished upstream could
be deleted. It contradicts the app's premise: nothing here is ever deleted out from under the
user. A disconnected source's origin keeps every chapter rather than losing them; the launch purge
spares anything with a read date; metadata pools on the series so a source dying takes nothing
with it. A chapter row carries `progress` and `lastReadDate` - deleting one throws away reading
history because a scanlator retracted a release.

Once deletion is off the table, the completeness promise has no consumer. What remains of the
concern - a vanished chapter still ranking and still dead-ending the reader - is answerable lazily
at the point of failure instead: the content call already fails, so flag it there. No completeness
promise, no extra requests, and it only fires for a chapter someone actually opened.

## Why the split exists at all

`SourceService.chapters` once took a `have: Int` parameter and returned an optional list, where
`nil` meant "nothing changed." Only one source's server could act on that; the others took a
parameter they ignored and returned an optional they never made `nil`. An optional also can't say
three things at once - unchanged, genuinely empty, and a real list - a distinction that ended up
carried entirely by a comment. And a reader of `SourceService` had no way to tell that clause was
for one source only, so the natural assumption was that it mattered everywhere.

The fix kept `SourceService` at one method returning one list, and moved the shortcut behind
`RevalidatingSource`.
