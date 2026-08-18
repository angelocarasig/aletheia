# Chapter Storage

> Note: research only. There is no chapter downloader yet - nothing writes `chapter.path` today,
> and `AssetStore`'s only current client is the cover downloader. This document decided what a
> download *would* write, ahead of the subsystem being built.

## The answer

**The directory is the store. CBZ is the export/import boundary.** These aren't competing answers
to one question - they're answers to two different questions that got conflated. What a download
writes is a directory of zero-padded page files, unchanged from what `AssetStore` already does for
covers; what the reader reads is that directory; what leaves the app (if export is ever built) is
a `.cbz` built on demand from the directory; what a user could import is a `.cbz` exploded back
into the directory store. Choosing CBZ-as-export changes no code that exists - it adds a feature,
it doesn't alter the download design.

## Why not store archives directly

The reader's page pipeline only ever hands the image decoder a file URL - there's no `Data` path
and no custom image data provider anywhere in the codebase today. An archive entry has no URL, so
storing chapters as archives would mean a custom image-decoding bridge wrapping an archive URL and
an entry path, explicit cache keys, and the page model losing its simple hashable file-URL
identity. Several comic readers prove this is tractable, but it's real cost across the hottest
path in the app for something the plain directory approach already gives for free.

## Three assumptions that turned out false

- **"A zip costs resumability."** Mostly false - almost no reader streams pages directly into a
  zip; nearly all of them download into a temp directory and zip only as a terminal step, which
  means the archive question is orthogonal to the download path itself. The one reader that does
  stream incrementally into an open zip still can't resume a partial archive, because opening for
  write truncates whatever was there - its resume is chapter-granular off a separate index, not
  page-granular from the partial archive.
- **"CBZ needs a new dependency."** False, but not for the obvious reason. Foundation's own
  directory-to-zip API works with zero dependencies, but gets the wrong compression (always
  DEFLATE, unselectable) and the wrong entry order (raw directory-read order, not sorted by name) -
  disqualifying for an artifact whose entire value is interop. The real answer is that zlib is
  public in the iOS SDK, and a STORED-only ZIP writer (no compression, so no compressor needed) is
  small enough to write by hand.
- **"CBZ makes downloads visible in Files.app."** Orthogonal - downloads sit in the app-group
  container regardless of storage format, and the app declares neither of the two Info.plist keys
  that would make anything browsable in either format.

## What the ecosystem does, briefly

CBZ-by-default is the majority position among surveyed readers, but the entire published rationale
traces back to one old issue about a large flat directory of loose files hanging Android's SD-card
scanner - every load-bearing term of that argument (a system-level media scanner, removable
FAT/exFAT cards, a gallery surface indexing every file) is Android-specific and doesn't apply here.
That doesn't make CBZ wrong, it makes the popular default inherited rather than reasoned for this
platform.

The one format genuinely built for webtoon/continuous-scroll content (Readium's DiViNa profile,
with a normative `scrolled` layout flag and per-page dimensions as a first-class field) is not
actually shipped anywhere - its own maintainers describe it as still incubating years after
release, and even Readium's own toolkit doesn't render its scrolled layout correctly. Worth
stealing the schema as an optional manifest embedded in an exported CBZ later; not worth adopting
as a runtime format.

No container format encodes webtoon contiguity at all - the two approaches other readers take are
splitting a tall image at download time (lossy, irreversible), or scoring pages by aspect ratio and
width variance at read time to auto-detect a webtoon strip. This app already knows orientation from
its own source metadata, so neither is needed - detection only becomes relevant for a future
import path handling a user's existing files.

## Measurements that would drive the choice

- **STORED compression vs DEFLATE**: on a real 300MB batch of page JPEGs, STORED took ~300ms and
  grew the archive by 0.006% (pure container overhead); DEFLATE took over 40x as long to save
  roughly 0.7% of the size. Image bytes are already compressed - deflating them again is close to
  pure cost for negligible gain. The one exception worth deflating is a small metadata XML file
  embedded alongside the pages.
- **Per-file overhead of the directory approach** (APFS block rounding, per-file metadata) comes to
  under 1% of total size at a large-library scale - not a meaningful argument for archiving at
  rest.
- **Read-only memory mapping of a STORED archive is nearly free** against memory pressure; reading
  the same file fully into memory costs its whole size. This matters only for a future import path
  reading someone else's archives, not for anything currently planned.

## What a CBZ would need to be readable elsewhere, if built

These aren't preferences - a CBZ has no index, so several things are load-bearing for interop:

- **Page order is a filename sort, never archive entry order** - every reader surveyed sorts by
  filename; this app's existing zero-padded numeric naming already satisfies that.
- Lowercase extensions, ASCII-only entry names, no directory entries inside the archive, never
  encrypted (an encrypted zip silently reads as an empty archive to some libraries, with no error).
- The cover is whatever sorts first - no reader surveyed reliably honors an explicit cover marker.
- A metadata file (`ComicInfo.xml` at the archive root, in that exact case) is the closest thing to
  a de facto standard; per-page dimensions have a stable home in it and are safe to write across
  every version of the format. There's no sanctioned way to embed custom app-specific data in it
  beyond a sentinel-prefixed value in its free-text notes field, or a second sidecar file dropped
  alongside the pages (tolerated by every reader surveyed, stripped by none).
- JPEG and PNG are the only two image formats safely both encodable on iOS and universally readable
  elsewhere - the plan would be to export whatever bytes the source served, untranscoded.

## What to build, when this is picked up

A hand-written STORED-only ZIP writer over the system zlib import (for the free CRC32, not
compression), writing to a temp path and moving into place atomically rather than writing an
archive directly to its final path - a crash mid-write must never leave something that reports as
a complete, valid archive. A free-space guard before starting, and a failed archive must not abort
a batch of others. The existing per-part write behavior in the asset layer already avoids
buffering a whole chapter in memory before writing, which several other readers surveyed don't.
