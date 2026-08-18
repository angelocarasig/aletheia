//
//  ReaderGapSheet.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import SwiftUI

// what the rule's break could not say in four words. two readers arrived at the
// same two questions from opposite ends - "did I lose something" and "which
// sources did you actually ask" - and both are answerable in a sentence each,
// which is why this explains rather than navigating anywhere
struct ReaderGapSheet: View {
    let gap: ReaderSeparatorModel.Gap

    @Environment(\.dimensions) private var dimensions

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: "arrow.trianglehead.branch")
            } description: {
                VStack(spacing: dimensions.spacing.space12) {
                    // the first line answers the reader who thinks something was
                    // taken from her, and it is the more important of the two
                    Text(
                        "No source you have installed has these chapters. Nothing has been removed from your library."
                    )

                    if !gap.sources.isEmpty {
                        Text("Checked \(gap.sources.formatted(.list(type: .and)))")
                            .font(.caption)
                            .foregroundStyle(.muted)
                    }
                }
            }
            .toolbarTitleDisplayMode(.inline)
            .containerBackground(.clear, for: .navigation)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // inflection has to reach Text unerased, so the count branches rather than
    // the string - a ternary with a String on either side types the whole
    // expression as String and renders the markup verbatim
    private var title: String {
        gap.count == 1
            ? "Chapter \(gap.from.formatted()) Unavailable"
            : "Chapters \(gap.from.formatted())-\(gap.to.formatted()) Unavailable"
    }
}

// MARK: - Previews

#Preview("Range") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ReaderGapSheet(
            gap: .init(from: 45, to: 49, count: 5, sources: ["MangaDex", "WeebCentral"])
        )
    }
}

#Preview("One chapter") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ReaderGapSheet(gap: .init(from: 45, to: 45, count: 1, sources: ["MangaDex"]))
    }
}

// nothing to name, so the line that would name it does not appear rather than
// saying "checked nothing"
#Preview("No sources named") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ReaderGapSheet(gap: .init(from: 1102, to: 1239, count: 138))
    }
}
