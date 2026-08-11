//
//  DetailsSetup.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import SwiftUI

// at file scope rather than nested: DetailsSetup is generic over its link sheet,
// and a generic type cannot hold static stored properties
private enum Layout {
    static let glyphWidth: CGFloat = 28
    static let fillOpacity: Double = 0.05
    static let savingOpacity: Double = 0.6
}

// what happens after a series joins the library, not what decides whether it
// does. the add is already written by the time this appears, so every page here
// commits on tap - closing at any point leaves the series added and whatever was
// answered so far kept. nothing is staged, so there is nothing to lose by
// leaving, which is what lets the flow be three pages instead of one crowded one
struct DetailsSetup<LinkSheet: View>: View {
    let title: String
    let status: Status
    let collections: [CollectionPicker.Item]
    let isSaving: Bool
    // the tracker page's own inputs, the same four the Details section takes -
    // it renders the same rows, so it asks for the same facts
    let accounts: [Tracker]
    let links: [DetailsTracking.Link]
    let localProgress: Int
    let needingSignIn: Set<Tracker>
    let syncing: Set<Tracker>
    var onSetStatus: (Status) -> Void
    var onToggleCollection: (Int64) -> Void
    var onCreateCollection: (String, String?) -> Void
    // handed in rather than built here: linking needs eight closures onto the
    // view model, and the screen that owns them already constructs this sheet
    // for its own section. one builder keeps that construction in one place, and
    // the second argument is how to close it - the presenter owns dismissal,
    // because the two places this sheet is shown from are driven by different
    // state and neither can dismiss the other's
    @ViewBuilder var linkSheet: (Tracker, @escaping () -> Void) -> LinkSheet

    @Environment(\.dimensions) private var dimensions

    @State private var creating = false
    @State private var linking: Tracker?
    @State private var connecting = false
    // what a service says you are at, adopted from whichever one was linked most
    // recently on the page below. not an arbitration between two services: no
    // link can predate the add, so every link here is one the reader just made
    // and "the last one" is a fact about what they did rather than a merge
    @State private var adopted: Status?

    var body: some View {
        NavigationStack {
            Trackers
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Trackers

    // the first page because linking is what the next one adopts its answer
    // from. nothing here gates anything: the series is already in the library
    // and all three pages are the optional half
    private var Trackers: some View {
        TrackersContent
            .modifier(
                Chrome(
                    title: "Trackers",
                    subtitle: trackersSubtitle,
                    isSaving: isSaving,
                    onClose: dismiss.callAsFunction
                ) {
                    NavigationLink { Reading } label: { Next("Reading Status") }
                        .buttonStyle(.plain)
                }
            )
        .sheet(item: $linking) { tracker in
            linkSheet(tracker) { linking = nil }
        }
        // declared on the page rather than as a NavigationLink inside the empty
        // state, because connecting is what makes that empty state stop existing:
        // a link whose own source view is removed mid-push can pop itself, and
        // here it would do so while the sign-in sheet is still up
        .navigationDestination(isPresented: $connecting) {
            // pushed into this stack rather than opening Settings, so connecting
            // does not cost the reader the flow they are in. it carries the clear
            // background its siblings set through Chrome, or it paints over the
            // sheet's glass on the way in
            TrackingScreen()
                .containerBackground(.clear, for: .navigation)
        }
        // driven by the link landing rather than by the sheet closing: the write
        // goes through the observation before it reaches here, so reading the
        // status at dismiss time would race it
        .onChange(of: links) { was, now in
            guard let fresh = now.first(where: { link in
                !was.contains { $0.tracker == link.tracker }
            }) else { return }

            adopted = fresh.status
        }
    }

    @ViewBuilder
    private var TrackersContent: some View {
        // the same union the section uses: a service can be linked with no
        // account behind it, and that row has to survive to say so
        if accounts.isEmpty, links.isEmpty {
            // a whole page with nothing on it, which is what a full-surface
            // ContentUnavailableView is for - unlike the Details section, which
            // uses a single row because it sits between two full sections
            ContentUnavailableView {
                Label("No Accounts", systemImage: "person.crop.circle.badge.plus")
            } description: {
                Text("Connect AniList or MyAnimeList to keep your list in step with what you read here.")
            } actions: {
                Button("Connect an Account") { connecting = true }
                    .buttonStyle(.glassProminent)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: dimensions.spacing.space16) {
                    Text("Link this series to keep your progress in step as you read. You can do this later from the series itself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    DetailsTracking(
                        accounts: accounts,
                        links: links,
                        localProgress: localProgress,
                        showsHeader: false,
                        needingSignIn: needingSignIn,
                        syncing: syncing,
                        onLink: { linking = $0 },
                        onOpen: { linking = $0.tracker },
                        // reachable here, not decorative: a service that needs
                        // signing in again offers exactly this from its row, and
                        // it lands on the same pushed screen the empty state does
                        onConnect: { connecting = true },
                        // nothing has been pushed yet inside this flow, so there
                        // is never a failed sync to retry from here
                        onRetry: { _ in }
                    )
                }
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.vertical, dimensions.spacing.space8)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
    }

    // the page's own state, matching what the other two pages put here. built as
    // branches rather than a ternary: a String on either side of a ternary types
    // the whole expression as String and the inflection markup renders verbatim
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
        // a linked tracker already knows where you are, so the page adopts its
        // answer instead of asking again - only from the untouched default, or
        // it would overwrite a choice made a moment ago
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
                NavigationLink { Collections } label: { Next("Collections") }
                    .buttonStyle(.plain)
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

            // trailing tick for the chosen one of a set, leading circles for
            // membership on the next page - two questions, two markers
            if chosen {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Palette.brand)
                    .transition(.opacity)
            }
        }
        .padding(dimensions.spacing.space12)
        .background(
            chosen ? AnyShapeStyle(Palette.brandSubtle) : AnyShapeStyle(.primary.opacity(Layout.fillOpacity)),
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
                ) { EmptyView() }
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

