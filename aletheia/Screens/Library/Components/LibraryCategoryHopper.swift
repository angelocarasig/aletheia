//
//  LibraryCategoryHopper.swift
//  aletheia
//
//  Created by Angelo Carasig on 22/8/2026.
//

import SwiftUI

// tachiyomi's "category hopper" - a single floating pill, not a chip panel.
// the library is one continuous scroll with a section per collection, and
// this jumps between section headers rather than filtering down to one.
// core behaviour only: no drag-to-reposition, scroll-based auto-hide, or the
// long-press power actions the original also has
struct LibraryCategoryHopper: View {
    @Environment(\.dimensions) private var dimensions

    var sections: [LibraryViewModel.Section]
    var activeID: LibraryViewModel.SectionID?
    var onJump: (LibraryViewModel.SectionID) -> Void
    var onCreate: () -> Void

    @State private var showingPicker = false

    private var activeIndex: Int? {
        sections.firstIndex { $0.id == activeID }
    }

    private var previousID: LibraryViewModel.SectionID? {
        guard let activeIndex, activeIndex > 0 else { return nil }
        return sections[activeIndex - 1].id
    }

    private var nextID: LibraryViewModel.SectionID? {
        guard let activeIndex, activeIndex < sections.count - 1 else { return nil }
        return sections[activeIndex + 1].id
    }

    // always shown, even with zero or one section - the category button still
    // opens "New Collection" with nothing to jump to, and the chevrons dim
    // themselves via previousID/nextID rather than the whole thing hiding
    var body: some View {
        // no outer padding - each button is already controlL (50pt), and this
        // has to sit flush at that same height as LibraryActions' circle, not
        // taller
        HStack(spacing: dimensions.spacing.space4) {
            Chevron("chevron.up", target: previousID)
            CategoryButton
            Chevron("chevron.down", target: nextID)
        }
        .glassEffect(.regular.interactive(), in: .capsule)
        .sheet(isPresented: $showingPicker) {
            Picker
        }
    }
}

// MARK: - Buttons

extension LibraryCategoryHopper {
    // dims rather than disappears at either end - a still-visible, still-shaped
    // button that does nothing there reads as "you're at the edge," not as a
    // layout glitch
    fileprivate func Chevron(_ systemImage: String, target: LibraryViewModel.SectionID?) -> some View {
        let enabled = target != nil

        return Image(systemName: systemImage)
            .font(.system(size: dimensions.size.icon20, weight: .medium))
            .frame(width: dimensions.size.controlL, height: dimensions.size.controlL)
            .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .contentShape(.circle)
            .tappable {
                guard let target else { return }
                onJump(target)
            }
            .disabled(!enabled)
    }

    fileprivate var CategoryButton: some View {
        Image(systemName: "books.vertical")
            .font(.system(size: dimensions.size.icon20, weight: .medium))
            .frame(width: dimensions.size.controlL, height: dimensions.size.controlL)
            .contentShape(.circle)
            .tappable { showingPicker = true }
            .accessibilityLabel("Jump to Collection")
    }
}

// MARK: - Picker

extension LibraryCategoryHopper {
    fileprivate var Picker: some View {
        NavigationStack {
            List {
                ForEach(sections) { section in
                    Button {
                        onJump(section.id)
                        showingPicker = false
                    } label: {
                        HStack {
                            if section.isLocked {
                                GlitchText(text: section.name)
                                    .foregroundStyle(.primary)

                                Image(systemName: "lock.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(section.name)
                                    .foregroundStyle(.primary)
                            }

                            Spacer()

                            Text("\(section.entries.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    // List tints an unstyled Button's whole label with the accent
                    // color - plain keeps it to text weight/color only
                    .buttonStyle(.plain)
                }

                Button {
                    showingPicker = false
                    onCreate()
                } label: {
                    Label("New Collection", systemImage: "plus")
                        .foregroundStyle(.brand)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Jump to Collection")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
