//
//  TrackerCredential.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Foundation

// what one signed-in account is, stored in the keychain under the tracker's slug
// and nowhere else. the account details ride along because the settings screen
// has to name who is signed in without a request
struct TrackerCredential: Sendable, Codable, Equatable {
    var accessToken: String
    // myanimelist rotates this on every refresh and the new one must be kept.
    // anilist has none at all - its token simply expires after a year and the
    // reader signs in again, which is a routine event there rather than a fault
    var refreshToken: String?
    var expiresDate: Date?

    var remoteUserId: Int64
    var username: String
    var avatar: URL?
    var scoreFormat: ScoreFormat

    // stamped at receipt rather than trusting a served expires_in, and only used
    // to decide when to refresh ahead of a request
    var issuedDate: Date = .now

    func isValid(skew: TimeInterval = 300) -> Bool {
        guard let expiresDate else { return true }
        return Date() < expiresDate.addingTimeInterval(-skew)
    }

    var isRefreshable: Bool {
        refreshToken != nil
    }

    // the one signature both services share once they are out of road, and the
    // reason a rejected refresh clears the refresh token rather than deleting the
    // credential: anilist arrives here when its year runs out and myanimelist
    // when its refresh token is refused, and neither can be told from a never
    // connected account if the item is gone. deliberate sign-out still deletes,
    // so no item at all means never connected or disconnected on purpose
    var needsReauthentication: Bool {
        !isValid() && !isRefreshable
    }

    func apply(to request: inout URLRequest) {
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
    }
}

// MARK: - Expiry

extension TrackerCredential {
    // both services issue JWTs and both currently send expires_in beside them, so
    // this is the belt to that pair of braces rather than the primary source. a
    // nil expiry is the state to avoid: isValid() then answers true forever, which
    // is mihon's synthesised-expiry bug wearing a different hat
    static func expiry(inJWT token: String) -> Date? {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return nil }

        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // base64url drops the padding that base64 decoding insists on
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)

        guard
            let data = Data(base64Encoded: payload),
            let claims = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let exp = claims["exp"] as? TimeInterval
        else { return nil }

        return Date(timeIntervalSince1970: exp)
    }
}
