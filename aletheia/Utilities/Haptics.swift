//
//  Haptics.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import CoreHaptics

// the beat offsets below play "shave and a haircut, two bits" - haptics are
// optional hardware, so every failure path here is a silent no-op
enum BypassHaptic {
    private static let engine: CHHapticEngine? = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        return try? CHHapticEngine()
    }()

    static func play() {
        guard let engine else { return }

        let beats: [(offset: TimeInterval, intensity: Float)] = [
            (0.00, 1.0),
            (0.14, 0.9),
            (0.22, 0.9),
            (0.32, 1.0),
            (0.46, 1.0),
            (0.72, 1.0),
            (0.85, 1.0),
        ]

        let events = beats.map { beat in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: beat.intensity),
                    .init(parameterID: .hapticSharpness, value: 0.9),
                ],
                relativeTime: beat.offset
            )
        }

        guard let pattern = try? CHHapticPattern(events: events, parameters: []),
            let player = try? engine.makePlayer(with: pattern),
            (try? engine.start()) != nil
        else { return }

        try? player.start(atTime: CHHapticTimeImmediate)
        engine.notifyWhenPlayersFinished { _ in .stopEngine }
    }
}

// one CHHapticPattern, not a loop of awaited sleeps - the offsets are the
// effect itself, not a delay standing in for state, and handing the whole
// schedule to core haptics keeps it that way: nothing here waits on anything.
//
// deliberately more impulses than design.md's 11-per-action rule allows -
// that rule counts EVENTS, and a ramp is one event with texture. the
// carve-out and its two conditions are written down beside the rule
enum CountUpHaptic {
    private static let engine: CHHapticEngine? = {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return nil }
        return try? CHHapticEngine()
    }()

    // matched to the curve the digits use, so the last taps land as the
    // numbers stop, then one firm pop as the cards snap back to resting size.
    // the ramp fades INTO that pop deliberately - fading to nothing then
    // landing a sharp tap reads as a gesture with a release, not taps that
    // ran out
    static func play(duration: TimeInterval, steps: Int = 18) {
        guard let engine, steps > 1, duration > 0 else { return }

        var events = (0..<steps).map { step -> CHHapticEvent in
            let progress = Double(step) / Double(steps - 1)
            // inverse of easeOut - even progress through the VALUE means
            // offsets that spread out over time, which is the thinning
            let eased = 1 - pow(1 - progress, 1.0 / 3.0)
            let intensity = Float(0.45 * (1 - progress) + 0.08)

            return CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: intensity),
                    .init(parameterID: .hapticSharpness, value: 0.4),
                ],
                relativeTime: eased * duration
            )
        }

        // sharper as well as stronger - has to be heard over the ramp it follows
        events.append(
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: 1.0),
                    .init(parameterID: .hapticSharpness, value: 0.9),
                ],
                relativeTime: duration
            )
        )

        guard let pattern = try? CHHapticPattern(events: events, parameters: []),
            let player = try? engine.makePlayer(with: pattern),
            (try? engine.start()) != nil
        else { return }

        try? player.start(atTime: CHHapticTimeImmediate)
        engine.notifyWhenPlayersFinished { _ in .stopEngine }
    }
}
