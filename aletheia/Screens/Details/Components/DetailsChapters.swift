//
//  DetailsChapters.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI
import Foundation
import Tagged

struct DetailsChapters: View {
    let chapters: [Chapter]
    var isFetching: Bool = false
    var hasFetched: Bool = true
    // counts every origin, disabled ones included: two sources is exactly when
    // reordering starts to matter, and the common reason to reorder is to put a
    // working source above one you have turned off
    var sourceCount: Int = 0
    // series-scoped, so they live on the row rather than in UserDefaults
    var showAllChapters: Bool = false
    var showHalfChapters: Bool = true
    var onShowAllChapters: (Bool) -> Void
    var onShowHalfChapters: (Bool) -> Void
    // refresh and mark-all deliberately absent: DetailsActions already owns them,
    // one screen up. no surveyed reader duplicates its chapter bulk actions
    var onSources: () -> Void
    var onScanlators: () -> Void
    var onLanguages: () -> Void
    var onMark: (_ read: Bool, _ numbers: [Double]) -> Void
    // the queue itself, so a row can ask whether it is in it. reading `index` is
    // a membership read - it changes on enqueue and finish, seconds apart - and
    // the per-page ticks are read off the returned instance instead
    var downloads: Compositor.Downloads?
    var onDownload: (_ id: Int64) -> Void = { _ in }
    var onCancelDownload: (_ id: Int64) -> Void = { _ in }
    var onDelete: (_ id: Int64) -> Void = { _ in }
    var onOpen: (Chapter) -> Void

    @Environment(\.dimensions) private var dimensions

    @State private var sort: Sort = .numberDescending
    @State private var isExpanded = false

    // named for what the reader wants, not for the column being sorted. "number
    // descending" describes the query; "latest first" describes the intent that
    // sent you to the menu. which field it sorts on is the section header's job
    private enum Sort: Hashable {
        case numberDescending
        case numberAscending
        case dateNewest
        case dateOldest

        // one word each. the section header already names the field, so the label
        // only has to say which end you land on - and the chip below shows the
        // chosen word alone, where a phrase reads as a sentence fragment
        var label: String {
            switch self {
            case .numberDescending: "Latest"
            case .numberAscending: "First"
            case .dateNewest: "Recent"
            case .dateOldest: "Oldest"
            }
        }

        // one glyph per intent rather than a pair of arrows. an arrow only says
        // which way the list runs, which the label already said - these say what
        // you came for: the new stuff, the beginning, what just landed, the start
        // of the archive
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
        // roughly "Chapter 12 • 2 months ago • flag"
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

    // what the row's trailing control is currently showing. a chapter's own
    // bytes and the queue are two different facts, and this is where they
    // collapse into the single thing a person taps
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
        // has to sit on an ancestor that survives the swap - on the Group itself
        // it is replaced along with the branch, so nothing drives the transition
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

    // nothing to show yet and no fetch has landed - unknown, not empty
    private var isPending: Bool {
        chapters.isEmpty && (isFetching || !hasFetched)
    }

    // one value for the whole section to animate on. switching on the two
    // booleans separately would let the skeleton and the list cross-dissolve
    // through the empty state on the way
    fileprivate var phase: LoadPhase {
        if !chapters.isEmpty { .content }
        else if isPending { .pending }
        else { .empty }
    }
}

extension DetailsChapters {
    private var Header: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            SectionHeader(title: "Chapters") { Visibility }

            HStack(spacing: dimensions.spacing.space8) {
                Count

                SortChip

                Spacer(minLength: 0)

                Filters
            }
        }
    }

    // back in the section header, where the other sections put their one control.
    // it belongs above the row rather than in it: the three below reorder what
    // wins, these two change what the list is made of
    private var Visibility: some View {
        Menu {
            // two copies of one thing, which is exactly what this reveals: the
            // same chapter number from every source rather than only the winner.
            // deliberately not the 3d stack - that is the source button's glyph,
            // and these two do different jobs
            Toggle(isOn: allChapters) {
                Label("Show All", systemImage: "square.on.square")
            }

            // a literal half rather than a division sign: the setting is about
            // chapter 52.5 existing, not about dividing anything
            //
            // off and dimmed while everything is shown - a list that hides nothing
            // cannot be hiding half chapters, so the switch would be a lie
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

    // reads as on whenever everything is shown, so the row agrees with the list
    private var halfChapters: Binding<Bool> {
        Binding(
            get: { showAllChapters || showHalfChapters },
            set: onShowHalfChapters
        )
    }

    // three separate capsules rather than one segmented group: these narrow three
    // independent axes, and a shared container asserts they are one control with
    // three modes. spacing carries the relationship instead.
    //
    // all three always present, including on a series with one of everything - a
    // row whose controls come and go is harder to learn than one that is always
    // the same shape
    private var Filters: some View {
        HStack(spacing: dimensions.spacing.space8) {
            // opens Source Priority rather than a filter: with one source there
            // is no order to change, so it stays visible but inert
            Filter(
                "plus.square.dashed",
                "Change source priority",
                enabled: sourceCount > 1,
                action: onSources
            )

            Filter("person.2", "Filter by scanlator", action: onScanlators)

            // a character in a bubble, not a globe: a globe reads as the web as
            // often as language, and this narrows what the chapter is written in
            Filter("translate", "Filter by language", action: onLanguages)
        }
    }

    // dimmed rather than removed when it cannot act - the row keeps its shape,
    // and a control that is present but inert reads as "nothing to do here"
    // rather than as a feature the app does not have
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

    // a menu row has exactly one image slot and iOS renders it trailing, so the
    // checkmark takes the icon's place rather than sitting beside it. the icon
    // has done its job by then - you are looking at the row you already chose
    private func Option(_ option: Sort) -> some View {
        Button {
            sort = option
        } label: {
            Label(option.label, systemImage: option == sort ? "checkmark" : option.icon)
        }
    }

    // padded to a pill, not framed to a square: at 44x44 a capsule renders as a
    // circle, which sat beside the sort chip's pill as a different shape. same
    // construction as the sort label so the two match by being built alike
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
            // buttons rather than a Picker: a Picker draws its checkmark on the
            // leading edge and there is no way to move it. sections still say
            // which field each pair sorts on, which is what the labels leave out -
            // number and date disagree whenever a source backfills
            Section("Chapter number") {
                Option(.numberDescending)
                Option(.numberAscending)
            }

            Section("Release date") {
                Option(.dateNewest)
                Option(.dateOldest)
            }
        } label: {
            // neutral, not brand. a sort is always set, so a permanent tint says
            // nothing - and blue already means "a filter is on" one screen over.
            // the accent is reserved for state that varies
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
        // a Menu tints its own label with the accent colour, and .primary in the
        // background above then resolves against that tint rather than neutral -
        // which is why this capsule read differently to the filter's
        .menuStyle(.button)
        .buttonStyle(.plain)
    }
}

