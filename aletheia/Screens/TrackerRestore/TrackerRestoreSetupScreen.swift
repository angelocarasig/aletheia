//
//  TrackerRestoreSetupScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import GRDB
import SwiftUI

extension EnvironmentValues {
    @Entry fileprivate var stepPressed = false
}

private struct StepButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .environment(\.stepPressed, configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct TrackerRestoreSetupScreen: View {
    var onFinish: () -> Void

    @State private var selectedTracker: Tracker?
    @State private var composer: MigrationComposer<TrackerImportEntry>?
    @State private var showingQueue = false
    @State private var connecting = false

    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions
    @Environment(\.stepPressed) private var pressed

    private enum Layout {
        static let iconSize: CGFloat = 32
        static let tint: Double = 0.3
        static let overlineTracking: CGFloat = 1.2
    }

    private static let bulkListable: Set<Tracker> = [.anilist, .myAnimeList, .mangaBaka]

    var body: some View {
        TrackerStep
            .task {
                guard selectedTracker == nil else { return }
                selectedTracker = restorableTrackers.first
            }
            .task(id: selectedTracker) {
                guard let selectedTracker else {
                    composer = nil
                    return
                }
                composer = MigrationComposer(
                    source: LiveTrackerImportSource(
                        tracker: selectedTracker, trackers: compositor.trackers),
                    searching: LiveMigrationSearcher(),
                    committing: LiveTrackerRestoreCommitter(
                        database: compositor.database,
                        registry: compositor.registry,
                        refresher: compositor.refresh,
                        trackers: compositor.trackers,
                        tracker: selectedTracker
                    ),
                    registry: compositor.registry,
                    precheck: { [database = compositor.database] entries in
                        await Self.alreadyLinkedRemoteIds(
                            among: entries.map(\.id), tracker: selectedTracker, database: database)
                    },
                    precheckLabel: "Already Linked"
                )
            }
    }

    private var signedInTrackers: [Tracker] {
        Tracker.allCases.filter { compositor.trackers.accounts[$0] != nil }
    }

    private var restorableTrackers: [Tracker] {
        signedInTrackers.filter { Self.bulkListable.contains($0) }
    }

    // marks entries already linked elsewhere rather than dropping them - creating a
    // series for one again is the origin-uniqueness crash this flow used to hit
    private static func alreadyLinkedRemoteIds(
        among remoteIds: [Int64],
        tracker: Tracker,
        database: DatabaseClient
    ) async -> Set<Int64> {
        guard !remoteIds.isEmpty else { return [] }

        let rows = try? await database.reader.read { db in
            try SeriesTrackerRecord
                .filter(SeriesTrackerRecord.Columns.tracker == tracker.rawValue)
                .filter(remoteIds.contains(SeriesTrackerRecord.Columns.remoteId))
                .fetchAll(db)
        }
        return Set((rows ?? []).map(\.remoteId))
    }

    private var TrackerStep: some View {
        TrackerStepContent
            .modifier(
                Chrome(
                    title: "Restore from Tracker",
                    subtitle: Text("Choose which tracker to pull your library from."),
                    onClose: onFinish
                ) {
                    if !restorableTrackers.isEmpty, let composer {
                        NavigationLink {
                            SourcesStep(composer)
                        } label: {
                            Step(
                                overline: "Next", title: "Sources", glyph: "arrow.right",
                                tone: .brand)
                        }
                        .buttonStyle(StepButtonStyle())
                    }
                }
            )
            .navigationDestination(isPresented: $connecting) {
                TrackingScreen()
                    .containerBackground(.clear, for: .navigation)
            }
    }

    @ViewBuilder
    private var TrackerStepContent: some View {
        if restorableTrackers.isEmpty {
            NoAccounts
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    ForEach(signedInTrackers) { tracker in
                        TrackerRow(tracker)
                    }
                    .sensoryFeedback(.selection, trigger: selectedTracker)
                }
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.top, dimensions.spacing.space8)
                .padding(.bottom, dimensions.spacing.space48)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
    }

    private var NoAccounts: some View {
        ContentUnavailableView {
            Label("No Accounts Connected", systemImage: "person.crop.circle.badge.plus")
        } description: {
            Text(
                signedInTrackers.isEmpty
                    ? "Connect a tracker to restore your library from its list."
                    : "None of your connected trackers support restoring a library yet."
            )
        } actions: {
            if signedInTrackers.isEmpty {
                Button("Connect an Account") { connecting = true }
                    .buttonStyle(.glassProminent)
            }
        }
    }

    private func TrackerRow(_ tracker: Tracker) -> some View {
        let restorable = Self.bulkListable.contains(tracker)
        let chosen = restorable && selectedTracker == tracker

        return HStack(spacing: dimensions.spacing.space12) {
            Image(tracker.icon)
                .resizable()
                .scaledToFit()
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius8))

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(tracker.name)
                    .font(.subheadline)

                if let username = compositor.trackers.accounts[tracker]?.username {
                    Text(username)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if chosen {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Palette.brand)
                    .transition(.scale.combined(with: .opacity))
            } else if !restorable {
                Text("Coming soon")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(dimensions.spacing.space12)
        .glassEffect(
            chosen
                ? .regular.tint(Palette.brand.opacity(Layout.tint))
                : .regular.interactive(),
            in: .rect(cornerRadius: dimensions.radius.radius16)
        )
        .contentShape(.rect)
        .tappable {
            guard restorable else { return }
            selectedTracker = tracker
        }
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func SourcesStep(_ composer: MigrationComposer<TrackerImportEntry>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                ForEach(composer.availableSources, id: \.descriptor.slug) { source in
                    SourceRow(composer, source)
                }

                Text("Every entry is searched across the sources selected here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let failure = composer.loadFailure {
                    Text(failure)
                        .font(.caption)
                        .foregroundStyle(.dangerText)
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.top, dimensions.spacing.space8)
            .padding(.bottom, dimensions.spacing.space48)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .modifier(
            Chrome(
                title: "Sources",
                subtitle: Text(
                    "^[\(composer.selectedSourceSlugs.count) source](inflect: true) selected"),
                onClose: onFinish
            ) {
                StartButton(composer)
            }
        )
        .navigationDestination(isPresented: $showingQueue) {
            if let selectedTracker {
                TrackerRestoreScreen(
                    composer: composer, tracker: selectedTracker, onFinish: onFinish)
            }
        }
    }

    private func SourceRow(_ composer: MigrationComposer<TrackerImportEntry>, _ source: Source)
        -> some View
    {
        let selected = composer.selectedSourceSlugs.contains(source.descriptor.slug)

        return HStack(spacing: dimensions.spacing.space12) {
            Image(source.descriptor.icon)
                .resizable()
                .scaledToFit()
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius8))

            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(source.descriptor.name)
                    .font(.subheadline)

                Text(source.descriptor.baseURL.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(String(source.descriptor.fingerprint.prefix(12)))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Palette.brand)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(dimensions.spacing.space12)
        .glassEffect(
            selected
                ? .regular.tint(Palette.brand.opacity(Layout.tint))
                : .regular.interactive(),
            in: .rect(cornerRadius: dimensions.radius.radius16)
        )
        .contentShape(.rect)
        .tappable { composer.toggleSource(source.descriptor.slug) }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected)
    }

    private func StartButton(_ composer: MigrationComposer<TrackerImportEntry>) -> some View {
        let canStart = !composer.selectedSourceSlugs.isEmpty && !composer.loading

        return Button {
            Task {
                await composer.start()
                if !composer.rows.isEmpty { showingQueue = true }
            }
        } label: {
            Step(
                overline: composer.loading ? "Loading" : "Start",
                title: composer.loading ? "Your List" : "Restoring",
                glyph: "arrow.right",
                tone: .brand,
                loading: composer.loading
            )
        }
        .buttonStyle(StepButtonStyle())
        .disabled(!canStart)
        .opacity(canStart || composer.loading ? 1 : 0.5)
    }

    private func Step(
        overline: String,
        title: String,
        glyph: String,
        tone: Palette.Tone,
        loading: Bool = false
    ) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Text(overline.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .tracking(Layout.overlineTracking)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .contentTransition(.opacity)
            }

            Spacer(minLength: 0)

            if loading {
                ProgressView()
            } else {
                Image(systemName: glyph)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .contentTransition(.symbolEffect(.replace))
                    .scaleEffect(x: pressed ? 1.15 : 1, y: 1, anchor: .leading)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
            }
        }
        .foregroundStyle(tone.text)
        .padding(.horizontal, dimensions.spacing.space16)
        .padding(.vertical, dimensions.spacing.space12)
        .frame(minHeight: dimensions.touchTarget)
        .background(
            tone.subtle,
            in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
        .contentShape(.rect)
        .animation(.settle, value: loading)
    }

    private struct Chrome<Footer: View>: ViewModifier {
        let title: String
        let subtitle: Text
        var onClose: () -> Void
        @ViewBuilder var footer: () -> Footer

        @Environment(\.dimensions) private var dimensions

        func body(content: Content) -> some View {
            content
                .navigationTitle(title)
                .navigationSubtitle(subtitle)
                .navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    footer()
                        .padding(.horizontal, dimensions.screenMargin)
                        .padding(.bottom, dimensions.spacing.space8)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close", systemImage: "xmark", action: onClose)
                            .labelStyle(.iconOnly)
                    }
                }
        }
    }
}
