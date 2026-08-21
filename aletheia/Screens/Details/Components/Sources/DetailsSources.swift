//
//  DetailsSources.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI

struct DetailsSources: View {
    let origins: [Origin]
    var retrying: Set<Int64> = []
    var onSetPrimary: (Int64) -> Void
    var onReorder: ([Int64]) -> Void
    var onRemove: (Int64) -> Void
    var onRetry: (Int64) -> Void = { _ in }

    @State private var ordering = false

    @Environment(\.dimensions) private var dimensions
    @Environment(\.openURL) private var openURL

    private enum Layout {
        static let iconSize: CGFloat = 44
        static let rankWidth: CGFloat = 20
        static let placeholderOpacity: Double = 0.06
        static let unavailableOpacity: Double = 0.5
        static let slugLength = 8
        static let retryFill: Double = 0.1
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
        // the new order arrives through the observation, well after the tap
        // that caused it - the animation has to be explicit here
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

    // failedDate is the last-attempt date, not first-seen - the row says how
    // long ago the app last tried and got nothing
    @ViewBuilder
    private func Trouble(_ origin: Origin) -> some View {
        if let reason = origin.failureReason {
            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Group {
                    if let failedDate = origin.failedDate {
                        LiveRelative(date: failedDate) { relative in
                            Text("\(reason) Last tried \(relative).")
                        }
                    } else {
                        Text(reason)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.warningText)
                .lineLimit(2)

                Retry(origin)
            }
        }
    }

    @ViewBuilder
    private func Retry(_ origin: Origin) -> some View {
        if retrying.contains(origin.id) {
            ProgressView()
                .controlSize(.small)
        } else {
            Text("Try Again")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.brand)
                .padding(.horizontal, dimensions.spacing.space12)
                .padding(.vertical, dimensions.spacing.space4)
                .background(.brand.opacity(Layout.retryFill), in: .capsule)
                .tappable { onRetry(origin.id) }
        }
    }

    @ViewBuilder
    private func State(_ origin: Origin) -> some View {
        switch origin.availability {
        case .available where origin.failing: Badge(text: "FAILING", tone: .warning, size: .compact)
        case .available where origin.priority == 0:
            Badge(text: "PRIMARY", tone: .brand, size: .compact)
        case .available: EmptyView()
        case .disabled: Badge(text: "DISABLED", tone: .warning, size: .compact)
        case .disconnected: Badge(text: "DISCONNECTED", tone: .danger, size: .compact)
        case .missing: Badge(text: "NOT INSTALLED", tone: .neutral, size: .compact)
        }
    }

    private var duplicatedNames: Set<String> {
        Set(Dictionary(grouping: origins, by: \.name).filter { $1.count > 1 }.keys)
    }

    @ViewBuilder
    private func Subtitle(_ origin: Origin) -> some View {
        Group {
            if duplicatedNames.contains(origin.name) {
                Text(
                    "\(marker(for: origin.slug)) · ^[\(origin.chapterCount) chapter](inflect: true)"
                )
            } else {
                Text("^[\(origin.chapterCount) chapter](inflect: true)")
            }
        }
        .font(.caption2)
        .foregroundStyle(.muted)
        .lineLimit(1)
    }

    // eight characters, not the full slug - a uuid slug would push the chapter
    // count off the row, and eight is already past the first uuid group,
    // which is where two listings stop looking alike
    private func marker(for slug: String) -> String {
        slug.count <= Layout.slugLength ? slug : slug.prefix(Layout.slugLength) + "..."
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
    typealias Origin = DetailsComposer.Sources.Origin
}

// MARK: - Previews

// written out rather than read from the error types - failureReason is a
// stored column, so what a reader sees is whatever text was true when it
// failed, not what the enum says today
private struct SourcesPreview: View {
    @State private var index = 0
    @State private var retrying: Set<Int64> = []

