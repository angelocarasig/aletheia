//
//  LibraryActions.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import SwiftUI

struct LibraryActions: View {
    @Environment(\.dimensions) private var dimensions

    var onSort: () -> Void
    var onFilter: () -> Void
    var filtered = false
    // @Binding, not @State - the two floating clusters are mutually exclusive,
    // and only the screen can see both to enforce that
    @Binding var expanded: Bool

    @Namespace private var namespace

    private enum Layout {
        static let dot: CGFloat = 10
        static let dotBorder: CGFloat = 2
    }

    var body: some View {
        // spacing controls how far the options separate out of the root before
        // Liquid Glass reads them as one blob
        GlassEffectContainer(spacing: dimensions.spacing.space12) {
            VStack(spacing: dimensions.spacing.space12) {
                if expanded {
                    Action("Sort", systemImage: "arrow.up.arrow.down", id: "sort", action: onSort)
                    Action("Filter", image: Image(.filter), id: "filter", action: onFilter)
                }

                Root
            }
        }
    }
}

// MARK: - Buttons

extension LibraryActions {
    fileprivate var Root: some View {
        Image(systemName: expanded ? "xmark" : "line.3.horizontal.decrease")
            .contentTransition(.symbolEffect(.replace))
            .font(.system(size: dimensions.size.icon20, weight: .medium))
            .frame(width: dimensions.size.controlL, height: dimensions.size.controlL)
            .glassEffect(.regular.interactive(), in: .circle)
            .glassEffectID("root", in: namespace)
            // outside the glass container, or the dot would be sampled into the
            // surface instead of sitting on top of it
            .overlay(alignment: .topTrailing) {
                if filtered, !expanded {
                    Dot
                }
            }
            .contentShape(.circle)
            .tappable {
                withAnimation(.smooth) { expanded.toggle() }
            }
            .accessibilityLabel(expanded ? "Close options" : "Library options")
    }

    // the ring keeps this legible against whatever the glass surface has sampled
    // from behind it
    fileprivate var Dot: some View {
        Circle()
            .fill(.danger)
            .frame(width: Layout.dot, height: Layout.dot)
            .overlay {
                Circle().strokeBorder(Color.background, lineWidth: Layout.dotBorder)
            }
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Filters applied")
    }

    fileprivate func Action(
        _ label: String,
        systemImage: String? = nil,
        image: Image? = nil,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        Group {
            if let systemImage {
                Image(systemName: systemImage)
            } else if let image {
                image.renderingMode(.template)
            }
        }
        .font(.system(size: dimensions.size.icon16, weight: .medium))
        .frame(width: dimensions.size.control, height: dimensions.size.control)
        .glassEffect(.regular.interactive(), in: .circle)
        .glassEffectID(id, in: namespace)
        .contentShape(.circle)
        .tappable {
            withAnimation(.smooth) { expanded = false }
            action()
        }
        .accessibilityLabel(label)
    }
}
