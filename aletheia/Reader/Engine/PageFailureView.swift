//
//  PageFailureView.swift
//  aletheia
//
//  Created by Angelo Carasig on 9/8/2026.
//

import UIKit

// ContentUnavailableView's anatomy - glyph, title, message, action - built in
// UIKit rather than hosted. PageCell owns a real UIKit hierarchy (a zoomable
// scroll view and its gestures), so it cannot hand its contentConfiguration to
// SwiftUI the way SeparatorCell does without displacing that hierarchy
final class PageFailureView: UIView {
    private let glyph = UIImageView()
    private let title = UILabel()
    private let message = UILabel()
    private let action = UIButton(configuration: .bordered())
    private let stack = UIStackView()

    var onRetry: (() -> Void)?

    private enum Layout {
        static let glyphSize: CGFloat = 32
        static let messageWidth: CGFloat = 260
        static let messageLines = 3
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // the error names itself: title, sentence and whether retrying could change
    // the answer all come off the typed value, never off a message string
    func configure(with error: ReaderPageError) {
        title.text = error.errorDescription
        message.text = error.failureReason
        action.isHidden = !error.isRetryable
    }

    private func build() {
        isHidden = true

        glyph.image = UIImage(
            systemName: "exclamationmark.triangle",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: Layout.glyphSize)
        )
        glyph.tintColor = .secondaryLabel
        glyph.contentMode = .scaleAspectFit

        title.font = .preferredFont(forTextStyle: .headline)
        title.textColor = .label
        title.textAlignment = .center
        title.numberOfLines = 0

        message.font = .preferredFont(forTextStyle: .footnote)
        message.textColor = .secondaryLabel
        message.textAlignment = .center
        message.numberOfLines = Layout.messageLines

        action.configuration?.title = "Retry"
        action.configuration?.image = UIImage(systemName: "arrow.clockwise")
        action.configuration?.imagePadding = Dimensions.Spacing.space4
        action.addTarget(self, action: #selector(retry), for: .touchUpInside)

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = Dimensions.Spacing.space8
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(glyph)
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(message)
        stack.setCustomSpacing(Dimensions.Spacing.space16, after: message)
        stack.addArrangedSubview(action)
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            message.widthAnchor.constraint(lessThanOrEqualToConstant: Layout.messageWidth),
        ])
    }

    @objc private func retry() {
        onRetry?()
    }
}
