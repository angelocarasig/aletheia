//
//  LanguageCode.swift
//  aletheia
//
//  Created by Angelo Carasig on 4/8/2026.
//

/// supported content languages: english + cjk
enum LanguageCode: String, Codable, Sendable, Hashable, CaseIterable {
    case english = "en"
    case chinese = "zh"
    case japanese = "ja"
    case korean = "ko"

    var flag: String {
        switch self {
        case .english: return "🇬🇧"
        case .chinese: return "🇨🇳"
        case .japanese: return "🇯🇵"
        case .korean: return "🇰🇷"
        }
    }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        }
    }

    var flagWithName: String {
        "\(flag) \(displayName)"
    }
}
