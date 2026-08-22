//
//  SourceSettingsListScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 22/8/2026.
//

import SwiftUI

struct SourceSettingsListScreen: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions
    @AppStorage(Preferences.Key.bypassAdultSources) private var bypassAdult = Preferences.Default
        .bypassAdultSources

    @State private var vm: SourceSettingsViewModel?
    @State private var editing: SourceRecord.ID?

    var body: some View {
        ScrollView {
            if let vm {
                if vm.sources.isEmpty, !vm.isLoading {
                    ContentUnavailableView(
                        "No Sources",
                        systemImage: "puzzlepiece",
                        description: Text("Sources you install appear here.")
                    )
                } else {
                    VStack(spacing: dimensions.spacing.space12) {
                        ForEach(vm.sources, id: \.id) { source in
                            SettingsCard(
                                title: source.name,
                                systemImage: vm.icon(for: source) == nil ? "puzzlepiece.extension" : nil,
                                icon: vm.icon(for: source),
                                detail: detail(for: source)
                            ) { editing = source.id }
                        }
                    }
                    .padding(.horizontal, dimensions.screenMargin)
                    .padding(.vertical, dimensions.spacing.space16)
                }
            }
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .navigationTitle("Sources")
        .navigationSubtitle("Hide from search, or lock behind Face ID")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(
            isPresented: Binding(
                get: { editing != nil }, set: { if !$0 { editing = nil } })
        ) {
            if let vm, let id = editing, let source = vm.sources.first(where: { $0.id == id }) {
                SourceSettingsSheet(vm: vm, source: source)
            }
        }
        .task {
            let model =
                vm
                ?? SourceSettingsViewModel(database: compositor.database, registry: compositor.registry)
            model.bypassAdult = bypassAdult
            vm = model
            await model.load()
        }
        .task(id: bypassAdult) { vm?.bypassAdult = bypassAdult }
    }

    private func detail(for source: SourceRecord) -> String {
        var parts: [String] = []
        switch source.hideFromSearch {
        case .hidden: parts.append("Hidden from search")
        case .shown: parts.append("Shown in search")
        case .unset: break
        }
        if source.requiresFaceId { parts.append("Face ID required") }
        return parts.isEmpty ? "No restrictions" : parts.joined(separator: " · ")
    }
}
