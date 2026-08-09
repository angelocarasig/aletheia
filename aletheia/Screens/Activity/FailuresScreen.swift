//
//  FailuresScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import SwiftUI
import Tagged

// which series could not be checked, on which source, and why. reached from the
// Now section's count row - the count is the awareness, this is the attribution
// and the retry. rows leave on their own when a source answers again; there is
// nothing here to dismiss, because the state is a column rather than an inbox
struct FailuresScreen: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    @State private var vm: FailuresViewModel?
    @State private var route: SeriesEntry?

    private enum Layout {
        static let fillOpacity = 0.05
        static let iconSize: CGFloat = 36
    }

    private var phase: LoadPhase {
        if let vm {
            if vm.failure != nil { .failed }
            else if vm.entries == nil { .pending }
            else if vm.entries?.isEmpty == true { .empty }
            else { .content }
        } else {
            .pending
        }
    }

    var body: some View {
        ZStack {
            switch phase {
            case .content:
                if let vm { List(vm) .transition(.opacity) }
            case .empty:
                Recovered.transition(.opacity)
            case .failed:
                if let vm, let failure = vm.failure {
                    Unavailable(failure).transition(.opacity)
                }
            default:
                ProgressView().transition(.opacity)
            }
        }
        .animation(.settle, value: phase)
        .navigationTitle("Failing Sources")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { DetailsScreen(entry: $0) }
        .task {
            guard vm == nil else { return }
            let model = FailuresViewModel(
                database: compositor.database,
                registry: compositor.registry,
                refresher: compositor.refresh
            )
            vm = model
            model.observe()
        }
    }
}

// MARK: - Content

private extension FailuresScreen {
    func List(_ vm: FailuresViewModel) -> some View {
        ScrollView {
            VStack(spacing: dimensions.spacing.space12) {
                ForEach(vm.entries ?? []) { entry in
                    Row(entry, vm: vm)
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.vertical, dimensions.spacing.space16)
        }
    }

    // the series is the anchor and the source is the qualifier: a series can be
    // perfectly healthy on one source and dead on another, so naming only the
    // series would send you looking for a fault that is not there
    func Row(_ entry: FailuresViewModel.Entry, vm: FailuresViewModel) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            HStack(spacing: dimensions.spacing.space12) {
                Icon(entry)

                VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                    Text(entry.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    Text(entry.sourceName)
                        .font(.caption2)
                        .foregroundStyle(.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // an indicator, not the target - the whole card is the target,
                // which is what a chevron has always promised
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Text(entry.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text("Last tried \(entry.attemptedDate.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.muted)

                Spacer(minLength: 0)

                Retry(entry, vm: vm)
            }
        }
        .padding(dimensions.spacing.space12)
        .background(.primary.opacity(Layout.fillOpacity), in: .rect(cornerRadius: dimensions.radius.radius12))
        .contentShape(.rect)
        // the row navigates, the retry acts. a card carrying both needs the
        // button to win its own hit area, which is why Retry is a Button rather
        // than something layered over a tappable card
        .tappable { route = SeriesEntry.library(SeriesRecord.ID(rawValue: entry.seriesId)) }
    }

    @ViewBuilder
    func Icon(_ entry: FailuresViewModel.Entry) -> some View {
        if let icon = compositor.registry.source(slug: entry.sourceSlug)?.descriptor.icon {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius8))
        } else {
            Image(systemName: "questionmark")
                .font(.footnote)
                .foregroundStyle(.muted)
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .background(.primary.opacity(Layout.fillOpacity), in: .rect(cornerRadius: dimensions.radius.radius8))
        }
    }

    // the same unit everything else calls, so a retry while a library run is
    // already checking this origin joins that fetch instead of racing it
    @ViewBuilder
    func Retry(_ entry: FailuresViewModel.Entry, vm: FailuresViewModel) -> some View {
        if vm.retrying.contains(entry.id) {
            ProgressView()
                .controlSize(.small)
        } else {
            Text("Try Again")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.brand)
                .padding(.horizontal, dimensions.spacing.space12)
                .padding(.vertical, dimensions.spacing.space4)
                .background(.brand.opacity(0.1), in: .capsule)
                .tappable { Task { await vm.retry(entry) } }
        }
    }

    var Recovered: some View {
        ContentUnavailableView {
            Label("Everything's Working", systemImage: "checkmark.circle")
        } description: {
            Text("No source is currently failing to check for new chapters.")
        }
    }

    func Unavailable(_ failure: Failure) -> some View {
        ContentUnavailableView {
            Label(failure.title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(failure.message)
        }
    }
}
