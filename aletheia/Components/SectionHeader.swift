//
//  SectionHeader.swift
//  aletheia
//
//  Created by Angelo Carasig on 6/8/2026.
//

import SwiftUI

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    @Environment(\.dimensions) private var dimensions

    var body: some View {
        HStack(spacing: dimensions.spacing.space8) {
            // the title takes the width it needs and the rule absorbs what is
            // left - a two-word heading wrapping while a decorative line keeps
            // its space is the wrong thing to have given room to
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .lineLimit(1)
                .layoutPriority(1)

            Rectangle()
                .fill(.primary.opacity(0.1))
                .frame(height: 1)

            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}
