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

// most writes on this screen finish in under a tenth of a second, and a control
// that flashes disabled for eighty milliseconds reads as the app stuttering
// rather than as feedback. so a busy state is withheld until the write has been
// running long enough to be worth mentioning - the slow ones (marking four
// hundred chapters, removing a source) still show it
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

                // cancelled when the write finishes first, which is the whole
                // point: a fast write never reaches the assignment
                try? await Task.sleep(for: BusyLayout.threshold)
                guard !Task.isCancelled else { return }
                showing = true
            }
    }
}

// a write that did not happen, shown where it was asked for rather than as an
// alert over the whole screen. it stays until the reader taps it away, because
// a failure is a state rather than a message
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
