//
//  ReaderController.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import UIKit
import Photos

// one section per chapter, one item per page. sections are what make chapter
// insertion and eviction expressible without any index arithmetic
@MainActor
final class ReaderController: UIViewController {
    typealias DataSource = UICollectionViewDiffableDataSource<ReaderChapter.ID, ReaderItem>
    typealias Snapshot = NSDiffableDataSourceSnapshot<ReaderChapter.ID, ReaderItem>

    enum Position {
        case start
        case end
    }

    private enum Nudge {
        static let factor: CGFloat = 0.9
    }

    private(set) var configuration: ReaderConfiguration

    private var collectionView: UICollectionView!
    private var dataSource: DataSource!
    private var autoScroller: AutoScroller?
    private var autoAdvancer: AutoAdvancer?
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

    // separator heights are cached rather than recomputed, because extent() runs
    // inside every geometry walk
    private var separatorExtents: [ReaderBoundary: CGFloat] = [:]
    private var separatorDirections: [ReaderBoundary: ReadingDirection] = [:]

    // reading order decides direction, so the last position is kept rather than
    // the last offset - coordinates cannot answer this under right-to-left
    private(set) var lastDirection: ReadingDirection = .forward

    private var pendingInvalidation = false
    private var isZoomed = false
    private var requestedNext = false
    private var requestedPrevious = false
    private var lastReportedPage: ReaderPage?

    // a depth counter, not a flag. mid-mutation the reader momentarily sits
    // somewhere it never read - a snapshot apply lays out at the pre-restore
    // offset, a remove shrinks contentSize past the offset so UIScrollView
    // clamps - and every one of those dispatches scrollViewDidScroll
    private var mutations = 0

    var onVisiblePageChanged: ((ReaderPage, Int, Int) -> Void)?
    // the engine owns what a boundary means; the controller only renders it
    var separatorModel: ((ReaderBoundary, ReadingDirection) -> ReaderSeparatorModel)?
    var onSeparatorReached: ((ReaderBoundary, ReadingDirection) -> Void)?
    var onSeparatorRetry: ((ReaderBoundary) -> Void)?
    var onSeparatorRetryTracker: ((ReaderBoundary, String) -> Void)?
    var onSeparatorComplete: (() -> Void)?
    var onSeparatorGap: ((ReaderSeparatorModel.Gap) -> Void)?
    var onNeedsChapter: ((Position) -> Void)?
    var onSingleTap: ((CGPoint) -> Void)?
    var onZoomChanged: ((Bool) -> Void)?
    var onScrollingChanged: ((Bool) -> Void)?
    var onAutoScrollEnded: (() -> Void)?
    var onAutoAdvanceProgress: ((Double) -> Void)?
    // whether there is a chapter after this one at all, which the controller
    // cannot know - it only ever sees what is loaded
    var onCanContinue: (() -> Bool)?
    // the controller holds chapter ids and never their numbers, and has never
    // heard of the series at all
    var shareCaption: ((ReaderChapter.ID) -> (title: String, subtitle: String)?)?
    // sharing presents its own sheet from here, and saving writes from here for
    // the same reason: the decoded image is a UIKit object the layers above
    // deliberately never see. only the answer travels
    var onSaved: ((Result<Void, Error>) -> Void)?

    init(configuration: ReaderConfiguration) {
        self.configuration = configuration
        // width is zero until there is a view, so this one never warms anything
        // and its scale is immaterial - it is replaced the moment layout lands
        self.prefetcher = PagePrefetcher(count: configuration.prefetchCount, width: .zero, scale: 1)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildCollectionView()
        buildDataSource()

        // separator extents are constants per content-size category, so a reader
        // who changes their text size while the app is backgrounded comes back
        // to bands sized for the old one. cheap to redo - one model build per
        // boundary, at most windowSize + 1 of them
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.refreshSeparatorExtents()
            self.collectionView.collectionViewLayout.invalidateLayout()
        }
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
        // re-applying a resident chapter is a no-op, never a second section: the
        // snapshot keys on chapter id, so a duplicate is an uncatchable UIKit
        // exception. content that actually changed arrives through reload, which
        // removes first
        guard !loaded.contains(chapter) else { return }

