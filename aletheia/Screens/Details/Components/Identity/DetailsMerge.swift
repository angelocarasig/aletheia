//
//  DetailsMerge.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import Kingfisher
import SwiftUI

struct DetailsMerge: View {
    let source: Side
    let candidates: [Candidate]
    let isLoading: Bool
    var onSearch: (String) async -> Void
    var onMerge: (Int64) -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private enum Layout {
        static let coverWidth: CGFloat = 56
        static let titleLines = 2
        static let chevronOpacity: Double = 0.3
    }

    var body: some View {
        NavigationStack {
            Content
                .navigationTitle("Merge Into")
                .navigationSubtitle("Everything this series has moves to the one you pick")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .fontWeight(.semibold)
                        }
                        .accessibilityLabel("Cancel")
                    }
                }
                .navigationDestination(for: Candidate.self) { candidate in
                    MergeComparison(source: source, target: candidate)
                }
                .navigationDestination(for: Confirmation.self) { confirmation in
                    MergeConfirm(source: source, target: confirmation.target, onMerge: onMerge)
                }
                .containerBackground(.clear, for: .navigation)
        }
        // .task(id:) cancels the in-flight query itself on each keystroke - no
        // debounce needed; the empty first value doubles as the initial load
        .task(id: searchText) {
            await onSearch(searchText)
        }
    }
}

extension DetailsMerge {
    private var Content: some View {
        VStack(spacing: dimensions.spacing.space8) {
            Searchbar(
                searchText: $searchText,
                placeholder: "Search your library"
            )
            .padding(.horizontal, dimensions.screenMargin)

            Results
        }
        .animation(.settle, value: phase)
    }

    private var phase: LoadPhase {
        if !candidates.isEmpty { .content } else if isLoading { .pending } else { .empty }
    }

    @ViewBuilder
    private var Results: some View {
        Group {
            if isLoading && candidates.isEmpty {
                SheetSkeleton(rows: 5)
            } else if candidates.isEmpty && !searchText.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if candidates.isEmpty {
                ContentUnavailableView {
                    Label("Nothing to Merge Into", systemImage: "books.vertical")
                } description: {
                    Text("Your library has no other series to receive this one.")
                } actions: {
                    Button("Close") { dismiss() }
                }
            } else {
                Rows
            }
        }
        .transition(.opacity)
    }

