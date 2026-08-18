//
//  AutoScroller.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import UIKit

// UIUpdateLink rather than a timer: frame-synchronised, no drift, suspends with
// the app, and follows the display's actual refresh rate instead of assuming 60
@MainActor
final class AutoScroller {
    private weak var scrollView: UIScrollView?
    private var link: UIUpdateLink?
    private var lastTime: TimeInterval = 0
    private var mode: Orientation

    private(set) var isRunning = false
    private(set) var isPaused = false
    private(set) var speed: CGFloat

    var onReachedEnd: (() -> Void)?

    init(scrollView: UIScrollView, speed: CGFloat, mode: Orientation) {
        self.scrollView = scrollView
        self.speed = Self.clamp(speed)
        self.mode = mode
    }

    func start() {
        guard !isRunning, let scrollView else { return }

        isRunning = true
        isPaused = false
        lastTime = 0

        let link = UIUpdateLink(view: scrollView, actionTarget: self, selector: #selector(step))
        link.requiresContinuousUpdates = true
        link.isEnabled = true
        self.link = link
    }

    func stop() {
        guard isRunning else { return }
        link?.isEnabled = false
        link = nil
        isRunning = false
        isPaused = false
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        link?.isEnabled = false
    }

    func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
        // without this the first frame after a pause bills the whole pause as
        // elapsed time and the reader lurches forward by however long it sat
        lastTime = 0
        link?.isEnabled = true
    }

    func setSpeed(_ value: CGFloat) {
        speed = Self.clamp(value)
    }

    func setMode(_ value: Orientation) {
        mode = value
    }

    // MARK: Private

    @objc private func step(_ link: UIUpdateLink, _ info: UIUpdateInfo) {
        guard let scrollView, isRunning, !isPaused else { return }

        defer { lastTime = info.modelTime }
        guard lastTime > 0 else { return }

        let delta = info.modelTime - lastTime
        guard delta > 0 else { return }

        let distance = speed * delta
        var offset = scrollView.contentOffset

        switch mode.resolved {
        case .infinite, .vertical, .unknown:
            offset.y += distance
        case .leftToRight:
            offset.x += distance
        case .rightToLeft:
            offset.x -= distance
        }

        let clamped = clamp(offset, in: scrollView)
        if clamped == scrollView.contentOffset {
            stop()
            onReachedEnd?()
            return
        }

        scrollView.setContentOffset(clamped, animated: false)
    }

    private func clamp(_ offset: CGPoint, in scrollView: UIScrollView) -> CGPoint {
        let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)

        return CGPoint(
            x: min(max(0, offset.x), maxX),
            y: min(max(0, offset.y), maxY)
        )
    }

    private static func clamp(_ speed: CGFloat) -> CGFloat {
        min(
            max(ReaderConfiguration.Defaults.minAutoScrollSpeed, speed),
            ReaderConfiguration.Defaults.maxAutoScrollSpeed
        )
    }
}
