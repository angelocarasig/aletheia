# Chapter Comments

> Note: research only. Nothing here is implemented - `CommentingSource` and its supporting types
> don't exist in the codebase.

How the app could surface per-chapter reader discussion from a source, as an online-only feature.

The post-chapter moment - a cliffhanger ends and the reader wants reaction validation - lands
exactly on a surface this app already owns (the reader's end-of-chapter separator), and no
aggregator-style reader in the survey has this feature at all. Volume on the sources this app
currently ships is modest (roughly 10-16 replies on a popular chapter, not thousands), so this is
scoped as a cheap tier that ships first and proves whether readers tap it before any scraping tier
is built.

## The contract, if built

An opt-in refinement following the same shape as `AuthenticatingSource` (<doc:aletheia/SourceProtocols>) -
detected by cast at the call site, leaving the descriptor and its fingerprint untouched:

```swift
protocol CommentingSource: SourceService {
    func commentCount(seriesSlug: String, chapterSlug: String) async -> CommentCount?
    func comments(seriesSlug: String, chapterSlug: String, cursor: String?) async throws -> CommentPage
}
```

`commentCount` never throws and returns `nil` for "unknown," never for "zero" - the same
degrade-to-nothing precedent other sidecar fetches in the app already follow. Only one source in
the survey can answer a count cheaply without fetching the thread itself; the others would have to
return `nil` rather than doing a hidden full fetch just to count. A page cursor is an opaque
string whose shape differs per source (a page number, a timestamp, sometimes always-nil when a
source returns a whole thread in one response) - callers never parse it. Nesting is flattened to
one reply level regardless of how deep a source's own threading goes. The feature is read-only
throughout - every source in the survey gates posting behind its own account system, so an
external link-out is the only write path considered.

## Tiered rollout

| Tier | What ships | Sources |
|---|---|---|
| 1 | a count tease on the chapter separator, tapping opens an in-app browser to the thread | whichever source has a cheap, sanctioned statistics endpoint |
| 2 | a native collated thread in a sheet, paginated | sources with a scrapeable or first-party JSON thread |
| 3 | a source whose comments live entirely behind a third-party embed (e.g. Disqus) | requires its own API registration and reverse-engineered thread identifiers |

Tier 1 is the whole bet, cheap: one sanctioned API call, batchable across a whole chapter list. If
the separator row gets no taps, tiers 2 and 3 never need to happen.

## Reader integration, if built

The reader's end-of-chapter separator was explicitly designed with a reserved slot for content like
this to arrive later without a redesign (<doc:aletheia/ReaderGeometry>). Slot presence would follow the
same invariant every other separator slot follows: present or absent based on a static fact (does
the finished chapter's serving source conform to `CommentingSource`), never appearing or
disappearing based on when a count happens to land, since separator heights are declared rather
than measured. Comment fetch would trigger on reaching the chapter boundary - the app's existing
definition of "finished reading this chapter" - rather than on preload, for both spoiler safety
(no comment count visible before the chapter is actually read) and request frugality. After a
mid-read source swap, comments would follow the swap, resolving from the chapter's actual serving
origin the same way page content already does.

Every failure shape degrades to "the row is present and says nothing useful" rather than an error
surface or a missing row - offline reads "unavailable offline," an unknown count reads as a plain
"View comments" rather than a number, a source with no thread yet reads "No comments yet." Comments
are garnish; garnish doesn't throw.

## Rejected shapes

A stored descriptor capability flag was rejected in favor of the refinement-protocol pattern, since
a boolean field would enter the fingerprint hash and churn it for a cosmetic fact the cast-based
pattern already handles for free. Collating comments for one chapter across multiple sources was
rejected - chapter identifiers don't align across sources and thread granularity differs enough
that the merge would be mostly fiction; comments belong to the serving origin the reader is
actually looking at. Caching or persisting comments was rejected - the feature is explicitly
online-only, since the content is third-party, unmoderated, and stale within hours; persisting it
would be a schema change and a different feature.

## Per-provider notes

Endpoint-level facts churn fast (a provider redeploy can invalidate any of this), so treat the
following as a lead to re-verify before building, not a fact to trust blindly:

- One shipped source has a cheap, batchable, sanctioned statistics endpoint for a count, with
  content available via a public forum-style scrape as a secondary step.
- One shipped source exposes its comment thread as first-party JSON returning the whole thread in
  a single response, with no cheap standalone count.
- One shipped source exposes comments as server-rendered HTML fragments with cursor-based
  pagination, scrapeable with the HTML-parsing library already in use elsewhere in the codebase.
- One shipped source has no first-party comment surface at all - its comments live entirely inside
  a third-party embed, which would need its own API key and reverse-engineered chapter-thread
  identifiers before any tier-3 work could start, and is the least verified of the four.

Re-probe all of this against live responses before writing a single line of tier-1 code - a
provider's HTML/API shape is exactly the kind of fact that goes stale between when it's written
down and when it's acted on.
