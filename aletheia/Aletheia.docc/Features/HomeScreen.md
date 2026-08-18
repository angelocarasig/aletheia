# Home Screen

> Note: `Screens/Home/` and `Screens/Activity/` are both substantially built (`ContinueCard`,
> `UpdatesScreen`, `ReadingChart`, `ReadingHeatmap`, `ActivityNowSection` all exist), and
> `reading_event`/`reading_session` are real tables. `Screens/History/HistoryScreen.swift` is still
> a literal placeholder. This page mixes shipped decisions with still-open ones inline rather than
> separating them - worth splitting into a tighter Features article if this screen gets touched
> again.

How the Home and Activity tabs were designed, drawing on an ecosystem survey of reader/media apps,
a community-demand pass across several reader-app issue trackers, and a granularity analysis of
what event history each feature needs.

## The one governing principle: resume-first, never recommendations-first

Every non-commercial reader/media app surveyed leads its home surface with the user's own
in-progress reading. Every commercial app that inverted this order - promoting recommendations
over resume - produced the loudest documented backlash in the survey, repeatedly. Discovery lives
in this app's Search/Sources tabs; Home is the user's own reading, full stop. No recommendations
surface on Home.

**Streaks are not built as a loss mechanic.** Direct demand for streaks across several reader
communities was essentially zero, and the surrounding culture is actively wary of them (guilt
discourse around other apps' reading challenges, streak-anxiety criticism of language-learning
apps). What's wanted instead is a passive record - a heatmap with current/longest as retrospective
facts beside it, never a countdown with penalties. This matches <doc:Design>'s positive-framing
rule directly.

## Why the event log had to come before any UI

State columns alone (`series.lastReadDate`, `addedDate`) serve the continue-reading rail and
recently-added rail for free, but fail four different ways for anything counting reading activity
over time: a re-read overwrites the one date column instead of accumulating, "mark all as read"
touches no date at all, opening a series stamps a read date without any reading happening, and
sibling-row propagation writes one date across multiple rows. A day-bucketed event log is what
counts/heatmap/streaks actually need.

The event log's own schema and rationale live in <doc:ActivityHistory> and <doc:Schema> (the
no-foreign-key exception). What this research settled that isn't restated there: both event
grains (per-completion and per-session) had to land together rather than staged, because neither
can be backfilled - a week without the log running is a week of history that never existed, and
every reader-app project that deferred a session-level log documented regretting it later,
recovering only fragments of what a live log would have captured. The marginal cost of the
session grain is roughly one insert per sitting on top of the near-free per-completion grain, and
it's what buys the actually-desired headline stat (time spent reading, which users demonstrably
audit hardest of any number an app shows them) plus a real answer to "what did I read this week."
Raw page-turn events were considered and rejected outright - nothing downstream needs them, and
the reader already batches page progress behind a short throttle that a raw event stream would
bypass for no consumer.

## The Reading section redesign

Home originally shipped a three-tile stat strip (a chapter count, time read, current streak) as
one tap target into a stats screen. A six-lens review panel (<doc:FeedbackIteration>) rejected it
on first pass, and three of its complaints were independently confirmed against the code rather
than taken on faith: a scope control that visually applied to all three tiles but only actually
filtered two of the three queries; a `.combine`-then-`.accessibilityLabel` sequence that silently
discarded the combined content, so VoiceOver announced only a generic "opens details" instead of
any of the three numbers; and an uncapped wall-clock time figure that kept counting while the
reader sat open and unused.

The replacement: **the section header is the navigation, not the tiles.** A single 44pt tappable
header with a trailing glass-circle icon (the one sanctioned exception in <doc:LiquidGlass> to
"inline controls stay flat," since here the glass surface *is* the entire affordance) replaces
three separately-styled tiles sharing one invisible tap target - which a full panel agreed was an
affordance lie: the visual grouping promised three destinations and delivered one. The body
became a short prose line rather than tiles, since prose reflows correctly under large accessibility
text sizes where a fixed tile geometry breaks. The streak and the uncapped time figure both moved
off Home entirely, onto the detail screen where a scope control can actually mean something.

**A backlog count that only ever grows is not shown as a headline on Home after a long absence.**
The original design hid the whole section once a reader had been away past a threshold, reasoning
that a growing "unread" figure punishes returning. The panel found the harm real but the fix
wrong: hiding a section delays the judgement rather than removing it, and the day it reappears the
reader learns the app was managing what it showed them. The section is replaced by a plain
continue card after a long gap instead - a door, not a dashboard, and nothing left to hide.

**A three-card "hub" was proposed as a scalability fix and rejected unanimously on a second
round.** Giving each stat tile its own destination looked like it would fix the affordance lie
honestly, but the actual inventory behind it turned out to be one real destination and two things
that already had homes elsewhere - a three-slot grid built for a population of one. The generalizable
lesson: a fixed-size card grid doesn't scale, it accretes, and nothing in a flat grid ranks itself,
so a sixth candidate for the row has no principled way to compete for a slot against the first
three. The ecosystem's actual growth mechanism for a reading-focused home surface is better-ranked
rails with user-controlled order, not a launcher grid.

## The bar drill-down

Tapping a bar in the reading-activity chart re-scopes the existing recent-reading list to that
bucket, rather than opening a sheet or a second list - a sheet would hide the bar that was just
tapped, and a second inline list duplicates the first. Membership follows every bucket a sitting
overlaps, not just the one it's filed under by its stored day key, so a sitting spanning midnight
correctly appears (in full) under both buckets it touches rather than leaving one bar with no
rows to explain it. An empty bucket is still selectable and says so explicitly, rather than
swallowing the tap silently.

## Build order and current gaps

The event log and both rails that need only state columns (continue-reading, recently-added)
shipped first; the stat strip and its drill-down (needing weeks of log rows to be meaningful)
followed once the log had been running; the Activity tab's merged feed came after that. Still
open: the Updates screen has no per-series dismiss and no mark-all-read, which is what the panel
that reviewed it named as the difference between "a real destination" and "the same list one tap
further away" - until those exist its purpose is narrowly to get an overlong list off Home. An
updates-arrival-fact schema question (does a chapter need its own `addedDate`, separate from the
source-stated `publishedDate`, to distinguish "just discovered by an existing source" from "newly
attached source's whole back catalogue") is resolved by whatever `chapter.addedDate` currently
does in the schema - check <doc:Schema> and the current `ChapterRecord` rather than assuming this
page's proposal is what shipped.

The Activity tab's live-operations area ("Now" section, download queue) follows the same shape
this research settled on: live progress and history are always sibling surfaces across every
surveyed app - live tasks never become feed rows, they render in a dedicated live section above
the feed and disappear into a completed-item once done. `BGContinuedProcessingTask` is the
platform answer for surviving backgrounding, matching the newest-API-first convention.
