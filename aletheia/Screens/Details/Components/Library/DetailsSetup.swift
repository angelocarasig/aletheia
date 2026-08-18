//
//  DetailsSetup.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import SwiftUI

// file scope, not nested inside DetailsSetup - a generic type cannot hold
// static stored properties, and this needs one for the @Entry key
//
// press state of the card, published via environment so the label can read
// it. a ButtonStyle cannot re-parameterise the label it is handed, and a
// gesture alongside a NavigationLink races the link it sits on
extension EnvironmentValues {
    @Entry fileprivate var stepPressed = false
}

private struct StepButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .environment(\.stepPressed, configuration.isPressed)
            .scaleEffect(configuration.isPressed ? Layout.pressedScale : 1)
            .opacity(configuration.isPressed ? Layout.pressedOpacity : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

private enum Layout {
    static let glyphWidth: CGFloat = 28
    static let fillOpacity: Double = 0.05
    static let savingOpacity: Double = 0.6
    static let overlineTracking: CGFloat = 1.2
    // the afterimage behind the arrow - each ghost further back, fainter and
    // blurrier than the last. a trail reads as speed because the eye is being
    // shown where something WAS, so the falloff matters more than the count
    static let streakCount = 3
    static let streakOffset: CGFloat = 5
    static let streakOpacity: Double = 0.35
    static let streakBlur: CGFloat = 0.6
    static let streakEntry: CGFloat = 3
    static let streakPressed: CGFloat = 2.6
    static let headLean: CGFloat = 3
    static let pressedScale: CGFloat = 0.95
    static let pressedOpacity: Double = 0.8
}

// every page here commits on tap - the add already landed before this sheet
// opens, so closing at any point just leaves whatever was chosen so far
struct DetailsSetup<LinkSheet: View>: View {
    let title: String
    let status: Status
    let collections: [CollectionPicker.Item]
    let isSaving: Bool
    let accounts: [Tracker]
    let links: [DetailsTracking.Link]
    let localProgress: Int
    let needingSignIn: Set<Tracker>
    let syncing: Set<Tracker>
    var matches: [Tracker: DetailsComposer.Tracking.Match] = [:]
    var writing: Set<Tracker> = []
    var onPrefetch: () -> Void = {}
    var onAutoLink: (Tracker, TrackerCandidate) -> Void = { _, _ in }
    var onSetStatus: (Status) -> Void
    var onToggleCollection: (Int64) -> Void
    var onCreateCollection: (String, String?) -> Void
    // the Bool is captured at tap time, never re-derived from the list live -
    // linking writes a row, and a live re-read would swap the sheet's content
    // out from under the reader at the exact moment their commit lands
    @ViewBuilder var linkSheet: (Tracker, Bool, @escaping () -> Void) -> LinkSheet

    @Environment(\.dimensions) private var dimensions

    @State private var creating = false
    @State private var linking: Tracker?
    @State private var opening = false
    @State private var connecting = false
    @State private var adopted: Status?
    @State private var streaked = false

    var body: some View {
        NavigationStack {
            Trackers
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Trackers

    private var Trackers: some View {
        TrackersContent
            .modifier(
                Chrome(
                    title: "Trackers",
                    subtitle: trackersSubtitle,
                    isSaving: isSaving,
                    onClose: dismiss.callAsFunction
                ) {
                    NavigationLink {
                        Reading
                    } label: {
                        Next("Reading Status")
                    }
                    .buttonStyle(StepButtonStyle())
                }
            )
            .sheet(item: $linking) { tracker in
                linkSheet(tracker, opening) { linking = nil }
            }
            .task { onPrefetch() }
            // declared on the page rather than as a NavigationLink inside the empty
            // state - a NavigationLink whose source view is removed mid-push can
            // pop itself, and here that would happen while the sign-in sheet is up
            .navigationDestination(isPresented: $connecting) {
                TrackingScreen()
                    .containerBackground(.clear, for: .navigation)
            }
            // driven by the link landing, not by the sheet closing - the write
            // goes through the observation before it reaches here, so reading
            // status at dismiss time would race it
            .onChange(of: links) { was, now in
                guard
                    let fresh = now.first(where: { link in
                        !was.contains { $0.tracker == link.tracker }
                    })
                else { return }

                adopted = fresh.status
                linking = nil
            }
    }

    @ViewBuilder
    private var TrackersContent: some View {
        if accounts.isEmpty, links.isEmpty {
            ContentUnavailableView {
                Label("No Accounts", systemImage: "person.crop.circle.badge.plus")
            } description: {
                Text(
                    "Connect AniList or MyAnimeList to keep your list in step with what you read here."
                )
            } actions: {
                Button("Connect an Account") { connecting = true }
                    .buttonStyle(.glassProminent)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: dimensions.spacing.space16) {
                    Text(
                        "Link this series to keep your progress in step as you read. You can do this later from the series itself."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    DetailsTracking(
                        accounts: accounts,
                        links: links,
                        localProgress: localProgress,
                        showsHeader: false,
                        needingSignIn: needingSignIn,
                        syncing: syncing,
                        onLink: {
                            linking = $0
                            opening = false
                        },
                        onOpen: {
                            linking = $0.tracker
                            opening = true
                        },
                        onConnect: { connecting = true },
                        onRetry: { _ in },
                        reconciles: false,
                        matches: matches,
                        linking: writing,
                        onAutoLink: onAutoLink
                    )
                }
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.vertical, dimensions.spacing.space8)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
    }

    private var trackersSubtitle: Text {
        if accounts.isEmpty {
            Text(title)
        } else {
            Text("^[\(links.count) service](inflect: true) linked")
        }
    }

    // MARK: Reading status

    private var Reading: some View {
        ScrollView {
            VStack(spacing: dimensions.spacing.space12) {
                ForEach(Status.allCases, id: \.self) { value in
                    StatusRow(value)
                        .tappable { onSetStatus(value) }
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.bottom, dimensions.screenMargin)
            .animation(.settle, value: status)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        // only from the untouched default - overwriting a status the reader
        // already picked would clobber a deliberate choice
        .task {
            guard let adopted, status == .planning else { return }
            onSetStatus(adopted)
        }
        .sensoryFeedback(.selection, trigger: status)
        .modifier(
            Chrome(
                title: "Reading Status",
                subtitle: Text(status.label),
                isSaving: isSaving,
                onClose: dismiss.callAsFunction
            ) {
                NavigationLink {
                    Collections
                } label: {
                    Next("Collections")
                }
                .buttonStyle(StepButtonStyle())
            }
        )
    }

    private func StatusRow(_ value: Status) -> some View {
        let chosen = value == status

        return HStack(spacing: dimensions.spacing.space12) {
            Image(systemName: value.icon)
                .font(.title3)
                .foregroundStyle(value.tint)
                .frame(width: Layout.glyphWidth)

            Text(value.label)
                .font(.subheadline)
                .fontWeight(chosen ? .semibold : .regular)

            Spacer(minLength: 0)

            if chosen {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.brand)
                    .transition(.opacity)
            }
        }
        .padding(dimensions.spacing.space12)
        .background(
            chosen
                ? AnyShapeStyle(Palette.brandSubtle)
                : AnyShapeStyle(.primary.opacity(Layout.fillOpacity)),
            in: .rect(cornerRadius: dimensions.radius.radius12)
        )
        .contentShape(.rect)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    // MARK: Collections

    private var Collections: some View {
        CollectionsContent
            .sensoryFeedback(.selection, trigger: joinedCount)
            .sheet(isPresented: $creating) {
                CollectionForm(isSaving: isSaving, onCreate: onCreateCollection)
            }
            .modifier(
                Chrome(
                    title: "Collections",
                    subtitle: Text("^[\(joinedCount) collection](inflect: true) joined"),
                    isSaving: isSaving,
                    onClose: dismiss.callAsFunction
                ) { Finish() }
            )
    }

    @ViewBuilder
    private var CollectionsContent: some View {
        if collections.isEmpty {
            ContentUnavailableView {
                Label("No Collections", systemImage: "rectangle.stack")
            } description: {
                Text("Create a collection to group this series with others.")
            } actions: {
                Button("Create Collection") { creating = true }
                    .buttonStyle(.glassProminent)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: dimensions.spacing.space12) {
                    ForEach(collections) { collection in
                        CollectionRow(collection, joined: collection.contains)
                            .tappable { onToggleCollection(collection.id) }
                    }

                    Create
                }
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.bottom, dimensions.screenMargin)
                .animation(.settle, value: collections)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
    }

    private var joinedCount: Int {
        collections.filter(\.contains).count
    }

    private var Create: some View {
        HStack(spacing: dimensions.spacing.space12) {
            Image(systemName: "plus.circle.fill")
                .font(.title3)

            Text("New Collection")
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer(minLength: 0)
        }
        .foregroundStyle(Palette.brandText)
        .padding(dimensions.spacing.space12)
        .background(Palette.brandSubtle, in: .rect(cornerRadius: dimensions.radius.radius12))
        .contentShape(.rect)
        .tappable { creating = true }
    }

    // MARK: Chrome

    // resolved here, at the sheet's root - the same @Environment read inside a
    // pushed destination is that destination's dismiss, and pops one page
    // instead of closing the flow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stepPressed) private var pressed

    private func Next(_ title: String) -> some View {
        Step(overline: "Next", title: title, glyph: "arrow.right", tone: .brand)
    }

    private func Finish() -> some View {
        Button {
            dismiss()
        } label: {
            Step(overline: "All set", title: "Done", glyph: "checkmark", tone: .success)
        }
        .buttonStyle(StepButtonStyle())
    }

    private func Step(overline: String, title: String, glyph: String, tone: Palette.Tone)
        -> some View
    {
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
            }

            Spacer(minLength: 0)

            Glyph(glyph, trailing: tone == .brand)
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
        .onAppear {
            guard !reduceMotion else {
                streaked = true
                return
            }
            withAnimation(.smooth(duration: 0.45)) { streaked = true }
        }
    }

    private func Glyph(_ glyph: String, trailing streak: Bool) -> some View {
        let base = Image(systemName: glyph)
            .font(.subheadline)
            .fontWeight(.semibold)
            .contentTransition(.symbolEffect(.replace))

        // one multiplier for entry and press - two separate offsets would
        // fight whenever they overlapped
        let reach: CGFloat =
            if !streaked { Layout.streakEntry } else if pressed { Layout.streakPressed } else { 1 }

        return ZStack(alignment: .trailing) {
            if streak {
                ForEach(1...Layout.streakCount, id: \.self) { step in
                    let distance = Layout.streakOffset * CGFloat(step)

                    base
                        .opacity(Layout.streakOpacity / Double(step))
                        .blur(radius: Layout.streakBlur * CGFloat(step))
                        .offset(x: -distance * reach)
                        .opacity(streaked ? 1 : 0)
                }
            }

            base.offset(x: streak && pressed ? Layout.headLean : 0)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
        // this is a decorative repeat of the glyph in Step, which already
        // carries the accessible label - without this, VoiceOver reads the
        // arrow (and its ghosts) again on top of it
        .accessibilityHidden(true)
    }

    private struct Chrome<Footer: View>: ViewModifier {
        let title: String
        let subtitle: Text
        let isSaving: Bool
        var onClose: () -> Void
        @ViewBuilder var footer: () -> Footer

        @Environment(\.dimensions) private var dimensions

        func body(content: Content) -> some View {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .opacity(isSaving ? Layout.savingOpacity : 1)
                .animation(.settle, value: isSaving)
                .navigationTitle(title)
                .navigationSubtitle(subtitle)
                .toolbarTitleDisplayMode(.inline)
                .containerBackground(.clear, for: .navigation)
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

private struct SetupPreview: View {
    var seed: [CollectionPicker.Item] = Sample.collections
    var accounts: [Tracker] = [.anilist, .myAnimeList]
    var links: [DetailsTracking.Link] = []
    var needsSignIn: Set<Tracker> = []

    @State private var status: Status = .planning
    @State private var joined: Set<Int64> = [2]

    var body: some View {
        Color.clear.sheet(isPresented: .constant(true)) {
            DetailsSetup(
                title: "Vagabond",
                status: status,
                collections: seed.map {
                    .init(
                        id: $0.id, name: $0.name, count: $0.count, contains: joined.contains($0.id))
                },
                isSaving: false,
                accounts: accounts,
                links: links,
                localProgress: 42,
                needingSignIn: needsSignIn,
                syncing: [],
                onSetStatus: { status = $0 },
                onToggleCollection: { id in
                    if joined.contains(id) { joined.remove(id) } else { joined.insert(id) }
                },
                onCreateCollection: { _, _ in },
                linkSheet: { tracker, _, _ in Text("Link to \(tracker.name)") }
            )
        }
    }
}

private enum Sample {
    static let collections: [CollectionPicker.Item] = [
        .init(id: 1, name: "Currently Reading", count: 12, contains: false),
        .init(id: 2, name: "Isekai", count: 48, contains: true),
        .init(id: 3, name: "Finished", count: 106, contains: false),
        .init(id: 4, name: "Recommended by Ren", count: 1, contains: false),
    ]

    static let linked = DetailsTracking.Link(
        id: 1,
        tracker: .anilist,
        remoteId: 101177,
        remoteTitle: "Vagabond",
        status: .reading,
        progress: 42,
        total: 327,
        score: 90,
        scoreFormat: .point10,
        syncedDate: .now,
        attemptedDate: .now,
        failureReason: nil,
        queued: false
    )
}

#Preview("Flow") {
    SetupPreview()
}

#Preview("No accounts") {
    SetupPreview(accounts: [])
}

#Preview("Linked") {
    SetupPreview(links: [Sample.linked])
}

#Preview("Needs signing in") {
    SetupPreview(needsSignIn: [.anilist, .myAnimeList])
}

#Preview("No collections") {
    SetupPreview(seed: [])
}
