//
//  DetailsCovers.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Kingfisher
import SwiftUI

struct DetailsCovers: View {
    let covers: [Cover]
    let referer: URL?
    let isSaving: Bool
    var onSetPreferred: (Int64?) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Int64?
    @State private var previewing: Cover?
    @State private var showingGrid = false
    @Namespace private var glass

    private enum Layout {
        static let pageWidthFactor: CGFloat = 0.7
        static let peekScale: CGFloat = 0.75
        static let peekOpacity: Double = 0.45
        static let controlHeight: CGFloat = 65
        static let backdropBlur: CGFloat = 60
        static let backdropScale: CGFloat = 1.4
        static let backdropDim: Double = 0.55
        static let iconSize: CGFloat = 40
        static let gridIconSize: CGFloat = 25
        static let fillOpacity: Double = 0.1
        static let shadow: CGFloat = 28
        static let savingOpacity: Double = 0.6
        static let badgePadding: CGFloat = 10
        static let settle: Animation = .smooth(duration: 0.25)
        static let pageHeightFactor: CGFloat = 0.92
        static let coverRatio: CGFloat = 1414.0 / 1000.0
        static let gridMinWidth: CGFloat = 104
        static let gridRatio: CGFloat = 0.7
        static let gridBadgePadding: CGFloat = 6
    }

    private var preferredId: Int64? {
        covers.first(where: \.isPreferred)?.id
    }

    private var sourceCount: Int {
        Set(covers.compactMap(\.sourceName)).count
    }

    private var focused: Cover? {
        selected.flatMap { id in covers.first { $0.id == id } }
            ?? covers.first { $0.isPreferred }
            ?? covers.first
    }

