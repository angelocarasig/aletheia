//
//  ActivityNowSection.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import SwiftUI

struct ActivityNowSection: View {
    let model: Model
    var onCancelRefresh: () -> Void = {}
    var onOpenUpdates: () -> Void = {}
    var onOpenDownloads: () -> Void = {}
    var onOpenFailures: () -> Void = {}
    var onOpenTracking: () -> Void = {}

    @Environment(\.dimensions) private var dimensions

    struct Model: Equatable {
        var refresh: RefreshState = .idle(lastChecked: nil)
        var downloads: DownloadState = .idle(stored: 0, bytes: 0)
        var failing: Int = 0
        var signedOut: [Tracker] = []

        enum RefreshState: Equatable {
            case idle(lastChecked: Date?)
            case running(scope: String?, seriesTitle: String?, completed: Int, total: Int)
        }

        enum DownloadState: Equatable {
            case idle(stored: Int, bytes: Int64)
            case active(chapters: Int, progress: Double)
        }
    }

    private enum Layout {
        static let fillOpacity = 0.05
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            RefreshRow

            DownloadsRow

            if model.failing > 0 {
                FailingRow
            }

            ForEach(model.signedOut) { tracker in
                SignedOutRow(tracker)
            }
        }
    }
}

// MARK: - Rows

