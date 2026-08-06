//
//  DetailsScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI

struct DetailsScreen: View {
    let entry: SeriesEntry

    @Environment(\.database) private var database
    @Environment(\.dimensions) private var dimensions
    @Environment(\.compositor) private var compositor

    @State private var vm: DetailsViewModel?
    @State private var reading: DetailsChapters.Chapter?
    @State private var showingCovers = false
    @State private var showingDisambiguation = false
    // written here, read only inside the backdrop - reading it in this body
    // would re-evaluate the whole chapter list on every scroll step
    @State private var scroll = DetailsScroll()

    // resolved rather than computed: a library entry has to look up its primary
    // origin before there is a source to read from
    @State private var route: DetailsRoute?
    @State private var unresolved = false

    private enum Layout {
        // the skeleton mirrors the real layout, so a crossfade reads as the
        // placeholder resolving rather than one screen replacing another
        static let settle: Animation = .smooth(duration: 0.35)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // outside the branch so the skeleton sits on it too - it was
            // rendering against the system background before
            Palette.canvas
                .ignoresSafeArea()

            if let vm, vm.isReady {
                DetailsBackdrop(cover: vm.cover, referer: route?.source.descriptor.referer, scroll: scroll)
                    .transition(.opacity)

                ScrollView(.vertical, showsIndicators: false) {
                    Content(vm)
                }
                .transition(.opacity)
                // clamped inside the transform, not after: the callback only
                // fires when its value changes, so clamping stops it entirely
                // past the ramp rather than firing for another 149,000 points of
                // chapter list. rounding bounds the ramp itself to a few updates
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    let scrolled = geometry.contentOffset.y + geometry.contentInsets.top
                    let ramped = min(max(scrolled, 0), DetailsBackdrop.rampDistance)
                    return (ramped / DetailsBackdrop.rampStep).rounded() * DetailsBackdrop.rampStep
                } action: { _, offset in
                    scroll.offset = offset
                }
                .scrollEdgeEffectStyle(.soft, for: .top)
            } else if unresolved {
                // no installed source can serve this series - the rows are still
                // in the database, but nothing can fetch or read from them
                ContentUnavailableView(
                    "Source Unavailable",
                    systemImage: "questionmark.circle",
                    description: Text("No installed source can open this series")
                )
                .transition(.opacity)
            } else {
                DetailsSkeleton()
                    .transition(.opacity)
            }
        }
        .animation(Layout.settle, value: vm?.isReady ?? false)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $reading) { chapter in
            if let route {
                ReaderScreen(
                    source: route.source,
                    seriesSlug: route.stub.slug,
                    chapterSlug: chapter.id,
                    title: "Ch. \(chapter.number.formatted())"
                )
            }
        }
        .sheet(isPresented: $showingDisambiguation) {
            if let vm, let route {
                DetailsDisambiguation(
                    title: vm.title,
                    sourceName: route.source.descriptor.name,
                    candidates: vm.candidates,
                    onAttach: { id in
                        showingDisambiguation = false
                        Task { await vm.attach(to: id) }
                    },
                    onKeepSeparate: {
                        showingDisambiguation = false
                        vm.keepSeparate()
                    }
                )
                .interactiveDismissDisabled()
            }
        }
        .onChange(of: vm?.needsDisambiguation ?? false) { _, needs in
            showingDisambiguation = needs
        }
        .sheet(isPresented: $showingCovers) {
            if let vm {
                DetailsCovers(
                    covers: vm.covers,
                    referer: route?.source.descriptor.referer,
                    isSaving: vm.isSaving,
                    onSetPreferred: { id in Task { await vm.setPreferredCover(id) } }
                )
            }
        }
        .task {
            guard vm == nil else { return }

            guard let route = await DetailsViewModel.route(
                for: entry,
                registry: compositor.registry,
                database: database
            ) else {
                unresolved = true
                return
            }

            self.route = route

            let vm = DetailsViewModel(
                source: route.source,
                stub: route.stub,
                registry: compositor.registry,
                database: database
            )
            self.vm = vm
            await vm.load()
        }
    }

    private func Content(_ vm: DetailsViewModel) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space20) {
            // the backdrop shows through here rather than parallaxing - it is a
            // sibling of the scroll view, not a header inside it
            Spacer()
                .frame(height: DetailsBackdrop.heroHeight)

            DetailsHeader(
                cover: vm.cover,
                referer: route?.source.descriptor.referer,
                title: vm.title,
                authors: vm.authors,
                onOpenCovers: { showingCovers = true },
                onOpenTitles: { fatalError("not implemented") }
            )

            DetailsActions(
                inLibrary: vm.inLibrary,
                isSaving: vm.isSaving,
                canToggle: vm.canToggleLibrary,
                status: vm.status,
                onToggleLibrary: { Task { await vm.toggleLibrary() } },
                onSetStatus: { status in Task { await vm.setStatus(status) } }
            )

            if let synopsis = vm.detail?.synopsis, !synopsis.isEmpty {
                DetailsSynopsis(synopsis: synopsis)
            }

            if !vm.tags.isEmpty {
                DetailsTags(tags: vm.tags)
            }

            if !vm.origins.isEmpty {
                DetailsSources(origins: vm.origins)
            }

            DetailsCollections(collections: vm.collections)

            DetailsMetadata(
                classification: vm.detail?.classification,
                publication: vm.detail?.publication,
                readCount: 0,
                totalCount: vm.chapterDisplays.count,
                lastFetchedDate: vm.lastMetadataFetch,
                lastReadDate: nil
            )

            DetailsChapters(
                chapters: vm.chapterDisplays,
                isFetching: vm.isFetchingChapters,
                hasFetched: vm.hasFetchedChapters
            ) { chapter in
                reading = chapter
            }
        }
        .padding(.horizontal, dimensions.spacing.space8)
        .padding(.bottom, dimensions.spacing.space48)
    }
}
