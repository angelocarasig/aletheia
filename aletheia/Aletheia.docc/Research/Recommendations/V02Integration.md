# Fitting Orihime to This App

What changes about how the app carries a recommendation model, now that there's more than one worth
carrying. Describes product and infrastructure decisions only - see <doc:V02Artifact> for the pack itself.
**Not built.** Everything here is a design, verified against the app's actual code during review, not
shipped code.

## From one bundled model to a picker of downloadable ones

v01 shipped as one thing: bundled inside the app, gitignored, always present, never a choice. That was the
right call when there was exactly one model and no alternative to offer. It stops being the right call the
moment a second, heavier model exists that not every reader will want to carry.

The new shape: Settings gets a model picker, closer to a game's language packs than a version bump. Each
model - v01, Orihime, whatever ships after - is a separate download via Background Assets, switchable,
removable independently of the others. A reader who never touches it keeps the app at its current size;
one who wants Orihime's better matching pays for it once, explicitly, and can remove it later without
losing anything else.

This reverses a deliberate earlier decision on purpose. v01's docs argued hard against "download on first
use" - it turns an always-working feature into one with a permanent "not available yet" state. That
reasoning still holds for a single default model with no alternative. It doesn't hold once the whole point
is reader choice: **the feature ships off by default now** - a reader opts in and picks a model themselves,
rather than the app choosing one for them at install time.

## Each pack is fully isolated, on purpose

Considered and rejected: sharing metadata across packs via content-addressed deduplication (two packs with
byte-identical files reusing one copy on disk). Rejected because it only pays off when two packs are built
from the exact same catalogue snapshot, and model generations don't stay in lockstep - v01 and Orihime
already sit on different monthly dumps, a future model will too, so the common case is "different dump
date, no shared bytes" rather than the reverse. The engineering cost of doing this safely (a shared blob
store, reference-counted deletion so removing one pack can't silently break another still pointing at the
same file) buys a saving that mostly wouldn't trigger.

Instead: **every pack is self-contained.** Its own rails, its own compute pieces, its own metadata if it
needs any beyond what a shared reference pack already provides. Removing a pack means deleting its files,
full stop - nothing to reference-count, nothing that can go stale because another pack changed underneath
it.

## v01 doesn't retire when Orihime ships

The original plan (see the early exchanges that shaped <doc:V02Artifact>) was a straight replace - grade
Orihime, delete v01's rails if it doesn't regress. That's no longer the model. v01 stays a permanently
selectable option in the picker alongside Orihime and whatever comes after, the same way a game doesn't
delete an old language pack just because a better-translated one shipped. The **grading gate still
applies** before Orihime becomes trustworthy at all - a Labeller run (Orihime vs. Protostar) has to clear
before it's offered as more than an experiment, covering both the resolved and the new unmatched-mode path
- but clearing that gate is a prerequisite for offering Orihime, not a trigger for removing v01.

## One cache, one source of truth for "what should this series show"

The compute path is expensive enough (encode, profile, score against the whole catalogue, on the order of
a second) that recomputing it on every `Details` open isn't acceptable, the way a v01 rails lookup always
was. Caching the result surfaced a real design smell first: `SeriesRecord.catalogId` (resolution identity)
and a naive "check catalogId, then check a cache table, then compute" call-site pattern would have made two
independently-invalidated stores that need to agree with each other - exactly the kind of hidden dependency
that drifts silently.

The fix: **one table is now the single source of truth.** `series_recommendation` holds, per
`(seriesId, packId)`: a fingerprint of the local inputs that produced the result (title pool, synopsis,
tags, cover, year, format), the resolved catalogue id if resolution landed (`NULL` if it didn't - a normal,
common shape, not an error state), and the computed rail itself. A `Details` open does exactly one lookup.
Fingerprint matches → render immediately. Fingerprint mismatch or no row → show whatever's cached (if
anything) while a background recompute runs, then write the new row - the same non-blocking shape
`Details` already uses for chapters loading after metadata (`DetailsComposer+Observation.swift`'s reactive
`apply(_ stored:)`, which already fires on any relevant field change with no new "watch for changes"
plumbing needed).

`SeriesRecord.catalogId` as a standalone column is dropped entirely rather than kept as a mirror - nothing
external depends on it surviving (the library backup format already treats a resolved id as
re-derivable, not something that has to round-trip through a restore), so there's no reason to keep two
places holding the same fact. `Compositor.Impressions.owned()`'s bulk ownership query becomes a join
against the new table instead of a flat scan - not a hot path, the extra join costs nothing that matters.

