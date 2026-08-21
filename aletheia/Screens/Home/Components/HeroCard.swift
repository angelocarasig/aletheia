//
//  HeroCard.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/2026.
//

import SwiftUI
import Tagged

struct HeroCard: View {
    static let panelHeight: CGFloat = 600

    let entry: HomeViewModel.ContinueEntry
    var obscured: Bool = false
    var onContinue: () -> Void = {}
    var onDetails: () -> Void = {}

    @Environment(\.dimensions) private var dimensions

    private enum Layout {
        static let scrimStops: [(opacity: Double, location: Double)] = [
            (0.0, 0.0),
            (0.30, 0.50),
            (0.60, 0.70),
            (1.0, 1.0),
        ]
        static let eyebrowTracking: CGFloat = 0.6
        static let trackTint: Double = 0.30
        static let trackLabel: Double = 0.55
        static let titleLines = 2
        static let authorLines = 1
        static let transitOpacity: Double = 0.3
        static let transitOffset: CGFloat = 40
    }

    private var started: Bool { entry.lastReadNumber != nil }

    private var measurable: Bool { started && entry.totalChapters > 0 }

    private var fraction: Double {
        guard let read = entry.lastReadNumber, entry.totalChapters > 0 else { return 0 }
        return min(max(read / Double(entry.totalChapters), 0), 1)
    }

    private var position: String {
        guard measurable, let read = entry.lastReadNumber else {
            return entry.totalChapters > 0 ? "\(entry.totalChapters) CH" : ""
        }
        return "Ch \(Self.number(read)) of \(entry.totalChapters)"
    }

    var body: some View {
        CoverImage(url: entry.cover)
            .frame(maxWidth: .infinity)
            .frame(height: Self.panelHeight)
            .clipped()
            .obscured(obscured)
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    Scrim
                        .frame(height: Self.panelHeight)

                    Card
                        .scrollTransition(.interactive) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : Layout.transitOpacity)
                                .offset(y: phase.isIdentity ? 0 : Layout.transitOffset)
                        }
                }
            }
    }
}

extension HeroCard {
    fileprivate var Scrim: some View {
        LinearGradient(
            stops: Layout.scrimStops.map {
                .init(color: Palette.canvas.opacity($0.opacity), location: $0.location)
            },
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }

    fileprivate var Card: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space16) {
            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Meta
                    .padding(.bottom, dimensions.spacing.space4)

                Text(entry.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.textPrimary)
                    .lineLimit(Layout.titleLines)
                    .multilineTextAlignment(.leading)

                if let authors = entry.authors {
                    Text(authors)
                        .font(.caption)
                        .foregroundStyle(.muted)
                        .lineLimit(Layout.authorLines)
                        .truncationMode(.tail)
                }
            }

            Actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, dimensions.spacing.space24)
        .padding(.bottom, dimensions.spacing.space40)
    }
}

extension HeroCard {
    @ViewBuilder
    fileprivate var Meta: some View {
        let position = position

        if !position.isEmpty || entry.unreadCount > 0 {
            HStack(spacing: dimensions.spacing.space4) {
                if !position.isEmpty {
                    Text(position)
                }

                if entry.unreadCount > 0 {
                    if !position.isEmpty {
                        Text("·")
                    }

                    Text("\(entry.unreadCount) NEW")
                        .foregroundStyle(.warning)
                }
            }
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .tracking(Layout.eyebrowTracking)
            .foregroundStyle(.muted)
            .lineLimit(1)
        }
    }

    fileprivate var Actions: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Button(action: onContinue) {
                Resume
            }
            .buttonStyle(.plain)

            Button(action: onDetails) {
                HStack(spacing: dimensions.spacing.space8) {
                    Image(systemName: "info.circle")
                        .font(.caption2.weight(.bold))

                    Text("Details")
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.textPrimary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, dimensions.spacing.space16)
                .padding(.vertical, dimensions.spacing.space12)
                .glassEffect(.regular, in: .capsule)
                .contentShape(.capsule)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    fileprivate var Resume: some View {
        if measurable {
            ResumeFace(faded: true)
                .overlay {
                    GeometryReader { geometry in
                        ResumeFace(faded: false)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .mask(alignment: .leading) {
                                Rectangle()
                                    .frame(width: geometry.size.width * fraction)
                            }
                    }
                    .allowsHitTesting(false)
                }
                .contentShape(.capsule)
        } else {
            ResumeFace(faded: false)
                .contentShape(.capsule)
        }
    }

    fileprivate func ResumeFace(faded: Bool) -> some View {
        HStack(spacing: dimensions.spacing.space8) {
            Image(systemName: "play.fill")
                .font(.caption2.weight(.bold))

            Text(
                started
                    ? "Continue Ch \(Self.number(entry.target.number))"
                    : "Start Ch \(Self.number(entry.target.number))"
            )
            .font(.caption.weight(.semibold))
        }
        .foregroundStyle(Palette.onBrand.opacity(faded ? Layout.trackLabel : 1))
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .padding(.vertical, dimensions.spacing.space12)
        .background(
            Palette.brand.opacity(faded ? Layout.trackTint : 1),
            in: .capsule
        )
    }

    fileprivate static func number(_ value: Double) -> String {
        let rounded = value.rounded()
        return abs(value - rounded) < 0.001 ? String(Int(rounded)) : String(format: "%g", value)
    }
}

#if DEBUG
    private enum Sample {
        static let authors = "Yuna Seo, Haneul Park, Jiwoo Lim, Minseo Kang"

        static func cover(_ seed: String) -> URL? {
            URL(string: "https://picsum.photos/seed/\(seed)/800/1200")
        }

        static func entry(
            title: String,
            seed: String?,
            unread: Int,
            publication: Publication,
            total: Int,
            read: Double?,
            next: Double,
            authors: String? = Sample.authors
        ) -> HomeViewModel.ContinueEntry {
            HomeViewModel.ContinueEntry(
                id: SeriesRecord.ID(rawValue: 1),
                title: title,
                cover: seed.flatMap(cover),
                unreadCount: unread,
                lastReadDate: .now,
                target: read == nil
                    ? .start(chapterId: .init(rawValue: 1), number: next)
                    : .resume(chapterId: .init(rawValue: 1), number: next, progress: 0.45),
                adult: false,
                authors: authors,
                publication: publication,
                totalChapters: total,
                lastReadNumber: read
            )
        }
    }

    #Preview("Resuming") {
        HeroCard(
            entry: Sample.entry(
                title: "A Former Hero Returned From Another World",
                seed: "aletheia",
                unread: 3,
                publication: .Ongoing,
                total: 88,
                read: 42,
                next: 43
            )
        )
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        .background(.canvas)
    }

    #Preview("Bright art") {
        HeroCard(
            entry: Sample.entry(
                title: "Heavenly Solo Defender",
                seed: "bright-1",
                unread: 0,
                publication: .Hiatus,
                total: 214,
                read: 197.5,
                next: 198
            )
        )
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        .background(.canvas)
    }

    #Preview("No cover, no authors") {
        HeroCard(
            entry: Sample.entry(
                title: "The Long Winter and the Gate That Would Not Close",
                seed: nil,
                unread: 60,
                publication: .Completed,
                total: 60,
                read: nil,
                next: 1,
                authors: nil
            )
        )
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        .background(.canvas)
    }

    #Preview("Obscured") {
        HeroCard(
            entry: Sample.entry(
                title: "Blade of the Waning Moon",
                seed: "adult-1",
                unread: 4,
                publication: .Ongoing,
                total: 120,
                read: 61,
                next: 62
            ),
            obscured: true
        )
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        .background(.canvas)
    }
#endif
