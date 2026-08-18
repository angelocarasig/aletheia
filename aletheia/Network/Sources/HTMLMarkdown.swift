//
//  HTMLMarkdown.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import Foundation
import SwiftSoup

enum HTMLMarkdown {
    static func from(_ html: String) -> String {
        guard let body = try? SwiftSoup.parseBodyFragment(html).body() else { return "" }
        var out = ""
        try? append(body, into: &out)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func append(_ node: Node, into out: inout String) throws {
        for child in node.getChildNodes() {
            if let text = child as? TextNode {
                out += text.text()
            } else if let element = child as? Element {
                switch element.tagName() {
                case "br":
                    out += "\n"
                case "a":
                    out += "[\(try element.text())](\(try element.attr("href")))"
                case "strong", "b":
                    var inner = ""
                    try append(element, into: &inner)
                    out += "**\(inner)**"
                case "em", "i":
                    var inner = ""
                    try append(element, into: &inner)
                    out += "*\(inner)*"
                case "s", "del", "strike":
                    var inner = ""
                    try append(element, into: &inner)
                    out += "~~\(inner)~~"
                case "u":
                    var inner = ""
                    try append(element, into: &inner)
                    out += "<u>\(inner)</u>"
                default:
                    try append(element, into: &out)
                }
            }
        }
    }
}
