//
//  AppLog.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation
import os

// every line the app writes about itself, to three places at once: a file that
// survives the process, any screen currently watching, and os.Logger for the
// Xcode console.
//
// the file is the reason this exists. OSLogStore on iOS can only read the
// CURRENT process - there is no scope for a previous launch - so a crash takes
// its own explanation with it unless something wrote to disk on the way past.
//
// it replaced a 500-entry in-memory ring buffer that nothing ever read.
//
// the intake stream is not decoration. actor calls are not FIFO, so a
// `Task { await write(line) }` per call races: the lines arrive in whatever
// order the executor picks, which for a log is the one property that matters.
// AsyncStream.Continuation.yield is synchronous, thread-safe and ordered, so
// the public call is a yield and one drain task is the only writer
actor AppLog {
    nonisolated static let shared = AppLog()

    struct Entry: Identifiable, Sendable {
        let id = UUID()
        let date: Date
        let level: Level
        let category: String
        let message: String

        var line: String {
            "\(date.formatted(.iso8601.time(includingFractionalSeconds: true))) [\(level.mark)] [\(category)] \(message)"
        }
    }

    // written at every call site, so it defaults - 60-odd existing lines say
    // what happened without grading it, and most of them are genuinely .info
    enum Level: String, Sendable, CaseIterable {
        case debug, info, warning, error

        // fixed width, so the category column lines up down the file. the level
        // is the thing a person scans for first and a ragged left edge is what
        // stops them
        var mark: String {
            switch self {
            case .debug: "DBG"
            case .info: "INF"
            case .warning: "WRN"
            case .error: "ERR"
            }
        }
    }

    private nonisolated let intake: AsyncStream<Entry>
    private nonisolated let feed: AsyncStream<Entry>.Continuation

    // each live reader gets its own continuation: an AsyncStream has exactly one
    // consumer, so a shared one would deliver each line to whichever screen
    // happened to be waiting
    private var readers: [UUID: AsyncStream<Entry>.Continuation] = [:]

    private var handle: FileHandle?

    private let mirror = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? Constants.App.identifier,
        category: "app"
    )

    private enum Rotation {
        // one rotation kept, so the ceiling is 10 MB and a crash still has the
        // run before it to read
        static let limit: UInt64 = 5 * 1024 * 1024
        static let current = "aletheia.log"
        static let previous = "aletheia.1.log"
    }

    private nonisolated var current: URL { Constants.Paths.logs.appending(path: Rotation.current) }
    private nonisolated var previous: URL {
        Constants.Paths.logs.appending(path: Rotation.previous)
    }

    private init() {
        (intake, feed) = AsyncStream.makeStream(of: Entry.self, bufferingPolicy: .unbounded)
    }

    // called once at launch rather than from init: a task spawned inside an
    // actor's initialiser captures self before initialisation has finished, and
    // the unbounded buffer means nothing logged before this call is lost - it is
    // held and written the moment the drain begins
    nonisolated func start() {
        Task { await drain() }
    }

    // MARK: Writing

    // synchronous and callable from anywhere, which is what every existing call
    // site already assumes. the signature is unchanged from the version this
    // replaced, so `level` had to be the parameter that defaults
    nonisolated func log(_ message: String, level: Level = .info, category: String = "app") {
        feed.yield(Entry(date: .now, level: level, category: category, message: message))
    }

    private func drain() async {
        open()

        for await entry in intake {
            append(entry)
            for reader in readers.values { reader.yield(entry) }
            echo(entry)
        }
    }

    private func open() {
        let manager = FileManager.default
        let path = current.path(percentEncoded: false)

        if !manager.fileExists(atPath: path) {
            manager.createFile(atPath: path, contents: nil)
        }

        handle = try? FileHandle(forWritingTo: current)
        _ = try? handle?.seekToEnd()
    }

    private func append(_ entry: Entry) {
        rotate()
        try? handle?.write(contentsOf: Data((entry.line + "\n").utf8))
    }

    private func rotate() {
        guard let size = try? handle?.offset(), size > Rotation.limit else { return }

        try? handle?.close()
        handle = nil

        let manager = FileManager.default
        try? manager.removeItem(at: previous)
        try? manager.moveItem(at: current, to: previous)

        open()
    }

    private func echo(_ entry: Entry) {
        // the interpolation is public on purpose: os.Logger redacts string
        // arguments by default, and a log the developer cannot read is not one
        switch entry.level {
        case .debug:
            mirror.debug("[\(entry.category, privacy: .public)] \(entry.message, privacy: .public)")
        case .info:
            mirror.info("[\(entry.category, privacy: .public)] \(entry.message, privacy: .public)")
        case .warning:
            mirror.warning(
                "[\(entry.category, privacy: .public)] \(entry.message, privacy: .public)")
        case .error:
            mirror.error("[\(entry.category, privacy: .public)] \(entry.message, privacy: .public)")
        }
    }

    // MARK: Reading

    // oldest first, both files, so a crash and the run that led to it read in
    // one direction
    func history() -> [String] {
        [previous, current]
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .flatMap { $0.split(separator: "\n", omittingEmptySubsequences: true) }
            .map(String.init)
    }

    // from the moment of subscription. a reader that goes away terminates its
    // own stream, which is what removes it here - nothing has to remember to
    func live() -> AsyncStream<Entry> {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: Entry.self, bufferingPolicy: .unbounded)

        readers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.release(id) }
        }

        return stream
    }

    private func release(_ id: UUID) {
        readers[id] = nil
    }

    // MARK: Export

    // both halves, oldest first, and only the ones that exist - sharing the live
    // url alone hands over the current file, which after a rotation is the part
    // that does NOT contain what went wrong. no snapshot is written: these are
    // the real files, so exporting costs nothing and cannot go stale
    nonisolated func files() -> [URL] {
        [previous, current].filter {
            FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        }
    }

    func clear() {
        try? handle?.close()
        handle = nil

        let manager = FileManager.default
        try? manager.removeItem(at: current)
        try? manager.removeItem(at: previous)

        open()
    }
}
