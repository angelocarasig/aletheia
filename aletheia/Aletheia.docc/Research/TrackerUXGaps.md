# Tracker UX Gaps

Known rough edges in the tracker linking/sync flow, surfaced by a UI review panel and spot-checked
against code during this catalog's migration - not a complete or re-verified list. Treat every item
below as "reported, not necessarily still true" and check the code before acting on one.

## Confirmed still open

- **No per-origin chapter numbering offset.** Progress pushed to a tracker is the max chapter
  number read across every origin, but two origins for the same series can number differently (a
  season reset, a re-release). There's no per-origin correction for this - a `chapterOffset`
  concept was designed but never given a column or a writer.
- **No library filter grouping by tracker.** Library filtering has no "linked to AniList" /
  "linked to MyAnimeList" / "untracked" grouping, so finding everything linked to one service
  means opening each series individually.
- **No library-wide view of drift.** There's no single place that says "12 titles are ahead on
  AniList" - checking whether a link has fallen behind means opening that series' Details screen.

## Resolved since this was written

- **Bulk-importing an existing tracker account's list** was the single largest gap found (opening
  the feature with an existing 400-entry account meant 400 manual searches) - this shipped later
  as the tracker-restore feature (<doc:aletheia/TrackerRestore>): pull the whole list, auto-match,
  review what didn't match.

## Smaller reported issues, not re-verified

- Status adoption when linking two trackers in one sitting picks whichever was tapped most
  recently rather than the more advanced status (e.g. linking a "Reading" account after a
  "Planning" one discards the more accurate state).
- Score display format is captured once at sign-in and never refreshed - changing it on the
  tracker's own site would silently mis-render every score in the app.
- A missing (not just expired) keychain credential isn't treated the same as a dead one - a
  restored database with no matching keychain entry can leave sync rows pending forever with
  nothing surfaced anywhere.
- MyAnimeList's write response is trusted as proof the write landed without an independent re-read
  - worth a live check given MAL is documented elsewhere as capable of returning `200` for a body
  it silently ignored.

## Two design decisions worth keeping on record

- **The tracker "Synced" button intentionally stays live and tappable** (opens an unlink
  confirmation) while a similarly-shaped chapter-download-complete indicator is intentionally
  inert. Not a contradiction - see the two anti-pattern rows added to <doc:aletheia/Design> about
  destructive controls in list rows and editable-vs-terminal completed states, which is the
  reusable version of this decision.
- **One control handles both sync directions** (pull when the tracker is ahead, push when local
  is ahead), naming the direction and the chapter number in the label rather than splitting into
  two buttons. Revisited and reconfirmed once already; not an open question.
