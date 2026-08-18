//
//  DetailsChapters.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation
import SwiftUI
import Tagged

struct DetailsChapters: View {
    let chapters: [Chapter]
    var isFetching: Bool = false
    var cadence: DetailsComposer.Cadence?
    var hasFetched: Bool = true
    var sourceCount: Int = 0
    var showAllChapters: Bool = false
    var showHalfChapters: Bool = true
    var onShowAllChapters: (Bool) -> Void
    var onShowHalfChapters: (Bool) -> Void
    var onSources: () -> Void
    var onScanlators: () -> Void
    var onLanguages: () -> Void
    var onMark: (_ read: Bool, _ numbers: [Double]) -> Void
    var downloads: Compositor.Downloads?
    var onDownload: (_ id: Int64) -> Void = { _ in }
    var onCancelDownload: (_ id: Int64) -> Void = { _ in }
    var onDelete: (_ id: Int64) -> Void = { _ in }
    var onOpen: (Chapter) -> Void

    @Environment(\.dimensions) private var dimensions

    @State private var sort: Sort = .numberDescending
    @State private var isExpanded = false

    private enum Sort: Hashable {
        case numberDescending
        case numberAscending
        case dateNewest
        case dateOldest

        var label: String {
            switch self {
            case .numberDescending: "Latest"
            case .numberAscending: "First"
            case .dateNewest: "Recent"
            case .dateOldest: "Oldest"
            }
        }

        var icon: String {
            switch self {
            case .numberDescending: "sparkles"
            case .numberAscending: "1.circle"
            case .dateNewest: "clock"
            case .dateOldest: "clock.arrow.circlepath"
            }
        }
    }

    private enum Layout {
        static let collapsedLimit = 8
        static let skeletonRows = 6
        static let skeletonBarHeight: CGFloat = 10
        static let skeletonMeta: [CGFloat] = [64, 6, 96, 6, 16]
        static let skeletonScanlator: CGFloat = 88
        static let sourceIconSize: CGFloat = 44
        static let newDayThreshold = 3
        static let progressHeight: CGFloat = 3
        static let titleLines = 2
        static let emptyStateHeight: CGFloat = 200
        static let finishedOpacity: Double = 0.5
        static let disabledOpacity: Double = 0.35
        static let fillOpacity: Double = 0.1
        static let ringWidth: CGFloat = 2
        static let ringTrackOpacity: Double = 0.3
        static let ringDuration: Double = 0.1
    }

    private enum DownloadPhase: Equatable {
        case idle
        case queued
        case downloading
        case failed
        case completed

        var tracked: Bool {
            self == .queued || self == .downloading
        }

        var label: String {
            switch self {
            case .idle: "Download"
            case .queued: "Waiting to download, tap to cancel"
            case .downloading: "Downloading, tap to cancel"
            case .failed: "Download failed, tap to retry"
            case .completed: "Downloaded"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            Header
            Chapters
        }
        // animation must live on a container that survives the phase swap; on Group
        // itself it is replaced along with the branch, so nothing drives the transition
        .animation(.settle, value: phase)
    }

    private var sorted: [Chapter] {
        switch sort {
        case .numberDescending: chapters.sorted { $0.number > $1.number }
        case .numberAscending: chapters.sorted { $0.number < $1.number }
        case .dateNewest: chapters.sorted { $0.publishedDate > $1.publishedDate }
        case .dateOldest: chapters.sorted { $0.publishedDate < $1.publishedDate }
        }
    }

    private var displayed: [Chapter] {
        guard !isExpanded else { return sorted }
        return Array(sorted.prefix(Layout.collapsedLimit))
    }

    private var hasMore: Bool {
        chapters.count > Layout.collapsedLimit
    }

    private var isPending: Bool {
        chapters.isEmpty && (isFetching || !hasFetched)
    }

    fileprivate var phase: LoadPhase {
        if !chapters.isEmpty { .content } else if isPending { .pending } else { .empty }
    }
}

extension DetailsChapters {
    private var Header: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            SectionHeader(title: "Chapters") { Visibility }

            if let cadence {
                DetailsCadence(
                    display: cadence.current.display,
                    force: cadence.canForce
                        ? (glyph: cadence.forceGlyph, action: { cadence.force() })
                        : nil
                )
                .padding(.bottom, dimensions.spacing.space4)
            }

