//
//  TrackerRestoreSetupScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 17/8/26.
//

import SwiftUI

// step one of restore: which tracker, which sources. Start pulls the list
// (LiveTrackerImportSource, see TrackerImportSource) and pushes the queue
// once rows exist. nothing here writes to the database - the first write
// anywhere in this flow is a row's own Save.
//
// the composer is built lazily here rather than handed in, the same shape
// DetailsScreen builds DetailsComposer - it needs the compositor from the
// environment, which is not available at a call site constructing this view
struct TrackerRestoreSetupScreen: View {
    var onFinish: () -> Void

    @State private var composer: TrackerRestoreComposer?
    @State private var showingQueue = false
    @State private var connecting = false

    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let iconSize: CGFloat = 32
        static let tint: Double = 0.3
    }

    // which trackers actually have a service behind them that can answer a
    // whole-list pull - a fact about which concrete service backs each case,
    // fixed at compile time rather than something worth an actor round trip
    // to ask for
    private static let bulkListable: Set<Tracker> = [.anilist, .myAnimeList, .mangaBaka]

    var body: some View {
        Group {
            if let composer {
                Content(composer)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Restore from Tracker")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close", systemImage: "xmark", action: onFinish)
                    .labelStyle(.iconOnly)
            }
        }
        .task {
            guard composer == nil else { return }
            composer = TrackerRestoreComposer(
                importSources: restorableTrackers.map {
                    LiveTrackerImportSource(tracker: $0, trackers: compositor.trackers)
                },
                searching: LiveTrackerRestoreSearcher(),
                committing: LiveTrackerRestoreCommitter(
                    database: compositor.database,
                    registry: compositor.registry,
                    refresher: compositor.refresh,
                    trackers: compositor.trackers
                ),
                registry: compositor.registry,
                database: compositor.database
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

    @ViewBuilder
    private func Content(_ composer: TrackerRestoreComposer) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                if restorableTrackers.isEmpty {
                    NoAccounts
                } else {
                    VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                        SectionHeader("Tracker")

                        ForEach(signedInTrackers) { tracker in
                            TrackerRow(composer, tracker)
                        }
                        .sensoryFeedback(.selection, trigger: composer.selectedTracker)
                    }
                }

                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    SectionHeader("Sources to Search")

                    ForEach(composer.availableSources, id: \.descriptor.slug) { source in
                        SourceRow(composer, source)
                    }

                    Text("Every entry is searched across the sources selected here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
        .safeAreaInset(edge: .bottom) {
            StartButton(composer)
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.bottom, dimensions.spacing.space8)
        }
        .navigationDestination(isPresented: $showingQueue) {
            TrackerRestoreScreen(composer: composer, onFinish: onFinish)
        }
        .navigationDestination(isPresented: $connecting) {
            TrackingScreen()
                .containerBackground(.clear, for: .navigation)
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

    // the same tinted-capsule primary action DetailsContinue uses for "the
    // one thing you came here to do" - this screen has exactly one of those
    // too, so it gets the same shape rather than a plain glassProminent bar
    private func StartButton(_ composer: TrackerRestoreComposer) -> some View {
        let canStart = restorableTrackers.contains(composer.selectedTracker)
            && !composer.selectedSourceSlugs.isEmpty
            && !composer.loading

        return HStack(spacing: dimensions.spacing.space12) {
            Image(systemName: "arrow.down.doc")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(canStart ? Palette.brandText : .secondary)

            Text(composer.loading ? "Loading Your List" : "Start Restoring")
                .font(.subheadline)
                .fontWeight(.semibold)

            Spacer(minLength: 0)

            if composer.loading {
                ProgressView()
            } else {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, dimensions.spacing.space16)
        .padding(.vertical, dimensions.spacing.space16)
        .frame(minHeight: dimensions.touchTarget)
        .glassEffect(
            canStart
                ? .regular.tint(Palette.brand.opacity(Layout.tint)).interactive()
                : .regular,
            in: .capsule
        )
        .contentShape(.capsule)
        .tappable {
            Task {
                await composer.start()
                if !composer.rows.isEmpty { showingQueue = true }
            }
        }
        .disabled(!canStart)
    }

    // the tracker pick is a chosen option, same shape DetailsEdit uses for
    // its own preferred-supplier rows: tint + trailing checkmark on the
    // pick, plain interactive glass on everything else. a tracker without a
    // bulk-listing service behind it stays untappable and says so, the same
    // "no working else" a source protocol opt-in would require
    private func TrackerRow(_ composer: TrackerRestoreComposer, _ tracker: Tracker) -> some View {
        let restorable = Self.bulkListable.contains(tracker)
        let chosen = restorable && composer.selectedTracker == tracker

        return HStack(spacing: dimensions.spacing.space12) {
            Image(tracker.icon)
                .resizable()
                .scaledToFit()
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius8))

            Text(tracker.name)
                .font(.subheadline)

            Spacer(minLength: 0)

            if chosen {
                Image(systemName: "checkmark.circle.fill")
                    .font(.footnote)
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
            composer.selectedTracker = tracker
        }
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    // membership, not a chosen option, but the same visual language: tint +
    // trailing checkmark when picked, plain interactive glass otherwise.
    // unlike TrackerRow this stays tappable while chosen - it toggles rather
    // than picks, so retapping the current state must be able to undo it
    private func SourceRow(_ composer: TrackerRestoreComposer, _ source: Source) -> some View {
        let selected = composer.selectedSourceSlugs.contains(source.descriptor.slug)

        return HStack(spacing: dimensions.spacing.space12) {
            Image(source.descriptor.icon)
                .resizable()
                .scaledToFit()
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius8))

            Text(source.descriptor.name)
                .font(.subheadline)

            Spacer(minLength: 0)

            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.footnote)
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
}
