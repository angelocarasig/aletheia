//
//  SourceHomeScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 5/8/2026.
//

import SwiftUI

struct SourceHomeScreen: View {
    let source: Source
    let record: SourceRecord?

    @Environment(\.dimensions) private var dimensions
    @Environment(\.compositor) private var compositor
    @State private var vm: SourceHomeViewModel?
    @State private var searchPreset: SourcePreset?
    @State private var seriesRoute: SeriesStub?
    @State private var showingSearch = false

    private var presets: [SourcePreset] {
        source.presets.filter { !$0.hidden }.sorted { $0.order < $1.order }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                SourceHero(
                    source: source,
                    record: record,
                    entries: vm?.heroEntries ?? [],
                    isLoading: vm?.isLoadingHero ?? true
                )

                About
                    .padding(.horizontal, dimensions.screenMargin)

                ForEach(presets) { preset in
                    SourcePresetRow(
                        source: source,
                        preset: preset,
                        onOpen: { searchPreset = preset },
                        onOpenSeries: { seriesRoute = $0 }
                    )
                    .padding(.horizontal, dimensions.screenMargin)
                }
            }
            .padding(.bottom, dimensions.spacing.space24)
        }
        .ignoresSafeArea(.container, edges: .top)
        .navigationTitle(source.descriptor.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $searchPreset) { preset in
            SearchScreen(source: source, preset: preset)
        }
        .navigationDestination(item: $seriesRoute) { stub in
            DetailsScreen(entry: .source(sourceSlug: source.descriptor.slug, stub: stub))
        }
        .navigationDestination(isPresented: $showingSearch) {
            SearchScreen(source: source)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
            }

            // searching and configuring are unrelated - without the spacer they
            // share one glass capsule and read as a single control
            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    AppLog.shared.log("settings tapped for '\(source.descriptor.slug)'", category: "sources")
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .task {
            let vm = vm ?? SourceHomeViewModel(source: source, requester: compositor.requester)
            self.vm = vm
            await vm.loadCredential()
            await vm.loadHero()
        }
    }

    private var About: some View {
        HStack(spacing: dimensions.spacing.space8) {
            Pill(value: sourceHost, label: "Website", icon: "globe", color: .brand, url: source.descriptor.baseURL)
            Pill(value: languages, label: "Languages", icon: "character.book.closed.fill", color: .warning)
            Pill(value: hash, label: "Version", icon: "number", color: .success)
            if vm?.isAuthenticating == true {
                CredentialPill
            }
        }
    }

    private var CredentialPill: some View {
        let refreshing = vm?.isRefreshingCredential == true

        return PillCard(color: .danger) {
            PillIcon {
                if refreshing {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.danger)
                } else {
                    Image(systemName: "key.fill")
                        .font(.title3)
                        .foregroundStyle(.danger)
                }
            }

            PillValue(color: .danger) {
                if let expiry = vm?.credentialExpiry {
                    Text(timerInterval: Date.now...max(expiry, .now), countsDown: true)
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                } else {
                    Text("Active")
                }
            }

            PillLabel("Credentials")
        }
        .contentShape(.rect)
        .tappable { Task { await vm?.refreshCredential() } }
    }

    @ViewBuilder
    private func Pill(value: String, label: String, icon: String, color: Color, url: URL? = nil) -> some View {
        let content = PillCard(color: color) {
            PillIcon {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
            }
            PillValue { Text(value) }
            PillLabel(label)
        }

        if let url {
            Link(destination: url) { content }
        } else {
            content
        }
    }

    private func PillCard<Content: View>(color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: dimensions.spacing.space4) {
            content()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, dimensions.spacing.space12)
        .padding(.horizontal, dimensions.spacing.space4)
        .background(color.opacity(0.1))
        .clipShape(.rect(cornerRadius: dimensions.radius.radius12))
    }

    private func PillIcon<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(height: dimensions.size.icon24)
    }

    private func PillValue<Content: View>(color: Color = .primary, @ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private func PillLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.muted)
            .lineLimit(1)
    }

    private var sourceHost: String {
        source.descriptor.baseURL.host() ?? source.descriptor.baseURL.absoluteString
    }

    private var languages: String {
        let codes = source.descriptor.languages
        guard let first = codes.first else { return "All" }
        let remaining = codes.count - 1
        return remaining == 0 ? first.rawValue.uppercased() : "\(first.rawValue.uppercased()) +\(remaining)"
    }

    private var hash: String {
        String((record?.hash ?? source.descriptor.fingerprint).prefix(7))
    }
}
