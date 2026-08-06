//
//  AppLog.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation
import Observation

@MainActor
@Observable
final class AppLog {
    nonisolated static let shared = AppLog()

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let category: String
        let message: String
    }

    private(set) var entries: [Entry] = []

    nonisolated init() {}

    nonisolated func log(_ message: String, category: String = "app") {
        let date = Date()
        print("\(date.formatted(.iso8601.time(includingFractionalSeconds: true))) [\(category)] \(message)")
        Task { @MainActor in
            entries.append(Entry(date: date, category: category, message: message))
            if entries.count > 500 {
                entries.removeFirst(entries.count - 500)
            }
        }
    }

    func clear() {
        entries.removeAll()
    }
}
