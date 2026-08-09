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
        .task {
            let vm = vm ?? SourcePresetViewModel(source: source, preset: preset, database: compositor.database)
            self.vm = vm
            if vm.isIdle { await vm.load() } else { vm.resume() }
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
                Unavailable {
                    ContentUnavailableView("No Results", systemImage: "magnifyingglass")
                }
            case .content:
                if case .loaded(let items) = vm?.phase {
                    Carousel(items)
                }
            case .failed:
                Unavailable {
                    ContentUnavailableView {
                        Label("Couldn't Load", systemImage: "exclamationmark.triangle")
                    } actions: {
                        Button("Retry") { Task { await vm?.load() } }
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

    private func Unavailable<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .frame(height: Layout.unavailableHeight)
    }
}
