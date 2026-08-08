//
//  CollapsingHeader.swift
//  aletheia
//
//  Created by Angelo Carasig on 8/8/2026.
//

import SwiftUI

// outside the type: a generic cannot hold static stored properties
private enum Layout {
    // small deliberate deadband: without it a single pixel of rubber-banding or
    // a fingertip tremor flickers the header
    static let threshold: CGFloat = 6
    static let settle: Animation = .smooth(duration: 0.25)
}

// a header that gets out of the way while you read down a list and comes back
// the moment you reach for it.
//
// the header is an overlay rather than a sibling in the scroll content, so
// hiding it never changes the content's layout - the results do not reflow, they
// just gain the space. content is inset by the measured header height instead,
// which is why the header must be able to report its own size rather than be
// told one
struct CollapsingHeader<Header: View, Content: View>: View {
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content

    @Environment(\.dimensions) private var dimensions

    @State private var hidden = false
    @State private var height: CGFloat = 0
    @State private var safeTop: CGFloat = 0

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // full width always: a vertical scroll view hugs its content's width,
            // so near-empty content would collapse it - and the header overlays
            // the scroll view, so it would collapse with it
            content()
                .padding(.top, height + dimensions.spacing.space8)
                .frame(maxWidth: .infinity)
        }
        .overlay(alignment: .top) { HeaderOverlay }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { safeTop = $0 }
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { old, new in
            // anywhere near the top the header is always shown, so it can never
            // be stranded off screen with nothing left to scroll back through
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
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
            .offset(y: hidden ? -(height + safeTop) : 0)
            .opacity(hidden ? 0 : 1)
            // a header that is off screen must not keep catching taps
            .allowsHitTesting(!hidden)
            .animation(Layout.settle, value: hidden)
    }
}
