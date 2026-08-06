//
//  LibraryScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI

struct LibraryScreen: View {
    @Environment(\.database) private var database
    @Environment(\.dimensions) private var dimensions
    @Environment(\.compositor) private var compositor

    @AppStorage("gridColumns") private var gridColumns = 3
    @State private var vm: LibraryViewModel?

    private enum Layout {
        static let placeholderCards = 12
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: dimensions.spacing.space12),
            count: max(1, gridColumns)
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let vm, !vm.isLoading {
                    Grid(vm)
                } else {
                    Skeleton
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: SeriesEntry.self) { DetailsScreen(entry: $0) }
            .task {
                let vm = vm ?? LibraryViewModel(database: database, assets: compositor.assets)
                self.vm = vm
                await vm.load()
            }
        }
    }

    @ViewBuilder
    private func Grid(_ vm: LibraryViewModel) -> some View {
        if vm.entries.isEmpty {
            ContentUnavailableView(
                "Library Empty",
                systemImage: "books.vertical",
                description: Text("Series you add from a source appear here")
            )
        } else {
            LazyVGrid(columns: columns, spacing: dimensions.spacing.space16) {
                ForEach(vm.entries) { entry in
                    NavigationLink(value: SeriesEntry.library(entry.id)) {
                        LibraryCard(title: entry.title, cover: entry.cover, unreadCount: entry.unreadCount)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, dimensions.spacing.space12)
        }
    }

    private var Skeleton: some View {
        LazyVGrid(columns: columns, spacing: dimensions.spacing.space16) {
            ForEach(0..<Layout.placeholderCards, id: \.self) { _ in
                LibraryCard()
            }
        }
        .padding(.horizontal, dimensions.spacing.space12)
        .shimmer()
    }
}
