# Schema

How a table is named, shaped, and wired into ``DatabaseClient``.

## Migrations

The v1 schema (`registerV1_0_0` for tables, `registerV1_0_1` for indexes, both in
`Database/Migrations/Migrations.swift`) is closed:

- **Never edit `registerV1_0_0` or `registerV1_0_1`**, and never change what an existing record's
  `createTable`/`createIndexes` produces. Their checksums are what a shipped database migrates
  against.
- A new column, table, view, or index is a **new** migration - `registerV1_0_2` and onward - doing
  its own `ALTER TABLE` / `CREATE`, registered in `Migrations.register`.
- A new record type still owns its `createTable` and still joins ``DatabaseClient/allRecords``, so
  a fresh install builds it in v1.0.0. An existing install only gets it from the new migration, so
  **both paths have to be written and have to agree**.
- Dropping or renaming a column is a table rebuild, not an edit. Flag it as such.
- `eraseDatabaseOnSchemaChange` is deliberately off in DEBUG (`Database/Client.swift`) - a changed
  checksum on a closed migration throws at launch instead of being silently absorbed by a wipe. If
  it throws, something edited a closed migration.

## Naming

| Thing | Convention | Examples |
|---|---|---|
| table | lowercase; snake_case for multiword | `series`, `reading_event` |
| record struct | PascalCase + `Record` | ``SeriesRecord``, ``OriginRecord`` |
| view struct | PascalCase + `View` | ``BestChapterView``, ``RichfulEntryView`` |
| columns | camelCase | `seriesId`, `localDayKey` |
| date columns | **`*Date` suffix - never `*At`** | `addedDate`, `publishedDate`, `lastReadDate` |

## The canonical record shape

Mirror an existing record such as ``SeriesRecord`` or ``OriginRecord``:

```swift
struct FooRecord: Codable, DatabaseRecord {           // + UniqueRecord for find-or-create; + Hashable if needed
    typealias ID = Tagged<Self, Int64>
    private(set) var id: ID?                           // autoincrement rowid
    private(set) var barId: BarRecord.ID                // FK: typed as the other record's .ID
    var title: String                                   // own fields
    var addedDate: Date = .distantPast                  // timestamps LAST, *Date suffix
}

extension FooRecord {
    static var databaseTableName: String { "foo" }
    enum Columns { static let id = Column(CodingKeys.id) /* one per stored field, id/FKs first */ }
    static func createTable(db: Database) throws { }    // fresh-install DDL. Record owns it.
    static func createIndexes(db: Database) throws { }  // fresh-install indexes only
    mutating func didInsert(_ inserted: InsertionSuccess) { id = ID(rawValue: inserted.rowID) }
}

extension FooRecord {                                   // associations in their own extension
    static let bar = belongsTo(BarRecord.self)
    var bar: QueryInterfaceRequest<BarRecord> { request(for: FooRecord.bar) }
}
```

## Rules

- **Primary keys are `Tagged<Self, Int64>` autoincrement rowids** - not UUIDs, not `String`, except
  where a natural key is required (``SourceRecord``'s `slug` is the code-stable string key
  alongside its `Int64` id). `GRDB+Tagged.swift` bridges `Tagged` to GRDB column types.
- **Foreign key columns are typed with the target's `.ID`** and are `private(set)`.
- **Date columns use the `*Date` suffix** and a sentinel convention: `NOT NULL` with `.distantPast`
  meaning "never" (``SeriesRecord``'s `addedDate`), or nullable with `NULL` meaning "never"
  (``ChapterRecord``'s `lastReadDate` - the schema's one nullable date). Pick per column,
  deliberately; any UNION-shaped recency query has to handle both.
- Enums store as `.text` (the `String` raw value). `URL` stores as `.text`. Arrays and other
  `Codable` collections store as `.blob`.
- **Foreign key delete rules**: default `.cascade` `NOT NULL`; `origin.sourceId` is nullable
  `.setNull` (a "disconnected" origin); `tag.canonicalId` is a self-reference `.setNull`;
  `chapter.scanlatorId` is the schema's only `.restrict`.
- ``UniqueRecord`` adds a `uniqueFilter(for:)` requirement and a default `findOrCreate(_:in:)` -
  the upsert-by-natural-key idiom, used by lookup/junction records like `Scanlator`, `Author`, and
  `Tag`.
- **Struct body order**: `id` (only if overriding) -> foreign keys -> fields -> timestamps ->
  associations -> `init`.
- New records join ``DatabaseClient/allRecords`` in **dependency order** (foreign key targets
  before referrers); views likewise in `allViews`.
- Inside a `read`/`write` closure, pass the `db` handle into any nested call rather than opening
  a new one.
- Raw SQL is confined to migrations, view definitions, and the FTS5 view; everything else goes
  through the query interface.
- Metric queries go flat against base tables rather than through a view. See <doc:Metrics>.

## History tables carry no foreign keys

``ReadingEventRecord`` and `ReadingSessionRecord` are the schema's deliberate exception to the
foreign key convention: their `seriesId` column carries no FK constraint, and they snapshot data
that would otherwise only live behind the join (`seriesTitle` beside `seriesId`). Both available
cascade rules are wrong for a history log - `.cascade` erases history on the launch purge,
`.setNull` blanks what a row refers to - and a series id isn't even stable, since merge/attach
hard-deletes the losing row. Joins from history back to `series` are best-effort; the snapshot is
what keeps a row readable when the join fails.
