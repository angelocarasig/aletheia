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
                VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                    ForEach(vm.supportedFilters, id: \.self) { filter in
                        FilterGroup(filter: filter, vm: vm)
                    }
                }
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
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct FilterGroup: View {
    let filter: SourceFilter
    let vm: SearchGridViewModel

    @Environment(\.dimensions) private var dimensions

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            Text(name)
                .font(.subheadline.weight(.semibold))

            switch filter {
            case let .number(id, _):
                NumberField(vm: vm, id: id)
            case let .select(id, _, options):
                if options.count <= Layout.segmentedMax {
                    SegmentedSelect(vm: vm, id: id, options: options)
                } else {
                    SingleSelectChips(vm: vm, id: id, options: options)
                }
            case let .multiSelect(id, _, options, canExclude):
                MultiSelectGroup(vm: vm, id: id, options: options, canExclude: canExclude)
            case .text:
                EmptyView()
            }
        }
    }

    private var name: String {
        switch filter {
        case let .text(_, name), let .number(_, name), let .select(_, name, _), let .multiSelect(_, name, _, _):
            return name
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
            .onAppear {
                if case let .number(_, value) = vm.selection(for: id) { text = String(value) }
            }
            .onChange(of: text) { _, new in
                if let value = Int(new), value > 0 {
                    vm.setSelection(.number(id: id, value: value), for: id)
                } else {
                    vm.setSelection(nil, for: id)
                }
            }
    }
}

private struct SegmentedSelect: View {
    let vm: SearchGridViewModel
    let id: String
    let options: [SourceFilter.Option]

    var body: some View {
        Picker("", selection: binding) {
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
                if case let .select(_, optionID) = vm.selection(for: id) { return optionID }
                return options.first?.id ?? ""
            },
            set: { vm.setSelection(.select(id: id, optionID: $0), for: id) }
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
                    nsfw: option.nsfw,
                    tint: selected ? .brand : nil,
                    glyph: selected ? "checkmark" : nil
                ) {
                    vm.setSelection(selected ? nil : .select(id: id, optionID: option.id), for: id)
                }
            }
        }
    }

    private var current: String? {
        if case let .select(_, optionID) = vm.selection(for: id) { return optionID }
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
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            if options.count > Threshold.searchable {
                Searchbar(searchText: $search, placeholder: "Search \(options.count) options")
            }

            FlowLayout(spacing: 6) {
                ForEach(filtered) { option in
                    let state = state(for: option.id)
                    FilterChip(
                        label: option.name,
                        nsfw: option.nsfw,
                        tint: tint(for: state),
                        glyph: glyph(for: state),
                        strikethrough: state == .excluded
                    ) {
                        toggle(option.id)
                    }
                }
            }
        }
    }

    private enum ChipState { case off, included, excluded }

    private var filtered: [SourceFilter.Option] {
        guard !search.isEmpty else { return options }
        return options.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var selection: (included: [String], excluded: [String]) {
        if case let .multiSelect(_, included, excluded) = vm.selection(for: id) {
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
        vm.setSelection(empty ? nil : .multiSelect(id: id, included: included, excluded: excluded), for: id)
    }
}

private struct FilterChip: View {
    let label: String
    var nsfw: Bool = false
    let tint: Color?
    var glyph: String? = nil
    var strikethrough: Bool = false
    let action: () -> Void

    @Environment(\.dimensions) private var dimensions

    var body: some View {
        HStack(spacing: dimensions.spacing.space4) {
            if let glyph {
                Image(systemName: glyph)
                    .font(.caption2.weight(.bold))
            }
            Text(label)
                .strikethrough(strikethrough, color: foreground.opacity(0.5))
            if nsfw { Badge }
        }
        .font(.subheadline)
        .fontWeight(tint == nil ? .regular : .medium)
        .foregroundStyle(foreground)
        .padding(.horizontal, dimensions.spacing.space12)
        .padding(.vertical, dimensions.spacing.space8)
        .background(background)
        .clipShape(.capsule)
        .overlay {
            if nsfw, tint == nil {
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
        if tint == nil, nsfw { return Color.danger.opacity(0.06) }
        return (tint ?? Color.primary).opacity(tint == nil ? 0.06 : 0.14)
    }
}
