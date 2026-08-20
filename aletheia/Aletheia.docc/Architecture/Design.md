# Design

The rules for building UI in this app. Each section links to the full doc where one exists; this
page states the rule, the linked doc keeps the evidence.

Flat, minimal, offline-first. The screen renders from the database; the network only ever fills
the database. Content is colourful (covers), so chrome stays monochromatic and accents are
rationed to state that varies.

Every rule below assumes iOS 26 - see <doc:Aletheia>. Liquid Glass, `.sensoryFeedback`, symbol
effects, and `WebPage` are the baseline, not an upgrade path.

Before iterating on a surface that's built but "looks off," run the six-lens review panel rather
than eyeballing it alone - see <doc:FeedbackIteration>.

## Loading and phase transitions

Full doc: <doc:aletheia/LoadingTransitions>

- Every loading surface derives **one `LoadPhase`** (`pending` / `empty` / `content` / `failed`,
  ``LoadPhase``) and both branches on it **and** animates on it. Never key the animation on a
  correlated boolean (`isLoading`, `isEmpty`) - that's how swaps go dead or partial.
- Swap = `.transition(.opacity)` per branch plus one `.animation(.settle, value: phase)` on the
  surviving layout container (`VStack`/`ZStack`, never a bare `Group`).
- `.settle` is the only loading-swap animation. Don't invent durations.
- Skeletons mirror the real layout (explicit bars or real card instances), `.shimmer()` on the
  container (one sweep), `.allowsHitTesting(false)` plus `.accessibilityHidden(true)`. List-shaped
  sheets use ``SheetSkeleton``.
- `ProgressView` is action feedback only (saving, refresh pill, load-more slot) - never the first
  paint of a content surface.
- A wait with a known size gets a measure, not a spinner: where the byte total is knowable, show
  progress (a stroked ring with the percentage inside, ``PageProgressView``). Reveal on a delay so
  a cache hit never flashes it, and fall back to the same instant path when the response states no
  length.
- `ContentUnavailableView` appears only after a fetch has landed - pending is not empty.
- Swap whole branches, never per-row transitions inside lazy containers (they eat removal
  transitions).
- A symbol never crossfades - it draws. When the changing view is an SF Symbol, use a symbol
  effect: `.contentTransition(.symbolEffect(.replace))` when the glyph changes in the same slot,
  `.transition(.symbolEffect(.drawOn))` when it enters or leaves. A busy state in such a slot is
  `progress.indicator` plus `.symbolEffect(.rotate, options: .repeat(.continuous))`. The write must
  happen inside an animation, and Reduce Motion falls back to `.opacity` at the call site.

## Liquid Glass

Full doc: <doc:LiquidGlass>

- Chrome always; cards by decision. A card - a tappable rectangle standing for one thing, with its
  own padding and corner radius - takes `.glassEffect(.regular.interactive(), in: .rect(cornerRadius:style: .continuous))`.
  What stays flat is everything smaller or more numerous than a card: chips, badges, inline
  controls, section-header fills, tile backgrounds, and anything drawn inside a card - glass
  cannot sample glass.
- One exception to "inline controls stay flat": a lone circular control against the canvas (a
  section-header action, a stepper) takes `.glassEffect(.regular.interactive(), in: .circle)` at
  `dimensions.touchTarget`, because the surface is the entire affordance there. The disabled form
  drops the glass entirely rather than dimming it.
- `.interactive()` tracks the tap, not the look - it belongs only on a card that actually
  navigates. A card that carries information plus its own controls but navigates nowhere keeps
  `.regular` and drops `.interactive()`.
- `.regular` over your own content (sheets, lists); `.clear` over full-bleed media you don't
  control (reader, cover viewer) - `.clear` never adapts, and needs a dark tint plus a pinned dark
  scheme for its content.
- Glass adaptivity is size-dependent (~65pt): small elements flip light/dark with the backdrop,
  large ones don't.
- Never pin foreground colours on glass - use `.primary`/`.secondary` and let glass vend the
  content colour. `Palette.*` is for solid backgrounds. `Menu` needs
  `.menuStyle(.button).buttonStyle(.plain)` to stop accent-tinting its label.
