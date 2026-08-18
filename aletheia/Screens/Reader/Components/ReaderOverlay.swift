//
//  ReaderOverlay.swift
//  aletheia
//
//  Created by Angelo Carasig on 7/8/2026.
//

import SwiftUI

// mirrors v2's reader chrome: a header that names where you are, and a control
// card that moves you
struct ReaderOverlay: View {
    let engine: ReaderEngine
    let sourceIcon: ImageResource?

    var onPreviousChapter: () -> Void
    var onNextChapter: () -> Void
    var onSeek: (Int) -> Void
    var onModeChange: (Orientation) -> Void
    var onFilters: () -> Void
    var onSpeedChange: (CGFloat) -> Void
    var onIntervalChange: (TimeInterval) -> Void
    var onChapters: () -> Void
    var onSources: () -> Void
    var onSettings: () -> Void
    var onTapZones: () -> Void
    var onDismiss: () -> Void

    @Environment(\.dimensions) private var dimensions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let track: CGFloat = 6
        static let disabledOpacity: Double = 0.35
        static let tintOpacity: Double = 0.2
        static let settle: Animation = .snappy(duration: 0.25)
        static let identity: Animation = .snappy(duration: 0.3)
        // roughly the width of "Chapter 41", so the capsule barely resizes when
        // the real title lands
        static let placeholderWidth: CGFloat = 84
        static let placeholderHeight: CGFloat = 12
        static let placeholderFill: Double = 0.12
    }

    // clear glass has no adaptive behaviour, so it never flips to suit what is
    // behind it. the tint is the legibility control - without it the chrome
    // disappears into a busy page
    private var surface: Glass {
        .clear.tint(.black.opacity(engine.configuration.chromeTint)).interactive()
    }

    var body: some View {
        VStack(spacing: dimensions.spacing.space12) {
            Header

            Spacer(minLength: 0)

            if engine.isAutoScrolling {
                SpeedPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Controls
        }
        .padding(dimensions.screenMargin)
        .environment(\.colorScheme, .dark)
        .animation(Layout.settle, value: engine.isAutoScrolling)
    }
}

// MARK: - Header

extension ReaderOverlay {
    fileprivate var Header: some View {
        GlassEffectContainer(spacing: dimensions.spacing.space8) {
            HStack(spacing: dimensions.spacing.space8) {
                // the source's own icon, so the button doubles as "which source
                // am I reading from" rather than being a mystery glyph
                SourceButton

                Identity

                Spacer(minLength: 0)

                Circular("gearshape", action: onSettings)

                Circular("xmark", action: onDismiss)
            }
            // on the row rather than the button: a transition needs a transaction
            // from an ancestor that outlives the view being replaced
            .animation(Layout.identity, value: sourceIcon)
        }
    }

    @ViewBuilder
    fileprivate var SourceButton: some View {
        if let sourceIcon {
            // the artwork fills the control, so there is no glass ring around
            // it - the icon is the button
            Image(sourceIcon)
                .resizable()
                .scaledToFill()
                .frame(width: dimensions.size.control, height: dimensions.size.control)
                .clipShape(.circle)
                .contentShape(.circle)
                .tappable(action: onSources)
                // swapping sources replaces the artwork, and a hard cut on the
                // one control that says where you are reading from reads as a
                // glitch. keyed on the icon so the swap is what drives it
                .id(sourceIcon)
                .transition(.opacity.combined(with: .scale))
        } else {
            // a downloaded chapter whose source has since been removed. nothing
            // to fill with, so this one keeps the glass
            Icon("book.closed")
                .frame(width: dimensions.size.control, height: dimensions.size.control)
                .glassEffect(surface, in: .circle)
                .contentShape(.circle)
                .tappable(action: onSources)
        }
    }

