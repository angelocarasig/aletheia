//
//  TrackerReconcile.swift
//  aletheia
//
//  Created by Angelo Carasig on 14/8/2026.
//

import SwiftUI

enum TrackerReconcile: Equatable {
    case pull(Int)
    case push(Int)

    var chapter: Int {
        switch self {
        case .pull(let value), .push(let value): value
        }
    }
}

extension View {
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
        case .pull(let chapter): "Mark \(chapter) chapters read?"
        case .push(let chapter): "Update \(subject) to \(chapter)?"
        case nil: ""
        }
    }

    // pull is .destructive, push is not - a pull writes read history that
    // cannot be un-happened, a push writes a number the reader can just
    // retype on the service's own site
    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: presented, presenting: pending) { reconcile in
                switch reconcile {
                case .pull(let chapter):
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
                case .pull(let chapter):
                    Text(
                        "Chapters 1 to \(chapter) are marked read across every source on this series, dated today. Unmarking them later will not remove them from your reading stats."
                    )
                case .push(let chapter):
                    Text(
                        "Sends chapter \(chapter) to every service this series is linked to. You can change their entries back on their own websites."
                    )
                }
            }
    }
}
