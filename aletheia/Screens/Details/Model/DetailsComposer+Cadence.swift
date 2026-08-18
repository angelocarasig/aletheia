//
//  DetailsComposer+Cadence.swift
//  aletheia
//
//  Created by Angelo Carasig on 15/8/26
//

import Observation
import SwiftUI

extension DetailsComposer {
    // when the next chapter is likely, inferred from this series' own release
    // history. a cadence is observed; a schedule is published, and nobody
    // publishes one for scanlated work - which is why this exists at all and why
    // it never uses the word schedule
    //
    // its own child rather than part of Chapters because it reads two slices of
    // the bundle: chapter dates for the arithmetic, and supplier publication
    // state for whether an estimate should be made at all
    @MainActor
    @Observable
    final class Cadence: DetailsApplying {
        private(set) var state: State = .none
        // the estimate itself, kept beside the state because a debug surface
        // wants them and the copy layer wants only the state
        private(set) var interval: Double?
        private(set) var dispersion: Double?

        // the events this was last computed from. the observation re-fires on
        // every progress tick - reading a page writes to chapter - and none of
        // those writes moves a release date, so the work is skipped unless the
        // dates themselves changed
        @ObservationIgnored private var events: [Date] = []
        // what a forced run needs, kept rather than the whole bundle
        @ObservationIgnored private var claim: (value: Publication, attribution: String?)?

        // a forced answer outlives nothing. deliberately in memory: a guess the
        // reader asked for once must not quietly become the app's stated opinion
        // on the next launch, and there is no column to invalidate when a
        // chapter lands
        private(set) var forced: State?

        enum State: Equatable {
            // nothing known and nothing to say about why - the slot stays empty
            // every case says something. an empty slot on some series and a
            // sentence on others reads as the feature being broken, and the
            // reader has no way to tell which it is
            case none
            // carries which ending and whose claim it is. bare "Completed" in a
            // slot that means "when is the next chapter" reads as "never, you
            // have it all" - and whether our copy is whole is a different
            // question that nothing here can answer. gap detection finds
            // interior holes; nothing finds trailing truncation
            case finished(Publication, source: String?)
            // carries the RELEASE count, not the chapter count. three chapters
            // posted within three minutes are one release and no gap at all,
            // and "not enough chapters" is a plain lie to someone looking at
            // three of them
            case sparse(releases: Int)
            // the three reasons a date cannot be named, kept apart because they
            // are different facts about the next chapter and one label for all
            // three said nothing about any of them
            case overdue(by: Int)
            case irregular
            case dormant(since: Date)
            case predicted(Date, Confidence)
            // stated by a supplier, never inferred. the attribution is the whole
            // point - an unattributed claim reads as the app's own voice, which
            // is exactly the authority it has not got
            case hiatus(source: String?)
        }

        enum Confidence: Equatable {
            case high
            case medium
        }

        // from DetailsApplying
        // the answer on screen. a forced run wins until the screen goes away
        var current: State { forced ?? state }

        // only where the maths produced no date. recomputing identical inputs
        // returns an identical answer, so on predicted and overdue the control
        // would be visibly inert
        var canForce: Bool {
            // nothing to force with. one release has no gap, so a forced run
            // returns the identical refusal - which is exactly the inert control
            // the button is meant to avoid being
            guard events.count >= Limits.forcedEvents else { return false }
            switch current {
            case .predicted, .overdue: return false
            default: return true
            }
        }

        // try where the arithmetic never ran, retry where it ran and declined
        var forceGlyph: String {
            switch current {
            case .irregular, .dormant: "arrow.clockwise"
            default: "wand.and.sparkles"
            }
        }

        // ignores the supplier's claim and drops to a single gap, because the
        // reader asking is different from the app volunteering
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

// MARK: - Derivation

extension DetailsComposer.Cadence {
    fileprivate enum Limits {
        // one release event, not one chapter. measured 2026-08-15 across 2,570
        // chapters: 48h beats the 12h the spec asked for on every metric at no
        // cost in coverage - median error 0.81d to 0.40d - because a scanlator
        // clearing a backlog does it over a night and a morning, not an hour
        static let batchHours: Double = 48
        static let window = 10
        static let minimumEvents = 4
        // a forced run accepts one gap. statistically that is nothing, which is
        // why the app never volunteers it - but a reader who taps has asked for
        // the best available answer rather than for a good one
        static let forcedEvents = 2
        // relative, never fixed. a flat 21 days classifies every gap of a monthly
        // series as a break, which empties the in-season set and leaves the
        // median undefined
        static let breakFloor: Double = 21
        static let breakFactor: Double = 3
        // dormancy. the absolute floor is load-bearing: 4x alone declares a
        // near-daily series dead after five days, and one constant has to cover
        // daily through bi-monthly
        static let dormantFloor: Double = 90
        static let dormantFactor: Double = 4
        // mean absolute deviation over the median, on the in-season set. scale
        // free, so it behaves the same at 1 day and at 45. measured across the
        // library: below 0.15 the estimate lands within a quarter day, above 0.40
        // it misses by nine
        static let tight: Double = 0.15
        static let loose: Double = 0.40
    }

    fileprivate struct Resolved {
        let state: State
        let interval: Double?
        let dispersion: Double?
    }

