//
//  DetailsSetup.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import SwiftUI

// at file scope rather than nested: DetailsSetup is generic over its link sheet,
// and a generic type cannot hold static stored properties
// the press state of the card, published by its own button style so the label
// can read it. a ButtonStyle cannot re-parameterise the label it is handed, and
// a gesture alongside a NavigationLink races the link it sits on - the
// environment is the one channel that goes down rather than across
private extension EnvironmentValues {
    @Entry var stepPressed = false
}

private struct StepButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // the same squish .tappable gives every other control, or the two Next
        // cards would press differently from the Done card beside them
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
    // enough to read as an overline at caption2 without the word coming apart.
    // uppercase loses the ascender and descender cues that space letters for
    // you, which is why tracking is what makes a small uppercase label legible
    static let overlineTracking: CGFloat = 1.2
    // the afterimage behind the arrow. two ghosts, each further back, fainter
    // and blurrier than the last - a trail reads as speed because the eye is
    // being shown where something WAS, so the falloff matters more than the
    // count. a third adds nothing at this size but does add a smear
    static let streakCount = 3
    static let streakOffset: CGFloat = 5
    static let streakOpacity: Double = 0.35
    static let streakBlur: CGFloat = 0.6
    // where the ghosts start before settling, as a multiple of their resting
    // offset. far enough to read as arriving, near enough not to leave the card
    static let streakEntry: CGFloat = 3
    // held down, the trail lengthens and the head leans into it. released, a
    // spring pulls it back - the snap is the whole effect, so the return is
    // stiffer than the stretch
    static let streakPressed: CGFloat = 2.6
    static let headLean: CGFloat = 3
    // PressableButtonStyle's own values, so every card in the flow presses alike
    static let pressedScale: CGFloat = 0.95
    static let pressedOpacity: Double = 0.8
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
    // the second argument is whether the row that was tapped already had a link.
    // decided at tap time and held, never re-derived from the list: linking
    // writes a row, and a builder that re-reads the list swaps the screen out
    // from under the reader at the exact moment their commit lands
    @ViewBuilder var linkSheet: (Tracker, Bool, @escaping () -> Void) -> LinkSheet

    @Environment(\.dimensions) private var dimensions

    @State private var creating = false
    @State private var linking: Tracker?
    @State private var opening = false
    @State private var connecting = false
    // what a service says you are at, adopted from whichever one was linked most
    // recently on the page below. not an arbitration between two services: no
    // link can predate the add, so every link here is one the reader just made
    // and "the last one" is a fact about what they did rather than a merge
    @State private var adopted: Status?
    // one-shot, per page: the trail settles inward on appear and then holds. a
    // repeating version was the obvious reading of "sandevistan" and is the
    // wrong one for a footer - a control that never stops moving is the thing
    // the eye cannot leave alone
    @State private var streaked = false

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
                        .buttonStyle(StepButtonStyle())
                }
            )
        .sheet(item: $linking) { tracker in
            linkSheet(tracker, opening) { linking = nil }
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
            // and the same signal closes the link sheet. the page underneath is
            // the list of services, so the row filling in IS the outcome - the
            // Synced button that keeps a sheet open elsewhere has nothing to
            // show here that the flow does not already state one layer up.
            // only a NEW link, so editing one already made is not yanked shut
            linking = nil
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
                        onLink: { linking = $0; opening = false },
                        onOpen: { linking = $0.tracker; opening = true },
                        // reachable here, not decorative: a service that needs
                        // signing in again offers exactly this from its row, and
                        // it lands on the same pushed screen the empty state does
                        onConnect: { connecting = true },
                        // nothing has been pushed yet inside this flow, so there
                        // is never a failed sync to retry from here
                        onRetry: { _ in },
                        reconciles: false
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

    // resolved on this view, which lives at the sheet's root - the same property
    // read inside a pushed destination is that destination's dismiss and pops
    // one page instead of closing the flow
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.stepPressed) private var pressed

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
        Step(overline: "Next", title: title, glyph: "arrow.right", tone: .brand)
    }

    // the same card, ended. the last page had no footer at all, so the flow just
    // stopped - the reader was left to find the X, which is the exit for leaving
    // early rather than for finishing. a way out that means "I am done" is not
    // the same control as one that means "never mind"
    private func Finish() -> some View {
        // green, because this is the only card in the flow that is not a way
        // onward. the semantic table gives blue to interactive and green to
        // complete, and the reader learns the difference in one glance rather
        // than by reading the word
        Button { dismiss() } label: {
            Step(overline: "All set", title: "Done", glyph: "checkmark", tone: .success)
        }
        .buttonStyle(StepButtonStyle())
    }

    private func Step(overline: String, title: String, glyph: String, tone: Palette.Tone) -> some View {
        HStack(spacing: dimensions.spacing.space12) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                // the word that does the work. a destination name with its
                // current value beneath it is Settings grammar - it describes a
                // place - and no amount of fill turns that into "forward". this
                // says what the tap DOES before it says where it goes.
                //
                // an overline: uppercased and letter-spaced, which is what makes
                // it read as a label ABOUT the line below rather than as a first
                // line of it. a rule was tried here and dangled - it separated
                // two things that were never competing, where the gap in size,
                // weight and tracking already does all the separating needed
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

            // an arrow, not a chevron. a chevron is disclosure - it means "there
            // is more inside this row" - where an arrow is motion. the two look
            // alike and mean different things, and the settings row this was
            // borrowing from is precisely the disclosure case
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

    // the afterimage. only on the arrow: a checkmark is a state that arrived,
    // not a thing in motion, and giving it a trail would say the flow is still
    // going somewhere. drawn behind, trailing-aligned, so the glyph itself
    // never moves and the trail grows out of where it already is
    private func Glyph(_ glyph: String, trailing streak: Bool) -> some View {
        let base = Image(systemName: glyph)
            .font(.subheadline)
            .fontWeight(.semibold)
            .contentTransition(.symbolEffect(.replace))

        // at rest 1, on the way in 3, held down 2.6 - one multiplier, because the
        // arrival and the press are the same gesture at different moments and
        // two separate offsets would fight whenever they overlapped
        let reach: CGFloat =
            if !streaked { Layout.streakEntry }
            else if pressed { Layout.streakPressed }
            else { 1 }

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

            // the head leans the way it is going while the trail stretches behind
            // it, so the press reads as loading a spring rather than as the glyph
            // sliding off its own trail
            base.offset(x: streak && pressed ? Layout.headLean : 0)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
        // the ghosts are the same glyph again, so VoiceOver would otherwise read
        // the arrow three times
        .accessibilityHidden(true)
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
        failureReason: nil,
        queued: false
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