- `glassEffectID` only for genuine morphs; `.interactive()` only on things that should squish.
- Sheets get glass from a partial detent (`[.medium, .large]`); never set `presentationBackground`,
  and give navigation containers `.containerBackground(.clear, for: .navigation)` so they don't
  paint over it.

## Selection language

Full doc: <doc:aletheia/SelectionLanguage>

One vocabulary, four meanings, no substitutions:

| Meaning | Marker | Colour |
|---|---|---|
| chosen option (persisted, exclusive) | trailing `checkmark` (+ row tint); artwork gets a corner `checkmark.circle.fill` badge | `.brand` |
| current position (session, not stored) | container fill 0.15, no glyph | `.brand` |
| membership (non-exclusive) | leading `checkmark.circle.fill` / `circle` | `.brand` / `.muted` |
| finished / complete (fact) | `checkmark` | `.secondary`, never `.brand` |

- Star is reserved for future favorites; amber never marks selection.
- Automatic is a first-class first row showing what it resolves to, not a clear button.
- Preferences commit instantly; staged Cancel/Done only for irreversible or accumulated edits
  (disambiguation, reorder sheets). An instant-apply sheet closes with Close - a "Done" that only
  dismisses is a lie.
- Custom selected rows carry `.accessibilityAddTraits(.isSelected)` and
  `.sensoryFeedback(.selection)`.

## Section controls

Full doc: <doc:aletheia/SectionControls>

- A sort control is a pop-up button - capsule showing the current value as text, neutral tint (a
  sort is always set, so permanent blue says nothing). There's no standard sort icon; sort takes
  text.
- Text controls and symbol controls sit in separate containers - adjacency reads as one button.
- Filter = `line.3.horizontal.decrease`; overflow = bare `ellipsis`, never `ellipsis.circle`; a
  menu with fewer than three items should be a different component.
- Active filter = tinted background plus filled variant plus count, never colour alone. Say "N of
  M" when a filter is hiding things.
- Hide a control that has nothing to choose (one language, one scanlator) - or keep the row shape
  and dim it, but never render an affordance that can't be operated.
- Targets: 44pt default, 28pt floor; controls in one row share one height.
- Bulk actions never mix with sort/filter - they live one screen up or in a selection mode.

## Search and filter surfaces

Full docs: <doc:aletheia/SourceSearch>, <doc:aletheia/HighCardinalityFilters>

- One filter entry point, not peer rows per category; results are the hero.
- Applied filters render as a chip row with a count, each chip removable in place - state must be
  visible without opening anything.
- Sort stays out of the filter surface (always-set single-select vs optional multi-select).
- Vocabulary thresholds: search field past 15 options, search-only mode past 100, render cap 60 -
  and selected options stay visible while searching, or tri-state picks get lost.
- Tri-state include/exclude: cycle with `.success` / `.danger` plus a glyph channel; excludes never
  open the adult gate.
- Reset/Clear is immediate and never staged. An over-filtered empty state carries a "Clear
  Filters" action.

## Adult content presentation

Full doc: <doc:aletheia/AdultContent>

- Two mechanisms, never merged: the gate (which filter options are ticked) decides retrieval; the
  preference (`blurAdultContent`) decides presentation. The preference never shapes a request.
- Blur, never hide. Cover art blurs; the title stays legible. The reveal switch appears only when
  something on screen is actually covered.
- Sensitivity tints filter options (`.adult`, `.suggestive` - red family); adult-only sources are
  badged `18+` on their row, never given a separate section.

## Error presentation

Full doc: <doc:aletheia/Errors>

- A view model hands a view a presentation value (title, message, retryability) - never a raw
  error. `String(describing:)` on an error is always wrong; the typed errors already carry the
  sentence.
- Retry is an offer, shown only when retrying could change the answer (`isRetryable`).
- Full-surface failure = `ContentUnavailableView` with `"Couldn't <verb>"` plus
  `exclamationmark.triangle`; an action that failed over valid content = alert, not a screen
  replacement.
