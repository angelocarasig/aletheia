//
//  TrackingScreen.swift
//  aletheia
//
//  Created by Angelo Carasig on 10/8/2026.
//

import SwiftUI
import AuthenticationServices

// one card per service, and never more than two. signing in is a once-ever act,
// which is why it lives behind settings rather than in a tab
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
            // signing out is not the only way a card changes: a token running
            // out moves the name, the sentence and the control at once, and none
            // of that is a change to the accounts dictionary
            .animation(.settle, value: compositor.trackers.needingSignIn)
        }
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .navigationTitle("Tracking")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            failure?.title ?? "",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure?.message ?? "")
        }
        .confirmationDialog(
            "Disconnect \(disconnecting?.name ?? "")?",
            isPresented: Binding(get: { disconnecting != nil }, set: { if !$0 { disconnecting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                guard let tracker = disconnecting else { return }
                Task { await compositor.trackers.signOut(tracker) }
            }
            Button("Cancel", role: .cancel) { disconnecting = nil }
        } message: {
            // nothing local is destroyed and the links survive a reconnect, so
            // the only cost is that pushes stop. said plainly, because the word
            // disconnect invites the reader to assume worse
            Text("Your links stay, and nothing is removed from your list. Progress just stops syncing until you sign in again.")
        }
        .sheet(item: $pasting) { tracker in
            TrackerTokenSheet(tracker: tracker) { token in
                do {
                    try await compositor.trackers.signIn(token: token, for: tracker)
                    return nil
                } catch {
                    // handed back rather than raised as an alert: the sheet is
                    // still open with the token in it, and an alert over a field
                    // that needs correcting is a message where a state belongs
                    return Failure(error, fallback: "Couldn't Connect")
                }
            }
        }
        .task { compositor.trackers.hydrate() }
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

    // one paragraph, once, rather than a footer under each card repeating half
    // of it. the asymmetry between the two services is the only thing here a
    // reader could not guess
    private var Explainer: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            Text("Chapters you finish are sent to your lists. Nothing is ever read back into your library without you asking.")

            Text("AniList connections run out after a year. Signing in again is normal, not a fault.")
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

    // one predicate for both services and both lifecycles, rather than this
    // screen deciding for itself what a dead account looks like
    private func expired(_ tracker: Tracker) -> Bool {
        compositor.trackers.needingSignIn.contains(tracker)
    }

    // MARK: Connect

    private func connect(_ tracker: Tracker) {
        guard connecting == nil else { return }

        // no browser grant for this one: the reader pastes a token, and the sheet
        // owns the whole attempt including its failures
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
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
                return
            } catch {
                failure = Failure(error, fallback: "Couldn't Connect")
            }
        }
    }
}

// MARK: - Card

// one account, as a view rather than a method on the screen: every state it can
// be in is then a set of values, so all four are visible in a preview without a
// keychain, a network, or waiting a year for a token to run out
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

    // the branch selector and the animation key are the same value, which is the
    // whole rule: keying a correlated boolean is how a swap goes dead or partial
    private enum Phase: Equatable {
        case disconnected
        case connecting
        case connected
        case needsSignIn
    }

    private var phase: Phase {
        if isConnecting { .connecting }
        else if account == nil { .disconnected }
        else if needsSignIn { .needsSignIn }
        else { .connected }
    }

    var body: some View {
        HStack(spacing: dimensions.spacing.space12) {
            // the brand tile, untinted - a logo recoloured to match its
            // surroundings stops being a logo
            Image(tracker.icon)
                .resizable()
                .frame(width: Layout.tile, height: Layout.tile)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius4))

            VStack(alignment: .leading, spacing: dimensions.spacing.space4) {
                // the name steps back when the account needs the reader, so the
                // amber line under it is the loudest thing in the row. a service
                // that cannot sync is not the heading it was a moment ago - and
                // the two lines at equal weight read as an ordinary row with an
                // odd subtitle rather than as something to act on
                Text(tracker.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(needsSignIn ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))

                State
            }

            Spacer(minLength: 0)

            Action
        }
        .frame(minHeight: dimensions.touchTarget)
        .animation(.settle, value: phase)
    }

    // three sentences in one slot. each branch fades rather than cutting, and
    // the container above carries the animation - a bare Group cannot host both
    // halves of a transition
    @ViewBuilder
    private var State: some View {
        if let account {
            if needsSignIn {
                // never "token expired". on one service this is a yearly
                // certainty and on the other a rarity, and the reader does not
                // care which produced it - only what to do about it
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
            // a symbol rather than a ProgressView, and not for looks: this slot
            // is a glyph the rest of the time, and a ProgressView has no stroke
            // for the outcome to draw out of when the sign-in lands
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
            // the same recipe as the details section's connect and its link
            // circle: regular interactive glass, shape following the content,
            // and a semantic foreground because glass vends its own
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

    // one construction for both glyphs this slot can hold, so the swap between
    // them replaces in place rather than crossfading two different images
    private func Glyph(_ name: String) -> some View {
        Image(systemName: name)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(width: dimensions.touchTarget, height: dimensions.touchTarget)
            .contentTransition(.symbolEffect(.replace))
    }
}

// MARK: - Previews

private extension TrackerCredential {
    static func sample(_ username: String = "angelo", refreshable: Bool = true) -> Self {
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

// the four states one account can be in. the third is the one that used to be
// unreachable without waiting a year, and it is the whole reason this row is a
// view rather than a method
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

// the screen itself, which reads the real keychain - a layout check rather than
// a state check, since what it shows is whatever this device is signed into
#Preview("Screen") {
    NavigationStack {
        TrackingScreen()
    }
}

// the states in motion, which is the only way to judge a transition - a static
// preview shows the endpoints and says nothing about the swap between them.
// tap through: connect, land, run out, disconnect
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
