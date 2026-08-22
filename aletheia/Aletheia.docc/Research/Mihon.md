# Mihon

Feature scan of Mihon - the continuation of Tachiyomi, Android only, Kotlin + Compose, Apache-2.0.
The oldest and by far the largest project in this category.

> Scanned 2026-08-22, against `main` at v0.20.4 (23k stars, pushed the same day). Read from the
> source tree and the official docs. Source: `github.com/mihonapp/mihon`. Docs: `mihon.app/docs`.

The **Us** column was checked against this codebase. Rows marked `?` weren't checked. Android-only
mechanisms are marked `—` where iOS gives us no equivalent to build.

## Legend

| | meaning |
|---|---|
| ✓ | built here |
| ~ | partly built, or built to a narrower scope |
| ✗ | not built - a real gap |
| — | deliberate divergence, or not expressible on iOS |

## Verdict

Mihon is the reference implementation of this whole category, and most of what the iOS readers do
is a re-derivation of a decision made here first. It is also the only one of the three with a
serious answer to the two problems we've been calling ours: **it predicts a series' release cadence
and uses it to decide when to poll**, and **it detects a duplicate when you add a series that's
already in the library from another source**.

The gap list against it is longer than for Aidoku or Suwatte, but most of it is depth rather than
kind - a dozen settings on a feature we have one setting for. Three items are genuinely absent
here and worth acting on: **download-ahead**, **cadence-gated refresh** (we compute cadence already
and only display it), and **local source**.

Its biggest structural advantage over both iOS readers is that Android lets an app install code at
runtime. Half of what follows flows from that, and none of it is available to us.

## What the takedown changed

Kakao Entertainment sent a cease and desist on 2 January 2024; Tachiyomi removed its bundled
extensions on 9 January and announced the end of development on 13 January. Mihon is the
continuation, from the same contributors.

The architectural consequence is the interesting part, because it's a design response to legal
pressure rather than to a product need: **there is no official extension repository any more.** A
reader adds repository URLs themselves, and the app carries an explicit trust step -
`ExtensionStoreRepository`, plus a `TrustExtensionRepositoryMigration` for readers upgrading from
the bundled era. The app ships knowing nothing about where content comes from.

That's the far end of the axis we sit at the other end of: they ship no sources and can't be held
responsible for any; we ship nine and are responsible for all of them. Worth stating plainly
somewhere in our own docs, because it's the argument *for* our model, not just a description of it.

## Sources and Content

| Feature | What it does | Us | Notes |
|---|---|---|---|
| APK extensions | Sources are installable Android packages | — | Not possible on iOS. This is why both iOS readers reinvented it as WASM (<doc:Aidoku>) or JS (<doc:Suwatte>) |
| User-added extension repos | Reader supplies repository URLs; app trusts none by default | — | See above |
| NSFW source toggle | Hides sources marked adult at the source level | ~ | Ours is a gate/preference split at query level - <doc:AdultContent>. Theirs is coarser but also covers hiding the source itself |
| Local source | A folder of archives read as a first-class source, with `ComicInfo.xml`, `cover.jpg`, `details.json` | ✗ | Third reader in a row with this. Ours is decided-but-unbuilt - <doc:ChapterStorage> |
| Source migration | Move entries off a dead source, choosing what to carry | ✓ | `SourceMigrationScreen`, `DisconnectedSourceMigrationScreen` |
| Duplicate detection on add | Adding a series already in the library from another source raises a dialog instead of creating a second entry | ✓ | Stronger here: we resolve it automatically into one series with two origins - <doc:Details>. Theirs asks |
| Global search | One query fanned across every enabled source | ✓ | <doc:SourceSearch> |
| Hide in-library items while browsing | Browse results dim or hide what you already have | ? | Unverified |

## Library

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Categories | User-defined groups | ✓ | Collections |
| Default category | Where a newly added series lands | ? | Unverified |
| Per-category display settings | Each category remembers its own layout and sort | ✗ | `categorized_display_settings` |
| Per-category update exclusion | A category can be skipped by the global refresh | ~ | We have skip rules; whether they're category-shaped is unverified |
| Filters and sorts | | ✓ | Ours is wider - tri-state include/exclude across seven axes |
| Display modes | Grid, comfortable grid, list | ✗ | Grid only |
| Bulk selection | Multi-select with mark-read, download, category, delete | ✗ | Third reader in a row with this |
| Download badges | Downloaded-chapter count on the cover | ~ | We badge unread only - <doc:Design> allows one overlay per artwork |
| Missing-chapter indicators | The chapter list shows how many numbers are absent between two rows | ~ | We detect gaps and surface them in the reader (`ReaderGapSheet`); not in the chapter list |
| Chapter swipe actions | Configurable swipe-left/right on a chapter row | ? | Unverified |
| Mark duplicate chapter read | Reading a chapter marks the same number from other scanlators read | ✗ | Separate settings for existing and new duplicates |
| Update interval and restrictions | Refresh every N hours, only on Wi-Fi, only while charging | — | iOS decides when a `BGTask` runs; we can request power/network conditions but not schedule. Our copy says so explicitly |
| Smart update | Skips entries unlikely to have anything new | ~ | See FetchInterval below |
| Update only during release period | Skips a series outside its predicted release window | ✗ | We compute the cadence and only display it. See below |
| Update only completely-read entries | Doesn't refresh what you're behind on | ✗ | |
| Refresh metadata on update | Re-pulls covers and details during the library refresh | ✓ | ``Compositor/Metadata`` on its own slower schedule |

