//
//  ReaderFiltersSheet.swift
//  aletheia
//
//  Created by Angelo Carasig on 13/8/2026.
//

import SwiftUI

// what the page looks like, as opposed to how it moves. the split is the same
// one Mihon, Kotatsu and Suwatte all draw: the gearshape holds layout and
// behaviour, this holds the four things that change the pixels.
//
// global, like everything behind the gearshape. per-series filters are the one
// idea worth taking from Kotatsu and they need a column, so they are not here
struct ReaderFiltersSheet: View {
    let engine: ReaderEngine

    var onDim: (Double) -> Void
    var onGrayscale: (Bool) -> Void
    var onInverted: (Bool) -> Void
    var onWarmth: (Double) -> Void
    var onKeepScreenOn: (Bool) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss

    private enum Layout {
        static let fillOpacity: Double = 0.08
        static let pillOpacity: Double = 0.12
    }

    var body: some View {
        NavigationStack {
            Content
                .navigationTitle("Filters")
                .navigationSubtitle(Text("Saved across all your series"))
                .navigationBarTitleDisplayMode(.inline)
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

extension ReaderFiltersSheet {
    fileprivate var Content: some View {
        let configuration = engine.configuration

        return ScrollView {
            VStack(spacing: dimensions.spacing.space8) {
                BrightnessRow(configuration.dim)
                WarmthRow(configuration.warmth)
                ToneRow(configuration)
                AwakeRow(configuration.keepScreenOn)
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.top, dimensions.spacing.space8)
            .padding(.bottom, dimensions.spacing.space24)
        }
        .scrollContentBackground(.hidden)
    }

    // stated as brightness and stored as dim, so the slider runs the way the
    // word does: right is brighter, and the value behind it goes the other way.
    // the ceiling is what the screen can already do at its own minimum
    fileprivate func BrightnessRow(_ dim: Double) -> some View {
        let maximum = ReaderConfiguration.Defaults.maxDim

        return Card {
            SliderHeader(
                "Brightness",
                "Dims below what the screen alone can reach.",
                value: (1 - dim / maximum).formatted(.percent.precision(.fractionLength(0)))
            )

            Slider(
                value: Binding(get: { maximum - dim }, set: { onDim(maximum - $0) }),
                in: 0...maximum
            ) {
                Text("Brightness")
            } minimumValueLabel: {
                Bound("moon.fill")
            } maximumValueLabel: {
                Bound("sun.max.fill")
            }
            .tint(Palette.brand)
        }
    }

    fileprivate func WarmthRow(_ warmth: Double) -> some View {
        let maximum = ReaderConfiguration.Defaults.maxWarmth
        let strength = (abs(warmth) / maximum).formatted(.percent.precision(.fractionLength(0)))

        return Card {
            SliderHeader(
                "Tint",
                "Warmer takes the blue out for reading at night. Cooler pulls back a page that runs yellow.",
                value: warmth == 0
                    ? "Neutral" : (warmth < 0 ? "Cool \(strength)" : "Warm \(strength)")
            )

            // stepped where its neighbours are continuous, because this is the
            // only slider whose default sits in the middle - on a continuous
            // track neutral is a value you can approach and never land on
            Slider(
                value: Binding(get: { warmth }, set: onWarmth),
                in: -maximum...maximum,
                step: ReaderConfiguration.Defaults.warmthStep
            ) {
                Text("Tint")
            } minimumValueLabel: {
                Bound("snowflake")
            } maximumValueLabel: {
                Bound("flame.fill")
            }
            .tint(Palette.brand)
        }
    }

    fileprivate func ToneRow(_ configuration: ReaderConfiguration) -> some View {
        Card {
            Toggle(isOn: Binding(get: { configuration.grayscale }, set: onGrayscale)) {
                Row("Grayscale", "Drops colour. Kinder to a colour page read in the dark.")
            }

            Divider()

            Toggle(isOn: Binding(get: { configuration.inverted }, set: onInverted)) {
                Row("Invert", "Flips black and white, for scans that are the wrong way round.")
            }
        }
        .tint(Palette.brand)
    }

    fileprivate func AwakeRow(_ keepScreenOn: Bool) -> some View {
        Card {
            Toggle(isOn: Binding(get: { keepScreenOn }, set: onKeepScreenOn)) {
                Row("Keep Screen On", "The display will not sleep while you are reading.")
            }
        }
        .tint(Palette.brand)
    }
}

// MARK: - Primitives

extension ReaderFiltersSheet {
    fileprivate func Card(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            content()
        }
        .padding(dimensions.spacing.space16)
        .background {
            RoundedRectangle(cornerRadius: dimensions.radius.radius16)
                .fill(.primary.opacity(Layout.fillOpacity))
        }
    }

    fileprivate func Bound(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    fileprivate func Row(_ title: String, _ summary: String) -> some View {
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
    }

    fileprivate func SliderHeader(_ title: String, _ summary: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Row(title, summary)

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
