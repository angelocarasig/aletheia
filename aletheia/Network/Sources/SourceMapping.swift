//
//  SourceMapping.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation

extension Classification {
    init(rating: String?) {
        switch (rating ?? "").lowercased() {
        case "safe": self = .Safe
        case "suggestive": self = .Suggestive
        case "erotica", "pornographic": self = .Explicit
        default: self = .Unknown
        }
    }
}

extension Publication {
    init(status: String?) {
        switch (status ?? "").lowercased() {
        case "releasing", "ongoing": self = .Ongoing
        case "finished", "completed": self = .Completed
        case "on_hiatus", "on hiatus", "hiatus": self = .Hiatus
        case "discontinued", "cancelled": self = .Cancelled
        default: self = .Unknown
        }
    }
}
