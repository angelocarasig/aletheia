//
//  AnyModifier+Referer.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import Foundation
import Kingfisher

extension AnyModifier {
    // most sources reject image requests that do not carry their own referer
    static func referer(_ url: URL?) -> AnyModifier {
        let referer = url?.absoluteString

        return AnyModifier { request in
            guard let referer else { return request }

            var request = request
            request.setValue(referer, forHTTPHeaderField: "Referer")
            return request
        }
    }
}
