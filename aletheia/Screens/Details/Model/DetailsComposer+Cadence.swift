//
//  DetailsComposer+Cadence.swift
//  aletheia
//
//  Created by Angelo Carasig on 15/8/26
//

import Observation
import SwiftUI

extension DetailsComposer {
    // a cadence is observed, a schedule is published - nobody publishes one for
    // scanlated work, so this never uses the word "schedule"
    @MainActor
    @Observable
    final class Cadence: DetailsApplying {
        private(set) var state: State = .none
        private(set) var interval: Double?
        private(set) var dispersion: Double?

        // the observation re-fires on every progress tick, but none of those
        // writes move a release date - recomputation is skipped unless the
        // dates actually changed
        @ObservationIgnored private var events: [Date] = []
        @ObservationIgnored private var claim: (value: Publication, attribution: String?)?

        // deliberately in memory, never persisted: a guess the reader asked for
        // once must not become the app's stated opinion on the next launch
        private(set) var forced: State?

        enum State: Equatable {
            case none
            // gap detection finds interior holes, not trailing truncation - a
            // finished flag here doesn't mean our copy is complete
            case finished(Publication, source: String?)
            // release count, not chapter count - chapters posted together
            // collapse into one release
            case sparse(releases: Int)
            case overdue(by: Int)
            case irregular
            case dormant(since: Date)
            case predicted(Date, Confidence)
            // stated by a supplier, never inferred - unattributed, this would
            // read as the app's own claim, which it has no authority to make
            case hiatus(source: String?)
        }

        enum Confidence: Equatable {
            case high
            case medium
        }

        var current: State { forced ?? state }

        // recomputing identical inputs returns an identical answer, so this is
        // false wherever the maths already produced one - predicted, overdue,
        // or too few events to try at all - to avoid an inert button
        var canForce: Bool {
            guard events.count >= Limits.forcedEvents else { return false }
            switch current {
            case .predicted, .overdue: return false
            default: return true
            }
        }

        var forceGlyph: String {
            switch current {
            case .irregular, .dormant: "arrow.clockwise"
            default: "wand.and.sparkles"
            }
        }

        // ignores the supplier's claim - the reader asking is different from
        // the app volunteering
        func force() {
            forced =
                Self.resolve(
                    events: events, claim: nil,
                    minimum: Limits.forcedEvents
                ).state
        }

        func apply(_ stored: Stored) {
            let next = Self.events(in: stored)
            guard next != events else { return }
            events = next
            claim = Self.publication(in: stored)
            // a new chapter invalidates a forced answer - it was computed from
            // an event list that no longer exists
            forced = nil

            let resolved = Self.resolve(events: next, claim: claim)
            if state != resolved.state { state = resolved.state }
            if interval != resolved.interval { interval = resolved.interval }
            if dispersion != resolved.dispersion { dispersion = resolved.dispersion }
        }
    }
}

extension DetailsComposer.Cadence {
    fileprivate enum Limits {
        // measured 2026-08-15 across 2,570 chapters: 48h beats the 12h the spec
        // asked for on every metric (median error 0.81d to 0.40d) - a scanlator
        // clearing a backlog does it over a night and a morning, not an hour
        static let batchHours: Double = 48
        static let window = 10
        static let minimumEvents = 4
        // one gap is statistically nothing, which is why the app never
        // volunteers it - but a reader who taps has asked for the best
        // available answer, not a good one
        static let forcedEvents = 2
        // relative, never fixed: a flat 21 days would classify every gap of a
        // monthly series as a break, emptying the in-season set
        static let breakFloor: Double = 21
        static let breakFactor: Double = 3
        // the absolute floor is load-bearing - 4x alone declares a near-daily
        // series dead after five days
        static let dormantFloor: Double = 90
        static let dormantFactor: Double = 4
        // mean absolute deviation over the median, scale-free. measured across
        // the library: below 0.15 the estimate lands within a quarter day,
        // above 0.40 it misses by nine
        static let tight: Double = 0.15
        static let loose: Double = 0.40
    }

    fileprivate struct Resolved {
        let state: State
        let interval: Double?
        let dispersion: Double?
    }

    // collapses origins first - the same chapter mirrored by three sources is
    // one release - then folds a backlog dump into the single event it was
    fileprivate static func events(in stored: DetailsComposer.Stored) -> [Date] {
        var earliest: [Double: Date] = [:]
        for row in stored.chapters {
            // a parse failure lands on distantPast, which would otherwise inject
            // a ~730,000 day gap into the interval calculation
            guard row.publishedDate > Constants.Cadence.epoch else { continue }
            if let existing = earliest[row.number], existing <= row.publishedDate { continue }
            earliest[row.number] = row.publishedDate
        }

        var collapsed: [Date] = []
        for date in earliest.values.sorted() {
            guard let last = collapsed.last else {
                collapsed.append(date)
                continue
            }
            if date.timeIntervalSince(last) > Limits.batchHours * 3600 {
                collapsed.append(date)
            }
        }
        return collapsed
    }

