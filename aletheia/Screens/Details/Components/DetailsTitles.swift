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
    var onSetPreferred: (Int64) -> Void

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

    // the tint moves between rows on a write that comes back through the
    // observation, so the tap's own transaction is long closed by then
    private var preferred: Int64? {
        titles.first(where: \.isPreferred)?.id
    }

    var body: some View {
        NavigationStack {
            Content
                .navigationTitle("Titles")
                .navigationSubtitle("^[\(titles.count) title](inflect: true) · ^[\(sourceCount) source](inflect: true)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
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

                // one container so adjacent rows blend into a single surface
                // rather than reading as a stack of separate stickers
                GlassEffectContainer(spacing: dimensions.spacing.space8) {
                    LazyVStack(spacing: dimensions.spacing.space8) {
                        ForEach(titles) { title in
                            Row(title)
                                .tappable {
                                    // a series always displays under something, so
                                    // the pick can move but never be cleared
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
            // has to sit on an ancestor of every row, so the tint leaving one and
            // arriving on another are the same transaction
            .animation(Layout.settle, value: preferred)
        }
    }

    private var Explanation: some View {
        Text("The one you pick is shown everywhere — your library, search results, and this screen.")
            .font(.footnote)
            .foregroundStyle(.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.bottom, dimensions.spacing.space12)
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
                Image(systemName: "star.fill")
                    .font(.footnote)
                    .foregroundStyle(.warning)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(dimensions.spacing.space12)
        // the current pick is not interactive glass - it cannot be tapped, so it
        // should not offer press feedback
        .glassEffect(
            title.isPreferred
                ? .regular.tint(Palette.warning.opacity(Layout.tintOpacity))
                : .regular.interactive(),
            in: .rect(cornerRadius: dimensions.radius.radius16)
        )
        .contentShape(.rect)
    }

    @ViewBuilder
    private func Icon(_ title: Title) -> some View {
        Group {
            if let icon = title.sourceIcon {
                Image(icon)
                    .resizable()
                    .scaledToFit()
            } else {
                // the contributing source no longer ships with the app
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
    struct Title: Identifiable, Hashable {
        let id: Int64
        let value: String
        let sourceName: String?
        // nil when the contributing source is no longer installed
        let sourceIcon: ImageResource?
        let isPreferred: Bool
    }
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

    // a real pool: the romanised original, the licensed english release, a
    // shorthand, and the native script. lengths vary wildly, which is the thing
    // the row has to survive
    static let pool: [DetailsTitles.Title] = [
        title(1, """
            Tsuihou-kei no Akuyaku Party no Leader ni Tensei Shita node, Zamaa Sareru \
            Mae ni Jibun o Tsuihou Shimashita.
            """, preferred: true),
        title(2, "I Exiled Myself Before the Villains Could", source: "MangaDex", icon: .mangaDex),
        title(3, "Tsuihou-kei no Akuyaku Party", source: "MangaDex", icon: .mangaDex),
        title(4, "追放系の悪役パーティーのリーダーに転生したので", source: nil, icon: nil)
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

// nothing picked, so the fallback wording in the explanation is the operative
// half and no row carries the tint
#Preview("No preference") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DetailsTitles(
            titles: Sample.pool.map {
                .init(id: $0.id, value: $0.value, sourceName: $0.sourceName, sourceIcon: $0.sourceIcon, isPreferred: false)
            },
            isSaving: false,
            onSetPreferred: { _ in }
        )
    }
}

// the common case for a freshly added series - one source, one title, and the
// sheet still has to justify opening
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
