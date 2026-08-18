//
//  TrackerRestoreSetupScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import SwiftUI
import GRDB

// the press state of a Step card, published by its own button style so the
// label can read it - the same shape DetailsSetup.swift uses for its own
// Next/Finish cards. not reused directly: that type is private to its own
// file, and this flow is two steps rather than three and has no reason to
// share code with a screen it looks nothing else like
private extension EnvironmentValues {
    @Entry var stepPressed = false
}

private struct StepButtonStyle: ButtonStyle {
    // GRDB.Configuration also lives at module scope in this file (needed
    // below for the raw tracker-link query), so the protocol's own
    // Configuration typealias is spelled out rather than left bare
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .environment(\.stepPressed, configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// two steps, pushed rather than shown together: which tracker, then which
// sources. nothing here writes to the database - the first write anywhere in
// this flow is a row's own Save, on the queue screen Start pushes to once
// composer.start() (LiveTrackerImportSource, see MigrationSource) comes
// back with rows
//
// which tracker is a plain local choice, not composer state - unlike the
// old per-flow composer, MigrationComposer takes one already-resolved
// source, so nothing about the pull can be decided until this step answers
// it. the composer itself is only built once a tracker is chosen, right
// before the Sources step needs one to search across
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

    // which trackers actually have a service behind them that can answer a
    // whole-list pull - a fact about which concrete service backs each case,
    // fixed at compile time rather than something worth an actor round trip
    // to ask for
    private static let bulkListable: Set<Tracker> = [.anilist, .myAnimeList, .mangaBaka]

    var body: some View {
        TrackerStep
            .task {
                guard selectedTracker == nil else { return }
                selectedTracker = restorableTrackers.first
            }
            // rebuilds whenever the chosen tracker changes - construction is
            // pure (no I/O until Start), so there is nothing to preserve by
            // patching an existing instance instead. any source selection
            // already made resets with it, the same way switching trackers
            // reset nothing else about the flow either
            .task(id: selectedTracker) {
                guard let selectedTracker else { composer = nil; return }
                composer = MigrationComposer(
                    source: LiveTrackerImportSource(tracker: selectedTracker, trackers: compositor.trackers),
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
                        await Self.alreadyLinkedRemoteIds(among: entries.map(\.id), tracker: selectedTracker, database: database)
                    },
                    precheckLabel: "Already Linked"
                )
            }
    }

    // only a tracker this account is actually signed in to can ever be
    // pulled from - listing the rest and explaining why they're disabled is
    // a "not signed in" case Save would otherwise hit at the very end of a
    // commit, which is the wrong place to discover it. order follows
    // Tracker.allCases so a reader who has connected more than one sees a
    // stable order
    private var signedInTrackers: [Tracker] {
        Tracker.allCases.filter { compositor.trackers.accounts[$0] != nil }
    }

    // the ones actually offered as a pull source: signed in AND backed by a
    // service that can answer a bulk pull
    private var restorableTrackers: [Tracker] {
        signedInTrackers.filter { Self.bulkListable.contains($0) }
    }

    // a preventive check ahead of any search: a tracker's own list can carry
    // an entry the reader already linked before this pull ran - by a
    // previous restore, or by hand from Details - and creating a series for
    // it a second time is exactly the origin-uniqueness crash this flow used
    // to hit. those rows are marked rather than dropped, so they stay visible
    // in their own pill instead of just vanishing from the count
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

    // MARK: Step 1 - Tracker

    // the first page because it decides everything the second one needs -
    // which sources even apply is not tracker-specific today, but the pull
    // itself is, and there is nothing to search for until it has run
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
                            Step(overline: "Next", title: "Sources", glyph: "arrow.right", tone: .brand)
                        }
                        .buttonStyle(StepButtonStyle())
                    }
                }
            )
            .navigationDestination(isPresented: $connecting) {
                // pushed into this stack rather than opening Settings, so
                // connecting does not cost the reader the flow they are in
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

    // the same "nothing to work with yet" shape DetailsSetup's own Trackers
    // page uses when nothing is connected
    private var NoAccounts: some View {
        ContentUnavailableView {
            Label("No Accounts Connected", systemImage: "person.crop.circle.badge.plus")
        } description: {
            // signed into something is a real, different state from signed
            // into nothing - a reader connected only to mangaBaka should not
            // be told to go connect an account they already have
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

    // the tracker pick is a chosen option, same shape DetailsEdit uses for
    // its own preferred-supplier rows: tint + trailing checkmark on the
    // pick, plain interactive glass on everything else. a tracker without a
    // bulk-listing service behind it stays untappable and says so, the same
    // "no working else" a source protocol opt-in would require. the signed-in
    // username underneath is the same fact TrackingScreen's own card shows -
    // this list is only ever signed-in trackers, so an account always exists
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

    // MARK: Step 2 - Sources

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
                subtitle: Text("^[\(composer.selectedSourceSlugs.count) source](inflect: true) selected"),
                onClose: onFinish
            ) {
                StartButton(composer)
            }
        )
        .navigationDestination(isPresented: $showingQueue) {
            if let selectedTracker {
                TrackerRestoreScreen(composer: composer, tracker: selectedTracker, onFinish: onFinish)
            }
        }
    }

    // membership, not a chosen option, but the same visual language: tint +
    // trailing checkmark when picked, plain interactive glass otherwise.
    // unlike TrackerRow this stays tappable while chosen - it toggles rather
    // than picks, so retapping the current state must be able to undo it.
    // base url + fingerprint underneath are the same identity SourceRecord.hash
    // is built from (descriptor.fingerprint, CLAUDE.md §6) - useful here
    // because this screen is exactly where a reader is choosing between
    // sources that may look alike. deliberately not SourcePing - that answers
    // "is it up right now", which is a different question from "what is this"
    private func SourceRow(_ composer: MigrationComposer<TrackerImportEntry>, _ source: Source) -> some View {
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

    // the flow's own Finish: not a NavigationLink, since it has to run
    // composer.start() and only push once real rows come back - the same
    // "Button styled like the Step card it sits beside" DetailsSetup's own
    // Finish() is, for the same reason (dismiss() there, an async gate here)
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

    // MARK: Chrome

    // progression as a row rather than a pinned full-width button, the same
    // recipe DetailsSetup's own Step card uses: one colour, drawn as the
    // foreground and again at low opacity behind it. an accent on an ACTION
    // rather than on state, which is the case that colour is allowed to mean
    // something every time
    private func Step(
        overline: String,
        title: String,
        glyph: String,
        tone: Palette.Tone,
        loading: Bool = false
    ) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                // the word that does the work, ahead of the destination it
                // names - "this says what the tap DOES before it says where
                // it goes", DetailsSetup.swift's own words for the same card
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

    // one frame for both steps, and one way out of the flow from either -
    // trailing rather than leading, because step two's own back chevron
    // already claims the leading slot once a NavigationLink push is in the
    // stack. DetailsSetup's own Chrome makes the identical move for the
    // identical reason: "back stays leading, where the system puts it"
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
