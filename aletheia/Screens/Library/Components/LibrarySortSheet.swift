//
//  LibrarySortSheet.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import SwiftUI

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

                // hand-built rather than a segmented picker - the picker's labels
                // are UIKit-drawn and swap instantly with no transition to attach to
                Section("Order") {
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
        // on the stack, not at the mutation - navigationSubtitle is nav chrome
        // and doesn't animate from a withAnimation inside the content
        .animation(.smooth, value: sort)
        .animation(.smooth, value: ascending)
    }

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
                ascending = option.defaultsAscending
            }
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
