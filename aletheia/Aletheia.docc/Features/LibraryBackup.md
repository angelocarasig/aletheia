# Library Backup

The file format behind Settings > Data & Storage > Backup & Storage - exporting and restoring a
whole library from a portable file. `Screens/Backup/`.

Distinct from CBZ export: this backup carries library state - series, progress, links - never
downloaded chapter content. The two are separate features with separate scopes.

## Why not a raw database dump

A copy of the GRDB file would be near-zero effort, but it's tied to the live schema (a future
migration could break restoring an old backup unless the whole migration chain stays
restore-compatible forever), local rowids are meaningless on another install and would still need
a translation layer, and it carries device-local junk (cached file paths, error strings, WAL
internals) that shouldn't leave the device unfiltered. A structured, versioned format avoids all
three.

## Envelope

``LibraryBackupEnvelope`` wraps a small uncompressed header around a compressed payload, so the
header is readable without first committing to decompressing something this build might not
understand:

```
[4 bytes] magic:        "ALTH"
[2 bytes] version:      UInt16, big-endian
[4 bytes] originalSize: UInt32, big-endian (zlib's uncompress needs the output size up front)
[N bytes] zlib-deflated LibraryBackup protobuf message
```

`version` is the schema version of the protobuf message that follows, not the app version - it's
bumped only for changes protobuf's own wire compatibility can't absorb. The app version travels
inside the payload itself as an informational field, never used for compatibility decisions.

Reading a version newer than this build understands fails closed - no partial or best-effort
decode. The same "an opt-in must always have a working else" discipline that governs source
capabilities (<doc:aletheia/SourceProtocols>) applies here: there's no working else for a payload shape
this build has never seen.

## Message shape

Portable identity throughout - source slug plus series slug, tag/author/collection names, never a
local rowid. The same identity model `MigrationEntry`-conforming types already use elsewhere: an
import is a create-or-attach pass, not a row-for-row restore.

```protobuf
message LibraryBackup {
  string exported_by_app_version = 1;
  int64 exported_date = 2;
  repeated SeriesEntry series = 3;

  message SeriesEntry {
    string preferred_title = 1;
    string status = 2;
    int64 added_date = 3;
    int64 last_read_date = 4;
    string orientation = 5;
    bool show_all_chapters = 6;
    bool show_half_chapters = 7;
    repeated OriginEntry origins = 8;
    repeated string tags = 9;
    repeated string authors = 10;
    repeated string collections = 11;
    repeated TrackerLink tracker_links = 12;
    optional int64 catalog_id = 13;  // advisory only - see below
  }
}
```

`OriginEntry` carries source slug, series slug, priority, and the full chapter list per origin.
`ChapterEntry` carries the whole row, not just progress - a restore must not depend on the source
still carrying the same chapter list later, so title, url, language, scanlator, both dates, and
progress all round-trip. Only local-only fields (id, origin id, a downloaded file's path) stay
out. `TrackerLink` carries the full `SeriesTrackerRecord` snapshot rather than just enough to
identify the link - that row is deliberately denormalized so it renders fully with zero network
access when the reader is signed out (see <doc:aletheia/Trackers>), and restoring only identity fields
would bring back a link that shows blank until the next sync.

Covers, synopsis, classification, and publication stay out of the payload entirely - those come
back through the normal metadata refresh path once an origin exists, the same as any newly
attached source. `catalog_id` is advisory only: the model bundle a restore lands on may not be the
one the backup was exported from, and a miss there is read the same as never-resolved, not an
error.

## Versioning discipline

Two layers. **Wire-level** is protobuf's own rules and needs no version bump: field numbers are
permanent identity, never reused or retyped, only ever added to, and a dropped field's number is
reserved rather than reassigned. An old payload keeps decoding correctly against a newer schema
under this discipline alone. **Semantic-level** is an explicit version bump plus a decode-and-adapt
path, for anything wire compatibility can't absorb - a field's meaning changing, a value moving
between messages. The same append-only rule that governs the live database schema (<doc:aletheia/Schema>)
applies here: a shipped version's decode path is never edited once it's shipped, a new version
gets a new adapter, and the envelope's `version` field selects which adapter runs.

## Import reuses the migration framework

Restoring a backup isn't a bespoke commit chain - it's mostly the same pieces `Screens/Migrations/`
already has, wired to a new entry source. A source still installed with an exact slug match
attaches directly with no search; a source no longer installed falls back to the same
search-and-pick queue flow other migrations use, so a missing source becomes a queued row rather
than a hard failure. Chapters seed the same shape a live chapter fetch already writes. Series-level
state (`inLibrary`, the real `addedDate` from the payload rather than "now") is its own write,
since reusing the ordinary add-to-library path would stamp every restored series with the same
instant and break both library sort-by-added and the Home new-chapters feed, which gates on a
chapter's published date being after the series' added date. Tracker links write directly as a
`SeriesTrackerRecord` insert rather than through a live link call, since that call requires the
device already being signed in - "linked but not signed in" is already a first-class rendered
state (<doc:aletheia/Trackers>), so restore lands there directly instead of forcing a login. Tags and
authors resolve by `findOrCreate`; collections need their own case-insensitive lookup-then-create,
since `CollectionRecord` carries no uniqueness constraint anywhere else in the codebase.