private extension View {
    // one definition, so the two controls cannot drift apart again
    func chipBackground(_ opacity: Double) -> some View {
        background(.primary.opacity(opacity), in: .capsule)
    }
}

extension DetailsChapters {
    private var Chapters: some View {
        Group {
            switch phase {
            // "none" is only true once a fetch has landed - before that the list
            // is unknown, not empty, and saying otherwise is a lie for a minute
            case .pending:
                Skeleton
                    .transition(.opacity)

            // a chapter fetch that fails surfaces through the action alert, so
            // the section itself never reaches .failed - it renders as empty
            case .empty, .failed:
                EmptyState
                    .transition(.opacity)

            case .content:
                LazyVStack(spacing: 0) {
                    ForEach(displayed) { chapter in
                        Divider()
                        // on the row, not inside Details - Details carries the
                        // canRead .disabled, and marking or opening in browser
                        // must survive an uninstalled source
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
        // on the container, so one sweep crosses every row - per-row masks are
        // n independent animated gradients saying the same thing
        .shimmer()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

    // two different empties. a fetch that landed and found nothing is a fact
    // about the source; a fetch that never ran is a fact about us, and saying
    // "no chapters" there states the source's position on something it was
    // never asked. the way out is the same in both cases and already on this
    // screen twice - pull to refresh, and Refresh Chapters in the actions above
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
            Storage(chapter)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // the lookup is a read of the collection - it answers WHICH download - and
    // the progress is read off the returned instance, which is what keeps a page
    // landing on chapter 3 from redrawing the other two hundred rows. a row whose
    // lookup returns nil is subscribed to membership alone and never ticks
    private func Storage(_ chapter: Chapter) -> some View {
        let download = downloads?.index[ChapterRecord.ID(rawValue: chapter.id)]
        let state = state(for: chapter, download)
        // read unconditionally rather than on a branch of the switch below: a
        // read that only happens in one case is not a dependency in the others
        let fraction = download?.fraction ?? 0

        return ZStack {
            // the track, carrying the ring at rest so the trim has something to
            // fill rather than appearing out of nothing
            Circle()
                .stroke(lineWidth: Layout.ringWidth)
                .foregroundStyle(.brand)
                .opacity(state.tracked ? Layout.ringTrackOpacity : 0)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(style: StrokeStyle(lineWidth: Layout.ringWidth, lineCap: .round, lineJoin: .round))
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
        // completed is a status, not a control: deleting a chapter's bytes off a
        // 20pt target sitting where "downloading, tap to stop" was a second ago is
        // one mistap away, so deletion lives in the context menu and nowhere else
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

            // a stop rather than an x: the ring around it is the thing being
            // stopped, and the glyph sits inside it
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

    // downloaded is this row's own bytes, so it outranks a queue entry that can
    // only be a re-download of something already on disk
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

    // relative to the sorted list as displayed, tapped row included - "above"
    // means what is on screen above your thumb, not a chapter-number comparison
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
        let url: URL

        // nil when the origin's source is no longer installed
        let sourceIcon: ImageResource?

        // an uninstalled or disabled source can still show its chapters, but
        // nothing can fetch pages for them
        let canRead: Bool

        // this row's own bytes, not this chapter number's. two sources serving
        // chapter 44 are two rows with two paths, and downloading one says
        // nothing about the other (offline-availability.md)
        let downloaded: Bool

        var finished: Bool { progress >= 1 }
    }
}
