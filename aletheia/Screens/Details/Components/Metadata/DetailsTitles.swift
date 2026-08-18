//
//  DetailsTitles.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI

struct DetailsTitles: View {
    let titles: [Title]
    let isSaving: Bool
    var onSetPreferred: (Int64?) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    private enum Layout {
        static let iconSize: CGFloat = 22
        static let fillOpacity: Double = 0.1
        static let tintOpacity: Double = 0.3
        static let savingOpacity: Double = 0.6
        static let settle: Animation = .smooth(duration: 0.2)
    }

    private var sourceCount: Int {
        Set(titles.compactMap(\.sourceName)).count
    }

    // the tint moves between rows once the write comes back through the
    // observation, well after the tap's own transaction has closed - the
    // ancestor's own .animation is what drives that transition, not the tap
    private var preferred: Int64? {
        titles.first(where: \.isPreferred)?.id
    }

    var body: some View {
        NavigationStack {
            Content
                .navigationTitle("Titles")
                .navigationSubtitle(
                    "^[\(titles.count) title](inflect: true) · ^[\(sourceCount) source](inflect: true)"
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var Content: some View {
        if titles.isEmpty {
            EmptyState
        } else {
            ScrollView {
                Explanation

                GlassEffectContainer(spacing: dimensions.spacing.space8) {
                    LazyVStack(spacing: dimensions.spacing.space8) {
                        AutomaticRow
                            .tappable {
                                guard preferred != nil else { return }
                                onSetPreferred(nil)
                            }

                        ForEach(titles) { title in
                            Row(title)
                                .tappable {
                                    guard !title.isPreferred else { return }
                                    onSetPreferred(title.id)
                                }
                        }
                    }
                }
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.bottom, dimensions.spacing.space24)
            }
            .opacity(isSaving ? Layout.savingOpacity : 1)
            .animation(Layout.settle, value: preferred)
        }
    }

    private var Explanation: some View {
        Text("The one you pick is shown everywhere: your library, search results, and this screen.")
            .font(.footnote)
            .foregroundStyle(.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.bottom, dimensions.spacing.space12)
    }

    private var AutomaticRow: some View {
        HStack(spacing: dimensions.spacing.space12) {
            Image(systemName: "wand.and.stars")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: Layout.iconSize, height: Layout.iconSize)

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text("Automatic")
                    .font(.subheadline)
                    .fontWeight(preferred == nil ? .semibold : .regular)

                Text("Decided by source priority")
                    .font(.caption)
                    .foregroundStyle(.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if preferred == nil {
                Check
            }
        }
        .padding(dimensions.spacing.space12)
        .glassEffect(
            preferred == nil
                ? .regular.tint(Palette.brand.opacity(Layout.tintOpacity))
                : .regular.interactive(),
            in: .rect(cornerRadius: dimensions.radius.radius16)
        )
        .contentShape(.rect)
        .accessibilityAddTraits(preferred == nil ? .isSelected : [])
    }

    private func Row(_ title: Title) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            Icon(title)

            Text(title.value)
                .font(.subheadline)
                .fontWeight(title.isPreferred ? .semibold : .regular)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            if title.isPreferred {
                Check
            }
        }
        .padding(dimensions.spacing.space12)
        .glassEffect(
            title.isPreferred
                ? .regular.tint(Palette.brand.opacity(Layout.tintOpacity))
                : .regular.interactive(),
            in: .rect(cornerRadius: dimensions.radius.radius16)
        )
        .contentShape(.rect)
        .accessibilityAddTraits(title.isPreferred ? .isSelected : [])
    }

    private var Check: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(.brand)
            .transition(.scale.combined(with: .opacity))
    }

    @ViewBuilder
    private func Icon(_ title: Title) -> some View {
        Group {
            if let icon = title.sourceIcon {
                Image(icon)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: dimensions.radius.radius4)
                    .fill(.primary.opacity(Layout.fillOpacity))
            }
        }
        .frame(width: Layout.iconSize, height: Layout.iconSize)
        .clipShape(.rect(cornerRadius: dimensions.radius.radius4))
    }

    private var EmptyState: some View {
        ContentUnavailableView(
            "No Titles",
            systemImage: "textformat",
            description: Text("This series has no alternative titles stored yet")
        )
    }
}

extension DetailsTitles {
    typealias Title = DetailsComposer.Series.Title
}

// MARK: - Previews

private enum Sample {
    static func title(
        _ id: Int64,
        _ value: String,
        source: String? = "MangaFire",
        icon: ImageResource? = .mangaFire,
        preferred: Bool = false
    ) -> DetailsTitles.Title {
        .init(id: id, value: value, sourceName: source, sourceIcon: icon, isPreferred: preferred)
    }

    static let pool: [DetailsTitles.Title] = [
        title(
            1,
            """
            Tsuihou-kei no Akuyaku Party no Leader ni Tensei Shita node, Zamaa Sareru \
            Mae ni Jibun o Tsuihou Shimashita.
            """, preferred: true),
        title(2, "I Exiled Myself Before the Villains Could", source: "MangaDex", icon: .mangaDex),
        title(3, "Tsuihou-kei no Akuyaku Party", source: "MangaDex", icon: .mangaDex),
        title(4, "追放系の悪役パーティーのリーダーに転生したので", source: nil, icon: nil),
    ]
}

#Preview("Titles") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DetailsTitles(
            titles: Sample.pool,
            isSaving: false,
            onSetPreferred: { _ in }
        )
    }
}

#Preview("No preference") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DetailsTitles(
            titles: Sample.pool.map {
                .init(
                    id: $0.id, value: $0.value, sourceName: $0.sourceName,
                    sourceIcon: $0.sourceIcon, isPreferred: false)
            },
            isSaving: false,
            onSetPreferred: { _ in }
        )
    }
}

#Preview("Single title") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DetailsTitles(
            titles: [Sample.pool[0]],
            isSaving: false,
            onSetPreferred: { _ in }
        )
    }
}

#Preview("Saving") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DetailsTitles(
            titles: Sample.pool,
            isSaving: true,
            onSetPreferred: { _ in }
        )
    }
}

#Preview("Empty") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DetailsTitles(
            titles: [],
            isSaving: false,
            onSetPreferred: { _ in }
        )
    }
}
