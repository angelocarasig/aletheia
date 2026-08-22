//
//  DownloadStorageSection.swift
//  aletheia
//
//  Created by Angelo Carasig on 22/8/2026.
//

import Charts
import Kingfisher
import SwiftUI
import Tagged

struct DownloadStorageSection: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    @State private var vm: DownloadStorageViewModel?
    @State private var selectedContributor: String?
    @State private var deletingSeries: SeriesStorage?

    init(vm: DownloadStorageViewModel? = nil) {
        _vm = State(initialValue: vm)
    }

    private enum Layout {
        static let coverWidth: CGFloat = 44
        static let coverHeight: CGFloat = 58
        static let fillOpacity = 0.05
        static let skeletonRows = 6

        static let maxContributors = 6
        // below this share of total, a wedge reads as a thin sliver rather
        // than a distinct value - folds into "Other" even if it would
        // otherwise fit within maxContributors
        static let donutMinimumShare = 0.03
        static let donutSize: CGFloat = 130
        static let legendDot: CGFloat = 8
        static let legendHeight: CGFloat = 130

        // two SectorMark layers: a dim track that hides entirely under
        // whichever wedge is selected, and a full-color value ring that
        // grows both inward and outward on selection rather than dimming
        static let donutTrackInner = 0.55
        static let donutTrackOuter = 0.95
        static let donutTrackInset: CGFloat = 4
        static let donutTrackCornerRadius: CGFloat = 6
        static let donutTrackOpacity = 0.2

        static let donutValueInnerUnselected = 0.60
        static let donutValueOuterUnselected = 0.85
        static let donutValueInnerSelected = 0.55
        static let donutValueOuterSelected = 0.98
        static let donutValueInset: CGFloat = 6
        static let donutValueCornerRadius: CGFloat = 8
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
        .alert(
            deleteSeriesTitle,
            isPresented: Binding(
                get: { deletingSeries != nil }, set: { if !$0 { deletingSeries = nil } })
        ) {
            Button("Delete Downloads", role: .destructive) {
                guard let id = deletingSeries?.id else { return }
                deletingSeries = nil
                compositor.downloads.delete(for: id)
            }
            Button("Cancel", role: .cancel) { deletingSeries = nil }
        } message: {
            Text("This can't be undone.")
        }
    }

    private var deleteSeriesTitle: String {
        let count = deletingSeries?.chapterCount ?? 0
        return "Delete \(count) downloaded \(count == 1 ? "chapter" : "chapters")?"
    }
}

// MARK: - Content

extension DownloadStorageSection {
    fileprivate func Content(_ series: [SeriesStorage]) -> some View {
        let total = series.reduce(0) { $0 + $1.bytes }
        let contributors = Self.contributors(from: series, total: total)

        return VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            HStack(spacing: dimensions.spacing.space12) {
                Tile(
                    label: "Storage",
                    value: ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
                Tile(label: "Series", value: "\(series.count)")
                Tile(label: "Chapters", value: "\(series.reduce(0) { $0 + $1.chapterCount })")
            }

            if !contributors.isEmpty {
                SmallContributors(contributors)
                    .padding(.top, dimensions.spacing.space24)
            }

            VStack(spacing: dimensions.spacing.space8) {
                ForEach(series) { item in
                    Row(item, total: total)
                }
            }
        }
    }

