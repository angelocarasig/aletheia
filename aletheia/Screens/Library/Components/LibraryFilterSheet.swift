//
//  LibraryFilterSheet.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import SwiftUI

// the same grammar as the source refine sheet: options are FilterChips in a
// FlowLayout, bare checkmark and brand tint when on, nothing when off. an option
// should read the same wherever it is shown, and this is the app's second place
// that picks a subset from a set
struct LibraryFilterSheet: View {
    @Binding var filter: LibraryFilter
    var tags: [LibraryViewModel.Option<TagRecord.ID>] = []
    var sources: [LibraryViewModel.Option<SourceRecord.ID>] = []
    var trackers: [TrackerFilter] = []

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    private enum Motion {
        static let settle: Animation = .snappy(duration: 0.28)
        // out of its own centre, since a wrapped row has no edge to arrive from
        // and the chips beside it are reflowing at the same time
        static let chip: AnyTransition = .scale(scale: 0.85).combined(with: .opacity)
    }

    // named once: the title is both the heading and the key a group is expanded
    // by, so a literal in two places would drift
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
        // past this a vocabulary stops being something you scan and becomes
        // something you look up
        static let searchable = 15
        // FlowLayout measures every child handed to it, so the cut happens before
        // it, not inside it
        static let shown = 60
    }

    // by title rather than by index, so reordering the groups cannot silently
    // expand a different one
    @State private var expanded: Set<String> = []

    // per group, so searching tags does not wipe what was typed under sources
    @State private var searches: [String: String] = [:]

    // Text, not String, and if/else rather than a ternary - either one erases the
    // literal to a plain String and the inflection markup renders on screen
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
                    // three bands, divided: how you are reading it, what the work
                    // itself is, and where it came from. the order runs from what
                    // you control to what you only observe
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

                    // all three are empty until something is owned, so the group
                    // is absent rather than an expandable row with nothing in it.
                    // the divider goes with them, or an empty library shows a
                    // rule under the last group with nothing beneath it
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

                    // last of the three relationship groups, and last overall: a
                    // link is the furthest thing here from the series itself
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

    // opens whatever is already narrowing the grid, so a filter you set last week
    // is visible rather than hidden behind a row you have to remember to tap.
    // nothing set means nothing to reveal, so the first group opens instead of
    // leaving three dead rows
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

    // one builder for every group: each is the same question asked of a different
    // enum, and three hand-written copies would drift the moment one is edited
    // inset from the cards either side, so it reads as separating them rather
    // than as another edge belonging to one of them
    private var Band: some View {
        Divider()
            .padding(.horizontal, dimensions.spacing.space12)
            .padding(.vertical, dimensions.spacing.space4)
    }

    // keyed by id rather than by the option itself, so an enum can store its own
    // cases while a tag stores only its row id
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
        // keyed on what is actually on screen rather than on the search text, so a
        // keystroke matching the same set does not re-animate, and a selection made
        // with no search still does
        .animation(Motion.settle, value: shown.map { $0[keyPath: id] })
    }

    // status, publication, rating, tags, sources and trackers - a tap cycles
    // off -> included -> excluded -> off, the same grammar the source refine
    // sheet already uses for a remote source's own multi-select filters
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
            // a vocabulary in the hundreds opens empty: showing the first sixty of
            // four hundred is an arbitrary sample pretending to be a menu. what
            // stays is whatever is chosen, which is the one thing always needed
            guard !searchFirst else { return chosen }
            guard options.count > Threshold.shown else { return options }

            let rest = options.filter { !selection.wrappedValue.contains($0[keyPath: id]) }
            return chosen + rest.prefix(Threshold.shown - chosen.count)
        }

        return options.filter { $0[keyPath: label].localizedCaseInsensitiveContains(query) }
    }

    // the tri-state groups: same shape as the group above, chosen means
    // included-or-excluded rather than just contains
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

    // the count is the only per-group text worth keeping: it says which group is
    // narrowing things, which the chips below only answer if you read them all
    private func Header(_ title: String, icon: String, count: Int, isOpen: Bool) -> some View {
        let isActive = count > 0

        return HStack(spacing: dimensions.spacing.space8) {
            // fills and turns brand when the group is narrowing, so the state has
            // a shape channel and not only the count beside it
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
