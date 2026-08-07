//
//  SeparatorCell.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI
import UIKit

// hosts the SwiftUI separator. configured on willDisplay rather than on dequeue
// so the model - and the direction inside it - is read fresh every time the
// boundary comes back on screen
final class SeparatorCell: UICollectionViewCell {
    static let reuseIdentifier = "SeparatorCell"

    var onRetry: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        contentConfiguration = nil
        onRetry = nil
    }

    func configure(with model: ReaderSeparatorModel) {
        contentConfiguration = UIHostingConfiguration {
            ReaderSeparatorView(model: model) { [weak self] in
                self?.onRetry?()
            }
        }
        // the view declares its own heights and the layout has already sized
        // this cell from them, so the default margins would double-count
        .margins(.all, 0)
    }
}
