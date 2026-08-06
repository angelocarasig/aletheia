//
//  RelativeDate.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation

enum RelativeDate {
    static func parse(_ text: String?) -> Date? {
        guard let text else { return nil }
        let value = Int(text.prefix { $0.isNumber }) ?? 0
        let unit = text.drop { $0.isNumber || $0.isWhitespace }.prefix { $0.isLetter }.lowercased()

        let component: Calendar.Component
        switch unit {
        case let u where u.hasPrefix("mo"): component = .month
        case let u where u.hasPrefix("y"): component = .year
        case let u where u.hasPrefix("w"): component = .weekOfYear
        case let u where u.hasPrefix("d"): component = .day
        case let u where u.hasPrefix("h"): component = .hour
        case let u where u.hasPrefix("m"): component = .minute
        case let u where u.hasPrefix("s"): component = .second
        default: return nil
        }
        return Calendar.current.date(byAdding: component, value: -value, to: Date())
    }
}
