//
//  RecommendationsScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/2026
//

import SwiftUI

struct RecommendationsScreen: View {
    @State private var vm = RecommendationsViewModel()
    @Environment(\.dimensions) private var dimensions

    @State private var showingAnalytics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("Models")

                    ForEach(RecommendationModelOption.all) { option in
                        ModelRow(option)
                            .task { vm.watch(option) }
                    }
                }

                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("Diagnostics")

                    SettingsCard(
                        title: "Analytics",
                        systemImage: "sparkle.magnifyingglass",
                        detail: "What the model showed, and what came of it"
                    ) { showingAnalytics = true }
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.vertical, dimensions.spacing.space16)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .navigationTitle("Recommendations")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showingAnalytics) { ImpressionsScreen() }
    }

    @ViewBuilder
    private func ModelRow(_ option: RecommendationModelOption) -> some View {
        let state = vm.states[option.packId] ?? .init()

        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            HStack(spacing: dimensions.spacing.space12) {
                VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                    HStack(spacing: dimensions.spacing.space8) {
                        Text(option.name)
                            .font(.subheadline)
                            .fontWeight(.semibold)

                        if vm.isActive(option) {
                            Text("Active")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundStyle(Palette.Tone.success.text)
                                .padding(.horizontal, dimensions.spacing.space8)
                                .padding(.vertical, dimensions.spacing.space2)
                                .background(Palette.Tone.success.subtle, in: .capsule)
                        }
                    }

                    Text(option.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Action(option, state: state)
            }

            if let progress = state.progress {
                ProgressView(value: progress)
                    .tint(.brand)
            }

            if let message = state.errorMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.danger)
                    .lineLimit(2)
            }
        }
        .padding(dimensions.spacing.space12)
        .frame(minHeight: dimensions.touchTarget)
        .glassEffect(
            .regular.interactive(),
            in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
    }

    @ViewBuilder
    private func Action(_ option: RecommendationModelOption, state: RecommendationsViewModel.ModelState)
        -> some View
    {
        if vm.isDownloading(option) {
            ProgressView()
                .controlSize(.small)
        } else if vm.isActive(option) {
            Button {
                vm.remove(option)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.danger)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(option.name)")
        } else {
            Button("Download") {
                vm.download(option)
            }
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(Palette.Tone.brand.text)
            .padding(.horizontal, dimensions.spacing.space12)
            .padding(.vertical, dimensions.spacing.space8)
            .background(Palette.Tone.brand.subtle, in: .capsule)
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        RecommendationsScreen()
    }
}
