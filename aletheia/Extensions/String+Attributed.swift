//
//  String+Attributed.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Foundation

extension String {
    // remote input, so the parser gets a ceiling before it gets the bytes
    private static let attributedCap = 100_000

    // inline-only on purpose: .full collapses the \n\n paragraph breaks every
    // source uses, flattening a synopsis into one blob. inline parsing keeps
    // whitespace verbatim and still resolves **bold** and [text](url)
    func toAttributed() -> AttributedString {
        guard count <= Self.attributedCap else { return AttributedString(self) }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: self, options: options)) ?? AttributedString(self)
    }
}
