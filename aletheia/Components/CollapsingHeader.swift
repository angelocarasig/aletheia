//
//  CollapsingHeader.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import SwiftUI

private enum Layout {
    // deadband so rubber-banding or a fingertip tremor doesn't flicker the header
    static let threshold: CGFloat = 6
    static let settle: Animation = .smooth(duration: 0.25)
}

struct CollapsingHeader<Header: View, Content: View>: View {
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    @Environment(\.dimensions) private var dimensions

    @State private var hidden = false
    @State private var height: CGFloat = 0
    @State private var safeTop: CGFloat = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // without maxWidth, near-empty content collapses the scroll view's
            // width, and the overlaid header collapses with it
            content()
                .padding(.top, height + dimensions.spacing.space8)
                .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .top) { HeaderOverlay }
        .onGeometryChange(for: CGFloat.self) {
            $0.safeAreaInsets.top
        } action: {
            safeTop = $0
        }
        .onScrollGeometryChange(for: CGFloat.self) {
            $0.contentOffset.y
        } action: { old, new in
            // keep visible near the top so it can't be stranded hidden with
            // nothing left to scroll back through
            if new <= height {
                if hidden { hidden = false }
            } else if abs(new - old) > Layout.threshold {
                let downward = new > old
                if hidden != downward { hidden = downward }
            }
        }
    }

    private var HeaderOverlay: some View {
        header()
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.top, dimensions.spacing.space8)
            .padding(.bottom, dimensions.spacing.space12)
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))
            .onGeometryChange(for: CGFloat.self) {
                $0.size.height
            } action: {
                height = $0
            }
            .offset(y: hidden ? -(height + safeTop) : 0)
            .opacity(hidden ? 0 : 1)
            .allowsHitTesting(!hidden)
            .animation(Layout.settle, value: hidden)
    }
}
