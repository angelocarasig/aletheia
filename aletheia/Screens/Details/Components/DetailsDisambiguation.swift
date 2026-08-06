//
//  DetailsDisambiguation.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI
import Kingfisher

struct DetailsDisambiguation: View {
    let title: String
    let sourceName: String
    let candidates: [Candidate]
    var onAttach: (Int64) -> Void
    var onKeepSeparate: () -> Void

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let coverWidth: CGFloat = 70
        static let coverAspect: CGFloat = 11 / 16
        static let fillOpacity: Double = 0.1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: dimensions.spacing.space12) {
                    Explanation

                    ForEach(candidates) { candidate in
                        Row(candidate)
                            .tappable { onAttach(candidate.id) }
                    }

                    KeepSeparate
                }
                .padding(dimensions.screenMargin)
            }
            .navigationTitle("Already in Library?")
            .navigationSubtitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var Explanation: some View {
        Text("You already have ^[\(candidates.count) series](inflect: true) with this title. Attaching adds \(sourceName) as another source instead of creating a duplicate.")
            .font(.subheadline)
            .foregroundStyle(.muted)
            .padding(.bottom, dimensions.spacing.space4)
    }

    private func Row(_ candidate: Candidate) -> some View {
        HStack(alignment: .top, spacing: dimensions.spacing.space12) {
            Cover(candidate)

            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Text(candidate.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let authors = candidate.authors, !authors.isEmpty {
                    Text(authors)
                        .font(.caption)
                        .foregroundStyle(.muted)
                        .lineLimit(1)
                }

                HStack(spacing: dimensions.spacing.space4) {
                    Badge("^[\(candidate.sourceCount) source](inflect: true)")
                    Badge("^[\(candidate.chapterCount) chapter](inflect: true)", tone: .neutral)
                }
                .padding(.top, dimensions.spacing.space2)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.muted)
        }
        .padding(dimensions.spacing.space12)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: dimensions.radius.radius16))
        .contentShape(.rect)
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

    private var KeepSeparate: some View {
        Button(action: onKeepSeparate) {
            Label("None of these — keep separate", systemImage: "plus.square.dashed")
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, dimensions.spacing.space8)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.roundedRectangle(radius: dimensions.radius.radius16))
        .padding(.top, dimensions.spacing.space4)
    }
}

extension DetailsDisambiguation {
    struct Candidate: Identifiable, Hashable {
        let id: Int64
        let title: String
        let cover: URL?
        let referer: URL?
        let authors: String?
        let sourceCount: Int
        let chapterCount: Int
    }
}
