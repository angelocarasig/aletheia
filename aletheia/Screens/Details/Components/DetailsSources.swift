//
//  DetailsSources.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI

struct DetailsSources: View {
    let origins: [Origin]
    var onSetPrimary: (Int64) -> Void
    var onReorder: ([Int64]) -> Void
    var onRemove: (Int64) -> Void

    @State private var ordering = false

    @Environment(\.dimensions) private var dimensions
    @Environment(\.openURL) private var openURL

    private enum Layout {
        static let iconSize: CGFloat = 44
        static let rankWidth: CGFloat = 20
        static let placeholderOpacity: Double = 0.06
        static let unavailableOpacity: Double = 0.5
        static let slugLength = 8
        static let settle: Animation = .smooth(duration: 0.3)
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
        // the new order arrives through the observation, so the tap that caused it
        // is long finished by the time the rows move
        .animation(Layout.settle, value: origins)
        .sheet(isPresented: $ordering) {
            OriginOrder(origins: origins, onCommit: onReorder)
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
            .contentTransition(.numericText())
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
            HStack(alignment: .firstTextBaseline, spacing: dimensions.spacing.space8) {
                Text(origin.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                State(origin)
            }

            Subtitle(origin)

            if origin.failing {
                Trouble(origin)
            }
        }
    }

    // the attempt date, not a first-seen date: the row says how long ago the app
    // last tried and got nothing, which is the fact it actually holds
    @ViewBuilder
    private func Trouble(_ origin: Origin) -> some View {
        if let reason = origin.failureReason {
            Group {
                if let failedDate = origin.failedDate {
                    Text("\(reason) Last tried \(failedDate.formatted(.relative(presentation: .named))).")
                } else {
                    Text(reason)
                }
            }
            .font(.caption2)
            .foregroundStyle(.warningText)
            .lineLimit(2)
        }
    }

    @ViewBuilder
    private func State(_ origin: Origin) -> some View {
        switch origin.availability {
        case .available where origin.failing: Badge(text: "FAILING", tone: .warning, size: .compact)
        case .available where origin.priority == 0: Badge(text: "PRIMARY", tone: .brand, size: .compact)
        case .available: EmptyView()
        case .disabled: Badge(text: "DISABLED", tone: .warning, size: .compact)
        case .disconnected: Badge(text: "DISCONNECTED", tone: .danger, size: .compact)
        case .missing: Badge(text: "NOT INSTALLED", tone: .neutral, size: .compact)
        }
    }

    // two origins from one source render the same name and icon, so the slug is
    // surfaced exactly then - it is the only fact telling the listings apart
    private var duplicatedNames: Set<String> {
        Set(Dictionary(grouping: origins, by: \.name).filter { $1.count > 1 }.keys)
    }

    @ViewBuilder
    private func Subtitle(_ origin: Origin) -> some View {
        Group {
            if duplicatedNames.contains(origin.name) {
                Text("\(marker(for: origin.slug)) · ^[\(origin.chapterCount) chapter](inflect: true)")
            } else {
                Text("^[\(origin.chapterCount) chapter](inflect: true)")
            }
        }
        .font(.caption2)
        .foregroundStyle(.muted)
        .lineLimit(1)
    }

    // a marker, not the slug - mangadex slugs are uuids that would push the
    // chapter count off the row, and eight characters is already past the first
    // uuid group, which is where two listings stop looking alike
    private func marker(for slug: String) -> String {
        slug.count <= Layout.slugLength ? slug : slug.prefix(Layout.slugLength) + "…"
    }

    private func Actions(_ origin: Origin) -> some View {
        Menu {
            Button {
                onSetPrimary(origin.id)
            } label: {
                Label("Set as Primary", systemImage: "star")
            }
            .disabled(origin.priority == 0)

            Button {
                ordering = true
            } label: {
                Label("Change Priority", systemImage: "arrow.up.arrow.down")
            }
            .disabled(origins.count <= 1)

            Button {
                guard let url = origin.url else { return }
                openURL(url)
            } label: {
                Label("Open in Browser", systemImage: "safari")
            }
            .disabled(origin.url == nil)

            Button {
                guard let url = origin.url else { return }
                UIPasteboard.general.string = url.absoluteString
            } label: {
                Label("Copy URL", systemImage: "doc.on.doc")
            }
            .disabled(origin.url == nil)

            Divider()

            // a series must always keep at least one origin
            Button(role: .destructive) {
                onRemove(origin.id)
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
        let slug: String
        let host: String
        let url: URL?
        let icon: ImageResource?
        let priority: Int
        let chapterCount: Int
        let fetchedDate: Date?
        let availability: Availability
        // the last attempt's error, cleared the moment the source answers again -
        // so this is what is wrong now, never what once was
        let failureReason: String?
        let failedDate: Date?

        var unavailable: Bool { availability != .available }

        // a source the user switched off is not a source that is failing
        var failing: Bool { failureReason != nil && availability == .available }

        // disabled is the user's own doing, disconnected means the source row
        // went away, missing means it is no longer compiled into the app
        enum Availability {
            case available, disabled, disconnected, missing
        }
    }
}
