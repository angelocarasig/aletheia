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

    @ViewBuilder
    private var Content: some View {
        Group {
            switch vm?.phase ?? .loading {
            case .loading:
                Skeleton
            case .loaded(let items) where items.isEmpty:
                Unavailable {
                    ContentUnavailableView("No Results", systemImage: "magnifyingglass")
                }
            case .loaded(let items):
                Carousel(items)
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
        .animation(.smooth(duration: 0.35), value: vm?.isIdle)
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
