//
//  MangaFireSigner.swift
//  aletheia
//
//  Created by Angelo Carasig on 13/8/2026.
//

import Foundation

// every /api/ path answers an unsigned request with 403 {"message": "Missing
// token."} - an application check, not cloudflare. the token is deterministic
// and stateless: no timestamp, no nonce, no session, no cookie, no user agent.
//
// this is not deobfuscation. the site signs inside a jscrambler bytecode vm
// and nothing here touches it - what follows reimplements the algorithm that vm
// performs, from constants a human extracted once. so the tables are data with
// a shelf life: mangafire rotated the previous scheme's keys three times in six
// weeks before replacing it wholesale. a rotation surfaces as a 403 on a request
// that still reproduces `reference`, which is why that test vector is here and
// not only in a test target this project does not yet build.
//
// see docs/sources/mangafire.md
enum MangaFireSigner {
    // the canonical string is NOT the request url, and the two differences are
    // the whole difficulty. sign `key[0]`/`key[1]` while sending `key[]`, and
    // sign the decoded value while sending the encoded one. either mistake is a
    // 403 that looks exactly like a rotated table
    static func sign(path: String, items: [URLQueryItem]) -> URLQueryItem {
        let sorted = items.enumerated()
            .sorted { left, right in
                // stable: equal keys keep the order the caller supplied, which
                // is what makes `key[0]`/`key[1]` mean the caller's first and
                // second value rather than an arbitrary pair
                left.element.name == right.element.name
                    ? left.offset < right.offset
                    : left.element.name < right.element.name
            }
            .map(\.element)

        var canonical = path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path

        if !sorted.isEmpty {
            var index = 0
            var previous = ""
            let pairs = sorted.map { item -> String in
                var name = item.name
                if name.hasSuffix("[]") {
                    if name != previous { index = 0 }
                    previous = name
                    name = String(name.dropLast(2)) + "[\(index)]"
                    index += 1
                }
                return "\(name)=\(item.value ?? "")"
            }
            canonical += "?" + pairs.joined(separator: "&")
        }

        return URLQueryItem(name: "vrf", value: token(for: canonical))
    }

    static func token(for canonical: String) -> String {
        var data = [UInt8](canonical.utf8)
        for stage in stages { data = stage.apply(to: data) }

        return Data(data).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // the published vector from aidoku's own unit test. a port that cannot
    // reproduce this must not be pointed at the network
    static let reference = (
        canonical:
            "/titles?content_rating[0]=safe&content_rating[1]=suggestive&limit=30&order[chapter_updated_at]=desc&page=1",
        token:
            "8sK3xtqdFZdOu6WNqS1bZ0shnUDqyRXMnh4NlZ7aYCPUhmAbm1C1qPzeL_OIIf0obIggCZIHJHIF_VdaYGWoz1D2WyKu2XhBqaoQcC-UzOL9vlMOE6MXU01kzYuIPwgPSvk_Z55Rw17nfA"
    )

    static var reproducesReference: Bool {
        token(for: reference.canonical) == reference.token
    }

    private static let prefix = "/api"

    private struct Stage {
        let table: [UInt8]
        let key: [UInt8]
        let iv: UInt8

        // byte substitution with output feedback - each output byte seeds the
        // next, so the stream is self synchronising and two inputs sharing a
        // prefix produce tokens sharing a prefix
        func apply(to data: [UInt8]) -> [UInt8] {
            guard !key.isEmpty, table.count == 256 else { return data }

            var out = [UInt8](repeating: 0, count: data.count)
            var previous = iv

            for index in data.indices {
                previous = table[Int(data[index] ^ key[index % key.count] ^ previous)]
                out[index] = previous
            }
            return out
        }
    }

    private static let stages: [Stage] = [
        Stage(table: decode(table1), key: decode(key1), iv: 0x5A),
        Stage(table: decode(table2), key: decode(key2), iv: 0x35),
        Stage(table: decode(table3), key: decode(key3), iv: 0xBA),
    ]

    private static func decode(_ value: String) -> [UInt8] {
        Data(base64Encoded: value).map { [UInt8]($0) } ?? []
    }

    // copied verbatim from keiyoushi's VrfSigner.kt, which is the one upstream
    // every reader ports from. never retype these
    private static let table1 =
        "yINlmUNho8VYJT+ibTIP+9ESiULpVEtMOoD6U6lRE0R/xwXo/Xp9NrUgC4cw/Lmo33vUyjUE40kUoEWIr/fxfNNcq2s79ShQ5NhNrFnJ4hXPwOu/SuXzIbuTQKGFvfm08E9jvCfqAtoDqvQq3dVWPQFmJjgvkISBeXY3BgANR+yVnjGbcxZ47d6kLNfZPIayTq3/YGySb1KuVZodWp/WGNAO5pfMcpaK53Hhs0allBszaMaxuouOwdxbwgxIw6YunSsXjI05Yi0j9j4eHKfSXR8Ifo/Od+8iamRfCXTyvm7NGRGYdcQ0ywcK/u6RXhrbcCm4t2eCtrDgQVecJGkQ+A=="
    private static let key1 = "0Ec58JOY3uBzJK9m3zqIOpdlF7UFiax9DmA="

    private static let table2 =
        "IUFltCxD3Oc2cwCgkJffthaOg9cgPUb0LgW6H/VtfcF0kc5F25t+aWj6JH9VOhOaY0rAFdUxlDnl5BLNvwEJvQtP5qcw7vdb/K+chnbwnspSHT8mz5lqwz41TezG0hkO06FTjJZhsyNuFLDpD2ZZxQj/QIRcF90zpmQ7Byu483WsQqUE0C342HL+JXngRB6fRzxRyVTaKu83h7UYTJ0QMt6ixFh6S3F8gqkKwrGTL3jHNBsD45UnifK8+RGtishQV2K3rujLKEkiZxpr2dYcudFW4oFsDKhad3CLBvuyTqsCo4B7mL5IKQ1vXo/MOOvq1I1d8ar9X6Ttu5KF4fZgiA=="
    private static let key2 = "AAdjb1iPY8CiDmq9H34tKTBF8a3oDQ=="

    private static let table3 =
        "NQHlu1/wVO5EmkwQymF810qqY2xG1k2obcas4Z9mCsPEIFl9pRIjFxbJ7ybMHbBckT5Ton85E0FOeHezbh/mjlEYpmpnlXOS8dgrqeq2KfxImTh1YK9y0PeMNhzA1OQzSY9brYOJq/l2QnE/hwOeZIhPixVSKIUlDb5vLcH6RWKxkIEMuP0bDwIqQ71AJJaEaMJL7A6YtyIwoRT+L5v4aZzodN/0+3nOGsfblFjgxSfPzVDjNFeNl5P26+kEC/8AHgdrpAbt3hHz3HrRN1Y6e+JHgF7ncFWnoF0y3THL1S71WgWGCa6KtSzTCCG58n68nTyj2T3Sshk7utqCtMi/ZQ=="
    private static let key3 = "DELOJgPsVaCcblDtTGMdHzM="
}
