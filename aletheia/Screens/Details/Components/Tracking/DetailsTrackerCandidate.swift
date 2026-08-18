//
//  DetailsTrackerCandidate.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import Kingfisher
import SwiftUI

struct DetailsTrackerCandidate: View {
    let tracker: Tracker
    let candidate: TrackerCandidate
    let localProgress: Int
    let conflict: String?
    let scoreFormat: ScoreFormat
    var linked: Bool = false
    // off inside the add-to-library flow - local progress there is zero by
    // construction, so the disagreement banner would fire on every link
    // saying the same expected thing rather than reporting a real conflict
    var reconciles: Bool = true
    // read from the link row, not from the entry this screen fetches, so it
    // still answers while that fetch is running and when it fails. nil on
    // the way IN to a link, where nothing could have synced yet
    var syncedDate: Date?
    var onLoad: () async throws -> TrackerEntry
    var onCommit: (TrackerCandidate, TrackerUpdate) async throws -> Void
    var onUnlink: ((Bool) -> Void)?
    var onCatchUp: ((Int) -> Void)?
    // pushes to every linked service, not just this one - they are all
    // behind the same local read state
    var onPushLocal: (() -> Void)?
    // caller-owned because @Environment(\.dismiss) means "pop" on a pushed
    // copy of this view and "close the sheet" on a root one, and this has
    // to mean the second thing in both places
    var onClose: (() -> Void)?

    @Environment(\.dimensions) private var dimensions
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var entry: TrackerEntry?
    @State private var phase: LoadPhase = .pending
    @State private var failure: Failure?

    // its own reference type so only the backdrop observes it - held beside
    // the scroll view, every update would re-evaluate a body holding the
    // whole screen
    @State private var scroll = DetailsScroll()

    @State private var status: Status = .reading
    @State private var progress = 0
    @State private var score = 0
    @State private var seeded = false
    @State private var unlinking = false
    @State private var confirming: TrackerReconcile?
    @State private var committed = false
    // captured at seed time, not diffed against the fetched entry - seeding
    // also runs on the failure path, so a reader whose entry would not load
    // can still edit and still save
    @State private var baseline: Draft?

    private struct Draft: Equatable {
        var status: Status
        var progress: Int
        var score: Int
    }

    private var current: Draft {
        .init(status: status, progress: progress, score: score)
    }
    @State private var saving: SaveState = .idle
    // an alert, not an inline field - the row sits mid-height on a
    // large-detent sheet, and a number pad would cover both the row being
    // edited and the commit button below it
    @State private var typing = false
    @State private var draft = ""

    private enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    private enum Layout {
        static let fadeStart: CGFloat = 0.20
        static let fadeEnd: CGFloat = 0.75
        static let progressCeiling = 9999
        static let coverWidth: CGFloat = 120
        static let coverAspect: CGFloat = 11 / 16
        static let placeholderOpacity: Double = 0.1
        static let fillOpacity: Double = 0.05
        static let barHeight: CGFloat = 6
        static let trackOpacity: Double = 0.15
        static let tickWidth: CGFloat = 3
        static let washOpacity: Double = 0.25
        static let markSize: CGFloat = 18
        static let markDrop: CGFloat = 4
    }

