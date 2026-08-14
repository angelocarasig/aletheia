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

    @State private var composer: DetailsComposer?
    @State private var reading: DetailsComposer.Chapters.Target?
    @State private var showingCovers = false
    @State private var showingSourceOrder = false
    @State private var showingScanlatorOrder = false
    @State private var showingLanguageOrder = false
    @State private var showingTitles = false
    @State private var searchingAll = false
    @State private var showingEdit = false
    @State private var showingMerge = false
    @State private var showingCollections = false
    @State private var showingSetup = false
    @State private var removing: DetailsComposer.Sources.Origin?
    // which service the reader is picking an entry for, and which link they
    // opened. both are the sheet's subject rather than a bare boolean
    @State private var linking: Tracker?
    @State private var managing: DetailsComposer.Tracking.Link?
    @State private var showingTracking = false
    @State private var marking: DetailsComposer.Chapters.Request?
    @State private var markCommitted: UUID?
    @State private var showingDisambiguation = false
    // written here, read only inside the backdrop - reading it in this body
    // would re-evaluate the whole chapter list on every scroll step
    @State private var scroll = DetailsScroll()

    // the branch selector and the animation key are the same value on purpose -
    // keying a correlated boolean is how swaps go dead or partial.
    // see docs/features/loading-transitions.md
    private var phase: LoadPhase {
        if composer?.ready == true { .content }
        else if composer?.failure != nil { .failed }
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
                if let composer {
                    Loaded(composer)
                        .transition(.opacity)
                }
            case .failed:
                if let composer, let failure = composer.failure {
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
            SearchScreen(query: composer?.series.title ?? "", embedded: true)
        }
        // a sheet rather than a push: connecting is an errand off the side of
        // this series, not a place inside it - and dismissing lands back on the
        // section with its rows already filled in. a push from here would bury
        // the series one level down behind an account list
        .sheet(isPresented: $showingTracking) {
            NavigationStack {
                TrackingScreen()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // keyed on the service being linked, so the sheet always knows which of
        // the two it is picking for
        .sheet(item: $linking) { tracker in
            if let composer {
                TrackerLink(tracker, composer, onFinish: { linking = nil })
            }
        }
        // the same screen a search result opens, reached from the other side:
        // already linked, so its commit saves rather than links and it carries
        // unlink. one screen rather than a manage sheet that would be this one
        // with three controls removed
        .sheet(item: $managing) { link in
            if let composer {
                TrackerManage(link, composer, onFinish: { managing = nil })
            }
        }
        .sheet(isPresented: $showingDisambiguation) {
            if let composer {
                DetailsDisambiguation(
                    candidates: composer.identity.candidates,
                    onAttach: { id in
                        showingDisambiguation = false
                        Task { await composer.attach(to: id) }
                    },
                    onKeepSeparate: {
                        showingDisambiguation = false
                        Task { await composer.separate() }
                    },
                    // there is no series to fall back to, so backing out of the
                    // choice leaves the screen with nothing to show
                    onCancel: {
                        showingDisambiguation = false
                        composer.cancel()
                        dismiss()
                    }
                )
                .interactiveDismissDisabled()
            }
        }
        .onChange(of: composer?.identity.isAmbiguous ?? false) { _, needs in
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
                Task { await composer?.sources.remove(id) }
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
            if let composer {
                let library = composer.library

                // the picker presents its own create form, so dismissing the
                // form returns to the list with the new collection already joined
                Busy(saving: library.saving) { busy in
                    CollectionPicker(
                        collections: library.collections,
                        isSaving: busy,
                        onToggle: { id in Task { await library.toggle(collection: id) } },
                        onCreate: { name, description in
                            Task {
                                await library.create(
                                    collection: name,
                                    description: description,
                                    joining: true
                                )
                            }
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $showingSetup) {
            if let composer {
                let library = composer.library
                let tracking = composer.tracking

                DetailsSetup(
                    title: composer.series.title,
                    status: library.status,
                    collections: library.collections,
                    isSaving: library.saving,
                    accounts: tracking.accounts,
                    links: tracking.links,
                    localProgress: tracking.furthest,
                    needingSignIn: tracking.needingSignIn,
                    syncing: tracking.syncing,
                    onSetStatus: { status in Task { await library.set(status: status) } },
                    onToggleCollection: { id in Task { await library.toggle(collection: id) } },
                    onCreateCollection: { name, description in
                        Task {
                            await library.create(
                                collection: name,
                                description: description,
                                joining: true
                            )
                        }
                    },
                    // the same routing the section below uses - a service with
                    // no link searches for one, a linked service opens what it
                    // has. presented from inside the flow rather than beside it,
                    // because a second sheet on this view would not open over
                    // the first one
                    // reconciliation is off in here: see DetailsTrackerCandidate
                    linkSheet: { tracker, opening, close in
                        if opening, let link = tracking.links.first(where: { $0.tracker == tracker }) {
                            TrackerManage(link, composer, reconciles: false, onFinish: close)
                        } else {
                            TrackerLink(tracker, composer, reconciles: false, onFinish: close)
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $showingMerge) {
            if let composer {
                let series = composer.series

                DetailsMerge(
                    source: .init(
                        title: series.title,
                        authors: series.authors.joined(separator: ", "),
                        synopsis: series.synopsis.map { String($0.characters) },
                        cover: series.cover,
                        referer: series.referer,
                        status: composer.library.status,
                        publication: series.publication,
                        origins: composer.sources.origins.count,
                        read: series.readCount,
                        total: series.totalCount
                    ),
                    candidates: composer.identity.matches,
                    isLoading: composer.identity.isSearching,
                    onSearch: { query in
                        guard let id = composer.seriesId else { return }
                        await composer.identity.search(query, for: id)
                    },
                    onMerge: { id in
                        showingMerge = false
                        Task { await composer.merge(into: id) }
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let composer {
                let series = composer.series

                Busy(saving: series.saving) { busy in
                    DetailsEdit(
                        titles: series.titles,
                        synopses: series.synopses,
                        metadata: series.choices,
                        isSaving: busy,
                        onSetTitle: { id in Task { await series.prefer(title: id) } },
                        onSetSynopsis: { id in Task { await series.prefer(synopsis: id) } },
                        onSetClassification: { id in Task { await series.prefer(classification: id) } },
                        onSetPublication: { id in Task { await series.prefer(publication: id) } }
                    )
                }
            }
        }
        .sheet(isPresented: $showingTitles) {
            if let composer {
                let series = composer.series

                Busy(saving: series.saving) { busy in
                    DetailsTitles(
                        titles: series.titles,
                        isSaving: busy,
                        onSetPreferred: { id in Task { await series.prefer(title: id) } }
                    )
                }
            }
        }
        // the same sheet DetailsSources presents. reordering is what decides
        // which source's copy of a chapter wins, so it belongs to both sections
        .sheet(isPresented: $showingSourceOrder) {
            if let composer {
                OriginOrder(
                    origins: composer.sources.origins,
                    onCommit: { ids in Task { await composer.sources.reorder(ids) } }
                )
            }
        }
        .sheet(isPresented: $showingScanlatorOrder) {
            if let composer {
                let sources = composer.sources

                ScanlatorOrder(
                    groups: sources.scanlatorOrder,
                    isLoading: sources.isLoadingScanlators,
                    onCommit: { origin, ids in
                        Task { await sources.reorder(scanlators: ids, in: origin) }
                    }
                )
                // read on present: this needs every scanlator, including ones
                // that currently win nothing, which the screen's list does not have
                .task { await sources.scanlators() }
            }
        }
        .sheet(isPresented: $showingLanguageOrder) {
            if let composer {
                let sources = composer.sources

                LanguageOrder(
                    languages: sources.languageOrder,
                    isLoading: sources.isLoadingLanguages,
                    onCommit: { codes in Task { await sources.reorder(languages: codes) } }
                )
                .task { await sources.languages() }
            }
        }
        .sheet(isPresented: $showingCovers) {
            if let composer {
                let series = composer.series

                Busy(saving: series.saving) { busy in
                    DetailsCovers(
                        covers: series.covers,
                        referer: series.referer,
                        isSaving: busy,
                        onSetPreferred: { id in Task { await series.prefer(cover: id) } }
                    )
                }
            }
        }
        .task {
            guard composer == nil else { return }

            let composer = DetailsComposer(
                entry: entry,
                registry: compositor.registry,
                assets: compositor.assets,
                refresher: compositor.refresh,
                trackers: compositor.trackers,
                database: database
            )
            self.composer = composer
            await composer.load()
        }
    }

    // MARK: Tracking sheets

    // both are built in two places now - beside the section, and inside the
    // add-to-library flow - so the construction lives once and the presenter
    // hands in how to close, since the two contexts are driven by different state
    @ViewBuilder
    private func TrackerLink(
        _ tracker: Tracker,
        _ composer: DetailsComposer,
        reconciles: Bool = true,
        onFinish: @escaping () -> Void
    ) -> some View {
        let tracking = composer.tracking
        let adult = composer.series.classification == .Explicit

        DetailsTrackerLink(
            tracker: tracker,
            seriesTitle: composer.series.title,
            existing: tracking.links.first { $0.tracker == tracker },
            adult: adult,
            localProgress: tracking.furthest,
            scoreFormat: tracking.format(for: tracker),
            onSearch: { query in
                try await tracking.search(tracker, query: query, adult: adult)
            },
            onLoadEntry: { id in try await tracking.entry(tracker, remoteId: id) },
            onCatchUp: { progress in Task { await composer.catchUp(to: progress) } },
            onPushLocal: { Task { await tracking.push() } },
            onConflicts: { await tracking.conflicts(tracker) },
            onResolve: { text in await tracking.resolve(text, on: tracker) },
            onCommit: { candidate, update in
                try await tracking.link(
                    candidate,
                    on: tracker,
                    update: update,
                    status: composer.library.status
                )
            },
            onUnlink: { removeRemote in
                onFinish()
                // resolved at tap time rather than captured: the link did not
                // exist when this sheet was built
                guard let link = tracking.links.first(where: { $0.tracker == tracker }) else { return }
                Task { await tracking.unlink(link, removeRemote: removeRemote) }
            },
            onCancel: onFinish,
            reconciles: reconciles
        )
    }

    @ViewBuilder
    private func TrackerManage(
        _ link: DetailsComposer.Tracking.Link,
        _ composer: DetailsComposer,
        reconciles: Bool = true,
        onFinish: @escaping () -> Void
    ) -> some View {
        let tracking = composer.tracking

        NavigationStack {
            DetailsTrackerCandidate(
                tracker: link.tracker,
                candidate: .init(
                    id: link.remoteId,
                    title: link.remoteTitle,
                    totalChapters: link.total
                ),
                localProgress: tracking.furthest,
                conflict: nil,
                scoreFormat: link.scoreFormat,
                linked: true,
                reconciles: reconciles,
                syncedDate: link.syncedDate,
                onLoad: { try await tracking.entry(link.tracker, remoteId: link.remoteId) },
                onCommit: { _, update in try await tracking.edit(link, update: update) },
                onUnlink: { removeRemote in
                    onFinish()
                    Task { await tracking.unlink(link, removeRemote: removeRemote) }
                },
                onCatchUp: { progress in Task { await composer.catchUp(to: progress) } },
                onPushLocal: { Task { await tracking.push() } },
                onClose: onFinish
            )
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Content

    @ViewBuilder
    private func Loaded(_ composer: DetailsComposer) -> some View {
        DetailsBackdrop(cover: composer.series.cover, referer: composer.series.referer, scroll: scroll)
            .transition(.opacity)

        ScrollView(.vertical, showsIndicators: false) {
            DetailsContent(composer: composer, actions: actions(composer))
        }
        .transition(.opacity)
        // clamped inside the transform, not after: the callback only
        // fires when its value changes, so clamping stops it entirely
        // past the ramp rather than firing for another 149,000 points of
        // chapter list. rounding bounds the ramp itself to a few updates
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            let scrolled = geometry.contentOffset.y + geometry.contentInsets.top
            let ramped = min(max(scrolled, 0), DetailsBackdrop.blurDistance)
            return (ramped / DetailsBackdrop.blurStep).rounded() * DetailsBackdrop.blurStep
        } action: { _, offset in
            scroll.offset = offset
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .refreshable { await composer.refresh() }
        // floats over the content rather than displacing it - a refresh runs over
        // a list that already renders, so nothing below should move
        .overlay(alignment: .bottomTrailing) {
            if composer.refresh.state != .idle {
                DetailsRefreshPill(
                    outcomes: composer.refresh.state.outcomes,
                    refresher: compositor.refresh
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if case let rebuilt = live(composer), !rebuilt.isEmpty {
                // a fetch this screen no longer remembers starting, or a library
                // run holding this series. pulling to refresh here would join
                // those fetches rather than start a second set
                DetailsRefreshPill(outcomes: rebuilt, refresher: compositor.refresh)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        // an inset rather than an overlay: this one is permanent, and a bar that
        // permanently covers the last chapter row is a bar that hides the thing
        // it is about
        .safeAreaInset(edge: .bottom) {
            DetailsContinue(chapters: composer.chapters.chapters) { chapter in
                open(chapter, in: composer)
            }
            .padding(.horizontal, dimensions.screenMargin)
            // lifted off the safe area edge so it reads as floating over the
            // list rather than sitting on the bottom of the screen
            .padding(.bottom, dimensions.spacing.space8)
        }
        .animation(.settle, value: composer.refresh.state)
        // the other thing the overlay switches on, or the shared-unit pill would
        // appear and leave without a transition
        .animation(.settle, value: live(composer))
    }

    private func actions(_ composer: DetailsComposer) -> DetailsContent.Actions {
        DetailsContent.Actions(
            openCovers: { showingCovers = true },
            openTitles: { showingTitles = true },
            searchAll: { searchingAll = true },
            openCollections: { showingCollections = true },
            openSetup: { showingSetup = $0 },
            openEdit: { showingEdit = true },
            openMerge: { showingMerge = true },
            openSourceOrder: { showingSourceOrder = true },
            openScanlatorOrder: { showingScanlatorOrder = true },
            openLanguageOrder: { showingLanguageOrder = true },
            confirmRemove: { removing = $0 },
            link: { linking = $0 },
            manage: { managing = $0 },
            connect: { showingTracking = true },
            catchUp: { progress in Task { await composer.catchUp(to: progress) } },
            mark: { read, numbers in requestMark(composer, read: read, numbers: numbers) },
            read: { chapter in open(chapter, in: composer) }
        )
    }

    private func open(_ chapter: DetailsComposer.Chapters.Row, in composer: DetailsComposer) {
        guard let target = composer.chapters.read(chapter) else { return }
        Task { await composer.chapters.open(chapter) }
        reading = target
    }

    // rebuilt from the shared unit rather than remembered, which is what lets
    // the pill come back after the screen was closed and reopened mid-fetch.
    // only origins still in play appear: an origin that finished while the
    // screen was gone took its count with the last composer, and inventing a
    // row for it would be inventing the answer too
    private func live(_ composer: DetailsComposer) -> [DetailsComposer.Refresh.Outcome] {
        let refresh = compositor.refresh
        let waiting = composer.seriesId.map {
            refresh.isQueued(series: $0.rawValue) || refresh.isChecking(series: $0.rawValue)
        } ?? false

        return composer.refresh.origins.compactMap { target in
            guard refresh.isChecking(origin: target.id) || waiting else { return nil }
            return .init(id: target.id, name: target.name, icon: target.icon, result: nil)
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
                    Task { await composer?.load() }
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
    private func requestMark(_ composer: DetailsComposer, read: Bool, numbers: [Double]) {
        if let request = composer.chapters.request(read: read, numbers: numbers) {
            marking = request
        } else {
            Task { await composer.chapters.mark(read: read, numbers: numbers) }
        }
    }

    private func commit(_ request: DetailsComposer.Chapters.Request) {
        marking = nil
        markCommitted = request.id
        Task { await composer?.chapters.mark(read: request.read, numbers: request.numbers) }
    }
}
