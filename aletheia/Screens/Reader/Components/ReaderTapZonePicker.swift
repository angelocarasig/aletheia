//
//  ReaderTapZonePicker.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI

// choosing a layout flashes it behind the sheet rather than waiting for a
// dismissal, so the preview and the real thing are seen together
struct ReaderTapZonePicker: View {
    let layout: ReaderTapZones.Layout
    let reversed: Bool
    let isRightToLeft: Bool

    var onSelect: (ReaderTapZones.Layout) -> Void
    var onReverse: (Bool) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    private enum Layout {
        static let mapWidth: CGFloat = 40
        static let mapRatio: CGFloat = 19.5 / 9
        static let fillOpacity: Double = 0.1
        static let currentOpacity: Double = 0.15
        static let rowSpacing: CGFloat = 2
    }

    var body: some View {
        NavigationStack {
            Content
                .navigationTitle("Tap Zones")
                .navigationSubtitle(subtitle)
                .navigationBarTitleDisplayMode(.inline)
                // a navigation container paints an opaque layer of its own, which
                // would sit between the content and the sheet's glass
                .containerBackground(.clear, for: .navigation)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Content

private extension ReaderTapZonePicker {
    var Content: some View {
        ScrollView {
            LazyVStack(spacing: Layout.rowSpacing) {
                ForEach(ReaderTapZones.Layout.allCases) { option in
                    Row(option)
                }

                FlipRow
                    .padding(.top, dimensions.spacing.space12)
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.bottom, dimensions.spacing.space24)
        }
        .scrollContentBackground(.hidden)
        .animation(.settle, value: layout)
        .animation(.settle, value: reversed)
    }

    func Row(_ option: ReaderTapZones.Layout) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            // drawn by the same view as the full-screen flash, so a row can
            // never describe a layout the reader does not actually use
            ReaderTapZoneMap(layout: option, reversed: reversed, isCompact: true)
                .frame(width: Layout.mapWidth, height: Layout.mapWidth * Layout.mapRatio)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius4))

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(option.label)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(option.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if option == layout {
                Check
            }
        }
        .padding(dimensions.spacing.space12)
        .background { Highlight(option == layout) }
        .contentShape(.rect)
        .tappable { onSelect(option) }
    }

    var FlipRow: some View {
        Toggle(isOn: Binding(get: { reversed }, set: onReverse)) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text("Flip Sides")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(flipSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .disabled(!layout.isFlippable)
        .opacity(layout.isFlippable ? 1 : Layout.currentOpacity * 4)
        .padding(dimensions.spacing.space12)
        .background {
            RoundedRectangle(cornerRadius: dimensions.radius.radius16)
                .fill(.primary.opacity(Layout.fillOpacity))
        }
    }

    var Check: some View {
        Image(systemName: "checkmark")
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(Palette.brand)
    }

    @ViewBuilder
    func Highlight(_ shown: Bool) -> some View {
        if shown {
            RoundedRectangle(cornerRadius: dimensions.radius.radius16)
                .fill(Palette.brand.opacity(Layout.currentOpacity))
        }
    }
}

// MARK: - Copy

private extension ReaderTapZonePicker {
    var subtitle: Text {
        Text("Saved across all your series")
    }

    // a right-to-left series mirrors the zones on its own, so the toggle is
    // already on when the sheet opens and saying nothing would read as a bug
    var flipSummary: String {
        guard isRightToLeft else { return "Swap the back and forward zones." }
        return "This series reads right to left, so the zones are mirrored already."
    }
}