- No error channel that nothing renders - if it's captured, it reaches a screen or a log, decided,
  not defaulted.
- Scope the error type to the unit that failed. `ReaderError` is chapter-scoped; a page that won't
  download gets `ReaderPageError` - `.offline`, `.timedOut`, `.unavailable(status:)`, `.corrupt`,
  `.failed`, with `isRetryable` honest per case. A third-party error vocabulary stops at one
  boundary: `ReaderPageError.init(_ KingfisherError)`.
- In a UIKit surface that can't reach `ContentUnavailableView`, rebuild its anatomy - glyph,
  title, message, action - rather than hosting it.

## Cards, grids, and artwork

Full doc: <doc:aletheia/Library>

- One overlay per artwork, maximum. The unread count is the only thing on a library cover; red is
  correct - an unread count is a notification (items awaiting you, goes to zero), not ambient
  data. Zero unread means no badge; absence is the signal.
- Overlaid text always gets a contrast layer (opaque capsule); nested shapes are concentric
  (`ConcentricRectangle` for artwork in cards).
- No tint on cards - covers are the colour. Glass is allowed on a card per the Liquid Glass rules
  above; a grid cell that's mostly artwork takes neither, because there's no surface left for
  glass to be.
- Cover aspect is 11/16; grid gutter is `screenMargin`; `gridColumns` comes from
  `Preferences.Key.gridColumns`, never a local literal.
- Cards use `.tappable` (press-scale) or `NavigationLink` plus `.plain`; long-press is spoken for
  by the context menu - never both a context menu and an edit menu on one item.
- Card cover placeholders: Kingfisher `.placeholder` shimmer rect plus `.fade(0.25)`.

## Colour

- All colour through `Palette` dot-shorthand (`.foregroundStyle(.brand)`, `.tint(.danger)`) -
  semantic aliases over Radix colorsets plus Apple system neutrals. Never shadow system colours
  (`Color.red` stays reachable).
- Semantics: green = success/complete, blue (`.brand`) = interactive/active, amber = attention and
  only attention, red = error/destructive/notification, gray/`.muted` = secondary/disabled.
- Radix steps pair 11-on-3 (text on subtle background). Step 9 is the solid fill step and can never
  be text - `Palette.Tone` exists so a fill colour can't be passed where text is drawn; `Badge`
  takes a `Tone`, follow it.
- Spend the accent on state that varies. A control that's always blue says nothing; the tinted
  state should mean "something is on."
- `.muted` is `Color.secondary` - low contrast in light mode, kept for automatic Increase Contrast
  support.

## Layout tokens

- Spacing/radius through `Dimensions` numeric tokens (`space8`, `radius12` - the number is the
  value); `screenMargin` 16; `touchTarget`/`size.control` 44.
- No magic numbers: per-view constants go in a `private enum Layout`; app-wide values become
  tokens; user-configurable values live in `Preferences.Key`/`Default`.
- A local per-view animation constant must never be named `settle` - that name is reserved for the
  app-wide `Animation.settle`, and `.animation(Layout.settle, value:)` vs `.animation(.settle,
  value:)` differ by one character and mean different animations. A local non-loading animation is
  fine; reusing the reserved name for it isn't.
- A reserved box is sized to the tallest thing it holds. Where a layout declares a height rather
  than measuring it, an over-generous constant makes nominally equal spacing render unequal.
- A declared height is a constant per content-size category, not one constant. Scale the
  text-bearing terms through `UIFontMetrics`; leave padding, spacing, and hairlines alone, since
  scaling air only inflates the surface.

## Haptics

Haptics go through SwiftUI's own `.sensoryFeedback(_:trigger:)`, which honours the system setting,
plus `Utilities/Haptics.swift` for anything the system vocabulary can't express. There's no in-app
haptics toggle.

- Types, via `.sensoryFeedback`: `.selection` for a choice; `.impact` weights for
  navigation/toggles/destructive; `.success` for completed/added; `.warning` for attention;
  `.error` for failed.
