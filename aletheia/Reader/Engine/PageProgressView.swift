//
//  PageProgressView.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import UIKit

final class PageProgressView: UIView {
    private let track = CAShapeLayer()
    private let fill = CAShapeLayer()
    private let label = UILabel()

    private enum Layout {
        static let diameter: CGFloat = 64
        static let stroke: CGFloat = diameter * (16.0 / 140.0)
        static let text: CGFloat = diameter * (36.0 / 140.0)
        static let trackAlpha: CGFloat = 0.15
        static let threshold: TimeInterval = 0.15
        static let settle: CFTimeInterval = 0.25
    }

    private var reveal: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: Layout.diameter, height: Layout.diameter)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let inset = Layout.stroke / 2
        let path = UIBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset)).cgPath
        track.path = path
        fill.path = path
        track.frame = bounds
        fill.frame = bounds
    }

    // MARK: Interface

    // shown on a delay so an instantly-served page never flashes a ring
    func begin() {
        cancelReveal()
        set(0, animated: false)
        isHidden = true

        let reveal = DispatchWorkItem { [weak self] in
            self?.isHidden = false
        }
        self.reveal = reveal
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.threshold, execute: reveal)
    }

    func update(received: Int64, total: Int64) {
        guard total > 0 else { return }
        set(min(1, max(0, Double(received) / Double(total))), animated: true)
    }

    func end() {
        cancelReveal()
        isHidden = true
        set(0, animated: false)
    }

    // MARK: Private

    private func build() {
        isHidden = true
        isUserInteractionEnabled = false

        for layer in [track, fill] {
            layer.fillColor = UIColor.clear.cgColor
            layer.lineWidth = Layout.stroke
            layer.lineCap = .round
            self.layer.addSublayer(layer)
        }

        track.strokeColor = UIColor.secondaryLabel.withAlphaComponent(Layout.trackAlpha).cgColor
        fill.strokeColor = UIColor.label.cgColor
        fill.strokeEnd = 0
        // from twelve o'clock, clockwise - a ring that starts at three reads as
        // a decoration rather than a measure
        fill.transform = CATransform3DRotate(CATransform3DIdentity, -.pi / 2, 0, 0, 1)

        // UIKit needs a descriptor where SwiftUI takes `design: .rounded`
        // inline, and falls back to system if absent
        let base = UIFont.systemFont(ofSize: Layout.text, weight: .bold)
        label.font =
            base.fontDescriptor.withDesign(.rounded).map {
                UIFont(descriptor: $0, size: Layout.text)
            } ?? base
        label.textColor = .label
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    // the implicit CALayer animation is what smooths the fill: successive writes
    // coalesce on the same key rather than queueing, so the ring eases toward
    // each new value instead of stepping to it
    private func set(_ next: Double, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated { CATransaction.setAnimationDuration(Layout.settle) }
        fill.strokeEnd = next
        CATransaction.commit()

        label.text = "\(Int(next * 100))%"
    }

    private func cancelReveal() {
        reveal?.cancel()
        reveal = nil
    }
}
