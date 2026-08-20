# MangaBaka

The third tracker, alongside AniList and MyAnimeList. MangaBaka is an aggregator - one entry
carries the AniList, MyAnimeList, Kitsu, MangaUpdates, Anime-Planet, Shikimori, and ANN ids for the
same work - and its metadata is the best-shaped supplier of the three, but its auth path differs
from the other two.

See <doc:Trackers> for the shared sync engine and schema this tracker plugs into, and
<doc:aletheia/TrackerCandidates> for the four other services considered and rejected before this
one shipped.

## Auth: a pasted token, not a redirect

MangaBaka runs a real OpenID Connect provider (`authorization_code` + PKCE S256, a refresh grant,
a revocation endpoint) that's better-specified than either shipping service's flow. It's unusable
for this app anyway: the token endpoint only advertises `client_secret_basic`/`client_secret_post`
auth methods, there's no dynamic client registration, and no public self-serve page exists to
register a native app and receive a `client_id`. A native public client has nothing to
authenticate with.

The shipping path is a Personal Access Token - an `mb-`-prefixed key the reader creates on
MangaBaka's site (`/u/settings`) and pastes in. Every authenticated endpoint accepts a PAT or an
OAuth bearer interchangeably, so this isn't a lesser tier, just a different acquisition path -
it lands in the same `TrackerCredential` shape every other tracker uses, with no refresh token and
no expiry. That's also the better steady state in practice: AniList's token has a hard one-year
life with no refresh at all and interrupts a reader annually, guaranteed; a PAT persists until the
reader revokes it. The paste screen validates the token against the profile endpoint before saving
(so a bad paste fails at the field, not at the first push) and checks that the `library.write`
scope is actually present - though a PAT's `scopes` field reports empty even when it has full
access, so that specific check was removed after a real token got wrongly rejected by it; a
genuinely read-only token is now only caught at the first push, as a 403 with the service's own
message on the link row.

An OAuth path stays purely additive if MangaBaka ever opens client registration - same
`TrackerService`, same schema, only the auth acquisition step would gain a second option.

## Vocabulary mapping

**Status** - MangaBaka has seven states against this app's five. `rereading` maps to `.reading`
(the same as AniList's `REPEATING`) and `considering` maps to `.planning`; neither extra state is
ever written back, only read.

**Score** - `rating` is already `0...100`, nullable, matching this app's canonical storage exactly -
no conversion needed on either read or write, unlike the other two services. The account's display
scale (`rating_steps`) maps onto `ScoreFormat` for four of five possible values; the fifth (a
25-step scale) has no matching case and falls back to `.point100` - the number itself stays
correct either way since storage is canonical, only the picker granularity is coarser than the
website's.

**Publication and classification** map onto this app's enums more precisely than either shipping
service: MangaBaka's `content_rating` is the exact four-tier vocabulary this app's `Classification`
already models (safe/suggestive/erotica-or-pornographic-as-explicit), and `status` includes a real
hiatus state where AniList and MyAnimeList's default responses don't. `upcoming` (nothing published
yet) maps to `.Unknown` rather than `.Ongoing`, since claiming chapters exist when none do is
worse than not naming the state at all.

## What only this service can do

**Merge forwarding.** Every series carries a merge state, and a merged series names its
successor's id rather than 404ing the way an equivalent situation on AniList does. On any fetch
where the service reports a merge, the link's remote id is rewritten to the successor and the
fetch retries once - and the rewrite has to persist before any write goes out, or the app ends up
reading from the new id while still writing to the old one, a worse state than not following the
merge at all.

**Cross-service ids exist but are never auto-linked.** A MangaBaka entry publishes the same work's
id on six other trackers, and the reverse lookup works too - link one service, and the ids for the
others are sitting right there. This is deliberately not used to auto-link anything: the same
reasoning that keeps a content source's published tracker cross-reference from seeding a link
applies here with a more respectable third party in the middle - a mis-linked series should always
be traceable to a choice the reader actually made. What's legitimate is a pre-filled confirmation
(resolving the candidate from a cached lookup and opening the ordinary confirmation screen with it
already selected) - not yet built.

**Search and metadata work without an account.** Neither other service allows an unauthenticated
read of anything; MangaBaka's search and series-detail endpoints need no token, so a reader with no
MangaBaka account can still see what a link would look like.

## Rate limits and errors

Search is capped tighter than everything else (30/min) and belongs to a screen with a text field
in it, so the link search is debounced rather than firing per keystroke. Everything else
(including all authenticated calls) is capped around six times AniList's real ceiling; this app
paces it conservatively regardless. No rate-limit headers are returned on any response, so pacing
is open-loop rather than reading a remaining-budget header the way AniList's client can. A series
not on the reader's list is a distinguishable 404, separate from a 401 for a dead credential -
which is exactly the distinction the remote-vs-local progress guard depends on to avoid treating
"we can't check" the same as "nothing to catch up on."

## Real bugs this integration found

**A successful write's response body is not the entry the documentation describes** - it's a bare
boolean. The first version decoded the documented shape, failed, and reported "the service isn't
responding" about a write that had, in fact, already landed - the worst failure shape, since a
retry then looks like it would duplicate an entry that already exists. The fix doesn't parse the
write's body at all: check the status, then read the entry back in a second request, the same
thing the MyAnimeList client already does for its own reason (a `200` there can mean a silently
ignored write). Read-after-write is now this feature's general pattern for any tracker whose
write-response shape hasn't been independently confirmed against live data.

**A generic error type erased which failure actually happened.** One shared "unavailable" case
covered both "the host didn't respond" and "we couldn't parse the response," which reads
identically on screen and is nearly useless for anyone debugging it after the fact - a dedicated
log category now carries the specific decode failure (the field and a slice of the raw body)
separately from the deliberately vague message shown to the reader.

## Metadata supply

Needed no new code - the metadata-absorption path built for AniList/MyAnimeList (see
<doc:TrackerMetadata>) is generic over which tracker supplied the data, so MangaBaka was live the
moment it registered as a service. Its titles arrive as a language-tagged pool (matching this
app's own title-pool shape more closely than either other tracker), and its covers arrive with
real dimensions. Prose is stored (`storesProse = true`) on the reasoning that this app is personal
and non-commercial - MangaBaka's data license permits storage with attribution, unlike
MyAnimeList's terms, which impose a retraction duty a local cache can't honor. That attribution is
still owed and not yet built - there's no About surface in the app yet to put it on. Metadata is
only captured at link time and never refreshed afterward, the same limitation every tracker
supplier has.

## Bulk listing

Feeds <doc:TrackerRestore>. The endpoint that looks like the obvious whole-list read
(`/v1/my/library`) turns out to carry no series data at all in its response - a beta `v2` endpoint
is what actually answers a whole-list pull, and its own pagination link silently reverts to a much
smaller page size than requested if followed naively, which desyncs page boundaries and can return
the same series twice. The client drives its own page counter and resends the requested page size
explicitly on every request rather than trusting the server's own pagination link.
