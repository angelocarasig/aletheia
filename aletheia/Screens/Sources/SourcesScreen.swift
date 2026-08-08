//
//  SourcesScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI

struct SourcesScreen: View {
    @Environment(\.database) private var database
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions
    
    @State private var vm: SourcesViewModel?
    @State private var searchText = ""
    @State private var collapsed: Set<String> = ["disabled"]
    @State private var route: Route?
    @State private var globalSearch: GlobalSearch?
    
    private struct Route: Identifiable, Hashable {
        let slug: String
        var id: String { slug }
    }

    // the text itself is the identity: submitting the same term twice is the
    // same destination, and the screen seeds from it
    private struct GlobalSearch: Identifiable, Hashable {
        let text: String
        var id: String { text }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: dimensions.spacing.space16) {
                    Searchbar(
                        searchText: $searchText,
                        placeholder: "Search sources",
                        handoff: .init(
                            tint: .brand,
                            label: { "Search every source for “\($0)”" },
                            onSelect: { text in globalSearch = GlobalSearch(text: text) }
                        )
                    )
                    
                    if let vm {
                        let pinned = filtered(vm.pinned)
                        let active = filtered(vm.active)
                        let disabled = filtered(vm.disabled)
                        
                        if !pinned.isEmpty {
                            ExpandableSection(title: "Pinned", isExpanded: isExpanded("pinned"), toggle: { toggle("pinned") }) {
                                Rows(pinned)
                            }
                        }
                        
                        Rows(active)
                        
                        if !disabled.isEmpty {
                            ExpandableSection(title: "Disabled", count: disabled.count, isExpanded: isExpanded("disabled"), toggle: { toggle("disabled") }) {
                                Rows(disabled)
                            }
                        }
                    }
                }
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.bottom, dimensions.screenMargin)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle("Sources")
            .navigationDestination(item: $route) { route in
                if let source = compositor.registry.source(slug: route.slug) {
                    SourceHomeScreen(source: source, record: vm?.sources.first { $0.slug == route.slug })
                }
            }
            // embedded: this stack is the Sources tab's, so the pushed screen
            // must not bring one of its own
            .navigationDestination(item: $globalSearch) { search in
                SearchScreen(query: search.text, embedded: true)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: searchText)
            .task {
                let vm = vm ?? SourcesViewModel(database: database, registry: compositor.registry)
                self.vm = vm
                vm.start()
            }
        }
    }
    
    // containered because several glass views in one tree share a render pass -
    // applying the effect outside a container is what degrades performance.
    // spacing is small on purpose: a value larger than the stack's own spacing
    // makes neighbouring rows blend into one capsule at rest
    @ViewBuilder
    private func Rows(_ records: [SourceRecord]) -> some View {
        GlassEffectContainer(spacing: dimensions.spacing.space4) {
            LazyVStack(spacing: dimensions.spacing.space8) {
                List(records)
            }
        }
    }

    @ViewBuilder
    private func List(_ records: [SourceRecord]) -> some View {
        ForEach(records, id: \.slug) { record in
            SourceRow(record: record, source: compositor.registry.source(slug: record.slug)) {
                route = Route(slug: record.slug)
            }
            .contextMenu {
                Button {
                    vm?.togglePinned(record)
                } label: {
                    Label(record.pinned ? "Unpin" : "Pin", systemImage: record.pinned ? "pin.slash" : "pin")
                }
                
                Button(role: record.disabled ? nil : .destructive) {
                    vm?.toggleDisabled(record)
                } label: {
                    Label(record.disabled ? "Enable" : "Disable", systemImage: record.disabled ? "checkmark.circle" : "xmark.circle")
                }
            }
        }
    }
    
    private func filtered(_ list: [SourceRecord]) -> [SourceRecord] {
        guard !searchText.isEmpty else { return list }
        return list.filter { record in
            let name = compositor.registry.source(slug: record.slug)?.descriptor.name ?? record.slug
            return name.localizedCaseInsensitiveContains(searchText)
            || record.slug.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private func isExpanded(_ key: String) -> Bool {
        !collapsed.contains(key)
    }
    
    private func toggle(_ key: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            if collapsed.contains(key) {
                collapsed.remove(key)
            } else {
                collapsed.insert(key)
            }
        }
    }
}

