//
//  FailuresScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import SwiftUI
import Kingfisher
import Tagged

// which series could not be checked, on which source, and why. reached from the
// Now section's count row - the count is the awareness, this is the attribution
// and the retry. rows leave on their own when a source answers again; there is
// nothing here to dismiss, because the state is a column rather than an inbox
struct FailuresScreen: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions

    @State private var vm: FailuresViewModel?
    @State private var route: SeriesEntry?

    // session state rather than a stored preference: it is how you are looking
    // at this list right now, not a setting about the app
    @State private var grouping: FailuresViewModel.Grouping = .source

    private enum Layout {
        static let fillOpacity = 0.05
        static let iconSize: CGFloat = 36
        static let headerIconSize: CGFloat = 24
        static let coverAspect: CGFloat = 11 / 16
        // the card's leading edge, so it is a width and the content sets the
        // height. wider than the artwork's own ratio at this height, so it
        // crops rather than letterboxes - the reason line still gets the room
        // it needs on the right
        static let coverWidth: CGFloat = 96
        static let headerCoverHeight: CGFloat = 24
        static let placeholderOpacity = 0.1
    }

    private var phase: LoadPhase {
        if let vm {
            if vm.failure != nil { .failed }
            else if vm.entries == nil { .pending }
            else if vm.isEmpty { .empty }
            else { .content }
        } else {
            .pending
        }
    }

    var body: some View {
        ZStack {
            switch phase {
            case .content:
                if let vm { List(vm) .transition(.opacity) }
            case .empty:
                Recovered.transition(.opacity)
            case .failed:
                if let vm, let failure = vm.failure {
                    Unavailable(failure).transition(.opacity)
                }
            default:
                ProgressView().transition(.opacity)
            }
        }
        .animation(.settle, value: phase)
        // not "Failing Sources" any more: a tracker that cannot sync is the same
        // kind of fact about a different party, and it lands on this screen too
        .navigationTitle("Failures")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $route) { DetailsScreen(entry: $0) }
        .task {
            guard vm == nil else { return }
            let model = FailuresViewModel(
                database: compositor.database,
                registry: compositor.registry,
                refresher: compositor.refresh,
                trackers: compositor.trackers
            )
            vm = model
            model.observe()
        }
    }
}

// MARK: - Content

