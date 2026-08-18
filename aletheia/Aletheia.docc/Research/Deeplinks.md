# Deeplinks

> Note: research only. Nothing here is implemented - no URL scheme, no share extension, no
> `onOpenURL` handling exists in the app today.

Getting a URL from elsewhere on the device into the app - "I'm looking at a series on a source's
website, open it here" - and the reverse.

## The constraint that decides everything

**Universal Links can't be claimed for a domain this app doesn't own, and there's no workaround.**
They require an `apple-app-site-association` file hosted on the target domain naming this app's
team and bundle id - only the domain owner can host that file, and there's no user-facing "always
open these links in this app" setting on iOS the way Android's intent-filter disambiguation
allows. Handoff from Safari is gated on the same mechanism, so it's out for the same reason. This
is also why Android readers look more capable here - an Android app can declare an intent-filter
host and the OS routes a raw source URL into the app with no domain ownership needed at all.
That option doesn't exist on iOS.

**Consequence: every viable path is user-initiated.** Nothing built here makes a tapped link in
Safari open this app.

## What the ecosystem ships

No surveyed iOS reader has a share extension or universal links. The two that ship inbound
handling both use a custom URL scheme (`aidoku://`, replacing `https`; `suwatte://deeplink?url=`,
wrapping it). The one Android reader in the survey with no platform config at all just accepts a
pasted URL into its search bar and resolves it locally - no entitlement, no extension, no scheme
registration, works from any app that can copy a URL. That's the path worth taking first.

Across every surveyed app, the split is the same: a source *declares* what URLs it owns (a host
list, a prefix), and matching happens centrally in the host app scanning that declaration - nobody
puts regexes in the per-source declaration. Parsing itself is nearly always pure string work with
no network call; a fetch only shows up for chapter-to-parent-series resolution, or as a generic
fallback that fetches details and searches by title.

## This app's URL shapes

Every source here follows `<host>/<marker>/<slug>[/decorative]`, so URL-to-slug is one rule with a
per-source marker and no fetch needed - one existing source already implements exactly this as a
private search-parser helper. One source is the exception worth remembering: its series URL fuses
an id and a cosmetic slug into one path component, shipped three different URL shapes over time,
so recovering the id needs a three-way fallback (last component; the part after a dot if one
exists, for a legacy shape; else the part before the first hyphen; else the component itself) -
worth copying wholesale from prior art rather than re-deriving, since a link pasted from an old
bookmark is exactly the case this feature exists to serve.

## What it would take to build

**The source contract** would be an opt-in refinement (see <doc:SourceProtocols>) - synchronous
and network-free by default, since every source can answer by parsing alone:

```swift
protocol DeepLinkingSource: SourceService {
    func target(for url: URL) -> DeepLinkTarget?
}

enum DeepLinkTarget: Sendable {
    case series(slug: String)
    case chapter(seriesSlug: String, chapterSlug: String)
}
```

Routing candidates come from a source's declared base URL host for free; a source needing to
declare mirrors would need its own hosts list, entering the descriptor fingerprint since it's part
of static identity. Multiple sources legitimately owning overlapping domains (an aggregator and a
mirror) wants a picker, not first-match-wins - the existing disambiguation UI pattern
(<doc:Details>) is the precedent.

**The resolve path should reuse matching, not duplicate it**: parse the URL, build a
`SeriesEntry.source(sourceSlug:stub:)`, and run it through the existing match flow rather than a
parallel one. Two gaps stand in the way today: a series stub's title is non-optional and a bare
URL can't supply one (so tier-two title matching would need to either fetch details first or make
title optional), and an origin's stored URL is never queried for matching even though it would be
the most precise tier available.

**Entry points, cheapest first:**

1. Outbound sharing first - an origin's stored URL plus a share sheet action is a small amount of
   UI over data already stored, and has no platform constraints at all.
2. Paste-into-search - the pattern above, highest value for the effort, no platform config.
3. A custom URL scheme plus `onOpenURL` - cheap, and it's the plumbing everything after it targets
   (a user-built Shortcut, in-app links inside a synopsis).
4. A share extension - the only path that appears in Safari's share sheet, with a hard limit: a
   share extension cannot open its containing app (the API call for that returns false, and the
   documented Apple guidance is that share extensions aren't allowed to). It has to finish its job
   inside the sheet.
5. A Safari Web Extension - considered and set aside; it needs several deliberate permission steps
   before it works once, and duplicates what a share extension already does for a second target
   with its own manifest.

**A share extension must not write to the database directly.** GRDB's own guidance is that sharing
a SQLite database across processes is close to untestable on iOS, and critically, database
observation can't see writes made by another process - a row written by the extension wouldn't
appear in a running app's UI at all without a lot of extra machinery (Darwin notifications,
persistent WAL, file coordination) this app's database configuration doesn't have. The workable
shape is a plain-file inbox instead: a small JSON file in the shared app-group container that the
extension writes and the main app drains on next foreground through its normal path. Every hazard
above disappears, and it's actually testable.

## App Review

Recorded factually. A share extension's activation rule enumerating target hostnames is reviewable
metadata; a generic wildcard rule isn't, which is a real asymmetry in how the same feature reads
to review depending on how it's declared.

## Recommended order

1. Outbound sharing - no new concepts.
2. Paste-into-search - highest value per unit of work, no platform config.
3. The deep-linking source contract and central resolver - needed by everything after this.
4. A custom URL scheme - unlocks Shortcuts and in-app links.
5. A share extension - only once the inbox-file design is settled.

The first two need no new target, no entitlement, and no `Info.plist` change.