        // after the guards, so the defer never outlives an operation that never
        // started. the snapshot apply and the offset restore both report from
        // geometry that is only half-settled
        beginMutation()
        defer { endMutation() }

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

        // extents first, or the boundaries this insert creates are counted at
        // a fallback height
        refreshSeparatorExtents()

        // summed rather than read back off contentSize: the layout is a plain
        // stack, so this is exact, and it cannot absorb an unrelated height
        // change that slipped in across the await below. counts the separators
        // the insert brings with it, and uses the scroll-axis extent rather
        // than an image ratio - the latter was wrong in every paged mode
        let inserted = items(for: chapter).reduce(CGFloat.zero) {
            $0 + extent(of: $1, width: pageWidth)
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

            // both answers to the same question: what the layout says is
            // centre-screen now, and what the stale visible set would have said.
            // if they agree, the geometry is settled and the reporter is honest
            let centre = centremostPage()
            let stale = collectionView.indexPathsForVisibleItems
                .min { lhs, rhs in
                    let mid = { (path: IndexPath) -> CGFloat in
                        self.collectionView.layoutAttributesForItem(at: path)?.frame.midY ?? .greatestFiniteMagnitude
                    }
                    let target = collectionView.contentOffset.y + collectionView.bounds.height / 2
                    return abs(mid(lhs) - target) < abs(mid(rhs) - target)
                }
                .flatMap { dataSource.itemIdentifier(for: $0)?.page }

            AppLog.shared.log(
                """
                prepend ch\(chapter): \(chapterPages.count) pages, \(measured) measured - \
                size \(Int(size.height))→\(Int(collectionView.contentSize.height)) \
                inserted \(Int(inserted)), \
                offset \(Int(offset.y))→\(Int(restored.y)), \
                settled at \(Int(collectionView.contentOffset.y)), \
                centre ch\(centre?.chapter.description ?? "-") \
                (visible set said ch\(stale?.chapter.description ?? "-"))
                """,
                category: "reader.layout"
            )
        } else {
            AppLog.shared.log(
                "append ch\(chapter): \(chapterPages.count) pages, \(measured) measured",
                level: .debug,
                category: "reader.layout"
            )
        }

