# Comments

File header, then almost nothing else.

```swift
//
//  FileName.swift
//  aletheia
//
//  Created by Angelo Carasig on D/M/YY
//
```

Every `.swift` file starts with that block and nothing else - no `///` doc comments, no inline
`//`, no `// MARK:` on new code.

## When a comment is warranted

A comment survives only if it's context the code can't say about itself:

- A bug or incident reference - this shape looks wrong but is intentional because of something
  that happened.
- A workaround for a library or platform quirk - GRDB, SwiftUI, UIKit, or WebKit behaves
  surprisingly here.
- A non-obvious invariant that causes real damage if violated, and isn't derivable from the
  surrounding code.
- A deliberate performance or security tradeoff over the obvious alternative.
- An actionable `TODO`/`FIXME`/`HACK`.

Design rationale that reads as obviously correct once you see the code doesn't qualify, even when
it's accurate and well-written. Narrating what the code already says doesn't qualify either.

## Style

- Lowercase, no trailing period, terse.
- Explains why, never what.
- ASCII punctuation only - no em dash, en dash, ellipsis character, curly quotes.

## Legacy comments

Existing `///` doc comments and `// MARK:` sections predate this convention and stay as they are -
don't strip them just for existing, and don't add new ones. Judge them by the bar above only if
you're already touching that comment for another reason.
