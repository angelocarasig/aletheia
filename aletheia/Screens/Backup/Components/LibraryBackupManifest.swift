//
//  LibraryBackupManifest.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI

// rows redact to a shimmer while a count is still loading (nil)
struct LibraryBackupManifestGroup: View {
    let title: String
    let rows: [(icon: String, label: String, count: Int?)]

    @Environment(\.dimensions) private var dimensions

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader(title)

            VStack(spacing: dimensions.spacing.space12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    if index > 0 { Divider() }
                    LibraryBackupManifestRow(icon: row.icon, label: row.label, count: row.count)
                }
            }
            .padding(dimensions.spacing.space16)
            .glassEffect(.regular, in: .rect(cornerRadius: dimensions.radius.radius16, style: .continuous))
        }
    }
}

private struct LibraryBackupManifestRow: View {
    let icon: String
    let label: String
    let count: Int?

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let iconWidth: CGFloat = 24
    }

    var body: some View {
        row.animation(.settle, value: count)
    }

    @ViewBuilder
    private var row: some View {
        let content = HStack(spacing: dimensions.spacing.space12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: Layout.iconWidth)

            Text(label)
                .font(.subheadline)

            Spacer(minLength: 0)

            Group {
                if let count {
                    Text("\(count)")
                        .contentTransition(.numericText())
                } else {
                    Text("000")
                        .redacted(reason: .placeholder)
                }
            }
            .font(.subheadline.weight(.semibold))
            .fontDesign(.rounded)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }

        if count == nil {
            content.shimmer()
        } else {
            content
        }
    }
}