    // one release event per moment, not per chapter. the earliest publication
    // per number collapses origins - the same chapter mirrored by three sources
    // is one release - and the batch window then folds a backlog dump into the
    // single event it actually was
    fileprivate static func events(in stored: DetailsComposer.Stored) -> [Date] {
        var earliest: [Double: Date] = [:]
        for row in stored.chapters {
            // a parse failure lands on distantPast and would otherwise inject a
            // ~730,000 day gap that becomes the predicted interval
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

        // a finished work has no next chapter. checked before the arithmetic so a
        // completed series never reaches the overdue branch, which would report
        // its final chapter as a silence
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
            // no releases at all is a different silence from too few: one has not
            // been fetched, the other has and has nothing to work with
            return Resolved(
                state: events.isEmpty ? .none : .sparse(releases: events.count),
                interval: nil, dispersion: nil)
        }

        let gaps = zip(events, events.dropFirst()).map { $1.timeIntervalSince($0) / 86400 }
        let recent = Array(gaps.suffix(Limits.window))
        // two passes, and the order is what makes it work: the provisional median
        // sets a threshold in the series' own units, and only then is the real
        // interval taken over what sits below it
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

        // past one full cadence there is no evidence the cadence still holds, so
        // the estimate stops and the observation takes over. rolling it forward
        // would assert a rhythm that has already been contradicted once
        // order matters: dormancy outranks lateness, and both outrank a spread
        // that would have declined to name a date anyway
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

        // one gap has a deviation of zero by construction, so the tier would
        // read high off a single observation and name a bare date. anything this
        // thin is hedged regardless of what the arithmetic says
        let thin = seasonal.count < Limits.minimumEvents - 1
        let due = last.addingTimeInterval(gHat * 86400)
        return Resolved(
            state: .predicted(due, !thin && spread < Limits.tight ? .high : .medium),
            interval: gHat, dispersion: spread)
    }

    // the supplier the reader pinned for publication, else any that states one.
    // either kind can be named: publication arrives in a source's own details
    // response, so it is a claim that source is making rather than an inference
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

// MARK: - Copy

extension DetailsComposer.Cadence.State {
    // structured rather than one string, so the view can weight the value
    // differently from the label without markdown or interpolation - both of
    // which erase silently when composed, which is how the inflect trap keeps
    // catching people
    struct Display: Equatable {
        let glyph: String
        // LocalizedStringKey, not String. Text's StringProtocol overload neither
        // extracts into the catalog nor parses inflection markup, and it does
        // both silently - the whole of this copy would have shipped
        // untranslatable and no build would have said so
        let label: LocalizedStringKey
        // nil where the state has no figure to emphasise
        let value: LocalizedStringKey?
    }

    // two grammars only: "Next chapter ..." forward and "Last chapter ..." back.
    // confidence is carried by how SPECIFIC the sentence is rather than by a word
    // like "estimated" - a sure guess names a date, an unsure one hedges it
    // every line is about the NEXT chapter - either when it is expected, or why
    // that cannot be said. an earlier version answered "we cannot predict" with
    // a fact about the LAST chapter, which is a different question nobody asked
    var display: Display {
        switch self {
        case .none:
            // our copy is empty, which is not the same as the series having
            // released nothing - and the reader can only act on the first one
            return Display(
                glyph: "questionmark.circle",
                label: "No chapters to predict from", value: nil)

        case .finished(let publication, let source):
            // "Series" rather than a bare adjective, so it reads as a fact about
            // the work rather than about our copy of it. attributed the same way
            // the hiatus line is - an unattributed claim is the app's own voice
            // branches rather than one interpolated string: each arm has to be
            // its own literal or the key is built at runtime and never extracted
            let label: LocalizedStringKey
            switch (publication == .Cancelled, source) {
            case (true, let who?): label = "Series cancelled, per \(who)"
            case (true, nil): label = "Series cancelled"
            case (false, let who?): label = "Series completed, per \(who)"
            case (false, nil): label = "Series completed"
            }
            return Display(glyph: "checkmark.circle", label: label, value: nil)

        case .sparse(let releases):
            // one release means every chapter landed together, which is a
            // different fact from having too few and the only one the reader can
            // reconcile with what is on screen
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
            // an unattributed claim reads as the app's own voice, which is
            // authority it has not got. only a supplier that can be named says
            // this at all
            let label: LocalizedStringKey =
                source.map { "On hiatus, reported by \($0)" }
                ?? "On hiatus"
            return Display(glyph: "pause.circle", label: label, value: nil)

        case .dormant(let since):
            return Display(
                glyph: "moon.zzz",
                label: "No chapters since", value: Self.back(since))

        case .overdue(let days):
            // still a statement about the next chapter: it was expected and has
            // not arrived, which is the honest form of a prediction that missed
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

    // a date, not a weekday. "Monday" is ambiguous about which Monday the moment
    // it is more than a few days out, and it cannot be compared against the
    // chapter rows below, which are all dated
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

    // dormancy is months, never days - it only fires past 90 of them. a month
    // name is read at a glance where "no releases for 214 days" invites
    // arithmetic, and the year appears once it can no longer be assumed
    private static func back(_ date: Date) -> LocalizedStringKey {
        let sameYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        let text = date.formatted(
            sameYear
                ? .dateTime.month(.wide)
                : .dateTime.month(.wide).year())
        return "\(text)"
    }
}
