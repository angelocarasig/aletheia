//
//  DisconnectedSourceMigrationScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI

private extension EnvironmentValues {
    @Entry var disconnectedMigrationStepPressed = false
}

private struct DisconnectedMigrationStepButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .environment(\.disconnectedMigrationStepPressed, configuration.isPressed)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

// one step, not two - there is no "from" to pick, disconnected is a fixed
// query (origin.sourceId IS NULL, the only thing "disconnected" means in
// this codebase - DisconnectedOriginMigrationSource). just which sources to
// search across and Migrate-or-Copy, then the same queue source migration
// uses. nothing here writes to the database - the first write is a row's
// own Save, inside OriginMigrationCommitter.commit
struct DisconnectedSourceMigrationScreen: View {
    var onFinish: () -> Void

    @State private var mode: OriginMigrationMode = .migrate
    @State private var composer: MigrationComposer<SourceMigrationEntry>?
    @State private var showingQueue = false

    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions
    @Environment(\.disconnectedMigrationStepPressed) private var pressed

    private enum Layout {
        static let iconSize: CGFloat = 32
        static let tint: Double = 0.3
        static let overlineTracking: CGFloat = 1.2
    }

    var body: some View {
        Group {
            if let composer {
                ToStep(composer)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard composer == nil else { return }
            composer = makeComposer()
        }
        // Migrate/Copy is picked on this same step, but the committer that
        // uses it is built ahead of time - re-run so a mode change before
        // Start is tapped actually takes
        .onChange(of: mode) {
            composer = makeComposer()
        }
    }

    private func makeComposer() -> MigrationComposer<SourceMigrationEntry> {
        MigrationComposer(
            source: DisconnectedOriginMigrationSource(database: compositor.database),
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

    // MARK: Step - To + Mode

    private func ToStep(_ composer: MigrationComposer<SourceMigrationEntry>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                ModeSection

                if composer.availableSources.isEmpty {
                    ContentUnavailableView {
                        Label("No Sources Installed", systemImage: "square.stack.3d.up.slash")
                    } description: {
                        Text("Install a source before reconnecting series to one.")
                    }
                } else {
                    ForEach(composer.availableSources, id: \.descriptor.slug) { source in
                        ToRow(composer, source)
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
        .modifier(
            Chrome(
                title: "Disconnected Sources",
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
        .buttonStyle(DisconnectedMigrationStepButtonStyle())
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
        DisconnectedSourceMigrationScreen(onFinish: {})
    }
}
