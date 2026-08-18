# Loading Transitions

How a surface moves from "not yet" to content - the skeleton, the swap, and what animates it.

## The standard

1. **One ``LoadPhase`` value per loading surface** - `pending`/`empty`/`content`/`failed` (a
   surface may omit cases it can't reach). Derived, not stored: fold booleans/optionals into one
   computed value. The branch switch and the animation key are the same value - never a correlated
   boolean (`isLoading`, `isIdle`, `slots.isEmpty`), which is the root cause of a dead or partial
   swap animation.
2. **`.opacity` crossfade, on the container.** Each branch carries `.transition(.opacity)`; one
   `.animation(.settle, value: phase)` sits on the surviving layout container (`VStack`/`ZStack`,
   never a bare `Group`). `.blurReplace` survives only for content-to-content identity swaps (not
   loading swaps) and must degrade to `.opacity` when `\.accessibilityReduceMotion` is set.
3. **One settle token: `Animation.settle` (`.smooth(duration: 0.35)`).** Declared once in
   `Environment/Theme.swift`, used by every loading swap. Non-loading animations (sheet staging,
   expand/collapse, grid mutations) are a separate concern and don't reuse this token or its name.
4. **Skeleton rules.** A skeleton mirrors the real layout - explicit bars, or real card instances
   with placeholder state. `.shimmer()` goes on the container, one sweep, one animated mask. The
   region is `.allowsHitTesting(false)` and `.accessibilityHidden(true)` - redaction alone still
   reads dummy text to VoiceOver. Shimmer renders as a static dim under Reduce Motion. Whole-branch
   swaps only - never per-row transitions inside lazy containers, which eat removal transitions.
5. **Spinners are action feedback, not first paint.** `ProgressView` keeps its legitimate sites -
   saving overlays, the refresh pill, load-more footers, page-image placeholders where the byte
   total isn't knowable. A content surface's first paint is a skeleton. Empty/error states stay
   `ContentUnavailableView`, gated on `phase` - reachable only from a landed fetch, never from
   `pending`.
6. **A symbol never crossfades - it draws.** Where the changing view is an SF Symbol, the swap
   uses a symbol effect rather than `.opacity`:

   | The symbol... | Modifier |
   |---|---|
   | changes glyph in the same slot (toggle, status, chevron) | `.contentTransition(.symbolEffect(.replace))` |
   | enters or leaves the hierarchy | `.transition(.symbolEffect(.drawOn))` (`.drawOff` outgoing) |
   | is busy | `Image(systemName: "progress.indicator")` + `.symbolEffect(.rotate, options: .repeat(.continuous))` |

   A spinner in such a slot must be a symbol, not a `ProgressView` - a `ProgressView` has no stroke
   for the outcome to draw out of. The animation has to exist explicitly: `.contentTransition`
   renders nothing unless the write happens inside a `withAnimation`, or the view carries
   `.animation(_:value:)` keyed to the state that changed (needed whenever the value arrives from
   a `Menu`, which animates nothing on its own). Reduce Motion falls back to `.opacity`, spelled
   out at the call site: `.transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))`.

   Scope: this is about the glyph changing, not the branch. A phase swap whose branches happen to
   contain symbols is still rule 2 - one `.opacity` on the container.

## Deliberately not adopted

A generic `Loadable<Value>` wrapper - view models are observation-driven and derive phase from
richer state; a wrapper would fight that. `TimelineView`-based shimmer - the gradient-mask shape
already in use is the settled approach elsewhere too. A blanket anti-flash debounce - most
surfaces here are database-backed and resolve in milliseconds, so a delay before showing the
loading state is added per-surface only if skeleton flash is actually observed, not by default.
