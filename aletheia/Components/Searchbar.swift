//
//  Searchbar.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI

struct Searchbar: View {
    struct Handoff {
        var icon: String
        var tint: Color?
        var label: (String) -> String
        var onSelect: (String) -> Void

        init(
            icon: String = "globe",
            tint: Color? = nil,
            label: @escaping (String) -> String,
            onSelect: @escaping (String) -> Void
        ) {
            self.icon = icon
            self.tint = tint
            self.label = label
            self.onSelect = onSelect
        }
    }

    @Environment(\.dimensions) private var dimensions
    @FocusState private var focused: Bool

    private enum Motion {
        static let settle: Animation = .snappy(duration: 0.3)
        static let appear: AnyTransition = .scale(scale: 0.94, anchor: .top)
            .combined(with: .opacity)
        static let reveal: AnyTransition = .scale(scale: 0.6, anchor: .leading)
            .combined(with: .opacity)
    }

    @Binding var searchText: String
    var placeholder: String
    // nil takes glass; a caller passing a colour opts out of glass entirely
    var backgroundColor: Color?
    // ignored when backgroundColor is set
    var tint: Color?
    var handoff: Handoff?

    init(
        searchText: Binding<String>,
        placeholder: String = "Search",
        backgroundColor: Color? = nil,
        tint: Color? = nil,
        handoff: Handoff? = nil
    ) {
        self._searchText = searchText
        self.placeholder = placeholder
        self.backgroundColor = backgroundColor
        self.tint = tint
        self.handoff = handoff
    }

    var body: some View {
        VStack(spacing: dimensions.spacing.space8) {
            // spacing below the stack's own, or GlassEffectContainer merges the
            // two shapes into one capsule at rest
            GlassEffectContainer(spacing: dimensions.spacing.space4) {
                HStack(spacing: dimensions.spacing.space8) {
                    Field

                    if !searchText.isEmpty {
                        Clear
                            .transition(Motion.reveal)
                    }
                }
            }

            if let handoff, !searchText.isEmpty {
                HandoffRow(handoff)
                    .transition(Motion.appear)
            }
        }
        // keyed on emptiness, not the text - keying on searchText re-ran the
        // animation on every keystroke
        .animation(Motion.settle, value: searchText.isEmpty)
    }
}

// MARK: - Field

extension Searchbar {
    @ViewBuilder
    fileprivate var Field: some View {
        if let backgroundColor {
            Input.background(backgroundColor, in: .capsule)
        } else if let tint {
            Input.glassEffect(.regular.tint(tint).interactive(), in: .capsule)
        } else {
            Input.glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    fileprivate var Input: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.muted)

            TextField(placeholder, text: $searchText)
                .focused($focused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
        }
        .padding(.horizontal, dimensions.spacing.space16)
        .frame(height: dimensions.touchTarget)
        .contentShape(.capsule)
        .onTapGesture { focused = true }
        .scrollDismissesKeyboard(.immediately)
    }

    // no foregroundStyle set - glass resolves its own content colour
    fileprivate var Clear: some View {
        Image(systemName: "xmark")
            .font(.system(size: dimensions.size.icon16, weight: .semibold))
            .frame(width: dimensions.touchTarget, height: dimensions.touchTarget)
            .glassEffect(.regular.interactive(), in: .circle)
            .contentShape(.circle)
            .tappable { searchText = "" }
            .accessibilityLabel("Clear search")
    }
}

// MARK: - Handoff

extension Searchbar {
    fileprivate func HandoffRow(_ handoff: Handoff) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            Image(systemName: handoff.icon)
                .font(.subheadline.weight(.semibold))

            Text(handoff.label(searchText))
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, dimensions.spacing.space16)
        .padding(.vertical, dimensions.spacing.space12)
        .frame(minHeight: dimensions.touchTarget)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(glass(for: handoff), in: .rect(cornerRadius: dimensions.radius.radius16))
        .contentShape(.rect)
        .tappable {
            handoff.onSelect(searchText)
        }
    }

    fileprivate func glass(for handoff: Handoff) -> Glass {
        guard let tint = handoff.tint else { return .regular.interactive() }
        return .regular.tint(tint).interactive()
    }
}