- One haptic per user action, matched to the animation's timing. Background work: one at start,
  one at completion - never per item. Never during reading or continuous scrolling.
- The test: more than 2-3 haptics in a 30-minute session is too many.
- A one-shot reveal may use a ramp, and a ramp is one haptic - the rule above counts events, and a
  ramp is a single event given texture. Two conditions keep this from swallowing the rule: it
  fires once per launch from something the reader didn't do repeatedly (not attached to a value
  that recurs or that the reader scrubs), and it's scheduled as one `CHHapticPattern` rather than a
  loop of awaited sleeps. Reduce Motion skips it entirely, along with whatever count-up animation
  it accompanies. `CountUpHaptic` is the reference implementation.

## Tap handling

- `.tappable {}` for tap actions, `.pressable` for press response - both built on Button plus
  `PressableButtonStyle`, not gestures (iOS 26 `ScrollView` cancels `DragGesture`-based taps).
  `Button` directly only where a system context needs it (menus, toolbars, alerts).
- `NavigationLink` for navigation - semantic elements where they exist.
- Always `.contentShape(.rect)` (or `.capsule`) before `.tappable` on composed rows, so the whole
  row hits.

## Text mechanics

- Inflection markup (`^[\(n) chapter](inflect: true)`) only survives if the literal reaches `Text`
  unerased. Four silent killers: a ternary with a `String` branch, building the string in a `let`
  first, a `String` parameter, and `navigationSubtitle` fed a `String` variable. Use `if`/`else`
  branches, `LocalizedStringKey`/`Text` parameters, and build a `Text` for subtitles.
- `Text`'s `+` is deprecated on iOS 26 - compose with a single interpolated literal.
- Sheet identity idiom: `navigationTitle` plus `navigationSubtitle(Text(...))` with an inflected
  count.
