//
//  SearchRefineSheet.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI

struct SearchRefineSheet: View {
    let vm: SearchGridViewModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dimensions) private var dimensions

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                SearchFilterPanel(vm: vm)
                    .padding(dimensions.screenMargin)
            }
            .navigationTitle("Refine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if vm.activeFilterCount > 0 {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Clear All", role: .destructive) {
                            vm.clearFilters()
                        }
                        .foregroundStyle(.danger)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

struct SearchFilterPanel: View {
    let vm: SearchGridViewModel
    @Environment(\.dimensions) private var dimensions

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
            ForEach(vm.supportedFilters, id: \.self) { filter in
                FilterGroup(filter: filter, vm: vm)
            }
        }
    }

}

extension SourceFilter {
    fileprivate var key: String {
        switch self {
        case .text(let id, _), .number(let id, _), .select(let id, _, _),
            .multiSelect(let id, _, _, _):
            return id
        }
    }

    fileprivate var displayName: String {
        switch self {
        case .text(_, let name), .number(_, let name), .select(_, let name, _),
            .multiSelect(_, let name, _, _):
            return name
        }
    }
}

private struct FilterGroup: View {
    let filter: SourceFilter
    let vm: SearchGridViewModel

    @Environment(\.dimensions) private var dimensions

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            Text(filter.displayName)
                .font(.subheadline.weight(.semibold))

            FilterControl(filter: filter, vm: vm)
        }
    }
}

private struct FilterControl: View {
    let filter: SourceFilter
    let vm: SearchGridViewModel

    var body: some View {
        switch filter {
        case .number(let id, _):
            NumberField(vm: vm, id: id)
        case .select(let id, _, let options):
            if options.count <= Layout.segmentedMax {
                SegmentedSelect(vm: vm, id: id, options: options)
            } else {
                SingleSelectChips(vm: vm, id: id, options: options)
            }
        case .multiSelect(let id, _, let options, let canExclude):
            MultiSelectGroup(vm: vm, id: id, options: options, canExclude: canExclude)
        case .text:
            EmptyView()
        }
    }

    private enum Layout {
        static let segmentedMax = 3
    }
}

private struct NumberField: View {
    let vm: SearchGridViewModel
    let id: String

    @Environment(\.dimensions) private var dimensions
    @State private var text = ""

    var body: some View {
        TextField("Any", text: $text)
            .keyboardType(.numberPad)
            .padding(.horizontal, dimensions.spacing.space12)
            .frame(height: dimensions.size.control)
            .background(Color.primary.opacity(0.06))
            .clipShape(.rect(cornerRadius: dimensions.radius.radius12))
            .onAppear { sync() }
            // without this the field kept showing its number after Clear All
            // even though the selection was gone
            .onChange(of: vm.selection(for: id)) { _, _ in sync() }
            .onChange(of: text) { _, new in
                if let value = Int(new), value > 0 {
                    vm.setSelection(.number(id: id, value: value), for: id)
                } else {
                    vm.setSelection(nil, for: id)
                }
            }
    }

    private func sync() {
        guard case .number(_, let value) = vm.selection(for: id) else {
            if !text.isEmpty { text = "" }
            return
        }
        let latest = String(value)
        if text != latest { text = latest }
    }
}

private struct SegmentedSelect: View {
    let vm: SearchGridViewModel
    let id: String
    let options: [SourceFilter.Option]

    // the getter previously fell back to options.first when nothing was
    // selected, rendering the control as chosen with no selection and no way back
    private static let unset = ""

    var body: some View {
        Picker("", selection: binding) {
            Text("Any").tag(Self.unset)

            ForEach(options) { option in
                Text(option.name).tag(option.id)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var binding: Binding<String> {
        Binding(
            get: {
                if case .select(_, let optionID) = vm.selection(for: id) { return optionID }
                return Self.unset
            },
            set: { optionID in
                guard optionID != Self.unset else {
                    vm.setSelection(nil, for: id)
                    return
                }
                vm.setSelection(.select(id: id, optionID: optionID), for: id)
            }
        )
    }
}

private struct SingleSelectChips: View {
    let vm: SearchGridViewModel
    let id: String
    let options: [SourceFilter.Option]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(options) { option in
                let selected = current == option.id
                FilterChip(
                    label: option.name,
                    sensitivity: option.sensitivity,
                    tint: selected ? .brand : nil,
                    glyph: selected ? "checkmark" : nil
                ) {
                    vm.setSelection(selected ? nil : .select(id: id, optionID: option.id), for: id)
                }
            }
        }
    }

    private var current: String? {
        if case .select(_, let optionID) = vm.selection(for: id) { return optionID }
        return nil
    }
}

private struct MultiSelectGroup: View {
    let vm: SearchGridViewModel
    let id: String
    let options: [SourceFilter.Option]
    let canExclude: Bool

    @Environment(\.dimensions) private var dimensions
    @State private var search = ""

    private enum Threshold {
        static let searchable = 15
        static let deferred = 100
        // FlowLayout measures every child it is handed, so results are capped
        // before it sees them; the list is pre-ordered by popularity so the cut
        // keeps the useful end
        static let shown = 60
    }

