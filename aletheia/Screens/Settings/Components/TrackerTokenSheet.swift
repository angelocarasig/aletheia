//
//  TrackerTokenSheet.swift
//  aletheia
//
//  Created by Angelo Carasig on 13/8/2026.
//

import SwiftUI

// signing in to a service that has no browser grant. a redirect proves a token by
// construction and a paste proves nothing, so this screen does the proving: the
// commit validates against the service and only a real account dismisses it.
//
// staged rather than instant-apply, which is the DetailsDisambiguation precedent -
// a commit that reaches a remote account confirms first.
// see docs/features/tracker-mangabaka.md §2.1
struct TrackerTokenSheet: View {
    let tracker: Tracker
    var onSubmit: (String) async -> Failure?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dimensions) private var dimensions

    @State private var token = ""
    @State private var saving = false
    @State private var reason: Failure?

    @FocusState private var focused: Bool

    private enum Layout {
        static let fillOpacity = 0.05
        static let tile: CGFloat = 44
    }

    // the prefix is the one thing that can be checked without spending a request,
    // so a wrong string is turned away at the field rather than at the service
    private var valid: Bool {
        token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .hasPrefix(Constants.Trackers.mangaBakaTokenPrefix)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: dimensions.spacing.space24) {
                    Header
                    Field
                    Steps
                }
                .padding(.horizontal, dimensions.screenMargin)
                .padding(.vertical, dimensions.spacing.space16)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .navigationTitle("Connect \(tracker.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .disabled(saving)
                }
            }
            .safeAreaInset(edge: .bottom) { Commit }
            .task { focused = true }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: Pieces

    private var Header: some View {
        HStack(spacing: dimensions.spacing.space12) {
            Image(tracker.icon)
                .resizable()
                .scaledToFit()
                .frame(width: Layout.tile, height: Layout.tile)
                .clipShape(.rect(cornerRadius: dimensions.radius.radius8, style: .continuous))

            // the asymmetry with the other two is the only thing here a reader
            // could not guess, so it is said once and plainly
            Text("\(tracker.name) doesn't offer a sign-in button. You create a token on their site and paste it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var Field: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            TextField("mb-...", text: $token, axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
                .lineLimit(2...4)
                .focused($focused)
                .disabled(saving)
                .padding(dimensions.spacing.space12)
                .background(
                    .primary.opacity(Layout.fillOpacity),
                    in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
                )
                // a failure belongs to the value that caused it, so typing clears
                // it rather than leaving a stale reason under a changed token
                .onChange(of: token) { reason = nil }

            // title, not message. Failure puts errorDescription in the first and
            // failureReason in the second, and for a rejection the second is a
            // fixed sentence about the service refusing - so reading message here
            // showed every failure as "The service refused the change" and buried
            // the one line that said what to do about it
            if let reason {
                Banner(
                    title: Text(reason.title),
                    message: reason.message.isEmpty ? nil : Text(reason.message),
                    systemImage: "exclamationmark.triangle",
                    tone: .danger
                )
            }
        }
    }

    private var Steps: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space8) {
            Text("Where to find it")
                .font(.footnote.weight(.medium))

            // the token lives in a tab of the settings page rather than at its own
            // address, so the link points at the page and the sentence names the
            // rest. a link that lands somewhere that does not exist is worse than
            // one step of reading
            Text("Open your MangaBaka account settings, create a token, and make sure it can write to your library. A read-only token can't record what you finish.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Link(destination: Constants.Trackers.mangaBakaSettings) {
                HStack(spacing: dimensions.spacing.space4) {
                    Text("Open account settings")
                    Image(systemName: "arrow.up.right")
                }
                .font(.caption.weight(.medium))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(dimensions.spacing.space12)
        .background(
            .primary.opacity(Layout.fillOpacity),
            in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
        )
    }

    private var Commit: some View {
        Text(saving ? "Checking" : "Connect")
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, dimensions.spacing.space12)
            .foregroundStyle(valid ? AnyShapeStyle(.onBrand) : AnyShapeStyle(.secondary))
            .background(
                valid ? AnyShapeStyle(.brand) : AnyShapeStyle(.primary.opacity(Layout.fillOpacity)),
                in: .rect(cornerRadius: dimensions.radius.radius12, style: .continuous)
            )
            .opacity(saving ? 0.6 : 1)
            .contentShape(.rect)
            .tappable { submit() }
            .disabled(!valid || saving)
            .padding(.horizontal, dimensions.screenMargin)
            .padding(.bottom, dimensions.spacing.space12)
    }

    // MARK: Commit

    private func submit() {
        guard valid, !saving else { return }

        Task {
            saving = true
            defer { saving = false }

            // nil is success. the sheet stays open on a failure so the token is
            // still there to correct - a dismiss would take the paste with it
            if let failure = await onSubmit(token.trimmingCharacters(in: .whitespacesAndNewlines)) {
                reason = failure
            } else {
                dismiss()
            }
        }
    }
}
