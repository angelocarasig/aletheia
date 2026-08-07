//
//  ReaderSurface.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI

// the only UIKit seam the rest of the app sees. everything above this is
// SwiftUI, everything below it is a collection view
struct ReaderSurface: UIViewControllerRepresentable {
    let engine: ReaderEngine

    func makeUIViewController(context: Context) -> ReaderController {
        let controller = ReaderController(configuration: engine.configuration)
        engine.attach(controller)
        return controller
    }

    func updateUIViewController(_ controller: ReaderController, context: Context) {
        guard controller.configuration != engine.configuration else { return }
        controller.update(engine.configuration)
    }
}
