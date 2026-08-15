//
//  AuthChallengeView.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI
import WebKit

extension View {
    // the verification sheet belongs to the app rather than to a screen: a
    // capture is raised by whichever request needed one, which can be a library
    // refresh with nothing on screen that knows a source is involved. it was
    // presented nowhere at all until 2026-08-15, so `interactive` was dead on
    // every source and the headless half of every capture was carrying all of them
    func authChallenge(from presenter: AuthPresenter) -> some View {
        // read here, in a body, or it is not a dependency - a read inside
        // Binding's getter runs when SwiftUI asks for the value rather than
        // while the body evaluates, and the sheet would never open
        let active = presenter.active

        return sheet(
            item: Binding(get: { active }, set: { if $0 == nil { presenter.hide() } })
        ) { challenge in
            AuthChallengeView(
                page: challenge.page,
                maneuver: challenge.maneuver,
                onClose: { presenter.hide() }
            )
        }
    }
}

struct AuthChallengeView: View {
    let page: WebPage
    let maneuver: String
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(maneuver)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()

                WebView(page)
            }
            .navigationTitle("Verify")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { onClose() }
                }
            }
        }
    }
}
