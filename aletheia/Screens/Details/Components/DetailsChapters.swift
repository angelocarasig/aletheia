//
//  DetailsChapters.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI
import Foundation

struct DetailsChapters: View {
    let chapters: [Chapter]
    var isFetching: Bool = false
    var hasFetched: Bool = true
    var canRefresh: Bool = false
    var onRefresh: () -> Void
    var onMarkAll: (Bool) -> Void
    var onOpen: (Chapter) -> Void

    @Environment(\.dimensions) private var dimensions

    @State private var sort: Sort = .numberDescending
    @State private var isExpanded = false

    private enum Sort: String, CaseIterable {
        case numberDescending = "Number descending"
        case numberAscending = "Number ascending"
        case dateNewest = "Date newest"
        case dateOldest = "Date oldest"
    }

    private enum Layout {
        static let collapsedLimit = 8
        static let skeletonRows = 6
        static let skeletonBarHeight: CGFloat = 10
        // roughly "Chapter 12 • 2 months ago • flag"
        static let skeletonMeta: [CGFloat] = [64, 6, 96, 6, 16]
        static let skeletonScanlator: CGFloat = 88
        static let sourceIconSize: CGFloat = 44
        static let newDayThreshold = 3
        static let progressHeight: CGFloat = 3
        static let titleLines = 2
        static let emptyStateHeight: CGFloat = 200
        static let finishedOpacity: Double = 0.5
        static let fillOpacity: Double = 0.1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            Header
            Chapters
        }
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

    // nothing to show yet and no fetch has landed - unknown, not empty
    private var isPending: Bool {
        chapters.isEmpty && (isFetching || !hasFetched)
    }
}

extension DetailsChapters {
    private var Header: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            SectionHeader(title: "Chapters") { Overflow }

            HStack(spacing: dimensions.spacing.space8) {
                Count

                SortChip
            }
        }
    }

    @ViewBuilder
    private var Count: some View {
        if isPending {
            Text("Loading chapters")
                .font(.subheadline)
                .foregroundStyle(.muted)
        } else {
            Text("^[\(chapters.count) chapter](inflect: true)")
                .font(.subheadline)
                .foregroundStyle(.muted)
        }
    }

    private var Overflow: some View {
        Menu {
            Button(action: onRefresh) {
                Label("Refresh Chapters", systemImage: "arrow.clockwise")
            }
            .disabled(!canRefresh)

            Divider()

            Button {
                onMarkAll(true)
            } label: {
                Label("Mark All as Read", systemImage: "checkmark.circle.fill")
            }

            Button {
                onMarkAll(false)
            } label: {
                Label("Mark All as Unread", systemImage: "x.circle.fill")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body)
                .fontWeight(.medium)
                .foregroundStyle(.muted)
                .frame(width: dimensions.size.control, height: dimensions.size.control)
                .contentShape(.rect)
        }
    }

    private var SortChip: some View {
        Menu {
            ForEach(Sort.allCases, id: \.self) { option in
                Button {
                    sort = option
                } label: {
                    if option == sort {
                        Label(option.rawValue, systemImage: "checkmark")
                    } else {
                        Text(option.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: dimensions.spacing.space4) {
                Text(sort.rawValue)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .fontWeight(.bold)
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.brand)
            .padding(.horizontal, dimensions.spacing.space8)
            .padding(.vertical, dimensions.spacing.space4)
            .background(Palette.brand.opacity(Layout.fillOpacity), in: .capsule)
        }
    }
}

extension DetailsChapters {
    @ViewBuilder
    private var Chapters: some View {
        if chapters.isEmpty {
            // "none" is only true once a fetch has landed - before that the list
            // is unknown, not empty, and saying otherwise is a lie for a minute
            if isPending {
                Skeleton
            } else {
                EmptyState
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(displayed) { chapter in
                    Divider()
                    Row(chapter)
                }

                if hasMore {
                    ExpandToggle
                }
            }
        }
    }

    // built from explicit bars rather than redacted text: redaction sizes each
    // block to the width of the string behind it, so placeholder copy leaves the
    // row two thirds empty no matter what it says
    private var Skeleton: some View {
        LazyVStack(spacing: 0) {
            ForEach(0..<Layout.skeletonRows, id: \.self) { _ in
                Divider()
                SkeletonRow
            }
        }
        .allowsHitTesting(false)
    }

    private var SkeletonRow: some View {
        HStack(alignment: .center, spacing: dimensions.spacing.space12) {
            RoundedRectangle(cornerRadius: dimensions.radius.radius8)
                .fill(.primary.opacity(Layout.fillOpacity))
                .frame(width: Layout.sourceIconSize, height: Layout.sourceIconSize)

            // mirrors Details: meta line, full-width title, scanlator
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

    // nil width fills the row - a fixed one stops short, as real metadata does
    private func Bar(_ width: CGFloat?) -> some View {
        Capsule()
            .fill(.primary.opacity(Layout.fillOpacity))
            .frame(maxWidth: width ?? .infinity, alignment: .leading)
            .frame(height: Layout.skeletonBarHeight)
    }

    private var EmptyState: some View {
        ContentUnavailableView(
            "No Chapters",
            systemImage: "book.closed",
            description: Text("No chapters available")
        )
        .frame(height: Layout.emptyStateHeight)
    }

    private var ExpandToggle: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            Text(isExpanded ? "Show Less" : "Show All \(chapters.count) Chapters")
        }
        .font(.subheadline)
        .foregroundStyle(.brand)
        .frame(maxWidth: .infinity)
        .padding(dimensions.spacing.space16)
        .background(Palette.brand.opacity(Layout.fillOpacity), in: .rect(cornerRadius: dimensions.radius.radius8))
        .padding(.top, dimensions.spacing.space8)
        .tappable {
            withAnimation { isExpanded.toggle() }
        }
    }

    private func Row(_ chapter: Chapter) -> some View {
        HStack(alignment: .center, spacing: dimensions.spacing.space12) {
            SourceIcon(chapter)
            Details(chapter)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // which source this chapter came from - the only per-row signal that a
    // multi-origin series is being merged together
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
                Badge(text: "NEW")
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

    // chapter numbers are stored as doubles - render 12.0 as "12" but keep 12.5
    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}

extension DetailsChapters {
    struct Chapter: Identifiable, Hashable {
        let id: Int64
        let number: Double
        let title: String
        let scanlator: String
        let language: LanguageCode
        let publishedDate: Date
        let progress: Double

        // nil when the origin's source is no longer installed
        let sourceIcon: ImageResource?

        // an uninstalled or disabled source can still show its chapters, but
        // nothing can fetch pages for them
        let canRead: Bool

        var finished: Bool { progress >= 1 }
    }
}
