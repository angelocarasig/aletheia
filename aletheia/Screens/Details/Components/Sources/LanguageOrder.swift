//
//  LanguageOrder.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import SwiftUI

// ranks above source priority when a chapter is selected - a language you
// cannot read is a wall, so the preferred site's copy in a lower-ranked
// language still loses to a lower site's copy in a higher one
struct LanguageOrder: View {
    let languages: [Language]
    let isLoading: Bool
    var onCommit: ([String]) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    @State private var working: [Language]

    init(languages: [Language], isLoading: Bool, onCommit: @escaping ([String]) -> Void) {
        self.languages = languages
        self.isLoading = isLoading
        self.onCommit = onCommit
        _working = State(initialValue: languages)
    }

    private var committable: Bool {
        !working.isEmpty && working.map(\.id) != languages.map(\.id)
    }

    var body: some View {
        NavigationStack {
            Content
                .navigationTitle("Language Priority")
                .navigationSubtitle("Checked before source priority")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            if committable { onCommit(working.map(\.id)) }
                            dismiss()
                        }
                        .fontWeight(.semibold)
                        .disabled(!committable)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .animation(.settle, value: phase)
        // an empty working set seeds wholesale; a populated one merges - the
        // staged order survives, and a language a mid-sheet fetch just
        // introduced appends at the end instead of never appearing
        .onChange(of: languages) { _, latest in
            guard !working.isEmpty else {
                working = latest
                return
            }
            let staged = working.map(\.id)
            let byId = Dictionary(uniqueKeysWithValues: latest.map { ($0.id, $0) })
            working = staged.compactMap { byId[$0] } + latest.filter { !staged.contains($0.id) }
        }
    }
}

// MARK: - Content

extension LanguageOrder {
    fileprivate var phase: LoadPhase {
        if !working.isEmpty { .content } else if isLoading { .pending } else { .empty }
    }

    @ViewBuilder
    fileprivate var Content: some View {
        if working.isEmpty, isLoading {
            SheetSkeleton(rows: 4)
                .transition(.opacity)
        } else if working.isEmpty {
            ContentUnavailableView(
                "No Languages",
                systemImage: "character.bubble",
                description: Text("No chapters have been fetched for this series yet.")
            )
            .transition(.opacity)
        } else {
            List {
                Section {
                    ForEach(working) { language in
                        Row(language)
                    }
                    .onMove { source, destination in
                        working.move(fromOffsets: source, toOffset: destination)
                    }
                }
            }
            // forced active - the drag handles show without a separate Edit button
            .environment(\.editMode, .constant(.active))
            .transition(.opacity)
        }
    }

    fileprivate func Row(_ language: Language) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            Text(language.flag)
                .font(.title3)

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(language.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("^[\(language.chapterCount) chapter](inflect: true)")
                    .font(.caption2)
                    .foregroundStyle(.muted)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Model

extension LanguageOrder {
    typealias Language = DetailsComposer.Sources.Language
}
