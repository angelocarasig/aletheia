//
//  Recommendation.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/26
//

import Foundation
import Tagged

// the catalogue's own series id. tagged so it cannot be mistaken for a
// SeriesRecord.ID, which is Int64 and means something entirely different - and
// because for a MangaBaka-linked series this value IS SeriesTrackerRecord.remoteId
typealias CatalogID = Tagged<CatalogSeries, Int32>
enum CatalogSeries {}

// what the engine hands back. deliberately carries no SeriesRecord and no cover
// from our database: a recommendation is usually a series the reader does not
// own, so it has to be renderable from the catalogue alone
struct Recommendation: Sendable, Identifiable, Hashable, Codable {
    let catalogId: CatalogID
    // an index into this bundle, and only this bundle. row order is not stable
    // across catalogue snapshots, so this must never be persisted - catalogId is
    // the durable one
    let row: Int

    let title: String
    let authors: [String]
    let artists: [String]
    let cover: URL?
    let synopsis: String?
    let tags: [String]

    let classification: Classification
    let publication: Publication
    let year: Int?
    let format: CatalogFormat
    let register: RegisterAxis

    // standard deviations above this seed's field, not a 0...1 quantity. each
    // block is z-scored within one query, so a score is meaningless next to
    // another seed's and thresholding on it says nothing
    let score: Float
    // the 0...1 one, and display only. the era block is deliberately excluded -
    // including it made a title that merely shared a publication year read as a
    // 46% content match
    let confidence: Float
    let blocks: Blocks

    var id: CatalogID { catalogId }

    struct Blocks: Sendable, Hashable, Codable {
        let tag: Float
        let embedding: Float
        let era: Float
    }

    static func == (lhs: Recommendation, rhs: Recommendation) -> Bool {
        lhs.catalogId == rhs.catalogId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(catalogId)
    }
}

// how the seed was arrived at, which is the difference between "the model was
// wrong" and "this series had four usable tags". a per-query fact, so it lives
// here rather than being repeated on twenty results
enum Seed: Sendable {
    case linked(CatalogID, row: Int)
    case resolved(row: Int, matched: String, votes: Int)
    case projected(encoded: Int, dropped: Int)

    var row: Int? {
        switch self {
        case .linked(_, let row), .resolved(let row, _, _): row
        case .projected: nil
        }
    }
}

struct RecommendationSet: Sendable {
    let seed: Seed
    // the catalogue id the seed resolved to, for both cases that resolve at all.
    // Seed carries it only for .linked - .resolved holds a row, and turning a row
    // into an id needs the bundle, which the recommender has and no caller does
    let seedCatalogId: CatalogID?
    // how much of the model actually ran. a projected seed has used == wTagEff
    // and one block out of three
    let wTagEff: Float
    let used: Float
    let results: [Recommendation]
}
