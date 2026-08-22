# Aidoku

Feature scan of Aidoku - a free, open-source iOS/iPadOS/macOS reader, GPLv3, UIKit + Core Data, by
skitty.

> Scanned 2026-08-22, against Aidoku v0.8.4. Read from its README, release notes, help guides, and
> source. Source: `github.com/Aidoku/Aidoku`. Release notes: `aidoku.app/release-notes`.

Every row's **Us** column was checked against this codebase, not against our own docs - several of
our pages have drifted (see <doc:Research>). Where a row is unverified it says so.

## Legend

| | meaning |
|---|---|
| ✓ | built here |
| ~ | partly built, or built to a narrower scope |
| ✗ | not built - a real gap |
| — | deliberate divergence, not a gap |

## Verdict

Aidoku's reach is wider; ours is deeper per series. It reads more kinds of content than we do
(local archives, self-hosted servers, novels) from more sites than we ever will (user-installed
WASM plugins), and it has a longer tail of small reader comforts. We do more with one series once
it's in the library - multi-origin resolution, release-date prediction, tracker-driven library
restore, per-origin scanlator priority - none of which Aidoku attempts.

Three gaps are worth acting on, in this order: **notifications that name the series and open it**
(cheap, blocked on a URL scheme we don't have), **local file reading** (a whole intake category,
and <doc:ChapterStorage> already decided the store shape), and **media-server sources** (the only
way someone's existing self-hosted library reaches us at all).

## Sources and Content

| Feature | What it does | Us | Notes |
|---|---|---|---|
| WASM `.aix` source plugins | Sources are WebAssembly bundles loaded at runtime | — | We compile 9 native `SourceService`s in. Opposite bet, made knowingly - see <doc:BuildingASource> |
| Third-party source lists | User adds a repo URL, installs sources from it in-app | — | Follows from the above. Aidoku disclaims these as unsupported |
| Built-in sources | Sources shipped with the app | ✓ | All of ours are built-in |
| Cloudflare handling | Gets through interstitials | ✓ | ``AuthenticatingSource`` + WebKit cookie capture, <doc:SourceAuth> |
| Local file reading | Open CBZ/ZIP archives from the device | ✗ | <doc:ChapterStorage> already picked CBZ as the import boundary; nothing reads one |
| ComicInfo.xml parsing | Pulls title/series/number metadata out of an archive | ✗ | Depends on the row above |
| Media server as source | Komga and Kavita browsed like any other source | ✗ | Whole category missing |
| Server mirrors | Several base URLs per server, failover between them | ✗ | Depends on the row above |
| Source pinning | Pin sources to the top of the browse list | ✓ | `source.pinned` |
| Source migration | Move a series from a dead source to a live one | ✓ | `SourceMigrationScreen`, `DisconnectedSourceMigrationScreen`, `OriginMigrationScreen` |
| Migration preview | Preview the target series and choose which data to copy before committing | ~ | We migrate; whether we let the reader pick fields is unverified |
| Incognito mode | Reading records nothing, with a persistent banner saying so | ✗ | |

## Library

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Categories | User-defined groups | ✓ | Collections (`CollectionRecord`, `SeriesCollectionRecord`) |
| Uncategorised pseudo-category | Built-in bucket for series in no category | ✓ | Reserved as a name in migration v1.0.4 |
| Filters | Narrow the library | ✓ | Ours is wider - tri-state include/exclude across status, publication, classification, read state, tags, sources, and tracker-linked-ness |
| Persistent filters | Filter survives leaving the tab | ✓ | `LibraryFilter` is stored |
| Filter groups per category | A saved filter configuration attached to a category | ✗ | |
| List mode | Row layout as an alternative to the grid | ✗ | Grid only |
| Multi-select | Bulk actions on several series | ✗ | Aidoku activates it with a two-finger drag |
| Scanlator affinity | Prefer chapters from the scanlator you're already reading | ✓ | Stronger here - `OriginScanlatorPriorityRecord` is an explicit stored priority per origin, not an inferred preference |
| Resume-last-opened setting | Continue from the last chapter opened rather than the next unread | ✗ | We always target next-unread |
| Update-on-Wi-Fi-only | Skips refresh off Wi-Fi | ? | Unverified |

## Reader

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Reading modes | Continuous strip, single page, LTR, RTL | ✓ | Four modes in ``ReaderConfiguration`` |
| Continuous with gaps | Webtoon strip with spacing between pages | ✗ | |
| Double-page spreads | Two pages side by side, with a page-offset control | ✗ | |
| Wide-page splitting | Detects a double-page image and splits it | ✗ | |
| Tap zones | Configurable screen regions for page turns | ✓ | Tap-zone layout is a stored preference |
| Auto-scroll / auto-advance | Hands-free progression | ✓ | Rate for continuous, dwell interval for paged - `AutoScroller`, `AutoAdvancer` |
| Live Text | Select, copy, and translate text on a page image | ✗ | VisionKit. Cheap, high visibility |
| ML upscaling | Enlarges low-resolution pages | ✗ | Experimental in Aidoku. <doc:Metal> is the standard if this is ever built |
| Auto background colour | Picks reader background from page content | ✗ | We offer manual dim, warmth, and chrome tint |
| Hide bars on swipe | Chrome auto-dismisses after a page turn | ~ | We hide chrome; not tied to the page turn |
| Disable double-tap zoom | Trades zoom for faster tap-zone response | ✗ | |
| Text/novel reader | Reads prose, with paging and font settings | ✗ | Out of scope for now |
| Apple Pencil squeeze | Squeeze to turn pages or open the chapter list | ✗ | |
| Hardware keyboard | Key bindings for navigation | ✗ | |
| Position keeping | Holds your place when content above resizes | ✓ | Far more rigorous here - see <doc:ReaderGeometry> |

## Trackers

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Services | | ~ | Aidoku: AniList, MyAnimeList, Shikimori, Bangumi, MangaBaka, Komga, Kavita. Us: AniList, MyAnimeList, MangaBaka |
| Shikimori, Bangumi | Two services we never evaluated | ✗ | <doc:TrackerCandidates> claims to have surveyed the field and misses both. That claim needs fixing |
| Server-as-tracker | A Komga/Kavita server doubles as the progress store | ✗ | Depends on media-server support |
| Chapter number offset | Per-link correction when our numbering and the tracker's disagree | ✗ | Direct answer to the chapter-number problem <doc:Trackers> documents and leaves open |
| Relogin without unlinking | Re-auth a broken tracker keeping every existing link | ? | Unverified |
| Show unavailable links | Surfaces a link whose tracker was removed rather than hiding it | ? | Unverified |
| Prompt to sync on newer remote | Offers to pull when the tracker is ahead of local progress | ~ | We sync both ways; whether we prompt on this specific case is unverified |
| Web login token capture | Signs in by extracting a localStorage key from a web view | ~ | We use it for source auth, not tracker auth |
| Metadata supply from trackers | Tracker fills synopsis, classification, publication | ✓ | <doc:TrackerMetadata> - Aidoku has no equivalent |
| Library restore from a tracker | Rebuilds a library from the tracker's list | ✓ | <doc:TrackerRestore> - Aidoku has no equivalent |

## Downloads and Storage

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Download queue | Queue with live progress | ✓ | ``Compositor/Downloads``, `DownloadQueueScreen` |
| Background downloading | Keeps downloading with the app closed | ✗ | We register `BGTaskScheduler` for refresh and metadata only - downloads are foreground |
| Parallel download toggle | User-controllable concurrency, for rate-limited sources | ~ | We gate concurrency per host automatically; it isn't exposed as a setting |
| Failed page retry | Re-fetches pages that failed rather than leaving holes | ✗ | Aidoku added this in 0.8.4 for rate-limited sources |
| Download compression | Shrinks stored pages | ✗ | |
| AVIF support | Reads AVIF pages and local files | ? | Unverified |
| Storage breakdown | Shows what downloads cost, by series | ✓ | `DownloadStorageSection` |
| CBZ export | Exports a downloaded chapter as an archive | ✗ | Decided in <doc:ChapterStorage>, not built |

## Backup and Sync

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Backup export | Whole library to a portable file | ✓ | Versioned protobuf envelope, <doc:LibraryBackup> |
| Scheduled automatic backups | Backs up on a schedule without being asked | ✓ | `AutoBackupScreen`, `RecentBackupsScreen` |
| Import from Files in-app | Restore by picking a file inside the app | ✓ | `BackupImportScreen` |
| iCloud sync | Library state syncs across devices | ✗ | Nothing CloudKit-shaped exists here |
| Import from another reader | Reads a Tachiyomi/Mihon export | ✗ | `OtherReaderImportScreen` is a "Coming Soon" placeholder |

## Notifications and Navigation

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Refresh-result notification | Tells you what a background refresh found | ✓ | `Notifier.refreshed` already reports counts across series |
| Per-series new-chapter notification | Names the series and its new-chapter count | ✗ | See below |
| Filter-aware counts | Only counts chapters the reader's language and scanlator filters would show | ✗ | See below |
| Batch collapse | Over N series collapses to one summary notification | ✗ | Aidoku's threshold is 3 |
| Tappable notification | Opens the series it's about | ✗ | Blocked on a URL scheme - <doc:Deeplinks> is research-only |
| URL scheme | `aidoku://source/manga` opens a series; deep link into the reader | ✗ | Same blocker |

### How Aidoku's new-chapter notification works

Worth writing down because it costs them almost nothing - it's a byproduct of refresh, not a
subsystem. `MangaManager.refreshLibrary()`, plus `NotificationManager`:

1. **The write produces the signal.** `setChapters` returns only the rows that were actually new.
   There's no separate diff pass.
2. **New is filtered down to notifiable.** Each new chapter is tested against that series' own
   language and scanlator filters; a chapter the reader would never see is stored but not counted.
   The number in the notification matches what opening the series would show.
3. **One summary per series** - identifier, title, notifiable count - accumulated across the run.
4. **Only when nobody's watching.** Guarded on `isBackground && settingEnabled`, so a refresh the
   reader triggered with the app open notifies nothing.
5. **Sent once at the end, capped.** More than three series collapses into a single "N series have
   new chapters"; three or fewer get one notification each, titled with the series name.
6. **The notification is a deep link.** It carries `sourceId`/`mangaId` in `userInfo`; the tap
   handler builds `aidoku://<source>/<manga>` and hands it to the same URL handler everything else
   uses. They got tappability for free because the scheme already existed.
7. **Permission is asked at the switch.** Flipping the setting on requests authorisation; a denial
   flips the setting back off, so it never sits enabled and silently dead.

Ours differs at 2, 5, 6, and 7. We ask provisionally at launch (<doc:BackgroundActivity>) and
promote later, which is quieter and deliberate. The rest is reachable except 6, which needs the
URL scheme first.

## Discovery

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Recent searches | Remembers query text | ✓ | `RecentSearches`, text only |
| Saved searches | Stores query text *and* its filter configuration | ✗ | |
| Tag/genre filter search | Search within a source's filter options | ~ | <doc:HighCardinalityFilters> covers the problem; scope of what shipped is unverified |
| Missing source indicator | Warns when a source list no longer carries an installed source | ✓ | `DisconnectedSourceMigrationScreen` covers the equivalent case |
| Recommendations | Suggests series | ✓ | Aidoku has none, by policy - and so does our Home (<doc:HomeScreen>); ours lives in Settings |
| Reading statistics | Reading time, heatmap, per-day breakdown | ✓ | Rough parity. Aidoku calls it Insights; ours is the Activity tab over `reading_event`/`reading_session` |

## What we have that Aidoku doesn't

- **Multi-origin series.** One series carried by several sources at once, with matching,
  disambiguation, a cover pool, and a preferred title - <doc:Details>. Aidoku's model is one
  source per entry; migration is how it moves between them.
- **Release prediction.** Next-chapter forecasting from release history - <doc:ReleasePrediction>.
- **Tracker Restore.** Rebuilding a library from a tracker account - <doc:TrackerRestore>.
- **Tracker metadata supply** - <doc:TrackerMetadata>.
- **Per-origin scanlator priority**, stored rather than inferred.
- **Reader anchor compensation** under content resize - <doc:ReaderGeometry>.

## Evidence quality

- Version *order* on Aidoku's GitHub releases page is reliable; the dates there contradict the
  dates on `aidoku.app/release-notes` for the same versions. Trust the site.
- Rows marked `?` were not checked in our code. They're small; resolve them the next time the
  surrounding subsystem is touched rather than in a sweep.
- The notification section is read from source, so it holds until Aidoku changes it. Everything
  else about Aidoku is read from release notes and may lag its actual behaviour.
