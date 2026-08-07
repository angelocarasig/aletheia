//
//  ReaderController.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import UIKit

// one section per chapter, one item per page. sections are what make chapter
// insertion and eviction expressible without any index arithmetic - v2 kept a
// PageMapper translating a flat index space by hand, and the padding it wrote
// for double-page spreads landed on the wrong side of an appended chapter
@MainActor
final class ReaderController: UIViewController {
    typealias DataSource = UICollectionViewDiffableDataSource<ReaderChapter.ID, ReaderPage>
    typealias Snapshot = NSDiffableDataSourceSnapshot<ReaderChapter.ID, ReaderPage>

    enum Position {
        case start
        case end
    }

    private(set) var configuration: ReaderConfiguration

    private var collectionView: UICollectionView!
    private var dataSource: DataSource!
    private var autoScroller: AutoScroller?
    private var prefetcher: PagePrefetcher

    private var order: [ReaderChapter.ID] = []
    private var loaded: [ReaderChapter.ID] = []
    private var pages: [ReaderChapter.ID: [ReaderPage]] = [:]
    private var sizes: [ReaderPage: CGSize] = [:]

    // a chapter's pages share a shape far more often than not, so a handful of
    // real measurements predict the rest of it better than one global constant
    private var ratios: [ReaderChapter.ID: CGFloat] = [:]
    private var samples: [ReaderChapter.ID: [CGFloat]] = [:]

    // how far the offset must move once the pending batch lands, to hold the
    // page under the reader still while content above it changes height
    private var pendingOffsetAdjustment: CGFloat = 0

    private var pendingInvalidation = false
    private var isZoomed = false
    private var requestedNext = false
    private var requestedPrevious = false
    private var lastReportedPage: ReaderPage?

    var onVisiblePageChanged: ((ReaderPage, Int, Int) -> Void)?
    var onNeedsChapter: ((Position) -> Void)?
    var onSingleTap: ((CGPoint) -> Void)?
    var onZoomChanged: ((Bool) -> Void)?
    var onScrollingChanged: ((Bool) -> Void)?
    var onAutoScrollEnded: (() -> Void)?

    init(configuration: ReaderConfiguration) {
        self.configuration = configuration
        self.prefetcher = PagePrefetcher(count: configuration.prefetchCount, width: .zero)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildCollectionView()
        buildDataSource()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        collectionView.frame = view.bounds
    }

    // MARK: Content

    func setOrder(_ value: [ReaderChapter.ID]) {
        order = value
    }

    func apply(_ chapterPages: [ReaderPage], for chapter: ReaderChapter.ID) async {
        guard !chapterPages.isEmpty else { return }
        guard let slot = order.firstIndex(of: chapter) else { return }

        // land any outstanding size corrections first. the snapshot below runs
        // its own layout pass, which would otherwise realise them, fold them
        // into the delta measured here, and then apply them again on flush
        flushInvalidation()

        let prepending = loaded.contains { existing in
            (order.firstIndex(of: existing) ?? .max) > slot
        }

        pages[chapter] = chapterPages
        loaded.append(chapter)
        loaded.sort { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }

        // whatever the source knew goes in before the first layout pass, so
        // those pages are laid out right the first time and never correct.
        // read here rather than off the diffed identifier, which keeps the
        // instance it was first inserted with
        for page in chapterPages {
            guard let size = page.size, size.width > 0, size.height > 0 else { continue }
            sizes[page] = size
            learn(ratio: size.height / size.width, for: chapter)
        }

        // content inserted above the reader shifts everything below it by
        // exactly the height of what went in. capture first, restore after -
        // appending needs none of this because indices below never move
        let offset = collectionView.contentOffset
        let size = collectionView.contentSize
        let measured = chapterPages.filter { sizes[$0] != nil }.count

        // summed rather than read back off contentSize: the layout is a plain
        // stack, so this is exact, and it cannot absorb an unrelated height
        // change that slipped in across the await below
        let inserted = chapterPages.reduce(CGFloat.zero) {
            $0 + height(for: $1, width: pageWidth)
        }

        await applySnapshot(animated: false)

        if prepending {
            var restored = offset
            if configuration.mode.isVertical {
                restored.y += inserted
            } else {
                restored.x += inserted
            }
            setOffsetWithoutAnimation(restored)

            AppLog.shared.log(
                """
                prepend ch\(chapter): \(chapterPages.count) pages, \(measured) measured — \
                size \(Int(size.height))→\(Int(collectionView.contentSize.height)) \
                inserted \(Int(inserted)), \
                offset \(Int(offset.y))→\(Int(restored.y)), \
                settled at \(Int(collectionView.contentOffset.y))
                """,
                category: "reader.layout"
            )
        } else {
            AppLog.shared.log(
                "append ch\(chapter): \(chapterPages.count) pages, \(measured) measured",
                category: "reader.layout"
            )
        }

        resetPreloadRequests()
    }

