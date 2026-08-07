//
//  ReaderTapZones.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI

// zones are fractions of the screen, so they hold at any size without a second
// set of numbers per device
enum ReaderTapZones {
    enum Action {
        case previous
        case next
        case menu
    }

    enum Layout: String, CaseIterable, Identifiable {
        case leftRight
        case edges
        case kindle

        var id: String { rawValue }

        var label: String {
            switch self {
            case .leftRight: "Left and Right"
            case .edges: "Edges"
            case .kindle: "Kindle"
            }
        }

        var regions: [Region] {
            switch self {
            case .leftRight:
                [
                    Region(.previous, x: 0, y: 0, width: 0.33, height: 1),
                    Region(.next, x: 0.67, y: 0, width: 0.33, height: 1)
                ]
            case .edges:
                [
                    Region(.previous, x: 0, y: 0, width: 0.2, height: 1),
                    Region(.next, x: 0.8, y: 0, width: 0.2, height: 1)
                ]
            case .kindle:
                [
                    Region(.menu, x: 0, y: 0, width: 1, height: 0.2),
                    Region(.previous, x: 0, y: 0.2, width: 0.25, height: 0.8),
                    Region(.next, x: 0.25, y: 0.2, width: 0.75, height: 0.8)
                ]
            }
        }
    }

    struct Region: Identifiable {
        let action: Action
        let rect: CGRect

        var id: String { "\(rect)" }

        init(_ action: Action, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
            self.action = action
            self.rect = CGRect(x: x, y: y, width: width, height: height)
        }
    }

    // first match wins, and anything unclaimed opens the menu - so a layout can
    // never leave a dead patch of screen
    static func action(
        at point: CGPoint,
        in size: CGSize,
        layout: Layout,
        reversed: Bool
    ) -> Action {
        guard ReaderSettings.tapZonesEnabled, size.width > 0, size.height > 0 else { return .menu }

        let normalised = CGPoint(x: point.x / size.width, y: point.y / size.height)
        let matched = layout.regions.first { $0.rect.contains(normalised) }?.action ?? .menu

        guard reversed else { return matched }
        return switch matched {
        case .previous: .next
        case .next: .previous
        case .menu: .menu
        }
    }
}

extension ReaderTapZones.Action {
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

// shown briefly when the reader opens or the layout changes, so the zones are
// discoverable without a settings trip
struct ReaderTapZoneOverlay: View {
    let layout: ReaderTapZones.Layout
    let reversed: Bool

    var body: some View {
        GeometryReader { proxy in
            ForEach(layout.regions) { region in
                let action = resolved(region.action)

                ZStack {
                    action.tint.opacity(0.25)
                    Image(systemName: action.icon)
                        .font(.title2)
                        .foregroundStyle(.white)
                }
                .frame(
                    width: region.rect.width * proxy.size.width,
                    height: region.rect.height * proxy.size.height
                )
                .position(
                    x: (region.rect.midX) * proxy.size.width,
                    y: (region.rect.midY) * proxy.size.height
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func resolved(_ action: ReaderTapZones.Action) -> ReaderTapZones.Action {
        guard reversed else { return action }
        return switch action {
        case .previous: .next
        case .next: .previous
        case .menu: .menu
        }
    }
}
