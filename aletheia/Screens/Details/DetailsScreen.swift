//
//  DetailsScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI
import Tagged

struct DetailsScreen: View {
    let entry: SeriesEntry

    @Environment(\.database) private var database
    @Environment(\.dimensions) private var dimensions
    @Environment(\.compositor) private var compositor
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
    @State private var marking: DetailsViewModel.MarkRequest?
    @State private var markCommitted: UUID?
    @State private var showingDisambiguation = false
    // written here, read only inside the backdrop - reading it in this body
    // would re-evaluate the whole chapter list on every scroll step
    @State private var scroll = DetailsScroll()

    private enum Layout {
        // the source badge inside the refresh pill - sized to the pill's text
        // line, not to the 44pt row icon it is cropped from
        static let badgeSize: CGFloat = 20
        // wide enough for a source name beside a failure sentence, narrow enough
        // that the pill never spans the screen it floats over
        static let pillWidth: CGFloat = 320
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
        .alert(
            markTitle,
            isPresented: Binding(get: { marking != nil }, set: { if !$0 { marking = nil } })
        ) {
            if let request = marking {
                if request.read {
                    Button("Mark as Read", role: .destructive) { commit(request) }
                } else {
                    Button("Mark as Unread", role: .destructive) { commit(request) }
                }
            }
            Button("Cancel", role: .cancel) { marking = nil }
        } message: {
            // silent when nothing is lost - a zero here would be a sentence
            // saying the action is free, which is not what the reader is being
            // asked to confirm
            if let request = marking, request.affected > 0 {
                if request.read {
                    Text("\(request.affected) \(request.affected == 1 ? "chapter" : "chapters") you're partway through will be marked finished, losing your page position.")
                } else {
                    Text("This clears your reading progress on \(request.affected) of them. This can't be undone.")
                }
            }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: markCommitted)
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
                refresher: compositor.refresh,
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
                Refreshing(vm.refreshState.outcomes)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if case let rebuilt = live(vm), !rebuilt.isEmpty {
                // a fetch this screen no longer remembers starting, or a library
                // run holding this series. pulling to refresh here would join
                // those fetches rather than start a second set
                Refreshing(rebuilt)
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
        // the other thing the overlay switches on, or the shared-unit pill would
        // appear and leave without a transition
        .animation(.settle, value: live(vm))
    }

    // rebuilt from the shared unit rather than remembered, which is what lets
    // the pill come back after the screen was closed and reopened mid-fetch.
    // only origins still in play appear: an origin that finished while the
    // screen was gone took its count with the last view model, and inventing a
    // row for it would be inventing the answer too
    private func live(_ vm: DetailsViewModel) -> [DetailsViewModel.RefreshState.Outcome] {
        let refresh = compositor.refresh
        let waiting = vm.seriesId.map {
            refresh.isQueued(series: $0.rawValue) || refresh.isChecking(series: $0.rawValue)
        } ?? false

        return vm.refreshables.compactMap { target in
            guard refresh.isChecking(origin: target.originId) || waiting else { return nil }
            return .init(id: target.originId, name: target.name, icon: target.icon, result: nil)
        }
    }

    // one row per source, each answering for itself: a spinner becomes that
    // source's outcome in place, so a dead source is named rather than collapsing
    // the whole run into "couldn't refresh". a single-origin series is one row
    private func Refreshing(_ outcomes: [DetailsViewModel.RefreshState.Outcome]) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            ForEach(outcomes) { outcome in
                Outcome(outcome)
            }
        }
        .padding(.horizontal, dimensions.spacing.space16)
        .padding(.vertical, dimensions.spacing.space12)
        .frame(maxWidth: Layout.pillWidth, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: dimensions.radius.radius16))
        .padding(dimensions.screenMargin)
    }

    private func Outcome(_ outcome: DetailsViewModel.RefreshState.Outcome) -> some View {
        // no answer yet is two different things: waiting for a slot at the host,
        // or actually talking to it. the unit knows which, and a row that says
        // "checking" while nothing is in flight is the small lie that makes a
        // slow refresh look broken
        let started = compositor.refresh.isChecking(origin: outcome.id)

        return HStack(spacing: dimensions.spacing.space8) {
            Icon(outcome, started: started)

            Text(outcome.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)

            Message(outcome.result, started: started)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // every state is a symbol, spinner included, so the outcome can enter by
    // drawing itself along the stroke the spinner drew off - the reader's
    // separator badge speaks the same dialect
    private func Icon(_ outcome: DetailsViewModel.RefreshState.Outcome, started: Bool) -> some View {
        Group {
            switch outcome.result {
            // waiting for a slot is not the same as talking to the host, and a
            // spinner for something that has not begun is the small lie that
            // makes a slow refresh look stuck
            case nil where !started:
                Image(systemName: "clock")
                    .foregroundStyle(.muted)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))

            case nil:
                Image(systemName: "progress.indicator")
                    .foregroundStyle(.secondary)
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: !reduceMotion)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))

            case .added:
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.success)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))

            // the inverse of the plus beside it, so the row reads as one
            // vocabulary: added, nothing added, failed. not a tick - that reads
            // as an achievement the source did not earn
            case .unchanged:
                Image(systemName: "minus.circle")
                    .foregroundStyle(.muted)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))

            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.warning)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))

            // stopped, not broken - the same muted weight as "nothing new",
            // because neither is something the reader has to act on
            case .cancelled:
                Image(systemName: "xmark.circle")
                    .foregroundStyle(.muted)
                    .transition(reduceMotion ? .opacity : AnyTransition(.symbolEffect(.drawOn)))
            }
        }
        .frame(width: Layout.badgeSize, height: Layout.badgeSize)
        .animation(.settle, value: outcome.result)
        .animation(.settle, value: started)
    }

    @ViewBuilder
    private func Message(_ result: OriginRefresher.Outcome?, started: Bool) -> some View {
        switch result {
        case nil: Text(started ? "Checking" : "Queued")
        case .added(let count): Text("^[\(count) new chapter](inflect: true)")
        case .unchanged: Text("Up to date")
        case .failed(let reason): Text(reason)
        case .cancelled: Text("Stopped")
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

    private var markTitle: String {
        let count = marking?.scope ?? 0
        let noun = count == 1 ? "chapter" : "chapters"
        if marking?.read == true {
            return "Mark \(count) \(noun) as read?"
        } else {
            return "Mark \(count) \(noun) as unread?"
        }
    }

    // one chapter is a common, visible, self-explaining change and goes straight
    // through; anything wider asks first
    private func requestMark(_ vm: DetailsViewModel, read: Bool, numbers: [Double]) {
        if let request = vm.markRequest(read: read, numbers: numbers) {
            marking = request
        } else {
            Task { await vm.mark(read: read, numbers: numbers) }
        }
    }

    private func commit(_ request: DetailsViewModel.MarkRequest) {
        marking = nil
        markCommitted = request.id
        Task { await vm?.mark(read: request.read, numbers: request.numbers) }
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
                onMarkAll: { read in requestMark(vm, read: read, numbers: vm.chapters.map(\.number)) },
                onEditDetails: { showingEdit = true },
                onMerge: { showingMerge = true }
            )

            // emptiness is decided at mapping - an empty synopsis arrives as nil
            DetailsSynopsis(synopsis: vm.synopsis)

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
                onMark: { read, numbers in requestMark(vm, read: read, numbers: numbers) }
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
