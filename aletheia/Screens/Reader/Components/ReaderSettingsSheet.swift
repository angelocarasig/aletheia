//
//  ReaderSettingsSheet.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/26.
//

import SwiftUI

// the gearshape's destination. everything here is a global preference that
// follows the reader between titles - the per-series mode stays in the
// overlay's mode menu, and the tap zones have their own picker behind the
// hand-tap button. values apply live behind the sheet, so the page is the
// preview
struct ReaderSettingsSheet: View {
    let engine: ReaderEngine

    var onPadding: (CGFloat) -> Void
    var onTint: (Double) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    private enum Layout {
        static let fillOpacity: Double = 0.08
        static let pillOpacity: Double = 0.12
        static let disabledOpacity: Double = 0.6
        static let paddingStep: CGFloat = 2
    }

    var body: some View {
        NavigationStack {
            Content
                .navigationTitle("Settings")
                .navigationSubtitle(Text("Saved across all your series"))
                .navigationBarTitleDisplayMode(.inline)
                // a navigation container paints an opaque layer of its own, which
                // would sit between the content and the sheet's glass
                .containerBackground(.clear, for: .navigation)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close", systemImage: "xmark") { dismiss() }
                            .labelStyle(.iconOnly)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Content

private extension ReaderSettingsSheet {
    var Content: some View {
        // read before any branch so the readouts stay body dependencies
        let configuration = engine.configuration
        return ScrollView {
            VStack(spacing: dimensions.spacing.space8) {
                PaddingRow(configuration)
                TintRow(configuration.chromeTint)
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.top, dimensions.spacing.space8)
            .padding(.bottom, dimensions.spacing.space24)
        }
        .scrollContentBackground(.hidden)
    }

    func PaddingRow(_ configuration: ReaderConfiguration) -> some View {
        let padding = configuration.horizontalPadding
        let active = configuration.mode.isContinuous
        return Card {
            SliderHeader(
                "Side Padding",
                active
                    ? "Breathing room beside the page."
                    : "Applies in Infinite Scroll.",
                value: "\(Int(padding))"
            )

            Slider(
                value: Binding(get: { padding }, set: onPadding),
                in: 0...ReaderConfiguration.Defaults.maxHorizontalPadding,
                step: Layout.paddingStep
            ) {
                Text("Side Padding")
            } minimumValueLabel: {
                Bound("rectangle.portrait")
            } maximumValueLabel: {
                Bound("rectangle.compress.vertical")
            }
            .tint(Palette.brand)
        }
        // still adjustable in a paged mode - the value is saved and the caption
        // says where it lands - but dimmed so the silence on screen reads as
        // intended rather than broken
        .opacity(active ? 1 : Layout.disabledOpacity)
    }

    func TintRow(_ tint: Double) -> some View {
        Card {
            SliderHeader(
                "Menu Darkness",
                "How dark the reader's menu glass is over the page.",
                value: tint.formatted(.percent.precision(.fractionLength(0)))
            )

            Slider(
                value: Binding(get: { tint }, set: onTint),
                in: 0...ReaderConfiguration.Defaults.maxChromeTint
            ) {
                Text("Menu Darkness")
            } minimumValueLabel: {
                Bound("sun.max")
            } maximumValueLabel: {
                Bound("moon")
            }
            .tint(Palette.brand)
        }
    }

    func Card(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            content()
        }
        .padding(dimensions.spacing.space16)
        .background {
            RoundedRectangle(cornerRadius: dimensions.radius.radius16)
                .fill(.primary.opacity(Layout.fillOpacity))
        }
    }

    func Bound(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    func SliderHeader(_ title: String, _ summary: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(value)
                .font(.footnote.monospacedDigit())
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, dimensions.spacing.space8)
                .padding(.vertical, dimensions.spacing.space2)
                .background(.primary.opacity(Layout.pillOpacity), in: .capsule)
        }
    }
}
