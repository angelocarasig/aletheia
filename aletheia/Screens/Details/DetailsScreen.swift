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
    @State private var showingSourceOrder = false
    @State private var showingScanlatorOrder = false
    @State private var showingLanguageOrder = false
    @State private var showingTitles = false
    @State private var searchingAll = false
    @State private var showingEdit = false
    @State private var showingMerge = false
    @State private var showingCollection = false
    @State private var showingCollections = false
    @State private var removing: DetailsSources.Origin?
    @State private var showingDisambiguation = false
    // written here, read only inside the backdrop - reading it in this body
    // would re-evaluate the whole chapter list on every scroll step
    @State private var scroll = DetailsScroll()

    private enum Layout {
        // the source badge inside the refresh pill - sized to the pill's text
        // line, not to the 44pt row icon it is cropped from
        static let badgeSize: CGFloat = 20
    }

    // the branch selector and the animation key are the same value on purpose -
    // keying a correlated boolean is how swaps go dead or partial.
    // see docs/features/loading-transitions.md
    private var phase: LoadPhase {
        if vm?.isReady == true { .content }
        else if vm?.failure != nil { .failed }
        else { .pending }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // outside the branch so the skeleton sits on it too - it was
            // rendering against the system background before
            Palette.canvas
                .ignoresSafeArea()

            switch phase {
            case .content:
                if let vm {
                    Loaded(vm)
                        .transition(.opacity)
                }
            case .failed:
                if let vm, let failure = vm.failure {
                    Unavailable(failure)
                        .transition(.opacity)
                }
            default:
                DetailsSkeleton()
                    .transition(.opacity)
            }
        }
        .animation(.settle, value: phase)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $reading) { target in
            ReaderScreen(
                seriesId: target.seriesId,
                chapterId: target.chapterId
            )
        }
        .navigationDestination(isPresented: $searchingAll) {
            SearchScreen(query: vm?.title ?? "", embedded: true)
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
        // an action the reader took that did not happen. the content behind it is
        // still valid, so this is raised and dismissed rather than replacing the
        // screen the way `failure` does
        .alert(
            vm?.actionFailure?.title ?? "",
            isPresented: Binding(
                get: { vm?.actionFailure != nil },
                set: { if !$0 { vm?.clearActionFailure() } }
            )
        ) {
            Button("OK", role: .cancel) { vm?.clearActionFailure() }
        } message: {
            Text(vm?.actionFailure?.message ?? "")
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
                // the picker presents its own create form, so dismissing the
                // form returns to the list with the new collection already joined
                CollectionPicker(
                    collections: vm.availableCollections,
                    isSaving: vm.isSaving,
                    onToggle: { id in Task { await vm.toggleCollection(id) } },
                    onCreate: { name, description in
                        Task { await vm.createCollection(name: name, description: description) }
                    }
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
        .sheet(isPresented: $showingMerge) {
            if let vm {
                DetailsMerge(
                    source: .init(
                        title: vm.title,
                        authors: vm.authors.joined(separator: ", "),
                        synopsis: vm.synopsis.map { String($0.characters) },
                        cover: vm.cover,
                        referer: vm.referer,
                        status: vm.status,
                        publication: vm.publication,
                        origins: vm.origins.count,
                        read: vm.readCount,
                        total: vm.chapters.count
                    ),
                    candidates: vm.mergeCandidates,
                    isLoading: vm.isLoadingMergeCandidates,
                    onSearch: { query in await vm.loadMergeCandidates(query: query) },
                    onMerge: { id in
                        showingMerge = false
                        Task { await vm.merge(into: id) }
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
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
        // the same sheet DetailsSources presents. reordering is what decides
        // which source's copy of a chapter wins, so it belongs to both sections
        .sheet(isPresented: $showingSourceOrder) {
            if let vm {
                OriginOrder(
                    origins: vm.origins,
                    onCommit: { ids in Task { await vm.reorderOrigins(ids) } }
                )
            }
        }
        .sheet(isPresented: $showingScanlatorOrder) {
            if let vm {
                ScanlatorOrder(
                    groups: vm.scanlatorGroups,
                    isLoading: vm.isLoadingScanlators,
                    onCommit: { origin, ids in
                        Task { await vm.reorderScanlators(origin, ids) }
                    }
                )
                // read on present: this needs every scanlator, including ones
                // that currently win nothing, which the screen's list does not have
                .task { await vm.loadScanlators() }
            }
        }
        .sheet(isPresented: $showingLanguageOrder) {
            if let vm {
                LanguageOrder(
                    languages: vm.languageOrder,
                    isLoading: vm.isLoadingLanguages,
                    onCommit: { codes in Task { await vm.reorderLanguages(codes) } }
                )
                .task { await vm.loadLanguages() }
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
        // an inset rather than an overlay: this one is permanent, and a bar that
        // permanently covers the last chapter row is a bar that hides the thing
        // it is about
        .safeAreaInset(edge: .bottom) {
            DetailsContinue(chapters: vm.chapters) { chapter in
                guard let target = vm.read(chapter) else { return }
                Task { await vm.open(chapter) }
                reading = target
            }
            .padding(.horizontal, dimensions.screenMargin)
            // lifted off the safe area edge so it reads as floating over the
            // list rather than sitting on the bottom of the screen
            .padding(.bottom, dimensions.spacing.space8)
        }
        .animation(.settle, value: vm.refreshState)
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
        case .checking(let icon):
            ProgressView()
                .controlSize(.small)

            if let icon {
                Image(icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Layout.badgeSize, height: Layout.badgeSize)
                    .clipShape(.rect(cornerRadius: dimensions.radius.radius4))
            }

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
        // a badged check is an origin freshly attached, whose whole list is
        // being fetched - "checking" would undersell what is happening
        case .checking(let icon):
            if icon == nil {
                Text("Checking for chapters")
            } else {
                Text("Loading chapters")
            }
        case .added(let count): Text("^[\(count) new chapter](inflect: true)")
        case .unchanged: Text("No new chapters")
        case .failed: Text("Couldn't refresh")
        case .idle: EmptyView()
        }
    }

    @ViewBuilder
    private func Unavailable(_ failure: Failure) -> some View {
        // the rows may well be in the database - what is missing is any installed
        // source that can fetch this series or read a page from it
        ContentUnavailableView {
            Label(
                failure.title,
                systemImage: failure.isRetryable ? "exclamationmark.triangle" : "questionmark.circle"
            )
        } description: {
            Text(failure.message)
        } actions: {
            if failure.isRetryable {
                Button("Try Again") {
                    Task { await vm?.load() }
                }
            }
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
                onOpenTitles: { showingTitles = true },
                onSearchAll: { searchingAll = true }
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
                onEditDetails: { showingEdit = true },
                onMerge: { showingMerge = true }
            )

            // emptiness is decided at mapping - an empty synopsis arrives as nil
            if let synopsis = vm.synopsis {
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
                sourceCount: vm.origins.count,
                showAllChapters: vm.showAllChapters,
                showHalfChapters: vm.showHalfChapters,
                onShowAllChapters: { on in Task { await vm.setShowAllChapters(on) } },
                onShowHalfChapters: { on in Task { await vm.setShowHalfChapters(on) } },
                onSources: { showingSourceOrder = true },
                onScanlators: { showingScanlatorOrder = true },
                onLanguages: { showingLanguageOrder = true },
                onMark: { read, numbers in Task { await vm.mark(read: read, numbers: numbers) } }
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
