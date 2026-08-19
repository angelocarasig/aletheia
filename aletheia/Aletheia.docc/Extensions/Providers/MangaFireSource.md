# MangaFire

`mangafire.to`. API lane - a signed JSON API, `/api/*`, no HTML scrape and no renderer.
`MangaFireSigner` reimplements the site's request-signing scheme natively; there is no
`WebRenderer` dependency anywhere in this source.

See <doc:aletheia/BuildingASource> for the lane vocabulary this page assumes.

Everything below is perishable by nature (a third party's endpoints, signing scheme, and site
behavior) - the code is truth when it disagrees with this page.

## The domain

`mangafire.to` is the real site; no rotation has happened. `mangafire.cc` is a clone (different
title, no signing infra, `/api/titles` 404s); `.net`/`.me`/`.com` are ad-parking; `.bz`/`.online`
don't resolve. A 200 from this site means nothing on its own - every unknown path returns the same
SPA shell byte-for-byte, so a response has to be checked by body, never by status.

## The `vrf` signature

Every `/api/` path answers an unsigned request with `403 {"message": "Missing token."}` - an
application-level check, not Cloudflare. The scheme is deterministic and stateless: no timestamp,
no nonce, no session binding. The same canonical string always yields the same token.

Signing has two steps. First, canonicalize: take the path (stripping the leading `/api`), collect
query pairs stable-sorted by key, rewrite `key[]` params to `key[0]`, `key[1]`... with the index
resetting per key, and join as `k=v&k=v` using decoded values. Second, run that string through
three sequential byte-substitution stages with output feedback (each stage's output feeds the
next), each keyed by its own IV and key bytes against a 256-byte permutation table, then base64url
the result with no padding as the `vrf` query parameter. `MangaFireSigner` carries the exact
tables, keys, and IVs - don't retype them if porting, copy them exactly, and reproduce the known
test vector before pointing a change at the live network.

**The canonical string and the wire URL differ on purpose, in two ways that both produce a 403
indistinguishable from a rotated key:** array params are signed as `key[0]=`/`key[1]=` but sent on
the wire as `key[]=`; spaces are signed decoded (a literal space) but sent on the wire as `%20` or
`+`. The server accepts either encoding on the wire - only the signed form must be decoded.

Order across different keys doesn't affect the signature, but order *within* one repeated key
does, since the index in `key[0]`/`key[1]` binds to position - so query items are handed to the
signer exactly as received rather than re-sorted, and same-key ordering must reach the wire intact.

**Two 403 bodies mean different things:** `"Missing token."` means no `vrf` parameter was sent at
all; `"Invalid token."` means one was sent and is wrong - either the canonicalization is off, or
the signing tables rotated. Only the second body can mean rotation, and only once the signer still
reproduces its known test vector - if the vector fails, the tables changed; if it passes and a
real request still gets "Invalid token," the canonicalization is wrong.

## Endpoints

All under `/api/`, all signed. Series are opaque string ids; chapters are integer ids. Sort is
`order[<key>]=<dir>` as separate query params (not a combined `sort=<key>:<dir>` string), with
direction baked into each declared sort option rather than a separate asc/desc toggle.

Chapter listing paginates at a page size of 200 and mixes every language in one response unless a
language filter is sent - this source deliberately never sends one, since filtering server-side
per language would multiply the request count for the same underlying rows; the reader's own
language priority ordering decides what displays. A chapter language outside the four modeled
codes (English/Chinese/Japanese/Korean) is dropped rather than defaulted to English, since
mislabeling a chapter's language is worse than omitting an unsupported one.

Chapters carry an `official`/`unofficial` type, and both can exist at the same chapter number for
the same series - the type becomes the row's scanlator name so the two stay distinguishable rather
than colliding into duplicate-looking rows.

**Filter validation is strict everywhere except `demographics`, which is silently ignored if given
a bogus value** rather than erroring - every other filter answers a bad value with a named 422.

**There's no default content gate.** Omitting the rating parameter returns every rating including
pornographic - see <doc:aletheia/AdultContent>. This source is rung 2 on the adult-content ladder: the list
payload carries no per-item rating (only the details endpoint does), so the request itself is what
determines the batch, and the rating parameter is sent unconditionally, whitelisted to the clean
tiers when the gate is shut.

## Images

Page URLs and dimensions arrive together in the chapter-content response, with no scramble
indicator - pages decode as ordinary images at their declared dimensions. Page image hosts require
`Referer: https://mangafire.to/`; without it the CDN returns a 403. Cover image hosts need no
referer.

## Cloudflare

Conforms to `AuthenticatingSource` (see <doc:aletheia/SourceAuth>), requiring `cf_clearance` as its one
required cookie, with a `session` cookie marked optional since the SPA doesn't reliably set it on
first paint. WebKit solves the challenge without interaction, and on this tenant the resulting
clearance is accepted by `URLSession` on the same device - the TLS-fingerprint binding
<doc:aletheia/SourceAuth> warns about doesn't apply here, though that shouldn't be assumed to generalize or
to hold forever for this tenant either. A bad signature also answers with a 403, which the default
Cloudflare-challenge heuristic would misread - `isChallenge` checks the response body for the
signing-specific error text first, so a signature bug doesn't get treated as (and re-triggers
capture for) a wall that was never actually there.