    private var Rows: some View {
        ScrollView {
            LazyVStack(spacing: dimensions.spacing.space8) {
                ForEach(candidates) { candidate in
                    NavigationLink(value: candidate) {
                        Row(candidate)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.bottom, dimensions.spacing.space24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func Row(_ candidate: Candidate) -> some View {
        HStack(alignment: .center, spacing: dimensions.spacing.space12) {
            MergeCover(url: candidate.cover, referer: candidate.referer, width: Layout.coverWidth)

            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Text(candidate.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(Layout.titleLines)
                    .multilineTextAlignment(.leading)

                HStack(spacing: dimensions.spacing.space4) {
                    Text("\(candidate.match)% match")
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.brandText)

                    Spacer(minLength: 0)

                    Group {
                        if candidate.total > 0 {
                            Text("^[\(candidate.total) chapter](inflect: true)")
                        } else {
                            Text("No chapters")
                        }
                    }
                    .fontWeight(.medium)
                    .foregroundStyle(.muted)
                }
                .font(.caption)
            }

            Image(systemName: "chevron.right")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(Palette.muted.opacity(Layout.chevronOpacity))
        }
        .padding(dimensions.spacing.space12)
        .background(
            .surface, in: .rect(cornerRadius: dimensions.radius.radius16, style: .continuous)
        )
        .contentShape(.rect)
    }
}

private struct MergeComparison: View {
    let source: DetailsMerge.Side
    let target: DetailsMerge.Candidate

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let coverWidth: CGFloat = 100
        static let titleLines = 2
        static let sublabelOpacity: Double = 0.6
        static let valueLines = 4
        static let hunkOpacity: Double = 0.25
    }

    var body: some View {
        ScrollView {
            VStack(spacing: dimensions.spacing.space24) {
                Cards

                Divider()

                Differences
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.top, dimensions.spacing.space16)
            .padding(.bottom, dimensions.spacing.space24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("Review Merge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: DetailsMerge.Confirmation(target: target)) {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                }
                .accessibilityLabel("Continue to confirmation")
            }
        }
    }

    private var Cards: some View {
        HStack(alignment: .top, spacing: dimensions.spacing.space12) {
            Card(side: source)

            Image(systemName: "arrow.right")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.muted)
                .frame(maxHeight: .infinity)

            Card(candidate: target)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func Card(side: DetailsMerge.Side) -> some View {
        Card(
            title: side.title,
            cover: side.cover,
            referer: side.referer,
            origins: side.origins,
            read: side.read,
            total: side.total,
            badge: "FROM",
            tone: .danger,
            sublabel: "Deleted after"
        )
    }

    private func Card(candidate: DetailsMerge.Candidate) -> some View {
        Card(
            title: candidate.title,
            cover: candidate.cover,
            referer: candidate.referer,
            origins: candidate.origins,
            read: candidate.read,
            total: candidate.total,
            badge: "INTO",
            tone: .success,
            sublabel: "Receives everything"
        )
    }

    private func Card(
        title: String,
        cover: URL?,
        referer: URL?,
        origins: Int,
        read: Int,
        total: Int,
        badge: String,
        tone: Palette.Tone,
        sublabel: String
    ) -> some View {
        VStack(spacing: dimensions.spacing.space8) {
            Badge(text: badge, tone: tone)

            MergeCover(url: cover, referer: referer, width: Layout.coverWidth)

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(Layout.titleLines)
                .multilineTextAlignment(.center)

            VStack(spacing: dimensions.spacing.space2) {
                Group {
                    if total > 0 {
                        Text(
                            "^[\(origins) source](inflect: true) · ^[\(total) chapter](inflect: true)"
                        )
                    } else {
                        Text("^[\(origins) source](inflect: true) · No chapters")
                    }
                }
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.muted)

                if read > 0 {
                    Text("\(read) of \(total) read")
                        .font(.caption2)
                        .foregroundStyle(Palette.brandText)
                }

                Text(sublabel)
                    .font(.caption2)
                    .foregroundStyle(Palette.muted.opacity(Layout.sublabelOpacity))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var Differences: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            // target keeps its own picks - what merges in adds to the pool,
            // never overwrites one
            Difference("Title", from: source.title, into: target.title)
            Difference("Authors", from: source.authors, into: target.authors)
            Difference("Status", from: source.status.label, into: target.status.label)
            Difference(
                "Publication", from: source.publication?.label, into: target.publication.label)
            Difference("Synopsis", from: source.synopsis, into: target.synopsis)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func Difference(_ label: String, from: String?, into: String?) -> some View {
        let left = from?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let right = into?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !left.isEmpty || !right.isEmpty {
            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.muted)

                Value(left, glyph: "minus.circle.fill", tone: .danger, role: "Merging away")
                Value(right, glyph: "plus.circle.fill", tone: .success, role: "Receiving")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(dimensions.spacing.space12)
            .background(
                .ultraThinMaterial,
                in: .rect(cornerRadius: dimensions.radius.radius16, style: .continuous))
        }
    }

    @ViewBuilder
    private func Value(_ text: String, glyph: String, tone: Palette.Tone, role: String) -> some View
    {
        HStack(alignment: .firstTextBaseline, spacing: dimensions.spacing.space8) {
            Image(systemName: glyph)
                .font(.caption2)
                .foregroundStyle(tone.text)

            Text(text.isEmpty ? "-" : text)
                .font(.footnote)
                .foregroundStyle(text.isEmpty ? Palette.muted : tone.text)
                .lineLimit(Layout.valueLines)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, dimensions.spacing.space8)
        .padding(.vertical, dimensions.spacing.space4)
        .background(
            tone.subtle.opacity(Layout.hunkOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius8, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(role): \(text.isEmpty ? "nothing" : text)")
    }
}

private struct MergeConfirm: View {
    let source: DetailsMerge.Side
    let target: DetailsMerge.Candidate
    let onMerge: (Int64) -> Void

    @Environment(\.dimensions) private var dimensions
    @State private var confirming = false
    @State private var committed = false

    private enum Layout {
        static let coverWidth: CGFloat = 100
        static let bulletWidth: CGFloat = 24
        static let titleLines = 2
        static let washOpacity: Double = 0.5
    }

    var body: some View {
        ScrollView {
            VStack(spacing: dimensions.spacing.space16) {
                Pair

                OutcomeCard

                DeletionCard
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.top, dimensions.spacing.space16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("Confirm Merge")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Commit
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.bottom, dimensions.spacing.space8)
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: committed)
        .alert(
            "Merge into \(target.title)?",
            isPresented: $confirming
        ) {
            Button("Merge", role: .destructive) {
                committed = true
                onMerge(target.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var Pair: some View {
        HStack(alignment: .top, spacing: dimensions.spacing.space16) {
            PairSide(
                badge: "FROM",
                tone: .danger,
                cover: source.cover,
                referer: source.referer,
                title: source.title,
                titleColor: Palette.dangerText,
                role: "Merging away"
            )

            Image(systemName: "arrow.right")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(.muted)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)

            PairSide(
                badge: "INTO",
                tone: .success,
                cover: target.cover,
                referer: target.referer,
                title: target.title,
                titleColor: Palette.successText,
                role: "Receiving"
            )
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func PairSide(
        badge: String,
        tone: Palette.Tone,
        cover: URL?,
        referer: URL?,
        title: String,
        titleColor: Color,
        role: String
    ) -> some View {
        VStack(spacing: dimensions.spacing.space8) {
            Badge(text: badge, tone: tone)

            MergeCover(url: cover, referer: referer, width: Layout.coverWidth)

            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(titleColor)
                .lineLimit(Layout.titleLines)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(role): \(title)")
    }

    private var OutcomeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Outcome(
                icon: "books.vertical",
                label: "Sources",
                value: Text("\(target.origins) → \(target.origins + source.origins)")
            )

            Separator

            Outcome(
                icon: "book.closed",
                label: "Chapters",
                value: Text("+\(source.total)")
            )

            Separator

            Outcome(
                icon: "bookmark",
                label: "Reading progress",
                value: source.read > 0
                    ? Text("^[\(source.read) chapter](inflect: true) kept") : Text("None yet")
            )

            Separator

            Outcome(
                icon: "folder",
                label: "Collections",
                value: Text("Combined")
            )
        }
        .padding(.horizontal, dimensions.spacing.space12)
        .background(
            .ultraThinMaterial,
            in: .rect(cornerRadius: dimensions.radius.radius16, style: .continuous))
    }

    private var Separator: some View {
        Divider()
            .padding(.leading, Layout.bulletWidth + dimensions.spacing.space12)
    }

    private var DeletionCard: some View {
        HStack(alignment: .firstTextBaseline, spacing: dimensions.spacing.space12) {
            Image(systemName: "trash")
                .font(.footnote)
                .foregroundStyle(Palette.dangerText)
                .frame(width: Layout.bulletWidth)

            Text("\"\(source.title)\" is deleted")
                .font(.subheadline)
                .foregroundStyle(Palette.dangerText)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(dimensions.spacing.space12)
        .background(
            Palette.dangerSubtle.opacity(Layout.washOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius16, style: .continuous)
        )
    }

    private func Outcome(icon: String, label: String, value: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: dimensions.spacing.space12) {
            Image(systemName: icon)
                .font(.footnote)
                .foregroundStyle(Palette.brandText)
                .frame(width: Layout.bulletWidth)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(Palette.textPrimary)

            Spacer(minLength: dimensions.spacing.space8)

            value
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.muted)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, dimensions.spacing.space12)
    }

    private var Commit: some View {
        Button {
            confirming = true
        } label: {
            Label("Merge", systemImage: "arrow.triangle.merge")
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, dimensions.spacing.space8)
        }
        .buttonStyle(.glassProminent)
        .tint(Palette.danger)
        .buttonBorderShape(.roundedRectangle(radius: dimensions.radius.radius16))
    }
}

private struct MergeCover: View {
    let url: URL?
    let referer: URL?
    let width: CGFloat

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let aspect: CGFloat = 11 / 16
        static let fillOpacity: Double = 0.1
        static let fade: TimeInterval = 0.25
    }

    var body: some View {
        Color.clear
            .aspectRatio(Layout.aspect, contentMode: .fit)
            .frame(width: width)
            .overlay {
                KFImage(url)
                    .requestModifier(AnyModifier.referer(referer))
                    .resizable()
                    .placeholder {
                        Rectangle().fill(.primary.opacity(Layout.fillOpacity)).shimmer()
                    }
                    .fade(duration: Layout.fade)
                    .scaledToFill()
            }
            .clipShape(.rect(cornerRadius: dimensions.radius.radius8))
    }
}

extension DetailsMerge {
    struct Side: Hashable {
        let title: String
        let authors: String?
        let synopsis: String?
        let cover: URL?
        let referer: URL?
        let status: Status
        let publication: Publication?
        let origins: Int
        let read: Int
        let total: Int
    }

    typealias Candidate = DetailsComposer.Identity.Match

    // wraps target as its own nav value - reusing Candidate for confirmation
    // would collide with the comparison destination in the NavigationStack
    struct Confirmation: Hashable {
        let target: Candidate
    }
}

#Preview {
    Color.clear.sheet(isPresented: .constant(true)) {
        DetailsMerge(
            source: .init(
                title: "Solo Leveling",
                authors: "Chugong",
                synopsis: "The weakest hunter of all mankind rises again.",
                cover: nil,
                referer: nil,
                status: .reading,
                publication: .Ongoing,
                origins: 2,
                read: 45,
                total: 179
            ),
            candidates: [
                .init(
                    id: 1,
                    title: "Solo Leveling: Ragnarok",
                    authors: "Chugong, Daul",
                    synopsis: "The story continues with Sung Suho.",
                    cover: nil,
                    referer: nil,
                    status: .planning,
                    publication: .Ongoing,
                    origins: 1,
                    read: 0,
                    total: 44,
                    score: 0.95
                ),
                .init(
                    id: 2,
                    title: "Solo Max-Level Newbie",
                    authors: "Swing Bat",
                    synopsis: nil,
                    cover: nil,
                    referer: nil,
                    status: .reading,
                    publication: .Ongoing,
                    origins: 2,
                    read: 12,
                    total: 120,
                    score: 0.61
                ),
            ],
            isLoading: false,
            onSearch: { _ in },
            onMerge: { _ in }
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
