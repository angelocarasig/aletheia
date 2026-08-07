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
    @State private var showingTapZones = false

    private enum Layout {
        static let settle: Animation = .easeOut(duration: 0.2)
        static let flash: Duration = .milliseconds(700)
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
            await flashTapZones()
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

                if showingTapZones {
                    ReaderTapZoneOverlay(
                        layout: ReaderSettings.tapZone,
                        reversed: ReaderSettings.tapZonesReversed
                    )
                    .ignoresSafeArea()
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
                        onModeChange: { mode in
                            vm.setMode(mode)
                            Task { await flashTapZones() }
                        },
                        onDimChange: { vm.setDim($0) },
                        onSpeedChange: { vm.setAutoScrollSpeed($0) },
                        // deferred screens. present as real controls so the
                        // chrome is laid out for them, and say so when tapped
                        onChapters: { AppLog.shared.log("TODO chapter list", category: "reader") },
                        onSources: { AppLog.shared.log("TODO source switcher", category: "reader") },
                        onSettings: { AppLog.shared.log("TODO reader settings", category: "reader") },
                        onTapZones: { Task { await flashTapZones() } },
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

    func Unavailable(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Can't Open This Series", systemImage: "book.closed")
        } description: {
            Text(message)
        } actions: {
            Button("Go Back") { dismiss() }
        }
    }

    func flashTapZones() async {
        guard ReaderSettings.tapZonesEnabled else { return }
        withAnimation(Layout.settle) { showingTapZones = true }
        try? await Task.sleep(for: Layout.flash)
        withAnimation(Layout.settle) { showingTapZones = false }
    }
}
