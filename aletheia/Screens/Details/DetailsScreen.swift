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
    @Environment(\.dismiss) private var dismiss

    @State private var vm: DetailsViewModel?
    @State private var reading: DetailsViewModel.ReaderTarget?
    @State private var showingCovers = false
    @State private var showingTitles = false
    @State private var showingEdit = false
    @State private var showingCollection = false
    @State private var showingCollections = false
    @State private var removing: DetailsSources.Origin?
    @State private var showingDisambiguation = false
    // written here, read only inside the backdrop - reading it in this body
    // would re-evaluate the whole chapter list on every scroll step
    @State private var scroll = DetailsScroll()

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
                Loaded(vm)
            } else if let vm, let failure = vm.failure {
                Unavailable(failure)
                    .transition(.opacity)
            } else {
                DetailsSkeleton()
                    .transition(.opacity)
            }
        }
        .animation(Layout.settle, value: vm?.isReady ?? false)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $reading) { target in
            ReaderScreen(
                seriesId: target.seriesId,
                chapterId: target.chapterId
            )
        }
        .sheet(isPresented: $showingDisambiguation) {
            if let vm {
                DetailsDisambiguation(
                    candidates: vm.candidates,
                    onAttach: { id in
                        showingDisambiguation = false
                        Task { await vm.attach(to: id) }
                    },
                    onKeepSeparate: {
                        showingDisambiguation = false
                        Task { await vm.keepSeparate() }
                    },
                    // there is no series to fall back to, so backing out of the
                    // choice leaves the screen with nothing to show
                    onCancel: {
                        showingDisambiguation = false
                        vm.cancel()
                        dismiss()
                    }
                )
                .interactiveDismissDisabled()
            }
        }
        .onChange(of: vm?.needsDisambiguation ?? false) { _, needs in
            showingDisambiguation = needs
        }
        .confirmationDialog(
            "Remove \(removing?.name ?? "this source")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove Source", role: .destructive) {
                guard let id = removing?.id else { return }
                removing = nil
                Task { await vm?.removeOrigin(id) }
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: {
            Text("Its chapters are removed with it. Your reading progress on chapters from other sources is kept.")
        }
        .sheet(isPresented: $showingCollections) {
            if let vm {
                CollectionPicker(
                    collections: vm.availableCollections,
                    isSaving: vm.isSaving,
                    onToggle: { id in Task { await vm.toggleCollection(id) } },
                    // stacked over the picker, so dismissing the form returns to
                    // the list with the new collection already joined
                    onCreate: { showingCollection = true }
                )
            }
        }
        .sheet(isPresented: $showingCollection) {
            if let vm {
                CollectionForm(isSaving: vm.isSaving) { name, description in
                    Task { await vm.createCollection(name: name, description: description) }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let vm {
                DetailsEdit(
                    titles: vm.titles,
                    synopses: vm.synopses,
                    metadata: vm.metadataChoices,
                    isSaving: vm.isSaving,
                    onSetTitle: { id in Task { await vm.setPreferredTitle(id) } },
                    onSetSynopsis: { id in Task { await vm.setPreferredSynopsis(id) } },
                    onSetMetadata: { id in Task { await vm.setPreferredMetadata(id) } }
                )
            }
        }
        .sheet(isPresented: $showingTitles) {
            if let vm {
                DetailsTitles(
                    titles: vm.titles,
                    isSaving: vm.isSaving,
                    onSetPreferred: { id in Task { await vm.setPreferredTitle(id) } }
                )
            }
        }
        .sheet(isPresented: $showingCovers) {
            if let vm {
                DetailsCovers(
                    covers: vm.covers,
                    referer: vm.referer,
                    isSaving: vm.isSaving,
                    onSetPreferred: { id in Task { await vm.setPreferredCover(id) } }
                )
            }
        }
        .task {
            guard vm == nil else { return }

            let vm = DetailsViewModel(
                entry: entry,
                registry: compositor.registry,
                assets: compositor.assets,
                database: database
            )
            self.vm = vm
            await vm.load()
        }
    }

    private var sourceName: String {
        guard case .source(let slug, _) = entry else { return "" }
        return compositor.registry.source(slug: slug)?.descriptor.name ?? slug
    }

    @ViewBuilder
    private func Loaded(_ vm: DetailsViewModel) -> some View {
        DetailsBackdrop(cover: vm.cover, referer: vm.referer, scroll: scroll)
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
        .refreshable { await vm.refresh() }
        // floats over the content rather than displacing it - a refresh runs over
        // a list that already renders, so nothing below should move
        .overlay(alignment: .bottomTrailing) {
            if vm.refreshState != .idle {
                Refreshing(vm.refreshState)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(Layout.settle, value: vm.refreshState)
    }

    // one pill for the whole sequence: the spinner becomes the outcome in place,
    // and the capsule grows to whatever the answer needs
    private func Refreshing(_ state: DetailsViewModel.RefreshState) -> some View {
        HStack(spacing: dimensions.spacing.space8) {
            Icon(state)
            Message(state)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, dimensions.spacing.space16)
        .padding(.vertical, dimensions.spacing.space12)
        .glassEffect(.regular, in: .capsule)
        .padding(dimensions.screenMargin)
    }

    @ViewBuilder
    private func Icon(_ state: DetailsViewModel.RefreshState) -> some View {
        switch state {
        case .checking:
            ProgressView()
                .controlSize(.small)

        case .added:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.success)

        case .unchanged:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.muted)

        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.warning)

        case .idle:
            EmptyView()
        }
    }

    @ViewBuilder
    private func Message(_ state: DetailsViewModel.RefreshState) -> some View {
        switch state {
        case .checking: Text("Checking for chapters")
        case .added(let count): Text("^[\(count) new chapter](inflect: true)")
        case .unchanged: Text("No new chapters")
        case .failed: Text("Couldn't refresh")
        case .idle: EmptyView()
        }
    }

    @ViewBuilder
    private func Unavailable(_ failure: DetailsViewModel.Failure) -> some View {
        switch failure {
        case .unavailable:
            // the rows may well be in the database, but no installed source can
            // fetch this series or read a page from it
            ContentUnavailableView(
                "Source Unavailable",
                systemImage: "questionmark.circle",
                description: Text("No installed source can open this series")
            )

        case .fetch(let message):
            ContentUnavailableView(
                "Couldn't Load Series",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
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
                referer: vm.referer,
                title: vm.title,
                authors: vm.authors,
                onOpenCovers: { showingCovers = true },
                onOpenTitles: { showingTitles = true }
            )

            DetailsActions(
                inLibrary: vm.inLibrary,
                isSaving: vm.isSaving,
                canToggle: vm.canToggleLibrary,
                canRefresh: vm.canRefresh,
                status: vm.status,
                onToggleLibrary: { Task { await vm.toggleLibrary() } },
                onSetStatus: { status in Task { await vm.setStatus(status) } },
                onRefreshChapters: { Task { await vm.refreshChapters() } },
                onMarkAll: { read in Task { await vm.markAll(read: read) } },
                onEditDetails: { showingEdit = true }
            )

            if let synopsis = vm.synopsis, !synopsis.isEmpty {
                DetailsSynopsis(synopsis: synopsis)
            }

            if !vm.tags.isEmpty {
                DetailsTags(tags: vm.tags)
            }

            if !vm.origins.isEmpty {
                DetailsSources(
                    origins: vm.origins,
                    onSetPrimary: { id in Task { await vm.setPrimary(id) } },
                    onReorder: { ids in Task { await vm.reorderOrigins(ids) } },
                    // its chapters go with it, so this one asks first
                    onRemove: { id in removing = vm.origins.first { $0.id == id } }
                )
            }

            DetailsCollections(
                collections: vm.collections,
                hasAny: !vm.availableCollections.isEmpty,
                onToggle: { id in Task { await vm.toggleCollection(id) } },
                onPick: { showingCollections = true },
                onCreate: { showingCollection = true }
            )

            DetailsMetadata(
                classification: vm.classification,
                publication: vm.publication,
                readCount: vm.readCount,
                totalCount: vm.chapters.count,
                lastFetchedDate: vm.lastMetadataFetch,
                lastReadDate: vm.lastReadDate
            )

            DetailsChapters(
                chapters: vm.chapters,
                isFetching: vm.isFetchingChapters,
                hasFetched: vm.hasFetchedChapters,
                canRefresh: vm.canRefresh,
                onRefresh: { Task { await vm.refreshChapters() } },
                onMarkAll: { read in Task { await vm.markAll(read: read) } }
            ) { chapter in
                guard let target = vm.read(chapter) else { return }
                Task { await vm.open(chapter) }
                reading = target
            }
        }
        .padding(.horizontal, dimensions.spacing.space8)
        .padding(.bottom, dimensions.spacing.space48)
    }
}
