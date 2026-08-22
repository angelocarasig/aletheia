//
//  TrackingScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import AuthenticationServices
import SwiftUI

struct TrackingScreen: View {
    @Environment(\.compositor) private var compositor
    @Environment(\.dimensions) private var dimensions
    @Environment(\.webAuthenticationSession) private var session

    @State private var connecting: Tracker?
    @State private var failure: Failure?
    @State private var disconnecting: Tracker?
    @State private var pasting: Tracker?

    private enum Layout {
        static let tile: CGFloat = 36
        static let fillOpacity = 0.05
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                VStack(alignment: .leading, spacing: dimensions.spacing.space16) {
                    SectionHeader("Accounts")

                    ForEach(Tracker.allCases) { tracker in
                        Card(tracker)
                    }
                }

                Explainer
            }
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.vertical, dimensions.spacing.space16)
            .animation(.settle, value: compositor.trackers.accounts)
            // needingSignIn changes independently of accounts, so it needs its own animation trigger
            .animation(.settle, value: compositor.trackers.needingSignIn)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .navigationTitle("Tracking")
        .navigationSubtitle(connected ?? "Not connected")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            failure?.title ?? "",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure?.message ?? "")
        }
        .alert(
            "Disconnect \(disconnecting?.name ?? "")?",
            isPresented: Binding(
                get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } })
        ) {
            Button("Disconnect", role: .destructive) {
                guard let tracker = disconnecting else { return }
                Task { await compositor.trackers.signOut(tracker) }
            }
            Button("Cancel", role: .cancel) { disconnecting = nil }
        } message: {
            Text(
                "Your links stay, and nothing is removed from your list. Progress just stops syncing until you sign in again."
            )
        }
        .sheet(item: $pasting) { tracker in
            TrackerTokenSheet(tracker: tracker) { token in
                do {
                    try await compositor.trackers.signIn(token: token, for: tracker)
                    return nil
                } catch {
                    // returned, not routed to the failure alert - the sheet stays open with the token
                    return Failure(error, fallback: "Couldn't Connect")
                }
            }
        }
        .task { compositor.trackers.hydrate() }
    }

    private var connected: String? {
        let accounts = compositor.trackers.accounts.keys
        guard !accounts.isEmpty else { return nil }
        return Tracker.allCases
            .filter { accounts.contains($0) }
            .map(\.name)
            .joined(separator: " · ")
    }

    // MARK: Row

    private func Card(_ tracker: Tracker) -> some View {
        TrackingCard(
            tracker: tracker,
            account: compositor.trackers.accounts[tracker],
            needsSignIn: expired(tracker),
            isConnecting: connecting == tracker,
            onConnect: { connect(tracker) },
            onDisconnect: { disconnecting = tracker }
        )
    }

    private var Explainer: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            Text(
                "Chapters you finish are sent to your lists. Nothing is ever read back into your library without you asking."
            )

            Text(
                "AniList connections run out after a year. Signing in again is normal, not a fault."
            )
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(dimensions.spacing.space12)
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
    }

    private func expired(_ tracker: Tracker) -> Bool {
        compositor.trackers.needingSignIn.contains(tracker)
    }

    // MARK: Connect

    private func connect(_ tracker: Tracker) {
        guard connecting == nil else { return }

        guard !tracker.usesPastedToken else {
            pasting = tracker
            return
        }

        Task {
            connecting = tracker
            defer { connecting = nil }

            do {
                let authorization = try compositor.trackers.authorization(for: tracker)
                let callback = try await session.authenticate(
                    using: authorization.url,
                    callback: .customScheme(Constants.Trackers.scheme),
                    preferredBrowserSession: nil,
                    additionalHeaderFields: [:]
                )
                try await compositor.trackers.complete(callback, with: authorization)
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin
            {
                return
            } catch {
                failure = Failure(error, fallback: "Couldn't Connect")
            }
        }
    }
}

// MARK: - Card

