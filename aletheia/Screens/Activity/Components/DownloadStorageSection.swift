//
//  DownloadStorageSection.swift
//  aletheia
//
//  Created by Angelo Carasig on 22/8/2026.
//

import Kingfisher
import SwiftUI
import Tagged

struct DownloadStorageSection: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    @State private var vm: DownloadStorageViewModel?

    init(vm: DownloadStorageViewModel? = nil) {
        _vm = State(initialValue: vm)
    }

    private enum Layout {
        static let coverWidth: CGFloat = 44
        static let coverHeight: CGFloat = 58
        static let barHeight: CGFloat = 4
        static let fillOpacity = 0.05
        static let skeletonRows = 6
    }

    private var phase: LoadPhase {
        if let vm {
            if vm.failure != nil {
                .failed
            } else if vm.snapshot == nil {
                .pending
            } else if vm.snapshot?.isEmpty == true {
                .empty
            } else {
                .content
            }
        } else {
            .pending
        }
    }

    var body: some View {
        Group {
            switch phase {
            case .content:
                if let snapshot = vm?.snapshot {
                    Content(snapshot)
                        .transition(.opacity)
                }
            case .empty:
                ContentUnavailableView(
                    "Nothing Downloaded Yet",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Series you download chapters for will show up here by size.")
                )
                .transition(.opacity)
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
                }
            case .pending:
                Skeleton
                    .transition(.opacity)
            }
        }
        .animation(.settle, value: phase)
        .task {
            guard vm == nil else { return }
            let model = DownloadStorageViewModel(
                database: compositor.database, assets: compositor.assets)
            vm = model
            model.observe()
        }
    }
}

// MARK: - Content

extension DownloadStorageSection {
    fileprivate func Content(_ series: [SeriesStorage]) -> some View {
        let total = series.reduce(0) { $0 + $1.bytes }
        let maxBytes = series.map(\.bytes).max() ?? 1

        return VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
                    .font(.title2)
                    .fontWeight(.bold)

                Text("^[\(series.count) series](inflect: true) downloaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // largest-first, any N - grows the list rather than shrinking
            // tiles or bars the way the treemap and chart both did
            VStack(spacing: dimensions.spacing.space8) {
                ForEach(series) { item in
                    Row(item, maxBytes: maxBytes)
                }
            }
        }
    }

    fileprivate func Row(_ item: SeriesStorage, maxBytes: Int64) -> some View {
        NavigationLink(value: SeriesEntry.library(item.id)) {
            HStack(spacing: dimensions.spacing.space12) {
                Cover(item.cover)

                VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                    HStack(alignment: .firstTextBaseline, spacing: dimensions.spacing.space8) {
                        Text(item.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .foregroundStyle(.primary)

                        Spacer(minLength: 0)

                        Text(ByteCountFormatter.string(fromByteCount: item.bytes, countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .layoutPriority(1)
                    }

                    Text("^[\(item.chapterCount) chapter](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // relative to the biggest series here, not to total
                    // storage - a share-of-total bar would leave every row
                    // looking nearly empty once there are more than a few
                    GeometryReader { proxy in
                        Capsule()
                            .fill(.primary.opacity(Layout.fillOpacity))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(Palette.brand)
                                    .frame(
                                        width: proxy.size.width
                                            * CGFloat(Double(item.bytes) / Double(maxBytes)))
                            }
                    }
                    .frame(height: Layout.barHeight)
                }
            }
            .padding(dimensions.spacing.space12)
            .background(
                .primary.opacity(Layout.fillOpacity),
                in: .rect(cornerRadius: dimensions.radius.radius12))
        }
        .buttonStyle(.plain)
    }

    fileprivate func Cover(_ url: URL?) -> some View {
        Color.clear
            .frame(width: Layout.coverWidth, height: Layout.coverHeight)
            .overlay {
                if let url {
                    KFImage(url)
                        .resizable()
                        .placeholder {
                            Rectangle().fill(.primary.opacity(Layout.fillOpacity)).shimmer()
                        }
                        .fade(duration: 0.25)
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(.primary.opacity(Layout.fillOpacity))
                        .overlay {
                            Image(systemName: "book.closed")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                }
            }
            .clipped()
            .clipShape(.rect(cornerRadius: dimensions.radius.radius8))
    }

    fileprivate var Skeleton: some View {
        VStack(spacing: dimensions.spacing.space8) {
            ForEach(0..<Layout.skeletonRows, id: \.self) { _ in
                RoundedRectangle(cornerRadius: dimensions.radius.radius12)
                    .fill(.primary.opacity(Layout.fillOpacity))
                    .frame(height: Layout.coverHeight + dimensions.spacing.space16 * 2)
            }
        }
        .shimmer()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("Storage") {
    ScrollView {
        DownloadStorageSection(
            vm: .preview(
                snapshot: [
                    SeriesStorage(
                        id: SeriesRecord.ID(rawValue: 1), title: "Solo Leveling", cover: nil,
                        bytes: 620_000_000, chapterCount: 42),
                    SeriesStorage(
                        id: SeriesRecord.ID(rawValue: 2), title: "Omniscient Reader", cover: nil,
                        bytes: 340_000_000, chapterCount: 30),
                    SeriesStorage(
                        id: SeriesRecord.ID(rawValue: 3), title: "Berserk", cover: nil,
                        bytes: 210_000_000, chapterCount: 20),
                    SeriesStorage(
                        id: SeriesRecord.ID(rawValue: 4), title: "Vagabond", cover: nil,
                        bytes: 90_000_000, chapterCount: 8),
                    SeriesStorage(
                        id: SeriesRecord.ID(rawValue: 5), title: "Nano Machine", cover: nil,
                        bytes: 40_000_000, chapterCount: 4),
                ]
            )
        )
        .padding(16)
    }
}

#Preview("Empty") {
    ScrollView {
        DownloadStorageSection(vm: .preview(snapshot: []))
            .padding(16)
    }
}
