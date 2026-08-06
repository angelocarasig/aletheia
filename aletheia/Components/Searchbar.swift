//
//  Searchbar.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI

struct Searchbar: View {
    struct Submit {
        var icon: String
        var backgroundColor: Color?
        var prompt: (String) -> String
        var action: (String) -> Void

        init(
            icon: String = "globe",
            backgroundColor: Color? = nil,
            prompt: @escaping (String) -> String,
            action: @escaping (String) -> Void
        ) {
            self.icon = icon
            self.backgroundColor = backgroundColor
            self.prompt = prompt
            self.action = action
        }
    }

    @Environment(\.dimensions) private var dimensions

    @Binding var searchText: String
    var placeholder: String
    var backgroundColor: Color?
    var cornerRadii: RectangleCornerRadii?
    var submit: Submit?

    init(
        searchText: Binding<String>,
        placeholder: String = "Search",
        backgroundColor: Color? = nil,
        cornerRadii: RectangleCornerRadii? = nil,
        submit: Submit? = nil
    ) {
        self._searchText = searchText
        self.placeholder = placeholder
        self.backgroundColor = backgroundColor
        self.cornerRadii = cornerRadii
        self.submit = submit
    }

    var body: some View {
        VStack(spacing: dimensions.spacing.space8) {
            SearchField

            if let submit, !searchText.isEmpty {
                SubmitPrompt(submit)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: searchText)
    }

    private var SearchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.muted)

            TextField(placeholder, text: $searchText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.muted)
                        .font(.headline)
                }
            }
        }
        .padding()
        .frame(height: dimensions.size.control)
        .background(backgroundColor ?? .surface)
        .clipShape(
            UnevenRoundedRectangle(cornerRadii: cornerRadii ?? .init(
                topLeading: dimensions.radius.radius12,
                bottomLeading: dimensions.radius.radius12,
                bottomTrailing: dimensions.radius.radius12,
                topTrailing: dimensions.radius.radius12
            ))
        )
        .scrollDismissesKeyboard(.immediately)
    }

    @ViewBuilder
    private func SubmitPrompt(_ submit: Submit) -> some View {
        HStack {
            Image(systemName: submit.icon)
                .font(.subheadline)
            Text(submit.prompt(searchText))
                .font(.subheadline)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(submit.backgroundColor ?? Color(.quaternarySystemFill))
        .clipShape(.rect(cornerRadius: dimensions.radius.radius8))
        .tappable {
            submit.action(searchText)
        }
    }
}
