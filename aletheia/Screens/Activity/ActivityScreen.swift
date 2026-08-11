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
    @State private var showingFailures = false
    @State private var showingDownloads = false
    @State private var showingTracking = false

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

    // no empty state: the status rows are facts that always exist - the library
    // has been checked or it has not - so there is nothing this screen can be
    // empty OF. it had one while it carried a reading feed, which it no longer
    // does
    private var phase: LoadPhase {
        if let vm {
            if vm.failure != nil { .failed }
            else if vm.snapshot == nil { .pending }
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
                    if let snapshot = vm?.snapshot {
                        Status(snapshot)
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
            .toolbarTitleDisplayMode(.large)
            .navigationDestination(for: SeriesEntry.self) { DetailsScreen(entry: $0) }
            .navigationDestination(isPresented: $showingFailures) {
                FailuresScreen()
            }
            .navigationDestination(isPresented: $showingDownloads) {
                DownloadQueueScreen(downloads: compositor.downloads)
            }
            // the account screen rather than a per-series list: a dead account is
            // one fact about one service, and signing in is the only thing that
            // resolves it
            .navigationDestination(isPresented: $showingTracking) {
                TrackingScreen()
            }
            .task {
                guard vm == nil else { return }
                let model = ActivityViewModel(database: compositor.database)
                vm = model
                model.observe()
            }
        }
    }
}

// MARK: - Status

private extension ActivityScreen {
    // one scroll for both halves. the operational rows lead because they are the
    // only thing here that can need acting on - a failing source found while
    // scrolling past it is the tab working, and a status block pinned above a
    // scrolling chart would make it chrome the eye stops reading
    func Status(_ snapshot: ActivityViewModel.Snapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                // titled now that it shares the screen with reading history:
                // unlabelled, the status rows read as a preamble to the charts
                // rather than as their own subject. "Now" rather than "Library",
                // which is the first card's own name - a header repeating the
                // row under it says one of them is redundant, and it is not the
                // row
                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("Now")

                    Now(snapshot)
                }

                ReadingActivitySection()
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.vertical, dimensions.spacing.space16)
        }
        .scrollIndicators(.hidden)
        // content was passing under the translucent nav and tab bars and staying
        // legible-ish through them, which is worse than either hiding or showing
        // it: a section header parked under the bar is unreadable at partial
        // opacity with no cue that it is scrolled-off rather than missing
        .scrollEdgeEffectStyle(.hard, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    // always present, settled on facts while nothing runs, and taken over by the
    // live run when there is one. the numbers come from the runner's observable
    // model; the facts come from columns, which is what makes a run that
    // happened while the app was closed still leave a trace here
    func Now(_ snapshot: ActivityViewModel.Snapshot) -> some View {
        let refresh = compositor.refresh
        let downloads = compositor.downloads
        let queued = downloads.order.count

        return ActivityNowSection(
            model: .init(
                refresh: refresh.isRunning
                    ? .running(
                        scope: refresh.scope,
                        seriesTitle: refresh.current,
                        completed: refresh.completed,
                        total: refresh.total
                    )
                    : .idle(lastChecked: snapshot.lastChecked),
                // chapters rather than pages, and from the stored counters rather
                // than a fold over the queue: summing every item's progress here
                // would subscribe this row to all of them
                downloads: queued > 0
                    ? .active(
                        chapters: queued,
                        progress: downloads.total > 0
                            ? Double(downloads.completed) / Double(downloads.total)
                            : 0
                    )
                    : .idle(stored: snapshot.downloadedChapters),
                failing: snapshot.failingSources,
                // read live from the credentials rather than from the snapshot:
                // this is keychain state, not a column, and it changes on a
                // sign-in that no database write accompanies
                signedOut: Tracker.allCases.filter(compositor.trackers.needingSignIn.contains)
            ),
            onCancelRefresh: { refresh.cancel() },
            onOpenDownloads: { showingDownloads = true },
            // the count is the awareness; the list is the attribution and the
            // retry. a series can be healthy on one source and dead on another,
            // so naming the series alone would not be enough to act on
            onOpenFailures: { showingFailures = true },
            onOpenTracking: { showingTracking = true }
        )
        .animation(.settle, value: refresh.isRunning)
        .animation(.settle, value: queued > 0)
        .animation(.settle, value: compositor.trackers.needingSignIn)
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