private extension FailuresScreen {
    func List(_ vm: FailuresViewModel) -> some View {
        // the control sits outside the scroll: it scopes everything below it,
        // so scrolling it away would leave the list in a state with nothing on
        // screen saying which
        VStack(spacing: 0) {
            // one failure groups the same way twice, so the control would be an
            // affordance that cannot change anything. it scopes the source list
            // only, so it goes with the source list rather than the screen
            if (vm.entries?.count ?? 0) > 1 {
                GroupingControl
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                    ForEach(vm.sections(by: grouping)) { section in
                        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                            Header(section, vm: vm)

                            ForEach(section.entries) { entry in
                                Row(entry, vm: vm)
                            }
                        }
                    }

                    // second, because a source that cannot be read is the bigger
                    // problem: it costs you chapters, where a tracker that cannot
                    // sync costs you a number on someone else's website
                    if let links = vm.links, !links.isEmpty {
                        VStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                            TrackingHeader(links.count)

                            ForEach(links) { entry in
                                TrackingRow(entry, vm: vm)
                            }
                        }
                    }
                }
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.vertical, dimensions.spacing.space16)
            }
        }
        .animation(.settle, value: grouping)
    }

    var GroupingControl: some View {
        Picker("Group by", selection: $grouping) {
            ForEach(FailuresViewModel.Grouping.allCases) { option in
                Text(option.label).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, dimensions.screenMargin)
        .padding(.vertical, dimensions.spacing.space8)
    }

    // the count is the blast radius, and it is what makes the two groupings
    // worth switching between: six series behind one source is a different
    // problem from six sources behind one series
    // grouped by series the header is the only thing worth navigating to, so it
    // carries the tap and the chevron and the rows below it carry neither -
    // three chevrons pointing at one destination is three promises of somewhere
    // different to go
    @ViewBuilder
    func Header(_ section: FailuresViewModel.Section, vm: FailuresViewModel) -> some View {
        if grouping == .series, let entry = section.entries.first {
            HeaderContent(section, vm: vm)
                .contentShape(.rect)
                .tappable { route = SeriesEntry.library(SeriesRecord.ID(rawValue: entry.seriesId)) }
                .accessibilityHint("Opens the series")
        } else {
            HeaderContent(section, vm: vm)
        }
    }

    func HeaderContent(_ section: FailuresViewModel.Section, vm: FailuresViewModel) -> some View {
        HStack(spacing: dimensions.spacing.space8) {
            // combined into one VoiceOver label - but scoped to only this
            // decorative half, not the whole header, because RetryAllButton
            // sits beside it and a Button folded into
            // .accessibilityElement(children: .combine) loses its own action
            HStack(spacing: dimensions.spacing.space8) {
                // a source section shows the source's mark; a series section
                // shows the series' cover, which is the fastest way anyone
                // recognises one
                if let slug = section.sourceSlug {
                    if let icon = compositor.registry.source(slug: slug)?.descriptor.icon {
                        Image(icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: Layout.headerIconSize, height: Layout.headerIconSize)
                            .clipShape(.rect(cornerRadius: dimensions.radius.radius4))
                    }
                } else if let entry = section.entries.first {
                    HeaderCover(entry)
                }

                Text(section.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Count(section)
            }
            .accessibilityElement(children: .combine)

            // one row's own Retry already covers a section of one - this is
            // for the case that made grouping worth having in the first
            // place, six series behind one dead source or six sources behind
            // one missing series
            if section.count > 1 {
                RetryAllButton(section, vm: vm)
            }

            if grouping == .series {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: dimensions.touchTarget)
    }

    // its own tap target, same reason Retry is a Button inside RowCard's own
    // tappable card rather than layered over it - grouped by series the
    // whole header already navigates, and this must win against that rather
    // than trigger it
    @ViewBuilder
    func RetryAllButton(_ section: FailuresViewModel.Section, vm: FailuresViewModel) -> some View {
        let retrying = section.entries.contains { vm.retrying.contains($0.id) }

        if retrying {
            ProgressView()
                .controlSize(.small)
        } else {
            Text("Retry All")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.brand)
                .padding(.horizontal, dimensions.spacing.space12)
                .padding(.vertical, dimensions.spacing.space4)
                .background(.brand.opacity(0.1), in: .capsule)
                .tappable { Task { await vm.retryAll(section.entries) } }
                .accessibilityLabel("Retry all \(section.count) failures")
        }
    }

    @ViewBuilder
    func Count(_ section: FailuresViewModel.Section) -> some View {
        // each branch keeps its own literal, or the inflection markup is erased
        if grouping == .source {
            Text("^[\(section.count) series](inflect: true)")
                .font(.caption)
                .foregroundStyle(.muted)
        } else {
            Text("^[\(section.count) source](inflect: true)")
                .font(.caption)
                .foregroundStyle(.muted)
        }
    }

    // a failure is always a pair - this series, on this source - and the header
    // already names one half, so the row names the other. repeating the header's
    // half in every row underneath it is the noise that made the flat list hard
    // to read once more than one thing was broken
    @ViewBuilder
    func Row(_ entry: FailuresViewModel.Entry, vm: FailuresViewModel) -> some View {
        if grouping == .source {
            RowCard(entry, vm: vm)
                .contentShape(.rect)
                // the row navigates, the retry acts. a card carrying both needs
                // the button to win its own hit area, which is why Retry is a
                // Button rather than something layered over a tappable card
                .tappable { route = SeriesEntry.library(SeriesRecord.ID(rawValue: entry.seriesId)) }
        } else {
            // the series header above already went there. what is left on this
            // card is the one thing it alone can do, which is try again
            RowCard(entry, vm: vm)
        }
    }

    func RowCard(_ entry: FailuresViewModel.Entry, vm: FailuresViewModel) -> some View {
        HStack(spacing: 0) {
            // the artwork is the card's leading edge rather than an inset
            // thumbnail: it sets the card's height and gives the failure
            // something recognisable to hang on. under a series header the row
            // is a source, and its mark stays an icon - the header already
            // carries that series' cover
            if grouping == .source {
                Cover(entry)
            }

            VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                HStack(spacing: dimensions.spacing.space12) {
                    if grouping == .series {
                        Icon(entry)
                    }

                    Text(grouping == .source ? entry.title : entry.sourceName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // an indicator, not the target - the whole card is the
                    // target, which is what a chevron has always promised. it
                    // is absent grouped by series, where the card goes nowhere
                    if grouping == .source {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(entry.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    // live rather than formatted once: this screen is what a
                    // reader keeps open while retrying, and a stamp that says
                    // "1m ago" for the whole visit is the one thing here that
                    // would make a retry look like it never happened
                    HStack(spacing: dimensions.spacing.space4) {
                        Text("Last tried")
                        LiveRelativeText(date: entry.attemptedDate)
                    }
                    .font(.caption2)
                    .foregroundStyle(.muted)

                    Spacer(minLength: 0)

                    Retry(entry, vm: vm)
                }
            }
            .padding(dimensions.spacing.space12)
        }
        // clipped before the glass, or the artwork sits square over the card's
        // rounded corners - glassEffect shapes what it draws behind, not what
        // the card contains
        .clipShape(.rect(cornerRadius: dimensions.radius.radius12, style: .continuous))
        // interactive only where the card actually goes somewhere. grouped by
        // series it goes nowhere - the header did that - so it must not squish
        // under a press either, or it is still promising a tap it will not
        // honour. the one control on it is Retry, which responds for itself
        .glassEffect(
            grouping == .source ? .regular.interactive() : .regular,
            in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
    }

    // the stored file where the cover was downloaded, else the remote one -
    // the same resolution every other rail in the app uses. fixed width and an
    // unbounded height so the text column decides how tall the card is and the
    // artwork fills whatever that turns out to be
    func Cover(_ entry: FailuresViewModel.Entry) -> some View {
        let local = compositor.assets.local(for: entry.path)

        return Color.clear
            .frame(width: Layout.coverWidth)
            .frame(maxHeight: .infinity)
            .overlay {
                if let cover = local ?? entry.cover {
                    KFImage(cover)
                        .resizable()
                        .placeholder { Rectangle().fill(.primary.opacity(Layout.placeholderOpacity)).shimmer() }
                        .fade(duration: 0.25)
                        .scaledToFill()
                } else {
                    Rectangle().fill(.primary.opacity(Layout.placeholderOpacity))
                }
            }
            .clipped()
    }

    // the header's cover keeps a shape of its own: it sits inline beside a
    // title rather than against the card's edge
    func HeaderCover(_ entry: FailuresViewModel.Entry) -> some View {
        let local = compositor.assets.local(for: entry.path)

        return Color.clear
            .aspectRatio(Layout.coverAspect, contentMode: .fit)
            .frame(height: Layout.headerCoverHeight)
            .overlay {
                if let cover = local ?? entry.cover {
                    KFImage(cover)
                        .resizable()
                        .placeholder { Rectangle().fill(.primary.opacity(Layout.placeholderOpacity)).shimmer() }
                        .fade(duration: 0.25)
                        .scaledToFill()
                } else {
                    Rectangle().fill(.primary.opacity(Layout.placeholderOpacity))
                }
            }
            .clipShape(.rect(cornerRadius: dimensions.radius.radius4))
    }

    @ViewBuilder
    func Icon(_ entry: FailuresViewModel.Entry) -> some View {
        if let icon = compositor.registry.source(slug: entry.sourceSlug)?.descriptor.icon {
            Image(icon)
                .resizable()
                .scaledToFit()
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius8))
        } else {
            Image(systemName: "questionmark")
                .font(.footnote)
                .foregroundStyle(.muted)
                .frame(width: Layout.iconSize, height: Layout.iconSize)
                .background(.primary.opacity(Layout.fillOpacity), in: .rect(cornerRadius: dimensions.radius.radius8))
        }
    }

    // the same unit everything else calls, so a retry while a library run is
    // already checking this origin joins that fetch instead of racing it
    @ViewBuilder
    func Retry(_ entry: FailuresViewModel.Entry, vm: FailuresViewModel) -> some View {
        if vm.retrying.contains(entry.id) {
            ProgressView()
                .controlSize(.small)
        } else {
            Text("Try Again")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.brand)
                .padding(.horizontal, dimensions.spacing.space12)
                .padding(.vertical, dimensions.spacing.space4)
                .background(.brand.opacity(0.1), in: .capsule)
                .tappable { Task { await vm.retry(entry) } }
        }
    }

    var Recovered: some View {
        ContentUnavailableView {
            Label("Everything's Working", systemImage: "checkmark.circle")
        } description: {
            Text("Nothing is failing to check for new chapters or to reach a tracker.")
        }
    }

    // MARK: Tracking

    // no grouping control and no icon column: there are two services at most, and
    // the mark on each row already says which. what varies here is the series
    func TrackingHeader(_ count: Int) -> some View {
        HStack(spacing: dimensions.spacing.space8) {
            Image(systemName: "app.connected.to.app.below.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: Layout.headerIconSize)

            Text("Tracking")
                .font(.subheadline)
                .fontWeight(.semibold)

            Spacer(minLength: 0)

            Text("^[\(count) series](inflect: true)")
                .font(.caption)
                .foregroundStyle(.muted)
        }
        .frame(minHeight: dimensions.touchTarget)
        .accessibilityElement(children: .combine)
    }

    func TrackingRow(_ entry: FailuresViewModel.TrackerEntry, vm: FailuresViewModel) -> some View {
        HStack(spacing: 0) {
            TrackingCover(entry)

            VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
                HStack(spacing: dimensions.spacing.space12) {
                    Image(entry.tracker.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: Layout.iconSize, height: Layout.iconSize)
                        .clipShape(.rect(cornerRadius: dimensions.radius.radius8))

                    VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
                        Text(entry.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        // only when the two names disagree. a link pointing at the
                        // wrong entry is one reason a push keeps failing, and this
                        // is where it becomes visible
                        if entry.remoteTitle != entry.title, !entry.remoteTitle.isEmpty {
                            Text("Linked to \(entry.remoteTitle)")
                                .font(.caption2)
                                .foregroundStyle(.muted)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(entry.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    HStack(spacing: dimensions.spacing.space4) {
                        Text("Last tried")
                        LiveRelativeText(date: entry.attemptedDate)
                    }
                    .font(.caption2)
                    .foregroundStyle(.muted)

                    Spacer(minLength: 0)

                    TrackingRetry(entry, vm: vm)
                }
            }
            .padding(dimensions.spacing.space12)
        }
        .clipShape(.rect(cornerRadius: dimensions.radius.radius12, style: .continuous))
        .glassEffect(
            .regular.interactive(),
            in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
        .contentShape(.rect)
        .tappable { route = SeriesEntry.library(SeriesRecord.ID(rawValue: entry.seriesId)) }
    }

    func TrackingCover(_ entry: FailuresViewModel.TrackerEntry) -> some View {
        let local = compositor.assets.local(for: entry.path)

        return Color.clear
            .frame(width: Layout.coverWidth)
            .frame(maxHeight: .infinity)
            .overlay {
                if let cover = local ?? entry.cover {
                    KFImage(cover)
                        .resizable()
                        .placeholder { Rectangle().fill(.primary.opacity(Layout.placeholderOpacity)).shimmer() }
                        .fade(duration: 0.25)
                        .scaledToFill()
                } else {
                    Rectangle().fill(.primary.opacity(Layout.placeholderOpacity))
                }
            }
            .clipped()
    }

    // no spinner: a retry wakes the whole lane rather than resending this row, so
    // there is no per-row work to report. the row leaves on its own the moment the
    // push lands, which is the same signal every other row on this screen uses
    func TrackingRetry(_ entry: FailuresViewModel.TrackerEntry, vm: FailuresViewModel) -> some View {
        Text("Try Again")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.brand)
            .padding(.horizontal, dimensions.spacing.space12)
            .padding(.vertical, dimensions.spacing.space4)
            .background(.brand.opacity(0.1), in: .capsule)
            .tappable { vm.retry(entry) }
    }

    func Unavailable(_ failure: Failure) -> some View {
        ContentUnavailableView {
            Label(failure.title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(failure.message)
        }
    }
}
