import SwiftUI
import UIKit

enum PageCommand { case previous, next }

/// The reading surface: a TextKit 2 UITextView showing one chapter.
/// All offsets crossing this boundary are RENDERED offsets (UTF-16 units into `attributedText`).
struct ChapterTextView: UIViewRepresentable {
    let attributedText: NSAttributedString
    let contentID: Int                       // changes when a different chapter is shown
    let backgroundColor: UIColor
    let tintColor: UIColor
    let margin: CGFloat
    @Binding var scrollTarget: Int?          // rendered offset to place at the top; cleared after scrolling
    var autoScrollSpeed: Double?             // points per second; nil when auto-scroll is off or paused
    var onVisibleOffsetChanged: (Int) -> Void
    var onNextChapter: () -> Void
    var onAddBookmark: (NSRange, String) -> Void
    var onTapCenter: () -> Void
    var onReachedEnd: () -> Void             // auto-scroll or a next-screen swipe hit the end of the chapter

    static func dismantleUIView(_ view: UITextView, coordinator: Coordinator) {
        coordinator.setAutoScroll(speed: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = ReaderTextView(usingTextLayoutManager: true)
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = true
        view.alwaysBounceVertical = true
        view.showsVerticalScrollIndicator = true
        view.delegate = context.coordinator
        view.textContainer.lineFragmentPadding = 0
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
        view.backgroundColor = backgroundColor
        view.tintColor = tintColor
        view.linkTextAttributes = [.foregroundColor: tintColor]
        (view as? ReaderTextView)?.horizontalMargin = margin

        if contentChanged {
            let chapterChanged = coordinator.contentID != contentID
            coordinator.contentID = contentID
            coordinator.attributedText = attributedText
            // Keep the reading position across a restyle of the same chapter.
            let keep = chapterChanged ? nil : coordinator.currentTopOffset()
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
    final class ReaderTextView: UITextView {
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

        private func updateInsets() {
            let safe = window?.safeAreaInsets ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
            let insets = UIEdgeInsets(top: safe.top + Self.topPadding, left: horizontalMargin,
                                      bottom: safe.bottom + Self.bottomPadding, right: horizontalMargin)
            if textContainerInset != insets { textContainerInset = insets }
            verticalScrollIndicatorInsets = UIEdgeInsets(top: safe.top, left: 0, bottom: safe.bottom, right: 0)
        }
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

        /// Rendered offset of the first visible line.
        func currentTopOffset() -> Int? {
            guard let view = textView, let layout = view.textLayoutManager, let content = layout.textContentManager else { return nil }
            // The text inset is the window safe area plus the fixed top padding, so the first line below
            // the status bar sits `topPadding` above the container origin.
            let y = max(view.contentOffset.y - ReaderTextView.topPadding, 0)
            guard let fragment = layout.textLayoutFragment(for: CGPoint(x: 0, y: y)) else { return nil }
            var location = fragment.rangeInElement.location
            let frameY = fragment.layoutFragmentFrame.minY
            for line in fragment.textLineFragments {
                let lineBottom = frameY + line.typographicBounds.maxY
                if lineBottom > y + 1 {
                    if let loc = content.location(fragment.rangeInElement.location, offsetBy: line.characterRange.location) {
                        location = loc
                    }
                    break
                }
            }
            return content.offset(from: content.documentRange.location, to: location)
        }

        func scroll(toRenderedOffset offset: Int) {
            guard let view = textView, let layout = view.textLayoutManager, let content = layout.textContentManager else { return }
            view.layoutIfNeeded()
            let length = view.attributedText?.length ?? 0
            let clamped = min(max(offset, 0), max(length - 1, 0))
            guard let location = content.location(content.documentRange.location, offsetBy: clamped) else { return }
            layout.ensureLayout(for: NSTextRange(location: content.documentRange.location, end: location) ?? content.documentRange)
            guard let fragment = layout.textLayoutFragment(for: location) else { return }
            var y = fragment.layoutFragmentFrame.minY
            let within = content.offset(from: fragment.rangeInElement.location, to: location)
            for line in fragment.textLineFragments where line.characterRange.contains(within) {
                y += line.typographicBounds.minY
                break
            }
            let target = y + ReaderTextView.topPadding
            let maxY = max(view.contentSize.height - view.bounds.height, 0)
            view.setContentOffset(CGPoint(x: 0, y: min(max(target, 0), maxY)), animated: false)
            report()
        }

        // MARK: Screen paging

        /// Top and bottom (text-container coordinates) of the line at `y`, or of the next line when `y` falls between lines.
        private func line(at y: CGFloat, depth: Int = 0) -> (minY: CGFloat, maxY: CGFloat)? {
            guard depth < 3, let layout = textView?.textLayoutManager,
                  let fragment = layout.textLayoutFragment(for: CGPoint(x: 0, y: max(y, 0))) else { return nil }
            let frameY = fragment.layoutFragmentFrame.minY
            for line in fragment.textLineFragments {
                let bounds = line.typographicBounds
                if frameY + bounds.maxY > y { return (frameY + bounds.minY, frameY + bounds.maxY) }
            }
            return line(at: fragment.layoutFragmentFrame.maxY + 0.5, depth: depth + 1)
        }

        /// Scrolls one screen, aligned so the line cut off at the bottom becomes the first line (and vice versa).
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
                // First line not fully visible at the bottom.
                let lineTop = line(at: top + visible)?.minY ?? top + visible
                target = (lineTop > top + 1 ? lineTop : top + visible) + padding
            case .previous:
                guard view.contentOffset.y > 0.5 else { return }
                // First fully visible line becomes the first line below the new screen.
                var anchor = top
                if let current = line(at: top) {
                    anchor = current.minY >= top - 0.5 ? current.minY : (line(at: current.maxY + 0.5)?.minY ?? current.maxY)
                }
                let newTop = anchor - visible
                var lineTop = newTop
                if let candidate = line(at: newTop) {
                    lineTop = candidate.minY >= newTop - 0.5 ? candidate.minY : (line(at: candidate.maxY + 0.5)?.minY ?? candidate.maxY)
                }
                target = (lineTop < anchor - 1 ? lineTop : newTop) + padding
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
            autoScrollSpeed = speed
            guard displayLink == nil else { return }
            endReported = false
            autoY = nil
            lastTick = CACurrentMediaTime()
            lastAutoReport = lastTick
            let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func chapterDidChange() {
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
            view.contentOffset = CGPoint(x: 0, y: y)
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
            if !decelerate { report() }
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
            return UIMenu(children: [bookmark] + suggestedActions)
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
