//
//  CollectionSettingsListScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 22/8/2026.
//

import SwiftUI

struct CollectionSettingsListScreen: View {
    @Environment(\.database) private var database
    @Environment(\.dimensions) private var dimensions

    @State private var vm: CollectionSettingsViewModel?
    @State private var route: CollectionRecord.ID?

    var body: some View {
        ScrollView {
            if let vm {
                if vm.collections.isEmpty, !vm.isLoading {
                    ContentUnavailableView(
                        "No Collections",
                        systemImage: "rectangle.stack",
                        description: Text("Collections you create in Library appear here.")
                    )
                } else {
                    VStack(spacing: dimensions.spacing.space12) {
                        ForEach(vm.collections, id: \.id) { collection in
                            SettingsCard(
                                title: collection.name,
                                systemImage: "rectangle.stack",
                                detail: detail(for: collection)
                            ) { route = collection.id }
                        }
                    }
                    .padding(.horizontal, dimensions.screenMargin)
                    .padding(.vertical, dimensions.spacing.space16)
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .navigationTitle("Collections")
        .navigationSubtitle("Hide from Home, or lock behind Face ID")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { id in
            if let vm, let collection = vm.collections.first(where: { $0.id == id }) {
                CollectionSettingsScreen(vm: vm, collection: collection)
            }
        }
        .task {
            let model = vm ?? CollectionSettingsViewModel(database: database)
            vm = model
            await model.load()
        }
    }

    private func detail(for collection: CollectionRecord) -> String {
        var parts: [String] = []
        if collection.hideFromHome { parts.append("Hidden from Home") }
        if collection.requiresFaceId { parts.append("Face ID required") }
        return parts.isEmpty ? "No restrictions" : parts.joined(separator: " · ")
    }
}
