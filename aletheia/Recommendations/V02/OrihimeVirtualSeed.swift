//
//  OrihimeVirtualSeed.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import CoreGraphics
import Foundation

// a title described directly rather than found by row - the unresolved path.
// mirrors heuresis' own VirtualSeed dataclass (blocks/virtual.py) field for
// field, since this is a port of that exact scoring recipe, not a reinterpretation
struct OrihimeVirtualSeed: Sendable {
    var title: String = ""
    var synopsis: String = ""
    var tagNames: [String] = []
    var year: Int?
    var coverImage: CGImage?
    var register: RegisterAxis = .general

    // series format: no source in this app reports it, so there is nowhere to
    // source this from yet - the format block stays permanently gated off for
    // a virtual seed (OrihimeScorer) until this exists, not a bug
}
