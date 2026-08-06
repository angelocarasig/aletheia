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
            Text(title)
                .font(.title2)
                .fontWeight(.bold)

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
