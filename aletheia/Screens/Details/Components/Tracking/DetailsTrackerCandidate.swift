//
//  DetailsTrackerCandidate.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import SwiftUI
import Kingfisher

// one candidate, in full, and the last thing between the reader and a write to a
// public list.
//
// the search list can only show what a row has space for, and the fact that
// matters most is not on the service's media at all - it is on the READER'S own
// entry for it: whether they already track this, how far it says they are, and
// what linking would change that to. so this fetches the entry on appear rather
// than the list fetching fifty of them, and states the outcome in words before
// the button that causes it
struct DetailsTrackerCandidate: View {
    let tracker: Tracker
    let candidate: TrackerCandidate
    // how far this app has you read, which is what a link would seed the entry with
    let localProgress: Int
    // another series in the library already points at this entry
    let conflict: String?
    // the account's own scale, so a score renders in the units the reader set on
    // the website rather than ours
    let scoreFormat: ScoreFormat
    // already linked: the screen becomes a manage screen and the commit saves
    // rather than links
    var linked: Bool = false
    // off inside the add-to-library flow. the series was added seconds ago, so
    // local progress is zero by construction and the banner fires on every link
    // saying the same thing - which is not a disagreement, it is the expected
    // state of a fresh row. the series page already shows the divergence as a
    // standing fact on the tracker row, so this is a duplicate asked at the one
    // moment the reader has no way to answer it
    var reconciles: Bool = true
    // read from the link row rather than from the entry this screen fetches, so
    // it still answers while that fetch is running and when it fails - which is
    // exactly when "are these numbers current" is worth asking. nil on the way
    // IN to a link, where nothing could have synced yet
    var syncedDate: Date?
    var onLoad: () async throws -> TrackerEntry
    // awaited rather than fired: a control that reports saving, saved and failed
    // has to know which of those happened, and only the caller does
    var onCommit: (TrackerCandidate, TrackerUpdate) async throws -> Void
    // the flag is whether to remove the entry from the reader's list as well -
    // two genuinely different outcomes, so the alert asks rather than assuming
    var onUnlink: ((Bool) -> Void)?
    // marks chapters read in THIS app, up to the number the service holds
    var onCatchUp: ((Int) -> Void)?
    // the other direction: this app is further along, so every linked service
    // gets the number. all of them, not just this one - they are all behind the
    // same read state
    var onPushLocal: (() -> Void)?
    // leaves the whole flow, which is not the same as leaving this screen. the
    // caller owns it because @Environment(\.dismiss) means "pop" on a pushed
    // copy of this view and "close the sheet" on a root one, and the X has to
    // mean the second thing in both places
    var onClose: (() -> Void)?

    @Environment(\.dimensions) private var dimensions
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var entry: TrackerEntry?
    @State private var phase: LoadPhase = .pending
    @State private var failure: Failure?

    // its own reference type so only the backdrop observes it - held beside the
    // scroll view, every update would re-evaluate a body holding the whole screen
    @State private var scroll = DetailsScroll()

    // the draft, seeded from whichever is further along once the entry lands.
    // separate from `entry` because the commit is staged - nothing reaches the
    // service until the button, which is the rule for anything that writes to a
    // public list
    @State private var status: Status = .reading
    @State private var progress = 0
    @State private var score = 0
    @State private var seeded = false
    @State private var unlinking = false
    @State private var confirming: TrackerReconcile?
    // the write landed and the screen stayed. the button becomes the state it
    // produced, and tapping it again is the way back out
    @State private var committed = false
    // whether the draft holds anything the service has not been told. set by the
    // controls themselves rather than derived from a diff, so it survives the
    // entry failing to load - the push re-reads before it writes anyway
    // what the controls held when the screen settled, so "changed" is a
    // comparison rather than a flag: moving a value and moving it back is not a
    // change, and a one-way flag said it was.
    //
    // captured at SEED time rather than diffed against the fetched entry, which
    // is the part that has to stay - seeding runs on the failure path too, so a
    // reader whose entry would not load can still edit and still save
    @State private var baseline: Draft?

    private struct Draft: Equatable {
        var status: Status
        var progress: Int
        var score: Int
    }

