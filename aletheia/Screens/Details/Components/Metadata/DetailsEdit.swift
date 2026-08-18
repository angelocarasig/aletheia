//
//  DetailsEdit.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI

struct DetailsEdit: View {
    let titles: [DetailsTitles.Title]
    let synopses: [Synopsis]
    let metadata: [Metadata]
    let isSaving: Bool
    var onSetTitle: (Int64?) -> Void
    var onSetSynopsis: (Int64?) -> Void
    var onSetClassification: (Int64?) -> Void
    var onSetPublication: (Int64?) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    @State private var field: Field = .title
    @State private var stagedTitle: Int64?
    @State private var stagedSynopsis: Int64?
    @State private var stagedClassification: Int64?
    @State private var stagedPublication: Int64?
    @State private var touched = false

    init(
        titles: [DetailsTitles.Title],
        synopses: [Synopsis],
        metadata: [Metadata],
        isSaving: Bool,
        onSetTitle: @escaping (Int64?) -> Void,
        onSetSynopsis: @escaping (Int64?) -> Void,
        onSetClassification: @escaping (Int64?) -> Void,
        onSetPublication: @escaping (Int64?) -> Void
    ) {
        self.titles = titles
        self.synopses = synopses
        self.metadata = metadata
        self.isSaving = isSaving
        self.onSetTitle = onSetTitle
        self.onSetSynopsis = onSetSynopsis
        self.onSetClassification = onSetClassification
        self.onSetPublication = onSetPublication
        _stagedTitle = State(initialValue: titles.first(where: \.isPreferred)?.id)
        _stagedSynopsis = State(initialValue: synopses.first(where: \.isPreferred)?.id)
        _stagedClassification = State(initialValue: metadata.first(where: \.isClassification)?.id)
        _stagedPublication = State(initialValue: metadata.first(where: \.isPublication)?.id)
    }

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
        case rating = "Rating"
        case status = "Status"