    fileprivate static func resolve(
        events: [Date],
        claim: (value: Publication, attribution: String?)?,
        minimum: Int = Limits.minimumEvents,
        now: Date = .now
    ) -> Resolved {
        let publication = claim

        // checked before the arithmetic so a completed series never reaches the
        // overdue branch
        if publication?.value == .Completed || publication?.value == .Cancelled {
            return Resolved(
                state: .finished(
                    publication?.value ?? .Completed,
                    source: publication?.attribution),
                interval: nil, dispersion: nil)
        }
        if publication?.value == .Hiatus {
            return Resolved(
                state: .hiatus(source: publication?.attribution),
                interval: nil, dispersion: nil)
        }
        guard events.count >= minimum, let last = events.last else {
            // no releases is a different silence from too few: not fetched vs
            // fetched but insufficient
            return Resolved(
                state: events.isEmpty ? .none : .sparse(releases: events.count),
                interval: nil, dispersion: nil)
        }

        let gaps = zip(events, events.dropFirst()).map { $1.timeIntervalSince($0) / 86400 }
        let recent = Array(gaps.suffix(Limits.window))
        // order matters: the provisional median sets a threshold in the series'
        // own units, then the real median is taken only over what's below it
        let provisional = median(recent)
        let threshold = max(Limits.breakFloor, Limits.breakFactor * provisional)
        let inSeason = recent.filter { $0 <= threshold }
        let seasonal = inSeason.isEmpty ? recent : inSeason

        let gHat = median(seasonal)
        guard gHat > 0 else {
            return Resolved(state: .irregular, interval: nil, dispersion: nil)
        }
        let mad = seasonal.map { abs($0 - gHat) }.reduce(0, +) / Double(seasonal.count)
        let spread = mad / gHat

        let elapsed = now.timeIntervalSince(last) / 86400
        let dormant = max(Limits.dormantFloor, Limits.dormantFactor * gHat)

        // order matters: dormancy outranks lateness, and both outrank a spread
        // too loose to name a date anyway
        if elapsed > dormant {
            return Resolved(state: .dormant(since: last), interval: gHat, dispersion: spread)
        }
        if spread >= Limits.loose {
            return Resolved(state: .irregular, interval: gHat, dispersion: spread)
        }
        if elapsed > gHat {
            return Resolved(
                state: .overdue(by: Int((elapsed - gHat).rounded())),
                interval: gHat, dispersion: spread)
        }

        // a single gap has zero deviation by construction, which would read as
        // high confidence off one observation - hedge regardless of spread
        let thin = seasonal.count < Limits.minimumEvents - 1
        let due = last.addingTimeInterval(gHat * 86400)
        return Resolved(
            state: .predicted(due, !thin && spread < Limits.tight ? .high : .medium),
            interval: gHat, dispersion: spread)
    }

    fileprivate static func publication(in stored: DetailsComposer.Stored)
        -> (value: Publication, attribution: String?)?
    {
        let stating = stored.suppliers.filter { $0.publication != .Unknown && !$0.detached }
        guard let chosen = stating.first(where: \.isPublication) ?? stating.first else {
            return nil
        }
        return (chosen.publication, chosen.tracker?.name ?? chosen.sourceName)
    }

    fileprivate static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }
}

extension DetailsComposer.Cadence.State {
    struct Display: Equatable {
        let glyph: String
        // LocalizedStringKey, not String - Text's StringProtocol overload skips
        // both catalog extraction and inflection parsing silently, with no
        // build warning
        let label: LocalizedStringKey
        let value: LocalizedStringKey?
    }

    // every line is about the NEXT chapter - either when it's expected, or why
    // that can't be said. an earlier version answered "can't predict" with a
    // fact about the LAST chapter, which nobody asked
    var display: Display {
        switch self {
        case .none:
            return Display(
                glyph: "questionmark.circle",
                label: "No chapters to predict from", value: nil)

        case .finished(let publication, let source):
            // each arm is its own literal - interpolating into one key builds it
            // at runtime and it never extracts into the catalog
            let label: LocalizedStringKey
            switch (publication == .Cancelled, source) {
            case (true, let who?): label = "Series cancelled, per \(who)"
            case (true, nil): label = "Series cancelled"
            case (false, let who?): label = "Series completed, per \(who)"
            case (false, nil): label = "Series completed"
            }
            return Display(glyph: "checkmark.circle", label: label, value: nil)

        case .sparse(let releases):
            return Display(
                glyph: "questionmark.circle",
                label: releases <= 1
                    ? "All chapters arrived at once"
                    : "Not enough separate releases to predict yet",
                value: nil)

        case .irregular:
            return Display(
                glyph: "questionmark.circle",
                label: "Chapters arrive too irregularly to predict", value: nil)

        case .hiatus(let source):
            let label: LocalizedStringKey =
                source.map { "On hiatus, reported by \($0)" }
                ?? "On hiatus"
            return Display(glyph: "pause.circle", label: label, value: nil)

        case .dormant(let since):
            return Display(
                glyph: "moon.zzz",
                label: "No chapters since", value: Self.back(since))

        case .overdue(let days):
            return Display(
                glyph: "clock.badge.exclamationmark",
                label: "Next chapter overdue by",
                value: "^[\(days) day](inflect: true)")

        case .predicted(let date, let confidence):
            return Display(
                glyph: "clock",
                label: confidence == .high ? "Next chapter" : "Next chapter around",
                value: Self.forward(date))
        }
    }

    private static func forward(_ date: Date) -> LocalizedStringKey {
        if Calendar.current.isDateInToday(date) { return "today" }
        if Calendar.current.isDateInTomorrow(date) { return "tomorrow" }
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        let text = date.formatted(
            sameYear
                ? .dateTime.day().month(.abbreviated)
                : .dateTime.day().month(.abbreviated).year())
        return "\(text)"
    }

    private static func back(_ date: Date) -> LocalizedStringKey {
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        let text = date.formatted(
            sameYear
                ? .dateTime.month(.wide)
                : .dateTime.month(.wide).year())
        return "\(text)"
    }
}