    private var current: Draft {
        .init(status: status, progress: progress, score: score)
    }
    // the inline save's own lifecycle, which is separate from `committed`: that
    // one is about a link having been made, this one about a write landing
    @State private var saving: SaveState = .idle
    // an alert rather than an inline field: this screen is a large-detent sheet
    // and the row sits mid-height, so a number pad would cover the row it is
    // editing along with the commit below it
    @State private var typing = false
    @State private var draft = ""


    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }


    private enum Layout {
        // fractions of the artwork's own 700pt height. it is untouched above
        // fadeStart, gone below fadeEnd, and on its way out between them
        static let fadeStart: CGFloat = 0.20
        static let fadeEnd: CGFloat = 0.75

        // where a stepper stops when the service has no total - high enough that
        // no real series reaches it, low enough that a held finger cannot run away
        static let progressCeiling = 9999
        static let coverWidth: CGFloat = 120
        static let coverAspect: CGFloat = 11 / 16
        static let placeholderOpacity: Double = 0.1
        static let fillOpacity: Double = 0.05
        static let barHeight: CGFloat = 6
        static let trackOpacity: Double = 0.15
        static let tickWidth: CGFloat = 3
        // a state marker, not a fill: at full strength the destructive control
        // outweighs the one it sits beside, which inverts what the row offers
        static let washOpacity: Double = 0.25
        // sized to the cap height of the subheadline beside it, so the mark
        // reads as part of the label rather than as a separate element
        static let markSize: CGFloat = 18
        static let markDrop: CGFloat = 4
    }

    // what the screen actually draws: the seed it was handed, with anything the
    // fetched entry knows better laid over it. a linked row can only seed an id,
    // a title and a total, so without this the artwork never arrives - the
    // request that carries it lands in `entry` and nothing reads it
    private var subject: TrackerCandidate {
        guard let entry else { return candidate }
        let remote = entry.candidate

        // every fallback here reads the SEED, never `subject` - this is the
        // getter that produces it, so a self-reference is unbounded recursion
        return TrackerCandidate(
            id: candidate.id,
            title: remote.title.isEmpty ? candidate.title : remote.title,
            cover: remote.cover ?? candidate.cover,
            year: remote.year ?? candidate.year,
            totalChapters: remote.totalChapters ?? candidate.totalChapters,
            status: remote.status == .Unknown ? candidate.status : remote.status,
            adult: remote.adult || candidate.adult,
            authors: remote.authors ?? candidate.authors,
            synopsis: remote.synopsis ?? candidate.synopsis,
            format: remote.format ?? candidate.format
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            DetailsBackdrop(
                cover: subject.cover,
                referer: nil,
                scroll: scroll,
                fadeStart: Layout.fadeStart,
                fadeEnd: Layout.fadeEnd
            )

            ScrollView {
                VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                    // the backdrop shows through here
                    Spacer()
                        .frame(height: DetailsBackdrop.heroHeight)

                    Hero
                    Actions
                    Entry
                    Editor
                    Synopsis
                    Facts
                }
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.bottom, dimensions.spacing.space16)
            }
            // clamped inside the transform, not after: the callback only fires
            // when its value changes, so clamping stops it entirely past the ramp
            // rather than firing for the rest of the scroll. rounding bounds the
            // ramp itself to a few dozen updates instead of one a frame
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                let scrolled = geometry.contentOffset.y + geometry.contentInsets.top
                let ramped = min(max(scrolled, 0), DetailsBackdrop.blurDistance)
                return (ramped / DetailsBackdrop.blurStep).rounded() * DetailsBackdrop.blurStep
            } action: { _, offset in
                scroll.offset = offset
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
        }
        .navigationTitle(tracker.name)
        .navigationBarTitleDisplayMode(.inline)
        .containerBackground(.clear, for: .navigation)
        .toolbar {
            // trailing on both presentations, so it never collides with the back
            // chevron a pushed copy already has: the chevron goes back one, this
            // leaves. one destructive action does not earn a menu, so unlink
            // moved into Details where it reads next to what it undoes
            if let onClose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "chevron.down", action: onClose)
                        .labelStyle(.iconOnly)
                }
            }
        }
        // both outcomes are destructive and only one is reversible, so they are
        // spelled out rather than hidden behind one word. the default is the
        // quiet one: stop syncing, leave the list alone
        .alert("Chapters Read", isPresented: $typing) {
            TypingAlert
        } message: {
            Text("Enter the chapter you are up to on \(tracker.name).")
        }
        .alert("Unlink from \(tracker.name)?", isPresented: $unlinking) {
            Button("Unlink", role: .destructive) { onUnlink?(false) }

            Button("Unlink and Delete Entry", role: .destructive) { onUnlink?(true) }

            Button("Cancel", role: .cancel) { unlinking = false }
        } message: {
            Text("Unlinking stops syncing and leaves your \(tracker.name) entry as it is. Deleting removes it from your list entirely, along with its score and dates. That can't be undone.")
        }
        .trackerReconcile(
            $confirming,
            subject: tracker.name,
            onCatchUp: { onCatchUp?($0) },
            onPushLocal: { onPushLocal?() }
        )
        .safeAreaInset(edge: .bottom) { Commit }
        // the button reports whether there is unsent work, so touching a control
        // after a save has to take it out of Synced - otherwise the one tap that
        // would send the change unlinks instead, and the only way to save is to
        // close the sheet and come back
        .onChange(of: status) { _, _ in touched() }
        .onChange(of: progress) { _, _ in touched() }
        .onChange(of: score) { _, _ in touched() }
        .sensoryFeedback(.selection, trigger: progress)
        .sensoryFeedback(.selection, trigger: status)
        .task { await load() }
    }

    // MARK: Hero

    private var Hero: some View {
        HStack(alignment: .top, spacing: dimensions.spacing.space16) {
            KFImage(subject.cover)
                .resizable()
                .placeholder {
                    Rectangle().fill(.primary.opacity(Layout.placeholderOpacity))
                }
                .fade(duration: 0.2)
                .scaledToFill()
                .frame(
                    width: Layout.coverWidth,
                    height: Layout.coverWidth / Layout.coverAspect
                )
                .clipShape(.rect(cornerRadius: dimensions.radius.radius12, style: .continuous))

            VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                Text(subject.title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.leading)

                if let authors = subject.authors, !authors.isEmpty {
                    Text(authors)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                FlowLayout(spacing: dimensions.spacing.space4) {
                    if subject.status != .Unknown {
                        Badge(
                            text: subject.status.label.uppercased(),
                            tone: tone(for: subject.status),
                            size: .compact
                        )
                    }

                    if let format = subject.format {
                        Badge(text: format.uppercased(), tone: .warning, size: .compact)
                    }

                    if subject.adult {
                        Badge(text: "ADULT", tone: .danger, size: .compact)
                    }
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Actions

    // above the entry rather than under the last fact on the page. both are one
    // tap and both are about the entry this screen is showing, so they belong
    // where it is introduced - as rows at the bottom they were reachable only by
    // scrolling past everything the reader came here to read
    @ViewBuilder
    private var Actions: some View {
        let url = tracker.url(for: subject.id)
        let unlinkable = linked && onUnlink != nil

        if url != nil || unlinkable {
            GlassEffectContainer(spacing: dimensions.spacing.space8) {
                HStack(spacing: dimensions.spacing.space8) {
                    if let url {
                        Label("Open on \(tracker.name)", systemImage: "arrow.up.right")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .modifier(Control())
                            .tappable { openURL(url) }
                    }

                    // a circle, and the narrower of the two: leaving is not what
                    // this screen is for, and a destructive control at equal
                    // width to the one beside it reads as an equal offer.
                    //
                    // the link family has no slash and no badge.minus - checked
                    // against the sdk's own catalog rather than guessed at, since
                    // a symbol that does not exist renders as nothing at all.
                    // personalhotspot.slash is the interlocking rings with a
                    // slash through them, which is the broken-chain reading the
                    // link family never shipped.
                    //
                    // the wash is a quarter strength, which is what keeps the
                    // glyph legible in the same family's text step rather than
                    // left to glass - the same pairing DetailsActions uses
                    if unlinkable {
                        Image(systemName: "personalhotspot.slash")
                            .foregroundStyle(Palette.dangerText)
                            .modifier(Control(tint: Palette.danger.opacity(Layout.washOpacity), circular: true))
                            .tappable { unlinking = true }
                            .accessibilityLabel("Unlink from \(tracker.name)")
                    }
                }
            }
            .frame(height: dimensions.size.controlL)
        }
    }

    private struct Control: ViewModifier {
        var tint: Color?
        // a circle takes its width from its height and carries no label, so it
        // reads as one action rather than the short end of a pair
        var circular = false

        @Environment(\.dimensions) private var dimensions

        @ViewBuilder
        func body(content: Content) -> some View {
            let sized = content
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, circular ? 0 : dimensions.spacing.space12)
                .frame(
                    width: circular ? dimensions.size.controlL : nil,
                    height: dimensions.size.controlL
                )

            // branched rather than type-erased: the shape parameter takes a
            // concrete InsettableShape and the two have no common box here
            if circular {
                sized.glassEffect(glass, in: .circle)
            } else {
                sized.glassEffect(
                    glass,
                    in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
                )
            }
        }

        private var glass: Glass {
            tint.map { .regular.tint($0).interactive() } ?? .regular.interactive()
        }
    }

    // MARK: Your entry

    // the section the search list could not carry, and the reason this screen
    // exists. an entry the reader already tracks says so in their own numbers,
    // not the service's
    @ViewBuilder
    private var Entry: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader("On Record")

            switch phase {
            case .content:
                if let entry {
                    Standing(entry).transition(.opacity)
                }
            case .failed:
                Trouble.transition(.opacity)
            default:
                Loading.transition(.opacity)
            }

            // split at the full stop it already had: what is true, then what it
            // costs. one paragraph made the reader finish both to learn either
            if let conflict {
                Banner(
                    "\(conflict) is already linked to this entry",
                    message: "Linking here means both series push their own progress to it.",
                    systemImage: "exclamationmark.triangle"
                )
            }
        }
        .animation(.settle, value: phase)
    }

    private var Loading: some View {
        HStack(spacing: dimensions.spacing.space8) {
            // a continuously spinning symbol is what Reduce Motion exists for,
            // and the words beside it already say what is happening
            Image(systemName: "progress.indicator")
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: !reduceMotion)

            Text("Checking your list")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(dimensions.spacing.space12)
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
    }

    // glyph-less on purpose: the two banners this one sits between are things to
    // act on, and this is a note about a fetch that failed harmlessly
    @ViewBuilder
    private var Trouble: some View {
        // Failure is already a title and a sentence under it, so the two halves
        // go to the two slots rather than one of them being dropped. it used to
        // read .message alone, which renders blank for any error that states a
        // title and nothing else
        if let failure {
            Banner(
                title: Text(failure.title),
                message: failure.message.isEmpty ? nil : Text(failure.message)
            )
        } else {
            Banner(
                "Couldn't reach \(tracker.name)",
                message: "Linking still works, and it will read your entry when it syncs."
            )
        }
    }

    // five states, and each says something different:
    //
    //   not listed    what linking will write, since there is nothing to compare
    //   in step       both rows, and a mark saying so - silence would read as
    //                 the card having failed to work out the answer
    //   remote ahead  both rows, service leading
    //   local ahead   both rows, this app leading
    //   no total      both rows, no bars, counts read "60 read" instead
    //
    // the two rows render in all four listed states. the shape is what a reader
    // learns, and a card that reorganises itself when the numbers agree teaches
    // the layout twice
    @ViewBuilder
    private func Standing(_ entry: TrackerEntry) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space16) {
            if entry.isListed {
                Side(
                    tracker.name,
                    icon: { Image(tracker.icon).resizable().scaledToFit() },
                    value: entry.progress,
                    of: entry.totalChapters,
                    leading: entry.progress >= localProgress
                )

                Side(
                    Constants.App.name,
                    icon: { Image(.aletheia).resizable().scaledToFit() },
                    value: localProgress,
                    of: entry.totalChapters,
                    leading: localProgress >= entry.progress
                )

                if entry.progress == localProgress {
                    // a verdict on the two rows above rather than a third row of
                    // the same kind, so it sits behind a rule - which is also
                    // what stops it reading as a label for the bar it follows
                    Divider()

                    // a fact, so it takes the secondary checkmark rather than the
                    // brand one - nothing here was chosen
                    Label("In step", systemImage: "checkmark")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
            } else {
                // one thought, so they sit together: what is true, then what the
                // commit will do about it. at the card's own spacing they read as
                // two separate announcements
                VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                    Text("Not on your \(tracker.name) list yet.")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

                    // the state a reader meets first, and the only one where the
                    // commit writes a number nothing on screen has shown them
                    Group {
                        if localProgress > 0 {
                            Text("Linking adds it at chapter \(localProgress).")
                        } else {
                            Text("Linking adds it with no progress yet.")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(dimensions.spacing.space16)
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
    }

    // `leading` is which side is further along, not which side is right. when the
    // two agree both lead, so neither dims and equality reads as equality rather
    // than as a tie nobody won
    private func Side<Icon: View>(
        _ name: String,
        @ViewBuilder icon: () -> Icon,
        value: Int,
        of total: Int?,
        leading: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            HStack(alignment: .firstTextBaseline, spacing: dimensions.spacing.space8) {
                // centred on the text rather than sharing its baseline: a square
                // mark hung off a baseline sits low against the letters beside it
                icon()
                    .frame(width: Layout.markSize, height: Layout.markSize)
                    .clipShape(.circle)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - Layout.markDrop }

                // the quieter half of the pair: whose number it is matters less
                // than what the number is, and the mark beside it has already
                // said whose. a step down in size does that without a second
                // colour doing it
                Text(name)
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: dimensions.spacing.space8)

                Group {
                    if let total, total > 0 {
                        Text("\(value) of \(total)")
                    } else {
                        Text("\(value) read")
                    }
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                // fixed-width digits, or the numericText roll shifts every
                // character beside it each time a count crosses a digit width
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.settle, value: value)
            }

            Bar(value: value, of: total, leading: leading)
        }
    }

    // no denominator, no bar: a length with nothing to be a fraction of is
    // decoration, and an ongoing series genuinely has no total
    @ViewBuilder
    private func Bar(value: Int, of total: Int?, leading: Bool) -> some View {
        if let total, total > 0 {
            GeometryReader { geometry in
                let width = geometry.size.width
                let fraction = min(Double(value) / Double(total), 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.primary.opacity(Layout.trackOpacity))

                    Capsule()
                        .fill(leading ? AnyShapeStyle(Palette.brand) : AnyShapeStyle(.tertiary))
                        .frame(width: max(width * fraction, Layout.barHeight))
                }
            }
            .frame(height: Layout.barHeight)
        }
    }

    // MARK: Sync

    // a banner in the section it concerns rather than a control in the chrome.
    // the disagreement is a fact about the numbers directly below it, and beside
    // the commit it read as a second thing to press before leaving
    @ViewBuilder
    private var Disagreement: some View {
        if reconciles, let entry, entry.isListed, entry.progress != localProgress {
            let remoteAhead = entry.progress > localProgress

            // the cloud is the service and the arrow is which way the number
            // travels, so the glyph says WHO is ahead rather than only which
            // direction something moves. a bare up/down arrow was true of the
            // transfer and silent about the two parties, which is the whole
            // subject of this banner.
            //
            // branched rather than ternaried so each string stays a literal:
            // a ternary with a String on either side erases inflection markup
            Group {
                if remoteAhead {
                    Banner(
                        "\(tracker.name) is at chapter \(entry.progress)",
                        // what the tap does, said before it is tapped: this one
                        // writes read state across every source of this series
                        message: "Mark chapters up to \(entry.progress) as read here",
                        systemImage: "icloud.and.arrow.down",
                        // brand, matching the section banner: an offer is not a
                        // warning, and the two amber notices on this screen are
                        // both things that went wrong
                        tone: .brand,
                        action: { confirming = .pull(entry.progress) }
                    )
                } else {
                    Banner(
                        "You are at chapter \(localProgress) here",
                        // and this one writes to a public list
                        message: "Update \(tracker.name) to match",
                        systemImage: "icloud.and.arrow.up",
                        tone: .brand,
                        action: { confirming = .push(localProgress) }
                    )
                }
            }
            .transition(.scale(scale: 0.94, anchor: .top).combined(with: .opacity))
        }
    }

    // MARK: Editor

    // status, chapters read and score - the three things a reader changes by
    // hand, in one place rather than a second sheet behind this one. staged:
    // every control writes to the draft and only the commit reaches the service,
    // because a stray tap here lands on a public profile
    @ViewBuilder
    private var Editor: some View {
        if phase != .pending {
            VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                SectionHeader("Edit")

                Disagreement

                VStack(spacing: 0) {
                    StatusRow
                    Divider().padding(.leading, dimensions.spacing.space12)
                    ProgressRow
                    Divider().padding(.leading, dimensions.spacing.space12)
                    ScoreRow
                }
                .background(
                    .primary.opacity(Layout.fillOpacity),
                    in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
                )

                Save
            }
            .animation(.settle, value: changed)
            .animation(.settle, value: saving)
        }
    }

    // our own five, never the wire's vocabulary - CURRENT and plan_to_read stay
    // on the wire where they belong
    private var StatusRow: some View {
        Menu {
            Picker("Status", selection: $status) {
                ForEach(Status.ordered, id: \.self) { value in
                    Label(value.label, systemImage: value.icon).tag(value)
                }
            }
        } label: {
            HStack {
                Text("Status")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Label(status.label, systemImage: status.icon)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(status.tint)
                    .contentTransition(.symbolEffect(.replace))
                    .animation(.settle, value: status)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(dimensions.spacing.space12)
            .frame(minHeight: dimensions.touchTarget)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    // a stepper rather than a field: the number moves by one almost every time,
    // and a keyboard over a sheet to type "43" is the wrong trade
    // the stepper is for drift and the field is for distance. holding + through
    // three hundred chapters is not a thing anyone will do, and it was the only
    // way to reach a number a reader already knows
    private var ProgressRow: some View {
        HStack(spacing: dimensions.spacing.space12) {
            Text("Chapters Read")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            ProgressControl
        }
        .padding(dimensions.spacing.space12)
        .frame(minHeight: dimensions.touchTarget)
    }

    // hand-built rather than a Stepper, because the value sits BETWEEN the two
    // buttons and a Stepper renders its pair as one unit with nothing to put
    // between them. what that costs is press-and-hold auto-repeat, which typing
    // replaces - and which was never going to carry three hundred chapters
    private var ProgressControl: some View {
        HStack(spacing: 0) {
            Step("minus") { progress = max(floor, progress - 1) }
                .disabled(progress <= floor)

            Divider().frame(height: dimensions.size.icon20)

            ProgressValue

            Divider().frame(height: dimensions.size.icon20)

            Step("plus") { progress = min(ceiling, progress + 1) }
                .disabled(progress >= ceiling)
        }
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius8, style: .continuous)
        )
        .animation(.settle, value: progress)
    }

    private func Step(_ glyph: String, action: @escaping () -> Void) -> some View {
        Image(systemName: glyph)
            .font(.subheadline)
            .fontWeight(.medium)
            .frame(width: dimensions.touchTarget, height: dimensions.touchTarget)
            .contentShape(.rect)
            .tappable(action: action)
            .accessibilityLabel(glyph == "plus" ? "Increase" : "Decrease")
    }

    // the middle segment is the value AND its context: the total is not editable
    // and is drawn as such, but it lives inside the tap target because splitting
    // them puts a number and the thing it is out of on opposite sides of a rule
    private var ProgressValue: some View {
        HStack(spacing: dimensions.spacing.space4) {
            Text("\(progress)")
                .font(.subheadline)
                .fontWeight(.medium)
                .contentTransition(.numericText())

            if let total = entry?.totalChapters, total > 0 {
                Text("of \(total)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, dimensions.spacing.space12)
        .frame(minHeight: dimensions.touchTarget)
        .contentShape(.rect)
        .tappable {
            draft = String(progress)
            typing = true
        }
        .accessibilityLabel("Chapters read")
        .accessibilityValue("\(progress)")
        .accessibilityHint("Enter a number")
    }

    // zero, not how far this app has you read. an explicit edit here is the ONE caller
    // allowed to lower a number - everything automatic carries a monotonic guard
    // precisely so that this can be the exception - and a floor at what this app
    // has read made the control unable to correct the mistake a reader would
    // most want to correct
    private var floor: Int { 0 }

    // flat rather than the entry's own total: a stated total is frequently wrong
    // or absent on an ongoing work, and a stepper that stops short of where the
    // reader knows they are is a worse failure than one that lets them overshoot
    private var ceiling: Int { Layout.progressCeiling }

    // the account's own scale, five shapes over one 0...100 number underneath -
    // which is what makes switching scale on the website a display change here
    // rather than a migration
    private var ScoreRow: some View {
        Menu {
            Picker("Score", selection: $score) {
                ForEach(scoreFormat.steps, id: \.self) { value in
                    Text(scoreFormat.label(for: value)).tag(value)
                }
            }
        } label: {
            HStack {
                Text("Score")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Text(scoreFormat.label(for: score))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(score > 0 ? Palette.textPrimary : Palette.muted)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(dimensions.spacing.space12)
            .frame(minHeight: dimensions.touchTarget)
            .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }

    // MARK: Synopsis

    @ViewBuilder
    private var Synopsis: some View {
        if let synopsis = subject.synopsis, !synopsis.isEmpty {
            VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                SectionHeader("Synopsis")

                // not truncated here. the list clipped it to two lines because
                // fifty rows had to fit; one entry has the room
                Text(synopsis)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Typing a number

    private var TypingAlert: some View {
        Group {
            TextField("Chapters read", text: $draft)
                .keyboardType(.numberPad)

            Button("Set") { apply() }
            Button("Cancel", role: .cancel) { typing = false }
        }
    }

    // clamped on the way in rather than while typing: a field that refuses the
    // second keystroke of "300" because 3 is out of range is unusable, so the
    // bounds are applied once, when the number is committed
    private func apply() {
        defer { typing = false }
        guard let value = Int(draft.filter(\.isNumber)) else { return }
        progress = min(max(value, floor), ceiling)
    }

    // MARK: Save

    // linked only. on the way IN to a link there is nothing to save yet - the
    // whole draft rides the one commit in the footer - so this is the control
    // that exists once the screen has stopped being about linking and started
    // being about editing.
    //
    // it slides out of the section it belongs to rather than living in the
    // chrome, because it saves THAT section and nothing else on the screen
    @ViewBuilder
    private var Save: some View {
        if linked, changed || saving != .idle {
            SaveLabel
                .lineLimit(1)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .frame(height: dimensions.size.controlL)
                .foregroundStyle(saveTint)
                .glassEffect(
                    .regular.interactive(),
                    in: .rect(cornerRadius: dimensions.radius.radius16, style: .continuous)
                )
                .contentShape(.rect)
                .tappable { commit() }
                .disabled(saving == .saving)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // one slot, four things to say, so the glyph replaces in place rather than
    // each state arriving as its own view. the spinner is a symbol for the same
    // reason: a ProgressView has no stroke for the outcome to draw out of
    @ViewBuilder
    private var SaveLabel: some View {
        switch saving {
        case .idle:
            Text("Save to \(tracker.name)")
        case .saving:
            Label("Saving", systemImage: "progress.indicator")
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: !reduceMotion)
        case .saved:
            Label("Saved", systemImage: "checkmark")
        case let .failed(reason):
            Label(reason, systemImage: "exclamationmark.triangle")
        }
    }

    // red, not amber. amber is the attention colour - something needs looking at
    // - where this is an action the reader took a second ago that did not happen.
    // the persistent SYNC FAILED badge on the series row stays amber for exactly
    // that reason: it is a status waiting to be noticed, not a failed tap
    private var saveTint: Color {
        switch saving {
        case .failed: Palette.dangerText
        case .saved: Palette.successText
        default: Palette.textPrimary
        }
    }

    private func commit() {
        guard saving != .saving else { return }

        Task {
            saving = .saving
            do {
                try await onCommit(subject, update)
                // the draft IS what the service now holds, so it becomes the
                // thing the next edit is measured against
                baseline = current
                saving = .saved
                // the control has said what happened; leaving it there would
                // make "Saved" a permanent claim about a draft that can move
                // again a second later
                try? await Task.sleep(for: .seconds(2))
                if saving == .saved { saving = .idle }
            } catch {
                saving = .failed(Failure(error, fallback: "Couldn't save").title)
            }
        }
    }

    // MARK: Facts

    private var Facts: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
            SectionHeader("Details")

            VStack(spacing: dimensions.spacing.space8) {
                if let year = subject.year {
                    Fact("Year", String(year))
                }

                Fact(
                    "Chapters",
                    subject.totalChapters.flatMap { $0 > 0 ? String($0) : nil } ?? "Still publishing"
                )

                if let format = subject.format {
                    Fact("Format", format)
                }

                // only once a link exists. on the way in, "Never" would be
                // stating the premise of the screen back at the reader
                if linked {
                    Fact("Last synced", synced)
                }

            }
        }
    }

    // two different nevers, and only one of them is information: a link whose
    // seeding never landed genuinely has not synced, and says so
    private var synced: String {
        guard let syncedDate, syncedDate > .distantPast else { return "Never" }
        return syncedDate.formatted(.relative(presentation: .named))
    }

    private func Fact(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .frame(minHeight: dimensions.touchTarget)
    }

    // MARK: Commit

    // the one action this screen exists for, at the bottom where a thumb is,
    // labelled with its outcome rather than "Done"
    private var Commit: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Primary
        }
        .padding(.horizontal, dimensions.screenMargin)
        .padding(.bottom, dimensions.spacing.space8)
    }

    // the same shape DetailsActions.Primary uses for Add to Library / In Library,
    // because this is the same kind of control: one button whose done state is a
    // resting state rather than a new offer.
    //
    // done INVERTS - the text colour becomes the fill and the canvas colour the
    // lettering - rather than taking an accent. an accent would say "this is the
    // interesting one", and synced is precisely the state that has stopped being
    // interesting. it was .glassProminent with no tint, which is the system
    // accent painting a flat slab over the glass
    @ViewBuilder
    private var Primary: some View {
        // a linked screen has nothing to put here: saving moved into the section
        // it saves, and unlink into Details. leaving a disabled "Save"
        // behind would be a second control for a job that already has one
        if !linked || committed {
            PrimaryLabel
                .lineLimit(1)
                .fontWeight(.medium)
                .contentTransition(.symbolEffect(.replace))
                .padding(.horizontal, dimensions.spacing.space8)
                .frame(maxWidth: .infinity)
                .frame(height: dimensions.size.controlL)
                .foregroundStyle(
                    committed
                        ? AnyShapeStyle(Palette.canvas)
                        : AnyShapeStyle(saveTint)
                )
                .glassEffect(
                    committed
                        ? .regular.tint(Palette.textPrimary).interactive()
                        : .regular.tint(Palette.brand).interactive(),
                    in: .rect(cornerRadius: dimensions.radius.radius16, style: .continuous)
                )
                .tappable {
                    if committed {
                        // the same button, now the way out of what it created
                        unlinking = true
                    } else {
                        link()
                    }
                }
                .disabled(saving == .saving)
                .animation(.settle, value: committed)
                .animation(.settle, value: saving)
                .sensoryFeedback(.success, trigger: committed)
        }
    }

    // the same four things the Save control says, in the same order, because
    // linking is a write like any other - it just ends somewhere Save does not,
    // at a state that stays rather than fading back to idle
    @ViewBuilder
    private var PrimaryLabel: some View {
        if committed {
            Label("Synced", systemImage: "checkmark")
        } else {
            switch saving {
            case .saving:
                Label("Linking", systemImage: "progress.indicator")
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: !reduceMotion)
            case let .failed(reason):
                Label(reason, systemImage: "exclamationmark.triangle")
            default:
                Text("Link to \(tracker.name)")
            }
        }
    }

    // the link half of commit(). it reports the same way and differs at the end:
    // a save says "Saved" and goes quiet, a link becomes the thing it created
    // and stays. the error was swallowed with try? before, so a link that failed
    // reported itself as Synced
    private func link() {
        guard saving != .saving else { return }

        Task {
            saving = .saving

            do {
                try await onCommit(subject, update)
                baseline = current
                saving = .idle
                committed = true
            } catch {
                saving = .failed(Failure(error, fallback: "Couldn't link").title)
            }
        }
    }

    // nothing to save is not a thing to offer saving, so a manage screen sits
    // disabled until something moves. a link has always got something to write
    private var changed: Bool {
        guard let baseline else { return false }
        return current != baseline
    }

    // sparse: only what the reader actually moved. an omitted field is preserved
    // on both services, and a blind full-object write is what resets statuses and
    // moves list positions on services that have no idea you did not mean to
    private var update: TrackerUpdate {
        var patch = TrackerUpdate(remoteId: subject.id, entryId: entry?.entryId)
        guard let entry else {
            patch.progress = progress
            patch.status = status
            patch.score = score > 0 ? score : nil
            return patch
        }

        if progress != entry.progress { patch.progress = progress }
        if status != entry.status { patch.status = status }
        if score != (entry.score ?? 0) { patch.score = score }
        return patch
    }

    private func tone(for publication: Publication) -> Palette.Tone {
        switch publication {
        case .Ongoing: .success
        case .Completed: .brand
        case .Hiatus: .warning
        case .Cancelled: .danger
        case .Unknown: .neutral
        }
    }

    // seeding moves all three controls, and that is not the reader editing - it
    // is the screen arriving. the flag has to survive that or every entry would
    // open already claiming unsent work
    private func touched() {
        guard seeded else { return }
        committed = false
    }

    private func load() async {
        do {
            let remote = try await onLoad()
            entry = remote
            seed(from: remote)
            phase = .content
        } catch {
            failure = Failure(error, fallback: "Couldn't Check Your List")
            // the draft still has to exist: the reader can link without us having
            // read their entry, and the push re-reads it before writing anyway
            seed(from: nil)
            phase = .failed
        }
    }

    // seeded once, from whichever side is further along - which is the same rule
    // the push itself applies, so the controls open showing what would happen if
    // the reader changed nothing
    private func seed(from remote: TrackerEntry?) {
        guard !seeded else { return }
        seeded = true

        progress = max(remote?.progress ?? 0, localProgress)
        score = remote?.score ?? 0
        // an entry the service does not hold yet opens on what linking would
        // actually write. progress is how far this app has you read rather than zero,
        // because that is what the push sends whatever this control shows - and
        // a series with nothing read is want-to-read rather than reading, which
        // is the one part of the default that was asserting something untrue
        status = remote?.status ?? (localProgress > 0 ? .reading : .planning)
        baseline = current
    }
}

// MARK: - Previews

private struct CandidatePreview: View {
    // a real cover, unlike the search list's specimens: the backdrop IS what
    // these previews are for, and it has nothing to blur or dim without one
    static let cover = URL(string: "https://s4.anilist.co/file/anilistcdn/media/manga/cover/large/bx159655-Kv58QINz1rXm.jpg")

    var tracker: Tracker = .anilist
    var candidate: TrackerCandidate = .init(
        id: 101177,
        title: "Kanojo mo Kanojo",
        cover: CandidatePreview.cover,
        year: 2020,
        totalChapters: 122,
        status: .Completed,
        authors: "Hiroyuki",
        synopsis: "Naoya Mukai has been in love with his childhood friend Saki for years, and when she finally accepts his confession he could not be happier. Then Nagisa Minase confesses to him too, and rather than turn her down he proposes something no one asked for: that he date them both, honestly and in the open."
    )
    var localProgress = 42
    var conflict: String?
    var entry: TrackerEntry? = .init(
        remoteId: 101177,
        title: "Kanojo mo Kanojo",
        totalChapters: 122,
        entryId: 900,
        status: .reading,
        progress: 38,
        score: 80
    )
    var stalls = false
    // how the commit behaves, so the save control's three outcomes are all
    // reachable without a network
    var commitDelay: Duration = .seconds(1)
    var commitFails = false
    var linked = false
    var syncedDate: Date? = .now.addingTimeInterval(-7200)

    // spelled out rather than inlined: a ternary between a closure and nil gives
    // the type checker nothing to infer the closure's shape from
    private var unlink: ((Bool) -> Void)? {
        linked ? { _ in } : nil
    }

    // presented the way the app presents it rather than rendered bare: this
    // screen is always inside a sheet, either as that sheet's root when reached
    // from a linked row or pushed into the link sheet's stack when reached from
    // a search result. rendering it flat hid the two things the sheet decides -
    // how the large detent crops the backdrop, and where the commit sits once
    // the drag indicator and the home affordance have taken their room
    var body: some View {
        Palette.canvas
            .ignoresSafeArea()
            .sheet(isPresented: .constant(true)) { Sheet }
    }

    private var Sheet: some View {
        NavigationStack {
            DetailsTrackerCandidate(
                tracker: tracker,
                candidate: candidate,
                localProgress: localProgress,
                conflict: conflict,
                scoreFormat: .point10,
                linked: linked,
                syncedDate: syncedDate,
                onLoad: {
                    if stalls { try await Task.sleep(for: .seconds(30)) }
                    guard let entry else { throw TrackerError.throttled(retryAfter: 60) }
                    return entry
                },
                onCommit: { _, _ in
                    try await Task.sleep(for: commitDelay)
                    if commitFails { throw TrackerError.unavailable }
                },
                onUnlink: unlink,
                onCatchUp: { _ in },
                onPushLocal: {},
                onClose: {}
            )
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: Linking - reached from a search result, nothing committed yet
//
// the screen is the same one both ways round, so the previews are grouped by
// which door was used rather than by which control happens to be on screen.
// linking is the half where the commit says Link, there is no unlink, and the
// Last synced row is absent because nothing has

// the ordinary case: an entry this reader does not have on their list. no
// comparison to draw and no sync control, because there is nothing to compare
#Preview("Linking · not on your list") {
    CandidatePreview(
        entry: .init(remoteId: 101177, title: "Kanojo mo Kanojo", totalChapters: 122)
    )
}

// already on their list and ahead of this app - the sync control appears BEFORE
// anything is linked, which is the case that decides whether linking is safe
#Preview("Linking · already on your list") {
    CandidatePreview(
        localProgress: 12,
        entry: .init(
            remoteId: 101177,
            title: "Kanojo mo Kanojo",
            totalChapters: 122,
            entryId: 900,
            status: .reading,
            progress: 60,
            score: nil
        )
    )
}

// the same entry is already linked to a different series in the library. the
// commit stays available - the reader may genuinely be fixing the other one
#Preview("Linking · claimed by another series") {
    CandidatePreview(conflict: "Girlfriend, Girlfriend")
}

// MARK: Managing - reached from a linked row, and the commit saves

// in step, which is what most linked series look like most of the time: no sync
// control, because there is nothing to reconcile
#Preview("Managing · in step") {
    CandidatePreview(
        localProgress: 38,
        entry: .init(
            remoteId: 101177,
            title: "Kanojo mo Kanojo",
            totalChapters: 122,
            entryId: 900,
            status: .reading,
            progress: 38
        ),
        linked: true
    )
}

// the service has heard more than this app has - the control pulls, and taking
// it marks chapters read locally
#Preview("Managing · service is ahead") {
    CandidatePreview(
        localProgress: 12,
        entry: .init(
            remoteId: 101177,
            title: "Kanojo mo Kanojo",
            totalChapters: 122,
            entryId: 900,
            status: .reading,
            progress: 60,
            score: nil
        ),
        linked: true
    )
}

// and the other direction, where taking it tells EVERY linked service rather
// than only this one
#Preview("Managing · you are ahead") {
    CandidatePreview(
        localProgress: 60,
        entry: .init(
            remoteId: 101177,
            title: "Kanojo mo Kanojo",
            totalChapters: 122,
            entryId: 900,
            status: .reading,
            progress: 38,
            score: 80
        ),
        linked: true
    )
}

