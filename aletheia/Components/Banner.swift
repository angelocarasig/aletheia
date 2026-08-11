//
//  Banner.swift
//  aletheia
//
//  Created by Angelo Carasig on 11/8/2026.
//

import SwiftUI

// a fact about the section it sits in, optionally with the one thing that
// resolves it. the handoff anatomy - glyph, sentence, chevron - because an
// actionable banner is not a submit: it is "the same thing, done somewhere
// else". solid tone rather than glass, since a banner sits inside content
// that is often already glass and glass cannot sample glass
struct Banner: View {
    private let title: Text
    private let message: Text?
    // optional, because a notice that is purely prose has nothing for a glyph to
    // add: the sentence is already the whole of it, and a triangle beside it only
    // raises the volume of something that was deliberately quiet
    private let systemImage: String?
    private let tone: Palette.Tone
    private let action: (() -> Void)?

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        // the second line is what the tap does, not a competing headline
        static let messageOpacity: Double = 0.8
    }

    // a literal keeps its inflection markup - passing the same string through a
    // String parameter renders the ^[...](inflect:) syntax verbatim
    init(
        _ title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        systemImage: String? = nil,
        tone: Palette.Tone = .warning,
        action: (() -> Void)? = nil
    ) {
        self.title = Text(title)
        self.message = message.map { Text($0) }
        self.systemImage = systemImage
        self.tone = tone
        self.action = action
    }

    init(
        title: Text,
        message: Text? = nil,
        systemImage: String? = nil,
        tone: Palette.Tone = .warning,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.tone = tone
        self.action = action
    }

    var body: some View {
        Content
            .accessibilityElement(children: .combine)
            .modifier(Tap(action: action))
    }

    private var Content: some View {
        HStack(spacing: dimensions.spacing.space12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                title
                    .font(.subheadline)
                    .fontWeight(.medium)

                if let message {
                    message
                        .font(.caption)
                        .opacity(Layout.messageOpacity)
                }
            }
            .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            // only when there is somewhere to go. a chevron on a banner that
            // does nothing is an affordance for a tap that never lands
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
            }
        }
        .foregroundStyle(tone.text)
        .padding(.horizontal, dimensions.spacing.space16)
        .padding(.vertical, dimensions.spacing.space12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: dimensions.touchTarget)
        .background(
            tone.subtle,
            in: .rect(cornerRadius: dimensions.radius.radius16, style: .continuous)
        )
    }

    // a modifier rather than a branch in the body, so both shapes stay one view
    // and a banner that gains an action does not remount
    private struct Tap: ViewModifier {
        let action: (() -> Void)?

        func body(content: Content) -> some View {
            if let action {
                content
                    .contentShape(.rect)
                    .tappable(action: action)
            } else {
                content
            }
        }
    }
}

// MARK: - Previews

#Preview("Banner") {
    ScrollView {
        VStack(spacing: 12) {
            Banner(
                "AniList is at chapter 60",
                message: "Mark chapters up to 60 as read here",
                systemImage: "icloud.and.arrow.down",
                action: {}
            )

            Banner(
                "You are at chapter 60 here",
                message: "Update AniList to match",
                systemImage: "icloud.and.arrow.up",
                action: {}
            )

            Banner(
                "Girlfriend, Girlfriend is already linked to this entry",
                message: "Linking here means both series push their own progress to it",
                systemImage: "exclamationmark.triangle"
            )

            Banner(
                "Signed out of MyAnimeList",
                systemImage: "person.crop.circle.dashed",
                tone: .danger,
                action: {}
            )

            Banner(
                "Couldn't reach MyAnimeList",
                message: "Linking still works, and it will read your entry when it syncs."
            )

            Banner(
                "Every chapter is downloaded",
                systemImage: "checkmark.circle",
                tone: .success
            )

            Banner(
                "3 sources are failing",
                message: "Tap to see which ones",
                systemImage: "exclamationmark.circle",
                tone: .neutral,
                action: {}
            )
        }
        .padding()
    }
}
