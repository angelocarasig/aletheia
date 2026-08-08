//
//  Searchbar.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI

// shaped after the system field on iOS 26: the input is one capsule and the clear
// action is a SEPARATE circle beside it, not a glyph living inside the field.
//
// two surfaces rather than one is the whole point - an inline xmark competes with
// the text for the same space and grows the field's tap target into something
// that does two different things depending on where you land
struct Searchbar: View {
    // where the same query goes when this field is not enough - sources search
    // hands off to every source, library search hands off to sources. not a
    // submit: nothing here commits what was typed, it re-runs it somewhere wider
    struct Handoff {
        var icon: String
        // a tint ON the glass, not a fill behind it. a solid colour here reads as
        // an iOS 18 filled row and, worse, stops the surface sampling what it
        // sits over - which is the whole of what makes it glass
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
        // grows out of the field's trailing edge rather than fading in place
        static let reveal: AnyTransition = .scale(scale: 0.6, anchor: .leading)
            .combined(with: .opacity)
    }

    @Binding var searchText: String
    var placeholder: String
    // nil takes glass. a caller passing a colour is saying "the surface is mine" -
    // .clear means the parent already drew one and this should add nothing
    var backgroundColor: Color?
    // a tint on the field's own glass, for callers marking the field itself -
    // an adult-only source's danger wash. ignored when backgroundColor is set
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
            // spacing below the stack's own, or the two shapes blend into one
            // capsule at rest and the separation is lost
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
        // keyed on emptiness, not the text: the clear button and the handoff row
        // appearing are the events worth animating, and every keystroke was
        // re-running it
        .animation(Motion.settle, value: searchText.isEmpty)
    }
}

// MARK: - Field

private extension Searchbar {
    @ViewBuilder
    var Field: some View {
        if let backgroundColor {
            Input.background(backgroundColor, in: .capsule)
        } else if let tint {
            Input.glassEffect(.regular.tint(tint).interactive(), in: .capsule)
        } else {
            Input.glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    var Input: some View {
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
        // the whole capsule focuses the field, not just the glyphs in it
        .onTapGesture { focused = true }
        .scrollDismissesKeyboard(.immediately)
    }

    // a circle, matching the system's trailing action. nothing sets a foreground:
    // glass resolves its own content colour from what it samples
    var Clear: some View {
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

private extension Searchbar {
    func HandoffRow(_ handoff: Handoff) -> some View {
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
        // nothing here sets a foreground colour beyond the chevron's secondary:
        // glass resolves its own light or dark appearance and vends a matching
        // content colour, and pinning one only ever matches by luck
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

    // .regular rather than .clear: this sits over the app's own content, not over
    // media, so it should adapt to what is behind it. interactive because it is a
    // button and the press response is the affordance
    func glass(for handoff: Handoff) -> Glass {
        guard let tint = handoff.tint else { return .regular.interactive() }
        return .regular.tint(tint).interactive()
    }
}
