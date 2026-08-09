//
//  ReaderChapterList.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI

// the chapter capsule's destination. one row per chapter NUMBER rather than per
// row in the table, so a series merged from several sources reads as one list.
//
// the glass here is the SYSTEM's, not ours, and two things are load-bearing for
// it: a partial-height detent must exist, and presentationBackground must NOT be
// set. iOS 26 makes a partial sheet Liquid Glass on its own, turns it opaque at
// full height on purpose, and any background we set replaces the glass outright
struct ReaderChapterList: View {
    let slots: [ChapterSlot]
    let current: Double?
    let isLoading: Bool
    var onSelect: (ChapterSlot) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    @State private var anchored = false
    @State private var currentIsVisible = true
    @State private var currentIsAbove = true

    private enum Layout {
        static let iconSize: CGFloat = 32
        static let progressHeight: CGFloat = 3
        static let finishedOpacity: Double = 0.4
        static let fillOpacity: Double = 0.1
        static let currentOpacity: Double = 0.15
        static let rowSpacing: CGFloat = 2
        static let skeletonRows = 10
        static let skeletonBarHeight: CGFloat = 10
        static let skeletonTitle: CGFloat = 150
        static let skeletonMeta: CGFloat = 90
        static let jump: Animation = .snappy(duration: 0.3)
    }

    // newest first, which is how the series reads everywhere else in the app.
    // the list still opens on the chapter being read, so descending costs no
    // extra travel to get to it
    private var ordered: [ChapterSlot] {
        slots.reversed()
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Content(proxy)
                    .overlay(alignment: .bottom) { JumpToCurrent(proxy) }
            }
            .navigationTitle("Chapters")
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
        // medium first: the sheet opens on the chapter you are reading and most
        // trips end there. dragging up gets the whole series, at the cost of the
        // glass, which the system trades away at full height by design
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // the reader pins dark chrome deliberately, and a bright panel in a dark
        // room undoes that in one tap
        .environment(\.colorScheme, .dark)
        // keyed to the same value the branches switch on - a boolean key left
        // skeleton -> "No Chapters" (both empty) as a hard cut
        .animation(.settle, value: phase)
    }
}

// MARK: - Chrome

private extension ReaderChapterList {
    // Text, not String. navigationSubtitle takes either, and the String overload
    // renders inflection markup verbatim - the literal has to reach a Text
    var subtitle: Text {
        guard !slots.isEmpty else { return Text("") }
        guard let current else { return Text("^[\(slots.count) chapter](inflect: true)") }

        // one literal rather than concatenated Texts: Text's + is deprecated on
        // iOS 26, and interpolation keeps the whole thing a single key, which is
        // what the inflection markup needs to resolve
        return Text("^[\(slots.count) chapter](inflect: true) · on \(number(current))")
    }