    func remove(_ chapter: ReaderChapter.ID) async {
        guard pages[chapter] != nil else { return }
        flushInvalidation()

        pages[chapter]?.forEach { sizes[$0] = nil }
        pages[chapter] = nil
        loaded.removeAll { $0 == chapter }

        // ratios survive eviction on purpose. a chapter that comes back gets
        // its 70-odd estimates right on the first layout pass, so the prepend
        // delta is correct and the correction run never happens
        await applySnapshot(animated: false)
    }

    func clear() async {
        flushInvalidation()
        pendingOffsetAdjustment = 0

        pages.removeAll()
        sizes.removeAll()
        ratios.removeAll()
        samples.removeAll()
        loaded.removeAll()
        await applySnapshot(animated: false)
    }

    // MARK: Navigation

    func scroll(to chapter: ReaderChapter.ID, page index: Int, animated: Bool) {
        guard let chapterPages = pages[chapter], !chapterPages.isEmpty else { return }
        let clamped = min(max(0, index), chapterPages.count - 1)
        guard let path = dataSource.indexPath(for: chapterPages[clamped]) else { return }

        collectionView.scrollToItem(
            at: path,
            at: scrollAnchor,
            animated: animated
        )
    }

    func advance(by pages: Int) {
        guard let current = lastReportedPage,
              let path = dataSource.indexPath(for: current) else { return }

        if configuration.mode.isContinuous {
            scrollByViewport(forward: pages > 0)
            return
        }

        let flat = flatIndex(of: path)
        let target = flat + pages
        guard let next = page(atFlat: target), let path = dataSource.indexPath(for: next) else { return }

        collectionView.scrollToItem(at: path, at: scrollAnchor, animated: true)
    }

    // MARK: Configuration

    func update(_ value: ReaderConfiguration) {
        let modeChanged = value.mode.resolved != configuration.mode.resolved
        let paddingChanged = value.horizontalPadding != configuration.horizontalPadding

        configuration = value
        autoScroller?.setSpeed(value.autoScrollSpeed)
        autoScroller?.setMode(value.mode)
        prefetcher = PagePrefetcher(count: value.prefetchCount, width: pageWidth)

        guard modeChanged || paddingChanged else { return }

        // the accumulator is expressed in coordinates the new layout destroys,
        // so drain what is pending and drop the rest
        flushInvalidation()
        pendingOffsetAdjustment = 0

        // hold the page being read across the relayout. querying it first, then
        // restoring after the new layout settles, is the whole trick - reading
        // it afterwards returns a position in coordinates that no longer exist
        let anchor = lastReportedPage

        applySemantics()
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)
        collectionView.isPagingEnabled = configuration.mode.isPaged
        collectionView.layoutIfNeeded()

