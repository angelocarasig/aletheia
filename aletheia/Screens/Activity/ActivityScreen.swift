//
//  ActivityScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI
import Tagged

// what happened, newest first - one row per series per day, merged from the
// reading log. the transient "Now" slot above the feed is reserved for live
// operations (library refresh, downloads) and stays empty until those
// subsystems exist; live tasks never become feed rows.
// see docs/features/background-activity.md
struct ActivityScreen: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    @State private var vm: ActivityViewModel?
    @State private var reading: ReadingTarget?

    private struct ReadingTarget: Identifiable, Hashable {
        let seriesId: SeriesRecord.ID
        let chapterId: ChapterRecord.ID
        var id: ChapterRecord.ID { chapterId }
    }

    private enum Layout {
        static let fillOpacity = 0.05
        static let skeletonRows = 6
        static let skeletonRowHeight: CGFloat = 64
    }

    private var phase: LoadPhase {
        if let vm {
            if vm.failure != nil { .failed }
            else if vm.snapshot == nil { .pending }
            else if vm.snapshot?.isEmpty == true { .empty }
            else { .content }
        } else {
            .pending
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                switch phase {
                case .content:
                    if let vm {
                        Feed(vm)
                            .transition(.opacity)
                    }
                case .empty:
                    // the status rows stay even with no history - they carry
                    // facts of their own, and a screen that is only sometimes
                    // shaped like itself reads as broken
                    if let snapshot = vm?.snapshot {
                        VStack(spacing: 0) {
                            Now(snapshot)
                                .padding(.horizontal, dimensions.screenMargin)
                                .padding(.top, dimensions.spacing.space16)

                            ContentUnavailableView {
                                Label("No Activity Yet", systemImage: "clock")
                            } description: {
                                Text("Chapters you finish and time you spend reading will appear here.")
                            }
                        }
                        .transition(.opacity)
                    }
                case .failed:
                    if let vm, let failure = vm.failure {
                        ContentUnavailableView {
                            Label(failure.title, systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(failure.message)
                        } actions: {
                            if failure.isRetryable {
                                Button("Try Again") { vm.retry() }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                        .transition(.opacity)
                    }
                default:
                    Skeleton
                        .transition(.opacity)
                }
            }
            .animation(.settle, value: phase)
            .navigationTitle("Activity")
            .navigationDestination(for: SeriesEntry.self) { DetailsScreen(entry: $0) }
            .navigationDestination(item: $reading) { target in
                ReaderScreen(seriesId: target.seriesId, chapterId: target.chapterId)
            }
            .toolbar {
                if let vm, phase == .content {
                    ToolbarItem(placement: .primaryAction) {
                        Picker("Grouping", selection: Binding(get: { vm.grouping }, set: { vm.grouping = $0 })) {
                            ForEach(ActivityViewModel.Grouping.allCases) { grouping in
                                Text(grouping.rawValue).tag(grouping)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .task {
                guard vm == nil else { return }
                let model = ActivityViewModel(
                    database: compositor.database,
                    registry: compositor.registry
                )
                vm = model
                model.observe()
            }
        }
    }
}

// MARK: - Feed

private extension ActivityScreen {
    func Feed(_ vm: ActivityViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space16) {
                if let snapshot = vm.snapshot {
                    Now(snapshot)
                }

                switch vm.grouping {
                case .day:
                    ForEach(vm.days) { group in
                        DaySection(group)
                    }
                case .series:
                    VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                        ForEach(vm.series) { group in
                            SeriesRow(group)
                        }
                    }
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.vertical, dimensions.spacing.space16)
        }
        .animation(.settle, value: vm.grouping)
    }

    // always present, settled on facts while nothing runs. when the downloader
    // and global refresh exist, their observable progress models take these
    // rows over with live state - and nothing else ever renders here
    func Now(_ snapshot: ActivityViewModel.Snapshot) -> some View {
        ActivityNowSection(model: .init(
            refresh: .idle(lastChecked: snapshot.lastChecked),
            downloads: .idle(stored: snapshot.downloadedChapters)
        ))
    }

    func DaySection(_ group: ActivityViewModel.DayGroup) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            Text(ReadingFormat.dayLabel(for: group.day))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            ForEach(group.entries) { entry in
                FeedRow(
                    title: entry.title,
                    summary: summary(chapters: entry.chapters, pages: entry.pages, seconds: entry.seconds),
                    detail: Text(entry.latestDate.formatted(date: .omitted, time: .shortened)),
                    alive: entry.alive,
                    seriesId: entry.seriesId,
                    target: entry.target
                )
            }
        }
    }

    func SeriesRow(_ group: ActivityViewModel.SeriesGroup) -> some View {
        FeedRow(
            title: group.title,
            summary: summary(chapters: group.chapters, pages: group.pages, seconds: group.seconds),
            detail: Text("^[\(group.days) day](inflect: true)"),
            alive: group.alive,
            seriesId: group.seriesId,
            target: group.target
        )
    }

    @ViewBuilder
    func FeedRow(
        title: String,
        summary: String,
        detail: Text,
        alive: Bool,
        seriesId: Int64,
        target: ContinueTarget?
    ) -> some View {
        let row = HStack(spacing: dimensions.spacing.space12) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .foregroundStyle(alive ? .primary : .secondary)

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            detail
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(dimensions.spacing.space12)
        .background(.primary.opacity(Layout.fillOpacity), in: .rect(cornerRadius: dimensions.radius.radius12))

        // a live series resumes straight into the reader; a dead snapshot
        // still names what happened but goes nowhere
        if alive, let target {
            row
                .contentShape(.rect)
                .tappable {
                    reading = ReadingTarget(
                        seriesId: SeriesRecord.ID(rawValue: seriesId),
                        chapterId: target.chapterId
                    )
                }
                .contextMenu {
                    NavigationLink(value: SeriesEntry.library(SeriesRecord.ID(rawValue: seriesId))) {
                        Label("View Series", systemImage: "book")
                    }
                }
        } else if alive {
            NavigationLink(value: SeriesEntry.library(SeriesRecord.ID(rawValue: seriesId))) {
                row
            }
            .buttonStyle(.plain)
        } else {
            row
        }
    }

    func summary(chapters: Int, pages: Int, seconds: Int) -> String {
        var parts: [String] = []
        if chapters > 0 { parts.append("\(chapters) finished") }
        if pages > 0 { parts.append("\(pages) pages") }
        if seconds > 0 { parts.append(ReadingFormat.duration(seconds)) }
        return parts.isEmpty ? "Read" : parts.joined(separator: " · ")
    }

    var Skeleton: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                ForEach(0..<Layout.skeletonRows, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: dimensions.radius.radius12)
                        .fill(.primary.opacity(Layout.fillOpacity))
                        .frame(height: Layout.skeletonRowHeight)
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.vertical, dimensions.spacing.space16)
        }
        .scrollDisabled(true)
        .shimmer()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
