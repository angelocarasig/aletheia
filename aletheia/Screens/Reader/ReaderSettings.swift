//
//  ReaderSettings.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation

// reading mode is per-series and lives on the series row. everything here is a
// global preference that follows the reader between titles
enum ReaderSettings {
    private enum Key {
        static let dim = "reader.dim"
        static let chromeTint = "reader.chromeTint"
        static let horizontalPadding = "reader.horizontalPadding"
        static let autoScrollSpeed = "reader.autoScrollSpeed"
        static let tapZone = "reader.tapZone"
        static let tapZonesReversed = "reader.tapZonesReversed"
        static let tapZonesEnabled = "reader.tapZonesEnabled"
    }

    private static let defaults = UserDefaults.standard

    static var dim: Double {
        get { defaults.double(forKey: Key.dim) }
        set { defaults.set(newValue, forKey: Key.dim) }
    }

    static var chromeTint: Double {
        get {
            defaults.object(forKey: Key.chromeTint) as? Double
                ?? ReaderConfiguration.Defaults.chromeTint
        }
        set { defaults.set(newValue, forKey: Key.chromeTint) }
    }

    static var horizontalPadding: CGFloat {
        get { defaults.object(forKey: Key.horizontalPadding) as? CGFloat ?? 0 }
        set { defaults.set(newValue, forKey: Key.horizontalPadding) }
    }

    static var autoScrollSpeed: CGFloat {
        get {
            defaults.object(forKey: Key.autoScrollSpeed) as? CGFloat
                ?? ReaderConfiguration.Defaults.autoScrollSpeed
        }
        set { defaults.set(newValue, forKey: Key.autoScrollSpeed) }
    }

    static var tapZone: ReaderTapZones.Layout {
        get {
            defaults.string(forKey: Key.tapZone)
                .flatMap(ReaderTapZones.Layout.init(rawValue:)) ?? .leftRight
        }
        set { defaults.set(newValue.rawValue, forKey: Key.tapZone) }
    }

    static var tapZonesReversed: Bool {
        get { defaults.bool(forKey: Key.tapZonesReversed) }
        set { defaults.set(newValue, forKey: Key.tapZonesReversed) }
    }

    static var tapZonesEnabled: Bool {
        get { defaults.object(forKey: Key.tapZonesEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.tapZonesEnabled) }
    }
}