// linked, but the seeding never landed - the one case where Never is a fact
// rather than a restatement of the screen's premise
#Preview("Managing · never synced") {
    CandidatePreview(linked: true, syncedDate: nil)
}

// an entry the service already calls finished. automatic pushes skip it
// entirely, so an explicit edit here is the only thing that can still write
#Preview("Managing · finished on the service") {
    CandidatePreview(
        localProgress: 122,
        entry: .init(
            remoteId: 101177,
            title: "Kanojo mo Kanojo",
            totalChapters: 122,
            entryId: 900,
            status: .completed,
            progress: 122,
            score: 90
        ),
        linked: true
    )
}

// MARK: The inline save
//
// linked only, and it slides out of the Edit section the moment the draft moves.
// move any control and watch it appear; these three cover what happens after it
// is tapped, which is the part a static preview cannot show

// a one-second write, so the spinner is actually visible before the tick
#Preview("Save · succeeds") {
    CandidatePreview(linked: true)
}

// slow enough to sit in the saving state and watch the rotate
#Preview("Save · slow") {
    CandidatePreview(commitDelay: .seconds(6), linked: true)
}

// the failure keeps the draft: nothing is discarded, and the reason replaces the
// label rather than raising an alert over the control that caused it
#Preview("Save · fails") {
    CandidatePreview(commitFails: true, linked: true)
}

// MARK: Shapes the metadata can take

// no year, no format, and a work with no stated total - every optional row in
// the Details section absent at once, which is what a thin entry looks like
#Preview("Sparse metadata") {
    CandidatePreview(
        candidate: .init(
            id: 101177,
            title: "A Series With Very Little Recorded About It At All",
            cover: CandidatePreview.cover,
            authors: "Unknown"
        ),
        entry: .init(remoteId: 101177, title: "A Series With Very Little Recorded About It At All"),
        linked: true
    )
}

// MARK: Load states

// the entry is still being fetched: the comparison cannot be drawn yet, and the
// commit must not be offered against numbers nobody has seen. the Last synced
// row still answers, because it comes off the stored row rather than the fetch
#Preview("Loading the entry") {
    CandidatePreview(stalls: true, linked: true)
}

// and the same screen when that fetch fails. the draft is still editable, which
// is deliberate - the push re-reads before it writes, so a failed read here does
// not make the reader's answer unusable
#Preview("Entry wouldn't load") {
    CandidatePreview(entry: nil, linked: true)
}

// MARK: Service

#Preview("MyAnimeList") {
    CandidatePreview(tracker: .myAnimeList, linked: true)
}