    // a linked row can only seed an id, a title and a total - without this
    // overlay the artwork never arrives, since the fetch that carries it
    // lands in `entry` and nothing else reads it
    private var subject: TrackerCandidate {
        guard let entry else { return candidate }
        let remote = entry.candidate

        // every fallback below reads the seed (`candidate`), never `subject` -
        // this is the getter that produces `subject`, so referencing it here
        // is unbounded recursion
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
            // clamped inside the transform, not the action - the callback only
            // fires when its returned value changes, so clamping the value
            // itself is what stops updates past the ramp, not a check in action
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
            if let onClose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "chevron.down", action: onClose)
                        .labelStyle(.iconOnly)
                }
            }
        }
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
            Text(
                "Unlinking stops syncing and leaves your \(tracker.name) entry as it is. Deleting removes it from your list entirely, along with its score and dates. That can't be undone."
            )
        }
        .trackerReconcile(
            $confirming,
            subject: tracker.name,
            onCatchUp: { onCatchUp?($0) },
            onPushLocal: { onPushLocal?() }
        )
        .safeAreaInset(edge: .bottom) { Commit }
        // touching a control after a save has to clear `committed`, or the
        // button stays showing "Synced" - the next tap would unlink instead
        // of sending the change, with no way to save but closing and reopening
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

                    // personalhotspot.slash (interlocking rings, slashed) - the
                    // link family has no slash or badge.minus variant, checked
                    // against the SDK's own catalog rather than guessed; a
                    // symbol that does not exist renders as nothing at all
                    if unlinkable {
                        Image(systemName: "personalhotspot.slash")
                            .foregroundStyle(Palette.dangerText)
                            .modifier(
                                Control(
                                    tint: Palette.danger.opacity(Layout.washOpacity), circular: true
                                )
                            )
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
        var circular = false

        @Environment(\.dimensions) private var dimensions

        @ViewBuilder
        func body(content: Content) -> some View {
            let sized =
                content
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, circular ? 0 : dimensions.spacing.space12)
                .frame(
                    width: circular ? dimensions.size.controlL : nil,
                    height: dimensions.size.controlL
                )

            // branched rather than type-erased - InsettableShape has no
            // common existential to hold .rect and .circle here
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

    @ViewBuilder
    private var Trouble: some View {
        // title and message both go to their own slot - this used to read
        // .message alone, which rendered blank for any error that states
        // only a title
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
                    Divider()

                    Label("In step", systemImage: "checkmark")
                        .font(.footnote)
                        .fontWeight(.medium)
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                    Text("Not on your \(tracker.name) list yet.")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)

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

    // `leading` means further along, not "correct" - when the two agree both
    // are passed true, so neither dims
    private func Side<Icon: View>(
        _ name: String,
        @ViewBuilder icon: () -> Icon,
        value: Int,
        of total: Int?,
        leading: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            HStack(alignment: .firstTextBaseline, spacing: dimensions.spacing.space8) {
                icon()
                    .frame(width: Layout.markSize, height: Layout.markSize)
                    .clipShape(.circle)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - Layout.markDrop }

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
                // monospaced or the numericText roll shifts every character
                // beside it each time the count crosses a digit width
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.settle, value: value)
            }

            Bar(value: value, of: total, leading: leading)
        }
    }

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

    @ViewBuilder
    private var Disagreement: some View {
        if reconciles, let entry, entry.isListed, entry.progress != localProgress {
            let remoteAhead = entry.progress > localProgress

            Group {
                if remoteAhead {
                    Banner(
                        "\(tracker.name) is at chapter \(entry.progress)",
                        // marks chapters read across every source of this
                        // series, not just this tracker's view of it
                        message: "Mark chapters up to \(entry.progress) as read here",
                        systemImage: "icloud.and.arrow.down",
                        tone: .brand,
                        action: { confirming = .pull(entry.progress) }
                    )
                } else {
                    Banner(
                        "You are at chapter \(localProgress) here",
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

    // hand-built, not a Stepper - Stepper renders its two buttons as one
    // unit with nothing insertable between them, and the value has to sit
    // between the minus and the plus here
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

    // zero, not localProgress - everywhere else progress carries a monotonic
    // guard, but an explicit edit here is the one place allowed to lower the
    // number, since that is precisely the mistake a reader would want to fix
    private var floor: Int { 0 }

    // flat, not the entry's own total - a stated total is frequently wrong or
    // absent on an ongoing work, and stopping short of where the reader knows
    // they are is worse than letting them overshoot
    private var ceiling: Int { Layout.progressCeiling }

    // score is always stored 0...100 - the account's chosen scale is a
    // display format over that number, not a different unit
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

    // clamped on the way in, not while typing - validating each keystroke
    // against the range would refuse the second digit of "300" for landing
    // out of bounds, so the clamp applies once, on commit
    private func apply() {
        defer { typing = false }
        guard let value = Int(draft.filter(\.isNumber)) else { return }
        progress = min(max(value, floor), ceiling)
    }

    // MARK: Save

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
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle")
        }
    }

    // red, not amber - this is an action the reader took a second ago that
    // did not happen, unlike the persistent SYNC FAILED badge on the series
    // row, which stays amber because it is a status waiting to be noticed,
    // not a failed tap
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
                baseline = current
                saving = .saved
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
                    subject.totalChapters.flatMap { $0 > 0 ? String($0) : nil }
                        ?? "Still publishing"
                )

                if let format = subject.format {
                    Fact("Format", format)
                }

                if linked {
                    Fact("Last synced", synced)
                }

            }
        }
    }

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

    private var Commit: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Primary
        }
        .padding(.horizontal, dimensions.screenMargin)
        .padding(.bottom, dimensions.spacing.space8)
    }

    // done inverts (text colour becomes the fill, canvas colour the
    // lettering) rather than taking an accent - it was .glassProminent with
    // no tint before, which was just the system accent painting a flat slab
    // over the glass
    @ViewBuilder
    private var Primary: some View {
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

    @ViewBuilder
    private var PrimaryLabel: some View {
        if committed {
            Label("Synced", systemImage: "checkmark")
        } else {
            switch saving {
            case .saving:
                Label("Linking", systemImage: "progress.indicator")
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: !reduceMotion)
            case .failed(let reason):
                Label(reason, systemImage: "exclamationmark.triangle")
            default:
                Text("Link to \(tracker.name)")
            }
        }
    }

    // the error used to be swallowed with try?, so a link that failed still
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

    private var changed: Bool {
        guard let baseline else { return false }
        return current != baseline
    }

    // sparse - only what the reader actually moved. an omitted field is
    // preserved on the service, where a blind full-object write can reset
    // statuses and move list positions the reader never touched
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

    // guarded on `seeded`, or seeding the three controls on arrival would
    // itself count as the reader editing, and every entry would open
    // already claiming unsent work
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
            seed(from: nil)
            phase = .failed
        }
    }

    private func seed(from remote: TrackerEntry?) {
        guard !seeded else { return }
        seeded = true

        progress = max(remote?.progress ?? 0, localProgress)
        score = remote?.score ?? 0
        // defaulting an unlisted entry to .reading would be wrong for a
        // series with nothing read yet - .planning is the honest default
        status = remote?.status ?? (localProgress > 0 ? .reading : .planning)
        baseline = current
    }
}

