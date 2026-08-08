//
//  DetailsEdit.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI

// picks which source speaks for the series. nothing here is typed by the user -
// every option came from an origin, so the choice is always between things that
// already exist rather than free text
struct DetailsEdit: View {
    let titles: [DetailsTitles.Title]
    let synopses: [Synopsis]
    let metadata: [Metadata]
    let isSaving: Bool
    var onSetTitle: (Int64?) -> Void
    var onSetSynopsis: (Int64?) -> Void
    var onSetMetadata: (Int64?) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    @State private var field: Field = .title

    private enum Layout {
        static let iconSize: CGFloat = 22
        static let fillOpacity: Double = 0.1
        static let tintOpacity: Double = 0.3
        static let savingOpacity: Double = 0.6
        static let synopsisLines = 6
        static let settle: Animation = .smooth(duration: 0.2)
    }

    private enum Field: String, CaseIterable, Identifiable {
        case title = "Title"
        case synopsis = "Synopsis"
        case status = "Status"

        var id: Self { self }
    }

    private var explanation: String {
        switch field {
        case .title: "Shown in your library, in search results, and on this screen."
        case .synopsis: "Sources write their own descriptions. Pick the one you'd rather read."
        case .status: "Ratings and publication status, taken from one source rather than merged."
        }
    }

