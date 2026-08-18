//
//  AuthChallengeView.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI
import WebKit

private enum Mount {
    static let opacity: Double = 0.015
}

extension View {
    // the verification sheet belongs to the app rather than to a screen: a
    // capture can be raised by a library refresh with nothing on screen that
    // knows a source is involved. it was presented nowhere at all until
    // 2026-08-15, so `interactive` was dead on every source
    func authChallenge(from presenter: AuthPresenter) -> some View {
        // read here, in a body, or it is not a dependency - a read inside
        // Binding's getter runs when SwiftUI asks for the value rather than
        // while the body evaluates, and the sheet would never open
        let active = presenter.active
        let mounted = presenter.mounted

        // over the tabs rather than behind them, deliberately: webkit throttles
        // timers and rAF in a page it considers not visible, and being covered by
        // the app's own content counts as not visible - a cloudflare challenge in
        // one misses its own deadline and retries every ten seconds until the
        // capture times out (this sat in `.background` for one afternoon and cost
        // six rounds of misdiagnosis). a hair of opacity rather than `.hidden` or
        // zero, which risk reading as invisible and landing back in the throttled
        // case. hit testing off, so the reader is touching the app underneath it.
        // only one WebView may hold a page, so this yields to the sheet
        return overlay {
            if let mounted, active == nil {
                WebView(mounted)
                    .opacity(Mount.opacity)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .sheet(
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