        resetPreloadRequests()
    }

    func remove(_ chapter: ReaderChapter.ID) async {
        guard pages[chapter] != nil else { return }

        beginMutation()
        defer { endMutation() }

        flushInvalidation()

        // hold the item under the reader BY IDENTITY, not by index - the index
        // space is about to lose a whole chapter. evicting one that sits above
        // the reader shrinks everything above it, and without this the reader
        // is thrown forward by the entire evicted chapter
        let width = pageWidth
        let vertical = configuration.mode.isVertical
        let before = flatItems()
        let anchored = vertical ? collectionView.contentOffset.y : collectionView.contentOffset.x
        let held = anchor(at: anchored, in: before, width: width)
        let heldItem = held.map { before[$0.index] }

        pages[chapter]?.forEach { sizes[$0] = nil }
        pages[chapter] = nil
        loaded.removeAll { $0 == chapter }
        separatorExtents[.after(chapter)] = nil
        separatorDirections[.after(chapter)] = nil
        refreshSeparatorExtents()

        // ratios survive eviction on purpose. a chapter that comes back gets
        // its 70-odd estimates right on the first layout pass, so the prepend
        // delta is correct and the correction run never happens
        await applySnapshot(animated: false)

        let after = flatItems()
        // nil means the reader was inside the chapter that just went, which
        // eviction protects against - leave the offset alone rather than guess
        guard let held,
              let heldItem,
              let index = after.firstIndex(of: heldItem)
        else {
            AppLog.shared.log(
                "evict ch\(chapter): anchor lost, offset untouched",
                level: .debug,
                category: "reader.layout"
            )
            return
        }

        let restored = max(0, position(
            of: Anchor(index: index, fraction: held.fraction),
            in: after,
            width: width
        ))

        var point = collectionView.contentOffset
        if vertical { point.y = restored } else { point.x = restored }
        setOffsetWithoutAnimation(point)

        AppLog.shared.log(
            """
            evict ch\(chapter): size \(Int(collectionView.contentSize.height)), \
            offset \(Int(anchored))→\(Int(restored)), \
            settled at \(Int(vertical ? collectionView.contentOffset.y : collectionView.contentOffset.x))
            """,
            level: .debug,
            category: "reader.layout"
        )
    }

    func clear() async {
        beginMutation()
        defer { endMutation() }

        flushInvalidation()
        pendingOffsetAdjustment = 0

        pages.removeAll()
        sizes.removeAll()
        ratios.removeAll()
        samples.removeAll()
        loaded.removeAll()
        separatorExtents.removeAll()
        separatorDirections.removeAll()
        await applySnapshot(animated: false)
    }

    // MARK: Navigation

    func scroll(to chapter: ReaderChapter.ID, page index: Int, animated: Bool) {
        guard let chapterPages = pages[chapter], !chapterPages.isEmpty else { return }
        let clamped = min(max(0, index), chapterPages.count - 1)
        guard let path = dataSource.indexPath(for: .page(chapterPages[clamped])) else { return }

        collectionView.scrollToItem(
            at: path,
            at: scrollAnchor,
            animated: animated
        )
    }

    // false means there was nothing to move to. the caller decides what that
    // means - the end of the series and a chapter still loading look identical
    // from here
    @discardableResult
    func advance(by pages: Int) -> Bool {
        // where the reader is, not where it last reported being. the reported
        // page is nil until something scrolls - a chapter opened at page 0 never
        // does - and it is also nil while a separator holds the screen
        guard let path = centremostPath()
            ?? lastReportedPage.flatMap({ dataSource.indexPath(for: .page($0)) })
        else { return false }

        if configuration.mode.isContinuous {
            scrollByViewport(forward: pages > 0)
            return true
        }

        let flat = flatIndex(of: path)
        let target = flat + pages
        guard let next = item(atFlat: target),
              let path = dataSource.indexPath(for: next) else { return false }

        collectionView.scrollToItem(at: path, at: scrollAnchor, animated: true)
        return true
    }

    // MARK: Configuration

    func update(_ value: ReaderConfiguration) {
        let modeChanged = value.mode.resolved != configuration.mode.resolved
        let paddingChanged = value.horizontalPadding != configuration.horizontalPadding

        configuration = value
        autoScroller?.setSpeed(value.autoScrollSpeed)
        autoScroller?.setMode(value.mode)
        // changing the dwell restarts it - the bar would otherwise finish the
        // cycle it was already part-way through at the old duration
        autoAdvancer?.setInterval(value.autoAdvanceInterval)
        prefetcher = PagePrefetcher(count: value.prefetchCount, width: pageWidth, scale: pageScale)

        // the two drivers do not survive being handed each other's mode, and a
        // mode change is already a full relayout
        if modeChanged, isAutoScrolling {
            stopAutoScroll()
            onAutoScrollEnded?()
        }

        guard modeChanged || paddingChanged else { return }

        // the accumulator is expressed in coordinates the new layout destroys,
        // so drain what is pending and drop the rest
        flushInvalidation()
        pendingOffsetAdjustment = 0
        // separator extent is the one item size that flips wholesale on a mode
        // change, so a stale cache would lay the band out at the wrong height
        refreshSeparatorExtents()

        // hold the page being read across the relayout. querying it first, then
        // restoring after the new layout settles, is the whole trick - reading
        // it afterwards returns a position in coordinates that no longer exist
        let anchor = lastReportedPage

        applySemantics()
        collectionView.setCollectionViewLayout(makeLayout(), animated: false)
        collectionView.isPagingEnabled = configuration.mode.isPaged
        collectionView.layoutIfNeeded()

        if let anchor, let path = dataSource.indexPath(for: .page(anchor)) {
            collectionView.scrollToItem(at: path, at: scrollAnchor, animated: false)
        }
    }

    // MARK: Auto-scroll

    // a strip creeps, a paged mode dwells and then slides. the two are different
    // enough that they are different drivers rather than a branch inside one
    func startAutoScroll() {
        guard autoScroller == nil, autoAdvancer == nil else { return }

        guard configuration.mode.isContinuous else {
            let advancer = AutoAdvancer(
                view: collectionView,
                interval: configuration.autoAdvanceInterval
            )
            advancer.onFire = { [weak self] in
                guard let self else { return false }
                // failing to move only ends the session when there is genuinely
                // nothing after this - otherwise the countdown simply runs again
                // while the next chapter finishes loading
                return advance(by: 1) || onCanContinue?() == true
            }
            advancer.onProgress = { [weak self] progress in
                self?.onAutoAdvanceProgress?(progress)
            }
            advancer.onReachedEnd = { [weak self] in
                AppLog.shared.log("auto-advance ended: nothing after this page", category: "reader")
                self?.stopAutoScroll()
                self?.onAutoScrollEnded?()
            }
            advancer.start()
            autoAdvancer = advancer
            return
        }

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
        autoAdvancer?.stop()
        autoAdvancer = nil
    }

    func resetAutoAdvance() {
        autoAdvancer?.reset()
    }

    var isAutoScrolling: Bool {
        autoScroller?.isRunning ?? autoAdvancer?.isRunning ?? false
    }

    func pageCount(for chapter: ReaderChapter.ID) -> Int {
        pages[chapter]?.count ?? 0
    }

    // MARK: Private

    private var pageWidth: CGFloat {
        max(1, view.bounds.width - configuration.horizontalPadding * 2)
    }

    // the display this reader is on, not the one UIScreen.main used to assume
    private var pageScale: CGFloat {
        max(1, traitCollection.displayScale)
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
        collectionView.register(SeparatorCell.self, forCellWithReuseIdentifier: SeparatorCell.reuseIdentifier)
        applySemantics()

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        collectionView.addGestureRecognizer(tap)

        view.addSubview(collectionView)
        prefetcher = PagePrefetcher(count: configuration.prefetchCount, width: pageWidth, scale: pageScale)
    }

    private func applySemantics() {
        // right-to-left is one property. the collection view mirrors positions
        // and the cells come along with it
        collectionView.semanticContentAttribute = configuration.mode.isRightToLeft
            ? .forceRightToLeft
            : .forceLeftToRight
    }

    private func buildDataSource() {
        dataSource = DataSource(collectionView: collectionView) { [weak self] collectionView, indexPath, item in
            switch item {
            case let .page(page):
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
                cell.onShare = { [weak self] image, page in
                    self?.share(image, page: page)
                }
                cell.onSave = { [weak self] image in
                    self?.save(image)
                }
                cell.configure(with: page, width: self.pageWidth)
                return cell

            case let .separator(boundary):
                let cell = collectionView.dequeueReusableCell(
                    withReuseIdentifier: SeparatorCell.reuseIdentifier,
                    for: indexPath
                )
                guard let cell = cell as? SeparatorCell, let self else { return cell }

                // configured properly in willDisplay, once the approach
                // direction is known. this is just so it is never blank
                if let model = self.separatorModel?(boundary, self.separatorDirections[boundary] ?? .forward) {
                    cell.configure(with: model)
                }
                cell.onRetry = { [weak self] in
                    self?.onSeparatorRetry?(boundary)
                }
                cell.onRetryTracker = { [weak self] service in
                    self?.onSeparatorRetryTracker?(boundary, service)
                }
                cell.onComplete = { [weak self] in
                    self?.onSeparatorComplete?()
                }
                cell.onExplainGap = { [weak self] gap in
                    self?.onSeparatorGap?(gap)
                }
                return cell
            }
        }
    }

    private func applySnapshot(animated: Bool) async {
        var snapshot = Snapshot()
        snapshot.appendSections(loaded)
        for chapter in loaded {
            snapshot.appendItems(items(for: chapter), toSection: chapter)
        }
        await dataSource.apply(snapshot, animatingDifferences: animated)
    }

    // separators are derived, never stored, so eviction cleans up after itself.
    // the trailing one exists whether or not the next chapter is loaded - that
    // is what carries loading, failure and end-of-series
    private func items(for chapter: ReaderChapter.ID) -> [ReaderItem] {
        var items: [ReaderItem] = []

        if chapter == loaded.first, chapter == order.first {
            items.append(.separator(.start))
        }

        items.append(contentsOf: (pages[chapter] ?? []).map(ReaderItem.page))
        items.append(.separator(.after(chapter)))
        return items
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
        let flat = flatItems()

        // measured against where the reader will BE once the pending batch
        // flushes, not where it is now - sizes already holds this batch's
        // earlier corrections while the layout has yet to re-run, so anything
        // else would double-count them
        let target = collectionView.contentOffset.y + pendingOffsetAdjustment
        let held = anchor(at: target, in: flat, width: width)

        let estimated = extent(of: .page(page), width: width)
        sizes[page] = size
        learn(ratio: size.height / size.width, for: page.chapter)
        let actual = extent(of: .page(page), width: width)

        if let held {
            let moved = position(of: held, in: flat, width: width) - target
            pendingOffsetAdjustment += moved

            if abs(actual - estimated) > 1 || abs(moved) > 1 {
                AppLog.shared.log(
                    "resize ch\(page.chapter) p\(page.index): \(Int(estimated))→\(Int(actual)) "
                        + "Δ\(Int(actual - estimated)), anchor moved \(Int(moved)), "
                        + "pending \(Int(pendingOffsetAdjustment))",
                    level: .debug,
                    category: "reader.layout"
                )
            }
        }

        scheduleInvalidation()
    }

    private func scheduleInvalidation() {
        // coalesced: a chapter's images land within a few frames of each other,
        // and each one would otherwise cost a full invalidation
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

        // zero whenever the context is honoured, which device logs show it always
        // is. kept as the diagnostic - a non-zero value means the adjustment was
        // dropped and the reader drifted by that much
        let residual = (offset.y + adjustment) - collectionView.contentOffset.y

        let after = collectionView.contentSize
        let settled = collectionView.contentOffset
        guard abs(after.height - before.height) > 1 || abs(settled.y - offset.y) > 1 else { return }

        AppLog.shared.log(
            "invalidate: size \(Int(before.height))→\(Int(after.height)), "
                + "offset \(Int(offset.y))→\(Int(settled.y)), "
                + "adjust \(Int(adjustment)), residual \(Int(residual))",
            level: .debug,
            category: "reader.layout"
        )
    }

    private func refreshSeparatorExtents() {
        var extents: [ReaderBoundary: CGFloat] = [:]
        for item in flatItems() {
            guard case let .separator(boundary) = item else { continue }
            // sized for the reader's own text size: the band's constants are
            // per content-size category, so a scaled headline gets a box that
            // scaled with it rather than one it overflows
            extents[boundary] = separatorModel?(boundary, .forward)
                .height(for: traitCollection.preferredContentSizeCategory)
                ?? ReaderSeparatorModel.Metrics.destination
        }
        separatorExtents = extents
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

    // the only extent function in the controller. the layout, the prepend sum
    // and the compensation walk all go through it, so contentSize and the walk
    // cannot disagree - that disagreement IS the scroll-jump bug.
    //
    // paged modes size every cell to the viewport along the scroll axis, so an
    // image ratio was never the extent there. a separator has no ratio at all,
    // which is what forced this to become explicit
    private func extent(of item: ReaderItem, width: CGFloat) -> CGFloat {
        guard configuration.mode.isContinuous else {
            return configuration.mode.isVertical
                ? collectionView.bounds.height
                : collectionView.bounds.width
        }

        switch item {
        case let .page(page):
            return height(for: page, width: width)
        case let .separator(boundary):
            // declared by the model, never measured from the rendered view - a
            // height discovered after layout moves the scroll under the reader
            return separatorExtents[boundary] ?? ReaderSeparatorModel.Metrics.destination
        }
    }

    private func height(for page: ReaderPage, width: CGFloat) -> CGFloat {
        if let size = sizes[page], size.width > 0 {
            return width * (size.height / size.width)
        }
        return width * (ratios[page.chapter] ?? configuration.mode.fallbackPageRatio)
    }

    // MARK: Direction

    // (slot in `order`, index within the chapter). `order` is the full chapter
    // list, so a slot never moves when a chapter is prepended or evicted - flat
    // item indices do, which is exactly why they cannot be used here
    private struct ReadingPosition: Comparable {
        let slot: Int
        let index: Int

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.slot == rhs.slot ? lhs.index < rhs.index : lhs.slot < rhs.slot
        }
    }

    private func readingPosition(of item: ReaderItem) -> ReadingPosition? {
        switch item {
        case let .page(page):
            return order.firstIndex(of: page.chapter)
                .map { ReadingPosition(slot: $0, index: page.index) }
        case .separator(.start):
            return ReadingPosition(slot: -1, index: .max)
        case let .separator(.after(chapter)):
            // sits after every page of the chapter it trails
            return order.firstIndex(of: chapter)
                .map { ReadingPosition(slot: $0, index: .max) }
        }
    }

    private func travelDirection(to boundary: ReaderBoundary) -> ReadingDirection {
        guard let from = lastReportedPage,
              let origin = readingPosition(of: .page(from)),
              let target = readingPosition(of: .separator(boundary))
        else { return .forward }
        return target < origin ? .backward : .forward
    }

    // re-renders visible separators without touching the snapshot or the
    // layout. the engine calls this when a destination resolves while the
    // reader is sitting on the boundary - willDisplay has already fired and
    // would never fire again. safe only because slot presence, and therefore
    // height, is independent of state
    func reloadSeparators() {
        for path in collectionView.indexPathsForVisibleItems {
            guard case let .separator(boundary) = dataSource.itemIdentifier(for: path),
                  let cell = collectionView.cellForItem(at: path) as? SeparatorCell,
                  let model = separatorModel?(boundary, separatorDirections[boundary] ?? .forward)
            else { continue }
            cell.configure(with: model)
        }
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

    // every geometry walk goes through this. a height that exists outside
    // height(for:width:) would make the offset compensation drift
    private func flatItems() -> [ReaderItem] {
        loaded.flatMap { items(for: $0) }
    }

    private func anchor(at y: CGFloat, in flat: [ReaderItem], width: CGFloat) -> Anchor? {
        guard !flat.isEmpty else { return nil }

        var top: CGFloat = 0
        for (index, item) in flat.enumerated() {
            let extent = extent(of: item, width: width)
            if y < top + extent || index == flat.count - 1 {
                let fraction = extent > 0 ? (y - top) / extent : 0
                return Anchor(index: index, fraction: min(max(0, fraction), 1))
            }
            top += extent
        }
        return Anchor(index: flat.count - 1, fraction: 1)
    }

    private func position(of anchor: Anchor, in flat: [ReaderItem], width: CGFloat) -> CGFloat {
        guard anchor.index < flat.count else { return 0 }

        var top: CGFloat = 0
        for item in flat.prefix(anchor.index) {
            top += extent(of: item, width: width)
        }
        return top + extent(of: flat[anchor.index], width: width) * anchor.fraction
    }

    // counts ITEMS, not pages - a section carries its trailing separator, and
    // the first one may carry the opening separator too
    private func flatIndex(of path: IndexPath) -> Int {
        let before = loaded.prefix(path.section).reduce(0) { $0 + items(for: $1).count }
        return before + path.item
    }

    private func item(atFlat index: Int) -> ReaderItem? {
        guard index >= 0 else { return nil }
        var remaining = index
        for chapter in loaded {
            let sectionItems = items(for: chapter)
            if remaining < sectionItems.count { return sectionItems[remaining] }
            remaining -= sectionItems.count
        }
        return nil
    }

    private func scrollByViewport(forward: Bool) {
        // the viewport and nothing else. measuring the item under the reader
        // makes the distance depend on how the source happened to slice the
        // chapter - short slices step short, a separator steps a third of a
        // screen - and a strip is one column, so a viewport step cannot skip
        // anything the way it could between discrete pages
        let step = collectionView.bounds.height * Nudge.factor
        var offset = collectionView.contentOffset
        offset.y += forward ? step : -step
        offset.y = min(
            max(0, offset.y),
            max(0, collectionView.contentSize.height - collectionView.bounds.height)
        )
        collectionView.setContentOffset(offset, animated: true)
    }

    // presented from here rather than from the cell: a cell has no view
    // controller to present from
    private func share(_ image: UIImage, page: ReaderPage) {
        let caption = shareCaption?(page.chapter)
        let item = PageActivityItem(
            image: image,
            title: caption?.title ?? "",
            subtitle: caption?.subtitle ?? "Page \(page.index + 1)"
        )

        let activity = UIActivityViewController(activityItems: [item], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = collectionView
        activity.popoverPresentationController?.sourceRect = CGRect(
            origin: CGPoint(x: collectionView.bounds.midX, y: collectionView.bounds.midY),
            size: .zero
        )
        present(activity, animated: true)
    }

    // add-only authorization, which is the least the write needs and the prompt
    // the reader expects. requested rather than assumed: performChanges against
    // a denied library fails with a message about the change request rather than
    // about permission, which is the wrong sentence to put in front of someone
    private func save(_ image: UIImage) {
        Task { @MainActor in
            do {
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard status == .authorized || status == .limited else { throw SaveError.denied }

                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
                onSaved?(.success(()))
            } catch {
                AppLog.shared.log("saving a page failed - \(error)", level: .error, category: "reader")
                onSaved?(.failure(error))
            }
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard !isZoomed else { return }
        // window space, so a zone stays where the user sees it rather than
        // moving with the content underneath
        onSingleTap?(gesture.location(in: nil))
    }

    private func beginMutation() {
        mutations += 1
    }

    // one reconciling report on the way out, so a mutation that genuinely moved
    // the reader is still announced - just once, from the settled geometry
    private func endMutation() {
        mutations = max(0, mutations - 1)
        guard mutations == 0 else { return }
        reportVisiblePage()
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
                let sectionItems = self.items(for: chapter)
                guard !sectionItems.isEmpty else { return nil }

                if mode.isPaged {
                    return Self.pagedSection(count: sectionItems.count, environment: environment)
                }

                return self.continuousSection(
                    items: sectionItems,
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
        items sectionItems: [ReaderItem],
        padding: CGFloat,
        environment: NSCollectionLayoutEnvironment
    ) -> NSCollectionLayoutSection {
        let containerWidth = environment.container.effectiveContentSize.width
        let width = max(1, containerWidth - padding * 2)
        let heights = sectionItems.map { extent(of: $0, width: width) }
        let total = heights.reduce(0, +)

        let group = NSCollectionLayoutGroup.custom(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .absolute(max(1, total))
            )
        ) { _ in
            var y: CGFloat = 0
            return zip(sectionItems, heights).map { item, height in
                // a separator spans the container; only pages take the reading
                // padding. heights come from the same extent either way, so the
                // walk stays exact
                let inset: CGFloat = item.page == nil ? 0 : padding
                let frame = CGRect(
                    x: inset,
                    y: y,
                    width: containerWidth - inset * 2,
                    height: height
                )
                y += height
                return NSCollectionLayoutGroupCustomItem(frame: frame)
            }
        }

        return NSCollectionLayoutSection(group: group)
    }
}

// MARK: - UICollectionViewDelegate

extension ReaderController: UICollectionViewDelegate {
    // direction is latched here and only here: the cell was dequeued before the
    // reader's approach was known, so this is the refresh the boundary needs
    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard case let .separator(boundary) = dataSource.itemIdentifier(for: indexPath) else { return }

        let direction = travelDirection(to: boundary)
        separatorDirections[boundary] = direction
        lastDirection = direction

        if let model = separatorModel?(boundary, direction) {
            (cell as? SeparatorCell)?.configure(with: model)
        }
        onSeparatorReached?(boundary, direction)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        reportVisiblePage()
        checkProximity()
        updatePrefetch()
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // a creeping strip fights the finger, so any touch ends it. a dwelling
        // page does not - a touch there reads as "not yet", so the countdown
        // starts over and the session carries on
        if autoAdvancer != nil {
            resetAutoAdvance()
        } else if autoScroller != nil {
            stopAutoScroll()
            onAutoScrollEnded?()
        }

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
        // gated here and nowhere else: checkProximity reads only offset/bounds/
        // contentSize, which are fresh whatever the layout is doing, and
        // updatePrefetch is advisory and self-corrects
        guard mutations == 0 else { return }
        guard let page = centremostPage() else { return }
        guard page != lastReportedPage else { return }

        let chapterPages = pages[page.chapter] ?? []
        guard let index = chapterPages.firstIndex(of: page) else { return }

        // latched only once the page is known live: it feeds travelDirection ->
        // separator approach -> whether onChapterFinished fires, so latching it
        // above the guard records direction from a page that was never reported
        lastReportedPage = page
        onVisiblePageChanged?(page, index, chapterPages.count)
    }

    private func centremostPage() -> ReaderPage? {
        // a separator centre-screen reports nothing, so the scrubber and the
        // page counter hold on the last real page instead of blanking
        centremostPath().flatMap { dataSource.itemIdentifier(for: $0)?.page }
    }

    // candidates come from the layout, not from indexPathsForVisibleItems: that
    // set is a product of layoutSubviews and so describes the bounds *before* a
    // programmatic offset write, while the distances are measured against the
    // bounds after it. bounds.origin IS contentOffset on a scroll view, so
    // querying with bounds keeps the rect and the frames in one coordinate space
    private func centremostPath() -> IndexPath? {
        let bounds = collectionView.bounds
        guard let candidates = collectionView.collectionViewLayout
            .layoutAttributesForElements(in: bounds) else { return nil }

        let vertical = configuration.mode.isVertical
        let centre = vertical ? bounds.midY : bounds.midX

        var best: (path: IndexPath, distance: CGFloat)?
        for attributes in candidates where attributes.representedElementCategory == .cell {
            let mid = vertical ? attributes.frame.midY : attributes.frame.midX
            let distance = abs(mid - centre)
            if best == nil || distance < best!.distance {
                best = (attributes.indexPath, distance)
            }
        }

        return best?.path
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

        var visible = collectionView.indexPathsForVisibleItems
            .compactMap { dataSource.itemIdentifier(for: $0)?.page }
            .compactMap { flat.firstIndex(of: $0) }

        // in paged mode the separator can be the only thing on screen, which is
        // exactly when the next chapter's first pages are wanted. anchor on the
        // last real page so warming carries across the boundary
        if visible.isEmpty, let last = lastReportedPage, let index = flat.firstIndex(of: last) {
            visible = [index]
        }

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

// one case, because everything else the photo library refuses states its own
// reason. a denial does not - it arrives as a change-request error naming a
// mechanism rather than the permission behind it
private enum SaveError: DescribableError {
    case denied

    var errorDescription: String? { "Couldn't Save Page" }

    var failureReason: String? {
        "aletheia has no permission to add to your photo library. You can allow it in Settings."
    }

    // asking again gets the same refusal until something changes outside the app
    var isRetryable: Bool { false }
}

