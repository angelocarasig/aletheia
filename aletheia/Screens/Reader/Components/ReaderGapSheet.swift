//
//  ReaderGapSheet.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import SwiftUI

struct ReaderGapSheet: View {
    let gap: ReaderSeparatorModel.Gap

    @Environment(\.dimensions) private var dimensions

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: "arrow.trianglehead.branch")
            } description: {
                VStack(spacing: dimensions.spacing.space12) {
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

#Preview("No sources named") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ReaderGapSheet(gap: .init(from: 1102, to: 1239, count: 138))
    }
}
