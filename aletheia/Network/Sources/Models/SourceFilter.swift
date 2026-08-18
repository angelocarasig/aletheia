//
//  SourceFilter.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

/// a filter a source declares it supports (in its descriptor). the search UI
/// renders these generically; the user's choices come back as [FilterSelection].
enum SourceFilter: Sendable, Hashable {
    case text(id: String, name: String)
    case number(id: String, name: String)
    case select(id: String, name: String, options: [Option])
    case multiSelect(id: String, name: String, options: [Option], canExclude: Bool)

    /// what selecting an option pulls into the results. it describes the *effect of
    /// ticking*, not the rating of any one series - `Classification` answers that,
    /// and answers it too coarsely here (it folds erotica and pornographic into one
    /// case, which is exactly where the gate below is drawn).
    enum Sensitivity: Sendable, Hashable {
        /// an ordinary option. nothing it returns needs warning about.
        case none

        /// racy, but never pornographic - fanservice, mature themes, or a warning
        /// label like gore. the row is marked in the UI; the adult gate stays shut.
        /// most of what used to be flagged `nsfw` belongs here.
        case suggestive

        /// selecting this necessarily returns pornographic content - a rating option
        /// that names it, or a genre that is pornographic by definition. the row is
        /// marked *and* the source is permitted to stop excluding adult results.
        ///
        /// the narrow list: it is the whole reason a search can return adult content
        /// at all, so an option marked here by mistake is a silent safety bug rather
        /// than a wrong colour.
        case adult
    }

    /// a single option: a display label paired with the backend id sent in requests.
    struct Option: Sendable, Hashable, Identifiable {
        let id: String
        let name: String
        let sensitivity: Sensitivity

        init(id: String, name: String, sensitivity: Sensitivity = .none) {
            self.id = id
            self.name = name
            self.sensitivity = sensitivity
        }
    }

    /// how a source can order results: the options, and which one applies when
    /// the caller picks none - the source's "best match" or nearest equivalent.
    ///
    /// no id and no name. an id looked like the request parameter, but every
    /// source hardcodes that when it builds the url, and the axis name was only
    /// ever shown by a sort row that no longer exists - the menu labels itself
    /// with the selected option
    struct Sort: Sendable, Hashable {
        let options: [Option]
        let defaultSort: String
    }
}

// MARK: - Stable fingerprint (deterministic; feeds SourceDescriptor.fingerprint)

extension SourceFilter {
    var fingerprint: String {
        switch self {
        case .text(let id, let name):
            return "text:\(id):\(name)"
        case .number(let id, let name):
            return "number:\(id):\(name)"
        case .select(let id, let name, let options):
            return "select:\(id):\(name):\(options.fingerprint)"
        case .multiSelect(let id, let name, let options, let canExclude):
            return "multi:\(id):\(name):\(canExclude):\(options.fingerprint)"
        }
    }
}

extension SourceFilter.Sort {
    var fingerprint: String {
        "\(defaultSort):\(options.fingerprint)"
    }

    var defaultSelection: SortSelection {
        SortSelection(optionID: defaultSort)
    }
}

extension Array where Element == SourceFilter.Option {
    // sensitivity is in here where the `nsfw` flag it replaced was not. that flag
    // was a tint and nothing else; this one decides whether a request may return
    // adult content, so a change to it is exactly what the hash exists to show
    var fingerprint: String {
        map { "\($0.id)=\($0.name):\($0.sensitivity.fingerprint)" }.joined(separator: ",")
    }
}

extension SourceFilter.Sensitivity {
    var fingerprint: String {
        switch self {
        case .none: "n"
        case .suggestive: "s"
        case .adult: "a"
        }
    }
}