    fileprivate var Identity: some View {
        VStack(alignment: .leading, spacing: dimensions.spacing.space2) {
            // two views rather than one string: "Loading" and a chapter number
            // are different kinds of thing, and numericText cannot morph a word
            // into digits - it would snap. resolving is a replace, moving between
            // chapters is a roll
            if let chapter = engine.current {
                Text("Chapter \(chapter.number.formatted())")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    // the number carries the direction on its own: forward rolls
                    // the digits up, back rolls them down. nothing has to track
                    // which way the chapter moved
                    .contentTransition(.numericText(value: chapter.number))
                    .transition(.replace(reduceMotion: reduceMotion))
            } else {
                // the shape the chapter will take, not a word standing in for it.
                // matches ReaderSkeleton's fill so the two placeholders read as
                // the same surface resolving
                Capsule()
                    .fill(.white.opacity(Layout.placeholderFill))
                    .frame(width: Layout.placeholderWidth, height: Layout.placeholderHeight)
                    .shimmer()
                    .transition(.replace(reduceMotion: reduceMotion))
            }

            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .lineLimit(1)
                    // arbitrary text, so it crossfades rather than rolls - keyed
                    // on the string so a change swaps it, not only nil <-> value
                    .id(subtitle)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, dimensions.spacing.space12)
        // matched to the circular controls either side of it so the row reads
        // as one band rather than a capsule floating between two buttons
        .frame(height: dimensions.size.control)
        .glassEffect(surface, in: .capsule)
        .contentShape(.rect)
        .tappable(action: onChapters)
        // the capsule resizes to whatever the new chapter is called, so the
        // transaction has to sit above the text rather than on it
        .animation(Layout.identity, value: engine.current?.id)
    }

    // most sources title a chapter with its own number, which then reads as the
    // same line twice
    fileprivate var subtitle: String? {
        guard let chapter = engine.current else { return nil }
        let title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        let number = chapter.number.formatted()
        let redundant = ["chapter \(number)", "ch. \(number)", "ch \(number)", number]
        guard !redundant.contains(title.lowercased()) else { return nil }

        return title
    }
}

// MARK: - Controls

extension ReaderOverlay {
    fileprivate var Controls: some View {
        GlassEffectContainer(spacing: dimensions.spacing.space8) {
            VStack(spacing: dimensions.spacing.space12) {
                SeekRow
                HStack(spacing: dimensions.spacing.space4) {
                    LeadingActions
                    Spacer(minLength: 0)
                    Position
                    Spacer(minLength: 0)
                    TrailingActions
                }
            }
            .padding(dimensions.spacing.space16)
            .glassEffect(surface, in: .rect(cornerRadius: dimensions.radius.radius28))
        }
    }

    fileprivate var SeekRow: some View {
        HStack(spacing: dimensions.spacing.space12) {
            Step("chevron.left", enabled: engine.canGoPrevious, action: onPreviousChapter)
            Scrubber
            Step("chevron.right", enabled: engine.canGoNext, action: onNextChapter)
        }
    }

    fileprivate var LeadingActions: some View {
        HStack(spacing: dimensions.spacing.space4) {
            AutoScrollToggle
            FiltersButton
        }
    }

    fileprivate var TrailingActions: some View {
        HStack(spacing: dimensions.spacing.space4) {
            ModeMenu
            Action("hand.tap", action: onTapZones)
        }
    }

