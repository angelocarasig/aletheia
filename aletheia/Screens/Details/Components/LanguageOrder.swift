//
//  LanguageOrder.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import SwiftUI

// the first tier a chapter is ranked by, above the source it came from. a source
// is a preference; a language you cannot read is a wall, so the preferred site's
// chinese copy loses to a lower site's english one. two copies in the same
// language tie here and fall through to source priority as before.
//
// flat rather than sectioned because this is consulted before the source is - the
// rows it compares come from different sites, so an ordering per site could not
// answer the question being asked
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

    // every series carries seeded priority rows, so the listed order is always
    // the stored order and done only has work to do once something moved
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
        // presented before the read lands, so the rows arrive after init. an
        // empty working set seeds wholesale; a populated one merges - counts
        // refresh, the staged order survives, and a language a mid-sheet fetch
        // just introduced appends at the end instead of never appearing
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

private extension LanguageOrder {
    @ViewBuilder
    var Content: some View {
        if working.isEmpty, isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if working.isEmpty {
            ContentUnavailableView(
                "No Languages",
                systemImage: "character.bubble",
                description: Text("No chapters have been fetched for this series yet.")
            )
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
            // always active, so the handles are there without an Edit button
            .environment(\.editMode, .constant(.active))
        }
    }

    func Row(_ language: Language) -> some View {
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
    struct Language: Identifiable, Hashable {
        // the LanguageCode raw value, which is what gets written back
        let id: String
        let flag: String
        let name: String
        let chapterCount: Int
    }
}
