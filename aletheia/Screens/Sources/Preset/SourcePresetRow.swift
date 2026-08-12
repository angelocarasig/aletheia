//
//  SourcePresetRow.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI

struct SourcePresetRow: View {
    let source: Source
    let preset: SourcePreset
    let onOpen: () -> Void
    let onOpenSeries: (SeriesStub) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.compositor) private var compositor
    @State private var vm: SourcePresetViewModel?

    // handed one only by previews, which drive the phases by hand. supplying it
    // is also what tells `task` not to fetch
    init(
        source: Source,
        preset: SourcePreset,
        vm: SourcePresetViewModel? = nil,
        onOpen: @escaping () -> Void,
        onOpenSeries: @escaping (SeriesStub) -> Void
    ) {
        self.source = source
        self.preset = preset
        self.onOpen = onOpen
        self.onOpenSeries = onOpenSeries
        _vm = State(initialValue: vm)
    }

    private enum Layout {
        static let skeletonCount = 6
        static let carouselVisible = 3
        static let unavailableHeight: CGFloat = 160
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            Header
            Content
        }
        .padding(dimensions.spacing.space16)
        .background(.surface)
        .clipShape(.rect(cornerRadius: dimensions.radius.radius12))
        // a model already here means the row is coming back after scrolling
        // away, so it picks its observation up rather than fetching again - and
        // it is the same branch a preview arrives on, which is what keeps a
        // preview off the network
        .task {
            guard vm == nil else {
                vm?.resume()
                return
            }
            let model = SourcePresetViewModel(source: source, preset: preset, database: compositor.database)
            vm = model
            await model.load()
        }
        .onDisappear { vm?.stop() }
    }

    private var Header: some View {
        HStack(alignment: .firstTextBaseline, spacing: dimensions.spacing.space8) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(preset.name)
                    .font(.title2)
                    .fontWeight(.bold)

                if let subtitle = preset.subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.muted)
                }
            }

            Spacer()

            Image(systemName: "chevron.forward")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.muted)
        }
        .contentShape(.rect)
        .tappable(action: onOpen)
    }

    // branch selector and animation key are one value - the old isIdle key was
    // a bool proxy, so loaded -> failed and loaded -> empty never animated
    private var phase: LoadPhase {
        switch vm?.phase {
        case nil, .loading: .pending
        case .loaded(let items) where items.isEmpty: .empty
        case .loaded: .content
        case .failed: .failed
        }
    }

    @ViewBuilder
    private var Content: some View {
        Group {
            switch phase {
            case .pending:
                Skeleton
            case .empty:
                // a preset is a standing request the source answers for itself,
                // so an empty one is the source having nothing to say rather
                // than a query that matched nothing - there is no filter here to
                // clear and no text to correct. that leaves asking again as the
                // only move, which is why this carries the same action as the
                // failed branch instead of being a dead end
                Unavailable {
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        Text("\(source.descriptor.name) didn't return anything for this.")
                    } actions: {
                        Button("Retry") { Task { await vm?.load() } }
                    }
                }
            case .content:
                if case .loaded(let items) = vm?.phase {
                    Carousel(items)
                }
            case .failed:
                if case .failed(let failure) = vm?.phase {
                    Unavailable {
                        ContentUnavailableView {
                            Label(failure.title, systemImage: "exclamationmark.triangle")
                        } description: {
                            // empty when the error states a title and nothing
                            // else, and ContentUnavailableView draws no gap for
                            // an empty description - so this needs no branch
                            Text(failure.message)
                        } actions: {
                            // an offer, not furniture: a source that will never
                            // answer this request gets no button
                            if failure.isRetryable {
                                Button("Retry") { Task { await vm?.load() } }
                            }
                        }
                    }
                }
            }
        }
        .transition(.opacity)
        .animation(.settle, value: phase)
    }

    private var Skeleton: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: dimensions.spacing.space12) {
                ForEach(0..<Layout.skeletonCount, id: \.self) { _ in
                    SourceCard()
                        .containerRelativeFrame(
                            .horizontal,
                            count: Layout.carouselVisible,
                            spacing: dimensions.spacing.space12
                        )
                }
            }
        }
        .scrollDisabled(true)
        .shimmer()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func Carousel(_ items: [SeriesStub]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: dimensions.spacing.space12) {
                ForEach(items, id: \.slug) { stub in
                    SourceCard(stub: stub, referer: source.descriptor.referer, match: vm?.match(for: stub))
                        .containerRelativeFrame(
                            .horizontal,
                            count: Layout.carouselVisible,
                            spacing: dimensions.spacing.space12
                        )
                        .tappable { onOpenSeries(stub) }
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
    }

    // a floor rather than a fixed height: the two branches that use this hold
    // different amounts - a glyph, a title, a sentence and a button between them
    // - and a box pinned to the shorter one clips the taller at larger text
    // sizes. nothing here declares its height for a scroll offset the way the
    // reader's separator does, so it is free to grow
    private func Unavailable<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .frame(minHeight: Layout.unavailableHeight)
    }
}

// MARK: - Previews

// one preview rather than four, because the thing worth looking at is the
// crossfade BETWEEN the branches: they are one animation keyed to one value, and
// four static previews show the states while hiding the only part that can break
#if DEBUG
private struct PresetPreview: View {
    private static let stubs: [SeriesStub] = [
        .init(slug: "a", title: "Witch Hat Atelier", cover: nil),
        .init(slug: "b", title: "The Knight Only Lives Today", cover: nil),
        .init(slug: "c", title: "The Greatest Estate Developer", cover: nil),
        .init(slug: "d", title: "Pick Me Up", cover: nil)
    ]

    private static let steps: [(name: String, phase: SourcePresetViewModel.Phase)] = [
        ("Loading", .loading),
        ("Content", .loaded(stubs)),
        ("Empty", .loaded([])),
        ("Failed", .failed(Failure(NetworkError.offline, fallback: "Couldn't Load"))),
        // the other half of the failed branch: a reason that states a title and
        // nothing under it, and one that does not earn a retry
        ("Failed, terminal", .failed(.init(title: "Couldn't Load", message: "", isRetryable: false)))
    ]

    private let source = AtsumaruSource(network: NetworkService())
    private let preset = SourcePreset(
        id: "updated",
        name: "Recently Updated",
        subtitle: "Freshly released chapters",
        order: 0,
        route: "recentlyUpdated"
    )

    @State private var step = 0
    @State private var vm: SourcePresetViewModel?

    var body: some View {
        VStack(spacing: 16) {
            if let vm {
                SourcePresetRow(
                    source: source,
                    preset: preset,
                    vm: vm,
                    onOpen: {},
                    onOpenSeries: { _ in }
                )
                // the row keeps its identity across the change, or SwiftUI
                // replaces the whole thing and the branch transition never runs
                .id("row")
            }

            Button {
                step = (step + 1) % Self.steps.count
                vm?.preview(phase: Self.steps[step].phase)
            } label: {
                Label("Next: \(Self.steps[(step + 1) % Self.steps.count].name)", systemImage: "arrow.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)

            Text("Showing \(Self.steps[step].name)")
                .font(.caption)
                .foregroundStyle(.muted)
        }
        .padding()
        .frame(maxHeight: .infinity)
        .background(.canvas)
        .task {
            guard vm == nil else { return }
            let model = SourcePresetViewModel(
                source: source,
                preset: preset,
                database: .preview
            )
            model.preview(phase: Self.steps[step].phase)
            vm = model
        }
    }
}

#Preview("Preset row") {
    PresetPreview()
}
#endif
