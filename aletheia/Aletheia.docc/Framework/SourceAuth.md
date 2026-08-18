# Source Authentication

How a source behind a wall - a Cloudflare interstitial, a login - gets through.

## The shape

An opt-in refinement, `AuthenticatingSource: SourceService`, cast at the call site like every
other opt-in (see <doc:SourceProtocols>). A plain source talks to `NetworkService` directly; a
conforming one routes every request through `fetch(_:)`, which buys the whole retry chain:

```
fetch(url)
  -> AuthRequester.send(request, for: source)
       -> credential(for:)         cached keychain credential if isValid(), else refresh
       -> credential.apply(&req)   sets User-Agent + Cookie headers
       -> NetworkService.send      the real request
       -> source.isChallenge(...)  did a wall answer instead of data?
       -> if challenged: refresh once -> re-apply -> send once more
```

- `credential(for:)` serves a keychain-cached `SourceCredential` while `isValid()` (expiry minus a
  60s skew), else refreshes. Silent on the hot path - it fires once per request.
- `refresh(for:)` single-flights per slug: concurrent 403s wake one capture, the rest join the
  in-flight task. The result saves to `Keychain.sources` keyed by slug.
- `isChallenge` has a Cloudflare default (the `cf-mitigated: challenge` header, a 403/503 from a
  `Server: cloudflare`, or `__cf_chl`/"Just a moment" body markers). A non-Cloudflare wall
  overrides it; answering `true` is what triggers capture-and-replay, so an unrecognised wall reads
  as an ordinary failure rather than looping.
- Current conformers: `MangaFireSource`, `MangaBallSource`, `NHentaiSource`, `ToonilySource`.

## Why WebKit does the capture

``WebAuthCapturer`` (`@MainActor`, iOS 26 `WebPage`) loads the challenge URL in a real engine so
the challenge actually runs - JS, Turnstile, the redirect dance - and the cookies it deposits are
genuine, not hand-forged. It collects them three ways at once, since no single one is reliable:

- an exponential poll (250ms doubling to 4s) - the load-bearing one.
- a navigation re-check that resets the poll on each navigation.
- a cookie-store observer, which doesn't fire on a non-persistent store and has no other conformer
  depending on it.

First run of all three that finds every required cookie wins; capture returns
`{cookies, userAgent, expiresAt}`, and the sheet (if interactive) dismisses.

**The page must be visible for any of this to work.** WebKit throttles timers and `requestAnimationFrame`
in a `WebPage` it doesn't consider visible, and a Cloudflare challenge is timing-sensitive enough
that a throttled one misses its own deadline and retries forever. Rendered is not the same as
visible - a page mounted in the view hierarchy but covered by other content is still throttled the
same as one with no view at all. Whatever presents the capture page must not be covered by
anything, including the app's own content.

**The cookie store is non-persistent, one per capture.** A shared, persistent store lets a
clearance minted days earlier still be sitting in the jar the moment a new capture begins, and
`evaluate` reads the jar rather than the navigation - so an observer can report success against a
stale cookie the capture never actually earned this run. A per-capture empty store makes
provenance a property of the design: the only cookies in it are the ones this navigation earned.

**The user agent is the engine's own, read once and then pinned** - the agent that earned the
cookies must be the agent that sends them, since Cloudflare ties a clearance to the agent it was
issued for. `AuthSpecification.userAgent` can still override for a source that genuinely needs a
specific string.

## The TLS fingerprint caveat

**The cookies are earned in WebKit's TLS context and replayed in `URLSession`'s. Nothing
guarantees the second context is accepted just because the first one was.**

Modern Cloudflare can bind a `cf_clearance` not only to the user agent but to the TLS fingerprint
(JA3/JA4), and often the IP, of the client that solved the challenge. `WKWebView` and `URLSession`
are two different TLS stacks with two different ClientHello fingerprints. Handing a WebKit-minted
clearance to `URLSession` can be rejected by a tenant that checks, even with a perfect cookie and
user agent.

**Failure mode if a tenant does check:** `isChallenge` fires on the replayed request, `refresh`
captures a fresh clearance in WebKit, the replay over `URLSession` is rejected again. The
retry-once policy stops this from looping infinitely, but it degrades to a persistent challenge
error rather than data - it reads as "auth keeps failing for no reason," and the reason is the
fingerprint, not the cookie.

There's no `URLSession` TLS-fingerprint control on iOS, so the escalation when a source rejects
the replay isn't a tweak to this chain - it's routing that source's data requests through WebKit
too, the same context that earned the clearance, not just the capture. That's a per-source
decision, made only when a source proves it needs it; cookie-replay stays the default because it's
far cheaper and works for every currently-shipped conformer.

**Test before assuming.** For any new Cloudflare-fronted source, hit its real data endpoint from a
device `URLSession` with a freshly captured credential before building on the cheap path. One
request answers whether that tenant is replay-friendly or fingerprint-bound.

**A broken capture and a fingerprint-bound tenant produce identical symptoms** - both read as
persistent auth failure. Confirm the credential is both new and earned before concluding anything
about the wall. `cf_clearance` expiry is the cheapest oracle: a freshly minted one always reads the
same remaining lifetime, a stale one counts down.

## Requirements: required and optional

`AuthRequirement.cookie(name:optional:)` splits a source's needed cookies into required and
optional sets. Capture returns as soon as the required set is satisfied, carrying whatever
optional cookies happened to be present. This exists because not every tenant challenges every
client the same way - a source can be adopted through this layer as a hedge against a tenant that
might tighten later, even when its usual response mints no challenge cookie at all. A source whose
second secret is a non-cookie value (a CSRF token from a `<meta>` tag, say) has `SourceCredential`
carry it as an opaque header map instead - cookie capture alone can't authenticate that case.

## Other things worth knowing

- The retry doesn't re-check `isChallenge` - a still-challenged retry surfaces challenge HTML as
  if it were data, a confusing decode error downstream rather than a typed auth error.
- The 60s expiry skew is generous for a proactive refresh but does nothing for a clearance revoked
  early server-side - that path relies entirely on `isChallenge` catching the next request.

## Why WebKit-for-capture, URLSession-for-volume

Running every page fetch through a real browser costs several seconds per call (see <doc:WebKit>).
Doing that only to mint a credential, then serving many cheap `URLSession` requests off that one
credential, is the whole point of the split. The TLS caveat above is the price of it, worth paying
by default because most tenants don't check - but a source that needs the browser for its data
requests too is a legitimate, if expensive, outcome of that check, not a bug in this design.
