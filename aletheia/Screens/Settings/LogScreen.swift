//
//  LogScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 13/8/2026.
//

import SwiftUI

struct LogScreen: View {
    @State private var entries: [Row] = []
    @Environment(\.dimensions) private var dimensions

    @State private var level: AppLog.Level?
    @State private var category: String?
    @State private var query = ""
    @State private var clearing = false
    @State private var loaded = false

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

        // parses AppLog's fixed "[level] [category]" line format
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
        static let selectedFill: Double = 0.15
        static let restingFill: Double = 0.06
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label(loaded ? "No Logs" : "Reading Logs", systemImage: "text.alignleft")
                } description: {
                    Text(
                        loaded
                            ? "Nothing has been recorded since the log was last cleared."
                            : "One moment.")
                }
            } else if visible.isEmpty {
                ContentUnavailableView {
                    Label("No Matches", systemImage: "line.3.horizontal.decrease")
                } description: {
                    Text(
                        "^[\(entries.count) line](inflect: true) recorded, none matching this filter."
                    )
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
        .safeAreaInset(edge: .top, spacing: 0) {
            if !entries.isEmpty { Filters }
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
            Text(
                "Removes every line on disk, including the previous launch. This cannot be undone.")
        }
        // a line logged between history() and live() starting is missed; accepted, not a bug
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
                // includes the rotated file - the half worth reading after a crash
                ShareLink(items: AppLog.shared.files()) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Button("Clear", systemImage: "trash", role: .destructive) { clearing = true }
            } label: {
                Label("Options", systemImage: "ellipsis")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
        }
    }

    // MARK: Filters

    private var Filters: some View {
        VStack(spacing: dimensions.spacing.space8) {
            Rail {
                Chip("All", count: entries.count, active: level == nil, tint: .brand) {
                    level = nil
                }
                ForEach(AppLog.Level.allCases, id: \.self) { value in
                    let n = counts.levels[value] ?? 0
                    Chip(
                        value.rawValue.capitalized, count: n,
                        active: level == value, tint: tint(value)
                    ) {
                        level = level == value ? nil : value
                    }
                    .disabled(n == 0)
                    .opacity(n == 0 ? 0.4 : 1)
                }
            }

            if categories.count > 1 {
                Rail {
                    Chip("All", count: entries.count, active: category == nil, tint: .brand) {
                        category = nil
                    }
                    ForEach(categories, id: \.self) { value in
                        Chip(
                            value, count: counts.categories[value] ?? 0,
                            active: category == value, tint: .brand
                        ) {
                            category = category == value ? nil : value
                        }
                    }
                }
            }
        }
        .padding(.horizontal, dimensions.screenMargin)
        .padding(.vertical, dimensions.spacing.space8)
        .background(.bar)
    }

    // negative outer padding puts the inset inside the scroll view, so the first
    // chip starts at the screen margin but the last can still scroll clear of it
    private func Rail<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: dimensions.spacing.space8) {
                content()
            }
            .padding(.horizontal, dimensions.screenMargin)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .padding(.horizontal, -dimensions.screenMargin)
    }

    private func Chip(
        _ title: String, count: Int, active: Bool,
        tint: Color, action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: dimensions.spacing.space4) {
            Text(title)
                .fontWeight(active ? .semibold : .medium)
                .lineLimit(1)

            Text("\(count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if active {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
            }
        }
        .font(.subheadline)
        .padding(.horizontal, dimensions.spacing.space12)
        .frame(height: dimensions.touchTarget)
        .background(
            active
                ? AnyShapeStyle(tint.opacity(Layout.selectedFill))
                : AnyShapeStyle(.primary.opacity(Layout.restingFill)),
            in: .capsule
        )
        .foregroundStyle(active ? AnyShapeStyle(tint) : AnyShapeStyle(.primary))
        .contentShape(.capsule)
        .tappable(action: action)
    }

    // counted over every entry rather than the visible set, so a chip's number
    // does not move while the search field is being typed into
    private var counts: (levels: [AppLog.Level: Int], categories: [String: Int]) {
        var levels: [AppLog.Level: Int] = [:]
        var categories: [String: Int] = [:]
        for row in entries {
            if let value = row.level { levels[value, default: 0] += 1 }
            if let value = row.category { categories[value, default: 0] += 1 }
        }
        return (levels, categories)
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

    private func tint(_ level: AppLog.Level?) -> Color {
        switch level {
        case .error: .dangerText
        case .warning: .warningText
        case .debug: .muted
        default: .textPrimary
        }
    }
}
