# Tracker Candidates

Four services considered and rejected as a third tracker, before MangaBaka ended up shipping
instead: MangaUpdates, Kitsu, AniDB, Anime-Planet.

See <doc:aletheia/TrackerMangaBaka> for the one that shipped.

## The answer

None of the four ships. All four were rejected for the same root cause, not for data quality - two
of them (MangaUpdates, Kitsu) fit this app's contract *better* than MyAnimeList does on several
axes. **Every one of the four requires the user's raw password, a permanently-running hidden
browser, or both - not one offers a redirect-based login flow.** AniList and MyAnimeList turned out
to be close to the only manga-tracking services with a login flow a native app can drive without
handling the user's password directly.

| | has manga? | login flow | verdict |
|---|---|---|---|
| MangaUpdates | yes | password only, no expiry | no - best data case, still no |
| Kitsu | yes | password only, writes blocked by Cloudflare on the live host | no |
| AniDB | **no** | raw password, custom protocol | disqualified before auth even matters |
| Anime-Planet | yes | no API at all, scraped session token | no |

## Per-candidate summary

- **AniDB** doesn't track manga at all - not incomplete, no manga entities exist in their database,
  and a from-scratch manga database has been "planned" since roughly 2008. Every other reader
  surveyed has zero AniDB integration, for the same reason.
- **MangaUpdates** has the strongest data case of the four (exact status/id fit, alias-aware
  search, no server-side value rewriting) but has no OAuth of any kind - only a raw
  username/password login with a token of undocumented, apparently unbounded lifetime. Two
  additional hazards worth remembering if this is ever revisited: an unauthenticated read returns
  `200 {}` instead of an error (defeats a "did my token die" check), and writing a status update
  moves the entry out of the user's custom list unless the existing list id is explicitly
  preserved.
- **Kitsu** fits this app's existing data model more cleanly than MyAnimeList does, but its OAuth
  only supports the password grant (confirmed in their own server source), and writes are blocked
  by a Cloudflare challenge on the current live host. Its docs, mobile apps, and commit cadence
  have all been fading since 2022 - a stewardship risk on top of the technical blockers.
- **Anime-Planet** has no public API of any kind and a site-wide Cloudflare challenge blocking
  every path, including read-only pages. Sign-in is a scraped session token from a rendered page,
  the identity key is a slug rather than a stable id, and their terms of service explicitly
  prohibit automated access.

## Further candidates, not investigated

Surfaced while surveying what other readers integrate; none of these were probed, only noted.

| Service | Why it might matter |
|---|---|
| **Bangumi** (bgm.tv) | Chinese, reported to have a real browser-redirect OAuth flow. Strong CN/JP catalogue. |
| **Shikimori** | Russian, reported OAuth, the most widely integrated of these by other readers. |
| **Kavita / Komga / Suwayomi** | Not public services - self-hosted servers a reader runs themselves. A different feature ("sync to my own server") than what `Tracker` models, would need its own design pass rather than a new case. |

Bangumi and Shikimori are the only two here reported to have the login flow this app needs - worth
probing first if a fourth tracker is ever wanted, per the rule above. Both are regional, so the
case for either is a userbase question, not a technical one.

## Reusable findings

Worth checking for on any future tracker candidate, since they cost real investigation time here:

- **Check for a redirect-based login flow before evaluating anything else.** All four candidates
  were fully evaluated on data model, ids, status mapping, and coverage before auth turned out to
  be the deciding factor for every one of them. Auth is cheap to check and expensive to discover
  last.
- **An unauthenticated read that returns `200` instead of an error is a distinct failure class.**
  Both MangaUpdates and Kitsu do this. It defeats the "is remote data actually current" guard this
  app uses before pushing local progress over remote - a dead token gets misread as "no entry
  exists" rather than "can't tell," and progress silently regresses.
- **A search that never returns empty is worse than one that errors.** MyAnimeList returns
  confident, unrelated results for a title it doesn't have rather than an empty list - a real trap
  for any auto-matching that trusts the top result.
