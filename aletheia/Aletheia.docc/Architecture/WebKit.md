# WebKit

How `WebPage` process behavior and render timing work, and what that means for any headless page
load in this app.

## Where this applies

``WebAuthCapturer`` is the only live `WebPage` consumer - it builds and navigates its own page to
capture auth cookies, wired into ``AuthRequester`` from ``Compositor``. ``WebRenderer`` builds a
`WebPage` too, but has no live caller outside its own files and the unregistered
`Providers/Deprecated/` lane; the facts below apply to it as well if it's ever revived.

## Process pooling doesn't exist

`WKProcessPool` is inert - creating multiple instances has no effect, and `WebPage.Configuration`
has no process-related property at all. There's no API-level way to launch a browser, hold the
handle, and open pages against it.

WebKit already warms processes on its own: a process cache retains a process after its page goes
away so the next page can adopt it. Building a `WebPage` - construction, cookie injection, script
installation - costs roughly 10ms; a genuine process cold start would be hundreds. Pooling pages
to save that cost isn't worth building.

## Where render time goes

Building a page is close to free. Navigation and readiness settling is the fixed cost - several
seconds per call, largely independent of payload size. Waiting on
`document.readyState === "complete"` is almost always the wrong readiness signal: `complete` only
fires once every subresource - cover images, fonts - has loaded, none of which a scrape or an
in-page API call needs. `interactive` (DOM parsed, deferred scripts run) is the signal that
actually matches what most calls need.

## A page that isn't visible is throttled

A `WebPage` with no view hierarchy at all never lays out or paints - expected. Less expected:
**rendered is not the same as visible.** WebKit throttles based on occlusion, not hierarchy
membership - a page mounted in a view but covered by other content is throttled the same as one
with no view at all. A page doing real work has to be on top and unoccluded. `.hidden` or
`alpha == 0` risk landing back in the throttled case; if it has to stay invisible to the reader,
use a full-size overlay at a tiny non-zero opacity with hit testing off instead.

The failure mode reads as a network problem, not a throttling one - a time-sensitive exchange (a
Cloudflare challenge, for instance) can miss its own deadline and retry forever on an occluded
page, which looks like the remote end rejecting the request.

## If page reuse is ever needed

The reuse that pays off is the loaded page, not the process - the remaining cost is per-navigation.
Keeping one `WebPage` parked on an origin with its scripts already loaded, then navigating it
repeatedly, skips both the settle and script-discovery cost on every call after the first. That has
real costs too: a resident process, background jetsam risk, and one page can only serve one origin
at a time.

Try `WebPage.Configuration.loadsSubresources = false` first - it blocks images, media, and fonts
with no `WKContentRuleList` needed, and combined with the `interactive` readiness fix may remove
the reason to keep a page warm at all.

## Rules of thumb

- Don't reach for `WKProcessPool` - it does nothing.
- Don't build page pooling to save process start cost - that's already near-free.
- Wait for the weakest readiness signal actually needed. `complete` is almost never it.
- Keep any page doing timing-sensitive work visible and unoccluded - behind other content counts
  as hidden.
