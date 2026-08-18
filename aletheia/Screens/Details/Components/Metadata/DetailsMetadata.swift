//
//  DetailsMetadata.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI

struct DetailsMetadata: View {
    let classification: Classification?
    let publication: Publication?
    let readCount: Int
    let totalCount: Int
    let lastFetchedDate: Date?
    let lastReadDate: Date?

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let cellPadding: CGFloat = 10
        static let fillOpacity: Double = 0.05
        static let percent: Double = 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space16) {
            SectionHeader("Metadata")
            Badges
            Stats
        }
    }

    @ViewBuilder
    private var Badges: some View {
        if classification != nil || publication != nil {
            HStack(spacing: dimensions.spacing.space8) {
                if let classification {
                    Badge(text: classification.rawValue, tone: classification.tone)
                }

                if let publication {
                    Badge(text: publication.rawValue, tone: publication.tone)
                }
            }
        }
    }

    private var Stats: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Cell(
                label: "Progress",
                value: progress,
                subtitle: progressSubtitle
            )
            Cell(label: "Fetched", subtitle: "Up to date") {
                Elapsed(lastFetchedDate)
            }
            Cell(label: "Last Read", subtitle: "-") {
                Elapsed(lastReadDate)
            }
        }
    }

    @ViewBuilder
    private func Elapsed(_ date: Date?) -> some View {
        if let date {
            LiveRelativeText(date: date)
        } else {
            Text("Never")
        }
    }

    private func Cell(
        label: String,
        value: String? = nil,
        subtitle: String,
        @ViewBuilder content: () -> some View = { EmptyView() }
    ) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.muted)

            Group {
                if let value {
                    Text(value)
                } else {
                    content()
                }
            }
            .font(.subheadline)
            .fontWeight(.semibold)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.muted)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Layout.cellPadding)
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius8)
        )
    }

    private var progress: String {
        totalCount > 0 ? "\(readCount)/\(totalCount)" : "-"
    }

    private var progressSubtitle: String {
        guard totalCount > 0 else { return "No chapters" }
        let percent = Int((Double(readCount) / Double(totalCount)) * Layout.percent)
        return "\(percent)% complete"
    }

    private func relative(_ date: Date?) -> String {
        date?.formatted(.relative(presentation: .named)) ?? "Never"
    }
}
