//
//  DetailsCovers.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI
import Kingfisher

struct DetailsCovers: View {
    let covers: [Cover]
    let referer: URL?
    let isSaving: Bool
    var onSetPreferred: (Int64?) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Int64?
    @State private var previewing: Cover?
    @Namespace private var glass

    private enum Layout {
        // fraction of the sheet width a page occupies - the remainder is what
        // lets the neighbouring covers peek in from the edges
        static let pageWidthFactor: CGFloat = 0.7
        static let peekScale: CGFloat = 0.75
        static let peekOpacity: Double = 0.45
        static let controlHeight: CGFloat = 65
        static let backdropBlur: CGFloat = 60
        static let backdropScale: CGFloat = 1.4
        static let backdropDim: Double = 0.55
        static let iconSize: CGFloat = 20
        static let fillOpacity: Double = 0.1
        static let shadow: CGFloat = 28
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
                // a background cannot change its host's layout size, unlike a
                // ZStack sibling that ignores the safe area - which was laying the
                // action row out wider than the screen
                .background { Backdrop }
                .navigationTitle("Covers")
                .navigationSubtitle("^[\(covers.count) cover](inflect: true) · ^[\(sourceCount) source](inflect: true)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .sensoryFeedback(.selection, trigger: selected)
        .fullScreenCover(item: $previewing) { cover in
            CoverPreview(cover: cover, referer: referer)
        }
    }

    @ViewBuilder
    private var Content: some View {
        if covers.isEmpty {
            EmptyState
        } else {
            // stacked rather than inset - safeAreaInset let the bar escape the
            // sheet's bounds and clip against the screen edge
            VStack(spacing: 0) {
                Pager
                Bar
            }
        }
    }

    // pages span a fraction of the container, so with more than one cover the
    // neighbours visibly poke in from the edges - the swipeability is shown, not
    // told. viewAligned snaps the fractional pages where .paging (which strides
    // by container width) cannot
    // a GeometryReader rather than onGeometryChange: the margins must be right
    // on the very first layout pass, or the initial scroll lands against stale
    // margins and the opening cover sits off-centre
    private var Pager: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: dimensions.spacing.space16) {
                    ForEach(covers) { cover in
                        Page(cover)
                            .containerRelativeFrame([.horizontal, .vertical]) { length, axis in
                                axis == .horizontal ? length * Layout.pageWidthFactor : length
                            }
                            // the focused page at full presence, its neighbours
                            // firmly receded - the size gap is what says "active"
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
            .contentMargins(
                .horizontal,
                proxy.size.width * (1 - Layout.pageWidthFactor) / 2,
                for: .scrollContent
            )
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selected, anchor: .center)
        }
        .onAppear { selected = focused?.id }
    }

    private func Page(_ cover: Cover) -> some View {
        KFImage(cover.artwork)
            .requestModifier(AnyModifier.referer(referer))
            .resizable()
            .placeholder { Rectangle().fill(.primary.opacity(Layout.fillOpacity)).shimmer() }
            .fade(duration: 0.25)
            .scaledToFit()
            .clipShape(.rect(cornerRadius: dimensions.radius.radius28, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: Layout.shadow, y: dimensions.spacing.space8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(cover.sourceName.map { "Cover from \($0)" } ?? "Cover")
    }

    // the selected cover blurred back over itself. content, not chrome, so it is
    // deliberately not glass
    @ViewBuilder
    private var Backdrop: some View {
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
                .ignoresSafeArea()
                .transition(.opacity)
                .id(focused.id)
        }
    }

    @ViewBuilder
    private var Bar: some View {
        if let focused {
            HStack(spacing: dimensions.spacing.space8) {
                PreferredToggle(focused)
                Attribution(focused)
                Overflow(focused)
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.vertical, dimensions.spacing.space12)
        }
    }

    // toggles rather than sets - clearing it hands the choice back to origin priority
    private func PreferredToggle(_ cover: Cover) -> some View {
        Button {
            onSetPreferred(cover.isPreferred ? nil : cover.id)
        } label: {
            Group {
                if isSaving {
                    ProgressView()
                } else {
                    Image(systemName: cover.isPreferred ? "star.fill" : "star")
                        .symbolEffect(.bounce, value: cover.isPreferred)
                }
            }
            .foregroundStyle(cover.isPreferred ? .warning : .textPrimary)
            .frame(width: Layout.controlHeight, height: Layout.controlHeight)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .disabled(isSaving)
        .accessibilityLabel(cover.isPreferred ? "Remove as primary cover" : "Set as primary cover")
    }

    // not interactive - it names where the artwork came from, nothing more
    private func Attribution(_ cover: Cover) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            SourceIcon(cover)

            Text(cover.sourceName ?? "Unknown")
                .font(.title3)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .padding(.horizontal, dimensions.spacing.space12)
        .frame(maxWidth: .infinity)
        .frame(height: Layout.controlHeight)
        .glassEffect(.regular, in: .capsule)
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
        .frame(width: Layout.iconSize, height: Layout.iconSize)
        .clipShape(.rect(cornerRadius: dimensions.radius.radius4))
    }

    private var EmptyState: some View {
        ContentUnavailableView(
            "No Covers",
            systemImage: "photo.on.rectangle",
            description: Text("This series has no covers stored yet")
        )
    }

    // already in kingfisher's cache from rendering the page, so this resolves
    // without a second download in the common case
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

    // clear glass over full-bleed media - the variant meant for exactly this
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

    // snap back when zoomed out, so the image can never be left off-centre
    private func settle() {
        guard scale <= Layout.minScale else { return }
        withAnimation(Layout.settle) {
            scale = Layout.minScale
            offset = .zero
        }
    }
}

extension DetailsCovers {
    struct Cover: Identifiable, Hashable {
        let id: Int64
        // the remote url stays the identity, and stays what Share offers - handing
        // out a file inside the app group container is a different action entirely
        let url: URL
        let local: URL?
        let sourceName: String?
        // nil when the contributing source is no longer installed. qualified
        // because Kingfisher declares an ImageResource of its own
        let sourceIcon: SwiftUI.ImageResource?
        let isPreferred: Bool

        var artwork: URL { local ?? url }
    }
}