        if let anchor, let path = dataSource.indexPath(for: anchor) {
            collectionView.scrollToItem(at: path, at: scrollAnchor, animated: false)
        }
    }

    // MARK: Auto-scroll

    func startAutoScroll() {
        guard autoScroller == nil else { return }

        let scroller = AutoScroller(
            scrollView: collectionView,
            speed: configuration.autoScrollSpeed,
            mode: configuration.mode
        )
        scroller.onReachedEnd = { [weak self] in
            self?.autoScroller = nil
            self?.onAutoScrollEnded?()
        }
        scroller.start()
        autoScroller = scroller
    }

    func stopAutoScroll() {
        autoScroller?.stop()
        autoScroller = nil
    }

    var isAutoScrolling: Bool {
        autoScroller?.isRunning ?? false
    }

    // MARK: Private

    private var pageWidth: CGFloat {
        max(1, view.bounds.width - configuration.horizontalPadding * 2)
    }

    private var scrollAnchor: UICollectionView.ScrollPosition {
        configuration.mode.isVertical ? .top : .centeredHorizontally
    }

    private func buildCollectionView() {
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.isPagingEnabled = configuration.mode.isPaged
        collectionView.delegate = self
        collectionView.register(PageCell.self, forCellWithReuseIdentifier: PageCell.reuseIdentifier)
        applySemantics()

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        collectionView.addGestureRecognizer(tap)

        view.addSubview(collectionView)
        prefetcher = PagePrefetcher(count: configuration.prefetchCount, width: pageWidth)
    }

    private func applySemantics() {
        // right-to-left is one property. the collection view mirrors positions
        // and the cells come along with it
        collectionView.semanticContentAttribute = configuration.mode.isRightToLeft
            ? .forceRightToLeft
            : .forceLeftToRight
    }

    private func buildDataSource() {
        dataSource = DataSource(collectionView: collectionView) { [weak self] collectionView, indexPath, page in
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: PageCell.reuseIdentifier,
                for: indexPath
            )
            guard let cell = cell as? PageCell, let self else { return cell }

            cell.onZoomChanged = { [weak self] zoomed in
                self?.setZoomed(zoomed)
            }
            cell.onSized = { [weak self] page, size in
                self?.record(size: size, for: page)
            }
            cell.onRetry = { page in
                AppLog.shared.log(
                    "retrying ch\(page.chapter) p\(page.index)",
                    category: "reader"
                )
            }
            cell.configure(with: page, width: self.pageWidth)
            return cell
        }
    }

    private func applySnapshot(animated: Bool) async {
        var snapshot = Snapshot()
        snapshot.appendSections(loaded)
        for chapter in loaded {
            snapshot.appendItems(pages[chapter] ?? [], toSection: chapter)
        }
        await dataSource.apply(snapshot, animatingDifferences: animated)
    }

    private func setOffsetWithoutAnimation(_ offset: CGPoint) {
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            collectionView.setContentOffset(offset, animated: false)
            CATransaction.commit()
        }
    }

    private func setZoomed(_ zoomed: Bool) {
        guard zoomed != isZoomed else { return }
        isZoomed = zoomed
        collectionView.isScrollEnabled = !zoomed
        if zoomed { stopAutoScroll() }
        onZoomChanged?(zoomed)
    }

    private func record(size: CGSize, for page: ReaderPage) {
        guard size.width > 0, size.height > 0 else { return }
        guard sizes[page] != size else { return }

        // a chapter evicted while its image was in flight must not repopulate
        // the caches it was just cleaned out of
        guard pages[page.chapter] != nil else { return }

        guard configuration.mode.isContinuous else {
            // paged modes size every cell to the viewport, so a real ratio
            // changes nothing. still worth banking for a later mode switch
            sizes[page] = size
            learn(ratio: size.height / size.width, for: page.chapter)
            return
        }

        let width = pageWidth
        let flat = flatPages()

        // measured against where the reader will BE once the pending batch
        // flushes, not where it is now - sizes already holds this batch's
        // earlier corrections while the layout has yet to re-run, so anything
        // else would double-count them
        let target = collectionView.contentOffset.y + pendingOffsetAdjustment
        let held = anchor(at: target, in: flat, width: width)

        let estimated = height(for: page, width: width)
        sizes[page] = size
        learn(ratio: size.height / size.width, for: page.chapter)
        let actual = height(for: page, width: width)

        if let held {
            let moved = position(of: held, in: flat, width: width) - target
            pendingOffsetAdjustment += moved

            if abs(actual - estimated) > 1 || abs(moved) > 1 {
                AppLog.shared.log(
                    "resize ch\(page.chapter) p\(page.index): \(Int(estimated))→\(Int(actual)) "
                        + "Δ\(Int(actual - estimated)), anchor moved \(Int(moved)), "
                        + "pending \(Int(pendingOffsetAdjustment))",
                    category: "reader.layout"
                )
            }
        }

        scheduleInvalidation()
    }

    private func scheduleInvalidation() {
        // coalesced: a chapter's images land within a few frames of each other
        // and v2 ran a full invalidation, inside a 0.3s animation, for each one
        guard !pendingInvalidation else { return }
        pendingInvalidation = true

        Task { @MainActor [weak self] in
            self?.flushInvalidation()
        }
    }

    // synchronous so structural changes can drain it before they measure - an
    // insertion that runs its own layout pass would otherwise absorb these
    // corrections and then have them applied a second time
    private func flushInvalidation() {
        guard pendingInvalidation else { return }
        pendingInvalidation = false

        let adjustment = pendingOffsetAdjustment
        pendingOffsetAdjustment = 0

        let before = collectionView.contentSize
        let offset = collectionView.contentOffset

        let layout = collectionView.collectionViewLayout
        let context = FullInvalidationContext()
        // handing the delta to UIKit rather than setting contentOffset means the
        // move lands inside the same layout pass, so a fling keeps flowing.
        // setting it directly stops deceleration dead, ten times in six seconds
        context.contentOffsetAdjustment = CGPoint(x: 0, y: adjustment)
        layout.invalidateLayout(with: context)
        collectionView.layoutIfNeeded()

        // if the context is honoured this is zero. a hard offset set would kill
        // an in-flight fling, so mid-deceleration we accept the drift instead
        let residual = (offset.y + adjustment) - collectionView.contentOffset.y
        if abs(residual) > 1, !collectionView.isDecelerating {
            setOffsetWithoutAnimation(
                CGPoint(
                    x: collectionView.contentOffset.x,
                    y: max(0, collectionView.contentOffset.y + residual)
                )
            )
        }

        let after = collectionView.contentSize
        let settled = collectionView.contentOffset
        guard abs(after.height - before.height) > 1 || abs(settled.y - offset.y) > 1 else { return }

        AppLog.shared.log(
            "invalidate: size \(Int(before.height))→\(Int(after.height)), "
                + "offset \(Int(offset.y))→\(Int(settled.y)), "
                + "adjust \(Int(adjustment)), residual \(Int(residual))",
            category: "reader.layout"
        )
    }

    private func learn(ratio: CGFloat, for chapter: ReaderChapter.ID) {
        guard ratio.isFinite, ratio > 0 else { return }

        var seen = samples[chapter, default: []]
        guard seen.count < ReaderConfiguration.Defaults.ratioSampleCap else { return }
        seen.append(ratio)
        samples[chapter] = seen

        guard seen.count >= ReaderConfiguration.Defaults.ratioSampleMinimum else { return }
        // median, so one spread among portrait pages cannot drag every estimate
        let sorted = seen.sorted()
        ratios[chapter] = sorted[sorted.count / 2]
    }

    private func height(for page: ReaderPage, width: CGFloat) -> CGFloat {
        if let size = sizes[page], size.width > 0 {
            return width * (size.height / size.width)
        }
        return width * (ratios[page.chapter] ?? configuration.mode.fallbackPageRatio)
    }

    // MARK: Geometry

    // where the reader is holding, expressed as a page plus how much of it sits
    // above the fold. a page straddling the edge only moves the art by the part
    // above it, so the fraction is what keeps that page still rather than the
    // ones below it
    private struct Anchor {
        let index: Int
        let fraction: CGFloat
    }

    private func flatPages() -> [ReaderPage] {
        loaded.flatMap { pages[$0] ?? [] }
    }

    private func anchor(at y: CGFloat, in flat: [ReaderPage], width: CGFloat) -> Anchor? {
        guard !flat.isEmpty else { return nil }

        var top: CGFloat = 0
        for (index, page) in flat.enumerated() {
            let extent = height(for: page, width: width)
            if y < top + extent || index == flat.count - 1 {
                let fraction = extent > 0 ? (y - top) / extent : 0
                return Anchor(index: index, fraction: min(max(0, fraction), 1))
            }
            top += extent
        }
        return Anchor(index: flat.count - 1, fraction: 1)
    }

    private func position(of anchor: Anchor, in flat: [ReaderPage], width: CGFloat) -> CGFloat {
        guard anchor.index < flat.count else { return 0 }

        var top: CGFloat = 0
        for page in flat.prefix(anchor.index) {
            top += height(for: page, width: width)
        }
        return top + height(for: flat[anchor.index], width: width) * anchor.fraction
    }

    private func flatIndex(of path: IndexPath) -> Int {
        let before = loaded.prefix(path.section).reduce(0) { $0 + (pages[$1]?.count ?? 0) }
        return before + path.item
    }

    private func page(atFlat index: Int) -> ReaderPage? {
        guard index >= 0 else { return nil }
        var remaining = index
        for chapter in loaded {
            let chapterPages = pages[chapter] ?? []
            if remaining < chapterPages.count { return chapterPages[remaining] }
            remaining -= chapterPages.count
        }
        return nil
    }

    private func scrollByViewport(forward: Bool) {
        let step = collectionView.bounds.height * 0.9
        var offset = collectionView.contentOffset
        offset.y += forward ? step : -step
        offset.y = min(
            max(0, offset.y),
            max(0, collectionView.contentSize.height - collectionView.bounds.height)
        )
        collectionView.setContentOffset(offset, animated: true)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard !isZoomed else { return }
        // window space, so a zone stays where the user sees it rather than
        // moving with the content underneath
        onSingleTap?(gesture.location(in: nil))
    }

    private func resetPreloadRequests() {
        requestedNext = false
        requestedPrevious = false
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let mode = configuration.mode
        let padding = configuration.horizontalPadding

        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = mode.isVertical ? .vertical : .horizontal

        return UICollectionViewCompositionalLayout(
            sectionProvider: { [weak self] index, environment in
                guard let self, index < self.loaded.count else { return nil }
                let chapter = self.loaded[index]
                let chapterPages = self.pages[chapter] ?? []
                guard !chapterPages.isEmpty else { return nil }

                if mode.isPaged {
                    return Self.pagedSection(count: chapterPages.count, environment: environment)
                }

                return self.continuousSection(
                    pages: chapterPages,
                    padding: padding,
                    environment: environment
                )
            },
            configuration: configuration
        )
    }

    private static func pagedSection(
        count: Int,
        environment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection {
        let size = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .fractionalHeight(1)
        )
        let item = NSCollectionLayoutItem(layoutSize: size)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
        return NSCollectionLayoutSection(group: group)
    }

    // exact frames rather than estimates. the content size is therefore always
    // correct, which is what lets a prepend be compensated by a size delta
    private func continuousSection(
        pages chapterPages: [ReaderPage],
        padding: CGFloat,
        environment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection {
        let containerWidth = environment.container.effectiveContentSize.width
        let width = max(1, containerWidth - padding * 2)
        let heights = chapterPages.map { height(for: $0, width: width) }
        let total = heights.reduce(0, +)

        let group = NSCollectionLayoutGroup.custom(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(max(1, total))
            )
        ) { _ in
            var y: CGFloat = 0
            return heights.map { height in
                let frame = CGRect(x: padding, y: y, width: width, height: height)
                y += height
                return NSCollectionLayoutGroupCustomItem(frame: frame)
            }
        }

        return NSCollectionLayoutSection(group: group)
    }
}

