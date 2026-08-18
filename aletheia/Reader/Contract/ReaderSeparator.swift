//
//  ReaderSeparator.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation
import SwiftUI
import UIKit

// THE INVARIANT: which slots are PRESENT depends only on the boundary and the
// chapter list, never on travel direction or load state - a separator whose
// height changed on turnaround or on a fetch landing would move every item
// below it. slots change what they SAY; they never change whether they exist
struct ReaderSeparatorModel: Equatable, Sendable {
    let boundary: ReaderBoundary
    var direction: ReadingDirection

    // present for every .after boundary in both directions, absent only at the
    // series start - read backward it renders the chapter you're returning
    // into, not the one you finished
    var terminal: Terminal?
    var continuity: Continuity?
    var gap: Gap?
    var destination: Destination

    // the reading-event write for the finished chapter, rendered beside the
    // terminal number. content only, never height - nil renders nothing
    var event: EventStatus?

    // NOT the travel direction - what was recorded stays recorded, so turning
    // round and coming back finds the same tick and the same tracker rows
    var crossed: Bool = false

    // two host facts: not already marked completed, and an origin says the
    // work is over. deliberately does NOT check whether our copy is whole - a
    // source can call a work complete while holding two thirds of it, and
    // without a tracker there is no total to check that claim against, so the
    // reader states only that you're level with what exists
    var completable: Bool = false

    // linkage is a series fact known before the first page renders, so rows
    // exist from the moment the separator is built and only their status glyph
    // changes - a row appearing once a push started would move everything below it
    var trackers: [Tracker] = []

    struct Terminal: Equatable, Sendable {
        let number: Double
        let title: String
    }

    struct Tracker: Equatable, Sendable, Identifiable {
        let id: String
        let name: String
        var icon: String?
        var state: State

        // skipped is not a tick - it would claim an achievement the push
        // declined to make. errored carries its own reason in the slot the
        // word already occupies, rather than a second line, since row height
        // must not depend on whether something failed. signedOut is split out
        // of skipped because the two resolve differently: skipped clears on
        // the next chapter, signedOut never clears until the reader signs back in
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

    // best_chapter ranks per chapter number by origin priority, so the
    // scanlator and image quality can change between consecutive chapters
    struct Continuity: Equatable, Sendable {
        var source: String?
        var scanlator: String?
        var language: String?

        var isEmpty: Bool {
            source == nil && scanlator == nil && language == nil
        }
    }

    struct Gap: Equatable, Sendable, Identifiable {
        var id: String { "\(from)-\(to)" }

        let from: Double
        let to: Double
        let count: Int
        var sources: [String] = []
    }

    enum Destination: Equatable, Sendable {
        case chapter(number: Double, title: String)
        case loading(number: Double?)
        case failed(ReaderError)
        // "finished" would be a claim about the work; caught up is a fact
        // about our copy of it, true whether the series ended, is
        // mid-translation, or is still running
        case caughtUp
        case startOfSeries
    }

    var action: Action? {
        switch destination {
        case .failed(let error): error.isRetryable ? .retry : nil
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

// heights are declared, not measured, so each slot contributes a known
// constant and the total is arithmetic. the destination box and action row
// are FIXED and always counted, however little they show, keeping the total
// independent of state
extension ReaderSeparatorModel {
    enum Metrics {
        static let padding: CGFloat = 12
        static let spacing: CGFloat = 16
        static let group: CGFloat = 6
        static let terminal: CGFloat = 52
        static let continuity: CGFloat = 20
        // linkage is stable for the session, so a height that depends on
        // trackers.count is still a declared height
        static let trackerRow: CGFloat = 22
        static let trackerGap: CGFloat = 4
        static let rule: CGFloat = 24
        // sized to the tallest destination it has to hold (~61); a centred
        // block in an oversized box drifts, so the slack has to stay small
        static let destination: CGFloat = 64
        static let action: CGFloat = 44

        // only the text-bearing slots scale with content size - a 52pt box
        // holding a headline overflows once scaled for AX5. structural terms
        // (padding, spacing, rule) are left alone since they inflate the band
        // without making anything more legible
        static func scaled(_ value: CGFloat, _ category: UIContentSizeCategory) -> CGFloat {
            UIFontMetrics.default.scaledValue(
                for: value,
                compatibleWith: UITraitCollection(preferredContentSizeCategory: category)
            )
        }
    }

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

    // internal - the view frames the group to this reserved space, so a
    // boundary with no rows to show centres what it has rather than leaving a
    // hole; the cell is sized once, before that's known, so shrinking here
    // would only move the hole rather than close it
    func behind(for category: UIContentSizeCategory) -> CGFloat {
        let terminalHeight = Metrics.scaled(Metrics.terminal, category)
        guard !trackers.isEmpty else { return terminalHeight }

        let row = Metrics.scaled(Metrics.trackerRow, category)
        let rows = CGFloat(trackers.count) * row
        let gaps = Metrics.trackerGap * CGFloat(trackers.count - 1)
        return terminalHeight + Metrics.group + rows + gaps
    }

    // a gap is not counted here - it describes the crossing rather than the
    // chapter, so it rides the rule instead and costs nothing
    private func ahead(for category: UIContentSizeCategory) -> CGFloat {
        var height = Metrics.scaled(Metrics.destination, category)
        if continuity?.isEmpty == false {
            height += Metrics.group + Metrics.scaled(Metrics.continuity, category)
        }
        return height
    }
}

// SwiftUI reports text size as DynamicTypeSize; the metrics above are keyed to
// UIKit's category since the collection view sizes cells from its own trait
// collection - one mapping so both halves ask the same question
extension UIContentSizeCategory {
    init(_ size: DynamicTypeSize) {
        self =
            switch size {
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

struct ReaderBoundaryInfo: Equatable, Sendable {
    var continuity: ReaderSeparatorModel.Continuity?
    var gap: ReaderSeparatorModel.Gap?

    static let none = ReaderBoundaryInfo()
}

extension ReaderSeparatorModel.Gap {
    // compares integer parts only: the reader's list is already filtered by
    // best_chapter's isVisible, so a fractional delta is a filtering artefact,
    // not a genuine gap - 1 -> 2 with 1.5 hidden reads as no gap, correctly
    static func between(_ previous: Double, _ next: Double) -> Self? {
        let low = previous.rounded(.down)
        let high = next.rounded(.down)
        let missing = Int(high - low) - 1
        guard missing >= 1 else { return nil }
        return .init(from: low + 1, to: high - 1, count: missing)
    }
}
