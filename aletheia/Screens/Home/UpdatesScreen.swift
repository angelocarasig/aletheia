//
//  UpdatesScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import SwiftUI
import Tagged

// every series that moved, where Home shows the first three. the rows behave
// exactly as they do there - tapping one opens the chapter, not a screen about
// the chapter - so arriving here changes how much you can see and nothing else
struct UpdatesScreen: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    @State private var vm: UpdatesViewModel?
    // the destinations are declared here rather than inherited: this screen is
    // pushed with navigationDestination(isPresented:), and a value push from
    // inside one of those lands beneath it
    @State private var reading: ReadingTarget?
    @State private var route: SeriesEntry?

    @AppStorage(Preferences.Key.blurAdultHome) private var blurAdult = Preferences.Default
        .blurAdultHome

    init(vm: UpdatesViewModel? = nil) {
        _vm = State(initialValue: vm)
    }

    private struct ReadingTarget: Identifiable, Hashable {
        let seriesId: SeriesRecord.ID
        let chapterId: ChapterRecord.ID
        var id: ChapterRecord.ID { chapterId }
    }

    private var obscured: Bool { blurAdult.blurs(adultSource: false) }

    private var phase: LoadPhase {
        if let vm {
            if vm.failure != nil {
                .failed
            } else if vm.entries == nil {
                .pending
            } else if vm.isEmpty {
                .empty
            } else {
                .content
            }
        } else {
            .pending
        }
    }

    var body: some View {
        ZStack {
            switch phase {
            case .content:
                if let entries = vm?.entries {
                    Content(entries)
                        .transition(.opacity)
                }
            case .empty:
                ContentUnavailableView {
                    Label("No New Chapters", systemImage: "bell.slash")
                } description: {
                    Text("Series you follow will appear here when they update.")
                }
                .transition(.opacity)
            case .failed:
                if let vm, let failure = vm.failure {
                    ContentUnavailableView {
                        Label(failure.title, systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(failure.message)
                    } actions: {
                        if failure.isRetryable {
                            Button("Try Again") { vm.retry() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .transition(.opacity)
                }
            default:
                ProgressView()
                    .transition(.opacity)
            }
        }
        .animation(.settle, value: phase)
        .navigationTitle("Updates")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { DetailsScreen(entry: $0) }
        .navigationDestination(item: $reading) { target in
            ReaderScreen(seriesId: target.seriesId, chapterId: target.chapterId)
        }
        .task {
            guard vm == nil else { return }
            let model = UpdatesViewModel(
                database: compositor.database,
                assets: compositor.assets,
                registry: compositor.registry
            )
            vm = model
            model.observe()
        }
    }
}

// MARK: - Content

extension UpdatesScreen {
    fileprivate func Content(_ entries: [HomeViewModel.UpdateEntry]) -> some View {
        ScrollView {
            GlassEffectContainer(spacing: dimensions.spacing.space12) {
                VStack(spacing: dimensions.spacing.space12) {
                    ForEach(entries) { entry in
                        UpdateCard(
                            title: entry.title,
                            cover: entry.cover,
                            count: entry.count,
                            latest: entry.latest,
                            obscured: obscured && entry.adult
                        )
                        .contentShape(.rect)
                        // the series, matching the shelf on Home this screen is
                        // the full list of. reading the chapter is the deliberate
                        // action rather than the accidental one
                        .tappable {
                            route = .library(entry.id)
                        }
                        .contextMenu {
                            Button {
                                reading = ReadingTarget(
                                    seriesId: entry.id, chapterId: entry.target.chapterId)
                            } label: {
                                Label(
                                    "Read \(ReadingFormat.chapter(entry.target.number))",
                                    systemImage: "book.pages")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.vertical, dimensions.spacing.space16)
        }
        .scrollIndicators(.hidden)
        .scrollEdgeEffectStyle(.hard, for: .top)
        .scrollEdgeEffectStyle(.soft, for: .bottom)
    }
}

// MARK: - Previews

#if DEBUG
    private enum Mock {
        static let titles = [
            "Blue Lock", "The Exiled Heavy Knight Knows How to Game the System", "Mia is back",
        ]
        static let counts = [213, 163, 44]

        static func entry(_ index: Int) -> HomeViewModel.UpdateEntry {
            let id = SeriesRecord.ID(rawValue: Int64(index + 1))
            let latest: Date = .now.addingTimeInterval(TimeInterval(-3_600 * (index + 1)))

            return HomeViewModel.UpdateEntry(
                id: id,
                title: titles[index % titles.count],
                cover: nil,
                count: counts[index % counts.count],
                latest: latest,
                target: .start(chapterId: ChapterRecord.ID(rawValue: Int64(index + 1)), number: 1),
                adult: false
            )
        }

        static func entries(_ count: Int) -> [HomeViewModel.UpdateEntry] {
            (0..<count).map(entry)
        }
    }

    #Preview("Populated") {
        NavigationStack {
            UpdatesScreen(vm: .preview(entries: Mock.entries(9)))
        }
    }

    #Preview("Empty") {
        NavigationStack {
            UpdatesScreen(vm: .preview(entries: []))
        }
    }
#endif
