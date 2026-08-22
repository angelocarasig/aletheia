//
//  CollectionSettingsScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 22/8/2026.
//

import SwiftUI

struct CollectionSettingsScreen: View {
    let vm: CollectionSettingsViewModel
    let collection: CollectionRecord

    @State private var hideFromHome: Bool
    @State private var requiresFaceId: Bool

    init(vm: CollectionSettingsViewModel, collection: CollectionRecord) {
        self.vm = vm
        self.collection = collection
        _hideFromHome = State(initialValue: collection.hideFromHome)
        _requiresFaceId = State(initialValue: collection.requiresFaceId)
    }

    var body: some View {
        Form {
            Section {
                Toggle("Hide from Home", isOn: $hideFromHome)
            } footer: {
                Text("Series in this collection won't appear anywhere on Home.")
            }

            Section {
                Toggle("Require Face ID", isOn: $requiresFaceId)
            } footer: {
                Text(
                    "This collection's section in Library stays hidden until unlocked with Face ID. A series it shares with another collection shows blurred there until unlocked. Unlocking lasts for this app session only."
                )
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: hideFromHome) { _, value in
            guard let id = collection.id else { return }
            Task { await vm.setHideFromHome(value, for: id) }
        }
        .onChange(of: requiresFaceId) { _, value in
            guard let id = collection.id else { return }
            Task { await vm.setRequiresFaceId(value, for: id) }
        }
    }
}
