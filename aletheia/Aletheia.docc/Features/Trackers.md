# Trackers

Progress tracking against AniList and MyAnimeList: sign in, link a series to a remote entry, and
keep the remote's progress and status in sync with what's read here.

A **link** is the `series_tracker` row joining one of our series to one remote entry. A **push** is
this app writing progress outward; a **pull** is reading the remote entry inward. Tracking requires
library membership - a series must be added before it can be linked, so the row always has
somewhere durable to live and the launch purge never has to reason about a tracked-but-unowned
series.

Whether a tracker should also supply series metadata (covers, titles, synopsis) is a separate
question - see <doc:TrackerMetadata>. A third tracker, MangaBaka, is covered in
<doc:TrackerMangaBaka>. Restoring a whole library from a tracker's list is <doc:TrackerRestore>.

## The two services

Both take an integer chapter count and an upsert-on-(user, media) model; neither accepts a
fractional chapter number, so progress is floored on the way out. Status vocabularies line up on
five cases - reading, planning, completed, dropped, paused - which is exactly the app's own
``Status`` enum. Re-reading has no local status of its own: a link whose remote status is
`.completed` is inert to automatic pushes (`isInert`) rather than gaining a sixth status, since
writing AniList's `REPEATING` state zeroes remote progress server-side and the risk of a mis-set
status wiping a public profile's number outweighs the rare case.

**AniList** - one GraphQL endpoint. Auth is the implicit grant (`response_type=token`), not
authorization-code - AniList has no PKCE, both grants yield an identical token, and applications
can't be deleted once created, so an embedded secret could never be rotated out. The token arrives
in the URL fragment, not the query. Sending anything beyond `client_id`/`response_type` breaks the
authorize call outright, and there's no `state` parameter on the AniList side. Token lifetime is
one year with no refresh token at all - reconnecting is a routine yearly event, not a fault. A dead
token on the wire is an HTTP 400 with `"Invalid token"`, not a 401. Real rate ceiling is 30/min
despite documentation saying 90; this app paces at 25/min (`Constants.Trackers`). `chapters` is
null for an ongoing series and progress isn't capped at it - clamping is entirely on this app.
Status transitions have server-side side effects: `COMPLETED` overwrites `progress` with the
media's max, and `REPEATING` resets it to zero - a status change and a progress value must never
be sent expecting both to stick, and the entry must be read back after any status transition to
know what actually landed. Adult media are returned by default; `isAdult:false` excludes them (and
"Ecchi" is not classified as adult on AniList's side, which is a real App Review hazard worth
knowing).

**MyAnimeList** - REST, `api.myanimelist.net/v2`. Register as a public app type, not `web` (which
issues a secret it then requires). PKCE with `plain` as the only supported challenge method - S256
fails outright. Access tokens are JWTs with roughly a one-month lifetime (decode the `exp` claim
rather than trusting the stated `expires_in`); refresh tokens rotate on every use and must be
persisted each time. The write endpoint (`PATCH .../my_list_status`) must be
`application/x-www-form-urlencoded` - sending JSON returns `200 OK` while silently applying only
`status` and discarding every other field, with no error. The list-read endpoint needs
`nsfw=true` unconditionally, or entries silently vanish from the response regardless of content -
this is not a content decision, only search is. There's no published rate limit; MAL throttles
with a 403 or a 504 rather than a 429, so requests are paced at roughly one per second with jitter.
A 403 specifically can mean "no credential was even parsed" as easily as "throttled," so it's never
treated as a signal to re-authenticate.

## Signing in

Both flows run through `ASWebAuthenticationSession` with distinct custom-scheme redirects.
Credentials live in the Keychain only, never the database, keyed by service slug. `TrackerCredential`
does not carry a score format column in the schema - format is an account fact restated on every
row, so it lives on the Keychain credential and reaches the view through the accounts list; a
signed-out or unreadable account falls back to a default format for display only, the stored
number itself is untouched. `TrackerAuthority` is a sibling actor to source auth's `AuthRequester`,
not a generalization of it - the two share only the single-flight-refresh pattern, since a tracker
token expires as a plain 401/400 with an HTTP POST to refresh it, nothing like WebKit challenge
capture. Refresh is single-flight per service; a Keychain save failure throws rather than silently
returning; a terminal refresh failure clears the refresh token and back-dates the expiry rather
than deleting the credential outright - a stranded credential still reads as "signed in a month
ago, needs reconnecting" rather than "never connected."

