//
//  SourceSettingsSheet.swift
//  aletheia
//
//  Created by Angelo Carasig on 22/8/2026.
//

import SwiftUI

// shared between the gearshape button on a source's own screen and the
// Settings > Sources list - same settings either way, just two entry points
struct SourceSettingsSheet: View {
    let vm: SourceSettingsViewModel
    let source: SourceRecord

    @Environment(\.dismiss) private var dismiss

    @State private var hideFromSearch: SearchVisibility
    @State private var requiresFaceId: Bool

    init(vm: SourceSettingsViewModel, source: SourceRecord) {
        self.vm = vm
        self.source = source
        _hideFromSearch = State(initialValue: source.hideFromSearch)
        _requiresFaceId = State(initialValue: source.requiresFaceId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Hide from Search", selection: $hideFromSearch) {
                        Text("Automatic").tag(SearchVisibility.unset)
                        Text("Hidden").tag(SearchVisibility.hidden)
                        Text("Shown").tag(SearchVisibility.shown)
                    }
                } footer: {
                    Text(
                        "Automatic hides an adult source by default. Either choice can be overridden here."
                    )
                }

                Section {
                    Toggle("Require Face ID", isOn: $requiresFaceId)
                } footer: {
                    Text(
                        "This source's own screen stays locked until unlocked with Face ID. Unlocking lasts for this app session only."
                    )
                }
            }
            .navigationTitle(source.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: hideFromSearch) { _, value in
                guard let id = source.id else { return }
                Task { await vm.setHideFromSearch(value, for: id) }
            }
            .onChange(of: requiresFaceId) { _, value in
                guard let id = source.id else { return }
                Task { await vm.setRequiresFaceId(value, for: id) }
            }
        }
    }
}
