# Release Prediction

`DetailsComposer.Cadence` (`Screens/Details/Model/DetailsComposer+Cadence.swift`) implements a
simplified version of the algorithm below.

Predicting when a series' next chapter will arrive, from its own release history alone -
deterministic, no training, one pass over recent chapter dates.

## The pipeline

1. **Collapse to release events.** Group chapters by number, take the earliest `publishedDate` per
   number (a chapter mirrored across origins is one release, not several), drop anything at or
   before the Unix epoch (every source's own parse-failure sentinel, which would otherwise inject
   a multi-century gap into the math). Sort, then merge anything within 48 hours of the previous
   kept event into it - a scanlator catching up on a backlog over a night reads as one release, not
   several artificially tight gaps.
2. **A stated publication status short-circuits everything.** If any supplier (source or tracker)
   states `Completed`/`Cancelled`, that wins outright - `.finished`. If one states `Hiatus`, that's
   `.hiatus`, attributed to whichever supplier said so. Neither state runs the arithmetic below at
   all - a stated fact from a tracker or source outranks an inference from silence.
3. **Below the minimum event count, no guess is offered** - `.none` for zero events, `.sparse` for
   some but not enough.
4. **Two-pass median for the gap estimate.** A provisional median over the last ten gaps sets a
   break threshold relative to that series' own cadence (`max(21 days, 3x the provisional gap)`) -
   a fixed threshold would misclassify every normal gap on a monthly series as a break. The real
   estimate (`gHat`) is the median only over gaps at or below that threshold.
5. **Dormancy outranks lateness, and both outrank a spread too loose to name a date.** If it's been
   longer than `max(90 days, 4x gHat)` since the last release, the state is `.dormant`. Otherwise
   if the gap spread (mean absolute deviation over the median) is at or above a loose threshold,
   the state is `.irregular` - too noisy to predict honestly. Otherwise if the elapsed time already
   exceeds the estimated gap, it's `.overdue(by:)`. Otherwise it's `.predicted(date, confidence)`,
   with `.high` confidence requiring both a tight spread and enough events to trust it - a single
   observed gap has zero deviation by construction and would otherwise read as falsely confident.

## What a reader can force

A "best guess anyway" action recomputes the same resolver with a lower minimum event count (2
instead of 4), available only when the normal result wasn't already a real prediction or overdue
call. The forced result lives only in memory for that session - never persisted, and cleared the
moment new chapter data arrives, since a guess the reader explicitly asked for once must not
become the app's standing opinion on the next launch.

## What differs from the original research

The researched design (see the project's dated history for the full investigation) called for a
five-state model with a distinct inferred "on break, expected back around X" state separate from
"overdue," reasoning that a correctly predicted seasonal break shouldn't read as broken. The
shipped version doesn't carry that distinction - it has `.dormant` (long silence) and `.overdue`
(short-term lateness against the estimated gap) but no separate seasonal-break state with its own
predicted return date. `.hiatus` only fires from a stated publication status, never inferred from
gap patterns alone. The batch-collapse window shipped at 48 hours rather than the researched 12,
based on measuring real chapter data - a real backlog catch-up event visibly spans a night and a
morning, not one hour.