    // a long list loses the chapter you are reading the moment you scroll, and
    // this is the way back. it only exists while the anchor is actually off
    // screen, so it is never a control asking to be used.
    //
    // every row here opens a chapter, so a pill naming one reads as another way
    // to do that. it has to say the thing it does instead - the chevron points
    // at where the chapter went, and "back to" is a return, not an open.
    //
    // brand-tinted and full size: it is only on screen when you have lost your
    // place, and something you go looking for has to be findable over a page of
    // artwork. glassProminent takes the tint rather than painting a flat capsule
    @ViewBuilder
    func JumpToCurrent(_ proxy: ScrollViewProxy) -> some View {
        if let current, !currentIsVisible, !slots.isEmpty {
            Button {
                withAnimation(Layout.jump) {
                    proxy.scrollTo(current, anchor: .center)
                }
            } label: {
                Label(
                    "Back to Chapter \(number(current))",
                    systemImage: currentIsAbove ? "chevron.up" : "chevron.down"
                )
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal, dimensions.spacing.space8)
                .padding(.vertical, dimensions.spacing.space4)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .tint(.brand)
            .padding(.bottom, dimensions.spacing.space16)
            .transition(.move(edge: currentIsAbove ? .top : .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Content

private extension ReaderChapterList {
    var phase: LoadPhase {
        if !slots.isEmpty { .content }
        else if isLoading { .pending }
        else { .empty }
    }

    @ViewBuilder
    func Content(_ proxy: ScrollViewProxy) -> some View {
        switch phase {
        case .pending:
            Skeleton
                .transition(.opacity)
        case .empty, .failed:
            ContentUnavailableView(
                "No Chapters",
                systemImage: "book.closed",
                description: Text("Nothing readable was found for this series.")
            )
            .transition(.opacity)
        case .content:
            Rows(proxy)
                .transition(.opacity)
        }
    }

    func Rows(_ proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: Layout.rowSpacing) {
                ForEach(ordered) { slot in
                    Row(slot)
                        .id(slot.number)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.bottom, dimensions.spacing.space64)
        }
        // a scroll view paints its own background over the sheet's glass unless
        // told not to
        .scrollContentBackground(.hidden)
        // the list is built before the rows exist, so anchoring on appear lands
        // on nothing. drive it off the data instead, once
        .onChange(of: slots.isEmpty, initial: true) {
            guard !anchored, !slots.isEmpty, let current else { return }
            anchored = true
            proxy.scrollTo(current, anchor: .center)
        }
        .onScrollTargetVisibilityChange(idType: Double.self) { visible in
            guard let current else { return }
            // the list runs newest first, so a chapter with a higher number than
            // anything on screen is above the fold rather than below it
            let above = visible.max().map { current > $0 } ?? currentIsAbove
            withAnimation(Layout.jump) {
                currentIsVisible = visible.contains(current)
                currentIsAbove = above
            }
        }
    }

    func Row(_ slot: ChapterSlot) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            SourceIcon(slot)

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(title(slot))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(meta(slot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if slot.started {
                    ProgressView(value: slot.progress)
                        .tint(.brand)
                        .frame(height: Layout.progressHeight)
                        .clipShape(.capsule)
                        .padding(.top, dimensions.spacing.space4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if slot.finished {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(dimensions.spacing.space12)
        // a tint rather than another surface: the chapter being read is the
        // anchor, and a card here would be a second material over the glass
        .background {
            if isCurrent(slot) {
                RoundedRectangle(cornerRadius: dimensions.radius.radius16)
                    .fill(Palette.brand.opacity(Layout.currentOpacity))
            }
        }
        // a finished chapter recedes, but the one being read never does - it is
        // the row the sheet opened for
        .opacity(slot.finished && !isCurrent(slot) ? Layout.finishedOpacity : 1)
        .contentShape(.rect)
        .tappable {
            onSelect(slot)
            dismiss()
        }
    }

    @ViewBuilder
    func SourceIcon(_ slot: ChapterSlot) -> some View {
        if let icon = slot.best.sourceIcon {
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
}

// MARK: - Copy

private extension ReaderChapterList {
    func isCurrent(_ slot: ChapterSlot) -> Bool {
        slot.number == current
    }

    // most sources title a chapter with its own number, which then reads as the
    // same thing twice on one line
    func title(_ slot: ChapterSlot) -> String {
        let label = "Chapter \(number(slot.number))"
        let title = slot.best.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.lowercased() != label.lowercased() else { return label }
        return "\(label) · \(title)"
    }

    func meta(_ slot: ChapterSlot) -> String {
        [
            slot.best.scanlator,
            slot.best.language.flag,
            slot.best.publishedDate.formatted(.relative(presentation: .numeric))
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
    }

    // chapter numbers are stored as doubles - render 12.0 as "12", keep 12.5
    func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

// MARK: - Loading

private extension ReaderChapterList {
    var Skeleton: some View {
        ScrollView {
            LazyVStack(spacing: Layout.rowSpacing) {
                ForEach(0..<Layout.skeletonRows, id: \.self) { _ in
                    SkeletonRow
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .shimmer()
        }
        .scrollContentBackground(.hidden)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    var SkeletonRow: some View {
        HStack(spacing: dimensions.spacing.space12) {
            RoundedRectangle(cornerRadius: dimensions.radius.radius8)
                .fill(.primary.opacity(Layout.fillOpacity))
                .frame(width: Layout.iconSize, height: Layout.iconSize)

            VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                Bar(Layout.skeletonTitle)
                Bar(Layout.skeletonMeta)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(dimensions.spacing.space12)
    }

    func Bar(_ width: CGFloat) -> some View {
        Capsule()
            .fill(.primary.opacity(Layout.fillOpacity))
            .frame(maxWidth: width, alignment: .leading)
            .frame(height: Layout.skeletonBarHeight)
    }
}