            HStack(spacing: dimensions.spacing.space8) {
                Count

                SortChip

                Spacer(minLength: 0)

                Filters
            }
        }
    }

    private var Visibility: some View {
        Menu {
            Toggle(isOn: allChapters) {
                Label("Show All", systemImage: "square.on.square")
            }

            Toggle(isOn: halfChapters) {
                Label("Show Half", systemImage: "circle.lefthalf.filled")
            }
            .disabled(showAllChapters)
        } label: {
            Icon("ellipsis")
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    private var allChapters: Binding<Bool> {
        Binding(get: { showAllChapters }, set: onShowAllChapters)
    }

    private var halfChapters: Binding<Bool> {
        Binding(
            get: { showAllChapters || showHalfChapters },
            set: onShowHalfChapters
        )
    }

    private var Filters: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Filter(
                "plus.square.dashed",
                "Change source priority",
                enabled: sourceCount > 1,
                action: onSources
            )

            Filter("person.2", "Filter by scanlator", action: onScanlators)

            Filter("translate", "Filter by language", action: onLanguages)
        }
    }

    private func Filter(
        _ name: String,
        _ label: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Icon(name)
            .chipBackground(Layout.fillOpacity)
            .contentShape(.capsule)
            .tappable(action: action)
            .disabled(!enabled)
            .opacity(enabled ? 1 : Layout.disabledOpacity)
            .accessibilityLabel(label)
    }

    // a Menu row has one image slot rendered trailing, so the checkmark takes
    // the icon's place rather than sitting beside it
    private func Option(_ option: Sort) -> some View {
        Button {
            sort = option
        } label: {
            Label(option.label, systemImage: option == sort ? "checkmark" : option.icon)
        }
    }

    private func Icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.muted)
            .padding(.horizontal, dimensions.spacing.space16)
            .frame(height: dimensions.touchTarget)
    }

    @ViewBuilder
    private var Count: some View {
        Group {
            if isPending {
                Text("Loading chapters")
            } else {
                Text("^[\(chapters.count) chapter](inflect: true)")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.muted)
        .contentTransition(.numericText())
        .animation(.settle, value: phase)
    }

    private var SortChip: some View {
        Menu {
            // buttons, not Picker - a Picker's checkmark is fixed to the leading edge
            Section("Chapter number") {
                Option(.numberDescending)
                Option(.numberAscending)
            }

            Section("Release date") {
                Option(.dateNewest)
                Option(.dateOldest)
            }
        } label: {
            HStack(spacing: dimensions.spacing.space4) {
                Text(sort.label)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.muted)
            .padding(.horizontal, dimensions.spacing.space12)
            .frame(height: dimensions.touchTarget)
            .chipBackground(Layout.fillOpacity)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }
}

extension View {
    fileprivate func chipBackground(_ opacity: Double) -> some View {
        background(.primary.opacity(opacity), in: .capsule)
    }
}

extension DetailsChapters {
    private var Chapters: some View {
        Group {
            switch phase {
            case .pending:
                Skeleton
                    .transition(.opacity)

            // chapter fetch failures surface via the action alert, so this
            // never reaches .failed here - it renders as empty instead
            case .empty, .failed:
                EmptyState
                    .transition(.opacity)

            case .content:
                LazyVStack(spacing: 0) {
                    ForEach(displayed) { chapter in
                        Divider()
                        // context menu on Row, not Details - Details carries the
                        // canRead .disabled, which would block mark/open-in-browser
                        // for an uninstalled source's chapters
                        Row(chapter)
                            .contextMenu { RowMenu(chapter) }
                    }

                    if hasMore {
                        ExpandToggle
                    }
                }
                .transition(.opacity)
            }
        }
    }

    // explicit bars, not redacted text - redaction sizes each block to the
    // width of the string behind it, leaving the row mostly empty
    private var Skeleton: some View {
        LazyVStack(spacing: 0) {
            ForEach(0..<Layout.skeletonRows, id: \.self) { _ in
                Divider()
                SkeletonRow
            }
        }
        .shimmer()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var SkeletonRow: some View {
        HStack(alignment: .center, spacing: dimensions.spacing.space12) {
            RoundedRectangle(cornerRadius: dimensions.radius.radius8)
                .fill(.primary.opacity(Layout.fillOpacity))
                .frame(width: Layout.sourceIconSize, height: Layout.sourceIconSize)

            VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                HStack(spacing: dimensions.spacing.space4) {
                    ForEach(Array(Layout.skeletonMeta.enumerated()), id: \.offset) { _, width in
                        Bar(width)
                    }
                    Spacer(minLength: 0)
                }

                Bar(nil)
                Bar(Layout.skeletonScanlator)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, dimensions.spacing.space12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .shimmer()
    }

    private func Bar(_ width: CGFloat?) -> some View {
        Capsule()
            .fill(.primary.opacity(Layout.fillOpacity))
            .frame(maxWidth: width ?? .infinity, alignment: .leading)
            .frame(height: Layout.skeletonBarHeight)
    }

    private var EmptyState: some View {
        ContentUnavailableView(
            hasFetched ? "No Chapters" : "No Chapters Yet",
            systemImage: hasFetched ? "book.closed" : "arrow.clockwise",
            description: hasFetched
                ? Text("This source has no chapters for this series.")
                : Text("This series hasn't been checked for chapters yet. Pull down to refresh.")
        )
        .frame(height: Layout.emptyStateHeight)
    }

    private var ExpandToggle: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .contentTransition(.symbolEffect(.replace))
            Text(isExpanded ? "Show Less" : "Show All \(chapters.count) Chapters")
        }
        .font(.subheadline)
        .foregroundStyle(.brand)
        .frame(maxWidth: .infinity)
        .padding(dimensions.spacing.space16)
        .background(
            Palette.brand.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius8)
        )
        .padding(.top, dimensions.spacing.space8)
        .tappable {
            withAnimation { isExpanded.toggle() }
        }
    }

    private func Row(_ chapter: Chapter) -> some View {
        HStack(alignment: .center, spacing: dimensions.spacing.space12) {
            SourceIcon(chapter)
            Details(chapter)
            Storage(chapter)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // index is a membership read; the returned instance is what keeps a page
    // landing on one chapter from re-rendering the other two hundred rows
    private func Storage(_ chapter: Chapter) -> some View {
        let download = downloads?.index[ChapterRecord.ID(rawValue: chapter.id)]
        let state = state(for: chapter, download)
        // read unconditionally - a conditional read isn't a tracked dependency
        // in the branches that skip it
        let fraction = download?.fraction ?? 0

        return ZStack {
            Circle()
                .stroke(lineWidth: Layout.ringWidth)
                .foregroundStyle(.brand)
                .opacity(state.tracked ? Layout.ringTrackOpacity : 0)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    style: StrokeStyle(
                        lineWidth: Layout.ringWidth, lineCap: .round, lineJoin: .round)
                )
                .foregroundStyle(.brand)
                .rotationEffect(.degrees(-90))
                .opacity(state == .downloading ? 1 : 0)
                .animation(.linear(duration: Layout.ringDuration), value: fraction)

            Glyph(state)
        }
        .frame(width: dimensions.size.icon20, height: dimensions.size.icon20)
        .frame(width: dimensions.touchTarget, height: dimensions.touchTarget)
        .opacity(state == .idle && !chapter.canRead ? Layout.disabledOpacity : 1)
        .contentShape(.rect)
        .tappable { act(state, on: chapter) }
        // completed stays non-tappable - deleting off a 20pt target that was
        // "downloading, tap to stop" a second ago is one mistap away, so
        // deletion lives in the context menu only
        .disabled(state == .completed || (state == .idle && !chapter.canRead))
        .accessibilityLabel(state.label)
        .animation(.settle, value: state)
    }

    @ViewBuilder
    private func Glyph(_ state: DownloadPhase) -> some View {
        Group {
            switch state {
            case .idle:
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.muted)

            case .queued:
                Image(systemName: "clock.fill")
                    .foregroundStyle(.brand)

            case .downloading:
                Image(systemName: "stop.fill")
                    .font(.caption2)
                    .foregroundStyle(.brand)

            case .failed:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.danger)

            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.success)
            }
        }
        .font(.title3)
        .contentTransition(.symbolEffect(.replace))
    }

    private func state(for chapter: Chapter, _ download: Download?) -> DownloadPhase {
        if chapter.downloaded { return .completed }

        guard let download else { return .idle }

        switch download.state {
        case .queued, .preparing: return .queued
        case .downloading: return .downloading
        case .failed: return .failed
        }
    }

    private func act(_ state: DownloadPhase, on chapter: Chapter) {
        switch state {
        case .idle, .failed: onDownload(chapter.id)
        case .queued, .downloading: onCancelDownload(chapter.id)
        case .completed: break
        }
    }

    @ViewBuilder
    private func RowMenu(_ chapter: Chapter) -> some View {
        ControlGroup {
            Button {
                onMark(true, [chapter.number])
            } label: {
                Label("Mark Read", systemImage: "book.closed")
            }
            .disabled(chapter.finished)

            Button {
                onMark(false, [chapter.number])
            } label: {
                Label("Mark Unread", systemImage: "book")
            }
            .disabled(chapter.progress == 0)
        }

        if chapter.downloaded {
            Button(role: .destructive) {
                onDelete(chapter.id)
            } label: {
                Label("Delete Download", systemImage: "trash")
            }
        } else if downloads?.index[ChapterRecord.ID(rawValue: chapter.id)] != nil {
            Button(role: .destructive) {
                onCancelDownload(chapter.id)
            } label: {
                Label("Cancel Download", systemImage: "xmark.circle")
            }
        } else {
            Button {
                onDownload(chapter.id)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .disabled(!chapter.canRead)
        }

        Link(destination: chapter.url) {
            Label("Open in Browser", systemImage: "safari")
        }

        Divider()

        ControlGroup {
            Button {
                onMark(true, numbers(above: chapter))
            } label: {
                Label("Read Above", systemImage: "arrow.up.square.fill")
            }

            Button {
                onMark(true, numbers(below: chapter))
            } label: {
                Label("Read Below", systemImage: "arrow.down.square.fill")
            }

            Button {
                onMark(true, chapters.map(\.number))
            } label: {
                Label("Read All", systemImage: "books.vertical.fill")
            }
        }

        ControlGroup {
            Button {
                onMark(false, numbers(above: chapter))
            } label: {
                Label("Unread Above", systemImage: "arrow.up.square")
            }

            Button {
                onMark(false, numbers(below: chapter))
            } label: {
                Label("Unread Below", systemImage: "arrow.down.square")
            }

            Button {
                onMark(false, chapters.map(\.number))
            } label: {
                Label("Unread All", systemImage: "books.vertical")
            }
        }
    }

    // "above"/"below" is position in the sorted list, not chapter-number comparison
    private func numbers(above chapter: Chapter) -> [Double] {
        guard let index = sorted.firstIndex(where: { $0.id == chapter.id }) else {
            return [chapter.number]
        }
        return sorted[...index].map(\.number)
    }

    private func numbers(below chapter: Chapter) -> [Double] {
        guard let index = sorted.firstIndex(where: { $0.id == chapter.id }) else {
            return [chapter.number]
        }
        return sorted[index...].map(\.number)
    }

    @ViewBuilder
    private func SourceIcon(_ chapter: Chapter) -> some View {
        if let icon = chapter.sourceIcon {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: Layout.sourceIconSize, height: Layout.sourceIconSize)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius8))
        } else {
            RoundedRectangle(cornerRadius: dimensions.radius.radius8)
                .fill(.primary.opacity(Layout.fillOpacity))
                .frame(width: Layout.sourceIconSize, height: Layout.sourceIconSize)
                .shimmer()
        }
    }

    private func Details(_ chapter: Chapter) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
            Meta(chapter)

            Text(chapter.title.isEmpty ? "Chapter \(number(chapter.number))" : chapter.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(Layout.titleLines)
                .multilineTextAlignment(.leading)

            Text(chapter.scanlator)
                .font(.caption)
                .foregroundStyle(.muted)
                .lineLimit(1)

            if chapter.progress > 0 && !chapter.finished {
                ProgressView(value: chapter.progress)
                    .tint(.brand)
                    .frame(height: Layout.progressHeight)
                    .clipShape(.capsule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, dimensions.spacing.space12)
        .opacity(chapter.finished || !chapter.canRead ? Layout.finishedOpacity : 1)
        .contentShape(.rect)
        .tappable { onOpen(chapter) }
        .disabled(!chapter.canRead)
    }

    private func Meta(_ chapter: Chapter) -> some View {
        HStack(spacing: dimensions.spacing.space4) {
            Text("Chapter \(number(chapter.number))")

            Separator
            Text(chapter.publishedDate.formatted(.relative(presentation: .numeric)))
                .lineLimit(1)
                .foregroundStyle(.muted)

            Separator
            Text(chapter.language.flag)

            if isNew(chapter) {
                Badge(text: "NEW", size: .compact)
            }
        }
        .font(.caption)
    }

    private var Separator: some View {
        Text("•")
            .foregroundStyle(.muted)
    }

    private func isNew(_ chapter: Chapter) -> Bool {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Layout.newDayThreshold, to: .now)
        guard let cutoff else { return false }
        return chapter.publishedDate >= cutoff
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

extension DetailsChapters {
    typealias Chapter = DetailsComposer.Chapters.Row
}
