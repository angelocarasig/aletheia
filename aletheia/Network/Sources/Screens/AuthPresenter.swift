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

    nonisolated init() {}

    func show(page: WebPage, maneuver: String, onDismiss: @escaping () -> Void) {
        active = Challenge(page: page, maneuver: maneuver, onDismiss: onDismiss)
    }

    func hide() {
        let onDismiss = active?.onDismiss
        active = nil
        onDismiss?()
    }
}