A seed that resolves to nothing scoreable (no synopsis and no cover) still gets a cache row - an empty
rail, cached the same as any other result, so the app doesn't re-attempt a doomed computation on every
open. This is a schema change (new table, one column removed elsewhere) and needs a proper append-only
migration per the project's migration convention, not an edit to an existing one.

## New infrastructure categories, not extensions of existing ones

Checked directly: this app has no existing Core ML, Vision, or Accelerate/vDSP usage anywhere. Everything
built for v01 - and everything the rails half of Orihime needs - is a memory-mapped file read, the same
loader shape throughout. The compute path is a genuinely different category of work:

- **Core ML inference**, for the text and cover encoders and the appeal student. **Reversed from the earlier
  plan**: models ship as source `.mlpackage`/`.mlmodel`, not precompiled `.mlmodelc`. The original ask to the
  pipeline side was precompiled specifically so the compile cost lands once at export, not on a reader's
  first open - matching v01's own "pay it at launch, not on first interaction" page-warming principle. That
  still would have been the better cost profile, but it means every pack revision needs a Mac-side compile
  step on the pipeline's end (`xcrun coremlcompiler`, verified working, but a real hop requiring a Mac and a
  manual file round-trip) before the app can use anything. Compiling on-device with `MLModel.compileModel(at:)`
  - the documented API for exactly this case, content that wasn't present at the app's own build time - trades
  a known one-time cost for a much simpler pipeline: no Mac hop, ship the `.mlpackage`s as downloaded,
  compile once after the pack finishes downloading, persist the result so it isn't paid again. The real
  cost this reintroduces: that one-time compile happens on a random reader's device instead of a known
  machine ahead of time, so a device/OS-specific compile failure surfaces in production instead of before
  release, and it can't be checked with a parity run before shipping the way a precompiled model could.
  Compute-unit assignment is still decided per model (see <doc:V02Artifact>), not left to the default.
- **Accelerate/BLAS**, for the full-catalogue scoring scan - deliberately not a Core ML operation, since
  batching many seeds at once (the case that would justify Metal) is unnecessary once results are cached
  per series.
- **Background Assets**, for pack delivery - verified end to end on a real device (see below). No longer
  unstarted, but still a genuinely new category of infrastructure for this app.

Deployment target is iOS 26.0/26.2 (confirmed from the project file), which is generous headroom for Core
ML conversion options - no constraint from the OS floor.

## Pack readiness after a Background Assets download

A pack finishing its Background Assets download isn't the same as a pack being usable - three steps happen
in between, all app-side, none of them optional:

1. **Unzip.** `ba-package` delivers a pack as a single `.aar` archive (verified directly - `xcrun ba-package
   package` produces one `.aar` file per pack, confirmed on a real build of both the Orihime and Protostar
   packs). The archive has to be extracted before anything inside it - rails, vectors, models - is
   readable.
2. **Compile the models.** `MLModel.compileModel(at:)` against each `.mlpackage`/`.mlmodel` the unzipped
   pack contains (three per Orihime-shaped pack: text encoder, cover encoder, appeal student), per the
   reversal above. This is the one genuinely slow step in the sequence and the reason it can't happen lazily
   on a reader's first "More Like This" open - it needs to run once, right after unzip, with its own
   progress state the picker can show.
3. **Mark the pack active/ready.** Only after both of the above succeed - a pack that's downloaded but not
   yet unzipped-and-compiled isn't a selectable option in the picker yet, it's still "installing."

This sequence is a property of *every* pack going forward, not just Orihime - whatever ships after it
inherits the same three steps, since the reversal above means on-device compilation is now the standing
approach, not a one-off exception.

## Background Assets, verified end to end

**Shipped and working, not just designed.** A real extension target (`RecommendationModels`, Self-Hosted +
Managed) downloaded a real pack (Protostar, the v01-equivalent) from a locally-hosted manifest onto a real
device, and the app read a file back out of it - `AssetPackManager.shared.contents(at:searchingInAssetPackWithID:)`
against `manifest.json` inside the downloaded pack. Every fact below came from an actual runtime error, not
a doc read.

**The extension itself needs close to no code.** Xcode's own "New Target" wizard has a template for this
(Background Download Extension → Self-Hosted, Managed) - not something hand-built against raw `.pbxproj`
edits. The generated `@main struct DownloaderExtension: ManagedDownloaderExtension` conforms with its one
optional hook (`shouldDownload`) left at the default `return true`, because that hook only filters
essential/prefetch packs the system would auto-download - every pack this app ships is `onDemand`, which
the system never auto-downloads regardless of what this method returns. Confirmed: this file needed zero
changes from what the wizard generated.

