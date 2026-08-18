//
//  LibraryFilterSheet.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import SwiftUI

struct LibraryFilterSheet: View {
    @Binding var filter: LibraryFilter
    var tags: [LibraryViewModel.Option<TagRecord.ID>] = []
    var sources: [LibraryViewModel.Option<SourceRecord.ID>] = []
    var trackers: [TrackerFilter] = []

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    private enum Motion {
        static let settle: Animation = .snappy(duration: 0.28)
        static let chip: AnyTransition = .scale(scale: 0.85).combined(with: .opacity)
    }

    // the title string doubles as the key `expanded` is toggled by - a literal
    // used in two places could drift out of sync
    private enum Titles {
        static let progress = "Progress"
        static let status = "Reading Status"
        static let publication = "Publication"
        static let rating = "Rating"
        static let tags = "Tags"
        static let sources = "Sources"
        static let trackers = "Tracking"
    }

    private enum Threshold {
        static let searchable = 15
        // FlowLayout measures every child handed to it, so the cut happens before
        // it, not inside it
        static let shown = 60
    }

    // by title, not index - a conditionally hidden group (tags/sources/trackers
    // can be absent) would shift indices and expand the wrong row
    @State private var expanded: Set<String> = []

    @State private var searches: [String: String] = [:]

    // Text, not String - coercing this to String would print the inflection
    // markup literally instead of rendering it
    private var subtitle: Text {
        if filter.isActive {
            Text("^[\(filter.count) filter](inflect: true) applied")
        } else {
            Text("Showing everything")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    Group(
                        Titles.progress,
                        icon: "book.pages",
                        options: ReadState.ordered,
                        id: \.self,
                        label: \.label,
                        selection: $filter.readStates
                    )

                    Group(
                        Titles.status,
                        icon: "bookmark",
                        options: Status.ordered,
                        id: \.self,
                        label: \.label,
                        selection: $filter.statuses
                    )

                    Band

                    Group(
                        Titles.publication,
                        icon: "calendar",
                        options: Publication.ordered,
                        id: \.self,
                        label: \.label,
                        selection: $filter.publications
                    )

                    Group(
                        Titles.rating,
                        icon: "shield",
                        options: Classification.ordered,
                        id: \.self,
                        label: \.label,
                        selection: $filter.classifications
                    )

                    if !tags.isEmpty || !sources.isEmpty || !trackers.isEmpty {
                        Band
                    }

                    if !tags.isEmpty {
                        Group(
                            Titles.tags,
                            icon: "tag",
                            options: tags,
                            id: \.id,
                            label: \.name,
                            searchFirst: true,
                            selection: $filter.tags
                        )
                    }

                    if !sources.isEmpty {
                        Group(
                            Titles.sources,
                            icon: "square.stack.3d.up",
                            options: sources,
                            id: \.id,
                            label: \.name,
                            artwork: \.artwork,
                            selection: $filter.sources
                        )
                    }

                    if !trackers.isEmpty {
                        Group(
                            Titles.trackers,
                            icon: "app.connected.to.app.below.fill",
                            options: trackers,
                            id: \.self,
                            label: \.label,
                            artwork: \.artwork,
                            selection: $filter.trackers
                        )
                    }
                }
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.vertical, dimensions.spacing.space16)
            }
            .navigationTitle("Filters")
            .navigationSubtitle(subtitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        withAnimation(Motion.settle) { filter.clear() }
                    }
                    .disabled(!filter.isActive)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .animation(Motion.settle, value: filter)
        .task { seed() }
    }

    private func seed() {
        guard expanded.isEmpty else { return }

        if !filter.readStates.isEmpty { expanded.insert(Titles.progress) }
        if !filter.statuses.isEmpty { expanded.insert(Titles.status) }
        if !filter.publications.isEmpty { expanded.insert(Titles.publication) }
        if !filter.classifications.isEmpty { expanded.insert(Titles.rating) }
        if !filter.tags.isEmpty { expanded.insert(Titles.tags) }
        if !filter.sources.isEmpty { expanded.insert(Titles.sources) }
        if !filter.trackers.isEmpty { expanded.insert(Titles.trackers) }

        if expanded.isEmpty { expanded.insert(Titles.progress) }
    }

    private var Band: some View {
        Divider()
            .padding(.horizontal, dimensions.spacing.space12)
            .padding(.vertical, dimensions.spacing.space4)
    }

    private func Group<Option: Hashable, Key: Hashable>(
        _ title: String,
        icon: String,
        options: [Option],
        id: KeyPath<Option, Key>,
        label: KeyPath<Option, String>,
        artwork: KeyPath<Option, ImageResource?>? = nil,
        searchFirst: Bool = false,
        selection: Binding<Set<Key>>
    ) -> some View {
        let isOpen = expanded.contains(title)
        let shown = visible(
            options,
            in: title,
            id: id,
            label: label,
            searchFirst: searchFirst,
            selection: selection
        )

        return VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            Header(title, icon: icon, count: selection.wrappedValue.count, isOpen: isOpen)
                .contentShape(.rect)
                .tappable {
                    withAnimation(Motion.settle) { expanded.toggle(title) }
                }

            if isOpen {
                if searchFirst || options.count > Threshold.searchable {
                    Searchbar(
                        searchText: Binding(
                            get: { searches[title] ?? "" },
                            set: { searches[title] = $0 }
                        ),
                        placeholder: "Search \(options.count) \(title.lowercased())"
                    )
                }

                if shown.isEmpty {
                    Text(searches[title]?.isEmpty == false ? "No matches" : "Type to find a tag")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else {
                    FlowLayout(spacing: dimensions.spacing.space8) {
                        ForEach(shown, id: id) { option in
                            let key = option[keyPath: id]
                            let isOn = selection.wrappedValue.contains(key)

                            FilterChip(
                                label: option[keyPath: label],
                                tint: isOn ? Palette.brand : nil,
                                glyph: isOn ? "checkmark" : nil,
                                artwork: artwork.flatMap { option[keyPath: $0] }
                            ) {
                                withAnimation(Motion.settle) { selection.wrappedValue.toggle(key) }
                            }
                            .accessibilityAddTraits(isOn ? [.isSelected] : [])
                            .transition(Motion.chip)
                        }
                    }
                }
            }
        }
        .padding(dimensions.spacing.space12)
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: dimensions.radius.radius16))
        // keyed on what's actually shown, not the search text - so a selection
        // change (which reorders shown) animates even when the search text didn't
        .animation(Motion.settle, value: shown.map { $0[keyPath: id] })
    }

    private func Group<Option: Hashable, Key: Hashable>(
        _ title: String,
        icon: String,
        options: [Option],
        id: KeyPath<Option, Key>,
        label: KeyPath<Option, String>,
        artwork: KeyPath<Option, ImageResource?>? = nil,
        searchFirst: Bool = false,
        selection: Binding<TriSet<Key>>
    ) -> some View {
        let isOpen = expanded.contains(title)
        let shown = visible(
            options,
            in: title,
            id: id,
            label: label,
            searchFirst: searchFirst,
            selection: selection
        )

        return VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            Header(title, icon: icon, count: selection.wrappedValue.count, isOpen: isOpen)
                .contentShape(.rect)
                .tappable {
                    withAnimation(Motion.settle) { expanded.toggle(title) }
                }

            if isOpen {
                if searchFirst || options.count > Threshold.searchable {
                    Searchbar(
                        searchText: Binding(
                            get: { searches[title] ?? "" },
                            set: { searches[title] = $0 }
                        ),
                        placeholder: "Search \(options.count) \(title.lowercased())"
                    )
                }

                if shown.isEmpty {
                    Text(searches[title]?.isEmpty == false ? "No matches" : "Type to find a tag")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                } else {
                    FlowLayout(spacing: dimensions.spacing.space8) {
                        ForEach(shown, id: id) { option in
                            let key = option[keyPath: id]
                            let state = selection.wrappedValue.state(for: key)

                            FilterChip(
                                label: option[keyPath: label],
                                tint: tint(for: state),
                                glyph: glyph(for: state),
                                artwork: artwork.flatMap { option[keyPath: $0] },
                                strikethrough: state == .excluded
                            ) {
                                withAnimation(Motion.settle) { selection.wrappedValue.cycle(key) }
                            }
                            .accessibilityAddTraits(state == .included ? [.isSelected] : [])
                            .transition(Motion.chip)
                        }
                    }
                }
            }
        }
        .padding(dimensions.spacing.space12)
        .background(.primary.opacity(0.04), in: .rect(cornerRadius: dimensions.radius.radius16))
        .animation(Motion.settle, value: shown.map { $0[keyPath: id] })
    }

    private func tint(for state: TriSet<some Hashable>.State) -> Color? {
        switch state {
        case .off: nil
        case .included: Palette.brand
        case .excluded: .danger
        }
    }

    private func glyph(for state: TriSet<some Hashable>.State) -> String? {
        switch state {
        case .off: nil
        case .included: "checkmark"
        case .excluded: "minus"
        }
    }

    // whatever is chosen always survives the cut - a filter you cannot see is a
    // filter you cannot turn off
    private func visible<Option: Hashable, Key: Hashable>(
        _ options: [Option],
        in title: String,
        id: KeyPath<Option, Key>,
        label: KeyPath<Option, String>,
        searchFirst: Bool,
        selection: Binding<Set<Key>>
    ) -> [Option] {
        let query = (searches[title] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = options.filter { selection.wrappedValue.contains($0[keyPath: id]) }

        guard !query.isEmpty else {
            // searchFirst groups start empty, not truncated - showing the first N
            // of hundreds would be an arbitrary sample pretending to be a menu
            guard !searchFirst else { return chosen }
            guard options.count > Threshold.shown else { return options }

            let rest = options.filter { !selection.wrappedValue.contains($0[keyPath: id]) }
            return chosen + rest.prefix(Threshold.shown - chosen.count)
        }

        return options.filter { $0[keyPath: label].localizedCaseInsensitiveContains(query) }
    }

    private func visible<Option: Hashable, Key: Hashable>(
        _ options: [Option],
        in title: String,
        id: KeyPath<Option, Key>,
        label: KeyPath<Option, String>,
        searchFirst: Bool,
        selection: Binding<TriSet<Key>>
    ) -> [Option] {
        let query = (searches[title] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = options.filter { selection.wrappedValue.contains($0[keyPath: id]) }

        guard !query.isEmpty else {
            guard !searchFirst else { return chosen }
            guard options.count > Threshold.shown else { return options }

            let rest = options.filter { !selection.wrappedValue.contains($0[keyPath: id]) }
            return chosen + rest.prefix(Threshold.shown - chosen.count)
        }

        return options.filter { $0[keyPath: label].localizedCaseInsensitiveContains(query) }
    }

    private func Header(_ title: String, icon: String, count: Int, isOpen: Bool) -> some View {
        let isActive = count > 0

        return HStack(spacing: dimensions.spacing.space8) {
            Image(systemName: icon)
                .symbolVariant(isActive ? .fill : .none)
                .font(.subheadline)
                .frame(width: dimensions.size.icon20)
                .foregroundStyle(isActive ? AnyShapeStyle(.brand) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))

            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)

            if isActive {
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.brand)
                    .contentTransition(.numericText())
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isOpen ? 0 : -90))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isOpen ? "Collapses this group" : "Expands this group")
    }
}
