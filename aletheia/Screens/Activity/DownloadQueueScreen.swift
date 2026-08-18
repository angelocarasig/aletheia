//
//  DownloadQueueScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import SwiftUI

// its own pushed screen off the activity tab's downloads row, never a tab and
// never a library entry point: library owns downloaded content, not the queue.
// the live vocabulary the whole app uses for a running operation - what is being
// worked on, x of N, a determinate bar, cancel.
// see docs/features/background-activity.md
struct DownloadQueueScreen: View {
    let downloads: Compositor.Downloads

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let fillOpacity = 0.05
        // shorter than the gap between two pages landing, so a fast chapter
        // never has one digit still sliding when the next arrives
        static let tick: TimeInterval = 0.2
    }

    var body: some View {
        Group {
            if downloads.order.isEmpty {
                ContentUnavailableView(
                    "Queue Is Empty",
                    systemImage: "arrow.down.circle",
                    description: Text(
                        "Chapters you download will appear here while they're being saved.")
                )
            } else {
                ScrollView {
                    VStack(spacing: dimensions.spacing.space8) {
                        Summary

                        ForEach(downloads.order) { download in
                            Row(download)
                        }
                    }
                    .padding(.horizontal, dimensions.spacing.space16)
                    .padding(.bottom, dimensions.spacing.space24)
                }
            }
        }
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !downloads.order.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel All", role: .destructive) {
                        downloads.cancelAll()
                    }
                }
            }
        }
        .animation(.settle, value: downloads.order.count)
    }
}

// MARK: - Rows

extension DownloadQueueScreen {
    // the coarse counters rather than a fold over every item: reducing `order`
    // to sum progress reads every download's pages and puts this view back on
    // the ten-times-a-second path the per-item split exists to avoid
    fileprivate var Summary: some View {
        let completed = downloads.completed
        let total = downloads.total

        return VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
            // the same treatment as the per-row page count, on a value that
            // moves once a chapter rather than once a page - the point is that
            // a number in this screen never cuts, whatever its cadence
            Text("\(completed) of \(total)")
                .font(.subheadline)
                .fontWeight(.medium)
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(completed)))
                .animation(.snappy(duration: Layout.tick), value: completed)

            ProgressView(value: total > 0 ? Double(completed) / Double(total) : 0)
                .tint(.brand)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(dimensions.spacing.space12)
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius12))
    }

    // every read below is on this download's own instance, so a page landing
    // here re-evaluates this row and nothing else
    fileprivate func Row(_ download: Download) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Text(download.series)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(download.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Status(download)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                downloads.cancel(chapter: download.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove from queue")
        }
        .padding(dimensions.spacing.space12)
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius12))
    }

    @ViewBuilder
    fileprivate func Status(_ download: Download) -> some View {
        switch download.state {
        case .queued:
            Text("Waiting")
                .font(.caption2)
                .foregroundStyle(.tertiary)

        // the first tick is a state rather than a silent zero: a chapter whose
        // page list is still being fetched has nothing to count yet, and saying
        // "0 of 0 pages" reads as broken
        case .preparing:
            Text("Preparing")
                .font(.caption2)
                .foregroundStyle(.tertiary)

        case .downloading:
            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                ProgressView(value: download.fraction)
                    .tint(.brand)

                // the count slides rather than cuts. numericText is the right
                // tool here and CountingText is not: this value arrives one
                // page at a time from the downloader, so each change is its own
                // small transition - where the all-time tiles sweep a whole
                // range once and need a frame-by-frame tween to do it.
                //
                // monospaced so the row does not twitch as digits change width,
                // and the animation is declared on the view because the write
                // lands from the downloader with no animation of its own
                Text("\(download.pagesDone) of \(download.pagesTotal) pages")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(download.pagesDone)))
                    .animation(.snappy(duration: Layout.tick), value: download.pagesDone)
            }
            .padding(.top, dimensions.spacing.space2)

        case .failed(let reason):
            Text(reason)
                .font(.caption2)
                .foregroundStyle(.danger)
                .lineLimit(2)
        }
    }
}
