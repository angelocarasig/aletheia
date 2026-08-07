//
//  AutoAdvancer.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import UIKit

// the paged counterpart to AutoScroller. a paged collection view snaps whole
// pages, so creeping the offset drags a page part-way across and lets paging
// pull it back - what a page mode wants is a dwell and then one clean slide.
//
// same UIUpdateLink for the same reasons: frame-synchronised, no timer drift,
// suspends with the app
@MainActor
final class AutoAdvancer {
    private weak var view: UIView?
    private var link: UIUpdateLink?
    private var lastTime: TimeInterval = 0
    private var elapsed: TimeInterval = 0
    private var published: Double = 1

    private(set) var isRunning = false
    private(set) var interval: TimeInterval

    // return false to stop. failing to move is not on its own a reason to -
    // the next chapter may simply still be loading - so the decision belongs to
    // whoever knows the chapter list
    var onFire: (() -> Bool)?
    var onProgress: ((Double) -> Void)?
    var onReachedEnd: (() -> Void)?

    // the bar has nowhere near a frame's worth of distinguishable positions, so
    // publishing every frame would be a hundred-odd wasted observations a second
    private enum Publish {
        static let steps: Double = 200
    }

    init(view: UIView, interval: TimeInterval) {
        self.view = view
        self.interval = Self.clamp(interval)
    }

    func start() {
        guard !isRunning, let view else { return }

        isRunning = true
        lastTime = 0
        elapsed = 0
        publish(1)

        let link = UIUpdateLink(view: view, actionTarget: self, selector: #selector(step))
        link.requiresContinuousUpdates = true
        link.isEnabled = true
        self.link = link
    }

    func stop() {
        guard isRunning else { return }
        link?.isEnabled = false
        link = nil
        isRunning = false
        lastTime = 0
        elapsed = 0
        publish(1)
    }

    func reset() {
        guard isRunning else { return }
        lastTime = 0
        elapsed = 0
        publish(1)
    }

    func setInterval(_ value: TimeInterval) {
        interval = Self.clamp(value)
        reset()
    }

    // MARK: Private

    @objc private func step(_ link: UIUpdateLink, _ info: UIUpdateInfo) {
        guard isRunning else { return }

        defer { lastTime = info.modelTime }
        guard lastTime > 0 else { return }

        let delta = info.modelTime - lastTime
        guard delta > 0 else { return }

        elapsed += delta

        guard elapsed >= interval else {
            publish(1 - elapsed / interval)
            return
        }

        elapsed = 0
        publish(1)

        guard onFire?() == false else { return }
        onReachedEnd?()
    }

    private func publish(_ value: Double) {
        let clamped = min(max(0, value), 1)
        let quantised = (clamped * Publish.steps).rounded() / Publish.steps
        guard quantised != published else { return }
        published = quantised
        onProgress?(quantised)
    }

    private static func clamp(_ value: TimeInterval) -> TimeInterval {
        min(
            max(ReaderConfiguration.Defaults.minAutoAdvanceInterval, value),
            ReaderConfiguration.Defaults.maxAutoAdvanceInterval
        )
    }
}
