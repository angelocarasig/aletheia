//
//  OrihimeManifest.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/26
//

import Foundation

struct OrihimeManifest: Decodable, Sendable {
    let packSchema: Int
    let builtAt: String
    let corpus: Corpus
    let counts: Counts
    let typeCodes: [String]
    let ratingLadder: [String]
    let railsCeiling: RailsCeiling
    let vectorsDtype: [String: String]
    let grade: String?
    let files: [String: FileSpec]

    struct Corpus: Decodable, Sendable {
        let catalogueSha256: String
        let activeSeries: Int
        let titles: Int
    }

    struct Counts: Decodable, Sendable {
        let seeds: Int
        let k: Int
        let relations: Int
        let excluded: Int
        let tagVocabulary: Int
        let virtualFixtures: Int
    }

    struct RailsCeiling: Decodable, Sendable {
        let rating: String
        let types: [String]
    }

    // shape/dtype are present for a standalone .npy entry; absent for a .npz container,
    // which holds several arrays rather than describing one
    struct FileSpec: Decodable, Sendable {
        let bytes: Int
        let sha256: String
        let shape: [Int]?
        let dtype: String?
    }
}