// MARK: - UICollectionViewDelegate

extension ReaderController: UICollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        reportVisiblePage()
        checkProximity()
        updatePrefetch()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // any touch beats the machine. auto-scroll never fights the user
        stopAutoScroll()
        onScrollingChanged?(true)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard !decelerate else { return }
        onScrollingChanged?(false)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        onScrollingChanged?(false)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        onScrollingChanged?(false)
    }

    // MARK: Private

    private func reportVisiblePage() {
        guard let page = centremostPage() else { return }
        guard page != lastReportedPage else { return }
        lastReportedPage = page

        let chapterPages = pages[page.chapter] ?? []
        guard let index = chapterPages.firstIndex(of: page) else { return }
        onVisiblePageChanged?(page, index, chapterPages.count)
    }

    private func centremostPage() -> ReaderPage? {
        let visible = collectionView.indexPathsForVisibleItems
        guard !visible.isEmpty else { return nil }

        let vertical = configuration.mode.isVertical
        let centre = vertical
            ? collectionView.contentOffset.y + collectionView.bounds.height / 2
            : collectionView.contentOffset.x + collectionView.bounds.width / 2

        var best: (path: IndexPath, distance: CGFloat)?
        for path in visible {
            guard let attributes = collectionView.layoutAttributesForItem(at: path) else { continue }
            let mid = vertical ? attributes.frame.midY : attributes.frame.midX
            let distance = abs(mid - centre)
            if best == nil || distance < best!.distance {
                best = (path, distance)
            }
        }

        guard let best else { return nil }
        return dataSource.itemIdentifier(for: best.path)
    }

    // state-driven rather than debounced on a clock: the request fires when the
    // reader crosses into the threshold and re-arms only once it leaves
    private func checkProximity() {
        let threshold = configuration.preloadThreshold
        let vertical = configuration.mode.isVertical

        let offset = vertical ? collectionView.contentOffset.y : collectionView.contentOffset.x
        let extent = vertical ? collectionView.bounds.height : collectionView.bounds.width
        let content = vertical ? collectionView.contentSize.height : collectionView.contentSize.width

        let fromStart = offset
        let fromEnd = content - (offset + extent)

        if fromEnd < threshold {
            if !requestedNext {
                requestedNext = true
                onNeedsChapter?(.end)
            }
        } else {
            requestedNext = false
        }

        if fromStart < threshold {
            if !requestedPrevious {
                requestedPrevious = true
                onNeedsChapter?(.start)
            }
        } else {
            requestedPrevious = false
        }
    }

    private func updatePrefetch() {
        let flat = loaded.flatMap { pages[$0] ?? [] }
        guard !flat.isEmpty else { return }

        let visible = collectionView.indexPathsForVisibleItems
            .compactMap { dataSource.itemIdentifier(for: $0) }
            .compactMap { flat.firstIndex(of: $0) }

        guard let lower = visible.min(), let upper = visible.max() else { return }
        prefetcher.update(visible: lower..<(upper + 1), in: flat)
    }
}

// MARK: - Invalidation

// invalidateEverything is read-only on the base class - it is what UIKit sets
// for a bare invalidateLayout(). the section provider bakes each chapter's
// heights into an absolute group size, so anything less than a full
// invalidation reuses cached sections and the new measurements never land
private final class FullInvalidationContext: UICollectionViewLayoutInvalidationContext {
    override var invalidateEverything: Bool { true }
}
