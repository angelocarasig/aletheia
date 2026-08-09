//
//  ActivityNowSection.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import SwiftUI

// the status zone above the activity feed: always present, never a mystery.
// idle rows settle to facts (when the library was last checked, what is
// stored); a running operation takes its row over with the fixed live
// vocabulary - current item name, x of N, a determinate bar, cancel. controls
// exist only while they can operate: an idle row is information, not an
// affordance. live state is in-memory only and never becomes feed rows.
// see docs/features/background-activity.md
struct ActivityNowSection: View {
    let model: Model
    var onCancelRefresh: () -> Void = {}
    var onOpenDownloads: () -> Void = {}
    var onClearFailure: (Model.FailureEntry.ID) -> Void = { _ in }

    @Environment(\.dimensions) private var dimensions

    struct Model: Equatable {
        var refresh: RefreshState = .idle(lastChecked: nil)
        var downloads: DownloadState = .idle(stored: 0)
        var failures: [FailureEntry] = []

        enum RefreshState: Equatable {
            case idle(lastChecked: Date?)
            case running(seriesTitle: String, completed: Int, total: Int)
        }

        enum DownloadState: Equatable {
            case idle(stored: Int)
            case active(chapters: Int, progress: Double)
        }

        struct FailureEntry: Equatable, Identifiable {
            let id: Int
            let seriesTitle: String
            let reason: String
        }
    }

    private enum Layout {
        static let fillOpacity = 0.05
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            RefreshRow

            DownloadsRow

            ForEach(model.failures) { failure in
                FailureRow(failure)
            }
        }
    }
}

// MARK: - Rows

private extension ActivityNowSection {
    @ViewBuilder
    var RefreshRow: some View {
        switch model.refresh {
        case let .idle(lastChecked):
            Card {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                    Text("Library")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if let lastChecked {
                        Text("Checked \(lastChecked.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not checked yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        case let .running(seriesTitle, completed, total):
            VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                HStack(spacing: dimensions.spacing.space12) {
                    VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                        Text("Updating Library")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(seriesTitle)
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
            .background(.primary.opacity(Layout.fillOpacity), in: .rect(cornerRadius: dimensions.radius.radius12))
        }
    }

    @ViewBuilder
    var DownloadsRow: some View {
        switch model.downloads {
        case let .idle(stored):
            Card {
                Image(systemName: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                    Text("Downloads")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if stored > 0 {
                        Text("^[\(stored) chapter](inflect: true) stored")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Nothing downloaded yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        case let .active(chapters, progress):
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
            .background(.primary.opacity(Layout.fillOpacity), in: .rect(cornerRadius: dimensions.radius.radius12))
            .contentShape(.rect)
            .tappable { onOpenDownloads() }
            .accessibilityLabel("^[\(chapters) chapter](inflect: true) downloading. Opens the queue.")
        }
    }

    func FailureRow(_ failure: Model.FailureEntry) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(Palette.warningText)

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text("Couldn't update \(failure.seriesTitle)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(failure.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onClearFailure(failure.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Dismiss")
        }
        .padding(dimensions.spacing.space12)
        .background(.primary.opacity(Layout.fillOpacity), in: .rect(cornerRadius: dimensions.radius.radius12))
    }

    func Card(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: dimensions.spacing.space12, content: content)
            .padding(dimensions.spacing.space12)
            .background(.primary.opacity(Layout.fillOpacity), in: .rect(cornerRadius: dimensions.radius.radius12))
    }
}

// MARK: - Previews

#Preview("Idle") {
    ActivityNowSection(
        model: .init(
            refresh: .idle(lastChecked: .now.addingTimeInterval(-7200)),
            downloads: .idle(stored: 12)
        )
    )
    .padding()
}

#Preview("Idle, Fresh Install") {
    ActivityNowSection(
        model: .init(
            refresh: .idle(lastChecked: nil),
            downloads: .idle(stored: 0)
        )
    )
    .padding()
}

#Preview("Refresh Running") {
    ActivityNowSection(
        model: .init(
            refresh: .running(seriesTitle: "Heavenly Solo Defender", completed: 12, total: 87),
            downloads: .idle(stored: 12)
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
    @Previewable @State var model = ActivityNowSection.Model(
        refresh: .running(seriesTitle: "A Former Hero Returned From Another World", completed: 30, total: 87),
        downloads: .active(chapters: 5, progress: 0.72),
        failures: [
            .init(id: 1, seriesTitle: "Motae Solo", reason: "The source didn't respond."),
            .init(id: 2, seriesTitle: "Solo Martial Arts", reason: "No internet connection available."),
        ]
    )

    ActivityNowSection(
        model: model,
        onClearFailure: { id in
            model.failures.removeAll { $0.id == id }
        }
    )
    .padding()
}

#Preview("Live Flow") {
    @Previewable @State var model = ActivityNowSection.Model(
        refresh: .idle(lastChecked: .now.addingTimeInterval(-86_400)),
        downloads: .idle(stored: 8)
    )

    VStack(spacing: 0) {
        ActivityNowSection(model: model)
            .animation(.smooth, value: model)

        Spacer()
    }
    .padding()
    .task {
        try? await Task.sleep(for: .seconds(1))
        let titles = ["Heavenly Solo Defender", "Motae Solo", "Solo Martial Arts", "This Duck Wants to Fly Solo"]
        for step in 0...40 {
            try? await Task.sleep(for: .milliseconds(300))
            model.refresh = .running(
                seriesTitle: titles[step % titles.count],
                completed: step * 2,
                total: 80
            )
            model.downloads = .active(chapters: max(1, 4 - step / 12), progress: Double(step) / 40)
        }
        // the run settles back to facts rather than vanishing
        model.refresh = .idle(lastChecked: .now)
        model.downloads = .idle(stored: 12)
    }
}
