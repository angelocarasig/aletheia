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
    private var task: Task<Void, Never>?
    
    private(set) var sources: [SourceRecord] = []
    
    var pinned: [SourceRecord] { sources.filter { $0.pinned && !$0.disabled } }
    var active: [SourceRecord] { sources.filter { !$0.pinned && !$0.disabled } }
    var disabled: [SourceRecord] { sources.filter(\.disabled) }
    
    init(database: DatabaseClient) {
        self.database = database
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
