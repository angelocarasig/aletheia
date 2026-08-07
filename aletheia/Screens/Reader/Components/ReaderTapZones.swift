//
//  ReaderTapZones.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI

// zones are fractions of the screen, so they hold at any size without a second
// set of numbers per device. every layout tiles the whole screen rather than
// declaring only its edges - a layout that leaves holes cannot be drawn, and
// there would be no way to express a middle that is not the menu
enum ReaderTapZones {
    enum Action {
        case previous
        case next
        case menu
    }

    enum Layout: String, CaseIterable, Identifiable {
        case off = "off"
        case edge = "edge"
        case edgeThin = "edge_thin"
        case kindle = "kindle"
        case vertical = "vertical"
        case corners = "corners"
        case reverseCorners = "reverse_corners"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .off: "Off"
            case .edge: "Edge"
            case .edgeThin: "Edge (Thin)"
            case .kindle: "Kindle"
            case .vertical: "Vertical"
            case .corners: "Corners"
            case .reverseCorners: "Reverse Corners"
            }
        }

        var summary: String {
            switch self {
            case .off: "A tap anywhere opens the menu."
            case .edge: "Tap the left or right edge to turn pages."
            case .edgeThin: "Thinner edge strips, bigger menu area."
            case .kindle: "Big next area with a small back strip."
            case .vertical: "Tap the top or bottom to turn pages."
            case .corners: "Turn pages from the left and right sides."
            case .reverseCorners: "Corners, with the sides mirrored."
            }
        }

        // nothing to swap when every region is the menu
        var isFlippable: Bool {
            regions.contains { $0.action != .menu }
        }

        var regions: [Region] {
            switch self {
            case .off:
                [
                    Region(.menu, x: 0, y: 0, width: 1, height: 1)
                ]
            case .edge:
                [
                    Region(.previous, x: 0, y: 0, width: 0.28, height: 1),
                    Region(.menu, x: 0.28, y: 0, width: 0.44, height: 1),
                    Region(.next, x: 0.72, y: 0, width: 0.28, height: 1)
                ]
            case .edgeThin:
                [
                    Region(.previous, x: 0, y: 0, width: 0.14, height: 1),
                    Region(.menu, x: 0.14, y: 0, width: 0.72, height: 1),
                    Region(.next, x: 0.86, y: 0, width: 0.14, height: 1)
                ]
            case .kindle:
                [
                    Region(.menu, x: 0, y: 0, width: 1, height: 0.3),
                    Region(.previous, x: 0, y: 0.3, width: 0.25, height: 0.7),
                    Region(.next, x: 0.25, y: 0.3, width: 0.75, height: 0.7)
                ]
            case .vertical:
                [
                    Region(.previous, x: 0, y: 0, width: 1, height: 0.28),
                    Region(.menu, x: 0, y: 0.28, width: 1, height: 0.44),
                    Region(.next, x: 0, y: 0.72, width: 1, height: 0.28)
                ]
            case .corners:
                [
                    Region(.previous, x: 0, y: 0, width: 0.22, height: 1),
                    Region(.previous, x: 0.22, y: 0.78, width: 0.56, height: 0.22),
                    Region(.next, x: 0.78, y: 0, width: 0.22, height: 1),
                    Region(.next, x: 0.22, y: 0, width: 0.56, height: 0.22),
                    Region(.menu, x: 0.22, y: 0.22, width: 0.56, height: 0.56)
                ]
            case .reverseCorners:
                [
                    Region(.previous, x: 0, y: 0, width: 0.22, height: 1),
                    Region(.previous, x: 0.22, y: 0, width: 0.56, height: 0.22),
                    Region(.next, x: 0.78, y: 0, width: 0.22, height: 1),
                    Region(.next, x: 0.22, y: 0.78, width: 0.56, height: 0.22),
                    Region(.menu, x: 0.22, y: 0.22, width: 0.56, height: 0.56)
                ]
            }
        }
    }

    struct Region {
        let action: Action
        let rect: CGRect

        init(_ action: Action, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
            self.action = action
            self.rect = CGRect(x: x, y: y, width: width, height: height)
        }
    }

    // right-to-left mirrors the pages, so it has to mirror the zones with them,
    // and the reader's own toggle composes on top rather than overriding it.
    // one function because the hit test, the flash and the picker previews must
    // all answer this the same way, and they live in three different files
    static func reversed(for mode: Orientation, manual: Bool) -> Bool {
        manual != mode.isRightToLeft
    }

    // first match wins, and anything unclaimed opens the menu - the layouts tile,
    // so that only catches a tap exactly on the far edge
    static func action(
        at point: CGPoint,
        in size: CGSize,
        layout: Layout,
        reversed: Bool
    ) -> Action {
        guard size.width > 0, size.height > 0 else { return .menu }

        let normalised = CGPoint(x: point.x / size.width, y: point.y / size.height)
        let matched = layout.regions.first { $0.rect.contains(normalised) }?.action ?? .menu

        return reversed ? matched.flipped : matched
    }
}

extension ReaderTapZones.Action {
    var flipped: Self {
        switch self {
        case .previous: .next
        case .next: .previous
        case .menu: .menu
        }
    }

    var tint: Color {
        switch self {
        case .previous: Palette.warning
        case .next: Palette.success
        case .menu: Palette.muted
        }
    }

    var icon: String {
        switch self {
        case .previous: "chevron.left"
        case .next: "chevron.right"
        case .menu: "line.3.horizontal"
        }
    }
}

// one renderer at two scales: full screen for the flash, thumbnail for a picker
// row. drawing the picker from anything else would let the two disagree about
// what a layout means, which is the one thing a preview must never do
struct ReaderTapZoneMap: View {
    let layout: ReaderTapZones.Layout
    let reversed: Bool
    var isCompact = false

    private enum Metrics {
        static let fill: Double = 0.25
        static let compactFill: Double = 0.55
        static let border: CGFloat = 1
    }

    var body: some View {
        GeometryReader { proxy in
            ForEach(Array(layout.regions.enumerated()), id: \.offset) { _, region in
                let action = reversed ? region.action.flipped : region.action

                ZStack {
                    action.tint.opacity(isCompact ? Metrics.compactFill : Metrics.fill)

                    if !isCompact {
                        Image(systemName: action.icon)
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
                .border(.background.opacity(Metrics.fill), width: Metrics.border)
                .frame(
                    width: region.rect.width * proxy.size.width,
                    height: region.rect.height * proxy.size.height
                )
                .position(
                    x: region.rect.midX * proxy.size.width,
                    y: region.rect.midY * proxy.size.height
                )
            }
        }
        .allowsHitTesting(false)
    }
}
