//
//  ReaderSourceSwitcher.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI

// the source icon's destination. scoped to ONE chapter on purpose - "this scan is
// unreadable, who else has it" is only ever asked about the page in front of you,
// and the durable answer already lives in origin and scanlator priority.
//
// the swap lasts the session. reopening the reader goes back to your ranking
struct ReaderSourceSwitcher: View {
    let slot: ChapterSlot?
    let active: ChapterRecord.ID?
    let isLoading: Bool
    var onSelect: (ChapterSlot.Option) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    @State private var expanded: Set<OriginRecord.ID> = []

    private enum Layout {
        static let iconSize: CGFloat = 32
        static let fillOpacity: Double = 0.1
        static let currentOpacity: Double = 0.15
        static let rowSpacing: CGFloat = 2
        // sits the scanlator rows under their source's name rather than its icon
        static let indent: CGFloat = 44
        static let expand: Animation = .snappy(duration: 0.25)
        static let skeletonRows = 6
    }

    // one entry per source, holding every scanlator that source has for this
    // chapter. built by walking the options in place so best_chapter's ranking
    // survives - both between sources and between scanlators inside one
    private struct Source: Identifiable {
        let id: OriginRecord.ID
        let name: String
        let icon: ImageResource?
        var options: [ChapterSlot.Option]
    }

    private func sources(of slot: ChapterSlot) -> [Source] {
        var result: [Source] = []
        for option in slot.options {
            if let index = result.firstIndex(where: { $0.id == option.originId }) {
                result[index].options.append(option)
            } else {
                result.append(
                    Source(
                        id: option.originId,
                        name: option.sourceName ?? "Unavailable Source",
                        icon: option.sourceIcon,
                        options: [option]
                    )
                )
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Content
                // reads straight into the list: every row completes the sentence
                .navigationTitle("Read From")
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
        // a partial-height detent is what makes the sheet Liquid Glass, and the
        // system turns it opaque at full height by design. never set
        // presentationBackground here - it replaces the glass outright
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .environment(\.colorScheme, .dark)
        .animation(.settle, value: phase)
    }
}

// MARK: - Content

private extension ReaderSourceSwitcher {
    var phase: LoadPhase {
        if let slot, slot.options.count > 1 { .content }
        else if isLoading { .pending }
        else { .empty }
    }

    @ViewBuilder
    var Content: some View {
        switch phase {
        case .content:
            if let slot {
                Options(slot)
                    .transition(.opacity)
            }
        case .pending:
            SheetSkeleton(rows: Layout.skeletonRows)
                .transition(.opacity)
        case .empty, .failed:
            // not an error - one source having the chapter is the normal case for
            // most series, and there is nothing to choose between
            ContentUnavailableView(
                "Only One Source",
                systemImage: "square.stack.3d.up.slash",
                description: Text("No other source has this chapter. Add another source to the series to read it from elsewhere.")
            )
            .transition(.opacity)
        }
    }


    func Options(_ slot: ChapterSlot) -> some View {
        ScrollView {
            LazyVStack(spacing: Layout.rowSpacing) {
                ForEach(sources(of: slot)) { source in
                    SourceRow(source)

                    // a source with one scanlator has nothing to expand into, so
                    // its row IS the choice and no chevron appears
                    if source.options.count > 1, expanded.contains(source.id) {
                        ForEach(source.options) { option in
                            ScanlatorRow(option)
                        }
                    }
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.bottom, dimensions.spacing.space24)
        }
        .scrollContentBackground(.hidden)
        .animation(Layout.expand, value: expanded)
        .animation(.settle, value: active)
        // the source you are reading from opens on its own, so the scanlator in
        // use is visible without hunting for it
        .onAppear {
            guard let source = sources(of: slot).first(where: { holds($0) }) else { return }
            expanded.insert(source.id)
        }
    }

    private func SourceRow(_ source: Source) -> some View {
        let many = source.options.count > 1

        return HStack(spacing: dimensions.spacing.space12) {
            SourceIcon(source.icon)

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(source.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                // branches, not a ternary: a ternary with a String on either side
                // erases the whole expression to String, and Text(String) renders
                // inflection markup verbatim. the literal has to reach Text intact
                Group {
                    if many {
                        Text("^[\(source.options.count) scanlator](inflect: true)")
                    } else {
                        Text(meta(source.options[0]))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if many {
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded.contains(source.id) ? 0 : -90))
            }
        }
        .padding(dimensions.spacing.space12)
        .background { Highlight(holds(source) && !expanded.contains(source.id)) }
        .contentShape(.rect)
        .tappable {
            guard many else {
                onSelect(source.options[0])
                dismiss()
                return
            }
            if expanded.contains(source.id) {
                expanded.remove(source.id)
            } else {
                expanded.insert(source.id)
            }
        }
    }

    func ScanlatorRow(_ option: ChapterSlot.Option) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            Text(meta(option))
                .font(.subheadline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Stored(option.downloaded)
        }
        .padding(dimensions.spacing.space12)
        .padding(.leading, Layout.indent)
        // the fill alone marks the serving row: a session swap is where you
        // are, not a stored preference, so it takes the position marker and
        // not the checkmark (selection-language.md)
        .background { Highlight(option.id == active) }
        .contentShape(.rect)
        .accessibilityAddTraits(option.id == active ? .isSelected : [])
        .tappable {
            onSelect(option)
            dismiss()
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // a download belongs to one row, not to a chapter number - so when ranking
    // moves, this is the screen that shows which row still holds the bytes
    @ViewBuilder
    func Stored(_ shown: Bool) -> some View {
        if shown {
            Image(systemName: "arrow.down.circle.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Downloaded")
        }
    }

    @ViewBuilder
    func Highlight(_ shown: Bool) -> some View {
        if shown {
            RoundedRectangle(cornerRadius: dimensions.radius.radius16)
                .fill(Palette.brand.opacity(Layout.currentOpacity))
        }
    }

    @ViewBuilder
    func SourceIcon(_ icon: ImageResource?) -> some View {
        if let icon {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius8))
        } else {
            RoundedRectangle(cornerRadius: dimensions.radius.radius8)
                .fill(.primary.opacity(Layout.fillOpacity))
                .frame(width: Layout.iconSize, height: Layout.iconSize)
        }
    }

    // whether the option in use belongs to this source, which is what lets a
    // collapsed row still show that it is the one being read
    private func holds(_ source: Source) -> Bool {
        source.options.contains { $0.id == active }
    }
}

// MARK: - Copy

private extension ReaderSourceSwitcher {
    // Text, not String: navigationSubtitle takes either and the String overload
    // renders inflection markup verbatim. counts SOURCES, not options - four
    // scanlators on one site is one place to read from, not four
    var subtitle: Text {
        guard let slot else { return Text("") }

        let count = Set(slot.options.map(\.originId)).count
        guard count > 1 else { return Text("Chapter \(number(slot.number))") }

        // one literal rather than concatenated Texts: Text's + is deprecated on
        // iOS 26, and interpolation keeps the whole thing a single key, which is
        // what the inflection markup needs to resolve
        return Text("Chapter \(number(slot.number)) · ^[\(count) source](inflect: true)")
    }

    func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    // the scanlator is the reason to pick one of these over another, so it leads
    func meta(_ option: ChapterSlot.Option) -> String {
        [option.scanlator, option.language.flag]
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }
}
