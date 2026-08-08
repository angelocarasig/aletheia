//
//  CollectionForm.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI

struct CollectionForm: View {
    let isSaving: Bool
    var onCreate: (String, String?) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Field?

    @State private var name = ""
    @State private var summary = ""

    private enum Field {
        case name
        case summary
    }

    private enum Layout {
        static let nameLimit = 50
        static let summaryLimit = 200
        static let summaryLines = 3...6
        static let warnAt = 10
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isReserved: Bool {
        CollectionRecord.isReserved(trimmed)
    }

    private var canCreate: Bool {
        !trimmed.isEmpty && !isReserved && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .focused($focused, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focused = .summary }
                        .onChange(of: name) { _, value in
                            name = String(value.prefix(Layout.nameLimit))
                        }
                } header: {
                    Text("Name")
                } footer: {
                    // the reason replaces the counter rather than stacking under
                    // it - one footer, one thing to fix
                    if isReserved {
                        Text("“\(trimmed)” is used by the library itself. Pick another name.")
                            .foregroundStyle(Palette.warning)
                    } else {
                        Remaining(name.count, of: Layout.nameLimit)
                    }
                }

                Section {
                    TextField("Optional", text: $summary, axis: .vertical)
                        .lineLimit(Layout.summaryLines)
                        .focused($focused, equals: .summary)
                        .onChange(of: summary) { _, value in
                            summary = String(value.prefix(Layout.summaryLimit))
                        }
                } header: {
                    Text("Description")
                } footer: {
                    Remaining(summary.count, of: Layout.summaryLimit)
                }
            }
            .navigationTitle("New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        let description = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCreate(trimmed, description.isEmpty ? nil : description)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canCreate)
                }
            }
            .task { focused = .name }
        }
        .presentationDetents([.medium, .large])
    }

    // silent until the limit is close, so it reads as a warning rather than a
    // running commentary on typing
    @ViewBuilder
    private func Remaining(_ used: Int, of limit: Int) -> some View {
        let left = limit - used

        if left <= Layout.warnAt {
            Text("^[\(left) character](inflect: true) left")
                .foregroundStyle(left == 0 ? Palette.warning : Palette.muted)
        }
    }
}

#Preview("New collection") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CollectionForm(isSaving: false, onCreate: { _, _ in })
    }
}

#Preview("Saving") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CollectionForm(isSaving: true, onCreate: { _, _ in })
    }
}