**Four `Info.plist` keys are required on the main app** (not the extension), each one only discovered by
hitting the actual validation error it produces when missing:

- `BAManifestURL` (String) - and it **must** be `https://`. No exception for `127.0.0.1`/localhost the way
  ordinary App Transport Security grants one - Background Assets enforces this at its own layer
  ("`BUG IN CLIENT OF BackgroundAssets: The 'BAManifestURL' must be a link to an 'https://' URL.`"). Plain
  HTTP against localhost, which works fine for ordinary networking, does not work here.
- `BAAppGroupID` (String) - the app group identifier, as a plain string, separate from just having the
  App Group *entitlement* present. Missing it isn't a soft validation warning, it's a hard crash the first
  time app code touches `AssetPackManager.shared`
  (`AssetPackManager.swift:226: Fatal error: ... lacks a string value for the key "BAAppGroupID"`).
- `BAInitialDownloadRestrictions` → `BADownloadDomainAllowList` (Array) - the manifest's host has to appear
  here or the request is rejected.
- `BAInitialDownloadRestrictions` → `BADownloadAllowance` and `BAEssentialDownloadAllowance` (Integers) -
  **both** required even though this app has zero essential packs; `BAEssentialDownloadAllowance` can
  honestly be `0`, but its absence still throws
  (`BUG IN CLIENT OF BackgroundAssets: The app must contain a number with a key named
  'BAEssentialDownloadAllowance'...`).

**A pack's own directory structure is preserved inside it, not flattened.** `ba-package package`'s manifest
selects source content via a `fileSelectors` directory entry (e.g. `{"directory":
"protostar-1-0-0-2026.08"}`) - and that directory name survives as a literal subfolder inside the resulting
pack. Reading a file back out needs the full path exactly as it was selected
(`protostar-1-0-0-2026.08/manifest.json`), not the bare filename - a bare `manifest.json` 404s
("`No file was found at "manifest.json"`"). The `.aar` itself is an opaque, proprietary archive format -
neither `unzip` nor `tar` can open it to check this directly, so this was confirmed by fixing the path and
re-testing, not by inspecting the file. Matches the header doc's own description of the shared namespace as
containing "subdirectories and asset files" from each pack, not a flattened file list.

**Real device vs. simulator isn't one clean line.** Calling `AssetPackManager` directly from app code
(`assetPack(withID:)`, `ensureLocalAvailability(of:)`) is what actually exercised every validation error
above, regardless of which target was running. What specifically needs a real, physical device:
`backgroundassets-debug`'s device list (`--list-devices`) only ever surfaced a real paired iPhone, never the
simulator, so the install/update-event *trigger* simulation this tool provides is real-device-only. And
critically, testing against genuine network reachability needs a real device for a reason that has nothing
to do with Background Assets itself: `127.0.0.1` means "this same machine" - on the simulator that's the
Mac, correctly reaching a locally-hosted manifest; on a real device it's the phone itself, which will never
reach anything. A local manifest server for real-device testing has to be bound to the Mac's actual LAN IP,
not loopback.

**Local self-hosted testing recipe, worth reusing for Orihime later:** `ba-package download-manifest
create` (already covered in <doc:V02Artifact>) generates the real manifest; Python's `http.server` needs a
small `ssl.SSLContext` wrapper to serve it over HTTPS at all (no built-in TLS support); `mkcert` issues a
cert covering both `127.0.0.1` and the Mac's LAN IP in one file, trusted automatically on the Mac once
`mkcert -install` runs. The one commonly-missed step for a **real device**: AirDropping the CA root and
installing it as a configuration profile (Settings → General → VPN & Device Management) is necessary but
not sufficient - trust has to be separately enabled on a completely different screen (Settings → General →
About → Certificate Trust Settings), which most walkthroughs don't call out as a distinct step from
installing the profile itself.

**The picker's model list is static, not pulled live from the manifest - now built, not just decided.**
`RecommendationModelOption.all` is one entry per `RecommenderService` this app actually ships an adapter
for (today: Protostar alone), not a mirror of `AssetPackManager.shared.allAssetPacks`. Two reasons, both
concrete now that the picker exists: a pack the app has no loader for is not a usable option no matter how
it's listed, and the manifest format itself (`{id, downloadPolicy, downloadSize, host, url, version}`)
carries no display name or description to show a reader anyway - a "dynamic" list would still need a
static app-side lookup for presentable text, which defeats the point of being dynamic. The working
reference implementation (`Screens/Settings/RecommendationsViewModel.swift`) is the real API surface a
picker needs: `status(ofAssetPackWithID:)` for the current state, `statusUpdates(forAssetPackWithID:)` for
live progress (a long-running per-pack watcher, not a one-shot poll), `ensureLocalAvailability(of:)` to
trigger a download, `remove(assetPackWithID:)` for the delete button. Verified on a real device end to end
through the actual Settings UI, not just the Bootstrap probe.