// MARK: - Row

// a struct rather than a view builder: each row owns its own ping state and task
private struct SourceRow: View {
    @Environment(\.dimensions) private var dimensions
    
    let record: SourceRecord
    let source: Source?
    var onTap: () -> Void
    
    @State private var ping: PingResult?

    private enum Layout {
        // the tint carries its own alpha rather than relying on the material to
        // soften it. .regular resolves dark over a dark page and averages a
        // full-strength colour toward that dark, so a bare .danger reads greyer
        // than .danger at a third of it. same value CollectionPicker tints with
        static let adultTint: Double = 0.05
        static let adultBorder: Double = 0.15
    }

    private var glass: Glass {
        guard source?.descriptor.adultOnly == true else { return .regular }
        return .regular.tint(Palette.danger.opacity(Layout.adultTint))
    }

    var body: some View {
        HStack(spacing: dimensions.spacing.space12) {
            Icon
            Info
            Spacer()
            Ping
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, dimensions.spacing.space12)
        .padding(.vertical, dimensions.spacing.space12)
        // applied after the padding that sizes it, per the glass contract - the
        // effect takes the frame it is given
        .glassEffect(glass, in: .rect(cornerRadius: dimensions.radius.radius16))
        // the material alone cannot hold a colour against black - the border is
        // where the red actually reads, and it gives the state a shape channel
        // rather than leaving it on hue alone
        .overlay {
            if source?.descriptor.adultOnly == true {
                RoundedRectangle(cornerRadius: dimensions.radius.radius16)
                    .strokeBorder(.danger.opacity(Layout.adultBorder), lineWidth: 1)
            }
        }
        .opacity(record.disabled ? 0.5 : 1)
        .contentShape(.rect)
        .tappable(action: onTap)
        .task {
            guard let source, !record.disabled else { return }
            let result = await source.ping()
            withAnimation(.smooth) { ping = result }
        }
    }
    
    @ViewBuilder
    private var Icon: some View {
        let shape = RoundedRectangle(cornerRadius: dimensions.radius.radius8)
        Group {
            if let source {
                Image(source.descriptor.icon)
                    .resizable()
                    .scaledToFit()
            } else {
                shape.fill(.quaternary)
            }
        }
        .frame(width: dimensions.size.icon40, height: dimensions.size.icon40)
        .clipShape(shape)
    }
    
    // a badge rather than a section of its own: the row already sorts and groups
    // by pinned/disabled, and a fourth grouping would structure the screen around
    // a property most sources do not have. nothing here shows content - only that
    // opening this source will
    private var Info: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
            HStack(spacing: dimensions.spacing.space4) {
                Text(source?.descriptor.name ?? record.slug)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if source?.descriptor.adultOnly == true {
                    Text("18+")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, dimensions.spacing.space4)
                        .padding(.vertical, 1)
                        .background(.danger, in: .capsule)
                }
            }
            
            HStack(spacing: dimensions.spacing.space4) {
                Text(source?.descriptor.baseURL.host() ?? record.slug)
                    .foregroundStyle(.secondary)
                Text(record.hash.prefix(7))
                    .monospaced()
                    .foregroundStyle(.tertiary)
            }
            .font(.caption)
            .lineLimit(1)
        }
    }
    
    @ViewBuilder
    private var Ping: some View {
        if !record.disabled, let ping {
            HStack(spacing: dimensions.spacing.space4) {
                if let latency = ping.latency {
                    Text("\(latency.milliseconds)ms")
                        .font(.caption2)
                        .foregroundStyle(color(for: ping.status))
                        .contentTransition(.numericText())
                }
                Circle()
                    .fill(color(for: ping.status))
                    .frame(width: dimensions.size.dot, height: dimensions.size.dot)
            }
            .transition(.opacity.combined(with: .scale))
        }
    }
    
    private func color(for status: PingStatus) -> Color {
        switch status {
        case .healthy: .success
        case .slow: .warning
        case .down: .danger
        }
    }
}
