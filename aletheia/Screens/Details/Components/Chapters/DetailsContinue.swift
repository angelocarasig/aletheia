//
//  DetailsContinue.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import SwiftUI

struct DetailsContinue: View {
    let chapters: [DetailsChapters.Chapter]
    var onOpen: (DetailsChapters.Chapter) -> Void

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let tint: Double = 0.25
    }

    private var next: DetailsChapters.Chapter? {
        let readable = chapters.filter(\.canRead)

        let resumable =
            readable
            .filter { $0.progress > 0 && $0.progress < 1 }
            .min { $0.number < $1.number }

        return resumable ?? readable.filter { $0.progress < 1 }.min { $0.number < $1.number }
    }

    private var started: Bool {
        chapters.contains { $0.progress > 0 }
    }

    var body: some View {
        if chapters.isEmpty {
            EmptyView()
        } else if let next {
            Reading(next)
        } else {
            Finished
        }
    }
}

// MARK: - States

extension DetailsContinue {
    fileprivate func Reading(_ chapter: DetailsChapters.Chapter) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            Icon(chapter)

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(started ? "Continue Reading" : "Start Reading")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Subtitle(chapter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, dimensions.spacing.space16)
        .padding(.vertical, dimensions.spacing.space12)
        .glassEffect(
            .regular.tint(Palette.brand.opacity(Layout.tint)).interactive(),
            in: .capsule
        )
        .contentShape(.capsule)
        .tappable { onOpen(chapter) }
    }

    fileprivate func Subtitle(_ chapter: DetailsChapters.Chapter) -> Text {
        let number = chapter.number.formatted(.number.precision(.fractionLength(0...2)))

        guard !chapter.scanlator.isEmpty else { return Text("Chapter \(number)") }
        return Text("Chapter \(number) · \(chapter.scanlator)")
    }

    @ViewBuilder
    fileprivate func Icon(_ chapter: DetailsChapters.Chapter) -> some View {
        let shape = RoundedRectangle(cornerRadius: dimensions.radius.radius8)

        Group {
            if let icon = chapter.sourceIcon {
                Image(icon)
                    .resizable()
                    .scaledToFit()
            } else {
                shape.fill(.quaternary)
            }
        }
        .frame(width: dimensions.size.icon32, height: dimensions.size.icon32)
        .clipShape(shape)
    }

    fileprivate var Finished: some View {
        HStack(spacing: dimensions.spacing.space12) {
            Image(systemName: "checkmark")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.success)

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text("All Caught Up")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("^[\(chapters.count) chapter](inflect: true) read")
                    .font(.caption)
                    .foregroundStyle(.muted)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, dimensions.spacing.space16)
        .padding(.vertical, dimensions.spacing.space12)
        .glassEffect(.regular, in: .capsule)
    }
}
