//
//  SourceMigrationScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI

// the press state of a Step card - same shape TrackerRestoreSetupScreen's own
// uses, duplicated rather than shared per that file's own note: three
// setup flows that each look nothing else like one another have no reason
// to share this
private extension EnvironmentValues {
    @Entry var sourceMigrationStepPressed = false
}

private struct SourceMigrationStepButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .environment(\.sourceMigrationStepPressed, configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// three steps, pushed: which source to move series off, which sources to
// search across (plus Migrate-or-Copy), then the queue. every series
// currently carrying an origin on the picked "from" source is offered -
// SeriesOnSourceMigrationSource, see docs. nothing here writes to the
// database - the first write is a row's own Save, inside
// OriginMigrationCommitter.commit
struct SourceMigrationScreen: View {
    var onFinish: () -> Void

    @State private var selectedFromSourceSlug: String?
    @State private var mode: OriginMigrationMode = .migrate
    @State private var composer: MigrationComposer<SourceMigrationEntry>?
    @State private var showingQueue = false

    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions
    @Environment(\.sourceMigrationStepPressed) private var pressed

    private enum Layout {
        static let iconSize: CGFloat = 32
        static let tint: Double = 0.3
        static let overlineTracking: CGFloat = 1.2
    }

    // the same existence gate SearchViewModel's own source list uses - while
    // bypassAdultSources is off, an adultOnly source does not exist here at
    // all, not merely hidden
    private var availableSources: [Source] {
        let defaults = UserDefaults.standard
        let unlocked = defaults.bool(forKey: Preferences.Key.bypassAdultSources)
            && defaults.bool(forKey: Preferences.Key.includeAdultSources)
        return unlocked ? compositor.registry.sources : compositor.registry.sources.filter { !$0.descriptor.adultOnly }
    }

    var body: some View {
        FromStep
            // rebuilds whenever the "from" source changes - construction is
            // pure, nothing has run yet, so there is nothing worth
            // preserving by patching an existing instance instead
            .task(id: selectedFromSourceSlug) {
                guard let selectedFromSourceSlug else { composer = nil; return }
                composer = MigrationComposer(
                    source: SeriesOnSourceMigrationSource(sourceSlug: selectedFromSourceSlug, database: compositor.database),
                    searching: LiveMigrationSearcher(),
                    committing: OriginMigrationCommitter(
                        database: compositor.database,
                        registry: compositor.registry,
                        refresher: compositor.refresh,
                        mode: mode
                    ),
                    registry: compositor.registry,
                    precheckLabel: "Already Attached"
                )
            }
            // Migrate/Copy is picked on the Sources step, but the committer
            // that uses it is built here - re-run so a mode change before
            // Start is tapped actually takes
            .task(id: mode) {
                guard let selectedFromSourceSlug else { return }
                composer = MigrationComposer(
                    source: SeriesOnSourceMigrationSource(sourceSlug: selectedFromSourceSlug, database: compositor.database),
                    searching: LiveMigrationSearcher(),
                    committing: OriginMigrationCommitter(
                        database: compositor.database,
                        registry: compositor.registry,
                        refresher: compositor.refresh,
                        mode: mode
                    ),
                    registry: compositor.registry,
                    precheckLabel: "Already Attached"
                )
            }
    }

    // MARK: Step 1 - From

    private var FromStep: some View {
        FromStepContent
            .modifier(
                Chrome(
                    title: "Between Sources",
                    subtitle: Text("Choose which source to move series off."),
                    onClose: onFinish
                ) {
                    if let composer {
                        NavigationLink {
                            ToStep(composer)
                        } label: {
                            Step(overline: "Next", title: "Sources", glyph: "arrow.right", tone: .brand)
                        }
                        .buttonStyle(SourceMigrationStepButtonStyle())
                    }
                }
            )
    }

    @ViewBuilder
    private var FromStepContent: some View {
        if availableSources.isEmpty {
            ContentUnavailableView {
                Label("No Sources Installed", systemImage: "square.stack.3d.up.slash")
            } description: {
                Text("Install a source before moving series between them.")
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    ForEach(availableSources, id: \.descriptor.slug) { source in
                        FromRow(source)
                    }
                    .sensoryFeedback(.selection, trigger: selectedFromSourceSlug)
                }
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.top, dimensions.spacing.space8)
                .padding(.bottom, dimensions.spacing.space48)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
    }

    private func FromRow(_ source: Source) -> some View {
        let chosen = selectedFromSourceSlug == source.descriptor.slug

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
            }

            Spacer(minLength: 0)

            if chosen {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Palette.brand)
                    .transition(.scale.combined(with: .opacity))
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
        .tappable { selectedFromSourceSlug = source.descriptor.slug }
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    // MARK: Step 2 - To + Mode

    private func ToStep(_ composer: MigrationComposer<SourceMigrationEntry>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                ModeSection

                ForEach(composer.availableSources, id: \.descriptor.slug) { source in
                    ToRow(composer, source)
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
            OriginMigrationScreen(composer: composer, onFinish: onFinish)
        }
    }

    private var ModeSection: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            ForEach(OriginMigrationMode.allCases) { option in
                ModeRow(option)
            }
        }
    }

    private func ModeRow(_ option: OriginMigrationMode) -> some View {
        let chosen = mode == option

        return HStack(spacing: dimensions.spacing.space12) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                Text(option.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(option.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if chosen {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Palette.brand)
                    .transition(.scale.combined(with: .opacity))
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
        .tappable { mode = option }
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func ToRow(_ composer: MigrationComposer<SourceMigrationEntry>, _ source: Source) -> some View {
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

    private func StartButton(_ composer: MigrationComposer<SourceMigrationEntry>) -> some View {
        let canStart = !composer.selectedSourceSlugs.isEmpty && !composer.loading

        return Button {
            Task {
                await composer.start()
                if !composer.rows.isEmpty { showingQueue = true }
            }
        } label: {
            Step(
                overline: composer.loading ? "Loading" : "Start",
                title: composer.loading ? "Series" : "Migrating",
                glyph: "arrow.right",
                tone: .brand,
                loading: composer.loading
            )
        }
        .buttonStyle(SourceMigrationStepButtonStyle())
        .disabled(!canStart)
        .opacity(canStart || composer.loading ? 1 : 0.5)
    }

    // MARK: Chrome

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

// MARK: - Previews

#Preview {
    NavigationStack {
        SourceMigrationScreen(onFinish: {})
    }
}