extension ActivityNowSection {
    @ViewBuilder
    fileprivate var RefreshRow: some View {
        switch model.refresh {
        case .idle(let lastChecked):
            Card {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                    Text("Updates")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if let lastChecked {
                        LiveRelative(date: lastChecked) { relative in
                            Text("Checked \(relative)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    } else {
                        Text("Not checked yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
            .tappable { onOpenUpdates() }
            .accessibilityLabel("Updates")

        case .running(let scope, let seriesTitle, let completed, let total):
            VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                HStack(spacing: dimensions.spacing.space12) {
                    VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                        Text(scope.map { "Updating \($0)" } ?? "Updating")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(seriesTitle ?? "Starting")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(completed) of \(total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Button {
                        onCancelRefresh()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Cancel library update")
                }

                ProgressView(value: Double(completed), total: Double(max(1, total)))
                    .tint(.brand)
            }
            .padding(dimensions.spacing.space12)
            .background(
                .primary.opacity(Layout.fillOpacity),
                in: .rect(cornerRadius: dimensions.radius.radius12))
        }
    }

    @ViewBuilder
    fileprivate var DownloadsRow: some View {
        switch model.downloads {
        case .idle(let stored, let bytes):
            Card {
                Image(systemName: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                    Text("Downloads")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if stored > 0 {
                        // both interpolations stay inside one Text literal -
                        // inflection markup ("^[n chapter](inflect:)") only
                        // parses through Text's own LocalizedStringKey init,
                        // which a precomputed String bypasses, but a second
                        // \() interpolation in the same literal doesn't
                        (bytes > 0
                            ? Text(
                                "^[\(stored) chapter](inflect: true) · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
                            )
                            : Text("^[\(stored) chapter](inflect: true) in storage"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Nothing downloaded yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(.rect)
            .tappable { onOpenDownloads() }
            .accessibilityLabel("Downloads")

        case .active(let chapters, let progress):
            HStack(spacing: dimensions.spacing.space12) {
                VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                    Text("Downloading · ^[\(chapters) chapter](inflect: true)")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    ProgressView(value: progress)
                        .tint(.brand)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(dimensions.spacing.space12)
            .background(
                .primary.opacity(Layout.fillOpacity),
                in: .rect(cornerRadius: dimensions.radius.radius12)
            )
            .contentShape(.rect)
            .tappable { onOpenDownloads() }
            .accessibilityLabel(
                "^[\(chapters) chapter](inflect: true) downloading. Opens the queue.")
        }
    }

    fileprivate var FailingRow: some View {
        HStack(spacing: dimensions.spacing.space12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Palette.warningText)

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text("^[\(model.failing) source](inflect: true) failing")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text("Their series can't pick up new chapters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(dimensions.spacing.space12)
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius12)
        )
        .contentShape(.rect)
        .tappable { onOpenFailures() }
    }

    fileprivate func SignedOutRow(_ tracker: Tracker) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            Image(tracker.icon)
                .resizable()
                .scaledToFit()
                .frame(width: dimensions.size.icon24, height: dimensions.size.icon24)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius8))

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text("Reconnect \(tracker.name)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                // AniList expires yearly by design, MyAnimeList only on failure - copy stays generic since the fix is identical either way
                Text("Your progress isn't syncing until you sign in again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(dimensions.spacing.space12)
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius12)
        )
        .contentShape(.rect)
        .tappable { onOpenTracking() }
    }

    fileprivate func Card(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: dimensions.spacing.space12, content: content)
            .padding(dimensions.spacing.space12)
            .background(
                .primary.opacity(Layout.fillOpacity),
                in: .rect(cornerRadius: dimensions.radius.radius12))
    }
}

// MARK: - Previews

#Preview("Idle") {
    ActivityNowSection(
        model: .init(
            refresh: .idle(lastChecked: .now.addingTimeInterval(-7200)),
            downloads: .idle(stored: 12, bytes: 340_000_000)
        )
    )
    .padding()
}

#Preview("Account signed out") {
    ActivityNowSection(
        model: .init(
            refresh: .idle(lastChecked: .now.addingTimeInterval(-3600)),
            downloads: .idle(stored: 12, bytes: 340_000_000),
            signedOut: [.anilist]
        )
    )
    .padding()
}

#Preview("Both accounts signed out") {
    ActivityNowSection(
        model: .init(
            refresh: .idle(lastChecked: .now.addingTimeInterval(-3600)),
            downloads: .idle(stored: 12, bytes: 340_000_000),
            failing: 2,
            signedOut: [.anilist, .myAnimeList]
        )
    )
    .padding()
}

#Preview("Idle, Fresh Install") {
    ActivityNowSection(
        model: .init(
            refresh: .idle(lastChecked: nil),
            downloads: .idle(stored: 0, bytes: 0)
        )
    )
    .padding()
}

#Preview("Refresh Running") {
    ActivityNowSection(
        model: .init(
            refresh: .running(
                scope: nil, seriesTitle: "Heavenly Solo Defender", completed: 12, total: 87),
            downloads: .idle(stored: 12, bytes: 340_000_000)
        )
    )
    .padding()
}

#Preview("Downloads Active") {
    ActivityNowSection(
        model: .init(
            refresh: .idle(lastChecked: .now.addingTimeInterval(-600)),
            downloads: .active(chapters: 3, progress: 0.4)
        )
    )
    .padding()
}

#Preview("Everything + Failures") {
    ActivityNowSection(
        model: .init(
            refresh: .running(
                scope: "Reading",
                seriesTitle: "A Former Hero Returned From Another World",
                completed: 30,
                total: 87
            ),
            downloads: .active(chapters: 5, progress: 0.72),
            failing: 2
        )
    )
    .padding()
}

#Preview("Live Flow") {
    @Previewable @State var model = ActivityNowSection.Model(
        refresh: .idle(lastChecked: .now.addingTimeInterval(-86_400)),
        downloads: .idle(stored: 8, bytes: 210_000_000)
    )

    VStack(spacing: 0) {
        ActivityNowSection(model: model)
            .animation(.smooth, value: model)

        Spacer()
    }
    .padding()
    .task {
        try? await Task.sleep(for: .seconds(1))
        let titles = [
            "Heavenly Solo Defender", "Motae Solo", "Solo Martial Arts",
            "This Duck Wants to Fly Solo",
        ]
        for step in 0...40 {
            try? await Task.sleep(for: .milliseconds(300))
            model.refresh = .running(
                scope: nil,
                seriesTitle: titles[step % titles.count],
                completed: step * 2,
                total: 80
            )
            model.downloads = .active(chapters: max(1, 4 - step / 12), progress: Double(step) / 40)
        }
        model.refresh = .idle(lastChecked: .now)
        model.downloads = .idle(stored: 12, bytes: 340_000_000)
    }
}