private struct TrackingCard: View {
    let tracker: Tracker
    let account: TrackerCredential?
    let needsSignIn: Bool
    let isConnecting: Bool
    var onConnect: () -> Void
    var onDisconnect: () -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let tile: CGFloat = 36
    }

    private enum Phase: Equatable {
        case disconnected
        case connecting
        case connected
        case needsSignIn
    }

    private var phase: Phase {
        if isConnecting {
            .connecting
        } else if account == nil {
            .disconnected
        } else if needsSignIn {
            .needsSignIn
        } else {
            .connected
        }
    }

    var body: some View {
        HStack(spacing: dimensions.spacing.space12) {
            Image(tracker.icon)
                .resizable()
                .frame(width: Layout.tile, height: Layout.tile)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius4))

            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                Text(tracker.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        needsSignIn ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))

                State
            }

            Spacer(minLength: 0)

            Action
        }
        .frame(minHeight: dimensions.touchTarget)
        .animation(.settle, value: phase)
    }

    // .animation(value: phase) lives on the parent HStack, not here - a bare Group
    // (the implicit @ViewBuilder container) can't host a transition itself
    @ViewBuilder
    private var State: some View {
        if let account {
            if needsSignIn {
                Text("Sign in again to keep tracking")
                    .font(.caption)
                    .foregroundStyle(Palette.warningText)
                    .transition(.opacity)
            } else {
                Text(account.username)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        } else {
            Text("Not connected")
                .font(.caption)
                .foregroundStyle(.muted)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var Action: some View {
        if isConnecting {
            // a symbol, not ProgressView - needs to morph into the outcome glyph via contentTransition
            Glyph("progress.indicator")
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: !reduceMotion)
                .transition(.opacity)
        } else if account != nil {
            Menu {
                Button("Sign In Again", action: onConnect)
                Button("Disconnect", role: .destructive, action: onDisconnect)
            } label: {
                Glyph("ellipsis")
                    .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .transition(.opacity)
        } else {
            Text("Connect")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .padding(.horizontal, dimensions.spacing.space16)
                .frame(height: dimensions.touchTarget)
                .glassEffect(.regular.interactive(), in: .capsule)
                .contentShape(.capsule)
                .tappable(action: onConnect)
                .accessibilityLabel("Connect \(tracker.name)")
                .transition(.opacity)
        }
    }

    // one Image construction for both glyphs - keeps view identity stable so
    // .symbolEffect(.replace) morphs in place instead of crossfading two views
    private func Glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(width: dimensions.touchTarget, height: dimensions.touchTarget)
            .contentTransition(.symbolEffect(.replace))
    }
}

// MARK: - Previews

extension TrackerCredential {
    fileprivate static func sample(_ username: String = "angelo", refreshable: Bool = true) -> Self
    {
        .init(
            accessToken: "token",
            refreshToken: refreshable ? "refresh" : nil,
            expiresDate: .now.addingTimeInterval(60 * 60 * 24 * 30),
            username: username,
            avatar: nil,
            scoreFormat: .point10
        )
    }
}

#Preview("Account states") {
    NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Group {
                    TrackingCard(
                        tracker: .anilist,
                        account: nil,
                        needsSignIn: false,
                        isConnecting: false,
                        onConnect: {},
                        onDisconnect: {}
                    )

                    TrackingCard(
                        tracker: .anilist,
                        account: .sample(),
                        needsSignIn: false,
                        isConnecting: false,
                        onConnect: {},
                        onDisconnect: {}
                    )

                    TrackingCard(
                        tracker: .anilist,
                        account: .sample(refreshable: false),
                        needsSignIn: true,
                        isConnecting: false,
                        onConnect: {},
                        onDisconnect: {}
                    )

                    TrackingCard(
                        tracker: .myAnimeList,
                        account: nil,
                        needsSignIn: false,
                        isConnecting: true,
                        onConnect: {},
                        onDisconnect: {}
                    )
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 16)
        }
        .navigationTitle("Tracking")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// reads the real keychain, not mock data - not deterministic across devices
#Preview("Screen") {
    NavigationStack {
        TrackingScreen()
    }
}

#Preview("States - live") {
    @Previewable @State var account: TrackerCredential?
    @Previewable @State var needsSignIn = false
    @Previewable @State var isConnecting = false

    NavigationStack {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TrackingCard(
                    tracker: .anilist,
                    account: account,
                    needsSignIn: needsSignIn,
                    isConnecting: isConnecting,
                    onConnect: {
                        isConnecting = true
                        Task {
                            try? await Task.sleep(for: .seconds(1))
                            isConnecting = false
                            needsSignIn = false
                            account = .sample()
                        }
                    },
                    onDisconnect: {
                        account = nil
                        needsSignIn = false
                    }
                )

                Divider()

                Button("Run the token out") { needsSignIn = true }
                    .disabled(account == nil)

                Button("Sign out") {
                    account = nil
                    needsSignIn = false
                }
                .disabled(account == nil)
            }
            .padding(16)
        }
        .navigationTitle("Tracking")
        .navigationBarTitleDisplayMode(.inline)
    }
}
