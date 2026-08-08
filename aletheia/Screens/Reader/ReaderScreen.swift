//
//  ReaderScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI

struct ReaderScreen: View {
    let seriesId: SeriesRecord.ID
    let chapterId: ChapterRecord.ID

    @Environment(\.compositor) private var compositor
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dimensions) private var dimensions

    @State private var vm: ReaderViewModel?
    @State private var showingChapters = false
    @State private var showingSources = false
    @State private var showingSettings = false

    private enum Layout {
        static let settle: Animation = .easeOut(duration: 0.2)
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if let vm, let engine = vm.engine {
                Reading(vm, engine)
            } else if let vm, let failure = vm.failure {
                Unavailable(failure)
            } else {
                // a whole screen of content is about to land, so it gets the
                // shape it will take rather than a spinner over nothing
                ReaderSkeleton()
                    .transition(.opacity)
            }
        }
        .statusBarHidden(!(vm?.isOverlayVisible ?? true))
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .animation(Layout.settle, value: vm?.isOverlayVisible ?? true)
        .task {
            guard vm == nil else { return }
            let model = ReaderViewModel(
                seriesId: seriesId,
                chapterId: chapterId,
                database: compositor.database,
                registry: compositor.registry
            )
            vm = model
            await model.load()
            model.flashTapZones()
        }
        .sheet(isPresented: Binding(get: { vm?.isShowingTapZones ?? false }, set: { vm?.isShowingTapZones = $0 })) {
            if let vm {
                ReaderTapZonePicker(
                    layout: vm.tapZone,
                    reversed: vm.tapZonesReversed,
                    isRightToLeft: vm.isReadingRightToLeft,
                    onSelect: { vm.setTapZone($0) },
                    onReverse: { vm.setTapZonesReversed($0) }
                )
            }
        }
        .sheet(isPresented: $showingChapters) {
            if let vm, let engine = vm.engine {
                ReaderChapterList(
                    slots: vm.slots,
                    current: engine.current?.number,
                    isLoading: vm.isLoadingSlots,
                    onSelect: { slot in
                        Task { await engine.jump(to: slot.chapter) }
                    }
                )
                // read on present rather than at open: progress moves as you
                // read, so the list has to be current, not cached from launch
                .task { await vm.loadSlots() }
            }
        }
        .sheet(isPresented: $showingSources) {
            if let vm, let engine = vm.engine, let chapter = engine.current?.id {
                ReaderSourceSwitcher(
                    slot: vm.slot(for: engine.current?.number),
                    active: vm.activeRow(for: chapter),
                    isLoading: vm.isLoadingSlots,
                    onSelect: { option in
                        Task { await vm.swap(to: option, for: chapter) }
                    }
                )
                // the alternatives ride along with the chapter list's query, so
                // this is the same read rather than a second one
                .task { await vm.loadSlots() }
            }
        }
        .sheet(isPresented: $showingSettings) {
            if let vm, let engine = vm.engine {
                ReaderSettingsSheet(
                    engine: engine,
                    onPadding: { vm.setHorizontalPadding($0) },
                    onTint: { vm.setChromeTint($0) }
                )
            }
        }
        .onDisappear {
            guard let vm else { return }
            Task { await vm.close() }
        }
    }
}

private extension ReaderScreen {
    @ViewBuilder
    func Reading(_ vm: ReaderViewModel, _ engine: ReaderEngine) -> some View {
        GeometryReader { proxy in
            ZStack {
                ReaderSurface(engine: engine)
                    .ignoresSafeArea()

                if engine.configuration.dim > 0 {
                    Color.black
                        .opacity(engine.configuration.dim)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }

                if vm.isFlashingTapZones {
                    ReaderTapZoneMap(layout: vm.tapZone, reversed: vm.tapZonesReversed)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                // deliberately outside the overlay branch: a paged mode turns
                // its own page, and you have to be able to see that coming with
                // the chrome down
                if engine.isAutoScrolling, engine.configuration.mode.isPaged {
                    ReaderCountdown(progress: engine.autoAdvanceProgress)
                        .transition(.opacity)
                }

                if let error = engine.error {
                    Failed(error, engine: engine)
                }

                if vm.isOverlayVisible {
                    ReaderOverlay(
                        engine: engine,
                        sourceIcon: vm.sourceIcon(for: engine.current?.id),
                        onPreviousChapter: { Task { await engine.previousChapter() } },
                        onNextChapter: { Task { await engine.nextChapter() } },
                        onSeek: { engine.goToPage($0) },
                        // the reading direction is half of what the zones mean,
                        // so changing it changes them and that has to be shown
                        onModeChange: { mode in
                            vm.setMode(mode)
                            vm.flashTapZones()
                        },
                        onDimChange: { vm.setDim($0) },
                        onSpeedChange: { vm.setAutoScrollSpeed($0) },
                        onIntervalChange: { vm.setAutoAdvanceInterval($0) },
                        // deferred screens. present as real controls so the
                        // chrome is laid out for them, and say so when tapped
                        onChapters: { showingChapters = true },
                        onSources: { showingSources = true },
                        onSettings: { showingSettings = true },
                        onTapZones: { vm.isShowingTapZones = true },
                        onDismiss: { dismiss() }
                    )
                    .transition(.opacity)
                }

            }
            // taps arrive from UIKit in window space and are handled the moment
            // they land. keeping the frame in step here is all the conversion
            // needs, and avoids routing a tap through observable state
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { frame in
                vm.surfaceFrame = frame
            }
        }
    }

    func Failed(_ error: ReaderError, engine: ReaderEngine) -> some View {
        ContentUnavailableView {
            Label(error.errorDescription ?? "Something Went Wrong", systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.failureReason ?? "")
        } actions: {
            if error.isRetryable {
                Button("Try Again") {
                    Task { await engine.retry() }
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Go Back") { dismiss() }
        }
        .background(.ultraThinMaterial)
    }

    func Unavailable(_ failure: Failure) -> some View {
        ContentUnavailableView {
            Label(failure.title, systemImage: "book.closed")
        } description: {
            Text(failure.message)
        } actions: {
            // Go Back always stands - the reader is pushed, so leaving is the
            // one action that is always available and always correct here
            Button("Go Back") { dismiss() }
        }
    }
}
