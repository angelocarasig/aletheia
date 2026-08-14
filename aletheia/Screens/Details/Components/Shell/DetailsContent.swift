//
//  DetailsContent.swift
//  aletheia
//
//  Created by Angelo Carasig on 12/8/26.
//

import SwiftUI
import Tagged

// the scroll's contents, one view per section. each takes only the part of the
// composer it draws, so a chapter finishing redraws the chapter list and leaves
// the header, the sources and the tracking rows alone. written as views rather
// than as builder functions for exactly that reason - a function is pasted into
// its caller, and everything it reads becomes the caller's dependency
struct DetailsContent: View {
    let composer: DetailsComposer
    let actions: Actions

    @Environment(\.dimensions) private var dimensions

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space20) {
            // the backdrop shows through here rather than parallaxing - it is a
            // sibling of the scroll view, not a header inside it
            Spacer()
                .frame(height: DetailsBackdrop.heroHeight)

            HeaderSection(series: composer.series, actions: actions)
            ActionsSection(composer: composer, actions: actions)
            SynopsisSection(series: composer.series)
            TagsSection(series: composer.series)
            TrackingSection(tracking: composer.tracking, library: composer.library, actions: actions)
            SourcesSection(sources: composer.sources, refresh: composer.refresh, actions: actions)
            MetadataSection(series: composer.series)
            ChaptersSection(composer: composer, actions: actions)
            RecommendationsSection(recommendations: composer.recommendations, actions: actions)
        }
        .padding(.horizontal, dimensions.spacing.space8)
        .padding(.bottom, dimensions.spacing.space48)
    }
}

// everything the sections need the screen to do. gathered into one value so a
// section takes two parameters rather than nine closures, and so adding a sheet
// does not change every signature between here and it
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
        // the mark a tracker's number asks for. it spans two children - read
        // state belongs to chapters, the number came from tracking - so it is
        // the root's, which is where it already lived for the manage sheet
        var catchUp: (Int) -> Void
        var mark: (Bool, [Double]) -> Void
        var read: (DetailsComposer.Chapters.Row) -> Void
        var inspect: (Recommendation) -> Void
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

    @Environment(\.compositor) private var compositor

    var body: some View {
        let library = composer.library

        VStack(alignment: .leading, spacing: 0) {
            Busy(saving: library.saving) { busy in
                DetailsActions(
                    inLibrary: library.inLibrary,
                    isSaving: busy,
                    canToggle: library.canToggle,
                    canRefresh: composer.refresh.canStart,
                    status: library.status,
                    collectionCount: library.joined.count,
                    // the add is committed first and the flow opens over it, so
                    // closing at any page leaves the series added. removing
                    // stays a plain toggle - there is nothing to set up on the
                    // way out
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
                    onMarkAll: { read in
                        actions.mark(read, composer.chapters.chapters.map(\.number))
                    },
                    onEditDetails: actions.openEdit,
                    onMerge: actions.openMerge,
                    onDownloadUnread: {
                        guard let id = composer.seriesId else { return }
                        compositor.downloads.enqueue(unreadFor: id)
                    },
                    onDeleteDownloads: {
                        guard let id = composer.seriesId else { return }
                        compositor.downloads.delete(for: id)
                    }
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
        // emptiness is decided at mapping - an empty synopsis arrives as nil
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
            // tracking requires library membership (trackers.md Q6). it used to
            // render nothing at all off-library, on the grounds that a Link row
            // which cannot be operated is an affordance that lies - but a
            // section that is simply absent lies differently, and worse: a
            // reader with two connected accounts and no tracking on screen
            // concludes the feature is broken rather than gated. dimmed and
            // inert says both things at once, and the line underneath says what
            // unlocks it
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
                    // its chapters go with it, so this one asks first
                    onRemove: { id in
                        guard let origin = sources.origins.first(where: { $0.id == id }) else { return }
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
            // both numbers now come from the same place, so "12 of 40" cannot
            // become "12 of 120" when every source's copy is on show
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
                hasFetched: composer.series.chaptersFetchedDate != nil,
                sourceCount: composer.sources.origins.count,
                showAllChapters: chapters.showAll,
                showHalfChapters: chapters.showHalf,
                onShowAllChapters: { on in Task { await chapters.show(all: on) } },
                onShowHalfChapters: { on in Task { await chapters.show(half: on) } },
                onSources: actions.openSourceOrder,
                onScanlators: actions.openScanlatorOrder,
                onLanguages: actions.openLanguageOrder,
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

// last on the screen, and the only section whose content comes from neither the
// database nor a source. it reads one child and nothing else, so a chapter
// progress tick cannot redraw twenty covers
private struct RecommendationsSection: View {
    let recommendations: DetailsComposer.Recommendations
    let actions: DetailsContent.Actions

    var body: some View {
        DetailsRecommendations(
            phase: recommendations.phase,
            results: recommendations.results,
            onOpen: actions.inspect
        )
    }
}