    private static let states: [(name: String, reason: String?)] = [
        ("Healthy", nil),
        ("Offline", "Check your connection and try again."),
        ("Timed out", "The server took too long to respond. Try again in a moment."),
        ("Bad response", "The server responded unexpectedly."),
        ("Encoding", "\(Constants.App.name) couldn't build the request."),
        ("Decoding", "\(Constants.App.name) couldn't read the server's response."),
        ("Transport", "A server with the specified hostname could not be found."),
        ("Nothing came back", "The server responded but returned nothing to read."),
        (
            "Verification timed out",
            "The source's checks didn't finish in time. Try again in a moment."
        ),
        ("Verification needed", "This source needs to verify your browser before it can be read."),
        ("Unknown", "Something unexpected went wrong. Please try again."),
        (
            "Two lines",
            "The server responded but returned nothing to read. This usually means the listing moved."
        ),
    ]

    private var state: (name: String, reason: String?) { Self.states[index] }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("Previous") { step(-1) }
                Button("Next") { step(1) }
                Spacer()
                Text("\(index + 1)/\(Self.states.count)")
                    .font(.caption)
                    .foregroundStyle(.muted)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Text(state.name)
                .font(.caption)
                .foregroundStyle(.muted)

            DetailsSources(
                origins: [failing, healthy],
                retrying: retrying,
                onSetPrimary: { _ in },
                onReorder: { _ in },
                onRemove: { _ in },
                onRetry: { id in
                    retrying.insert(id)
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        retrying.remove(id)
                    }
                }
            )

            Spacer()
        }
        .padding(16)
        .background(.canvas)
    }

    private func step(_ delta: Int) {
        index = (index + delta + Self.states.count) % Self.states.count
    }

    private var failing: DetailsSources.Origin {
        .init(
            id: 1,
            name: "MangaFire",
            slug: "one-piece.abc123",
            sourceSlug: "mangafire",
            host: "mangafire.to",
            url: URL(string: "https://mangafire.to/manga/one-piece.abc123"),
            icon: nil,
            priority: 0,
            chapterCount: 1102,
            fetchedDate: .now.addingTimeInterval(-7200),
            availability: .available,
            failureReason: state.reason,
            failedDate: state.reason == nil ? nil : .now.addingTimeInterval(-45)
        )
    }

    private var healthy: DetailsSources.Origin {
        .init(
            id: 2,
            name: "WeebCentral",
            slug: "01J76XY",
            sourceSlug: "weebcentral",
            host: "weebcentral.com",
            url: URL(string: "https://weebcentral.com/series/01J76XY"),
            icon: nil,
            priority: 1,
            chapterCount: 1098,
            fetchedDate: .now.addingTimeInterval(-600),
            availability: .available,
            failureReason: nil,
            failedDate: nil
        )
    }
}

#Preview("Failures") {
    SourcesPreview()
}

#Preview("Dark") {
    SourcesPreview()
        .environment(\.colorScheme, .dark)
}

#Preview("Unavailable") {
    ScrollView {
        DetailsSources(
            origins: [
                .init(
                    id: 1, name: "MangaFire", slug: "one-piece", sourceSlug: "mangafire",
                    host: "mangafire.to", url: nil,
                    icon: nil, priority: 0, chapterCount: 1102, fetchedDate: .now,
                    availability: .disabled, failureReason: nil, failedDate: nil),
                .init(
                    id: 2, name: "WeebCentral", slug: "01J76XY", sourceSlug: "weebcentral",
                    host: "weebcentral.com", url: nil,
                    icon: nil, priority: 1, chapterCount: 1098, fetchedDate: nil,
                    availability: .disconnected, failureReason: nil, failedDate: nil),
                .init(
                    id: 3, name: "Atsumaru", slug: "op", sourceSlug: "atsumaru", host: "atsu.moe",
                    url: nil, icon: nil,
                    priority: 2, chapterCount: 0, fetchedDate: nil, availability: .missing,
                    failureReason: nil, failedDate: nil),
                // disabled overrides failing - Origin.failing requires
                // availability == .available, so this row shows no trouble line
                .init(
                    id: 4, name: "MangaDex", slug: "uuid", sourceSlug: "mangadex",
                    host: "mangadex.org", url: nil,
                    icon: nil, priority: 3, chapterCount: 900, fetchedDate: nil,
                    availability: .disabled, failureReason: "Check your connection and try again.",
                    failedDate: .now),
            ],
            onSetPrimary: { _ in },
            onReorder: { _ in },
            onRemove: { _ in }
        )
        .padding(16)
    }
    .background(.canvas)
}
