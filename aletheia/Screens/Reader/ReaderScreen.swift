//
//  ReaderScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI
import Kingfisher

struct ReaderScreen: View {
    let source: Source
    let seriesSlug: String
    let chapterSlug: String
    let title: String

    @State private var pages: [PageURL] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.red).padding()
                }
                ForEach(pages, id: \.index) { page in
                    KFImage(page.url)
                        .requestModifier(AnyModifier.referer(source.descriptor.referer))
                        .resizable()
                        .placeholder {
                            Color.gray.opacity(0.1).frame(height: 300).overlay(ProgressView())
                        }
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .overlay { if isLoading { ProgressView() } }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }


    private func load() async {
        guard pages.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do { pages = try await source.content(seriesSlug: seriesSlug, chapterSlug: chapterSlug) }
        catch { errorText = String(describing: error) }
    }
}
