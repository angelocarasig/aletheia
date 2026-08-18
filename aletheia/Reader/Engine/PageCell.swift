//
//  PageCell.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import Kingfisher
import UIKit

final class PageCell: UICollectionViewCell {
    static let reuseIdentifier = "PageCell"

    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let progress = PageProgressView()
    private let failure = PageFailureView()

    // a cancelled load and a failed load arrive on the same completion path, so
    // the cell checks the url it is currently showing before reporting either -
    // without it, fast scrolling flashes "failed" over healthy pages
    private var token: URL?
    private var page: ReaderPage?
    private var width: CGFloat = .zero
    private var reportedZoom = false

    var onZoomChanged: ((Bool) -> Void)?
    var onSized: ((ReaderPage, CGSize) -> Void)?
    var onRetry: ((ReaderPage) -> Void)?
    var onShare: ((UIImage, ReaderPage) -> Void)?
    var onSave: ((UIImage) -> Void)?

    private enum Layout {
        static let minimumZoom: CGFloat = 1
        static let maximumZoom: CGFloat = 4
        static let doubleTapZoom: CGFloat = 2.5
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()

        imageView.kf.cancelDownloadTask()
        imageView.image = nil
        token = nil
        page = nil
        reportedZoom = false
        resetZoom()
        setFailure(nil)
        progress.end()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = contentView.bounds

        // reassigning the image frame unconditionally would wipe the transform
        // UIScrollView applies while zoomed, and layout runs whenever any other
        // cell finishes loading. only touch it at rest.
        //
        // the scale is compared with <= rather than == because an animated zoom
        // back to 1 settles a hair either side of it, and an equality test there
        // silently skips the reset for the rest of the cell's life
        guard !scrollView.isZooming, !scrollView.isZoomBouncing else { return }
        guard scrollView.zoomScale <= Layout.minimumZoom else { return }
        resetZoom()
    }

    func configure(with page: ReaderPage, width: CGFloat) {
        self.page = page
        self.width = width
        self.token = page.url

        setFailure(nil)
        progress.begin()

        imageView.kf.setImage(
            with: page.url,
            options: ReaderImage.options(
                headers: page.headers,
                width: width,
                scale: traitCollection.displayScale
            ),
            progressBlock: { [weak self] received, total in
                guard let self, self.token == page.url else { return }
                self.progress.update(received: received, total: total)
            }
        ) { [weak self] result in
            guard let self, self.token == page.url else { return }

            // ends unconditionally: a memory-cache hit completes synchronously
            // inside setImage, before any progress callback exists, so the ring
            // is driven off this one state rather than off progress events
            self.progress.end()

            switch result {
            case .success(let value):
                self.setFailure(nil)
                self.onSized?(page, value.image.size)
            case .failure(let error):
                // a reused cell cancelling its own load is not a failure the
                // reader should ever see
                guard !error.isTaskCancelled else { return }
                self.setFailure(ReaderPageError(error))
            }
        }
    }

    // MARK: Private

    private func build() {
        contentView.backgroundColor = .clear

        scrollView.delegate = self
        scrollView.minimumZoomScale = Layout.minimumZoom
        scrollView.maximumZoomScale = Layout.maximumZoom
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.isScrollEnabled = false
        scrollView.contentInsetAdjustmentBehavior = .never

        // both iOS 17.4+. the first stops a pan across a zoomed page from
        // flipping to the next one, the second centres undersized content -
        // together they replace hand-rolled gesture arbitration and centring
        scrollView.transfersHorizontalScrollingToParent = false
        scrollView.transfersVerticalScrollingToParent = false
        scrollView.contentAlignmentPoint = CGPoint(x: 0.5, y: 0.5)

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true

        contentView.addSubview(scrollView)
        scrollView.addSubview(imageView)

        progress.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progress)

        failure.translatesAutoresizingMaskIntoConstraints = false
        failure.onRetry = { [weak self] in self?.retry() }
        contentView.addSubview(failure)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        imageView.addGestureRecognizer(doubleTap)

        imageView.addInteraction(UIContextMenuInteraction(delegate: self))

        NSLayoutConstraint.activate([
            progress.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            progress.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            failure.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            failure.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            failure.topAnchor.constraint(equalTo: contentView.topAnchor),
            failure.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    private func setFailure(_ error: ReaderPageError?) {
        if let error { failure.configure(with: error) }
        failure.isHidden = error == nil
        imageView.isHidden = error != nil
    }

    // contentSize is set explicitly because the image view is positioned by
    // frame rather than by constraints, so the scroll view has nothing to infer
    // it from. left at zero it looks harmless until the first pinch, after which
    // every offset and centring calculation is against the wrong bounds
    private func resetZoom() {
        scrollView.setZoomScale(Layout.minimumZoom, animated: false)
        imageView.frame = CGRect(origin: .zero, size: scrollView.bounds.size)
        scrollView.contentSize = scrollView.bounds.size
        scrollView.contentOffset = .zero
        scrollView.isScrollEnabled = false
    }

    private func retry() {
        guard let page else { return }
        configure(with: page, width: width)
        onRetry?(page)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard !imageView.isHidden else { return }

        if scrollView.zoomScale > Layout.minimumZoom {
            scrollView.setZoomScale(Layout.minimumZoom, animated: true)
            return
        }

        let point = gesture.location(in: imageView)
        let size = CGSize(
            width: scrollView.bounds.width / Layout.doubleTapZoom,
            height: scrollView.bounds.height / Layout.doubleTapZoom
        )
        scrollView.zoom(
            to: CGRect(
                x: point.x - size.width / 2,
                y: point.y - size.height / 2,
                width: size.width,
                height: size.height
            ),
            animated: true
        )
    }
}

// MARK: - UIScrollViewDelegate

extension PageCell: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        let zoomed = scrollView.zoomScale > Layout.minimumZoom
        scrollView.isScrollEnabled = zoomed

        guard zoomed != reportedZoom else { return }
        reportedZoom = zoomed
        onZoomChanged?(zoomed)
    }

    // zooming all the way out has to put the page back where it started.
    // UIScrollView leaves the offset wherever the gesture ended, so without this
    // the image settles off-centre and stays there
    func scrollViewDidEndZooming(
        _ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat
    ) {
        guard scale <= Layout.minimumZoom else { return }
        resetZoom()
    }
}

// MARK: - UIContextMenuInteractionDelegate

extension PageCell: UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        // the decoded page, not its url: a source url is often signed, expires,
        // and needs the credential headers to fetch at all, so handing one to
        // another app gives them something that will not open
        guard !imageView.isHidden, let image = imageView.image, let page else { return nil }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.image = image
                },
                UIAction(
                    title: "Save to Photos", image: UIImage(systemName: "square.and.arrow.down")
                ) { _ in
                    self?.onSave?(image)
                },
                UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    self?.onShare?(image, page)
                },
            ])
        }
    }

    // the image view fills the cell and the page is drawn aspect-fit inside it,
    // so the default preview lifts the letterboxing with it - a portrait page on
    // a wide screen reads as a mostly-empty card
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        preview()
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        previewForDismissingMenuWithConfiguration configuration: UIContextMenuConfiguration
    ) -> UITargetedPreview? {
        preview()
    }

    private func preview() -> UITargetedPreview {
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(rect: drawn)
        return UITargetedPreview(view: imageView, parameters: parameters)
    }

    private var drawn: CGRect {
        let bounds = imageView.bounds
        guard let size = imageView.image?.size, size.width > 0, size.height > 0 else {
            return bounds
        }

        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)

        return CGRect(
            x: bounds.midX - fitted.width / 2,
            y: bounds.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}