    var body: some View {
        NavigationStack {
            Content
                // .background here, not a ZStack sibling - a ZStack sibling
                // ignoring the safe area laid the action row out wider than
                // the screen; .background cannot change its host's layout size
                .background { Backdrop }
                .navigationTitle("Covers")
                .navigationSubtitle(
                    "^[\(covers.count) cover](inflect: true) · ^[\(sourceCount) source](inflect: true)"
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("All Covers", systemImage: "square.grid.2x2") {
                            showingGrid.toggle()
                        }
                        .labelStyle(.iconOnly)
                        .symbolVariant(showingGrid ? .fill : .none)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.selection, trigger: selected)
        .sensoryFeedback(.selection, trigger: preferredId)
        .fullScreenCover(item: $previewing) { cover in
            CoverPreview(cover: cover, referer: referer)
        }
    }

    @ViewBuilder
    private var Content: some View {
        if covers.isEmpty {
            EmptyState
        } else {
            // stacked, not safeAreaInset - safeAreaInset let the bar escape
            // the sheet's bounds and clip against the screen edge
            VStack(spacing: 0) {
                if showingGrid {
                    Grid
                } else {
                    Pager
                    Bar
                }
            }
            .opacity(isSaving ? Layout.savingOpacity : 1)
            .animation(Layout.settle, value: showingGrid)
        }
    }

    // GeometryReader, not onGeometryChange - the margins must be right on the
    // very first layout pass, or the initial scroll lands against stale
    // margins and the opening cover sits off-centre
    private var Pager: some View {
        GeometryReader { proxy in
            // width follows the cover ratio at the current height, capped at
            // the wide-detent fraction, so a height-bound cover at a short
            // detent still leaves room for neighbours to peek
            let artworkWidth =
                proxy.size.height * Layout.pageHeightFactor / Layout.coverRatio
                + dimensions.spacing.space8 * 2
            // containerRelativeFrame is not used here - inside a margined
            // scroll view it measures an ambiguous container, which kept
            // skewing the centring
            let pageWidth = min(proxy.size.width * Layout.pageWidthFactor, artworkWidth)
            let margin = (proxy.size.width - pageWidth) / 2

            ScrollView(.horizontal, showsIndicators: false) {
                // spacing lives INSIDE each page (as padding), not between
                // items: viewAligned aligns item edges to the margin edge, so
                // any inter-item spacing shifts the landing off-centre
                LazyHStack(spacing: 0) {
                    ForEach(covers) { cover in
                        Page(cover, maxHeight: proxy.size.height * Layout.pageHeightFactor)
                            .padding(.horizontal, dimensions.spacing.space8)
                            .frame(width: pageWidth, height: proxy.size.height)
                            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1 : Layout.peekScale)
                                    .opacity(phase.isIdentity ? 1 : Layout.peekOpacity)
                            }
                            .id(cover.id)
                    }
                }
                .scrollTargetLayout()
            }
            // margins centre the first and last page; without them viewAligned
            // pins the ends to the edge and the affordance dies exactly there
            .contentMargins(.horizontal, margin, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selected, anchor: .center)
            .animation(Layout.settle, value: preferredId)
        }
        .onAppear { selected = focused?.id }
    }

    private var Grid: some View {
        ScrollView {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: Layout.gridMinWidth), spacing: dimensions.spacing.space12
                    )
                ],
                spacing: dimensions.spacing.space12
            ) {
                ForEach(covers) { cover in
                    GridItemView(cover)
                        .tappable {
                            selected = cover.id
                            showingGrid = false
                        }
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.bottom, dimensions.spacing.space24)
        }
        .scrollContentBackground(.hidden)
    }

    private func GridItemView(_ cover: Cover) -> some View {
        KFImage(cover.artwork)
            .requestModifier(AnyModifier.referer(referer))
            .resizable()
            .placeholder { Rectangle().fill(.primary.opacity(Layout.fillOpacity)).shimmer() }
            .fade(duration: 0.25)
            .scaledToFill()
            .aspectRatio(Layout.gridRatio, contentMode: .fit)
            .clipShape(.rect(cornerRadius: dimensions.radius.radius16, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if cover.isPreferred {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.brand, .white)
                        .padding(Layout.gridBadgePadding)
                }
            }
            .overlay(alignment: .topLeading) {
                SourceIcon(cover)
                    .padding(Layout.gridBadgePadding)
            }
            .contentShape(.rect)
            .accessibilityLabel(cover.sourceName.map { "Cover from \($0)" } ?? "Cover")
            .accessibilityAddTraits(cover.isPreferred ? .isSelected : [])
    }

    // the height bound is applied OUTSIDE the clip and overlays - a max frame
    // expands to its proposal rather than hugging its child, so putting it
    // between the image and the badges letterboxes the view and the badges
    // pin to empty space instead of the artwork corners
    private func Page(_ cover: Cover, maxHeight: CGFloat) -> some View {
        KFImage(cover.artwork)
            .requestModifier(AnyModifier.referer(referer))
            .resizable()
            .placeholder { Rectangle().fill(.primary.opacity(Layout.fillOpacity)).shimmer() }
            .fade(duration: 0.25)
            .scaledToFit()
            .clipShape(.rect(cornerRadius: dimensions.radius.radius16, style: .continuous))
            .overlay(alignment: .topTrailing) {
                if cover.isPreferred {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.brand, .white)
                        .padding(Layout.badgePadding)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .topLeading) {
                SourceIcon(cover)
                    .padding(Layout.badgePadding)
            }
            .shadow(color: .black.opacity(0.5), radius: Layout.shadow, y: dimensions.spacing.space8)
            .frame(maxHeight: max(maxHeight, 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(cover.sourceName.map { "Cover from \($0)" } ?? "Cover")
            .accessibilityAddTraits(cover.isPreferred ? .isSelected : [])
    }

    // the animation lives on this stable Color.clear base, not on the image -
    // .id(focused.id) replaces the KFImage as the pager swipes, so an
    // animation on the image itself is torn down with it and cuts instantly
    @ViewBuilder
    private var Backdrop: some View {
        Color.clear
            .overlay {
                if let focused {
                    KFImage(focused.artwork)
                        .requestModifier(AnyModifier.referer(referer))
                        .resizable()
                        .placeholder { Color.clear }
                        .fade(duration: 0.25)
                        .scaledToFill()
                        .scaleEffect(Layout.backdropScale)
                        .blur(radius: Layout.backdropBlur)
                        .overlay(Color.black.opacity(Layout.backdropDim))
                        .transition(.opacity)
                        .id(focused.id)
                }
            }
            .ignoresSafeArea()
            .animation(.smooth(duration: 0.35), value: focused?.id)
    }

    @ViewBuilder
    private var Bar: some View {
        if let focused {
            HStack(spacing: dimensions.spacing.space8) {
                PreferredToggle(focused)
                Overflow(focused)
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.vertical, dimensions.spacing.space12)
            .animation(Layout.settle, value: focused.id)
            .animation(Layout.settle, value: preferredId)
        }
    }

    private func PreferredToggle(_ cover: Cover) -> some View {
        Button {
            onSetPreferred(cover.isPreferred ? nil : cover.id)
        } label: {
            Label(
                cover.isPreferred ? "Remove as Preferred Cover" : "Set as Preferred Cover",
                systemImage: cover.isPreferred ? "xmark" : "checkmark"
            )
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.textPrimary)
            .lineLimit(1)
            .contentTransition(.opacity)
            .padding(.horizontal, dimensions.spacing.space16)
            .frame(maxWidth: .infinity)
            .frame(height: Layout.controlHeight)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
        .disabled(isSaving)
        .accessibilityLabel(
            cover.isPreferred ? "Remove as preferred cover" : "Set as preferred cover"
        )
        .accessibilityAddTraits(cover.isPreferred ? .isSelected : [])
    }

    private func Overflow(_ cover: Cover) -> some View {
        Menu {
            Button {
                previewing = cover
            } label: {
                Label("View Fullscreen", systemImage: "arrow.up.left.and.arrow.down.right")
            }

            ShareLink(item: cover.url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Button {
                save(cover)
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.textPrimary)
                .frame(width: Layout.controlHeight, height: Layout.controlHeight)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("More actions")
    }

    @ViewBuilder
    private func SourceIcon(_ cover: Cover) -> some View {
        let size = showingGrid ? Layout.gridIconSize : Layout.iconSize
        Group {
            if let icon = cover.sourceIcon {
                Image(icon)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: dimensions.radius.radius4)
                    .fill(.primary.opacity(Layout.fillOpacity))
                    .shimmer()
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: dimensions.radius.radius4))
        .animation(Layout.settle, value: showingGrid)
    }

    private var EmptyState: some View {
        ContentUnavailableView(
            "No Covers",
            systemImage: "photo.on.rectangle",
            description: Text("This series has no covers stored yet")
        )
    }

    private func save(_ cover: Cover) {
        let options: KingfisherOptionsInfo = [.requestModifier(AnyModifier.referer(referer))]

        KingfisherManager.shared.retrieveImage(with: cover.artwork, options: options) { result in
            guard case .success(let value) = result else { return }
            UIImageWriteToSavedPhotosAlbum(value.image, nil, nil, nil)
        }
    }
}

private struct CoverPreview: View {
    let cover: DetailsCovers.Cover
    let referer: URL?

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero

    private enum Layout {
        static let doubleTapScale: CGFloat = 2.5
        static let minScale: CGFloat = 1
        static let maxScale: CGFloat = 6
        static let settle: Animation = .spring(response: 0.3, dampingFraction: 0.8)
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            KFImage(cover.artwork)
                .requestModifier(AnyModifier.referer(referer))
                .resizable()
                .placeholder { ProgressView().tint(.white) }
                .scaledToFit()
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnify.simultaneously(with: pan))
                .onTapGesture(count: 2) { toggleZoom() }
        }
        .overlay(alignment: .topTrailing) { Close }
    }

    private var Close: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(width: dimensions.touchTarget, height: dimensions.touchTarget)
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.interactive(), in: .circle)
        .accessibilityLabel("Close")
        .padding(dimensions.screenMargin)
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { scale = min(max($0.magnification, Layout.minScale), Layout.maxScale) }
            .onEnded { _ in settle() }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { if scale > Layout.minScale { offset = $0.translation } }
            .onEnded { _ in settle() }
    }

    private func toggleZoom() {
        withAnimation(Layout.settle) {
            scale = scale > Layout.minScale ? Layout.minScale : Layout.doubleTapScale
            offset = .zero
        }
    }

    private func settle() {
        guard scale <= Layout.minScale else { return }
        withAnimation(Layout.settle) {
            scale = Layout.minScale
            offset = .zero
        }
    }
}

extension DetailsCovers {
    typealias Cover = DetailsComposer.Series.Cover
}
