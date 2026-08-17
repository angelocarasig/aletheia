//
//  TrackerRestoreCandidatePicker.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import SwiftUI

// the bigger picture behind a row's compact summary: every candidate as a
// SourceCard in a grid, plus the query that found them, editable in place.
// tapping a card commits the pick and closes - there is nothing else to
// confirm, the same one-step choice DetailsTrackerLink already uses
struct TrackerRestoreCandidatePicker: View {
    let entry: TrackerImportEntry
    let candidates: [TrackerRestoreCandidate]
    let selected: TrackerRestoreCandidate?
    let sourcesBySlug: [String: Source]
    let searching: Bool
    let onSearch: (String) -> Void
    let onSelect: (TrackerRestoreCandidate) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dimensions) private var dimensions

    @State private var query: String

    init(
        entry: TrackerImportEntry,
        candidates: [TrackerRestoreCandidate],
        selected: TrackerRestoreCandidate?,
        sourcesBySlug: [String: Source],
        searching: Bool,
        onSearch: @escaping (String) -> Void,
        onSelect: @escaping (TrackerRestoreCandidate) -> Void
    ) {
        self.entry = entry
        self.candidates = candidates
        self.selected = selected
        self.sourcesBySlug = sourcesBySlug
        self.searching = searching
        self.onSearch = onSearch
        self.onSelect = onSelect
        _query = State(initialValue: entry.title)
    }

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]
    private enum Layout {
        static let skeletonCount = 6
    }

    // branch and animation share this one value, per docs/design.md §1 - a
    // surface that keys its swap on a different flag than the one it
    // branches on is how a transition goes dead or partial
    private var phase: LoadPhase {
        if searching { .pending }
        else if candidates.isEmpty { .empty }
        else { .content }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Searchbar(searchText: $query, placeholder: entry.title)
                    .padding(.horizontal, dimensions.screenMargin)
                    .padding(.top, dimensions.spacing.space8)
                    .onSubmit { onSearch(query) }

                VStack(spacing: 0) {
                    switch phase {
                    case .pending:
                        Skeleton
                            .transition(.opacity)

                    case .empty:
                        ContentUnavailableView {
                            Label("No Matches", systemImage: "magnifyingglass")
                        } description: {
                            Text("Try a different title for \(entry.title).")
                        }
                        .transition(.opacity)

                    case .content:
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: dimensions.spacing.space12) {
                                ForEach(candidates) { candidate in
                                    CandidateCard(candidate)
                                }
                            }
                            .padding(dimensions.screenMargin)
                        }
                        .transition(.opacity)

                    case .failed:
                        EmptyView()
                    }
                }
                .animation(.settle, value: phase)
            }
            .navigationTitle("Choose a Match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "chevron.down", action: dismiss.callAsFunction)
                        .labelStyle(.iconOnly)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var Skeleton: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: dimensions.spacing.space12) {
                ForEach(0..<Layout.skeletonCount, id: \.self) { _ in
                    SourceCard()
                }
            }
            .padding(dimensions.screenMargin)
        }
        .shimmer()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func CandidateCard(_ candidate: TrackerRestoreCandidate) -> some View {
        let source = sourcesBySlug[candidate.sourceSlug]

        return SourceCard(stub: candidate.stub, referer: source?.descriptor.referer, selected: candidate == selected)
            .animation(.settle, value: candidate == selected)
            .overlay(alignment: .topLeading) { SourceIcon(source) }
            .contentShape(.rect)
            .tappable {
                onSelect(candidate)
                dismiss()
            }
    }

    @ViewBuilder
    private func SourceIcon(_ source: Source?) -> some View {
        if let icon = source?.descriptor.icon {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius4))
                .padding(dimensions.spacing.space4)
        }
    }
}
