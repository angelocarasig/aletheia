//
//  FailuresScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Kingfisher
import SwiftUI
import Tagged

struct FailuresScreen: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    @State private var vm: FailuresViewModel?
    @State private var route: SeriesEntry?

    @State private var grouping: FailuresViewModel.Grouping = .source

    private enum Layout {
        static let fillOpacity = 0.05
        static let iconSize: CGFloat = 36
        static let headerIconSize: CGFloat = 24
        static let coverAspect: CGFloat = 11 / 16
        static let coverWidth: CGFloat = 96
        static let headerCoverHeight: CGFloat = 24
        static let placeholderOpacity = 0.1
    }

    private var phase: LoadPhase {
        if let vm {
            if vm.failure != nil {
                .failed
            } else if vm.entries == nil {
                .pending
            } else if vm.isEmpty {
                .empty
            } else {
                .content
            }
        } else {
            .pending
        }
    }

    var body: some View {
        ZStack {
            switch phase {
            case .content:
                if let vm { List(vm).transition(.opacity) }
            case .empty:
                Recovered.transition(.opacity)
            case .failed:
                if let vm, let failure = vm.failure {
                    Unavailable(failure).transition(.opacity)
                }
            default:
                ProgressView().transition(.opacity)
            }
        }
        .animation(.settle, value: phase)
        .navigationTitle("Failures")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { DetailsScreen(entry: $0) }
        .task {
            guard vm == nil else { return }
            let model = FailuresViewModel(
                database: compositor.database,
                registry: compositor.registry,
                refresher: compositor.refresh,
                trackers: compositor.trackers
            )
            vm = model
            model.observe()
        }
    }
}

// MARK: - Content

