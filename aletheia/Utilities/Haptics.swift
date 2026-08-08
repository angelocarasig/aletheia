//
//  Haptics.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/26.
//

import CoreHaptics

// the bypass toggle's celebration: "shave and a haircut, two bits". haptics are
// optional hardware, so every failure path is a silent no-op
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
            (0.85, 1.0)
        ]

        let events = beats.map { beat in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    .init(parameterID: .hapticIntensity, value: beat.intensity),
                    .init(parameterID: .hapticSharpness, value: 0.9)
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
