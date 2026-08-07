//
//  ReaderSeparator.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import CoreGraphics
import Foundation

// what a chapter boundary is made of. a stack of slots rather than one layout,
// so the things that will live here later - tracker sync above all - arrive as
// another section instead of a redesign.
//
// THE INVARIANT: which slots are PRESENT depends only on the boundary and the
// chapter list. never on travel direction, never on load state. a separator
// whose height changed when the reader turned round, or when a fetch landed,
// would move every item below it - the exact jump this reader was just fixed
// for. slots change what they SAY; they never change whether they exist
struct ReaderSeparatorModel: Equatable, Sendable {
    let boundary: ReaderBoundary
    var direction: ReadingDirection

    // present for every .after boundary in both directions, absent only at the
    // start of a series. reading it backward renders the chapter you are
    // returning into rather than the one you finished
    var terminal: Terminal?
    var continuity: Continuity?
    var gap: Gap?
    var destination: Destination

    struct Terminal: Equatable, Sendable {
        let number: Double
        let title: String
    }

    // consecutive chapters can come from different sources: best_chapter ranks
    // per chapter number by origin priority, so the scanlator and the image
    // quality can change under the reader without warning
    struct Continuity: Equatable, Sendable {
        var source: String?
        var scanlator: String?
        var language: String?

        var isEmpty: Bool {
            source == nil && scanlator == nil && language == nil
        }
    }

    struct Gap: Equatable, Sendable {
        let from: Double
        let to: Double
        let count: Int
    }

    enum Destination: Equatable, Sendable {
        case chapter(number: Double, title: String)
        case loading(number: Double?)
        case failed(ReaderError)
        case caughtUp
        case startOfSeries
    }

    var action: Action? {
        guard case let .failed(error) = destination else { return nil }
        return error.isRetryable ? .retry : nil
    }

    enum Action: Equatable, Sendable {
        case retry
    }
}

// MARK: - Measurement

// heights are declared, not measured. the layout needs an exact number before
// anything renders, so each slot contributes a known constant and the total is
// arithmetic.
//
// the destination box and the action row are FIXED and always counted, however
// little they happen to be showing - that is what keeps the total independent
// of state
extension ReaderSeparatorModel {
    enum Metrics {
        static let padding: CGFloat = 12
        static let spacing: CGFloat = 16
        static let terminal: CGFloat = 52
        static let continuity: CGFloat = 28
        static let gap: CGFloat = 44
        static let rule: CGFloat = 24
        static let destination: CGFloat = 96
        static let action: CGFloat = 44
    }

    // depends only on which slots the BOUNDARY has, never on direction or state
    var height: CGFloat {
        var slots: [CGFloat] = []

        if terminal != nil {
            slots.append(Metrics.terminal)
            slots.append(Metrics.rule)
        }
        if continuity?.isEmpty == false { slots.append(Metrics.continuity) }
        if gap != nil { slots.append(Metrics.gap) }

        // always reserved. a destination that resolves from spinner to chapter
        // card, or grows a retry button, must not change the height
        slots.append(Metrics.destination)
        slots.append(Metrics.action)

        let content = slots.reduce(0, +)
        let gaps = Metrics.spacing * CGFloat(max(0, slots.count - 1))
        return Metrics.padding * 2 + content + gaps
    }
}

// MARK: - Static facts

// what the host knows about a boundary and the engine cannot: gaps come from
// the full chapter list, and source/scanlator changes come from the database.
// computed once, then merged with whatever the engine knows at the time
struct ReaderBoundaryInfo: Equatable, Sendable {
    var continuity: ReaderSeparatorModel.Continuity?
    var gap: ReaderSeparatorModel.Gap?

    static let none = ReaderBoundaryInfo()
}

extension ReaderSeparatorModel.Gap {
    // compares integer parts, which is what makes hidden half-chapters a
    // non-issue without plumbing the setting through: the reader's list is
    // already filtered by best_chapter's isVisible, so a fractional delta is a
    // filtering artefact and only whole numbers can genuinely be missing.
    // 1 -> 2 with 1.5 hidden reads as no gap, which is correct
    static func between(_ previous: Double, _ next: Double) -> Self? {
        let low = previous.rounded(.down)
        let high = next.rounded(.down)
        let missing = Int(high - low) - 1
        guard missing >= 1 else { return nil }
        return .init(from: low + 1, to: high - 1, count: missing)
    }
}
