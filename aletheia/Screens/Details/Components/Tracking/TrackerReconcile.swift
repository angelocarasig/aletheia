//
//  TrackerReconcile.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/2026.
//

import SwiftUI

// which way the sync is about to write, and how far. an enum rather than two
// booleans: both directions ask before they act, and one value is what keeps
// the two alerts in the same shape
enum TrackerReconcile: Equatable {
    // the service is further along: mark chapters read in this app
    case pull(Int)
    // this app is further along: send the number out to every linked service
    case push(Int)

    var chapter: Int {
        switch self {
        case let .pull(value), let .push(value): value
        }
    }
}

extension View {
    // the same confirmation from two places - the section banner and the manage
    // sheet - because the two offers write the same thing and the warnings are
    // the load-bearing part. a second copy of this wording is a second copy that
    // drifts, and what it would drift about is what a tap costs
    func trackerReconcile(
        _ pending: Binding<TrackerReconcile?>,
        subject: String,
        onCatchUp: @escaping (Int) -> Void,
        onPushLocal: @escaping () -> Void
    ) -> some View {
        modifier(
            TrackerReconcileAlert(
                pending: pending,
                subject: subject,
                onCatchUp: onCatchUp,
                onPushLocal: onPushLocal
            )
        )
    }
}

// subject is who the push lands on - one service by name, or "your trackers"
// where a series is linked to both. the pull side never needs it: marking read
// happens here, and which service suggested the number does not change that
private struct TrackerReconcileAlert: ViewModifier {
    @Binding var pending: TrackerReconcile?
    let subject: String
    let onCatchUp: (Int) -> Void
    let onPushLocal: () -> Void

    private var presented: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    private var title: String {
        switch pending {
        case let .pull(chapter): "Mark \(chapter) chapters read?"
        case let .push(chapter): "Update \(subject) to \(chapter)?"
        case nil: ""
        }
    }

    // both directions confirm, and both confirms are built from one value, so
    // they stay in step. what differs is what each costs: one writes history
    // that cannot be un-happened, the other writes a number that can be typed
    // back on the service's own site
    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: presented, presenting: pending) { reconcile in
                switch reconcile {
                case let .pull(chapter):
                    Button("Mark as Read", role: .destructive) {
                        onCatchUp(chapter)
                        pending = nil
                    }
                case .push:
                    Button("Update") {
                        onPushLocal()
                        pending = nil
                    }
                }

                Button("Cancel", role: .cancel) { pending = nil }
            } message: { reconcile in
                switch reconcile {
                case let .pull(chapter):
                    Text("Chapters 1 to \(chapter) are marked read across every source on this series, dated today. Unmarking them later will not remove them from your reading stats.")
                case let .push(chapter):
                    Text("Sends chapter \(chapter) to every service this series is linked to. You can change their entries back on their own websites.")
                }
            }
    }
}
