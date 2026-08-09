//
//  StatsScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import SwiftUI
import Tagged

// the rows behind Home's tiles. an aggregate with no drill-down turns every
// accuracy doubt into a dispute nothing can settle, so the numbers and the
// sessions that produced them ship as one surface
struct StatsScreen: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    @State private var vm: StatsViewModel?

    private enum Layout {
        static let heatWeeks = 16
        static let fillOpacity = 0.05
    }

    private var phase: LoadPhase {
        if let vm {
            if vm.failure != nil { .failed }
            else if vm.snapshot == nil { .pending }
            else if vm.snapshot?.isEmpty == true { .empty }
            else { .content }
        } else {
            .pending
        }
    }

    var body: some View {
        ZStack {
            switch phase {
            case .content:
                if let snapshot = vm?.snapshot {
                    Content(snapshot)
                        .transition(.opacity)
                }
            case .empty:
                ContentUnavailableView {
                    Label("No Reading Activity Yet", systemImage: "book.closed")
                } description: {
                    Text("Finish a chapter and it will be recorded here.")
                }
                .transition(.opacity)
            case .failed:
                if let vm, let failure = vm.failure {
                    ContentUnavailableView {
                        Label(failure.title, systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(failure.message)
                    } actions: {
                        if failure.isRetryable {
                            Button("Try Again") { vm.retry() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .transition(.opacity)
                }
            default:
                ProgressView()
                    .transition(.opacity)
            }
        }
        .animation(.settle, value: phase)
        .navigationTitle("Reading Activity")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard vm == nil else { return }
            let model = StatsViewModel(
                database: compositor.database,
                registry: compositor.registry
            )
            vm = model
            model.observe()
        }
    }
}

// MARK: - Content

private extension StatsScreen {
    func Content(_ snapshot: StatsViewModel.Snapshot) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                Totals(snapshot)

                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("Reading Days")
                    ReadingHeatmap(heat: snapshot.heat, weeks: Layout.heatWeeks, asOf: .now)
                    Runs(snapshot)
                }

                if !snapshot.sessions.isEmpty {
                    Sessions(snapshot.sessions)
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.vertical, dimensions.spacing.space16)
        }
    }

    func Totals(_ snapshot: StatsViewModel.Snapshot) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            Tile(value: Text("\(snapshot.chaptersAllTime)"), label: "Chapters")
            Tile(value: Text(ReadingFormat.duration(snapshot.secondsAllTime)), label: "Time Read")
            Tile(value: Text("\(snapshot.pagesAllTime)"), label: "Pages")
        }
    }

    func Runs(_ snapshot: StatsViewModel.Snapshot) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            Tile(value: Text("^[\(snapshot.currentRun) day](inflect: true)"), label: "Current Run")
            Tile(value: Text("^[\(snapshot.longestRun) day](inflect: true)"), label: "Best Run")
        }
    }

    // takes Text, not String - a String parameter is one of the four silent
    // inflection killers, and the run tiles inflect
    func Tile(value: Text, label: String) -> some View {
        VStack(spacing: dimensions.spacing.space4) {
            value
                .font(.title3)
                .fontWeight(.bold)

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, dimensions.spacing.space12)
        .background(.primary.opacity(Layout.fillOpacity), in: .rect(cornerRadius: dimensions.radius.radius12))
    }

    func Sessions(_ sessions: [ReadingSessionEntry]) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader("Sessions")

            let byDay = Dictionary(grouping: sessions, by: \.localDayKey)
            ForEach(byDay.keys.sorted(by: >), id: \.self) { day in
                VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                    Text(ReadingFormat.dayLabel(for: day))
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    ForEach(byDay[day] ?? []) { session in
                        SessionRow(session: session)
                    }
                }
            }
        }
    }

}
