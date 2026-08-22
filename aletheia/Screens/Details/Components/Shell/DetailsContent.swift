//
//  DetailsContent.swift
//  aletheia
//
//  Created by Angelo Carasig on 12/8/26.
//

import SwiftUI
import Tagged

// each section is a separate View type, not a builder function - a function
// is pasted into its caller and everything it reads becomes the caller's
// dependency, so a chapter finishing would redraw the whole scroll content
struct DetailsContent: View {
    let composer: DetailsComposer
    let actions: Actions

    @Environment(\.dimensions) private var dimensions

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space20) {
            Spacer()
                .frame(height: DetailsBackdrop.heroHeight)

            HeaderSection(series: composer.series, actions: actions)
            ActionsSection(composer: composer, actions: actions)
            SynopsisSection(series: composer.series)
            TagsSection(series: composer.series)
            TrackingSection(
                tracking: composer.tracking, library: composer.library, actions: actions)
            SourcesSection(sources: composer.sources, refresh: composer.refresh, actions: actions)
            MetadataSection(series: composer.series)
            ChaptersSection(composer: composer, actions: actions)
            RecommendationsSection(recommendations: composer.recommendations, actions: actions)
        }
        .padding(.horizontal, dimensions.spacing.space8)
        .padding(.bottom, dimensions.spacing.space48)
    }
}

extension DetailsContent {
    struct Actions {
        var openCovers: () -> Void
        var openTitles: () -> Void
        var searchAll: () -> Void
        var openCollections: () -> Void
        var openSetup: (Bool) -> Void
        var openEdit: () -> Void
        var openMerge: () -> Void
        var openSourceOrder: () -> Void
        var openScanlatorOrder: () -> Void
        var openLanguageOrder: () -> Void
        var confirmRemove: (DetailsComposer.Sources.Origin) -> Void
        var link: (Tracker) -> Void
        var manage: (DetailsComposer.Tracking.Link) -> Void
        var connect: () -> Void
        var catchUp: (Int) -> Void
        var mark: (Bool, [Double]) -> Void
        var read: (DetailsComposer.Chapters.Row) -> Void
        var inspect: (Recommendation) -> Void
        var confirmReset: () -> Void
        var confirmDownloadUnread: () -> Void
        var confirmDownloadAll: () -> Void
        var confirmDeleteDownloads: () -> Void
    }
}

private struct HeaderSection: View {
    let series: DetailsComposer.Series
    let actions: DetailsContent.Actions

    var body: some View {
        DetailsHeader(
            cover: series.cover,
            referer: series.referer,
            title: series.title,
            authors: series.authors,
            onOpenCovers: actions.openCovers,
            onOpenTitles: actions.openTitles,
            onSearchAll: actions.searchAll
        )
    }
}

private struct ActionsSection: View {
    let composer: DetailsComposer
    let actions: DetailsContent.Actions

    var body: some View {
        let library = composer.library

        VStack(alignment: .leading, spacing: 0) {
            Busy(saving: library.saving) { busy in
                DetailsActions(
                    inLibrary: library.inLibrary,
                    isSaving: busy,
                    canToggle: library.canToggle,
                    canRefresh: composer.refresh.canStart,
                    canRefreshMetadata: composer.refresh.canRefreshMetadata,
                    status: library.status,
                    collectionCount: library.joined.count,
                    onToggleLibrary: {
                        Task {
                            let adding = !library.inLibrary
                            let wrote = await library.toggle()
                            actions.openSetup(adding && wrote)
                        }
                    },
                    onSetStatus: { status in Task { await library.set(status: status) } },
                    onManageCollections: actions.openCollections,
                    onRefreshChapters: { Task { await composer.refreshChapters() } },
                    onRefreshMetadata: { Task { await composer.refreshMetadata() } },
                    onEditDetails: actions.openEdit,
                    onMerge: actions.openMerge,
                    onResetSeries: actions.confirmReset
                )
            }

            SectionFailure(failure: library.failure) { library.clear() }
        }
        .animation(.settle, value: library.failure)
    }
}

private struct SynopsisSection: View {
    let series: DetailsComposer.Series

    var body: some View {
        DetailsSynopsis(synopsis: series.synopsis)
    }
}

private struct TagsSection: View {
    let series: DetailsComposer.Series

    var body: some View {
        if !series.tags.isEmpty {
            DetailsTags(tags: series.tags)
        }
    }
}

