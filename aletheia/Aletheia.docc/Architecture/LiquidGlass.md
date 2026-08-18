# Liquid Glass

Why a glass surface renders dark when you expected light, and which variant to use where.

## Glass adaptivity is size-dependent

Small elements (navbars, tabbars, a 44pt circle) constantly adapt their appearance to what's
behind them, including flipping from light to dark based on the background. Bigger elements
(menus, sidebars, a card) adapt to context too, but don't flip light/dark - their surface area is
too large for that transition to read as anything but distracting; they keep the environment's
appearance and simulate a thicker material instead.

So two surfaces with identical modifiers can legitimately render differently - a 44pt circle flips
light/dark over changing content, a ~120pt card doesn't. The switch sits at roughly 65pt of layout
height; shape, width, and element count don't affect it, only height and backdrop luminance.

## Variant choice

| Context | Variant |
|---|---|
| Chrome over your own content layer - sheets, lists, scroll views | `.regular` |
| Chrome over full-bleed media you don't control the luminance of - a reader, a cover viewer, a player | `.clear` |

`.regular` blurs and adjusts the luminosity of background content - it goes dark over dark.
`.clear` is permanently transparent with no adaptive behaviour at all, which is exactly why it's
the right choice over media: it can't flip on you. Don't mix the two in one context.

`.clear` keeps the lensing that reads as glass but supplies no separation on its own, so chrome can
disappear into a busy page underneath it. A dimming layer fixes that - applying it as
`.tint(.black.opacity(x))` on the glass itself does the job without a second view (the reader's
`ReaderConfiguration.chromeTint`, default `0.4`, is this in practice). A dark tint implies light
content, and `.clear` won't adapt to supply it, so a surface using this pattern should also pin
`.environment(\.colorScheme, .dark)` - an immersive surface behaves like a video player regardless
of system appearance.

## Never pin foreground colours on glass

Glass resolves its own light/dark appearance and vends a matching content colour. Forcing a fixed
foreground fights that and only matches by luck.

Use `.primary`/`.secondary` on glass; keep `Palette.*` for solid backgrounds. Semantic tints
(`.brand` for an active state) are fine as a tint on the surface, not as a glyph colour.

`Menu` is a special case - it applies the accent colour to its own label regardless of what's set
on the content. `.menuStyle(.button).buttonStyle(.plain)` stops it.

## Mechanics

- **`GlassEffectContainer`** groups sibling glass shapes so they blend and share a render pass. It
  doesn't influence the light/dark decision, and is harmless but inert around a single child. Too
  many containers costs performance.
- **`glassEffectID`** is the morph mechanism, not decoration - use it only when a shape genuinely
  morphs between states, never on a view with no `glassEffect`.
- **`.interactive()`** adds press response only, no appearance implication - it's the wrong call on
  a large passive container, since it makes the container squish under touch with nothing to
  navigate to.
- **Glass cannot sample glass.** A `glassEffect` nested on a glass surface renders as a flat
  sticker. Controls sitting on a glass card should be plain.
- **Backdrop sampling works over UIKit-hosted content too.** Capture happens over the whole window
  layer tree regardless of whether the layers below came from SwiftUI or a
  `UIViewControllerRepresentable`.
