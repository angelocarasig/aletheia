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
    var onOpenFailures: () -> Void = {}
    var onOpenTracking: () -> Void = {}

    @Environment(\.dimensions) private var dimensions

    struct Model: Equatable {
        var refresh: RefreshState = .idle(lastChecked: nil)
        var downloads: DownloadState = .idle(stored: 0)
        // sources failing right now, read from origin.fetchError. not a list of
        // entries to dismiss: the column is true until that source answers
        // again, so an x would either hide a live fact or need a third column
        // saying it had been acknowledged
        var failing: Int = 0
        // services that have stopped syncing until the reader signs in again.
        // deliberately NOT folded into `failing` above, whose copy is about
        // sources and whose list is per origin - merging the two populations
        // makes that sentence false for half of what it counts. one row per dead
        // account rather than one per affected series: forty rows would all say
        // the same thing and none of them would be fixable where they stood
        var signedOut: [Tracker] = []

        enum RefreshState: Equatable {
            case idle(lastChecked: Date?)
            case running(scope: String?, seriesTitle: String?, completed: Int, total: Int)
        }

        enum DownloadState: Equatable {
            case idle(stored: Int)
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

        case let .running(scope, seriesTitle, completed, total):
            VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                HStack(spacing: dimensions.spacing.space12) {
                    VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                        // the scope is named, so a collection refresh never reads
                        // as though the whole library is being walked
                        Text(scope.map { "Updating \($0)" } ?? "Updating Library")
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

    // one row for however many are broken, opening the list. it leaves on its
    // own when the sources answer again - there is nothing here to dismiss
    var FailingRow: some View {
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
        .background(.primary.opacity(Layout.fillOpacity), in: .rect(cornerRadius: dimensions.radius.radius12))
        .contentShape(.rect)
        .tappable { onOpenFailures() }
    }

    // the one tracker failure a reader has to act on, and the only one that
    // cannot fix itself: a push that failed will retry, an account that has run
    // out will not. named rather than counted - "1 account" is a number where the
    // service's own name is the whole instruction
    func SignedOutRow(_ tracker: Tracker) -> some View {
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

                // anilist expires yearly by design and myanimelist only when
                // something went wrong. the reader does the same thing about
                // either, so neither says which - and neither says "expired",
                // which reads as a fault where one of the two is routine
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
        .background(.primary.opacity(Layout.fillOpacity), in: .rect(cornerRadius: dimensions.radius.radius12))
        .contentShape(.rect)
        .tappable { onOpenTracking() }
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

// the row that cannot fix itself, so it is the one thing here worth interrupting
// for. shown beside a healthy library on purpose: it has to read as one account's
// problem rather than as the app being broken
#Preview("Account signed out") {
    ActivityNowSection(
        model: .init(
            refresh: .idle(lastChecked: .now.addingTimeInterval(-3600)),
            downloads: .idle(stored: 12),
            signedOut: [.anilist]
        )
    )
    .padding()
}

// both at once - two rows rather than one summarising them, because the fix is
// per account and a combined row could not name which
#Preview("Both accounts signed out") {
    ActivityNowSection(
        model: .init(
            refresh: .idle(lastChecked: .now.addingTimeInterval(-3600)),
            downloads: .idle(stored: 12),
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
            downloads: .idle(stored: 0)
        )
    )
    .padding()
}

#Preview("Refresh Running") {
    ActivityNowSection(
        model: .init(
            refresh: .running(scope: nil, seriesTitle: "Heavenly Solo Defender", completed: 12, total: 87),
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
                scope: nil,
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
