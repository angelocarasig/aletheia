//
//  App.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/7/2026.
//

import Foundation

extension Constants {
    enum Tasks {
        // one identifier per operation rather than one shared: refresh and
        // downloads are independently startable and can run together, and
        // hitting the system's concurrent-task limit is a known cause of a
        // submission simply failing. declared in Info.plist under
        // BGTaskSchedulerPermittedIdentifiers
        static let refresh = "moe.aletheia.refresh"

        // a different api as well as a different id: the one above extends work
        // someone started, this one asks the system to find a moment of its own
        static let scheduledRefresh = "moe.aletheia.refresh.scheduled"
    }

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
