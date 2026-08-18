//
//  DetailsBusy.swift
//  aletheia
//
//  Created by Angelo Carasig on 12/8/26.
//

import SwiftUI

private enum BusyLayout {
    static let threshold: Duration = .milliseconds(250)
}

struct Busy<Content: View>: View {
    let saving: Bool
    @ViewBuilder var content: (Bool) -> Content

    @State private var showing = false

    var body: some View {
        content(showing)
            .task(id: saving) {
                guard saving else {
                    showing = false
                    return
                }

                try? await Task.sleep(for: BusyLayout.threshold)
                guard !Task.isCancelled else { return }
                showing = true
            }
    }
}

struct SectionFailure: View {
    let failure: Failure?
    var onDismiss: () -> Void

    var body: some View {
        if let failure {
            Banner(
                title: Text(failure.title),
                message: failure.message.isEmpty ? nil : Text(failure.message),
                systemImage: "exclamationmark.triangle.fill",
                tone: .warning,
                action: onDismiss
            )
            .transition(.opacity)
        }
    }
}
