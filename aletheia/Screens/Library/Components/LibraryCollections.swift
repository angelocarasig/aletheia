//
//  LibraryCollections.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import SwiftUI

struct LibraryCollections: View {
    @Environment(\.dimensions) private var dimensions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var collections: [LibraryViewModel.Collection]
    var total: Int
    @Binding var selected: CollectionRecord.ID?
    var onCreate: () -> Void
    var onRename: (LibraryViewModel.Collection) -> Void
    var onDelete: (LibraryViewModel.Collection) -> Void
    // @Binding, not @State - the two floating clusters are mutually exclusive,
    // and only the screen can see both to enforce that
    @Binding var expanded: Bool

    @Namespace private var glass

    private enum Layout {
        static let selectedFill: Double = 0.16
        static let restingFill: Double = 0.06
        static let dashed = StrokeStyle(lineWidth: 1, dash: [4, 3])
    }

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .smooth
    }

    var body: some View {
        GlassEffectContainer(spacing: dimensions.spacing.space12) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                if expanded {
                    Panel
                }

                Root
            }
        }
    }
}

// MARK: - Root

extension LibraryCollections {
    fileprivate var Root: some View {
        Image(systemName: expanded ? "xmark" : "square.stack")
            .contentTransition(.symbolEffect(.replace))
            .font(.system(size: dimensions.size.icon20, weight: .medium))
            .frame(width: dimensions.size.controlL, height: dimensions.size.controlL)
            .glassEffect(tinted, in: .circle)
            .glassEffectID("collections", in: glass)
            .contentShape(.circle)
            .tappable {
                withAnimation(animation) { expanded.toggle() }
            }
            .accessibilityLabel(expanded ? "Close collections" : "Collections")
    }

    fileprivate var tinted: Glass {
        selected == nil
            ? .regular.interactive()
            : .regular.tint(Palette.brand).interactive()
    }
}

// MARK: - Panel

extension LibraryCollections {
    // FlowLayout, not a horizontal scroll row - nesting a horizontal scroll
    // inside this vertical one is an accessibility trap
    fileprivate var Panel: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            Text("Collections")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: dimensions.spacing.space8) {
                Chip("All", count: total, id: nil)

                ForEach(collections) { collection in
                    Chip(collection.name, count: collection.count, id: collection.id)
                        .contextMenu {
                            Button("Rename", systemImage: "pencil") { onRename(collection) }
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                onDelete(collection)
                            }
                        }
                }

                New
            }
        }
        .padding(dimensions.spacing.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: dimensions.radius.radius20))
        .glassEffectID("collections", in: glass)
    }

    // plain fills, never nested glass - the panel is already a glass surface and
    // a second one on top of it flattens
    fileprivate func Chip(_ title: String, count: Int, id: CollectionRecord.ID?) -> some View {
        let isSelected = selected == id

        return HStack(spacing: dimensions.spacing.space4) {
            Text(title)
                .fontWeight(isSelected ? .semibold : .medium)
                .lineLimit(1)
                .truncationMode(.tail)

            Text("\(count)")
                .monospacedDigit()
                .foregroundStyle(.secondary)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
            }
        }
        .font(.subheadline)
        .padding(.horizontal, dimensions.spacing.space12)
        .frame(height: dimensions.touchTarget)
        .background(
            isSelected
                ? AnyShapeStyle(Palette.brand.opacity(Layout.selectedFill))
                : AnyShapeStyle(.primary.opacity(Layout.restingFill)),
            in: .capsule
        )
        .foregroundStyle(isSelected ? AnyShapeStyle(.brand) : AnyShapeStyle(.primary))
        .contentShape(.capsule)
        .tappable {
            withAnimation(animation) {
                selected = id
                expanded = false
            }
        }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    fileprivate var New: some View {
        Label("New", systemImage: "plus")
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.muted)
            .padding(.horizontal, dimensions.spacing.space12)
            .frame(height: dimensions.touchTarget)
            .overlay {
                Capsule().strokeBorder(.muted.opacity(0.4), style: Layout.dashed)
            }
            .contentShape(.capsule)
            .tappable {
                withAnimation(animation) { expanded = false }
                onCreate()
            }
    }
}
