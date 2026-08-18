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
    @Environment(\.scenePhase) private var scenePhase

    @State private var vm: ReaderViewModel?
    @State private var showingChapters = false
    @State private var showingSources = false
    @State private var showingSettings = false
    @State private var showingFilters = false

    // branch selector and animation key are one value - the swap previously
    // keyed isOverlayVisible, which never changes on readiness, so the
    // skeleton's transition was dead code. see docs/features/loading-transitions.md
    private var phase: LoadPhase {
        if vm?.engine != nil { .content } else if vm?.failure != nil { .failed } else { .pending }
    }

    var body: some View {
        // read here rather than inside the alert's binding: a read in a getter
        // runs when SwiftUI asks for the value rather than while the body is
        // evaluating, so it is not a dependency and the alert would never open
        let save = vm?.pageSave

        return ZStack {
            Color.black
                .ignoresSafeArea()

            switch phase {
            case .content:
                if let vm, let engine = vm.engine {
                    Reading(vm, engine)
                        .transition(.opacity)
                }
            case .failed:
                if let vm, let failure = vm.failure {
                    Unavailable(failure)
                        .transition(.opacity)
                }
            default:
                // a whole screen of content is about to land, so it gets the
                // shape it will take rather than a spinner over nothing
                ReaderSkeleton()
                    .transition(.opacity)
            }
        }
        .statusBarHidden(!(vm?.isOverlayVisible ?? true))
        .toolbarVisibility(.hidden, for: .navigationBar)
        .toolbarVisibility(.hidden, for: .tabBar)
        .animation(.settle, value: phase)
        .task {
            guard vm == nil else { return }
            let model = ReaderViewModel(
                seriesId: seriesId,
                chapterId: chapterId,
                database: compositor.database,
                registry: compositor.registry,
                trackers: compositor.trackers
            )
            vm = model
            await model.load()
            model.flashTapZones()
        }
        .sheet(
            isPresented: Binding(
                get: { vm?.isShowingTapZones ?? false }, set: { vm?.isShowingTapZones = $0 })
        ) {
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
        .sheet(item: Binding(get: { vm?.explainingGap }, set: { vm?.explainingGap = $0 })) { gap in
            ReaderGapSheet(gap: gap)
        }
        // a page saved leaves no trace on this screen - the page is still there
        // and still looks the same - so the alert is the whole of the answer
        .alert(
            save?.title ?? "",
            isPresented: Binding(get: { save != nil }, set: { if !$0 { vm?.pageSave = nil } }),
            presenting: save
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { save in
            // empty on success, and an alert draws no gap for an empty message,
            // so this needs no branch
            Text(save.message)
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
        .sheet(isPresented: $showingFilters) {
            if let vm, let engine = vm.engine {
                ReaderFiltersSheet(
                    engine: engine,
                    onDim: { vm.setDim($0) },
                    onGrayscale: { vm.setGrayscale($0) },
                    onInverted: { vm.setInverted($0) },
                    onWarmth: { vm.setWarmth($0) },
                    onKeepScreenOn: { vm.setKeepScreenOn($0) }
                )
            }
        }
        // held for the reader rather than for the app, so leaving the screen by
        // any route hands it back below
        .task(id: vm?.engine?.configuration.keepScreenOn) {
            UIApplication.shared.isIdleTimerDisabled =
                vm?.engine?.configuration.keepScreenOn ?? false
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            guard let vm else { return }
            Task { await vm.close() }
        }
        // .background commits progress and ends the sitting; .active starts the
        // next one. .inactive stays untouched - a notification shade or a call
        // banner is not the end of a sitting
        .onChange(of: scenePhase) { _, phase in
            guard let vm else { return }
            switch phase {
            case .background:
                Task { await vm.background() }
            case .active:
                vm.foreground()
            default:
                break
            }
        }
    }
}

extension ReaderScreen {
    @ViewBuilder
    fileprivate func Reading(_ vm: ReaderViewModel, _ engine: ReaderEngine) -> some View {
        GeometryReader { proxy in
            ZStack {
                // opacity rather than a branch, for both of these. a
                // UIViewControllerRepresentable inside an if/else is a different
                // view tree per state, and switching branches would tear the
                // collection view down and lose the reader's place
                ReaderSurface(engine: engine)
                    .ignoresSafeArea()
                    .grayscale(engine.configuration.grayscale ? 1 : 0)
                    .overlay {
                        // difference against white IS an inversion, and unlike
                        // .colorInvert() it has a strength, so it can be off
                        Color.white
                            .blendMode(.difference)
                            .opacity(engine.configuration.inverted ? 1 : 0)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }
                    .overlay {
                        // one overlay, two directions: the sign picks which
                        // channel gets pulled down and the magnitude is the
                        // strength, so neutral is a real zero rather than a
                        // third tone that happens to be colourless
                        let warmth = engine.configuration.warmth
                        let tone =
                            warmth < 0
                            ? ReaderConfiguration.Defaults.coolTone
                            : ReaderConfiguration.Defaults.warmthTone

                        Color(red: tone.red, green: tone.green, blue: tone.blue)
                            .blendMode(.multiply)
                            .opacity(abs(warmth))
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }

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
                        onFilters: { showingFilters = true },
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

    fileprivate func Failed(_ error: ReaderError, engine: ReaderEngine) -> some View {
        ContentUnavailableView {
            Label(
                error.errorDescription ?? "Something Went Wrong",
                systemImage: "exclamationmark.triangle")
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

    fileprivate func Unavailable(_ failure: Failure) -> some View {
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