## Reader

Mihon's reader settings are the largest surface in the category. Ours are closest to Suwatte's.

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Modes | Paged RTL, paged LTR, paged vertical, long strip, long strip with gaps | ~ | We have four; long-strip-with-gaps is the missing one, same row as <doc:Aidoku>'s |
| Per-series mode override | A series remembers its own reading mode | ✓ | Orientation resolves per series, including from tags |
| Scale type | Fit screen, stretch, fit width, fit height, original, smart fit | ? | Unverified |
| Zoom start position | Where a page opens when zoomed - auto, left, right, centre | ✗ | |
| Auto-zoom and pan wide images | | ✗ | |
| Double-tap animation speed | | ✗ | |
| Crop borders | Trims page margins | ✗ | Suwatte calls it crop whitespace |
| Split wide pages | Splits a spread | ✗ | |
| Rotate wide pages | Rotates rather than splitting | ✗ | |
| Long strip side padding | Horizontal padding in continuous mode | ✓ | `horizontalPadding` |
| Background colour | Black, grey, white, automatic | ~ | Ours is dim plus warmth, not a colour choice |
| Fullscreen, cutout display, screen timeout | | ~ | Keep-screen-on exists; the rest are Android display concerns |
| Rotation lock | Six orientation modes | ✗ | |
| Page number indicator | | ✓ | |
| Tap zones | Default, L-shaped, Kindle, edge, right/left, disabled | ~ | Three of nine layouts shipped - <doc:ReaderBacklog> |
| Invert tap zones | Horizontal, vertical, both, none | ✓ | |
| Volume key navigation | | — | No equivalent on iOS |
| E-ink flash on page change | Reduces ghosting | — | |
| Chapter transitions | Interstitial between chapters | ✓ | `ReaderSeparator` |
| Skip read / filtered / duplicate chapters | Navigation skips chapters matching a rule | ~ | We rank and pick a best chapter per number; skipping as a navigation setting isn't exposed |
| Long-tap page actions | Set as cover, copy, share, save | ~ | We share; set-as-cover and save aren't wired |

## Trackers

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Services | MyAnimeList, AniList, Kitsu, MangaUpdates, Shikimori, Bangumi | ~ | Six against our three. Note Kitsu and MangaUpdates ship here - <doc:TrackerCandidates> rejected both on auth grounds, which holds for iOS but evidently not for them |
| Enhanced trackers | Komga, Kavita, Suwayomi track automatically with no separate login, because the source *is* the tracker | ✗ | Elegant: a self-hosted server already knows your progress. Depends on media-server support |
| Private tracking | Marks the remote entry private where the service supports it (AniList, Kitsu) | ✗ | Small, and a real privacy feature |
| Sync direction | One-way, Mihon → tracker | ✓ | Ours is two-way; theirs is deliberately not |
| Offline queue | Progress recorded offline syncs when back online | ? | Unverified here |
| Library restore from tracker | | ✗ | <doc:TrackerRestore> - still ours alone across all three apps |
| Tracker metadata supply | | ✗ | <doc:TrackerMetadata> - also still ours alone |

## Downloads

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Download ahead | Auto-downloads the next N chapters when you reach the 2nd/3rd/4th/5th-to-last downloaded one | ✗ | The single best small feature found in this scan. Removes "I forgot to download before the flight" as a category of problem |
| Auto-download while reading | | ✗ | Same family |
| Download new chapters | Auto-download on library refresh, restricted by category and unread-only | ✗ | |
| Concurrency settings | Concurrent pages and concurrent sources, both reader-set | ~ | We gate per host automatically; it isn't a setting |
| Remove after read | Delete a chapter once read, once marked read, or never | ✗ | With an exclude-categories rule and a keep-bookmarked rule |
| Save chapter as CBZ | Downloads stored as CBZ rather than loose pages | ✗ | We chose the directory as the store and CBZ as the export boundary - <doc:ChapterStorage> - and built neither export nor this |
| Split tall images | Splits long webtoon strips at download time | ✗ | Storage/decode optimisation, not a reader setting |
| Download-only mode | App-wide toggle: only show what's on disk | ~ | Downloaded chapters stay reachable when a source goes away - <doc:OfflineAvailability> - but there's no global toggle |
| Storage breakdown | | ✓ | `DownloadStorageSection` |
| Background downloading | Continues with the app closed | ✗ | Same gap as <doc:Aidoku>; ours are foreground |