extension FailuresScreen {
    fileprivate func List(_ vm: FailuresViewModel) -> some View {
        VStack(spacing: 0) {
            if (vm.entries?.count ?? 0) > 1 {
                GroupingControl
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                    ForEach(vm.sections(by: grouping)) { section in
                        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                            Header(section, vm: vm)

                            ForEach(section.entries) { entry in
                                Row(entry, vm: vm)
                            }
                        }
                    }

                    if let links = vm.links, !links.isEmpty {
                        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                            TrackingHeader(links.count)

                            ForEach(links) { entry in
                                TrackingRow(entry, vm: vm)
                            }
                        }
                    }
                }
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.vertical, dimensions.spacing.space16)
            }
        }
        .animation(.settle, value: grouping)
    }

    fileprivate var GroupingControl: some View {
        Picker("Group by", selection: $grouping) {
            ForEach(FailuresViewModel.Grouping.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, dimensions.screenMargin)
        .padding(.vertical, dimensions.spacing.space8)
    }

    @ViewBuilder
    fileprivate func Header(_ section: FailuresViewModel.Section, vm: FailuresViewModel)
        -> some View
    {
        if grouping == .series, let entry = section.entries.first {
            HeaderContent(section, vm: vm)
                .contentShape(.rect)
                .tappable { route = SeriesEntry.library(SeriesRecord.ID(rawValue: entry.seriesId)) }
                .accessibilityHint("Opens the series")
        } else {
            HeaderContent(section, vm: vm)
        }
    }

    fileprivate func HeaderContent(_ section: FailuresViewModel.Section, vm: FailuresViewModel)
        -> some View
    {
        HStack(spacing: dimensions.spacing.space8) {
            // scoped to this half only - folding RetryAllButton into the combine would lose its own action
            HStack(spacing: dimensions.spacing.space8) {
                if let slug = section.sourceSlug {
                    if let icon = compositor.registry.source(slug: slug)?.descriptor.icon {
                        Image(icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: Layout.headerIconSize, height: Layout.headerIconSize)
                            .clipShape(.rect(cornerRadius: dimensions.radius.radius4))
                    }
                } else if let entry = section.entries.first {
                    HeaderCover(entry)
                }

                Text(section.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Count(section)
            }
            .accessibilityElement(children: .combine)

            if section.count > 1 {
                RetryAllButton(section, vm: vm)
            }

            if grouping == .series {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: dimensions.touchTarget)
    }

    @ViewBuilder
    fileprivate func RetryAllButton(_ section: FailuresViewModel.Section, vm: FailuresViewModel)
        -> some View
    {
        let retrying = section.entries.contains { vm.retrying.contains($0.id) }

        if retrying {
            ProgressView()
                .controlSize(.small)
        } else {
            Text("Retry All")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.brand)
                .padding(.horizontal, dimensions.spacing.space12)
                .padding(.vertical, dimensions.spacing.space4)
                .background(.brand.opacity(0.1), in: .capsule)
                .tappable { Task { await vm.retryAll(section.entries) } }
                .accessibilityLabel("Retry all \(section.count) failures")
        }
    }

    @ViewBuilder
    fileprivate func Count(_ section: FailuresViewModel.Section) -> some View {
        // each branch keeps its own string literal - interpolating into a shared one erases the inflection markup
        if grouping == .source {
            Text("^[\(section.count) series](inflect: true)")
                .font(.caption)
                .foregroundStyle(.muted)
        } else {
            Text("^[\(section.count) source](inflect: true)")
                .font(.caption)
                .foregroundStyle(.muted)
        }
    }

    @ViewBuilder
    fileprivate func Row(_ entry: FailuresViewModel.Entry, vm: FailuresViewModel) -> some View {
        if grouping == .source {
            RowCard(entry, vm: vm)
                .contentShape(.rect)
                .tappable { route = SeriesEntry.library(SeriesRecord.ID(rawValue: entry.seriesId)) }
        } else {
            RowCard(entry, vm: vm)
        }
    }

    fileprivate func RowCard(_ entry: FailuresViewModel.Entry, vm: FailuresViewModel) -> some View {
        HStack(spacing: 0) {
            if grouping == .source {
                Cover(entry)
            }

            VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                HStack(spacing: dimensions.spacing.space12) {
                    if grouping == .series {
                        Icon(entry)
                    }

                    Text(grouping == .source ? entry.title : entry.sourceName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if grouping == .source {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(entry.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    HStack(spacing: dimensions.spacing.space4) {
                        Text("Last tried")
                        LiveRelativeText(date: entry.attemptedDate)
                    }
                    .font(.caption2)
                    .foregroundStyle(.muted)

                    Spacer(minLength: 0)

                    Retry(entry, vm: vm)
                }
            }
            .padding(dimensions.spacing.space12)
        }
        // clipShape must precede glassEffect - glassEffect shapes what it draws behind, not the card's content
        .clipShape(.rect(cornerRadius: dimensions.radius.radius12, style: .continuous))
        .glassEffect(
            grouping == .source ? .regular.interactive() : .regular,
            in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
    }

    fileprivate func Cover(_ entry: FailuresViewModel.Entry) -> some View {
        let local = compositor.assets.local(for: entry.path)

        return Color.clear
            .frame(width: Layout.coverWidth)
            .frame(maxHeight: .infinity)
            .overlay {
                if let cover = local ?? entry.cover {
                    KFImage(cover)
                        .resizable()
                        .placeholder {
                            Rectangle().fill(.primary.opacity(Layout.placeholderOpacity)).shimmer()
                        }
                        .fade(duration: 0.25)
                        .scaledToFill()
                } else {
                    Rectangle().fill(.primary.opacity(Layout.placeholderOpacity))
                }
            }
            .clipped()
    }

    fileprivate func HeaderCover(_ entry: FailuresViewModel.Entry) -> some View {
        let local = compositor.assets.local(for: entry.path)

        return Color.clear
            .aspectRatio(Layout.coverAspect, contentMode: .fit)
            .frame(height: Layout.headerCoverHeight)
            .overlay {
                if let cover = local ?? entry.cover {
                    KFImage(cover)
                        .resizable()
                        .placeholder {
                            Rectangle().fill(.primary.opacity(Layout.placeholderOpacity)).shimmer()
                        }
                        .fade(duration: 0.25)
                        .scaledToFill()
                } else {
                    Rectangle().fill(.primary.opacity(Layout.placeholderOpacity))
                }
            }
            .clipShape(.rect(cornerRadius: dimensions.radius.radius4))
    }

    @ViewBuilder
    fileprivate func Icon(_ entry: FailuresViewModel.Entry) -> some View {
        if let icon = compositor.registry.source(slug: entry.sourceSlug)?.descriptor.icon {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius8))
        } else {
            Image(systemName: "questionmark")
                .font(.footnote)
                .foregroundStyle(.muted)
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .background(
                    .primary.opacity(Layout.fillOpacity),
                    in: .rect(cornerRadius: dimensions.radius.radius8))
        }
    }

    // shares the same fetch unit as the background refresher, so a retry mid-refresh joins it instead of racing it
    @ViewBuilder
    fileprivate func Retry(_ entry: FailuresViewModel.Entry, vm: FailuresViewModel) -> some View {
        if vm.retrying.contains(entry.id) {
            ProgressView()
                .controlSize(.small)
        } else {
            Text("Try Again")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.brand)
                .padding(.horizontal, dimensions.spacing.space12)
                .padding(.vertical, dimensions.spacing.space4)
                .background(.brand.opacity(0.1), in: .capsule)
                .tappable { Task { await vm.retry(entry) } }
        }
    }

    fileprivate var Recovered: some View {
        ContentUnavailableView {
            Label("Everything's Working", systemImage: "checkmark.circle")
        } description: {
            Text("Nothing is failing to check for new chapters or to reach a tracker.")
        }
    }

    // MARK: Tracking

    fileprivate func TrackingHeader(_ count: Int) -> some View {
        HStack(spacing: dimensions.spacing.space8) {
            Image(systemName: "app.connected.to.app.below.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: Layout.headerIconSize)

            Text("Tracking")
                .font(.subheadline)
                .fontWeight(.semibold)

            Spacer(minLength: 0)

            Text("^[\(count) series](inflect: true)")
                .font(.caption)
                .foregroundStyle(.muted)
        }
        .frame(minHeight: dimensions.touchTarget)
        .accessibilityElement(children: .combine)
    }

    fileprivate func TrackingRow(_ entry: FailuresViewModel.TrackerEntry, vm: FailuresViewModel)
        -> some View
    {
        HStack(spacing: 0) {
            TrackingCover(entry)

            VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                HStack(spacing: dimensions.spacing.space12) {
                    Image(entry.tracker.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: Layout.iconSize, height: Layout.iconSize)
                        .clipShape(.rect(cornerRadius: dimensions.radius.radius8))

                    VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                        Text(entry.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if entry.remoteTitle != entry.title, !entry.remoteTitle.isEmpty {
                            Text("Linked to \(entry.remoteTitle)")
                                .font(.caption2)
                                .foregroundStyle(.muted)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(entry.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    HStack(spacing: dimensions.spacing.space4) {
                        Text("Last tried")
                        LiveRelativeText(date: entry.attemptedDate)
                    }
                    .font(.caption2)
                    .foregroundStyle(.muted)

                    Spacer(minLength: 0)

                    TrackingRetry(entry, vm: vm)
                }
            }
            .padding(dimensions.spacing.space12)
        }
        .clipShape(.rect(cornerRadius: dimensions.radius.radius12, style: .continuous))
        .glassEffect(
            .regular.interactive(),
            in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
        .contentShape(.rect)
        .tappable { route = SeriesEntry.library(SeriesRecord.ID(rawValue: entry.seriesId)) }
    }

    fileprivate func TrackingCover(_ entry: FailuresViewModel.TrackerEntry) -> some View {
        let local = compositor.assets.local(for: entry.path)

        return Color.clear
            .frame(width: Layout.coverWidth)
            .frame(maxHeight: .infinity)
            .overlay {
                if let cover = local ?? entry.cover {
                    KFImage(cover)
                        .resizable()
                        .placeholder {
                            Rectangle().fill(.primary.opacity(Layout.placeholderOpacity)).shimmer()
                        }
                        .fade(duration: 0.25)
                        .scaledToFill()
                } else {
                    Rectangle().fill(.primary.opacity(Layout.placeholderOpacity))
                }
            }
            .clipped()
    }

    // no spinner here unlike Retry above - a tracking retry wakes the whole lane, not this row alone, so there is no per-row progress to show
    fileprivate func TrackingRetry(_ entry: FailuresViewModel.TrackerEntry, vm: FailuresViewModel)
        -> some View
    {
        Text("Try Again")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.brand)
            .padding(.horizontal, dimensions.spacing.space12)
            .padding(.vertical, dimensions.spacing.space4)
            .background(.brand.opacity(0.1), in: .capsule)
            .tappable { vm.retry(entry) }
    }

    fileprivate func Unavailable(_ failure: Failure) -> some View {
        ContentUnavailableView {
            Label(failure.title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(failure.message)
        }
    }
}
