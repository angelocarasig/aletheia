//
//  DetailsSetup.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import SwiftUI

// what happens after a series joins the library, not what decides whether it
// does. the add is already written by the time this appears, so every page here
// commits on tap - closing at any point leaves the series added and whatever was
// answered so far kept. nothing is staged, so there is nothing to lose by
// leaving, which is what lets the flow be three pages instead of one crowded one
struct DetailsSetup: View {
    let title: String
    let status: Status
    let collections: [CollectionPicker.Item]
    let isSaving: Bool
    // what a tracker says you are at. nil while trackers are a stub; once one
    // lands, the status page adopts it rather than starting at plan-to-read
    let trackedStatus: Status?
    var onSetStatus: (Status) -> Void
    var onToggleCollection: (Int64) -> Void
    var onCreateCollection: (String, String?) -> Void

    @Environment(\.dimensions) private var dimensions

    @State private var creating = false

    private enum Layout {
        static let glyphWidth: CGFloat = 28
        static let fillOpacity: Double = 0.05
        static let savingOpacity: Double = 0.6
    }

    var body: some View {
        NavigationStack {
            Trackers
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Trackers

    private var Trackers: some View {
        ContentUnavailableView {
            Label("Trackers", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
        } description: {
            Text("Linking a service to sync your progress isn't available yet. Your reading status is next.")
        }
        .modifier(Chrome(title: "Trackers", subtitle: Text(title), isSaving: isSaving) {
            NavigationLink { Reading } label: { Forward("Continue") }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        })
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
            .animation(.settle, value: status)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        // a linked tracker already knows where you are, so the page adopts its
        // answer instead of asking again - only from the untouched default, or
        // it would overwrite a choice made a moment ago
        .task {
            guard let trackedStatus, status == .planning else { return }
            onSetStatus(trackedStatus)
        }
        .sensoryFeedback(.selection, trigger: status)
        .modifier(Chrome(title: "Reading Status", subtitle: Text(status.label), isSaving: isSaving) {
            NavigationLink { Collections } label: { Forward("Continue") }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        })
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
                    // the end of the flow, so the forward affordance becomes a
                    // way out. one or the other per page, never both - a Close
                    // beside a Continue reads as two ways forward
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

    private func Forward(_ label: String) -> some View {
        Text(label)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
    }

    // every page wears the same frame, with exactly one way onward: a footer
    // that continues, or - on the last page - a close in the trailing slot the
    // back button never takes
    private struct Chrome<Footer: View>: ViewModifier {
        let title: String
        let subtitle: Text
        let isSaving: Bool
        // the last page has nowhere to continue to, so it trades its footer for
        // a close in the slot the back button never occupies. handed in rather
        // than read here: a modifier applied to a pushed page sees that page's
        // dismiss, which pops
        var onClose: (() -> Void)?
        @ViewBuilder let footer: () -> Footer

        @Environment(\.dimensions) private var dimensions

        func body(content: Content) -> some View {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // a write is in flight and the rows it will change are on screen
                .opacity(isSaving ? DetailsSetup.Layout.savingOpacity : 1)
                .animation(.settle, value: isSaving)
                .navigationTitle(title)
                .navigationSubtitle(subtitle)
                .toolbarTitleDisplayMode(.inline)
                // the medium detent is what makes the sheet glass; a navigation
                // container paints over it unless told not to
                .containerBackground(.clear, for: .navigation)
                .containerBackground(.clear, for: .navigation)
                .safeAreaInset(edge: .bottom) {
                    if onClose == nil {
                        footer()
                            .padding(.horizontal, dimensions.screenMargin)
                            .padding(.bottom, dimensions.spacing.space8)
                    }
                }
                .toolbar {
                    if let onClose {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Close", systemImage: "xmark", action: onClose)
                                .labelStyle(.iconOnly)
                        }
                    }
                }
        }
    }
}

// MARK: - Previews

private struct SetupPreview: View {
    var seed: [CollectionPicker.Item] = Sample.collections
    var trackedStatus: Status?

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
                trackedStatus: trackedStatus,
                onSetStatus: { status = $0 },
                onToggleCollection: { id in
                    if joined.contains(id) { joined.remove(id) } else { joined.insert(id) }
                },
                onCreateCollection: { _, _ in }
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
}

#Preview("Flow") {
    SetupPreview()
}

// a tracker answering for you: the status page opens already on Reading rather
// than plan-to-read, without the reader touching anything
#Preview("Tracked") {
    SetupPreview(trackedStatus: .reading)
}

#Preview("No collections") {
    SetupPreview(seed: [])
}
