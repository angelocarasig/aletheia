//
//  SourceFilter.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

import Foundation

enum SourceFilter: Sendable, Hashable {
    case text(id: String, name: String)
    case number(id: String, name: String)
    case select(id: String, name: String, options: [Option])
    case multiSelect(id: String, name: String, options: [Option], canExclude: Bool)

    // describes the effect of ticking an option, not the rating of any one series -
    // Classification answers that, and answers it too coarsely here (erotica and
    // pornographic fold into one case, which is exactly where the gate below is drawn)
    enum Sensitivity: Sendable, Hashable {
        case none

        // fanservice, mature themes, a warning label like gore - the row is marked
        // in the UI but the adult gate stays shut
        case suggestive

        // selecting this necessarily returns pornographic content - the row is marked
        // and the source is permitted to stop excluding adult results. this is the
        // whole reason a search can return adult content at all, so an option marked
        // here by mistake is a silent safety bug, not a wrong colour
        case adult
    }

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

    // no id or name - an id looked like the request parameter, but every source
    // hardcodes that when it builds the url; the menu labels itself with the
    // selected option instead
    struct Sort: Sendable, Hashable {
        let options: [Option]
        let defaultSort: String
    }
}

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
    // sensitivity feeds the fingerprint because it decides whether a request may
    // return adult content - a change to it must be detectable
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