**The Bootstrap.swift DEBUG probe has been removed.** Its comment said "delete once the Settings picker
replaces it" - that picker now exists and was what verified the download/remove flow above, so it was
redundant scaffolding pointing at the same hardcoded pack id the real feature also depends on.

**Two real bugs found only by running the shipped picker, not by reading any doc.** Downloading Protostar
through Settings and opening a `Details` screen surfaced both:

- `ModelBundle.load` read only `Bundle.main` - the same shape it always had, from when v01 shipped bundled
  inside the app. That bundle is empty in every build now (`Resources/Models` is gitignored and deleted),
  so recommendations were silently broken from the moment the bundled model was removed until this was
  found - nothing wired the Background Assets download to the thing that actually reads model files.
  Fixed by giving `ModelBundle.load(from:)` a `Source` (`.appBundle`, dev/preview only, vs. `.assetPack(id:root:)`),
  reading through `AssetPackManager.shared.contents(at:searchingInAssetPackWithID:options:.mappedIfSafe)`
  for the real path - the same `.mappedIfSafe` behavior as the bundle path, so construction stays nearly
  free either way.
- `TagVocabulary.init` had its own, separate `Bundle.main.url(forResource:)` call for `tagvocab.json` -
  a second load site that fixing `ModelBundle` alone didn't touch, caught by the very next error in the
  log (`malformed(file: "tagvocab.json", reason: "not in the bundle")`) once the first bug's fix let
  everything else load. `tagvocab.json` isn't declared in either manifest's `files` dict (it's a flat
  dictionary, not a typed array), so it never entered `ModelBundle`'s normal per-name loop - it needed its
  own explicit read, now folded into `ModelBundle.load` and handed to `TagVocabulary` as `bundle.tagVocabularyData`.

**The model switch is restart-required, not live - a second, deliberate reversal.** The first working
version swapped the active model mid-session: `switchActive(to:)` built a new adapter, warmed it, and
replaced the running one, no relaunch needed. Reconsidered once traced against a concrete flow (a fresh
install picking a pack for the first time) and simplified to the actual "game language pack" shape the
original request described - those normally take effect on next launch, not live. The app has no clean way
to page a 116 MB model back out of memory once loaded, and a live swap risked warming a new one on whatever
screen happened to be open when the reader tapped. `Compositor.recommendationsService`
(`RecommendationsService`, renamed from an earlier `RecommenderRouter`) now tracks two ids instead of one:
`selectedPackId` (the reader's persisted choice, written the instant a pack is downloaded or picked) and
`loadedPackId` (whichever pack this process actually built a scorer for, decided once at cold start and
never changed mid-session). `select()` is pure bookkeeping now - persist the choice, nothing else - and
when the two ids disagree, a root-level alert (`Main.swift`, driven by `pendingRestartUpdates`, an
`AsyncStream` matching the same reactive shape used elsewhere in this app) tells the reader a restart is
needed. iOS gives an app no way to relaunch itself, so both alert buttons just dismiss - the copy tells the
reader what to do, nothing here automates it. Until that restart happens, recommendations keep working off
whichever pack was already loaded (nothing, on a fresh install) - the existing graceful "an addition to a
screen, never load-bearing" degrade, unchanged.

**`RecommenderRouter.init` no longer guesses an active pack.** The first version defaulted to
`options.first?.packId` when nothing was persisted, so a fresh install showed Protostar as "Active" before
it was ever downloaded - found by tracing the exact fresh-install flow, not by a report. Fixed by dropping
the fallback entirely: no persisted `UserDefaults` selection means no active model at all, so
`isDownloaded`/`isActive` read false together and Settings correctly offers Download.

**Compositor.SeriesRecommendations was renamed to Compositor.Recommendations**, matching `DetailsComposer.Recommendations`'s
naming on the presentation side - purely cosmetic, no behavior change.

## Where it surfaces

Unchanged from v01: Details' "Similar Titles" rail is still the surface, still per-open rather than
precomputed or scheduled. What changes is invisible to the reader on a resolved seed and, once the compute
path lands, mostly invisible on an unresolved one too - the difference is a roughly one-second wait
(cached after the first time) rather than an empty section. The picker itself is new Settings surface,
scoped separately from this page.