    private enum Motion {
        static let settle: Animation = .snappy(duration: 0.28)
        static let chip: AnyTransition = .scale(scale: 0.85).combined(with: .opacity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            if options.count > Threshold.searchable {
                Searchbar(searchText: $search, placeholder: "Search \(options.count) options")
            }

            FlowLayout(spacing: 6) {
                ForEach(visible) { option in
                    let state = state(for: option.id)
                    FilterChip(
                        label: option.name,
                        sensitivity: option.sensitivity,
                        tint: tint(for: state),
                        glyph: glyph(for: state),
                        strikethrough: state == .excluded
                    ) {
                        toggle(option.id)
                    }
                    .transition(Motion.chip)
                }
            }

            if let hint {
                hint
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        // keyed on the visible ids rather than the search text, so a keystroke
        // that changes nothing does not animate
        .animation(Motion.settle, value: visible.map(\.id))
    }

    private enum ChipState { case off, included, excluded }

    private var isDeferred: Bool {
        options.count > Threshold.deferred
    }

    private var visible: [SourceFilter.Option] {
        let chosen = Set(selection.included + selection.excluded)
        let picked = options.filter { chosen.contains($0.id) }

        guard !search.isEmpty else {
            return isDeferred ? picked : capped(options, keeping: picked)
        }

        return capped(filtered, keeping: picked)
    }

    // chosen options are never cut, or typing would hide the selections it
    // is meant to be adding to
    private func capped(
        _ matches: [SourceFilter.Option],
        keeping picked: [SourceFilter.Option]
    ) -> [SourceFilter.Option] {
        guard matches.count > Threshold.shown else { return matches }

        let chosen = Set(picked.map(\.id))
        let rest = matches.filter { !chosen.contains($0.id) }
        return picked + rest.prefix(max(0, Threshold.shown - picked.count))
    }

    // Text, not String: inflection markup only parses through the
    // LocalizedStringKey overload
    private var hint: Text? {
        if search.isEmpty, isDeferred {
            let count = options.count - visible.count
            guard count > 0 else { return nil }
            return Text("^[\(count) option](inflect: true) - search to browse")
        }

        let hidden = filtered.count - visible.count
        guard hidden > 0 else { return nil }
        return Text("^[\(hidden) more match](inflect: true) - narrow your search")
    }

    private var filtered: [SourceFilter.Option] {
        guard !search.isEmpty else { return options }
        return options.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var selection: (included: [String], excluded: [String]) {
        if case .multiSelect(_, let included, let excluded) = vm.selection(for: id) {
            return (included, excluded)
        }
        return ([], [])
    }

    private func state(for optionID: String) -> ChipState {
        let current = selection
        if current.included.contains(optionID) { return .included }
        if current.excluded.contains(optionID) { return .excluded }
        return .off
    }

    private func tint(for state: ChipState) -> Color? {
        switch state {
        case .off: return nil
        case .included: return canExclude ? .success : .brand
        case .excluded: return .danger
        }
    }

    private func glyph(for state: ChipState) -> String? {
        switch state {
        case .off: return nil
        case .included: return canExclude ? "plus" : "checkmark"
        case .excluded: return "minus"
        }
    }

    private func toggle(_ optionID: String) {
        var (included, excluded) = selection
        let wasIncluded = included.contains(optionID)
        let wasExcluded = excluded.contains(optionID)
        included.removeAll { $0 == optionID }
        excluded.removeAll { $0 == optionID }

        if canExclude {
            if !wasIncluded, !wasExcluded {
                included.append(optionID)
            } else if wasIncluded {
                excluded.append(optionID)
            }
        } else if !wasIncluded {
            included.append(optionID)
        }

        let empty = included.isEmpty && excluded.isEmpty
        vm.setSelection(
            empty ? nil : .multiSelect(id: id, included: included, excluded: excluded), for: id)
    }
}

struct FilterChip: View {
    let label: String
    var sensitivity: SourceFilter.Sensitivity = .none
    let tint: Color?
    var glyph: String? = nil
    var artwork: ImageResource? = nil
    var strikethrough: Bool = false
    let action: () -> Void

    @Environment(\.dimensions) private var dimensions

    // the 18+ badge previously showed on any flagged sensitivity, mislabeling
    // Ecchi and Mature (neither pornographic) as rated
    private var flagged: Bool { sensitivity != .none }
    private var rated: Bool { sensitivity == .adult }

    var body: some View {
        HStack(spacing: dimensions.spacing.space4) {
            if let glyph {
                Image(systemName: glyph)
                    .font(.caption2.weight(.bold))
            }
            if let artwork {
                Image(artwork)
                    .resizable()
                    .scaledToFit()
                    .frame(width: dimensions.size.icon16, height: dimensions.size.icon16)
                    .clipShape(.rect(cornerRadius: dimensions.radius.radius4))
            }
            Text(label)
                .strikethrough(strikethrough, color: foreground.opacity(0.5))
            if rated { Badge }
        }
        .font(.subheadline)
        .fontWeight(tint == nil ? .regular : .medium)
        .foregroundStyle(foreground)
        .padding(.horizontal, dimensions.spacing.space12)
        .padding(.vertical, dimensions.spacing.space8)
        .background(background)
        .clipShape(.capsule)
        .overlay {
            if flagged, tint == nil {
                Capsule().strokeBorder(.danger.opacity(0.4), lineWidth: 1)
            }
        }
        .contentShape(.capsule)
        .tappable(action: action)
    }

    private var Badge: some View {
        Text("18+")
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, dimensions.spacing.space4)
            .padding(.vertical, 1)
            .background(.danger, in: .capsule)
    }

    private var foreground: Color { tint ?? .primary }
    private var background: Color {
        if tint == nil, flagged { return Color.danger.opacity(0.06) }
        return (tint ?? Color.primary).opacity(tint == nil ? 0.06 : 0.14)
    }
}