private struct TrackingSection: View {
    let tracking: DetailsComposer.Tracking
    let library: DetailsComposer.Library
    let actions: DetailsContent.Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // tracking requires library membership (trackers.md Q6). shown
            // dimmed and inert rather than hidden off-library - a section
            // that is simply absent reads as broken, not gated, to a reader
            // with accounts already connected
            DetailsTracking(
                accounts: tracking.accounts,
                links: tracking.links,
                localProgress: tracking.furthest,
                enabled: library.inLibrary,
                needingSignIn: tracking.needingSignIn,
                syncing: tracking.syncing,
                onLink: actions.link,
                onOpen: actions.manage,
                onConnect: actions.connect,
                onRetry: { link in Task { await tracking.retry(link) } },
                onCatchUp: actions.catchUp,
                onPushLocal: { Task { await tracking.push() } }
            )

            SectionFailure(failure: tracking.failure) { tracking.clear() }
        }
        .animation(.settle, value: tracking.failure)
    }
}

private struct SourcesSection: View {
    let sources: DetailsComposer.Sources
    let refresh: DetailsComposer.Refresh
    let actions: DetailsContent.Actions

    var body: some View {
        if !sources.origins.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                DetailsSources(
                    origins: sources.origins,
                    retrying: refresh.retrying,
                    onSetPrimary: { id in Task { await sources.promote(id) } },
                    onReorder: { ids in Task { await sources.reorder(ids) } },
                    onRemove: { id in
                        guard let origin = sources.origins.first(where: { $0.id == id }) else {
                            return
                        }
                        actions.confirmRemove(origin)
                    },
                    onRetry: { id in Task { await refresh.retry(id) } }
                )

                SectionFailure(failure: sources.failure) { sources.clear() }
            }
            .animation(.settle, value: sources.failure)
        }
    }
}

private struct MetadataSection: View {
    let series: DetailsComposer.Series

    var body: some View {
        DetailsMetadata(
            classification: series.classification,
            publication: series.publication,
            readCount: series.readCount,
            // read and total come from the same place - a per-source total
            // would let "12 of 40" drift into "12 of 120" across sources
            totalCount: series.totalCount,
            lastFetchedDate: series.metadataFetchedDate,
            lastReadDate: series.lastReadDate
        )
    }
}

private struct ChaptersSection: View {
    let composer: DetailsComposer
    let actions: DetailsContent.Actions

    @Environment(\.compositor) private var compositor

    var body: some View {
        let chapters = composer.chapters

        VStack(alignment: .leading, spacing: 0) {
            DetailsChapters(
                chapters: chapters.chapters,
                isFetching: composer.refresh.fetching,
                cadence: composer.cadence,
                hasFetched: composer.series.chaptersFetchedDate != nil,
                sourceCount: composer.sources.origins.count,
                canRefresh: composer.refresh.canStart,
                showAllChapters: chapters.showAll,
                showHalfChapters: chapters.showHalf,
                onShowAllChapters: { on in Task { await chapters.show(all: on) } },
                onShowHalfChapters: { on in Task { await chapters.show(half: on) } },
                onSources: actions.openSourceOrder,
                onScanlators: actions.openScanlatorOrder,
                onLanguages: actions.openLanguageOrder,
                onDownloadUnread: actions.confirmDownloadUnread,
                onDownloadAll: actions.confirmDownloadAll,
                onDeleteDownloads: actions.confirmDeleteDownloads,
                onMark: actions.mark,
                downloads: compositor.downloads,
                onDownload: { id in
                    compositor.downloads.enqueue(chapter: ChapterRecord.ID(rawValue: id))
                },
                onCancelDownload: { id in
                    compositor.downloads.cancel(chapter: ChapterRecord.ID(rawValue: id))
                },
                onDelete: { id in
                    compositor.downloads.delete(chapter: ChapterRecord.ID(rawValue: id))
                },
                onOpen: actions.read
            )

            SectionFailure(failure: chapters.failure) { chapters.clear() }
        }
        .animation(.settle, value: chapters.failure)
    }
}

private struct RecommendationsSection: View {
    let recommendations: DetailsComposer.Recommendations
    let actions: DetailsContent.Actions

    var body: some View {
        DetailsRecommendations(
            phase: recommendations.phase,
            results: recommendations.results,
            onOpen: actions.inspect,
            context: recommendations.context
        )
    }
}
