//
//  MangaBallTests.swift
//  aletheiaTests
//
//  Created by Angelo Carasig on 11/8/2026.
//

import Testing
import Foundation
@testable import aletheia

// three parsers whose failures are all silent on a live source: a query the waf
// eats, a language relabelled rather than dropped, and an upstream parse bug
// arriving as a chapter number. none of them need the network
@Suite("MangaBall")
struct MangaBallTests {

    @Test("drops only the denied token, and only when it stands alone")
    func sanitisesQueries() {
        #expect(MangaBallSource.sanitized("the system") == "the")
        #expect(MangaBallSource.sanitized("System of Blades") == "of Blades")
        // the possessive is normalised away to match, both spellings of it
        #expect(MangaBallSource.sanitized("system\u{2019}s edge") == "edge")
        #expect(MangaBallSource.sanitized("the system's edge") == "the edge")
        // plurals and embedded forms do not trigger the block, so they stay
        #expect(MangaBallSource.sanitized("systems systemic") == "systems systemic")
        // nothing to drop, which is what tells the caller a new word is live
        #expect(MangaBallSource.sanitized("solo leveling") == "solo leveling")
    }

    @Test("maps the site's own language spellings and drops the rest")
    func mapsLanguages() {
        #expect(MangaBallSource.language("en") == .english)
        #expect(MangaBallSource.language("zh") == .chinese)
        // the site spells these jp and kr in its own filters
        #expect(MangaBallSource.language("jp") == .japanese)
        #expect(MangaBallSource.language("kr") == .korean)
        #expect(MangaBallSource.language("ja") == .japanese)
        #expect(MangaBallSource.language("ko") == .korean)
        // dropped, never downgraded to english
        #expect(MangaBallSource.language("es-419") == nil)
        #expect(MangaBallSource.language("pt-br") == nil)
        #expect(MangaBallSource.language(nil) == nil)
    }

    @Test("rejects a chapter number wildly outside its series' own range")
    func boundsChapterNumbers() {
        let real = (1...261).map(Double.init)
        let ceiling = MangaBallSource.ceiling(for: real + [8217])
        #expect(8217 > ceiling)
        #expect(261 <= ceiling)

        // a legitimately four-digit webtoon scales the bound with it
        let long = (1...4000).map(Double.init)
        #expect(4000 <= MangaBallSource.ceiling(for: long))

        // a short series never bounds below the floor
        #expect(120 <= MangaBallSource.ceiling(for: [1, 2, 3]))
    }
}
