//
//  ReaderSeparator.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation
import SwiftUI
import UIKit

// what a chapter boundary is made of. a stack of slots rather than one layout,
// so the things that will live here later - tracker sync above all - arrive as
// another section instead of a redesign.
//
// THE INVARIANT: which slots are PRESENT depends only on the boundary and the
// chapter list. never on travel direction, never on load state. a separator
// whose height changed when the reader turned round, or when a fetch landed,
// would move every item below it. slots change what they SAY; they never
// change whether they exist
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

    // the reading-event write for the finished chapter, rendered beside the
    // terminal number going forward. content only, never height - nil renders
    // nothing, which is every separator until the reader wires the insert
    var event: EventStatus?

    // whether to offer marking the series completed. two conditions, both host
    // facts: you have not already said completed, and an origin says the work
    // itself is over.
    //
    // what it deliberately does NOT check is whether our copy is whole - a
    // source can call a work complete while holding two thirds of it, and
    // without a tracker (optional, and absent for most series) there is no total
    // to check that claim against. gaps and truncation are therefore not
    // conditions: the reader states only what it can verify - that you are level
    // with what exists - and the offer lets the one party who actually knows say
    // the rest. content only, and the action row is reserved either way, so this
    // moves nothing
    var completable: Bool = false

    // one row per linked tracker, non-optional and never rebuilt from load
    // state: linkage is a series fact known before the first page renders, so
    // the rows exist from the moment the separator is built and only their
    // status glyph changes. a row that appeared when a push started would move
    // every item below it mid-read
    var trackers: [Tracker] = []

    struct Terminal: Equatable, Sendable {
        let number: Double
        let title: String
    }

    struct Tracker: Equatable, Sendable, Identifiable {
        let id: String
        let name: String
        // asset name for the service's tile, drawn in its own colours - a logo
        // tinted to match its surroundings is no longer a logo. the monochrome
        // *Mark variants exist alongside for surfaces that do want a template.
        // nil falls back to the name alone
        var icon: String?
        var state: State

        // five states, all glyph-distinct, so the colour is never the only
        // channel. skipped is not a tick: it would claim an achievement the
        // push explicitly declined to make.
        //
        // errored carries its own reason rather than a generic word, and it goes
        // in the slot the word already occupies - a second line would make the
        // row's height depend on whether something failed, which is the one thing
        // this band is not allowed to do.
        //
        // signedOut is split OUT of skipped because the two have opposite
        // answers: skipped resolves itself on the next chapter, and this one
        // never resolves until the reader does something a reader cannot do from
        // inside the reader
        enum State: Equatable, Sendable {
            case loading
            case tracked
            case skipped
            case errored(String)
            case signedOut
        }
    }

    enum EventStatus: Equatable, Sendable {
        case recording
        case recorded
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

    // identified by its own range: there is one gap per boundary, and the range
    // is what a sheet presented for it is about
    struct Gap: Equatable, Sendable, Identifiable {
        var id: String { "\(from)-\(to)" }

        let from: Double
        let to: Double
        let count: Int
        // the sources that were asked and came back without these chapters.
        // naming them is the difference between "something is missing" and
        // "nothing you have installed carries this" - the second is actionable,
        // the first sounds like a fault
        var sources: [String] = []
    }

    enum Destination: Equatable, Sendable {
        case chapter(number: Double, title: String)
        case loading(number: Double?)
        case failed(ReaderError)
        // one ending, deliberately. "finished" would be a claim about the work;
        // caught up is a fact about our copy of it, and it stays true whether
        // the series ended, is mid-translation, or is still running
        case caughtUp
        case startOfSeries
    }

    var action: Action? {
        switch destination {
        case let .failed(error): error.isRetryable ? .retry : nil
        case .caughtUp: completable ? .complete : nil
        default: nil
        }
    }

    enum Action: Equatable, Sendable {
        case retry
        case complete
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
        // between members of one group, tighter than the gap between groups
        static let group: CGFloat = 6
        static let terminal: CGFloat = 52
        static let continuity: CGFloat = 20
        // linkage is stable for the session, so a height that depends on how
        // many services are linked is still a declared height
        static let trackerRow: CGFloat = 22
        static let trackerGap: CGFloat = 4
        static let rule: CGFloat = 24
        // sized to the tallest destination it has to hold - a chapter card with
        // caption, number and title is ~61. a centred block in an oversized box
        // drifts, so the slack has to stay small
        static let destination: CGFloat = 64
        static let action: CGFloat = 44

        // the text-bearing slots are constants at the default size, not at every
        // size: a 52pt box holding a headline overflows once that headline is
        // scaled for AX5, and this layout cannot grow to meet it. scaling here
        // keeps the height DECLARED - one constant per content-size category
        // rather than one constant full stop - so it is still known before
        // anything renders and still cannot move the scroll.
        //
        // the structural terms are deliberately left alone: padding, spacing and
        // the rule are air and a hairline, and scaling those only inflates the
        // band without making a word more legible
        static func scaled(_ value: CGFloat, _ category: UIContentSizeCategory) -> CGFloat {
            UIFontMetrics.default.scaledValue(
                for: value,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: category)
            )
        }
    }

    // depends only on which slots the BOUNDARY has, never on direction or state.
    //
    // two groups, not a list: what is behind you (the chapter you finished and
    // where it was recorded) and what is ahead (the chapter you are entering,
    // plus anything that describes it). a slot belongs to one of them, and the
    // group is what the reader sees rather than the slots
    var height: CGFloat { height(for: .large) }

    func height(for category: UIContentSizeCategory) -> CGFloat {
        var slots: [CGFloat] = []

        if terminal != nil {
            slots.append(behind(for: category))
            slots.append(Metrics.rule)
        }

        slots.append(ahead(for: category))
        slots.append(Metrics.scaled(Metrics.action, category))

        let content = slots.reduce(0, +)
        let gaps = Metrics.spacing * CGFloat(max(0, slots.count - 1))
        return Metrics.padding * 2 + content + gaps
    }

    // internal, because the view frames the group to it: the space is reserved
    // whatever is drawn inside, so backward travel - which has no push to report
    // and hides the rows - centres what it does have rather than leaving a hole
    // under it. the cell is sized from the forward model before direction is
    // even known, so shrinking here would only move the hole, not close it
    func behind(for category: UIContentSizeCategory) -> CGFloat {
        let terminalHeight = Metrics.scaled(Metrics.terminal, category)
        guard !trackers.isEmpty else { return terminalHeight }

        let row = Metrics.scaled(Metrics.trackerRow, category)
        let rows = CGFloat(trackers.count) * row
        let gaps = Metrics.trackerGap * CGFloat(trackers.count - 1)
        return terminalHeight + Metrics.group + rows + gaps
    }

    // the destination is always reserved - a spinner resolving to a chapter card,
    // or growing an action, must not change the height. a gap is not here: it
    // describes the crossing rather than the chapter, so it rides the rule and
    // costs nothing
    private func ahead(for category: UIContentSizeCategory) -> CGFloat {
        var height = Metrics.scaled(Metrics.destination, category)
        if continuity?.isEmpty == false {
            height += Metrics.group + Metrics.scaled(Metrics.continuity, category)
        }
        return height
    }
}

// SwiftUI reports the reader's text size as DynamicTypeSize while the metrics
// above are keyed to UIKit's category, because the collection view sizes cells
// from its own trait collection. one mapping so both halves ask the same question
extension UIContentSizeCategory {
    init(_ size: DynamicTypeSize) {
        self = switch size {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
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