    fileprivate var Position: some View {
        Text(position)
            .font(.subheadline)
            .fontWeight(.semibold)
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    fileprivate var position: String {
        guard engine.pageCount > 0 else { return "-" }
        return "\(engine.page + 1) / \(engine.pageCount)"
    }
}

// MARK: - Scrubber

extension ReaderOverlay {
    @ViewBuilder
    fileprivate var Scrubber: some View {
        // read here rather than inside the binding. a getter runs outside body
        // evaluation, so a page read that only happens in there never registers
        // as a dependency and the thumb stops following the reader
        let page = engine.page
        let count = engine.pageCount

        if count > 1 {
            // no local copy of where the finger is: goToPage writes `page`
            // synchronously before it scrolls, so the value read back is the one
            // just set and the thumb tracks exactly
            Slider(
                value: Binding(
                    get: { Double(page) },
                    set: { onSeek(Int($0)) }
                ),
                in: 0...Double(count - 1),
                step: 1
            )
            .disabled(engine.isLoading)
            .opacity(engine.isLoading ? Layout.disabledOpacity : 1)
            .sensoryFeedback(.selection, trigger: page)
        } else {
            // a one-page chapter still needs the row to hold its height, or the
            // card jumps between chapters
            Capsule()
                .fill(.tertiary)
                .frame(height: Layout.track)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Buttons

extension ReaderOverlay {
    fileprivate var AutoScrollToggle: some View {
        Action(
            engine.isAutoScrolling ? "pause.fill" : "play.fill",
            action: { engine.toggleAutoScroll() }
        )
        .disabled(engine.error != nil)
        .opacity(engine.error != nil ? Layout.disabledOpacity : 1)
    }

    // filled while anything is on, so the button reports the page's state rather
    // than only offering to change it
    fileprivate var FiltersButton: some View {
        Action(
            filtering ? "circle.lefthalf.filled.inverse" : "circle.lefthalf.filled",
            action: onFilters)
    }

    fileprivate var ModeMenu: some View {
        Menu {
            Picker("Reading Mode", selection: modeBinding) {
                ForEach(modes, id: \.self) { mode in
                    Label(mode.label, systemImage: icon(for: mode)).tag(mode)
                }
            }
        } label: {
            Icon(icon(for: engine.configuration.mode.resolved))
                .frame(width: dimensions.size.icon40, height: dimensions.size.icon40)
                .contentShape(.circle)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .disabled(engine.error != nil)
        .opacity(engine.error != nil ? Layout.disabledOpacity : 1)
    }

    fileprivate var SpeedPanel: some View {
        HStack(spacing: dimensions.spacing.space12) {
            Icon("tortoise.fill")

            if engine.configuration.mode.isContinuous {
                Slider(
                    value: speedBinding,
                    in: ReaderConfiguration.Defaults
                        .minAutoScrollSpeed...ReaderConfiguration.Defaults.maxAutoScrollSpeed,
                    step: 5
                )
            } else {
                // no step: whole seconds no longer divide the range, and a dwell
                // has no reason to quantise - nothing displays the number
                Slider(
                    value: intervalBinding,
                    in: ReaderConfiguration.Defaults
                        .minAutoAdvanceInterval...ReaderConfiguration.Defaults
                        .maxAutoAdvanceInterval
                )
            }

            Icon("hare.fill")
        }
        .padding(.horizontal, dimensions.spacing.space16)
        .padding(.vertical, dimensions.spacing.space12)
        .glassEffect(surface, in: .capsule)
    }

    fileprivate var modes: [Orientation] {
        [.infinite, .vertical, .leftToRight, .rightToLeft]
    }

    fileprivate func icon(for mode: Orientation) -> String {
        switch mode.resolved {
        case .infinite: "arrow.down.to.line"
        case .vertical: "square.stack"
        case .leftToRight: "arrow.right"
        case .rightToLeft: "arrow.left"
        case .unknown: "arrow.right"
        }
    }

    fileprivate var filtering: Bool {
        let configuration = engine.configuration
        return configuration.dim > 0
            || configuration.warmth != 0
            || configuration.grayscale
            || configuration.inverted
    }

    fileprivate var modeBinding: Binding<Orientation> {
        Binding(get: { engine.configuration.mode.resolved }, set: onModeChange)
    }

    fileprivate var speedBinding: Binding<CGFloat> {
        Binding(get: { engine.configuration.autoScrollSpeed }, set: onSpeedChange)
    }

    // a dwell gets shorter as the reader gets faster, so the raw value would put
    // the quick end under the tortoise. mirrored across the range instead, and
    // hare keeps meaning sooner
    fileprivate var intervalBinding: Binding<TimeInterval> {
        let span =
            ReaderConfiguration.Defaults.minAutoAdvanceInterval
            + ReaderConfiguration.Defaults.maxAutoAdvanceInterval

        return Binding(
            get: { span - engine.configuration.autoAdvanceInterval },
            set: { onIntervalChange(span - $0) }
        )
    }
}

// MARK: - Primitives

extension ReaderOverlay {
    fileprivate func Icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: dimensions.size.icon16, weight: .semibold))
    }

    // nothing in this overlay sets a colour. glass resolves its own light or
    // dark appearance from what it samples and vends a matching content colour -
    // pinning a foreground fights that, and only ever matches by luck
    fileprivate func Circular(
        _ name: String,
        size: CGFloat? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let side = size ?? dimensions.size.control

        return Icon(name)
            .frame(width: side, height: side)
            .glassEffect(surface, in: .circle)
            .contentShape(.circle)
            .tappable(action: action)
    }

    // no glass of its own: these sit on the control slab, and glass cannot
    // sample glass - nesting it renders a flat sticker on the surface
    fileprivate func Action(
        _ name: String,
        action: @escaping () -> Void
    ) -> some View {
        Icon(name)
            .frame(width: dimensions.size.icon40, height: dimensions.size.icon40)
            .contentShape(.circle)
            .tappable(action: action)
    }

    fileprivate func Step(_ name: String, enabled: Bool, action: @escaping () -> Void) -> some View
    {
        Icon(name)
            .frame(width: dimensions.size.icon32, height: dimensions.size.icon32)
            .contentShape(.circle)
            .tappable(action: action)
            .disabled(!enabled)
            .opacity(enabled ? 1 : Layout.disabledOpacity)
    }
}
