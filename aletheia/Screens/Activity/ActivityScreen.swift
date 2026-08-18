//
//  ActivityScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI
import Tagged

struct ActivityScreen: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    @State private var vm: ActivityViewModel?
    @State private var showingFailures = false
    @State private var showingDownloads = false
    @State private var showingUpdates = false
    @State private var showingTracking = false

    private enum Layout {
        static let fillOpacity = 0.05
        static let skeletonRows = 6
        static let skeletonRowHeight: CGFloat = 64
    }

    private var phase: LoadPhase {
        if let vm {
            if vm.failure != nil {
                .failed
            } else if vm.snapshot == nil {
                .pending
            } else {
                .content
            }
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
            .navigationDestination(isPresented: $showingUpdates) {
                UpdatesScreen()
            }
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

extension ActivityScreen {
    fileprivate func Status(_ snapshot: ActivityViewModel.Snapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
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
        // hard top edge keeps a scrolled-under header from sitting unreadable at partial opacity
        .scrollEdgeEffectStyle(.hard, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }

    fileprivate func Now(_ snapshot: ActivityViewModel.Snapshot) -> some View {
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
                // stored counters, not a fold over the queue - avoids subscribing this row to every item
                downloads: queued > 0
                    ? .active(
                        chapters: queued,
                        progress: downloads.total > 0
                            ? Double(downloads.completed) / Double(downloads.total)
                            : 0
                    )
                    : .idle(stored: snapshot.downloadedChapters),
                failing: snapshot.failingSources,
                // keychain state, not a column - a sign-in changes this with no accompanying db write
                signedOut: Tracker.allCases.filter(compositor.trackers.needingSignIn.contains)
            ),
            onCancelRefresh: { refresh.cancel() },
            onOpenUpdates: { showingUpdates = true },
            onOpenDownloads: { showingDownloads = true },
            onOpenFailures: { showingFailures = true },
            onOpenTracking: { showingTracking = true }
        )
        .animation(.settle, value: refresh.isRunning)
        .animation(.settle, value: queued > 0)
        .animation(.settle, value: compositor.trackers.needingSignIn)
    }

    fileprivate var Skeleton: some View {
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
