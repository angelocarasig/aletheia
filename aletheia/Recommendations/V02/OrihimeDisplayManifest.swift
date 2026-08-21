//
//  OrihimeDisplayManifest.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import Foundation

struct OrihimeDisplayManifest: Decodable, Sendable {
    let displayVersion: Int
    let titles: Int
    // the order status.npy's byte indexes into - named explicitly rather than
    // assumed to match CatalogStatus's own case order, the same discipline
    // type.npy's mismatch against CatalogFormat already proved necessary
    let statuses: [String]
}
