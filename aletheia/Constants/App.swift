//
//  App.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/7/2026.
//

import Foundation

extension Constants {
    enum App {
        static let identifier = "group.moe.aletheia"

        // xcode runs the whole app to render a canvas. XCODE_RUNNING_FOR_PREVIEWS
        // is the documented signal but is not set under xcode 26's XOJIT
        // previews - the bundle path is, because it runs from Xcode's own
        // Previews directory rather than the simulator's
        static var isPreview: Bool {
            Bundle.main.bundlePath.contains("/Previews/")
        }
    }
}
