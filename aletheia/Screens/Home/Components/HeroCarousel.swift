//
//  HeroCarousel.swift
//  aletheia
//
//  Created by Angelo Carasig on 21/8/2026.
//

import SwiftUI
import Tagged

struct HeroCarousel: View {
    let entries: [HomeViewModel.ContinueEntry]
    var obscured: Bool = false
    var onContinue: (HomeViewModel.ContinueEntry) -> Void = { _ in }
    var onDetails: (HomeViewModel.ContinueEntry) -> Void = { _ in }

    @Environment(\.dimensions) private var dimensions

    @State private var slot: Slot? = .real(0)
    @State private var advance: Task<Void, Never>?
    @State private var settles = 0

    private enum Layout {
        static let parallax: CGFloat = 0.5
        static let dot: CGFloat = 4
        static let activeDot: CGFloat = 12
        static let idleDot: Double = 0.5
        static let dotsHeight: CGFloat = 32
        static let dotsOffset: CGFloat = -20
    }

    private enum Timing {
        static let interval: Duration = .seconds(5)
    }

    private enum Slot: Hashable {
        case head
        case real(Int)
        case tail
    }

    private var ring: [(slot: Slot, entry: HomeViewModel.ContinueEntry)] {
        guard entries.count > 1 else {
            return entries.first.map { [(.real(0), $0)] } ?? []
        }

        var out: [(Slot, HomeViewModel.ContinueEntry)] = []
        if let last = entries.last { out.append((.head, last)) }
        out += entries.enumerated().map { (.real($0.offset), $0.element) }
        if let first = entries.first { out.append((.tail, first)) }
        return out
    }

    private var current: Int {
        switch slot {
        case .real(let index): min(index, max(entries.count - 1, 0))
        case .head: max(entries.count - 1, 0)
        case .tail, .none: 0
        }
    }

    var body: some View {
        if entries.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                GeometryReader { geometry in
                    Rail(width: geometry.size.width)
                }
                .frame(height: HeroCard.panelHeight + dimensions.spacing.space16)

                Dots
            }
            .sensoryFeedback(.selection, trigger: settles)
            .onAppear { schedule() }
            .onDisappear { advance?.cancel() }
            .onChange(of: entries.count) {
                slot = .real(0)
                schedule()
            }
        }
    }
}

extension HeroCarousel {
    fileprivate func Rail(width: CGFloat) -> some View {
        let travel = -width * Layout.parallax

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(ring, id: \.slot) { item in
                    ZStack {
                        HeroCard(
                            entry: item.entry,
                            obscured: obscured && item.entry.adult,
                            onContinue: { onContinue(item.entry) },
                            onDetails: { onDetails(item.entry) }
                        )
                        .frame(width: width, height: HeroCard.panelHeight)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content.offset(x: phase.value * travel)
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                    .clipped()
                    .contentShape(.rect)
                    .allowsHitTesting(item.slot == slot)
                }
            }
            .scrollTargetLayout()
            .padding(.bottom, dimensions.spacing.space16)
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $slot)
        .onScrollPhaseChange { old, phase in
            settle(from: old, to: phase)
        }
    }

    fileprivate var Dots: some View {
        HStack(spacing: dimensions.spacing.space4) {
            ForEach(entries.indices, id: \.self) { index in
                let active = index == current

                Circle()
                    .fill(active ? Color.white : Color.white.opacity(Layout.idleDot))
                    .frame(
                        width: active ? Layout.activeDot : Layout.dot,
                        height: active ? Layout.activeDot : Layout.dot
                    )
            }
        }
        .animation(.snappy, value: current)
        .frame(height: Layout.dotsHeight)
        .offset(y: Layout.dotsOffset)
        .accessibilityHidden(true)
    }
}

extension HeroCarousel {
    fileprivate func settle(from old: ScrollPhase, to phase: ScrollPhase) {
        guard phase == .idle else {
            if phase == .tracking || phase == .interacting { advance?.cancel() }
            return
        }

        switch slot {
        case .head: slot = .real(max(entries.count - 1, 0))
        case .tail: slot = .real(0)
        default: break
        }

        if old == .tracking || old == .interacting || old == .decelerating {
            settles += 1
            schedule()
        }
    }

    fileprivate func schedule() {
        advance?.cancel()
        guard entries.count > 1 else { return }

        advance = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: Timing.interval)
                guard !Task.isCancelled else { break }
                step()
            }
        }
    }

    fileprivate func step() {
        guard entries.count > 1 else { return }

        let next: Slot =
            switch slot {
            case .real(let index): index + 1 < entries.count ? .real(index + 1) : .tail
            case .head, .tail, .none: .real(0)
            }

        withAnimation(.snappy) { slot = next }
    }
}

#if DEBUG
    private enum Sample {
        static let titles = [
            "A Former Hero Returned From Another World",
            "Heavenly Solo Defender",
            "The Villainess Wants a Quiet Life",
            "Blade of the Waning Moon",
        ]

        static let authors = "Yuna Seo, Haneul Park, Jiwoo Lim, Minseo Kang"

        static func entries(_ count: Int) -> [HomeViewModel.ContinueEntry] {
            (0..<count).map { index in
                let read = Double(20 + index * 13)
                return HomeViewModel.ContinueEntry(
                    id: SeriesRecord.ID(rawValue: Int64(index + 1)),
                    title: titles[index % titles.count],
                    cover: URL(string: "https://picsum.photos/seed/hero-\(index)/800/1200"),
                    unreadCount: index * 2,
                    lastReadDate: .now,
                    target: .resume(
                        chapterId: .init(rawValue: Int64(index + 1)),
                        number: read + 1,
                        progress: 0.45
                    ),
                    adult: false,
                    authors: index == 2 ? nil : authors,
                    publication: [.Ongoing, .Hiatus, .Completed][index % 3],
                    totalChapters: 60 + index * 40,
                    lastReadNumber: read
                )
            }
        }
    }

    #Preview("Four") {
        ScrollView {
            HeroCarousel(entries: Sample.entries(4))
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(.canvas)
    }

    #Preview("Single") {
        ScrollView {
            HeroCarousel(entries: Sample.entries(1))
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(.canvas)
    }
#endif
