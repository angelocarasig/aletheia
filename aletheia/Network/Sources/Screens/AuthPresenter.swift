//
//  AuthPresenter.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation
import WebKit

@MainActor
@Observable
final class AuthPresenter {
    struct Challenge: Identifiable {
        let id = UUID()
        let page: WebPage
        let maneuver: String
        let onDismiss: () -> Void
    }

    private(set) var active: Challenge?

    // the page every capture is rendered into, sheet or no sheet. a WebPage that
    // is in no view hierarchy is never laid out and never painted, and turnstile
    // will not run in one - it mounted its iframe, got no layout, was cancelled,
    // and retried until the capture timed out. mounting it behind the app's own
    // content costs nothing visually and is the difference between a challenge
    // that completes and one that loops forever
    private(set) var mounted: WebPage?

    nonisolated init() {}

    func mount(_ page: WebPage) {
        mounted = page
    }

    func unmount() {
        mounted = nil
    }

    func show(page: WebPage, maneuver: String, onDismiss: @escaping () -> Void) {
        active = Challenge(page: page, maneuver: maneuver, onDismiss: onDismiss)
    }

    func hide() {
        let onDismiss = active?.onDismiss
        active = nil
        onDismiss?()
    }
}