// MARK: - Previews

private struct CandidatePreview: View {
    static let cover = URL(
        string:
            "https://s4.anilist.co/file/anilistcdn/media/manga/cover/large/bx159655-Kv58QINz1rXm.jpg"
    )

    var tracker: Tracker = .anilist
    var candidate: TrackerCandidate = .init(
        id: 101177,
        title: "Kanojo mo Kanojo",
        cover: CandidatePreview.cover,
        year: 2020,
        totalChapters: 122,
        status: .Completed,
        authors: "Hiroyuki",
        synopsis:
            "Naoya Mukai has been in love with his childhood friend Saki for years, and when she finally accepts his confession he could not be happier. Then Nagisa Minase confesses to him too, and rather than turn her down he proposes something no one asked for: that he date them both, honestly and in the open."
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
    var commitDelay: Duration = .seconds(1)
    var commitFails = false
    var linked = false
    var syncedDate: Date? = .now.addingTimeInterval(-7200)

    private var unlink: ((Bool) -> Void)? {
        linked ? { _ in } : nil
    }

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

#Preview("Linking · not on your list") {
    CandidatePreview(
        entry: .init(remoteId: 101177, title: "Kanojo mo Kanojo", totalChapters: 122)
    )
}

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

#Preview("Linking · claimed by another series") {
    CandidatePreview(conflict: "Girlfriend, Girlfriend")
}

// MARK: Managing - reached from a linked row, and the commit saves

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

#Preview("Managing · never synced") {
    CandidatePreview(linked: true, syncedDate: nil)
}

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

#Preview("Save · succeeds") {
    CandidatePreview(linked: true)
}

#Preview("Save · slow") {
    CandidatePreview(commitDelay: .seconds(6), linked: true)
}

#Preview("Save · fails") {
    CandidatePreview(commitFails: true, linked: true)
}

// MARK: Shapes the metadata can take

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

#Preview("Loading the entry") {
    CandidatePreview(stalls: true, linked: true)
}

#Preview("Entry wouldn't load") {
    CandidatePreview(entry: nil, linked: true)
}

// MARK: Service

#Preview("MyAnimeList") {
    CandidatePreview(tracker: .myAnimeList, linked: true)
}
