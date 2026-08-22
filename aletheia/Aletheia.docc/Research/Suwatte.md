# Suwatte

Feature scan of Suwatte - an ad-free iOS comic reader by Mantton, GPLv3, SwiftUI + UIKit over Realm
with CloudKit sync. TestFlight-only.

> Scanned 2026-08-22, against `main` (last pushed 2026-03-11). Read from the source tree rather
> than release notes, so the rows below describe code that exists. Source:
> `github.com/Suwatte/Suwatte`. Docs: `suwatte.mantton.com`.

The **Us** column was checked against this codebase. Rows marked `?` weren't checked.

## Legend

| | meaning |
|---|---|
| ✓ | built here |
| ~ | partly built, or built to a narrower scope |
| ✗ | not built - a real gap |
| — | deliberate divergence, not a gap |

## Verdict

Suwatte is the most *configurable* of the readers scanned and the widest in what it will open -
network sources, OPDS servers, Komga, and loose CBZ/CBR/RAR/ZIP archives all land in the same
library. Its reader settings sheet is roughly twice the size of ours.

Two things it has are worth taking seriously because they're near-misses on things we already do:
**smart collections** (a collection defined by a stored filter predicate rather than by
membership), and **ContentLink** (one library entry backed by several sources' copies). The second
is our multi-origin model arrived at from the other direction - see below.

Where we're clearly ahead is anything requiring the app to reason about a series rather than store
it: matching, release cadence, tracker-driven restore. Suwatte's model is a well-built container;
ours does more thinking about what's in it.

## Sources and Content

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Daisuke runners | Sources are JS bundles run in JavaScriptCore or a WKWebView environment, installed from user-added lists | — | Same divergence as Aidoku's WASM plugins, different engine. See <doc:Aidoku> |
| Trackers as runners too | A tracker is also a Daisuke runner, so trackers are user-installable | — | Ours are three compiled services. Bigger divergence than the source model - it means Suwatte ships no tracker at all, the user installs them |
| Local archives | Opens CBZ, CBR, RAR, ZIP from the device, browsable as a directory | ✗ | `DirectoryViewer` plus an `ArchiveHelper` module. CBR/RAR needs an unrar dependency we'd also need |
| OPDS v1 | Adds an OPDS catalogue server as a browsable, readable source | ✗ | `OPDSClient` is a first-class stored model |
| Komga | Documented as its own setup path | ✗ | Same category as Aidoku's Komga/Kavita |
| Cloudflare handling | Gets through interstitials | ✓ | ``AuthenticatingSource`` + WebKit cookie capture, <doc:SourceAuth> |
| Migration | Moves entries off a dead source | ✓ | Theirs is richer: a strategy selector, a preferred-destination rule, and a manual per-entry picker |
| Reverse image search | Search a panel image against SauceNAO, then resolve the result URL back into an installed runner | ✗ | Distinctive, and cheaper than it looks - see below |
| Custom thumbnails | Replace a series cover with your own image | ~ | We pick a preferred cover from the pool of covers sources supplied; we can't take an arbitrary file |

## Library

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Collections | User-defined groups | ✓ | Ours are `CollectionRecord`/`SeriesCollectionRecord` |
| **Smart collections** | A collection defined by a stored filter - reading flags, statuses, sources, tags, text match, content type, with an AND/OR operator - rather than by explicit membership | ✗ | `LibraryCollectionFilter`. Our filter vocabulary is already wider than theirs; what's missing is *saving* a filter as a collection |
| Reading flags | Per-entry state (reading, planning, completed, and so on) usable as a filter | ✓ | `Status` |
| Read Later | A separate queue from the library - saved to read, not yet added | ~ | We fold this into library membership plus `.planning` status. Theirs is a distinct model with its own screen and context menu |
| Multi-select | Bulk actions in the grid | ✗ | `LibraryGrid+SelectionModifier` |
| Compact library view | An alternate denser layout | ✗ | Grid only for us |
| Update feed | A feed of new chapters across the library | ✓ | `UpdatesScreen` |
| Search history | Remembers past queries | ✓ | `RecentSearches` |

## Reader

Suwatte's settings sheet is the widest surface of any reader scanned. Listing it in full because
it's the clearest picture of what "unparalleled customization" actually means in this category.

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Modes | Paged, vertical paged, webtoon, double-paged | ~ | We have four modes but not double-paged: continuous, vertical, LTR, RTL |
| Double-page + first-panel isolation | Two pages side by side, with an option to always show page one alone | ✗ | The isolation toggle is the detail that makes double-page actually usable on a cover page |
| Split wide pages | Detects a spread and splits it | ✗ | |
| Pillarbox / horizontal padding | Sizes images to a chosen percentage of screen width | ✓ | `horizontalPadding` |
| Page padding | Adjustable gap between pages in vertical modes | ✗ | Aidoku's "continuous with gaps" is the same feature. Our `ReaderGapSheet` is unrelated - it reports *missing chapters*, not page spacing |
| Crop whitespace | Trims excess white border around a panel | ✗ | |
| Scale type | Fit height, fit width, stretch, and so on | ? | Unverified |
| Downsampling | Reduces decoded image size | ✓ | `PageDownsampler` |
| Grayscale / colour invert | Image filters | ✓ | `grayscale`, `inverted` in ``ReaderConfiguration`` |
| Custom overlay | A colour + opacity layer over pages with a selectable blend mode | ~ | We have dim, warmth, and chrome tint - fixed effects, not an arbitrary colour and blend mode |
| Background colour | System background or a colour picker | ~ | Ours is dim/warmth, not a chosen colour |
| Transition pages | An end-of-chapter interstitial, suppressed for short chapters | ✓ | `ReaderSeparator`, `SeparatorCell` |
| Tap to navigate | Tap zones, invertible, with a layout picker and an on-screen guide | ✓ | Tap-zone layout plus `ReaderTapZonePicker`. <doc:ReaderBacklog> notes six of nine layouts still missing |
| Auto-scroll | Hands-free scrolling with a speed slider | ✓ | `AutoScroller` for continuous, `AutoAdvancer` for paged |
| Scrollbar position | Which edge the reader's scrubber sits on | ✗ | |
| Haptics toggle | Reader haptics on/off | ✓ | |
| Context actions on a page | Long-press a panel for actions | ✓ | `PageActivityItem` |
| Panel bookmarks | Bookmark a specific page to return to | ✗ | `Bookmark` is a stored model there. Nothing equivalent here |
| Point-accurate resume | Returns to the exact offset, not just the chapter | ✓ | Ours is anchor-based - <doc:ReaderGeometry> |

## Trackers and Sync

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Tracker services | | — | They ship none; the user installs tracker runners. We ship AniList, MyAnimeList, MangaBaka |
| Tracker links | Joins a library entry to a remote entry | ✓ | `TrackerLink` there, `series_tracker` here - <doc:Trackers> |
| Library sync from a runner | Pulls a whole remote list into the library | ✓ | <doc:TrackerRestore>. Theirs is `+LibrarySyncView` on the runner side |
| iCloud sync | Library, links, and progress sync across devices via CloudKit | ✗ | Partial there, and full library sync is disabled in their own README for crashing. Still more than we have |
| Progress markers | Per-chapter progress as its own model | ✓ | |
| Reading statistics | A stats screen over recorded reading | ✓ | Rough parity - our Activity tab, <doc:ActivityHistory> |
| Update notifications | Notifies on new chapters | ~ | Ours reports refresh results without naming series or being tappable - see <doc:Aidoku> for the mechanism worth copying |
| Deep linking | A URL opens the matching series in-app | ✗ | Load-bearing there: it's what makes reverse image search work. <doc:Deeplinks> is research-only here |
| Backups | Export/restore | ✓ | <doc:LibraryBackup> |

## ContentLink, and why it matters here

`ContentLink` is a two-column join: one `LibraryEntry` to one `StoredContent`. A reader who finds
the same series on a second source links it manually, and the entry then draws chapters from both.

That is our origin model, reached from the opposite end. We treat "one series, several sources" as
the *default* shape and spend a whole subsystem working out which rows mean the same series -
matching, disambiguation, a cover pool, preferred titles (<doc:Details>). Suwatte treats a single
source as the default and offers linking as a manual repair when the reader notices a duplicate.

The tradeoff is real in both directions. Manual linking never mis-matches, and never needs the
disambiguation UI, the merge path, or the reparenting bugs those cost us (<doc:TrackerMetadata>).
Automatic matching means a reader who adds a series from a second source doesn't end up with two
library rows and no idea why. Worth remembering when our matching produces a wrong answer: the
alternative isn't "better matching," it's asking the reader.

Their link is also CloudKit-backed, so a link made on one device appears on another. Ours has no
sync story at all.

## Reverse image search, and the resolver underneath

Worth writing down because the image half is trivial and the URL half is the actual feature.
`ImageSearchView`, `SauceNao`, and `DSK.handleURL`:

1. **Identify the panel.** The reader picks an image; it's POSTed as multipart form data to
   `saucenao.com/search.php` with `output_type=2`, `numres=10`, and `db=37` - SauceNAO's MangaDex
   index, so the search is scoped to manga rather than the whole site. Each result carries a
   thumbnail, a similarity percentage, source title, part, author, artist, and `ext_urls`.
2. **Tapping a result opens a link picker**, one button per `ext_url`, labelled by hostname.
3. **The link goes back into the app, not into Safari.** `DSK.handleURL(for:)` runs first;
   `SFSafariViewController` is only the fallback when it returns false.
4. **Resolution asks every installed runner** - sources *and* trackers - in three steps: skip any
   runner that didn't declare `canHandleURL`; skip any whose `owningLinks` prefixes don't match
   (a cheap string test before any work); ask the survivors to parse it, each returning a
   `DeepLinkContext` or nil.
5. **Zero matches falls back to Safari, one navigates, several raise a picker** naming each runner
   - an aggregator and a mirror can both legitimately claim a domain.
6. **The context is one of three things** - a series to open, a reader context (opens straight to a
   chapter), or a source-specific link - so a URL can land mid-chapter, not just on a profile.

The point: reverse image search isn't an image feature. It's a thin third-party client bolted onto
a URL resolver that already existed for the app's URL scheme - `handleURL` is the same function
deep links use. Once an arbitrary web URL resolves to "this series on that source," the search
screen is roughly 130 lines.

Same shape as <doc:Aidoku>'s notification finding, from a different angle: the URL resolver is the
load-bearing piece, and several visible features are cheap once it exists. Ours is
<doc:Deeplinks>, still research-only. The runner-side contract there - an opt-in capability plus a
declared list of owned URL prefixes, checked before parsing - is worth copying directly; it's the
same opt-in-refinement shape as <doc:SourceProtocols>.

Two flaws worth recording, since both are the kind that don't show up in a feature list:

- **The SauceNAO API key is hardcoded in the public repo**, so every install shares one key and one
  quota - the free tier is roughly 6 searches per 30 seconds and 100 per day *per key*. There's no
  per-user key setting and no rate-limit handling in the client. At any real user count the feature
  is mostly broken, and the key is lift-able by anyone reading the repo. If this is ever built
  here, the key belongs in the reader's own settings, and the rate-limit response needs a real
  branch.
- It encodes JPEG data but labels the part `file.png` with `image/png`. Harmless because SauceNAO
  sniffs content, but wrong.

## What we have that Suwatte doesn't

- **Automatic multi-origin resolution** - see above.
- **Release prediction** - <doc:ReleasePrediction>.
- **Chapter gap detection** - `ReaderGapSheet` reports numbers missing across every source checked.
- **Tracker metadata supply** - <doc:TrackerMetadata>.
- **Per-origin scanlator and language priority.**
- **Recommendations.**
- **Adult-content gate/preference split** - <doc:AdultContent>. Theirs is a single
  `ContentSelectionType` on a filter.

## Cross-app pattern

Kept in one place rather than restated per page - see <doc:Mihon>'s closing section for the gaps
that recur across every reader scanned.
