//
//  LogScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 13/8/2026.
//

import SwiftUI

// what the app has said about itself, this launch and the one before it. the
// point is the launch before: a crash takes its own explanation with it unless
// something wrote to disk on the way past, and this is where that file is read
struct LogScreen: View {
    @State private var entries: [Row] = []
    @State private var level: AppLog.Level?
    @State private var category: String?
    @State private var query = ""
    @State private var clearing = false
    @State private var loaded = false

    // history arrives as text and live arrives as entries, so both are flattened
    // to the one shape the list draws. the id is positional because a replayed
    // line from the file has no identity of its own to carry
    private struct Row: Identifiable {
        let id: Int
        let text: String
        let level: AppLog.Level?
        let category: String?

        init(id: Int, text: String, level: AppLog.Level?, category: String?) {
            self.id = id
            self.text = text
            self.level = level
            self.category = category
        }

        // a replayed line is text, and its level and category are the two
        // fields the filters need back out of it. the format is ours and fixed,
        // so this reads the two bracketed fields rather than matching the line
        init(text: String, at index: Int) {
            let fields = text.split(separator: "[").dropFirst().prefix(2).map {
                $0.prefix { $0 != "]" }.trimmingCharacters(in: .whitespaces)
            }

            self.init(
                id: index,
                text: text,
                level: fields.first.flatMap { mark in
                    AppLog.Level.allCases.first { $0.mark == mark }
                },
                category: fields.count > 1 ? fields[1] : nil
            )
        }
    }

    private enum Layout {
        static let tail = 2000
        static let rowInset: CGFloat = 8
        static let rowSpacing: CGFloat = 2
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label(loaded ? "No Logs" : "Reading Logs", systemImage: "text.alignleft")
                } description: {
                    Text(loaded
                         ? "Nothing has been recorded since the log was last cleared."
                         : "One moment.")
                }
            } else if visible.isEmpty {
                ContentUnavailableView {
                    Label("No Matches", systemImage: "line.3.horizontal.decrease")
                } description: {
                    Text("^[\(entries.count) line](inflect: true) recorded, none matching this filter.")
                } actions: {
                    Button("Clear Filters") {
                        level = nil
                        category = nil
                        query = ""
                    }
                }
            } else {
                Lines
            }
        }
        .animation(.settle, value: visible.count)
        .navigationTitle("Logs")
        .navigationBarTitleDisplayMode(.inline)
        .navigationSubtitle(subtitle)
        .searchable(text: $query, prompt: "Search logs")
        .toolbar { Toolbar }
        .alert("Clear Logs?", isPresented: $clearing) {
            Button("Clear", role: .destructive) {
                Task {
                    await AppLog.shared.clear()
                    entries = []
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes every line on disk, including the previous launch. This cannot be undone.")
        }
        // history first, then live, and the gap between them is accepted: a line
        // logged in that window is missed. it is a debug tool, and closing the
        // gap costs a de-dupe pass on every entry forever
        .task {
            let history = await AppLog.shared.history()
            entries = history.suffix(Layout.tail).enumerated().map { index, text in
                Row(text: text, at: index)
            }
            loaded = true

            for await entry in await AppLog.shared.live() {
                entries.append(
                    Row(
                        id: (entries.last?.id ?? -1) + 1,
                        text: entry.line,
                        level: entry.level,
                        category: entry.category
                    )
                )
                if entries.count > Layout.tail { entries.removeFirst(entries.count - Layout.tail) }
            }
        }
    }

    // MARK: Lines

    private var Lines: some View {
        ScrollViewReader { proxy in
            List(visible) { row in
                Text(row.text)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(tint(row.level))
                    .textSelection(.enabled)
                    .listRowInsets(
                        EdgeInsets(
                            top: Layout.rowSpacing,
                            leading: Layout.rowInset,
                            bottom: Layout.rowSpacing,
                            trailing: Layout.rowInset
                        )
                    )
                    .id(row.id)
            }
            .listStyle(.plain)
            // a log reads newest-last, so a new line arriving off the bottom is
            // the one thing worth following
            .onChange(of: visible.last?.id) { _, last in
                guard let last else { return }
                withAnimation { proxy.scrollTo(last, anchor: .bottom) }
            }
            .onAppear {
                guard let last = visible.last?.id else { return }
                proxy.scrollTo(last, anchor: .bottom)
            }
        }
    }

    @ToolbarContentBuilder
    private var Toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Level", selection: $level) {
                    Text("All Levels").tag(AppLog.Level?.none)
                    ForEach(AppLog.Level.allCases, id: \.self) { value in
                        Text(value.rawValue.capitalized).tag(AppLog.Level?.some(value))
                    }
                }

                if !categories.isEmpty {
                    Picker("Category", selection: $category) {
                        Text("All Categories").tag(String?.none)
                        ForEach(categories, id: \.self) { value in
                            Text(value).tag(String?.some(value))
                        }
                    }
                }

                Divider()

                // both files, not one: sharing only the live half hands over
                // everything EXCEPT the rotated part, which after a crash is
                // the half worth reading
                ShareLink(items: AppLog.shared.files()) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Button("Clear", systemImage: "trash", role: .destructive) { clearing = true }
            } label: {
                Label("Options", systemImage: filtering ? "line.3.horizontal.decrease.circle.fill" : "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
    }

    // MARK: Filtering

    private var visible: [Row] {
        entries.filter { row in
            if let level, row.level != level { return false }
            if let category, row.category != category { return false }
            if !query.isEmpty, !row.text.localizedCaseInsensitiveContains(query) { return false }
            return true
        }
    }

    private var categories: [String] {
        Array(Set(entries.compactMap(\.category))).sorted()
    }

    private var filtering: Bool {
        level != nil || category != nil
    }

    private var subtitle: Text {
        if filtering || !query.isEmpty {
            Text("\(visible.count) of ^[\(entries.count) line](inflect: true)")
        } else {
            Text("^[\(entries.count) line](inflect: true)")
        }
    }

    // error and warning earn a colour; the rest stay monochrome, or a screen
    // that is entirely coloured text says nothing by colouring any of it
    private func tint(_ level: AppLog.Level?) -> Color {
        switch level {
        case .error: .dangerText
        case .warning: .warningText
        case .debug: .muted
        default: .textPrimary
        }
    }
}