        var id: Self { self }
    }

    private var explanation: String {
        switch field {
        case .title: "Shown in your library, in search results, and on this screen."
        case .synopsis: "Sources write their own descriptions. Pick the one you'd rather read."
        case .rating: "Which source decides whether this is blurred behind the adult filter."
        case .status: "Whether this is still running. Trackers usually know best."
        }
    }

    private var selection: Int64? {
        switch field {
        case .title: stagedTitle
        case .synopsis: stagedSynopsis
        case .rating: stagedClassification
        case .status: stagedPublication
        }
    }

    private var changed: Bool {
        stagedTitle != titles.first(where: \.isPreferred)?.id
            || stagedSynopsis != synopses.first(where: \.isPreferred)?.id
            || stagedClassification != metadata.first(where: \.isClassification)?.id
            || stagedPublication != metadata.first(where: \.isPublication)?.id
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if stagedTitle != titles.first(where: \.isPreferred)?.id {
                            onSetTitle(stagedTitle)
                        }
                        if stagedSynopsis != synopses.first(where: \.isPreferred)?.id {
                            onSetSynopsis(stagedSynopsis)
                        }
                        if stagedClassification != metadata.first(where: \.isClassification)?.id {
                            onSetClassification(stagedClassification)
                        }
                        if stagedPublication != metadata.first(where: \.isPublication)?.id {
                            onSetPublication(stagedPublication)
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!changed || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        // reseed only while nothing has been staged, or an external change
        // would overwrite the reader's pending pick
        .onChange(of: titles) { _, latest in
            guard !touched else { return }
            stagedTitle = latest.first(where: \.isPreferred)?.id
        }
        .onChange(of: synopses) { _, latest in
            guard !touched else { return }
            stagedSynopsis = latest.first(where: \.isPreferred)?.id
        }
        .onChange(of: metadata) { _, latest in
            guard !touched else { return }
            stagedClassification = latest.first(where: \.isClassification)?.id
            stagedPublication = latest.first(where: \.isPublication)?.id
        }
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

            GlassEffectContainer(spacing: dimensions.spacing.space8) {
                LazyVStack(spacing: dimensions.spacing.space8) {
                    switch field {
                    case .title:
                        if !titles.isEmpty { AutomaticRow { stagedTitle = nil } }
                        Titles
                    case .synopsis:
                        if !synopses.isEmpty { AutomaticRow { stagedSynopsis = nil } }
                        Synopses
                    case .rating:
                        if !metadata.isEmpty { AutomaticRow { stagedClassification = nil } }
                        Suppliers(.rating, staged: stagedClassification) {
                            stagedClassification = $0
                        }
                    case .status:
                        if !metadata.isEmpty { AutomaticRow { stagedPublication = nil } }
                        Suppliers(.status, staged: stagedPublication) { stagedPublication = $0 }
                    }
                }
                // the branches sit in the same position in the switch, so
                // without this SwiftUI reuses one branch's views for another
                .id(field)
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.bottom, dimensions.spacing.space24)
        }
        .opacity(isSaving ? Layout.savingOpacity : 1)
        .animation(Layout.settle, value: selection)
        .animation(Layout.settle, value: field)
    }

    @ViewBuilder
    private var Titles: some View {
        if titles.isEmpty {
            Empty("No alternative titles stored")
        } else {
            ForEach(titles) { title in
                let staged = stagedTitle == title.id

                Row(preferred: staged, icon: title.sourceIcon) {
                    Text(title.value)
                        .font(.subheadline)
                        .fontWeight(staged ? .semibold : .regular)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                } action: {
                    stagedTitle = title.id
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
                let staged = stagedSynopsis == synopsis.id

                Row(preferred: staged, icon: synopsis.sourceIcon) {
                    VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                        Source(synopsis.sourceName, preferred: staged)

                        Text(synopsis.text)
                            .font(.caption)
                            .foregroundStyle(.muted)
                            .lineLimit(Layout.synopsisLines)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } action: {
                    stagedSynopsis = synopsis.id
                }
            }
        }
    }

    @ViewBuilder
    private func Suppliers(
        _ answering: Field,
        staged current: Int64?,
        select: @escaping (Int64) -> Void
    ) -> some View {
        if metadata.isEmpty {
            Empty("No sources to take this from")
        } else {
            ForEach(metadata) { entry in
                let staged = current == entry.id

                Row(preferred: staged, icon: entry.sourceIcon) {
                    VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                        Source(entry.sourceName, preferred: staged, detached: entry.detached)

                        if answering == .rating {
                            Badge(
                                text: entry.classification.rawValue, tone: entry.classification.tone
                            )
                        } else {
                            Badge(text: entry.publication.rawValue, tone: entry.publication.tone)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } action: {
                    select(entry.id)
                }
            }
        }
    }

    private func Source(_ name: String?, preferred: Bool, detached: Bool = false) -> some View {
        Text(detached ? "\(name ?? "Unknown source") (removed)" : (name ?? "Unknown source"))
            .font(.subheadline)
            .fontWeight(preferred ? .semibold : .medium)
    }

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
            touched = true
            clear()
        }
    }

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
            touched = true
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
    typealias Synopsis = DetailsComposer.Series.Synopsis

    typealias Metadata = DetailsComposer.Series.Metadata
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
        .init(
            id: 2, value: "I Exiled Myself Before the Villains Could", sourceName: "MangaDex",
            sourceIcon: .mangaDex, isPreferred: false),
        .init(
            id: 3, value: "追放系の悪役パーティーのリーダーに転生した", sourceName: nil, sourceIcon: nil,
            isPreferred: false),
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
        ),
    ]

    static let metadata: [DetailsEdit.Metadata] = [
        .init(
            id: 10, sourceName: "MangaFire", sourceIcon: .mangaFire, classification: .Safe,
            publication: .Ongoing, isClassification: true, isPublication: false, detached: false),
        .init(
            id: 11, sourceName: "AniList", sourceIcon: .aniList, classification: .Suggestive,
            publication: .Hiatus, isClassification: false, isPublication: true, detached: false),
        .init(
            id: 12, sourceName: "MangaDex", sourceIcon: nil, classification: .Suggestive,
            publication: .Ongoing, isClassification: false, isPublication: false, detached: true),
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
            onSetClassification: { _ in },
            onSetPublication: { _ in }
        )
    }
}

#Preview("One source") {
    Color.clear.sheet(isPresented: .constant(true)) {
        DetailsEdit(
            titles: [Sample.titles[0]],
            synopses: [Sample.synopses[0]],
            metadata: [Sample.metadata[0]],
            isSaving: false,
            onSetTitle: { _ in },
            onSetSynopsis: { _ in },
            onSetClassification: { _ in },
            onSetPublication: { _ in }
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
            onSetClassification: { _ in },
            onSetPublication: { _ in }
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
            onSetClassification: { _ in },
            onSetPublication: { _ in }
        )
    }
}