    // matches the Activity screen's all-time stats tile styling
    fileprivate func Tile(label: String, value: String) -> some View {
        VStack(spacing: dimensions.spacing.space4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, dimensions.spacing.space12)
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius12))
    }

    fileprivate static func contributors(from series: [SeriesStorage], total: Int64)
        -> [Contributor]
    {
        guard total > 0, !series.isEmpty else { return [] }

        var contributors: [Contributor] = []
        var rest: [SeriesStorage] = []

        for item in series {
            let share = Double(item.bytes) / Double(total)
            if contributors.count < Layout.maxContributors, share >= Layout.donutMinimumShare {
                contributors.append(
                    Contributor(
                        id: "\(item.id.rawValue)", title: item.title, bytes: item.bytes,
                        color: color(for: item.title), members: [item]))
            } else {
                rest.append(item)
            }
        }

        let restBytes = rest.reduce(0) { $0 + $1.bytes }
        if restBytes > 0 {
            contributors.append(
                Contributor(
                    id: "other", title: "Other", bytes: restBytes, color: Palette.muted,
                    members: rest))
        }

        return contributors
    }

    // stable per-series hue across app launches, not just within one process
    // - String.hashValue's seed is randomized per launch (hash-flood
    // protection), so hashing the title directly gives a different color
    // every time the app restarts. FNV-1a over the title's own bytes is
    // deterministic regardless of process
    fileprivate static func color(for title: String) -> Color {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in title.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        let hue = Double(hash % 360) / 360
        return Color(hue: hue, saturation: 0.55, brightness: 0.75)
    }

    fileprivate func SmallContributors(_ contributors: [Contributor]) -> some View {
        let selected = contributors.first { $0.id == selectedContributor }

        return VStack(alignment: .leading, spacing: dimensions.spacing.space16) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text("Storage Breakdown")
                    .font(.title3)
                    .fontWeight(.bold)

                Text(selected?.title ?? "Share of downloaded storage by series")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }

            HStack(alignment: .center, spacing: dimensions.spacing.space16) {
                Donut(contributors)
                    .frame(width: Layout.donutSize, height: Layout.donutSize)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                        if let selected {
                            ForEach(selected.members) { member in
                                LegendRow(
                                    title: member.title, bytes: member.bytes, color: selected.color)
                            }
                        } else {
                            ForEach(contributors) { item in
                                LegendRow(title: item.title, bytes: item.bytes, color: item.color)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: Layout.legendHeight, alignment: .top)
                .frame(maxWidth: .infinity, alignment: .leading)
                // a row that doesn't fully fit gets hard-cut by the fixed
                // height otherwise - fading it out instead reads as "more
                // below, scroll for it" rather than looking broken
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: 0.85),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom)
                )
            }
        }
        .animation(.settle, value: selectedContributor)
    }

    // selection comes from the manual angle math in handleTap below, not
    // chartAngleSelection - Charts' own tap-to-select is unreliable for a
    // donut with wedges this uneven in size
    fileprivate func Donut(_ contributors: [Contributor]) -> some View {
        ZStack {
            Chart(contributors) { item in
                SectorMark(
                    angle: .value("Size", item.bytes),
                    innerRadius: .ratio(Layout.donutTrackInner),
                    outerRadius: .ratio(Layout.donutTrackOuter),
                    angularInset: Layout.donutTrackInset
                )
                .foregroundStyle(
                    item.color.opacity(selectedContributor == item.id ? 0 : Layout.donutTrackOpacity)
                )
                .cornerRadius(Layout.donutTrackCornerRadius)
            }
            .chartLegend(.hidden)

            Chart(contributors) { item in
                let isSelected = selectedContributor == item.id
                SectorMark(
                    angle: .value("Size", item.bytes),
                    innerRadius: .ratio(
                        isSelected ? Layout.donutValueInnerSelected : Layout.donutValueInnerUnselected),
                    outerRadius: .ratio(
                        isSelected ? Layout.donutValueOuterSelected : Layout.donutValueOuterUnselected),
                    angularInset: Layout.donutValueInset
                )
                .foregroundStyle(item.color)
                .cornerRadius(Layout.donutValueCornerRadius)
            }
            .chartLegend(.hidden)
        }
        .contentShape(Rectangle())
        .animation(.spring(duration: 0.3), value: selectedContributor)
        .onTapGesture { location in
            handleTap(at: location, in: CGSize(width: Layout.donutSize, height: Layout.donutSize),
                contributors: contributors)
        }
    }

    // top of the circle is 0°, going clockwise - matches how each
    // contributor's own angular slice is walked below
    private func handleTap(at location: CGPoint, in size: CGSize, contributors: [Contributor]) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let dx = location.x - center.x
        let dy = location.y - center.y

        var angle = atan2(dy, dx) + .pi / 2
        if angle < 0 { angle += 2 * .pi }
        let degrees = angle * 180 / .pi

        let total = contributors.reduce(0) { $0 + $1.bytes }
        guard total > 0 else { return }

        var current: Double = 0
        for item in contributors {
            let span = Double(item.bytes) / Double(total) * 360
            if degrees >= current && degrees < current + span {
                selectedContributor = selectedContributor == item.id ? nil : item.id
                return
            }
            current += span
        }
    }

    fileprivate func LegendRow(title: String, bytes: Int64, color: Color) -> some View {
        HStack(spacing: dimensions.spacing.space8) {
            Circle()
                .fill(color)
                .frame(width: Layout.legendDot, height: Layout.legendDot)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    fileprivate func Row(_ item: SeriesStorage, total: Int64) -> some View {
        let percent = total > 0 ? Int((Double(item.bytes) / Double(total) * 100).rounded()) : 0

        // the delete button is a sibling of the NavigationLink, not nested
        // inside its label - a tappable inside a NavigationLink's own label
        // fights it for the tap rather than overriding it
        return HStack(spacing: dimensions.spacing.space8) {
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

                            Text(
                                ByteCountFormatter.string(
                                    fromByteCount: item.bytes, countStyle: .file)
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .layoutPriority(1)
                        }

                        HStack(spacing: dimensions.spacing.space4) {
                            Text("^[\(item.chapterCount) chapter](inflect: true)")

                            Text(verbatim: "·")
                                .foregroundStyle(.tertiary)

                            Text("\(percent)% of total")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            Image(systemName: "trash")
                .font(.subheadline)
                .foregroundStyle(Palette.dangerText)
                .padding(dimensions.spacing.space8)
                .contentShape(.rect)
                .tappable { deletingSeries = item }
                .accessibilityLabel("Delete downloaded chapters")
        }
        .padding(dimensions.spacing.space12)
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius12))
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

// MARK: - Contributor

extension DownloadStorageSection {
    fileprivate struct Contributor: Identifiable {
        let id: String
        let title: String
        let bytes: Int64
        let color: Color
        // the series folded into this wedge - one entry for a normal
        // contributor, several for "Other", which is what a tap reveals
        let members: [SeriesStorage]
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

#Preview("Long Tail") {
    ScrollView {
        DownloadStorageSection(
            vm: .preview(
                snapshot: [
                    SeriesStorage(
                        id: SeriesRecord.ID(rawValue: 1), title: "Solo Leveling", cover: nil,
                        bytes: 900_000_000, chapterCount: 90),
                    SeriesStorage(
                        id: SeriesRecord.ID(rawValue: 2), title: "Omniscient Reader", cover: nil,
                        bytes: 500_000_000, chapterCount: 60),
                    SeriesStorage(
                        id: SeriesRecord.ID(rawValue: 3), title: "Berserk", cover: nil,
                        bytes: 300_000_000, chapterCount: 40),
                    SeriesStorage(
                        id: SeriesRecord.ID(rawValue: 4), title: "Vagabond", cover: nil,
                        bytes: 40_000_000, chapterCount: 8),
                    SeriesStorage(
                        id: SeriesRecord.ID(rawValue: 5), title: "Nano Machine", cover: nil,
                        bytes: 35_000_000, chapterCount: 7),
                    SeriesStorage(
                        id: SeriesRecord.ID(rawValue: 6), title: "The Beginning After the End",
                        cover: nil, bytes: 32_000_000, chapterCount: 6),
                    SeriesStorage(
                        id: SeriesRecord.ID(rawValue: 7), title: "Return of the Mount Hua Sect",
                        cover: nil, bytes: 30_000_000, chapterCount: 6),
                    SeriesStorage(
                        id: SeriesRecord.ID(rawValue: 8), title: "Reincarnator", cover: nil,
                        bytes: 28_000_000, chapterCount: 5),
                    SeriesStorage(
                        id: SeriesRecord.ID(rawValue: 9), title: "Weak Hero", cover: nil,
                        bytes: 25_000_000, chapterCount: 5),
                    SeriesStorage(
                        id: SeriesRecord.ID(rawValue: 10), title: "Eleceed", cover: nil,
                        bytes: 22_000_000, chapterCount: 4),
                    SeriesStorage(
                        id: SeriesRecord.ID(rawValue: 11), title: "Lookism", cover: nil,
                        bytes: 20_000_000, chapterCount: 4),
                    SeriesStorage(
                        id: SeriesRecord.ID(rawValue: 12), title: "Sweet Home", cover: nil,
                        bytes: 18_000_000, chapterCount: 3),
                    SeriesStorage(
                        id: SeriesRecord.ID(rawValue: 13), title: "Wind Breaker", cover: nil,
                        bytes: 15_000_000, chapterCount: 3),
                    SeriesStorage(
                        id: SeriesRecord.ID(rawValue: 14), title: "Viral Hit", cover: nil,
                        bytes: 10_000_000, chapterCount: 2),
                ]
            )
        )
        .padding(16)
    }
}
