//
//  LibraryActions.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import SwiftUI

// one floating control that opens into its own options, the way Books handles
// the same two jobs. a toolbar item would put them at the far end of the reach
// arc, above a screen you scroll with your thumb
struct LibraryActions: View {
    @Environment(\.dimensions) private var dimensions

    var onSort: () -> Void
    var onFilter: () -> Void
    var filtered = false
    // owned by the screen, not the control: the two floating clusters are
    // mutually exclusive, and only their parent can see both
    @Binding var expanded: Bool

    @Namespace private var namespace

    private enum Layout {
        static let dot: CGFloat = 10
        static let dotBorder: CGFloat = 2
    }

    var body: some View {
        // spacing is what lets the options separate out of the root instead of
        // appearing beside it - inside this distance the shapes read as one blob
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

private extension LibraryActions {
    var Root: some View {
        Image(systemName: expanded ? "xmark" : "line.3.horizontal.decrease")
            .font(.system(size: dimensions.size.icon20, weight: .medium))
            .frame(width: dimensions.size.controlL, height: dimensions.size.controlL)
            .glassEffect(.regular.interactive(), in: .circle)
            .glassEffectID("root", in: namespace)
            // outside the glass, or it would be sampled into the surface rather
            // than sit on it. hidden while open, where the filter row is visible
            // and the dot would be describing something you are looking at
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

    // a notification, not decoration: something is being hidden from you right
    // now. the ring keeps it legible against whatever the glass has sampled
    var Dot: some View {
        Circle()
            .fill(.danger)
            .frame(width: Layout.dot, height: Layout.dot)
            .overlay {
                Circle().strokeBorder(Color.background, lineWidth: Layout.dotBorder)
            }
            .transition(.scale.combined(with: .opacity))
            .accessibilityLabel("Filters applied")
    }

    // collapsing on select is the point of the cluster: the option it opened is
    // now on screen, and leaving it expanded behind a sheet means dismissing twice
    func Action(
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