- Never re-render a wire value (a provider's raw string, an option id) - map at the boundary,
  display our vocabulary.

## Sheets

- `[.medium, .large]` detents plus drag indicator; the medium detent is what makes the sheet glass.
- Instant-apply sheets: Close. Staged sheets (reorder, disambiguation): Cancel plus a commit button
  whose label states the outcome, disabled until something changed.
- The close glyph is `xmark`, with one exception: a full-height sheet carrying its own backdrop
  artwork (`[.large]` only, a hero and a scrolling body over its own backdrop - currently
  `DetailsTrackerCandidate`) closes with `chevron.down` instead, since it covers the screen rather
  than sitting on it and reads as a card pulled up. The word is still "Close" in both cases -
  this is a glyph rule only.
- Sheets presented over the reader pin `.environment(\.colorScheme, .dark)` - an immersive surface
  behaves like a video player regardless of system appearance.
- A sheet presented before its data lands shows a ``SheetSkeleton`` and merges late arrivals into
  staged state - never wipes a drag in progress.
- Saving feedback: whole-surface dim to 0.6 while a write is in flight.

## Empty states

- Always `ContentUnavailableView` - there's not one hand-rolled empty `VStack` in the app; keep
  it that way. Search-empty uses `ContentUnavailableView.search(text:)` echoing the query.
- An empty state explains what belongs here and carries an action to resolve it (Browse Sources,
  Clear Filters, Retry). A dead-end empty state is a bug.
- Distinguish the empties: nothing-yet vs nothing-matches-filters vs genuinely-none are different
  states with different copy and different actions.
- Pending is never empty - see Loading and phase transitions above.

## Accessibility

- Never colour alone: every state carries a shape/glyph/text channel beside the colour.
- Custom selected rows: `.accessibilityAddTraits(.isSelected)`. Selection changes:
  `.sensoryFeedback(.selection)`.
- Reduce Motion: `.opacity` crossfades are the sanctioned substitute and need no reduction;
  blur/scale transitions degrade via `AnyTransition.replace(reduceMotion:)`; shimmer goes static.
  New motion must answer "what does this do under Reduce Motion."
- Skeletons are `.accessibilityHidden(true)` - VoiceOver must never read placeholder bars.
- Icon-only controls always get `.accessibilityLabel`.
- 44pt targets; ~12pt spacing around bezeled elements, ~24pt around bezel-less ones.

## Copy and framing

- "series" or "titles," never "manga," in user-facing text.
- Positive framing: name what selecting does, not what disabling loses; metrics celebrate
  progress.
- Avoid vague progress labels - "Loading..." adds nothing; name the thing ("Loading chapters") or
  show the shape instead.
- Button labels state the outcome ("Save 5 Sources," "Remove Source"), not the gesture ("OK,"
  "Done").
- No jargon without context; a technical term the user must know gets explained where it appears.

## Anti-patterns

| Anti-pattern | Instead |
|---|---|
| badge soup (multiple colourful badges per item) | one badge, and only if it demands attention |
| alarm colours for non-errors | semantics under Colour above |
| ambient data dressed as a notification badge | badges count actionable items only |
| negative framing ("0 of 30") | progress framing |
| buried primary actions | primary action visible without scroll |
| decorative colour/borders carrying no meaning | delete them |
| redundant confirmation ("success" badge where presence implies it) | absence is the signal |
| a "Done" that only dismisses | Close, glyph per the Sheets rules above |
| animation keyed to a proxy boolean | phase-keyed, see Loading and phase transitions |
| an SF Symbol crossfading or popping between states | `.symbolEffect(.replace)` / `.drawOn` |
| an affordance that can't be operated | hide it or dim it with the row shape kept |
| filter state visible only inside the menu | chip row / count on the trigger |
| duplicated bulk actions across surfaces | one owner per action |
| timing hacks (`asyncAfter`, sleeps) standing in for state | sequence on awaited results |
| N visually separate cards sharing one invisible tap target | the section header is the navigation - one 44pt target, a chevron, inert body below |
| one control scoping some of the values beside it | every figure under a scope control obeys it, or it doesn't sit there |
| a metric whose modal value is a failure state ("1 day") | suppress below a threshold, or frame as a record rather than a run |
| a punishing metric redrawn as shape to soften it | shape removes the label and keeps the consequence - cut the metric, not its caption |
| `.accessibilityLabel` after `.combine`, silently discarding the values | label names the thing, `accessibilityValue` carries the numbers |
| a section that vanishes at zero between two fixed neighbours | keep the shape, write a real empty state |
| a grid of navigation cards on a content screen | rails grow, doors accrete - add a rail with its own header link, or badge the owning tab |
| a permanent card for a condition that's usually absent | a conditional banner whose presence is the signal |
| a member that comes and goes inside a fixed row | fixed with a zero state, or not in the row |
| a status word with no subject ("Failures," "Problems") | name what happened and to what: "3 sources couldn't update" plus retry |
| a destructive control sitting in a repeating list row | ambient position plus destruction is the trap regardless of glyph - keep destruction behind a confirmation or a context menu, not a bare tap in a scrollable list |
| a "completed" glyph that's still editable treated as inert | a state with something left to change is a resting state, not a fact - only a genuinely terminal state (the only remaining action is undo) should go inert |

## Reach for these before building new

| Component | For |
|---|---|
| ``LoadPhase`` + `.settle` + `AnyTransition.replace` | any loading surface |
| ``SheetSkeleton`` | list-sheet pending state |
| `.shimmer()` | skeleton sweep, container-level |
| ``Badge`` (takes `Palette.Tone`) | status/count capsules |
| ``SectionHeader`` | in-content section titles (title, rule, trailing slot) |
| `ContentUnavailableView` | every empty/error/unavailable state |
| ``PageProgressView`` / ``PageFailureView`` | reader page pending and failed states (UIKit cells) |
| ``FlowLayout`` | wrapping chip collections |
| ``Searchbar`` | in-content search fields |
| ``CollapsingHeader`` | scroll-collapsing header regions |
| `.tappable` / `.pressable` | all tap/press response |
| `.sensoryFeedback` | all haptics |
| ``CollectionForm`` / ``CollectionPicker`` | collection membership UI |

Component idioms live where the components do; this table is the index, not the spec.
