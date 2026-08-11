//
//  BootstrapScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI

struct BootstrapScreen: View {
    let phase: Bootstrap.Phase
    var onRetry: () -> Void

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let iconSize: CGFloat = 56
        static let barWidth: CGFloat = 220
    }

    var body: some View {
        ZStack {
            Palette.canvas
                .ignoresSafeArea()

            if case .failed(let failure) = phase {
                Failed(failure)
            } else {
                Progress
            }
        }
        .animation(.smooth, value: phase)
    }

    private var Progress: some View {
        VStack(spacing: dimensions.spacing.space20) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: Layout.iconSize))
                .foregroundStyle(.brand)
                .symbolEffect(.pulse)

            VStack(spacing: dimensions.spacing.space8) {
                ProgressView(value: phase.progress)
                    .progressViewStyle(.linear)
                    .tint(.brand)
                    .frame(width: Layout.barWidth)

                Text(phase.label)
                    .font(.footnote)
                    .foregroundStyle(.muted)
                    .contentTransition(.numericText())
            }
        }
    }

    private func Failed(_ failure: Failure) -> some View {
        ContentUnavailableView {
            Label(failure.title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(failure.message)
        } actions: {
            Button("Try Again", action: onRetry)
                .buttonStyle(.glassProminent)
                .tint(.brand)
        }
    }
}

#Preview("Opening") {
    BootstrapScreen(phase: .opening) {}
}

#Preview("Failed") {
    BootstrapScreen(
        phase: .failed(
            Failure(
                title: "Couldn't Start",
                message: "The database could not be opened.",
                isRetryable: true
            )
        )
    ) {}
}
