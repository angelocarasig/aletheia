//
//  SourcesViewModel.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI
import GRDB
import Observation

@MainActor
@Observable
final class SourcesViewModel {
    private let database: DatabaseClient
    // adultOnly is a descriptor fact, not a column - the row cannot answer it
    private let registry: Compositor.Registry
    private var task: Task<Void, Never>?

    private(set) var sources: [SourceRecord] = []

    // while false, adultOnly sources are absent from every section rather than
    // sunk or badged - absence is the whole gate
    var bypassAdult = Preferences.Default.bypassAdultSources

    private var visible: [SourceRecord] {
        bypassAdult ? sources : sources.filter { !isAdult($0) }
    }

    var pinned: [SourceRecord] { ordered(visible.filter { $0.pinned && !$0.disabled }) }
    var active: [SourceRecord] { ordered(visible.filter { !$0.pinned && !$0.disabled }) }
    var disabled: [SourceRecord] { ordered(visible.filter(\.disabled)) }

    init(database: DatabaseClient, registry: Compositor.Registry) {
        self.database = database
        self.registry = registry
    }

    // adult sources sink to the bottom of whichever section they are in, rather
    // than to the bottom of the screen - a pinned adult source is still pinned,
    // and moving it out of its section would be overriding a choice you made
    private func ordered(_ records: [SourceRecord]) -> [SourceRecord] {
        records.sorted { lhs, rhs in
            let left = isAdult(lhs)
            let right = isAdult(rhs)

            guard left == right else { return !left }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func isAdult(_ record: SourceRecord) -> Bool {
        registry.source(slug: record.slug)?.descriptor.adultOnly == true
    }
    
    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            for await records in observe() {
                withAnimation(.smooth) { self.sources = records }
            }
        }
    }
    
    func stop() {
        task?.cancel()
        task = nil
    }
    
    func togglePinned(_ record: SourceRecord) {
        setPinned(!record.pinned, for: record)
    }
    
    func toggleDisabled(_ record: SourceRecord) {
        setDisabled(!record.disabled, for: record)
    }
    
    func setPinned(_ pinned: Bool, for record: SourceRecord) {
        update(slug: record.slug, field: .pinned, value: pinned)
    }
    
    func setDisabled(_ disabled: Bool, for record: SourceRecord) {
        update(slug: record.slug, field: .disabled, value: disabled)
    }
    
    private enum Field {
        case pinned, disabled
        
        var column: Column {
            switch self {
            case .pinned: SourceRecord.Columns.pinned
            case .disabled: SourceRecord.Columns.disabled
            }
        }
    }
    
    private func update(slug: String, field: Field, value: Bool) {
        let writer = database.writer
        Task {
            do {
                try await writer.write { db in
                    _ = try SourceRecord
                        .filter(SourceRecord.Columns.slug == slug)
                        .updateAll(db, field.column.set(to: value))
                }
            } catch {
                AppLog.shared.log("source update failed (\(slug)) — \(error)", category: "sources")
            }
        }
    }
    
    private func observe() -> AsyncStream<[SourceRecord]> {
        let reader = database.reader
        
        return AsyncStream { continuation in
            // uninstalled rows are kept so a series can still name the source it
            // came from, but there is nothing here to browse or pin
            let observation = ValueObservation.tracking { db in
                try SourceRecord
                    .filter(SourceRecord.Columns.installed == true)
                    .order(SourceRecord.Columns.slug)
                    .fetchAll(db)
            }
            
            let cancellable = observation.start(
                in: reader,
                onError: { _ in continuation.finish() },
                onChange: { continuation.yield($0) }
            )
            
            continuation.onTermination = { _ in cancellable.cancel() }
        }
    }
}
