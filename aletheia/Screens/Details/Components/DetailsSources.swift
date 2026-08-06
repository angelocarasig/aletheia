//
//  DetailsSources.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI

struct DetailsSources: View {
    let origins: [Origin]

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let iconSize: CGFloat = 44
        static let rankWidth: CGFloat = 20
        static let placeholderOpacity: Double = 0.06
        static let unavailableOpacity: Double = 0.5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space16) {
            SectionHeader("Sources")

            VStack(spacing: dimensions.spacing.space16) {
                ForEach(origins) { origin in
                    Row(origin)
                }
            }
        }
    }

    private func Row(_ origin: Origin) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            Rank(origin)
            Icon(origin)
            Details(origin)

            Spacer(minLength: 0)

            Actions(origin)
        }
        .opacity(origin.unavailable ? Layout.unavailableOpacity : 1)
    }

    private func Rank(_ origin: Origin) -> some View {
        Text("\(origin.priority + 1)")
            .font(.caption)
            .fontWeight(.bold)
            .foregroundStyle(origin.priority == 0 ? .brandText : .muted)
            .frame(width: Layout.rankWidth)
    }

    @ViewBuilder
    private func Icon(_ origin: Origin) -> some View {
        if let icon = origin.icon, !origin.unavailable {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius12))
        } else {
            Image(systemName: "questionmark")
                .font(.footnote)
                .foregroundStyle(.muted)
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .background(
                    .primary.opacity(Layout.placeholderOpacity),
                    in: .rect(cornerRadius: dimensions.radius.radius12)
                )
        }
    }

    // classification and publication are series-level and already shown once in
    // the metadata section - repeating them per origin says nothing new. what
    // is per-origin is how much it contributes and how fresh that is
    private func Details(_ origin: Origin) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
            HStack(spacing: dimensions.spacing.space8) {
                Text(origin.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                State(origin)
            }

            Subtitle(origin)
        }
    }

    @ViewBuilder
    private func State(_ origin: Origin) -> some View {
        switch origin.availability {
        case .available where origin.priority == 0: Badge(text: "PRIMARY", tone: .brand)
        case .available: EmptyView()
        case .disabled: Badge(text: "DISABLED", tone: .warning)
        case .disconnected: Badge(text: "DISCONNECTED", tone: .danger)
        case .missing: Badge(text: "NOT INSTALLED", tone: .neutral)
        }
    }

    private func Subtitle(_ origin: Origin) -> some View {
        let fetched = origin.fetchedDate
            .map { " · \($0.formatted(.relative(presentation: .numeric)))" } ?? ""

        return Text("\(origin.host) · ^[\(origin.chapterCount) chapter](inflect: true)\(fetched)")
            .font(.caption2)
            .foregroundStyle(.muted)
            .lineLimit(1)
    }

    private func Actions(_ origin: Origin) -> some View {
        Menu {
            Button {
                fatalError("not implemented")
            } label: {
                Label("Set as Primary", systemImage: "star.fill")
            }
            .disabled(origin.priority == 0)

            Button {
                fatalError("not implemented")
            } label: {
                Label("Change Priority", systemImage: "arrow.up.arrow.down")
            }

            Button {
                fatalError("not implemented")
            } label: {
                Label("Copy URL", systemImage: "doc.on.doc")
            }

            Divider()

            // a series must always keep at least one origin
            Button(role: .destructive) {
                fatalError("not implemented")
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .disabled(origins.count <= 1)
        } label: {
            Image(systemName: "ellipsis")
                .font(.footnote)
                .foregroundStyle(.muted)
                .frame(width: dimensions.size.control, height: dimensions.size.control)
                .contentShape(.rect)
        }
    }
}

extension DetailsSources {
    struct Origin: Identifiable, Hashable {
        let id: Int64
        let name: String
        let host: String
        let icon: ImageResource?
        let priority: Int
        let chapterCount: Int
        let fetchedDate: Date?
        let availability: Availability

        var unavailable: Bool { availability != .available }

        // disabled is the user's own doing, disconnected means the source row
        // went away, missing means it is no longer compiled into the app
        enum Availability {
            case available, disabled, disconnected, missing
        }
    }
}