## Data, Security, Privacy

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Backup format | Protobuf, gzipped | ✓ | Same choice we made independently - <doc:LibraryBackup> |
| Backup contents | Library, categories, history, tracking, **app and source preferences**, **extension repo list** | ~ | Ours carries library state only. Restoring settings is the piece worth stealing |
| Automatic backups | On a schedule, with a retained-copies limit | ✓ | `AutoBackupScreen`, `RecentBackupsScreen` |
| Cloud sync | | ✗ | Not in Mihon either - it's a fork feature. Neither of us has it |
| App lock | Biometric or device credential, always / when idle / never | ✗ | Nothing here. `LocalAuthentication` is unused |
| Secure screen | Blocks screenshots and hides the app in the switcher | ✗ | |
| Hide notification content | Keeps series titles out of the lock screen | ✗ | Relevant the moment we add per-series notifications |
| Incognito mode | Reading records no history; toggleable per source | ✗ | Third reader in a row. Theirs is the most granular - per source, not app-wide |
| DNS over HTTPS | Optional DoH resolver | ✗ | Circumvents basic DNS-level blocking |

## FetchInterval: cadence used for scheduling, not display

`FetchInterval` (`domain/.../manga/interactor/FetchInterval.kt`) is the direct analogue of our
``DetailsComposer/Cadence`` (<doc:ReleasePrediction>), and the comparison is instructive because
the algorithms are close and the *purposes* aren't.

How theirs works:

1. **Window by history size.** The last 3 distinct dates for a series with 8 or fewer chapters, the
   last 10 otherwise.
2. **Source dates first, client dates as fallback.** It prefers the source's stated upload dates;
   with fewer than 3 usable ones it falls back to the dates *this device first saw* each chapter.
   That fallback is what makes the feature work on sources that publish no dates at all - a class
   of source we currently just give up on.
3. **Median gap, not mean.** Gaps between consecutive dates, sorted, middle element. One hiatus
   doesn't drag the estimate.
4. **Defaults to 7 days**, clamps the result to 1-28 days.
5. **Backs off when wrong.** If more than about 10 predicted cycles have passed with nothing new,
   the interval doubles, repeatedly. A dead series stops being polled on its old rhythm.
6. **The reader can pin it.** A negative stored interval means manually set, and skips calculation
   entirely.
7. **The output is `nextUpdate`, a timestamp**, checked against a ±1-day grace window.

Ours collapses chapters to release events first (earliest `publishedDate` per number, so a chapter
mirrored across origins counts once) - a step theirs doesn't need, because it has no multi-origin
model. That collapse is genuinely better input.

**The difference that matters is what the number is for.** Ours renders a predicted date to the
reader. Theirs decides whether to make a network request at all: `pref_update_only_in_release_period`
skips any series outside its window during a global refresh. On a 400-series library that's a large
reduction in requests, which is also anti-bot behaviour - their own docs warn that bulk refreshing
trips source rate limits.

We already compute the input for this and throw the scheduling use away. Wiring cadence into
``Compositor/Refresh`` as a skip rule is a small change against work already done, and it would
make our refresh both faster and less likely to get a source angry at us. The backoff in step 5 is
the part to copy carefully - without it, a finished series gets polled forever on its old weekly
rhythm.

## What we have that Mihon doesn't

Shorter than for the other two, which is the honest result:

- **Multi-origin series as the default model.** Mihon detects a duplicate and asks; we resolve it
  into one series with several origins, a cover pool, and preferred titles - <doc:Details>.
- **Tracker-driven library restore** - <doc:TrackerRestore>.
- **Tracker metadata supply** - <doc:TrackerMetadata>.
- **Predicted release date shown to the reader.** They compute cadence but never display it.
- **Recommendations.**
- **Per-origin scanlator and language priority**, as stored preferences rather than a filter.

## Cross-app pattern

Kept here rather than restated per page. Four readers scanned: <doc:Aidoku>, <doc:Suwatte>, this
one, and <doc:Kotatsu>. The last is the control group - built outside the Tachiyomi lineage, so
where it agrees the finding isn't just one family's habit.

Gaps present in every reader scanned, in rough order of value for effort:

1. **A URL scheme.** Still the cheapest unlock - tappable notifications, share-sheet import, and
   Suwatte's reverse image search all sit behind it. <doc:Deeplinks>.
2. **Local archive reading.** Four for four. We decided the store shape and stopped -
   <doc:ChapterStorage>.
3. **Incognito mode.** Four for four.
4. **Library multi-select.** Absent here entirely.
5. **Bookmarks.** A page you can return to; in Suwatte and Kotatsu.
6. **App lock.** Biometric or passcode; in Mihon and Kotatsu.
7. **Media-server sources** (Komga, Kavita). Also unlocks Mihon's enhanced trackers.
8. **Download-ahead.** Only Mihon has it, and it's the best small feature found.

Nobody else has: automatic multi-origin resolution, tracker-driven restore (<doc:TrackerRestore>),
or tracker metadata supply (<doc:TrackerMetadata>).

Two things we thought were ours turned out not to be. Mihon predicts release cadence but spends it
on scheduling rather than display. Kotatsu ships first-party recommendations, bundled sources, and
working cross-device sync - the one project that made our source-model bet independently.
