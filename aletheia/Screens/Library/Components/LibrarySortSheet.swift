//
//  LibrarySortSheet.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import SwiftUI

// a preference, so it commits as you touch it and the grid behind is already
// reordered by the time you close. nothing to confirm, hence Close rather than
// Done - there is no version of this sheet you can cancel out of
struct LibrarySortSheet: View {
    @Binding var sort: LibrarySort
    @Binding var ascending: Bool

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Sort By") {
                    ForEach(LibrarySort.allCases) { option in
                        Row(option)
                    }
                }

                // the labels come from the selected option, so this never says
                // "ascending" and leaves you to work out what that means for dates.
                // hand-built rather than a segmented picker: those labels are
                // drawn by uikit and swap instantly when the sort above changes,
                // with no transition to attach to
                Section("Order") {
                    // the option's own default sits on the left, so A to Z leads
                    // for Title the way Newest first leads for a date
                    HStack(spacing: dimensions.spacing.space8) {
                        Segment(sort.defaultsAscending)
                        Segment(!sort.defaultsAscending)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Sort")
            .navigationSubtitle(sort.direction(ascending: ascending))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        // on the stack rather than at the mutation: the subtitle is nav chrome and
        // never sees a withAnimation from inside the content. ReaderSourceSwitcher
        // drives its own subtitle the same way
        .animation(.smooth, value: sort)
        .animation(.smooth, value: ascending)
    }

    // the label is the only thing that changes when the sort above changes, so it
    // carries the transition and the capsule around it stays put
    private func Segment(_ value: Bool) -> some View {
        let isSelected = ascending == value

        return Text(sort.direction(ascending: value))
            .font(.subheadline)
            .fontWeight(isSelected ? .semibold : .medium)
            .lineLimit(1)
            .contentTransition(.opacity)
            .frame(maxWidth: .infinity)
            .frame(height: dimensions.touchTarget)
            .background(
                isSelected
                    ? AnyShapeStyle(Palette.brand.opacity(0.16))
                    : AnyShapeStyle(.primary.opacity(0.06)),
                in: .capsule
            )
            .foregroundStyle(isSelected ? AnyShapeStyle(.brand) : AnyShapeStyle(.primary))
            .contentShape(.capsule)
            .tappable {
                guard !isSelected else { return }
                withAnimation(.smooth) { ascending = value }
            }
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func Row(_ option: LibrarySort) -> some View {
        let isSelected = sort == option

        return HStack(spacing: dimensions.spacing.space12) {
            Image(systemName: option.icon)
                .frame(width: dimensions.size.icon24)
                .foregroundStyle(isSelected ? AnyShapeStyle(.brand) : AnyShapeStyle(.secondary))

            Text(option.label)

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.brand)
            }
        }
        .contentShape(.rect)
        .tappable {
            guard !isSelected else { return }

            withAnimation(.smooth) {
                sort = option
                // each option has an order that is obviously right - a title
                // landing on Z to A because a date was picked first is a puzzle
                ascending = option.defaultsAscending
            }
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