    // the tint moves between rows on a write that comes back through the
    // observation, so the tap's own transaction is long closed by then
    private var selection: Int64? {
        switch field {
        case .title: titles.first(where: \.isPreferred)?.id
        case .synopsis: synopses.first(where: \.isPreferred)?.id
        case .status: metadata.first(where: \.isPreferred)?.id
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Field", selection: $field) {
                    ForEach(Field.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.bottom, dimensions.spacing.space12)

                Rows
            }
            .navigationTitle("Edit Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // picks apply instantly, so there is nothing to "do" - this
                    // button only closes
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

extension DetailsEdit {
    private var Rows: some View {
        ScrollView {
            Text(explanation)
                .font(.footnote)
                .foregroundStyle(.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.bottom, dimensions.spacing.space12)

            // one container so adjacent rows blend into a single surface rather
            // than reading as a stack of separate stickers
            GlassEffectContainer(spacing: dimensions.spacing.space8) {
                LazyVStack(spacing: dimensions.spacing.space8) {
                    switch field {
                    case .title:
                        if !titles.isEmpty { AutomaticRow { onSetTitle(nil) } }
                        Titles
                    case .synopsis:
                        if !synopses.isEmpty { AutomaticRow { onSetSynopsis(nil) } }
                        Synopses
                    case .status:
                        if !metadata.isEmpty { AutomaticRow { onSetMetadata(nil) } }
                        Statuses
                    }
                }
                // synopsis and status rows are both keyed by their origin id and
                // sit in the same position in the switch, so without this SwiftUI
                // reuses one branch's views for the other
                .id(field)
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.bottom, dimensions.spacing.space24)
        }
        .opacity(isSaving ? Layout.savingOpacity : 1)
        // has to sit on an ancestor of every row, so the tint leaving one and
        // arriving on another are the same transaction
        .animation(Layout.settle, value: selection)
        .animation(Layout.settle, value: field)
    }

    @ViewBuilder
    private var Titles: some View {
        if titles.isEmpty {
            Empty("No alternative titles stored")
        } else {
            ForEach(titles) { title in
                Row(preferred: title.isPreferred, icon: title.sourceIcon) {
                    Text(title.value)
                        .font(.subheadline)
                        .fontWeight(title.isPreferred ? .semibold : .regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                } action: {
                    onSetTitle(title.id)
                }
            }
        }
    }

    @ViewBuilder
    private var Synopses: some View {
        if synopses.isEmpty {
            Empty("No descriptions stored")
        } else {
            ForEach(synopses) { synopsis in
                Row(preferred: synopsis.isPreferred, icon: synopsis.sourceIcon) {
                    VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                        Source(synopsis.sourceName, preferred: synopsis.isPreferred)

                        Text(synopsis.text)
                            .font(.caption)
                            .foregroundStyle(.muted)
                            .lineLimit(Layout.synopsisLines)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } action: {
                    onSetSynopsis(synopsis.id)
                }
            }
        }
    }

    @ViewBuilder
    private var Statuses: some View {
        if metadata.isEmpty {
            Empty("No sources to take this from")
        } else {
            ForEach(metadata) { entry in
                Row(preferred: entry.isPreferred, icon: entry.sourceIcon) {
                    VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                        Source(entry.sourceName, preferred: entry.isPreferred)

                        HStack(spacing: dimensions.spacing.space8) {
                            Badge(text: entry.classification.rawValue, tone: entry.classification.tone)
                            Badge(text: entry.publication.rawValue, tone: entry.publication.tone)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } action: {
                    onSetMetadata(entry.id)
                }
            }
        }
    }

    private func Source(_ name: String?, preferred: Bool) -> some View {
        Text(name ?? "Unknown source")
            .font(.subheadline)
            .fontWeight(preferred ? .semibold : .medium)
    }

    // no pin set: display falls back to origin priority. clearing is a
    // first-class choice rather than a toggle side effect
    private func AutomaticRow(clear: @escaping () -> Void) -> some View {
        let automatic = selection == nil
        return HStack(spacing: dimensions.spacing.space12) {
            Image(systemName: "wand.and.stars")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: Layout.iconSize, height: Layout.iconSize)

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text("Automatic")
                    .font(.subheadline)
                    .fontWeight(automatic ? .semibold : .regular)

                Text("Decided by source priority")
                    .font(.caption)
                    .foregroundStyle(.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if automatic {
                Image(systemName: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.brand)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(dimensions.spacing.space12)
        .glassEffect(
            automatic
                ? .regular.tint(Palette.brand.opacity(Layout.tintOpacity))
                : .regular.interactive(),
            in: .rect(cornerRadius: dimensions.radius.radius16)
        )
        .contentShape(.rect)
        .accessibilityAddTraits(automatic ? .isSelected : [])
        .tappable {
            guard !automatic else { return }
            clear()
        }
    }

    // the current pick is not interactive glass - it cannot be tapped, so it
    // should not offer press feedback
    private func Row(
        preferred: Bool,
        icon: ImageResource?,
        @ViewBuilder content: () -> some View,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: dimensions.spacing.space12) {
            Icon(icon)
            content()

            if preferred {
                Image(systemName: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.brand)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(dimensions.spacing.space12)
        .glassEffect(
            preferred
                ? .regular.tint(Palette.brand.opacity(Layout.tintOpacity))
                : .regular.interactive(),
            in: .rect(cornerRadius: dimensions.radius.radius16)
        )
        .contentShape(.rect)
        .accessibilityAddTraits(preferred ? .isSelected : [])
        .tappable {
            guard !preferred else { return }
            action()
        }
    }

    @ViewBuilder
    private func Icon(_ icon: ImageResource?) -> some View {
        Group {
            if let icon {
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

    private func Empty(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.muted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, dimensions.spacing.space32)
    }
}

extension DetailsEdit {
    struct Synopsis: Identifiable, Hashable {
        // the origin it came from, not the series
        let id: Int64
        let sourceName: String?
        let sourceIcon: ImageResource?
        let text: String
        let isPreferred: Bool
    }

    struct Metadata: Identifiable, Hashable {
        let id: Int64
        let sourceName: String?
        let sourceIcon: ImageResource?
        let classification: Classification
        let publication: Publication
        let isPreferred: Bool
    }
}

// MARK: - Previews

private enum Sample {
    static let titles: [DetailsTitles.Title] = [
        .init(
            id: 1,
            value: "Tsuihou-kei no Akuyaku Party no Leader ni Tensei Shita node",
            sourceName: "MangaFire",
            sourceIcon: .mangaFire,
            isPreferred: true
        ),
        .init(id: 2, value: "I Exiled Myself Before the Villains Could", sourceName: "MangaDex", sourceIcon: .mangaDex, isPreferred: false),
        .init(id: 3, value: "追放系の悪役パーティーのリーダーに転生した", sourceName: nil, sourceIcon: nil, isPreferred: false)
    ]

    static let synopses: [DetailsEdit.Synopsis] = [
        .init(
            id: 10,
            sourceName: "MangaFire",
            sourceIcon: .mangaFire,
            text: """
                Reincarnated as the leader of a villain party fated for ruin, he exiles himself \
                before the story can catch up with him. What follows is less a redemption arc than \
                a long argument with fate.
                """,
            isPreferred: true
        ),
        .init(
            id: 11,
            sourceName: "MangaDex",
            sourceIcon: .mangaDex,
            text: "He was born into the party destined to lose. So he left first.",
            isPreferred: false
        )
    ]

    static let metadata: [DetailsEdit.Metadata] = [
        .init(id: 10, sourceName: "MangaFire", sourceIcon: .mangaFire, classification: .Safe, publication: .Ongoing, isPreferred: true),
        .init(id: 11, sourceName: "MangaDex", sourceIcon: .mangaDex, classification: .Suggestive, publication: .Hiatus, isPreferred: false)
    ]
}

#Preview("Edit details") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DetailsEdit(
            titles: Sample.titles,
            synopses: Sample.synopses,
            metadata: Sample.metadata,
            isSaving: false,
            onSetTitle: { _ in },
            onSetSynopsis: { _ in },
            onSetMetadata: { _ in }
        )
    }
}

// a single-origin series: every tab has exactly one option and nothing to choose
// between, which is the common case right after adding
#Preview("One source") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DetailsEdit(
            titles: [Sample.titles[0]],
            synopses: [Sample.synopses[0]],
            metadata: [Sample.metadata[0]],
            isSaving: false,
            onSetTitle: { _ in },
            onSetSynopsis: { _ in },
            onSetMetadata: { _ in }
        )
    }
}

#Preview("Nothing stored") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DetailsEdit(
            titles: [],
            synopses: [],
            metadata: [],
            isSaving: false,
            onSetTitle: { _ in },
            onSetSynopsis: { _ in },
            onSetMetadata: { _ in }
        )
    }
}

#Preview("Saving") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DetailsEdit(
            titles: Sample.titles,
            synopses: Sample.synopses,
            metadata: Sample.metadata,
            isSaving: true,
            onSetTitle: { _ in },
            onSetSynopsis: { _ in },
            onSetMetadata: { _ in }
        )
    }
}
