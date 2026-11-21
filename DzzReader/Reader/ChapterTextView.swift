import SwiftUI
import UIKit

enum PageCommand { case previous, next }

/// The reading surface: a TextKit 1 UITextView showing one document (a whole book, or one chapter of a big one).
/// All offsets crossing this boundary are RENDERED offsets (UTF-16 units into `attributedText`).
///
/// TextKit 1, not 2: a TextKit 2 UITextView redraws every paragraph on screen on every frame while it scrolls
/// (measured: ~200 fragment draws/s during auto-scroll, and the same under a finger), which made auto-scroll cost
/// about five times the CPU. TextKit 1 draws into tiles that only move.
struct ChapterTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let contentID: Int                       // changes when a different document is shown
    /// Titles of the chapters a pull past the top / bottom edge opens; nil when there is none (or it is on screen).
    var previousChapterHint: String? = nil
    var nextChapterHint: String? = nil
    let backgroundColor: UIColor
    let tintColor: UIColor
    let margin: CGFloat
    @Binding var scrollTarget: Int?          // rendered offset to place at the top; cleared after scrolling
    var autoScrollSpeed: Double?             // points per second; nil when auto-scroll is off or paused
    var onVisibleOffsetChanged: (Int) -> Void
    var onNextChapter: () -> Void
    var onAddBookmark: (NSRange, String) -> Void
    var onShareQuote: (NSRange, String) -> Void = { _, _ in }   // the selection goes to the 分享 card
    var onTapCenter: () -> Void
    var onReachedEnd: () -> Void             // auto-scroll, a next-screen swipe or a pull ran past the end
    var onReachedStart: () -> Void = {}      // a previous-screen swipe or a pull ran past the start

    static func dismantleUIView(_ view: UITextView, coordinator: Coordinator) {
        coordinator.setAutoScroll(speed: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = ReaderTextView(usingTextLayoutManager: false)
        // A whole book is up to 300K characters; lay out only what is needed instead of everything up front.
        view.layoutManager.allowsNonContiguousLayout = true
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = true
        view.alwaysBounceVertical = true
        view.showsVerticalScrollIndicator = true
        view.delegate = context.coordinator
        view.textContainer.lineFragmentPadding = 0
        assert(view.layoutManager.delegate == nil, "UITextView now uses its layout manager's delegate itself")
        view.layoutManager.delegate = view
        // The hidden navigation bar still reports a safe area; use the window's own insets instead.
        view.contentInsetAdjustmentBehavior = .never
        view.keyboardDismissMode = .onDrag

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        // Horizontal swipes turn the screen like a page: left = next screen, right = previous screen.
        for direction in [UISwipeGestureRecognizer.Direction.right, .left] {
            let swipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe(_:)))
            swipe.direction = direction
            swipe.delegate = context.coordinator
            view.addGestureRecognizer(swipe)
        }

        context.coordinator.textView = view
        apply(to: view, context: context, contentChanged: true)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let contentChanged = context.coordinator.contentID != contentID
            || context.coordinator.attributedText !== attributedText
        apply(to: view, context: context, contentChanged: contentChanged)
    }

    private func apply(to view: UITextView, context: Context, contentChanged: Bool) {
        let coordinator = context.coordinator
        coordinator.parent = self
        // SwiftUI calls this on every observed change (auto-scroll reports progress each second); setting
        // link attributes can redraw the whole text, so only touch what actually changed.
        if view.backgroundColor != backgroundColor { view.backgroundColor = backgroundColor }
        if view.tintColor != tintColor {
            view.tintColor = tintColor
            view.linkTextAttributes = [.foregroundColor: tintColor]
        }
        (view as? ReaderTextView)?.horizontalMargin = margin   // its didSet already skips unchanged insets

        if contentChanged {
            let chapterChanged = coordinator.contentID != contentID
            coordinator.contentID = contentID
            coordinator.attributedText = attributedText
            // Keep the reading position across a restyle of the same document. While a jump is still settling,
            // the top line may not be where it will end up, so keep the jump's target instead.
            let keep = chapterChanged ? nil : (coordinator.pendingTarget ?? coordinator.currentTopOffset())
            view.attributedText = attributedText
            if chapterChanged {
                view.setContentOffset(.zero, animated: false)
                coordinator.chapterDidChange()
            } else if let keep, scrollTarget == nil {
                coordinator.scroll(toRenderedOffset: keep)
            }
        }

        if let target = scrollTarget {
            DispatchQueue.main.async {
                coordinator.scroll(toRenderedOffset: target)
                coordinator.parent.scrollTarget = nil
            }
        }

        coordinator.setAutoScroll(speed: autoScrollSpeed)
    }

    // MARK: - Text view

    /// UITextView that pads its text by the window safe area (status bar / home indicator) plus reading margins.
    final class ReaderTextView: UITextView, @preconcurrency NSLayoutManagerDelegate {   // a UITextView lays out on the main thread
        /// TextKit 1 puts a paragraph's whole `lineSpacing` under each line, and the selection highlight covers
        /// the line fragment, so it hung far below the glyphs. Lower the glyphs by half the spacing so they sit
        /// in the middle of their fragment: the highlight then has as much room above the text as below it.
        /// Fragment rects are unchanged, so the line geometry used for scrolling and paging is unaffected.
        func layoutManager(_ layoutManager: NSLayoutManager,
                           shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>,
                           lineFragmentUsedRect: UnsafeMutablePointer<CGRect>,
                           baselineOffset: UnsafeMutablePointer<CGFloat>,
                           in textContainer: NSTextContainer,
                           forGlyphRange glyphRange: NSRange) -> Bool {
            let character = layoutManager.characterIndexForGlyph(at: glyphRange.location)
            guard character < textStorage.length,
                  let style = textStorage.attribute(.paragraphStyle, at: character, effectiveRange: nil) as? NSParagraphStyle,
                  style.lineSpacing > 0 else { return false }
            baselineOffset.pointee += style.lineSpacing / 2
            return true
        }

        var horizontalMargin: CGFloat = 20 { didSet { updateInsets() } }
        static let topPadding: CGFloat = 24
        static let bottomPadding: CGFloat = 64

        override func didMoveToWindow() {
            super.didMoveToWindow()
            updateInsets()
        }

        override func safeAreaInsetsDidChange() {
            super.safeAreaInsetsDidChange()
            updateInsets()
        }

        // MARK: Selection highlight

        /// The highlight and its handles would cover each line's whole fragment, line spacing included, which
        /// leaves a wide band of empty highlight above and below the characters. Trim them to the glyphs.
        override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
            super.selectionRects(for: range).map { selection in
                guard let tight = glyphBand(around: selection.rect) else { return selection }
                return TrimmedSelectionRect(selection, rect: tight)
            }
        }

        override func caretRect(for position: UITextPosition) -> CGRect {
            let caret = super.caretRect(for: position)
            return glyphBand(around: caret) ?? caret
        }

        /// `rect` (view coordinates, one line tall) narrowed vertically to the line's glyphs: from the font's
        /// ascender to its descender around the baseline, plus a little air. Nil when that would not be smaller.
        private func glyphBand(around rect: CGRect) -> CGRect? {
            guard textStorage.length > 0, rect.height > 0, !rect.isNull, !rect.isInfinite else { return nil }
            let inset = textContainerInset
            let point = CGPoint(x: max(rect.midX - inset.left, 0), y: max(rect.midY - inset.top, 0))
            let glyph = layoutManager.glyphIndex(for: point, in: textContainer)
            guard layoutManager.isValidGlyphIndex(glyph) else { return nil }
            let character = layoutManager.characterIndexForGlyph(at: glyph)
            guard character < textStorage.length,
                  let font = textStorage.attribute(.font, at: character, effectiveRange: nil) as? UIFont else { return nil }
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let baseline = fragment.minY + layoutManager.location(forGlyphAt: glyph).y + inset.top
            let air = font.pointSize * Self.selectionAir
            let top = baseline - font.ascender - air
            let bottom = baseline - font.descender + air
            guard bottom - top < rect.height - 1 else { return nil }
            return CGRect(x: rect.minX, y: top, width: rect.width, height: bottom - top)
        }

        /// Room above and below the glyphs inside the highlight, as a fraction of the font size.
        static let selectionAir: CGFloat = 0.08

        /// Only the text on screen. A whole book can be hundreds of thousands of characters; handing all of it to
        /// accessibility clients makes every query slow (XCUITest snapshots took ~5 s per query).
        override var accessibilityValue: String? {
            get { visibleText() }
            set {}
        }

        private func visibleText() -> String? {
            let length = textStorage.length
            guard length > 0 else { return nil }
            let insets = verticalScrollIndicatorInsets
            // Container coordinates of the visible band between the status bar and the home indicator.
            let top = max(contentOffset.y + insets.top - textContainerInset.top, 0)
            let bottom = top + max(bounds.height - insets.top - insets.bottom, 1)
            let start = firstLine(endingBelow: top + 1).map { characterRange(of: $0).location } ?? 0
            let end = line(atY: bottom).map { NSMaxRange(characterRange(of: $0)) } ?? length
            guard start < end, end <= length else { return textStorage.string }
            return (textStorage.string as NSString).substring(with: NSRange(location: start, length: end - start))
        }

        // MARK: Line geometry (text-container coordinates)

        /// One laid-out line: its glyphs and the rect its glyphs use (without line or paragraph spacing).
        struct Line {
            let glyphs: NSRange
            let rect: CGRect
        }

        func line(forGlyphAt index: Int) -> Line? {
            guard layoutManager.isValidGlyphIndex(index) else { return nil }
            var glyphs = NSRange()
            let rect = layoutManager.lineFragmentUsedRect(forGlyphAt: index, effectiveRange: &glyphs)
            return Line(glyphs: glyphs, rect: rect)
        }

        /// The line at `y`, or the nearest one when `y` falls in spacing or past the text.
        func line(atY y: CGFloat) -> Line? {
            guard textStorage.length > 0 else { return nil }
            let index = layoutManager.glyphIndex(for: CGPoint(x: 1, y: max(y, 0)), in: textContainer)
            return line(forGlyphAt: index)
        }

        func line(after line: Line) -> Line? { self.line(forGlyphAt: NSMaxRange(line.glyphs)) }

        func line(before line: Line) -> Line? {
            line.glyphs.location > 0 ? self.line(forGlyphAt: line.glyphs.location - 1) : nil
        }

        /// The first line whose bottom is below `y`, starting from the line at `y`.
        func firstLine(endingBelow y: CGFloat) -> Line? {
            guard var current = line(atY: y) else { return nil }
            for _ in 0..<8 where current.rect.maxY <= y {
                guard let next = line(after: current) else { break }
                current = next
            }
            return current
        }

        func characterRange(of line: Line) -> NSRange {
            layoutManager.characterRange(forGlyphRange: line.glyphs, actualGlyphRange: nil)
        }

        /// False for collapsed empty lines and lines holding only whitespace.
        func hasText(_ line: Line) -> Bool {
            guard line.rect.height > 2 else { return false }
            let range = characterRange(of: line)
            return !(textStorage.string as NSString).substring(with: range)
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        private func updateInsets() {
            let safe = window?.safeAreaInsets ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
            let insets = UIEdgeInsets(top: safe.top + Self.topPadding, left: horizontalMargin,
                                      bottom: safe.bottom + Self.bottomPadding, right: horizontalMargin)
            if textContainerInset != insets { textContainerInset = insets }
            verticalScrollIndicatorInsets = UIEdgeInsets(top: safe.top, left: 0, bottom: safe.bottom, right: 0)
        }
    }

    /// A system selection rect with its frame replaced; everything else is the original's.
    final class TrimmedSelectionRect: UITextSelectionRect {
        private let original: UITextSelectionRect
        private let trimmed: CGRect

        init(_ original: UITextSelectionRect, rect: CGRect) {
            self.original = original
            self.trimmed = rect
        }

        override var rect: CGRect { trimmed }
        override var writingDirection: NSWritingDirection { original.writingDirection }
        override var containsStart: Bool { original.containsStart }
        override var containsEnd: Bool { original.containsEnd }
        override var isVertical: Bool { original.isVertical }
        override var transform: CGAffineTransform { original.transform }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: ChapterTextView
        weak var textView: UITextView?
        var contentID: Int = .min
        var attributedText: NSAttributedString?
        private var debounce: Task<Void, Never>?
        private var lastReported: Int = -1

        // Auto-scroll state
        private var displayLink: CADisplayLink?
        private var autoScrollSpeed: Double = 0
        private var lastTick: CFTimeInterval = 0
        private var lastAutoReport: CFTimeInterval = 0
        private var autoY: CGFloat?              // fractional offset; contentOffset may be pixel-rounded
        private var pausedUntil: CFTimeInterval = 0
        private var endReported = false

        init(_ parent: ChapterTextView) {
            self.parent = parent
        }

        // MARK: Offsets

        private var reader: ReaderTextView? { textView as? ReaderTextView }

        /// Rendered offset of the first visible line.
        func currentTopOffset() -> Int? {
            guard let view = reader else { return nil }
            // The text inset is the window safe area plus the fixed top padding, so the first line below
            // the status bar sits `topPadding` above the container origin.
            let y = max(view.contentOffset.y - ReaderTextView.topPadding, 0)
            guard let line = view.firstLine(endingBelow: y + 1) else { return nil }
            return view.characterRange(of: line).location
        }

        /// Rendered offset a scroll is still settling on; restyles keep this instead of a possibly stale top line.
        private(set) var pendingTarget: Int?

        /// Puts the line containing `offset` at the top, then checks on the next pass that it is really there.
        /// With non-contiguous layout, text above the target may only have estimated positions until it is laid
        /// out, so a single attempt can land off in a long document.
        func scroll(toRenderedOffset offset: Int, attempt: Int = 0) {
            guard let view = reader else { return }
            let layout = view.layoutManager
            pendingTarget = offset
            view.layoutIfNeeded()
            let length = view.textStorage.length
            guard length > 0 else { return }
            let clamped = min(max(offset, 0), length - 1)
            // Non-contiguous layout only estimates where text it has not laid out sits, and corrects it later,
            // moving the text after the jump. Lay out everything up to the target so its position is real.
            layout.ensureLayout(forCharacterRange: NSRange(location: 0, length: clamped + 1))
            let glyph = layout.glyphIndexForCharacter(at: clamped)
            guard let line = view.line(forGlyphAt: glyph) else { return }
            let target = line.rect.minY + ReaderTextView.topPadding
            var maxY = max(view.contentSize.height - view.bounds.height, 0)
            if target > maxY {
                // The content height may still be an estimate below the target. Lay out a screen beyond it and
                // take the real height from the layout manager.
                let ahead = NSRange(location: clamped, length: min(4_000, length - clamped))
                layout.ensureLayout(forCharacterRange: ahead)
                let used = layout.usedRect(for: view.textContainer).height
                let height = used + view.textContainerInset.top + view.textContainerInset.bottom
                if height > view.contentSize.height { view.contentSize.height = height }
                maxY = max(view.contentSize.height - view.bounds.height, 0)
            }
            view.setContentOffset(CGPoint(x: 0, y: min(max(target, 0), maxY)), animated: false)
            DispatchQueue.main.async { [weak self] in self?.verifyScroll(to: offset, attempt: attempt) }
        }

        private func verifyScroll(to offset: Int, attempt: Int) {
            guard pendingTarget == offset, let view = textView else { return }   // superseded, or the reader took over
            view.layoutIfNeeded()
            let maxY = max(view.contentSize.height - view.bounds.height, 0)
            let top = currentTopOffset() ?? offset
            // On target when `offset` falls in the first visible line (lines are well under 64 characters),
            // or when the document end is reached and the target cannot come any higher.
            let landed = (top <= offset && offset - top < 64) || (top <= offset && view.contentOffset.y >= maxY - 1)
            if landed || attempt >= 3 {
                pendingTarget = nil
                report()
            } else {
                scroll(toRenderedOffset: offset, attempt: attempt + 1)
            }
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            pendingTarget = nil   // the reader's finger wins over a settling jump
        }

        // MARK: Screen paging

        /// Top and bottom (text-container coordinates) of the line at `y`, or of the next line when `y` falls between lines.
        private func line(at y: CGFloat) -> (minY: CGFloat, maxY: CGFloat)? {
            guard let line = reader?.firstLine(endingBelow: y) else { return nil }
            return (line.rect.minY, line.rect.maxY)
        }

        /// The last non-blank line that ends at or above `y` (skips paragraph spacing and collapsed empty lines).
        private func line(endingAtOrAbove y: CGFloat) -> (minY: CGFloat, maxY: CGFloat)? {
            guard let view = reader, var current = view.line(atY: max(y - 0.5, 0)) else { return nil }
            for _ in 0..<16 {
                if current.rect.maxY <= y + 0.5, view.hasText(current) {
                    return (current.rect.minY, current.rect.maxY)
                }
                guard let previous = view.line(before: current) else { return nil }
                current = previous
            }
            return nil
        }

        /// Top of the first line that starts at or below `y`.
        private func lineStart(atOrAfter y: CGFloat) -> CGFloat? {
            guard let current = line(at: y) else { return nil }
            return current.minY >= y - 0.5 ? current.minY : (line(at: current.maxY + 0.5)?.minY ?? current.maxY)
        }

        /// Scrolls one screen, keeping one line of overlap: the last fully visible line becomes the first line
        /// of the next screen, and the first fully visible line becomes the last line of the previous screen.
        func page(_ direction: PageCommand) {
            guard let view = textView else { return }
            view.layoutIfNeeded()
            let indicator = view.verticalScrollIndicatorInsets   // mirrors the window safe area
            let visible = max(view.bounds.height - indicator.top - indicator.bottom, 1)
            let padding = ReaderTextView.topPadding
            let top = view.contentOffset.y - padding             // container y at the top of the visible band
            let maxOffset = max(view.contentSize.height - view.bounds.height, 0)
            var target: CGFloat
            switch direction {
            case .next:
                if view.contentOffset.y >= maxOffset - 1 {
                    parent.onReachedEnd()
                    return
                }
                // The first line not fully visible at the bottom, then the fully visible line just above it.
                let cutTop = line(at: top + visible)?.minY ?? top + visible
                let lastFull = line(endingAtOrAbove: cutTop)?.minY ?? cutTop
                if lastFull > top + 1 {
                    target = lastFull + padding
                } else if cutTop > top + 1 {
                    target = cutTop + padding          // only one line fits on screen: no room for overlap
                } else {
                    target = top + visible + padding
                }
            case .previous:
                // At the first line counts as the top: a jump parks it under the status bar, `topPadding` down.
                guard view.contentOffset.y > padding + 0.5 else {
                    parent.onReachedStart()
                    return
                }
                // The first fully visible line stays on screen as the last line of the new screen.
                let anchor = lineStart(atOrAfter: top) ?? top
                let anchorBottom = line(at: anchor)?.maxY ?? anchor
                let newTop = anchorBottom - visible
                let lineTop = lineStart(atOrAfter: newTop) ?? newTop
                if lineTop < anchor - 1 {
                    target = lineTop + padding
                } else {
                    // The anchor line alone fills the screen: fall back to a plain previous screen.
                    let plainTop = lineStart(atOrAfter: anchor - visible) ?? anchor - visible
                    target = (plainTop < anchor - 1 ? plainTop : anchor - visible) + padding
                }
            }
            target = min(max(target, 0), maxOffset)
            autoY = nil
            pausedUntil = CACurrentMediaTime() + 0.5
            view.setContentOffset(CGPoint(x: 0, y: target), animated: true)
        }

        // MARK: Auto-scroll

        func setAutoScroll(speed: Double?) {
            guard let speed, speed > 0 else {
                displayLink?.invalidate()
                displayLink = nil
                if autoY != nil { report() }
                autoY = nil
                return
            }
            let speedChanged = speed != autoScrollSpeed
            autoScrollSpeed = speed
            if let link = displayLink {
                if speedChanged { link.preferredFrameRateRange = Self.frameRateRange(speed: speed, scale: pixelScale) }
                return
            }
            endReported = false
            autoY = nil
            lastTick = CACurrentMediaTime()
            lastAutoReport = lastTick
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.preferredFrameRateRange = Self.frameRateRange(speed: speed, scale: pixelScale)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        private var pixelScale: CGFloat {
            textView.map { $0.window?.screen.scale ?? $0.traitCollection.displayScale } ?? 3
        }

        /// Auto-scroll moves slowly, so redrawing at the display's full rate mostly re-renders sub-pixel moves.
        /// Ask for about one frame per pixel travelled, capped at 30 Hz (at most a few pixels per step).
        static func frameRateRange(speed: Double, scale: CGFloat) -> CAFrameRateRange {
            let pixelsPerSecond = Float(speed) * Float(scale)
            let preferred = min(max(pixelsPerSecond, 10), 30)
            return CAFrameRateRange(minimum: min(10, preferred), maximum: 30, preferred: preferred)
        }

        func chapterDidChange() {
            pendingTarget = nil   // it was an offset into the previous document
            endReported = false
            autoY = nil
            pausedUntil = CACurrentMediaTime() + 1   // let the reader see the new chapter's heading
        }

        @objc private func tick(_ link: CADisplayLink) {
            let now = link.timestamp
            let dt = min(now - lastTick, 0.1)
            lastTick = now
            guard let view = textView else { return }
            // The reader's finger, a fling or a page animation wins; resume from wherever it leaves off.
            if view.isTracking || view.isDragging || view.isDecelerating || now < pausedUntil {
                autoY = nil
                return
            }
            let maxOffset = max(view.contentSize.height - view.bounds.height, 0)
            if view.contentOffset.y >= maxOffset - 0.5 {
                if !endReported {
                    endReported = true
                    report()
                    parent.onReachedEnd()
                }
                return
            }
            var y = autoY ?? view.contentOffset.y
            if abs(y - view.contentOffset.y) > 2 { y = view.contentOffset.y }
            y = min(y + CGFloat(autoScrollSpeed * dt), maxOffset)
            autoY = y
            // Move in whole pixels only; a tick that would not change a pixel costs no redraw or relayout.
            let scale = pixelScale
            let snapped = y >= maxOffset ? maxOffset : (y * scale).rounded(.down) / scale
            if abs(snapped - view.contentOffset.y) >= 0.5 / scale {
                view.contentOffset = CGPoint(x: 0, y: snapped)
            }
            if now - lastAutoReport > 1 {
                lastAutoReport = now
                report()
            }
        }

        private func report() {
            guard let offset = currentTopOffset(), offset != lastReported else { return }
            lastReported = offset
            parent.onVisibleOffsetChanged(offset)
        }

        // MARK: UIScrollViewDelegate

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            updatePullHint()
            // Auto-scroll reports on its own throttle; skip a debounce task per frame.
            if displayLink != nil, !scrollView.isDragging, !scrollView.isDecelerating { return }
            debounce?.cancel()
            debounce = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                self?.report()
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { report() }

        func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) { report() }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            switch pullEdge() {
            case .previous(let distance) where distance >= Self.pullThreshold && parent.previousChapterHint != nil:
                hidePullHint()
                DispatchQueue.main.async { self.parent.onReachedStart() }
                return
            case .next(let distance) where distance >= Self.pullThreshold && parent.nextChapterHint != nil:
                hidePullHint()
                DispatchQueue.main.async { self.parent.onReachedEnd() }
                return
            default:
                break
            }
            if !decelerate { report() }
        }

        // MARK: Pull past the edge to change chapter

        static let pullThreshold: CGFloat = 72
        private var pullLabel: UILabel?

        private enum PullEdge { case previous(CGFloat), next(CGFloat), none }

        /// How far the reader has dragged past the top or bottom of the document.
        private func pullEdge() -> PullEdge {
            guard let view = textView else { return .none }
            let maxOffset = max(view.contentSize.height - view.bounds.height, 0)
            if view.contentOffset.y < 0 { return .previous(-view.contentOffset.y) }
            if view.contentOffset.y > maxOffset { return .next(view.contentOffset.y - maxOffset) }
            return .none
        }

        private func hidePullHint() { pullLabel?.alpha = 0 }

        private func updatePullHint() {
            guard let view = textView else { return }
            let title: String
            let distance: CGFloat
            let atTop: Bool
            switch pullEdge() {
            case .previous(let d) where parent.previousChapterHint != nil && view.isTracking:
                (distance, atTop) = (d, true)
                title = (d >= Self.pullThreshold ? "松开进入上一卷" : "下拉进入上一卷") + "\n" + parent.previousChapterHint!
            case .next(let d) where parent.nextChapterHint != nil && view.isTracking:
                (distance, atTop) = (d, false)
                title = (d >= Self.pullThreshold ? "松开进入下一卷" : "上拉进入下一卷") + "\n" + parent.nextChapterHint!
            default:
                hidePullHint()
                return
            }
            let label = pullLabel ?? {
                let label = UILabel()
                label.numberOfLines = 2
                label.textAlignment = .center
                label.font = .preferredFont(forTextStyle: .footnote)
                label.accessibilityIdentifier = "pullHint"
                view.addSubview(label)
                pullLabel = label
                return label
            }()
            label.text = title
            label.textColor = view.tintColor
            let insets = view.verticalScrollIndicatorInsets
            let height: CGFloat = 44
            // Pinned to the visible band, inside the gap the overscroll opens up.
            let y = atTop
                ? view.contentOffset.y + insets.top + max((distance - height) / 2, 4)
                : view.contentOffset.y + view.bounds.height - insets.bottom - height - max((distance - height) / 2, 4)
            label.frame = CGRect(x: 0, y: y, width: view.bounds.width, height: height)
            label.alpha = min(distance / Self.pullThreshold, 1)
        }

        // MARK: Links and edit menu

        func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
            if case .link(let url) = textItem.content, url == AttributedChapterBuilder.nextChapterURL {
                return UIAction { [weak self] _ in self?.parent.onNextChapter() }
            }
            return defaultAction
        }

        func textView(_ textView: UITextView, menuConfigurationFor textItem: UITextItem, defaultMenu: UIMenu) -> UITextItem.MenuConfiguration? {
            if case .link(let url) = textItem.content, url == AttributedChapterBuilder.nextChapterURL { return nil }
            return .init(menu: defaultMenu)
        }

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard range.length > 0 else { return UIMenu(children: suggestedActions) }
            let selected = (textView.attributedText.string as NSString).substring(with: range)
            let bookmark = UIAction(title: "添加书签", image: UIImage(systemName: "bookmark")) { [weak self] _ in
                self?.parent.onAddBookmark(range, selected)
                textView.selectedRange = NSRange(location: range.location, length: 0)
            }
            let share = UIAction(title: "分享卡片", image: UIImage(systemName: "text.quote")) { [weak self] _ in
                self?.parent.onShareQuote(range, selected)
                textView.selectedRange = NSRange(location: range.location, length: 0)
            }
            return UIMenu(children: [bookmark, share] + suggestedActions)
        }

        // MARK: Center tap

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            parent.onTapCenter()
        }

        @objc func handleSwipe(_ gesture: UISwipeGestureRecognizer) {
            page(gesture.direction == .left ? .next : .previous)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view = textView else { return false }
            if view.selectedRange.length > 0 { return false }
            if gestureRecognizer is UISwipeGestureRecognizer { return true }
            let point = touch.location(in: view)
            let visibleTop = view.contentOffset.y
            let height = view.bounds.height
            let relative = (point.y - visibleTop) / height
            guard relative > 1.0 / 3.0, relative < 2.0 / 3.0 else { return false }
            // Don't swallow taps on the next-chapter link.
            if let position = view.closestPosition(to: point) {
                let index = view.offset(from: view.beginningOfDocument, to: position)
                if index < view.attributedText.length, view.attributedText.attribute(.link, at: index, effectiveRange: nil) != nil {
                    return false
                }
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