`TrackingScreen` lives inside `SettingsScreen`, one row per service.

## Schema

`SeriesTrackerRecord` - one table, unique on `(seriesId, tracker)`, cascade-deleted with the
series:

- `tracker`, `remoteId`, `remoteEntryId` (AniList's list-entry id, distinct from the media id and
  what a delete must target; MyAnimeList has none) identify the link.
- `remoteTitle`, `remoteStatus`, `remoteProgress`, `remoteScore`, `totalChapters` are a
  deliberately denormalized snapshot - the same reasoning as `ReadingEventRecord.seriesTitle`: a
  signed-out or offline series must still render its tracker line with zero network access.
  `remoteScore` is a canonical `Int?` (AniList's 0-100 `scoreRaw`), converted only at the view -
  MyAnimeList's fixed 0-10 scale and AniList's five possible account formats all read and write
  through this one number.
- `pendingProgress`/`pendingStatus` **are the push queue** - both nil means clean, and a payload is
  always "whatever local state says right now," so there's nothing to persist beyond the fact that
  a link is dirty. This is a coalescing high-water mark, not an append log: `pendingProgress` only
  ever moves up.
- `linkedDate`, `syncedDate`, `attemptedDate`, `syncError` round out the row - `syncedDate` is a
  display fact (last-synced text on the tracker row), not a trigger for anything.

No account table - at most two accounts will ever exist, and the "must render signed out"
requirement is met entirely by the snapshot columns.

## The chapter-number problem

Read state in this app spans origins - a chapter is identified by its number, and the same number
can exist on multiple sources, scanlators, or languages at once, with gaps. Trackers take one
integer. The chosen mapping is `floor(max(number WHERE progress >= 1))` across every origin of the
series, computed flat against `chapter` joined to `origin` rather than through the ranked-chapter
view (a mapping that's a function of rows rather than numbers breaks the moment origins get
reordered). This overstates by exactly the size of a skipped gap rather than pinning forever on a
missing chapter, which is the tradeoff every alternative loses to. Two clamps apply regardless:
never push above a known `totalChapters`, and never push a decrease - a source disappearing must
never un-read history. The watermark is recomputed from the database at push time rather than
carried from the triggering event, since no single event value can express a series-level
watermark under this model. `chapterOffset`, a per-link remedy for a source whose own numbering
disagrees with the tracker's, is designed for but not yet built - nothing reads or writes it today.

## The sync engine

`Compositor.Trackers` is `@MainActor @Observable`, holding accounts and coarse pending/failure
state - no per-item observable class, since a tracker push is one request with no sub-progress to
report, unlike a download. `actor TrackerSyncer`'s unit of work is one link row, and it's the only
writer of `series_tracker`.

**The drain is observation-driven, not triggered per call site.** One `ValueObservation` over the
count of dirty rows means anything that writes the pending columns wakes the drain without needing
to know it exists - the reader finishing a chapter, a batch mark, a merge watermark, an explicit
edit all go through one `enqueue` function. The drain runs as one lane per tracker service rather
than one shared queue, since the two services have independent rate limits and independent auth
states - a dead MyAnimeList account must not stall AniList's queue, and it doesn't. Each lane paces
itself against its own last request (subtracting the request's own latency from the gap, not
adding it on top), re-reads its dirty set every pass so newly-dirtied rows get picked up, and halts
entirely on a terminal auth failure for that service rather than failing every remaining row one at
a time.

**Every push re-reads the remote entry first and sends `max(remote, local)`.** This is the fix for
the one failure mode that actually loses data: reading further on the tracker's own website between
app visits, then having a naive push overwrite the higher remote number with a lower local one. The
read comes for free inside the same request that fetches the entry (one round trip on AniList, part
of the `fields` set on MyAnimeList), so this doubles request count without doubling round trips.
**The response is the only proof a write landed** - AniList rewrites `progress` server-side on
`COMPLETED` and zeroes it on `REPEATING`; MyAnimeList can return `200 OK` for a body it silently
ignored. Either service's write is only trusted once read back.

**The monotonic guard exists in two places**: in `enqueue` (never write a pending value below the
cached remote progress) and again in the syncer immediately before sending (the cache can be
stale). The only path allowed to lower a value is an explicit user edit in the tracker screen,
which bypasses the guard on purpose. A `.completed` remote status makes a link inert to `enqueue`
entirely - no automatic push reaches it, only an explicit edit can, and the pull path still reads
`status` (not just `progress`) so a status change made on the tracker's own website - like un-doing
a completion by marking it `REPEATING` - is recognized rather than ignored.

Two accounts on one series are fully independent - no cross-tracker arbitration. A syncer only
ever sees one link row, a failure on one service never blocks the other, and the tracker section
renders each row's own numbers rather than a merged figure.

## UI surfaces

The Details tracking section renders nothing at all for a non-library series - not a disabled Link
row, since an affordance that can't be operated is worse than no row at all. Linking opens a search
sheet whose rows navigate into one screen that serves as both the candidate detail and the edit
surface - one screen doing both jobs, since the fields a reader would edit after linking are the
same fields they set while linking. Committing the link doesn't dismiss the screen; the button
becomes a filled "Synced" state, and a second tap opens the unlink confirmation - the reader sees
the write land, and the control that created a link is also the way out of it.

A progress mismatch between local and remote renders as one control naming the direction and the
number ("Sync with AniList - Chapter 60"), which pulls (marking local chapters read up to the
remote number) when the service is ahead and pushes to every linked service when local is ahead.
Both directions confirm before writing. Marking chapters read this way reuses the same watermark
path a batch mark already uses - never a second way to write read state - and does not itself
trigger a push back to the service the number came from (`enqueue` declines to write a value that
doesn't beat what that service already reported), though a sibling service that's behind does get
brought up to match.

In the reader, tracker state renders as one row per linked service in the chapter separator.
Presence is loaded once per reading session before the reader opens - a link can't be made from
inside the reader, so the row set is fixed for the sitting, which is what lets the separator
declare its height up front without a row appearing mid-scroll and shifting everything below it.
Each row's state is derived entirely from that link's own columns via one observation, not reported
by the sync engine directly: `errored` (a `syncError` is set), `signedOut` (the account can't push
until reconnected), `skipped` (nothing was sent, either declined by `enqueue` or no link exists),
`loading` (a pending value is set and hasn't cleared yet), or `tracked` (a push this boundary waited
for has landed). State freezes per boundary once crossed - a chapter's separator row doesn't spin
back up when a later chapter finishes, since the pending columns clear at the series level, not per
boundary.

When an account can't push, the Details tracking row reads "Sign in again to keep tracking" rather
than disappearing - a linked-but-unavailable service always keeps its row, since dropping it would
take a still-linked service off the screen with nothing to act on. The wording is the same
regardless of which service's lifecycle produced it (AniList's routine yearly expiry, or
MyAnimeList's genuinely rare one), since the reader does the same thing about either.

The library carries a filter group (per-tracker plus untracked), hidden until something in the
library is actually linked. The Failures screen carries a tracker section separate from the source
grouping, since a tracker retry wakes a whole lane rather than resending one row - no per-row
spinner, since the engine doesn't distinguish rows that way. Nothing renders on artwork - linkage
is discoverable through the filter and legible on Details, and a badge on every cover would be
ambient data dressed as a notification.

## Failure surfacing

A push failure is never a run-scoped signal - no pill, no toast. It failed, the pending columns are
still durable, it retries on the next wake. What does surface: `syncError` on the link row itself
(the Details tracking row and the Failures screen both read it), and a dead account as one row per
service in the Activity screen - named rather than counted, since "1 account" is a number where the
service's own name is the whole instruction, and a single dead account should never brand every
series that happens to be linked to it with the same badge.

## Not built

Pulling remote progress automatically when a Details screen becomes stale (`syncedDate` is
currently a display fact only, not a trigger). `chapterOffset`'s UI. The pre-release round trips
that verify AniList's field-omission-preserves-value assumption, the `COMPLETED` overwrite
behavior, `customLists` preservation, and non-`POINT_100` score writes against a live account -
these are inferred from documented behavior and convergent third-party evidence, not confirmed
against this app's own client.