    // resolved on this view, which lives at the sheet's root - the same property
    // read inside a pushed destination is that destination's dismiss and pops
    // one page instead of closing the flow
    @Environment(\.dismiss) private var dismiss

    // progression as a row rather than a pinned button. a full-width prominent
    // control is submit grammar, and there is nothing here to submit: the add
    // landed before this sheet opened and every page writes on tap.
    //
    // tinted rather than glass, and that is not taste: the sheet's own surface
    // IS glass at the medium detent, and glass cannot sample glass - nested, it
    // renders as a flat sticker, which is exactly how this row read. the fill is
    // what makes it the one coloured thing on the page, and it is the recipe the
    // New Collection row two pages along already uses: one colour, drawn as the
    // foreground and again at opacity behind it.
    //
    // an accent on an ACTION is not the always-blue-says-nothing case, which is
    // about state. the current value earns its place twice over, since it also
    // answers the page's question without going there
    private func Next(_ title: String) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                // the word that does the work. a destination name with its
                // current value beneath it is Settings grammar - it describes a
                // place - and no amount of fill turns that into "forward". this
                // says what the tap DOES before it says where it goes
                Text("Next")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            Spacer(minLength: 0)

            // an arrow, not a chevron. a chevron is disclosure - it means "there
            // is more inside this row" - where an arrow is motion. the two look
            // alike and mean different things, and the settings row this was
            // borrowing from is precisely the disclosure case
            Image(systemName: "arrow.right")
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .foregroundStyle(Palette.brandText)
        .padding(.horizontal, dimensions.spacing.space16)
        .padding(.vertical, dimensions.spacing.space12)
        .frame(minHeight: dimensions.touchTarget)
        .background(
            Palette.brandSubtle,
            in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
        .contentShape(.rect)
    }

    // one frame for all three pages, and one way out of the flow from any of
    // them. close sits trailing on every page because leaving is allowed on
    // every page - it was on the last one only, which read as "you may go once
    // you have finished". back stays leading, where the system puts it
    private struct Chrome<Footer: View>: ViewModifier {
        let title: String
        let subtitle: Text
        let isSaving: Bool
        // handed in rather than read here: a modifier applied to a pushed page
        // sees that page's dismiss, which pops one page instead of closing
        var onClose: () -> Void
        // the way onward, in the same place on every page that has one. via
        // safeAreaInset rather than an overlay, so the list above scrolls clear
        // of it instead of ending underneath it
        @ViewBuilder var footer: () -> Footer

        @Environment(\.dimensions) private var dimensions

        func body(content: Content) -> some View {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // a write is in flight and the rows it will change are on screen
                .opacity(isSaving ? Layout.savingOpacity : 1)
                .animation(.settle, value: isSaving)
                .navigationTitle(title)
                .navigationSubtitle(subtitle)
                .toolbarTitleDisplayMode(.inline)
                // the medium detent is what makes the sheet glass; a navigation
                // container paints over it unless told not to
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
                    .init(id: $0.id, name: $0.name, count: $0.count, contains: joined.contains($0.id))
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
                linkSheet: { tracker, _ in Text("Link to \(tracker.name)") }
            )
        }
    }
}

private enum Sample {
    static let collections: [CollectionPicker.Item] = [
        .init(id: 1, name: "Currently Reading", count: 12, contains: false),
        .init(id: 2, name: "Isekai", count: 48, contains: true),
        .init(id: 3, name: "Finished", count: 106, contains: false),
        .init(id: 4, name: "Recommended by Ren", count: 1, contains: false)
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
        failureReason: nil
    )
}

// the ordinary path: two accounts connected, neither linked yet
#Preview("Flow") {
    SetupPreview()
}

// nothing connected, so the page is the invitation rather than a list. the
// Connect action pushes the account screen into this same stack, so answering it
// lands back here with the row filled in
#Preview("No accounts") {
    SetupPreview(accounts: [])
}

// one service linked. the next page adopts its status, so the reader arrives on
// Reading rather than plan-to-read without touching anything
#Preview("Linked") {
    SetupPreview(links: [Sample.linked])
}

// connected but out of road, inside the flow: Link would fail, so the row sends
// the reader to the account screen this sheet can push
#Preview("Needs signing in") {
    SetupPreview(needsSignIn: [.anilist, .myAnimeList])
}

#Preview("No collections") {
    SetupPreview(seed: [])
}
