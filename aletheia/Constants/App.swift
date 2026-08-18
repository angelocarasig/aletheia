//
//  App.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/7/2026.
//

import Foundation

extension Constants {
    enum Tasks {
        // one identifier per operation, not shared - independently startable
        // operations sharing an id compete for the system's concurrent-task
        // limit and one submission fails silently. declared in Info.plist
        // under BGTaskSchedulerPermittedIdentifiers
        static let refresh = "moe.aletheia.refresh"

        // extends work already started; scheduledRefresh asks the system to
        // find its own moment instead
        static let scheduledRefresh = "moe.aletheia.refresh.scheduled"

        static let downloads = "moe.aletheia.downloads"

        // weeks-to-months cadence, not hours
        static let scheduledMetadataRefresh = "moe.aletheia.metadata.scheduled"
    }

    enum App {
        static let identifier = "group.moe.aletheia"

        static let name = "Aletheia"

        // XCODE_RUNNING_FOR_PREVIEWS is the documented signal but is not set
        // under xcode 26's XOJIT previews - bundle path is, since previews run
        // from Xcode's own Previews directory rather than the simulator's
        static var isPreview: Bool {
            Bundle.main.bundlePath.contains("/Previews/")
        }
    }
}
