# Errors

How a failure travels from the subsystem that raised it to the person looking at the screen.

## The shape

`Utilities/Failure.swift` is the one conversion point: a `Failure` (`title`, `message`,
`isRetryable`) plus a `DescribableError` protocol an error type opts into. `Failure.init(_
error:fallback:)` is the only place an `Error` becomes presentable text - an error that describes
itself is logged rather than reaching a screen as raw syntax. `String(describing:)` on an error is
never correct: it doesn't consult `LocalizedError`, it prints the case name and its associated
values.

`failure: Failure?` is the vocabulary across every screen with a fallible load - Details, Reader,
Library, Home, Stats, Updates, Activity, Failures, SearchGrid, Tracking, TrackerLink,
TrackerCandidate, Bootstrap.

## Error types

One typed error per subsystem, each conforming to `DescribableError` unless noted:

| Type | Where | Notes |
|---|---|---|
| `ReaderError` | `Reader/Contract/` | chapter-scoped, carries the chapter id, `isRetryable` |
| `ReaderPageError` | `Reader/Contract/` | page-scoped - `.offline`, `.timedOut`, `.unavailable(status:)`, `.corrupt`, `.failed` |
| `NetworkError` | `Network/` | also `isCancellation` |
| `KeychainError` | `Keychain/` | wraps `OSStatus` |
| `TrackerError` | tracker services | |
| `CaptureFailure` | `Network/Sources/Auth/` | `.timedOut`, `.cancelled` - both reach the auth sheet |
| `AssetError` | `Utilities/` | `.notAnImage(URL)` |
| `DetailsError` | `Screens/Details/` (private) | `.missingIdentifier` - stays a `throw` rather than a precondition; unreachable in practice, and a throw that degrades to a logged generic failure is a better outcome on a device than a crash |
| `ViewError` | `Database/Infrastructure/` | doesn't conform - fires during migration, before any screen exists |

## Retryability

Carried on `DescribableError` with a permissive default - retrying a read is harmless, and a dead
end costs more than a button that doesn't help. Types with genuinely permanent cases
(`ReaderError`, `ReaderPageError`, `NetworkError`) state theirs explicitly. Retry only ever renders
where `isRetryable` says so - it's an offer, not a reflex.

## Scope the error type to the unit that failed

`ReaderError` is chapter-scoped - every case carries a chapter id. A page that won't download is a
different unit, so it gets `ReaderPageError` rather than reusing the chapter-scoped type. A
third-party error vocabulary stops at one boundary: `ReaderPageError.init(_ KingfisherError)`.

## Presentation

- A view model hands a view a `Failure`, never a raw error.
- Full-surface failure = `ContentUnavailableView` with `"Couldn't <verb>"` plus
  `exclamationmark.triangle`; an action that fails over otherwise-valid content is an alert, not a
  screen replacement.
- `Failure.message` is empty when a type states only a title - `ContentUnavailableView` draws no
  gap for an empty description, so this needs no special-casing at the call site.
- `Failure.sentence` exists for one-line slots (a launch-failure screen, a save-state row) where an
  empty message under a title would read as more broken than a repeated title.
- A `LoadPhase.failed` case that drives a branch swap still carries a `Failure` if the branch it
  swaps to has anywhere to put a sentence (a full `ContentUnavailableView` with title, description,
  and an actions slot). A payload-free case is only correct where the failure branch renders
  nothing beyond a generic state.
- In a UIKit surface that can't reach `ContentUnavailableView`, rebuild its anatomy - glyph, title,
  message, action - rather than hosting SwiftUI inside it. `PageFailureView` is that rebuild for
  the reader's page cells, not a licence to hand-roll empty states elsewhere.

## What's deliberately not modeled

No silently swallowed errors - every `catch` either reaches `Failure` or logs. `fatalError` is
reserved for unavoidable `init(coder:)` conformances and genuine misconfiguration that should
crash rather than degrade. `try?` is for parsers where a missing optional field is the expected
case, not a failure being hidden.
