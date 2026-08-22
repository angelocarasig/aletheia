# Kotatsu

Feature scan of Kotatsu - an Android reader, Kotlin, GPL-3.0. The only large project in this scan
outside the Tachiyomi lineage, and the only one that bundles its sources the way we do.

> Scanned 2026-08-22, against the `devel` branch. Archived 2025-11-04; 8.8k stars. Read from the
> source tree and README. Source: `github.com/KotatsuApp/Kotatsu`.

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

Kotatsu is the closest thing to an independent replication of our own bet, and it mostly comes out
in our favour. It compiles roughly 1200 sources into the app rather than loading them at runtime -
the same choice we made, reached without reference to Tachiyomi's plugin model - and on top of that
it independently arrived at **bundled recommendations**, **cross-device sync**, and
**automatic source repair**. Three of the four things we thought were unusual about us turn out to
be things the one other bundled-source project also built.

The single feature worth taking wholesale is **AutoFix**: detect that a series' source has actually
stopped working, search every other source for a replacement, verify the replacement really serves
pages, and migrate - unattended. We have all three pieces (`SourcePing`, matching, migration
screens) wired to a manual flow.

## Why it shut down

The README's own notice: threatened action from Kakao Entertainment, plus Google's announced
sideloading restrictions. Development ended and the repository was archived on 2025-11-04.

That's Kakao's second kill in this category after Tachiyomi (<doc:Mihon>), and the second time the
response was structural rather than cosmetic. It's also the first time the *distribution channel*
appears as the threat rather than the content: a sideloading policy squeezes an Android app in a
way that has no analogue for us, since we were never going to be sideloaded.

Worth recording plainly: **bundling sources did not protect Kotatsu.** Our model reduces the
"anyone can publish a source" exposure, not the "you ship a client that reads a rights-holder's
catalogue" exposure. Those are different risks and only one of them is addressed by how sources
ship.

## Sources

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Bundled parsers | ~1200 sources compiled into the app from a separate `kotatsu-parsers` library | ✓ | Same model, two orders of magnitude more sources. Theirs are thin uniform parsers; ours are per-capability lane choices - <doc:BuildingASource> |
| Source enable/disable | Reader picks which of the bundled sources are active | ✓ | |
| Source priority by locale | Alternative search ranks sources by matching locale, then device locale | ~ | We have per-series language priority; not used to rank *sources* during a search fan-out |
| **Alternatives** | On demand, searches every source by title and streams back matches, with details fetched per hit | ~ | We do this at add-time as matching (<doc:Details>); theirs is an explicit user-facing "find this elsewhere" screen |
| **AutoFix** | Detects a broken source and migrates the series to a working one, unattended | ✗ | See below |
| Local CBZ | Third-party archives readable alongside online sources | ✗ | Fourth reader in a row - <doc:ChapterStorage> |

## AutoFix

`AutoFixUseCase` is the piece worth copying. It runs four steps:

1. **Health check, not a ping.** A series is healthy if fetching its details yields a first
   chapter, whose pages resolve, whose first page URL parses as a URL. That's an end-to-end probe
   through the whole content path - a source that answers but can't actually serve a page fails it.
   Our `SourcePing` is a much weaker signal.
2. **Search enabled sources first, then disabled ones.** Disabled sources are still valid rescue
   targets, which is a nice detail - a reader who turned a source off didn't say it was broken.
3. **Keep only healthy candidates, pick the one with the most chapters.** Not the best title match
   - the most complete copy.
4. **Wait for at least 4 candidates or 40 seconds**, whichever comes first, then migrate.

Everything there maps onto something we already have. `DisconnectedSourceMigrationScreen` is the
manual version of the same flow, and our matching is better input than a bare title search. What's
missing is the trigger, the health definition, and the willingness to act without asking.

The step to copy carefully is 1. "Is this source alive" is currently a question we answer
shallowly, and every downstream decision - migration prompts, offline availability
(<doc:OfflineAvailability>), refresh skipping - is only as good as that answer.

## Library and Discovery

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Favourites with categories | User-defined groups | ✓ | Collections |
| Filters | Genre, state, and more | ✓ | Ours is wider |
| History | Reading history as a first-class list | ~ | `HistoryScreen` is still a placeholder; the event log behind it exists - <doc:ActivityHistory> |
| Bookmarks | Bookmark a page and return to it | ✗ | Also in <doc:Suwatte>. Nothing here |
| Incognito | Reading records no history | ✗ | Fourth reader in a row |
| **Suggestions** | A built-in recommender over the library, with quick filters and a **tag blacklist** | ✓ | We have <doc:Recommendations>. The blacklist is the part we lack - a reader who never wants a genre suggested has no way to say so |
| Updates feed | New chapters across the library | ✓ | `UpdatesScreen` |
| New chapter notifications | | ~ | Ours reports refresh results without naming the series - see <doc:Aidoku> for the mechanism |
| Home screen widget | Library/updates on the launcher | — | The iOS equivalent is a WidgetKit widget; not built, and not the same thing |
| **Stats** | Per-series and overall reading stats with bar and pie charts | ✓ | Rough parity with our Activity tab |

## Reader

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Standard and webtoon modes | | ✓ | Four modes |
| Gesture support | Configurable reading gestures | ✓ | Tap zones |
| Tablet and desktop layouts | One app, three form factors | ~ | We build for iPhone; iPad is untested territory |
| Material You theming | Colour follows the system palette | — | Ours follows <doc:Design>'s monochrome-chrome rule deliberately |

Kotatsu's reader is the least configurable of the four scanned - closer to ours than to Mihon's or
Suwatte's. An independent project landing on a *small* reader-settings surface is mild evidence
that the huge ones are accretion rather than demand.

## Trackers and Sync

| Feature | What it does | Us | Notes |
|---|---|---|---|
| Services | Shikimori, AniList, MyAnimeList, Kitsu ("scrobbling") | ~ | Four against our three. Shikimori and Kitsu again - <doc:TrackerCandidates> has a hole for the first and a rejection for the second |
| **Sync** | App data syncs across devices through a Kotatsu account, against a self-hostable sync server | ✗ | The only project in the scan with working first-party sync. Mihon has none; Suwatte's is partial and crashes |
| Library restore from a tracker | | ✗ | <doc:TrackerRestore> - still ours alone across four apps |
| Tracker metadata supply | | ✗ | <doc:TrackerMetadata> - also still ours alone |

## Security and Data

| Feature | What it does | Us | Notes |
|---|---|---|---|
| App lock | Password or fingerprint | ✗ | Also in <doc:Mihon>. `LocalAuthentication` is unused here |
| Backups | Export and restore | ✓ | <doc:LibraryBackup> |
| Downloads | Download for offline reading | ✓ | |

## What this scan changes

Kotatsu is the control group. Everything the Tachiyomi lineage shares could be convergent
evolution inside one family; Kotatsu was built separately and still landed on incognito, app lock,
bookmarks, local archives, sync, recommendations, and stats.

Where it agrees with Mihon and we don't, the case for building it is stronger than one app's
opinion. That's **incognito**, **bookmarks**, **local archives**, and **app lock**.

Where it agrees with *us* against the Tachiyomi lineage - bundled sources, a small reader-settings
surface, first-party recommendations - those are our choices with a second data point behind them.

And it's the only project of the four whose core loop is measurably ahead of ours in one place:
knowing whether a source still works, and doing something about it without asking.
