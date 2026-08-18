//
//  ReaderSettings.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Foundation

// reading mode lives on the series row, not here - everything else is a global
// preference that follows the reader between titles
enum ReaderSettings {
    private enum Key {
        static let dim = "reader.dim"
        static let grayscale = "reader.grayscale"
        static let inverted = "reader.inverted"
        static let warmth = "reader.warmth"
        static let keepScreenOn = "reader.keepScreenOn"
        static let chromeTint = "reader.chromeTint"
        static let horizontalPadding = "reader.horizontalPadding"
        static let autoScrollSpeed = "reader.autoScrollSpeed"
        static let autoAdvanceInterval = "reader.autoAdvanceInterval"
        static let tapZone = "reader.tapZone"
        static let tapZonesReversed = "reader.tapZonesReversed"
    }

    private static let defaults = UserDefaults.standard

    static var dim: Double {
        get { defaults.double(forKey: Key.dim) }
        set { defaults.set(newValue, forKey: Key.dim) }
    }

    static var grayscale: Bool {
        get { defaults.bool(forKey: Key.grayscale) }
        set { defaults.set(newValue, forKey: Key.grayscale) }
    }

    static var inverted: Bool {
        get { defaults.bool(forKey: Key.inverted) }
        set { defaults.set(newValue, forKey: Key.inverted) }
    }

    static var warmth: Double {
        get { defaults.double(forKey: Key.warmth) }
        set { defaults.set(newValue, forKey: Key.warmth) }
    }

    static var keepScreenOn: Bool {
        get { defaults.bool(forKey: Key.keepScreenOn) }
        set { defaults.set(newValue, forKey: Key.keepScreenOn) }
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

    // a value stored before the range narrowed can sit outside the slider
    static var autoScrollSpeed: CGFloat {
        get {
            let stored =
                defaults.object(forKey: Key.autoScrollSpeed) as? CGFloat
                ?? ReaderConfiguration.Defaults.autoScrollSpeed

            return min(
                max(ReaderConfiguration.Defaults.minAutoScrollSpeed, stored),
                ReaderConfiguration.Defaults.maxAutoScrollSpeed
            )
        }
        set { defaults.set(newValue, forKey: Key.autoScrollSpeed) }
    }

    static var autoAdvanceInterval: TimeInterval {
        get {
            let stored =
                defaults.object(forKey: Key.autoAdvanceInterval) as? TimeInterval
                ?? ReaderConfiguration.Defaults.autoAdvanceInterval

            return min(
                max(ReaderConfiguration.Defaults.minAutoAdvanceInterval, stored),
                ReaderConfiguration.Defaults.maxAutoAdvanceInterval
            )
        }
        set { defaults.set(newValue, forKey: Key.autoAdvanceInterval) }
    }

    // an unknown id resolves rather than throwing the choice away - the layout
    // names changed once already, and a stored value from before that should
    // land somewhere sensible instead of on whatever case happens to be first
    static var tapZone: ReaderTapZones.Layout {
        get {
            defaults.string(forKey: Key.tapZone)
                .flatMap(ReaderTapZones.Layout.init(rawValue:)) ?? .edge
        }
        set { defaults.set(newValue.rawValue, forKey: Key.tapZone) }
    }

    // the reader's own toggle. what the zones actually do also depends on the
    // reading direction - see ReaderTapZones.reversed(for:manual:)
    static var tapZonesReversed: Bool {
        get { defaults.bool(forKey: Key.tapZonesReversed) }
        set { defaults.set(newValue, forKey: Key.tapZonesReversed) }
    }
}
