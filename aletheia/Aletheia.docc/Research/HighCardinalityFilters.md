# High-Cardinality Filters

> Note: The UI thresholds this research produced (search field past 15 options, search-only mode
> past 100, render cap 60) already shipped and are stated in <doc:Design>'s "Search and filter
> surfaces" section - this page doesn't restate them. The runtime-fetch contract this page
> originally argued for was **not** taken; verified current: `SourceFilter.Option` still has no
> `group` or `frequency` field, so that part of the proposal remains an open gap, not a decision
> reversed.

How a source offers a filter vocabulary too large to declare as literals in its descriptor -
written when a source turned up with thousands of tags against every other source's dozens.

## What breaks at scale, and what doesn't

Network cost isn't the problem - a several-thousand-tag vocabulary gzips small enough to fetch on
every launch for free. What actually breaks: `SourceDescriptor.fingerprint` hashes every option id
and name and lands on the source's stored hash, so baking a huge upstream-owned vocabulary in
means the upstream's own taxonomy edits become spurious schema churn; the descriptor file becomes
hundreds of KB of literals in a file meant to stay readable; and the filter sheet renders every
matching option eagerly into a flow layout, which doesn't scale to thousands of chips built on
open.

Curating a smaller subset doesn't work either - the tail of a large tag vocabulary usually *is*
the vocabulary. A handful of top tags cover a small fraction of real usage, and the discarded
majority is exactly the specific, high-value filtering people actually want (a named trope or
niche descriptor), not the broad genres that already have their own filter.

## The path actually taken

Rather than the runtime-fetch contract this research proposed (split declaration from options: the
descriptor just says a filter exists, an opt-in protocol supplies its options at request time,
keeping the bulk vocabulary out of the fingerprint) - the source that forced this question ships
its large vocabulary as a bundled JSON resource instead. That keeps the vocabulary inside the
fingerprint, the opposite of what this research argued for, accepting the fingerprint-churn cost
rather than routing around it. The tradeoff was judged acceptable for one source; it may not stay
acceptable if a second very-large-vocabulary source appears with a taxonomy that changes often.

**`Option.group` and `Option.frequency` are still missing.** The source that ships the bundled
vocabulary already has both fields in its own data and discards them on decode, because `Option`
has nowhere to put them. A group would let a large sheet section itself (dozens of natural
sections beat one flat list); a frequency would give a non-alphabetical default ordering, since
alphabetical over a large vocabulary surfaces "Absolute Boyfriend" before anything a reader
actually wants to filter by. This is the one part of the original research that's a live gap
rather than a decision made differently.

## Caching, if the runtime-fetch path is ever built

Fetch once per source on first sheet open, not at launch - most sessions never open a refine
sheet. Hold in memory for the app's lifetime; a vocabulary that changes periodically doesn't need
to be right within a session. No persistence, no new table - a schema change to avoid a fetch that
size would be the wrong trade. Failure should be non-fatal: the filter renders empty or hides,
everything else still works - that property is what would make the protocol a legitimate opt-in
rather than a requirement.
