//
//  DetailsDisambiguation.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI
import Kingfisher

struct DetailsDisambiguation: View {
    let candidates: [Candidate]
    var onAttach: (Int64) -> Void
    var onKeepSeparate: () -> Void
    var onCancel: () -> Void

    @Environment(\.dimensions) private var dimensions
    @State private var picked: Int64?

    private enum Layout {
        static let coverWidth: CGFloat = 124
        static let coverAspect: CGFloat = 11 / 16
        static let fillOpacity: Double = 0.1
        static let border: CGFloat = 2
        static let titleLines = 2
        static let authorLines = 2
        static let synopsisLines = 5
        static let metaLines = 1
        // context rather than a deciding fact, so it sits below everything else
        static let synopsisOpacity: Double = 0.7
        static let settle: Animation = .smooth(duration: 0.2)
    }

    // most read first, so whichever one the reader is invested in is never below
    // the fold
    private var ranked: [Candidate] {
        candidates.sorted { ($0.read, $0.total) > ($1.read, $1.total) }
    }

    private var single: Bool { candidates.count == 1 }
    private var anyStarted: Bool { candidates.contains(where: \.started) }

    private var headline: String {
        if single { anyStarted ? "You're already reading this" : "You already have this" }
        else { anyStarted ? "Which one are you reading?" : "Which one is it?" }
    }

    // series reads the same singular and plural, so this needs no inflection and
    // can stay a plain string for the subtitle
    private var subtitle: String {
        single
            ? "Adding it keeps your place and fills any gaps."
            : "\(candidates.count) series share this title."
    }

    // nothing is preselected, a single candidate included - the merge is
    // irreversible, so it should never happen without a deliberate tap
    private var selection: Candidate? {
        ranked.first { $0.id == picked }
    }

    var body: some View {
        NavigationStack {
            Rows
                .navigationTitle(headline)
                .navigationSubtitle(subtitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onCancel) {
                            Image(systemName: "chevron.backward")
                                .fontWeight(.semibold)
                        }
                        .accessibilityLabel("Back")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            guard let selection else { return }
                            onAttach(selection.id)
                        } label: {
                            Image(systemName: "checkmark")
                                .fontWeight(.semibold)
                        }
                        .disabled(selection == nil)
                        .accessibilityLabel("Merge with selected series")
                    }
                }
        }
    }
}

extension DetailsDisambiguation {
    private var Rows: some View {
        ScrollView {
            LazyVStack(spacing: dimensions.spacing.space8) {
                ForEach(ranked) { candidate in
                    Row(candidate)
                        .tappable { withAnimation(Layout.settle) { picked = candidate.id } }
                }

                // sits after the candidates rather than pinned, so it reads as the
                // last option in the list instead of a peer of the merge
                Separate
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.bottom, dimensions.spacing.space24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var Separate: some View {
        Button(action: onKeepSeparate) {
            Label("Add as new", systemImage: "plus.square.dashed")
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, dimensions.spacing.space8)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: dimensions.radius.radius16))
        .padding(.top, dimensions.spacing.space4)
    }

    private func Row(_ candidate: Candidate) -> some View {
        let chosen = selection?.id == candidate.id

        return HStack(alignment: .top, spacing: dimensions.spacing.space12) {
            Cover(candidate)

            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Text(candidate.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(Layout.titleLines)
                    .multilineTextAlignment(.leading)

                if let authors = candidate.authors, !authors.isEmpty {
                    Text(authors)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.muted)
                        .lineLimit(Layout.authorLines)
                }

                if let synopsis = candidate.synopsis, !synopsis.isEmpty {
                    Text(synopsis)
                        .font(.caption2)
                        .foregroundStyle(Palette.muted.opacity(Layout.synopsisOpacity))
                        .lineLimit(Layout.synopsisLines)
                        .multilineTextAlignment(.leading)
                }

                // pins the progress to the bottom of the row, so it lines up with
                // the cover's edge whatever the text above it does
                Spacer(minLength: dimensions.spacing.space4)

                if candidate.started, candidate.total > 0 {
                    ProgressView(value: Double(candidate.read), total: Double(candidate.total))
                        .tint(.brand)
                }

                HStack(alignment: .firstTextBaseline, spacing: dimensions.spacing.space4) {
                    // the inflected literal has to live at the Text site - building
                    // the string first skips grammar agreement entirely
                    Group {
                        if candidate.started {
                            Text("\(candidate.read) of \(candidate.total)")
                        } else if candidate.total > 0 {
                            Text("^[\(candidate.total) chapter](inflect: true)")
                        } else {
                            Text("No chapters")
                        }
                    }
                    // step 11 is the text step - step 9 is a solid fill and cannot
                    // hold contrast as small type
                    .fontWeight(.semibold)
                    .foregroundStyle(candidate.started ? Palette.brandText : Palette.muted)

                    Spacer(minLength: 0)

                    // a deciding fact, so it outranks the synopsis above it
                    Text(candidate.meta)
                        .fontWeight(.medium)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(Layout.metaLines)
                }
                .font(.caption2)
            }

            Spacer(minLength: 0)
        }
        .padding(dimensions.spacing.space12)
        .background(.surface, in: .rect(cornerRadius: dimensions.radius.radius16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: dimensions.radius.radius16, style: .continuous)
                .strokeBorder(chosen ? Palette.brand : .clear, lineWidth: Layout.border)
        }
        .contentShape(.rect)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func Cover(_ candidate: Candidate) -> some View {
        Color.clear
            .aspectRatio(Layout.coverAspect, contentMode: .fit)
            .frame(width: Layout.coverWidth)
            .overlay {
                KFImage(candidate.cover)
                    .requestModifier(AnyModifier.referer(candidate.referer))
                    .resizable()
                    .placeholder { Rectangle().fill(.primary.opacity(Layout.fillOpacity)).shimmer() }
                    .scaledToFill()
            }
            .clipShape(.rect(cornerRadius: dimensions.radius.radius8))
    }

}

extension DetailsDisambiguation {
    typealias Candidate = DetailsComposer.Identity.Candidate
}

#Preview {
    let title = """
        Tsuihou-kei no Akuyaku Party no Leader ni Tensei Shita node, Zamaa Sareru \
        Mae ni Jibun o Tsuihou Shimashita.: Skill o Ubau "Steal" tte Akuyakusugiru \
        kedo Tsuyosugiru
        """

    let cover = URL(
        string: "https://mangadex.org/covers/c2068513-1e3b-4e44-b8f5-b0ac5567aa2b/766323e2-c863-422a-a2a5-76f3d5bee137.jpg"
    )

    return Color.clear.sheet(isPresented: .constant(true)) {
        DetailsDisambiguation(
            candidates: [
                .init(
                    id: 1,
                    title: title,
                    authors: "Kaburagi Haruka, Nishizawa 5-mm",
                    synopsis: "Reincarnated as the leader of a villain party fated for ruin, he exiles himself before the story can catch up with him.",
                    cover: cover,
                    referer: nil,
                    read: 40,
                    total: 142,
                    lastReadDate: Date(timeIntervalSince1970: 1_785_628_800),
                    addedDate: Date(timeIntervalSince1970: 1_772_323_200)
                ),
                .init(
                    id: 2,
                    title: title,
                    authors: "Kaburagi Haruka, Nishizawa 5-mm",
                    synopsis: "Reincarnated as the leader of a villain party fated for ruin, he exiles himself before the story can catch up with him.",
                    cover: cover,
                    referer: nil,
                    read: 118,
                    total: 142,
                    lastReadDate: Date(timeIntervalSince1970: 1_785_715_200),
                    addedDate: Date(timeIntervalSince1970: 1_780_272_000)
                ),
                .init(
                    id: 3,
                    title: title,
                    authors: "Kaburagi Haruka, Nishizawa 5-mm",
                    synopsis: "Reincarnated as the leader of a villain party fated for ruin, he exiles himself before the story can catch up with him.",
                    cover: cover,
                    referer: nil,
                    read: 0,
                    total: 87,
                    lastReadDate: nil,
                    addedDate: Date(timeIntervalSince1970: 1_767_225_600)
                )
            ],
            onAttach: { _ in },
            onKeepSeparate: { },
            onCancel: { }
        )
        .presentationDetents([.large])
    }
}
