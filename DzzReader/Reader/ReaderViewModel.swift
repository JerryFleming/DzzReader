import Foundation
import SwiftData
import SwiftUI
import DzzCore

/// Drives the reader. A book is shown as one DOCUMENT: the whole book when it is small enough
/// (`LoadedBook.isWholeBook`), otherwise one chapter at a time. Chapters are always positions within the book;
/// progress and bookmarks are stored as (chapter index, source offset within that chapter) in both modes.
@Observable @MainActor
final class ReaderViewModel {
    let book: Book
    private let context: ModelContext
    let settings: ReaderSettings

    private(set) var loaded: LoadedBook?
    /// The chapter at the top of the screen.
    private(set) var chapterIndex = 0
    /// The chapters currently rendered into the text view.
    private(set) var document: Range<Int> = 0..<0
    private(set) var rendered: RenderedChapter?
    private(set) var attributed = NSAttributedString()
    private(set) var contentID = 0
    /// SOURCE offset within the current chapter of the first visible character. This is what gets persisted.
    private(set) var visibleSourceOffset = 0
    var scrollTarget: Int?                   // rendered offset handed to the text view
    var showChrome = false
    var autoScrolling = false {
        didSet { if !autoScrolling { flushProgress() } }
    }
    var error: String?
    var toast: String?

    private var scheme: ColorScheme = .light
    private let wholeBookLimit: Int

    init(book: Book, context: ModelContext, settings: ReaderSettings, wholeBookLimit: Int = LoadedBook.wholeBookLimit) {
        self.book = book
        self.context = context
        self.settings = settings
        self.wholeBookLimit = wholeBookLimit
    }

    // MARK: Derived

    var chapters: [ChapterRange] { loaded?.chapters ?? [] }

    var isWholeBook: Bool { loaded?.isWholeBook ?? false }

    var chapterTitle: String {
        displayed(chapters.indices.contains(chapterIndex) ? chapters[chapterIndex].title : book.title)
    }

    // MARK: Script (繁 ⇄ 简)

    /// The shown document converted to the chosen script, kept so restyles don't convert it again.
    @ObservationIgnored private var convertedText: (contentID: Int, script: ChineseScript, text: String)?

    /// A title or other short text as it should appear on screen.
    func displayed(_ text: String) -> String {
        settings.script.apply(text)
    }

    private func displayText(for rendered: RenderedChapter) -> String? {
        guard let script = settings.script.script else { return nil }
        if let cached = convertedText, cached.contentID == contentID, cached.script == script { return cached.text }
        let text = script.convertKeepingOffsets(rendered.text)
        convertedText = (contentID, script, text)
        return text
    }

    var fraction: Double {
        guard !chapters.isEmpty else { return 0 }
        return ProgressMapper.fraction(chapterIndex: chapterIndex, offsetInChapter: visibleSourceOffset, chapters: chapters)
    }

    var currentSectionIndex: Int? {
        guard chapters.indices.contains(chapterIndex) else { return nil }
        let chapter = chapters[chapterIndex]
        let absolute = chapter.startOffset + visibleSourceOffset
        var current: Int?
        for (i, s) in chapter.sections.enumerated() where s.offset <= absolute { current = i }
        return current
    }

    var hasPrevious: Bool { chapterIndex > 0 }
    var hasNext: Bool { chapterIndex + 1 < chapters.count }

    /// Title of the chapter after the rendered document, when it has to be loaded separately.
    var nextDocumentTitle: String? {
        guard !document.isEmpty, document.upperBound < chapters.count else { return nil }
        return chapters[document.upperBound].title
    }

    /// Title of the chapter before the rendered document, when it has to be loaded separately.
    var previousDocumentTitle: String? {
        guard !document.isEmpty, document.lowerBound > 0 else { return nil }
        return chapters[document.lowerBound - 1].title
    }

    private var bodyLength: Int {
        attributed.length - AttributedChapterBuilder.footerLength(for: nextDocumentTitle)
    }

    // MARK: Offsets

    /// Rendered offset of a (chapter, source offset in chapter) position; the chapter must be in `document`.
    func renderedOffset(chapter index: Int, sourceOffset: Int) -> Int {
        guard let rendered, document.contains(index) else { return 0 }
        let chapter = chapters[index]
        let offset = min(max(sourceOffset, 0), chapter.length)
        return rendered.renderedOffset(forSource: chapter.startOffset - chapters[document.lowerBound].startOffset + offset)
    }

    /// The (chapter, source offset in chapter) position of a rendered offset in the current document.
    func position(forRendered renderedOffset: Int) -> (chapter: Int, offset: Int) {
        guard let rendered, !document.isEmpty else { return (chapterIndex, 0) }
        let clamped = min(max(renderedOffset, 0), max(bodyLength, 0))
        let index = document.lowerBound + ChapterRenderer.chapterIndex(forRendered: clamped, starts: rendered.chapterStarts)
        let chapter = chapters[index]
        let absolute = chapters[document.lowerBound].startOffset + rendered.sourceOffset(forRendered: clamped)
        return (index, min(max(absolute - chapter.startOffset, 0), chapter.length))
    }

    // MARK: Loading

    func load(fileURL: URL? = nil, scheme: ColorScheme) async {
        self.scheme = scheme
        do {
            let result = try await BookLoader.load(book: book, fileURL: fileURL, wholeBookLimit: wholeBookLimit)
            loaded = result
            book.lastOpened = .now

            var index = 0
            var offset = 0
            if let progress = book.progress {
                index = min(max(progress.chapterIndex, 0), result.chapters.count - 1)
                offset = min(max(progress.characterOffset, 0), result.chapters[index].length)
            }
            show(chapter: index, sourceOffset: offset)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Navigation

    func go(toChapter index: Int, sourceOffset: Int = 0) {
        guard chapters.indices.contains(index) else { return }
        show(chapter: index, sourceOffset: sourceOffset)
    }

    func next() { if hasNext { go(toChapter: chapterIndex + 1) } }
    func previous() { if hasPrevious { go(toChapter: chapterIndex - 1) } }

    func go(toFraction fraction: Double) {
        guard !chapters.isEmpty else { return }
        let located = ProgressMapper.locate(fraction: fraction, chapters: chapters)
        show(chapter: located.chapterIndex, sourceOffset: located.offsetInChapter)
    }

    /// Preview for the slider label without moving.
    func preview(fraction: Double) -> String {
        guard !chapters.isEmpty else { return "" }
        let located = ProgressMapper.locate(fraction: fraction, chapters: chapters)
        return chapters[located.chapterIndex].title
    }

    /// Scrolling (auto-scroll, a swipe, or a pull) ran past the end of the document.
    func reachedEnd() {
        if nextDocumentTitle != nil {
            go(toChapter: document.upperBound)
        } else if autoScrolling {
            autoScrolling = false
            toast = "已读完"
        }
    }

    /// A swipe or pull ran past the start of the document: open the previous chapter at its last screen.
    func reachedStart() {
        guard previousDocumentTitle != nil else { return }
        let index = document.lowerBound - 1
        go(toChapter: index, sourceOffset: chapters[index].length)
    }

    private func show(chapter index: Int, sourceOffset: Int) {
        guard let loaded else { return }
        let span = loaded.documentSpan(containing: index)
        if span != document || rendered == nil {
            document = span
            rendered = loaded.rendered(span)
            contentID += 1
            rebuildAttributed()
        }
        chapterIndex = index
        visibleSourceOffset = min(max(sourceOffset, 0), chapters[index].length)
        scrollTarget = renderedOffset(chapter: index, sourceOffset: visibleSourceOffset)
        persistProgress()
    }

    // MARK: Appearance

    func restyle(scheme: ColorScheme) {
        self.scheme = scheme
        rebuildAttributed()
    }

    private func rebuildAttributed() {
        guard let rendered else { return }
        attributed = AttributedChapterBuilder.build(rendered: rendered, text: displayText(for: rendered),
                                                    settings: settings, theme: settings.theme,
                                                    scheme: scheme, nextChapterTitle: nextDocumentTitle.map(displayed))
    }

    // MARK: Progress

    func recordVisibleRenderedOffset(_ renderedOffset: Int) {
        guard rendered != nil else { return }
        let position = position(forRendered: renderedOffset)
        guard position.chapter != chapterIndex || position.offset != visibleSourceOffset else { return }
        chapterIndex = position.chapter
        visibleSourceOffset = position.offset
        persistProgress()
    }

    private func persistProgress() {
        guard !chapters.isEmpty else { return }
        // Auto-scroll reports a new top line about every second. Any change to a model in the context makes every
        // @Query re-fetch, and the shelf under the reader fetches the whole catalogue, so keep the position here
        // and write it into the model only when saving: every 15 s, or when auto-scroll stops, pauses or leaves.
        let now = Date.now
        if autoScrolling, let lastSave, now.timeIntervalSince(lastSave) < Self.autoScrollSaveInterval {
            unsavedProgress = true
            return
        }
        writeProgress()
    }

    static let autoScrollSaveInterval: TimeInterval = 15
    private var lastSave: Date?
    private var unsavedProgress = false

    /// Writes progress held back while auto-scrolling.
    func flushProgress() {
        guard unsavedProgress else { return }
        writeProgress()
    }

    private func writeProgress() {
        guard !chapters.isEmpty else { return }
        lastSave = .now
        unsavedProgress = false
        let fraction = self.fraction
        if let progress = book.progress {
            progress.chapterIndex = chapterIndex
            progress.characterOffset = visibleSourceOffset
            progress.fraction = fraction
            progress.updatedAt = .now
        } else {
            let progress = ReadingProgress(chapterIndex: chapterIndex, characterOffset: visibleSourceOffset, fraction: fraction)
            progress.book = book
            book.progress = progress
        }
        try? context.save()
    }

    // MARK: Sharing

    /// The 分享 card markup for a selection: `书名•卷名::文字`, using the chapter the selection starts in.
    /// The split-part suffix such as （1/3） is dropped from the chapter title, chapter marks and
    /// whitespace from the text, and the card's own markup characters (`::`, `|`) from all three.
    func quoteMarkup(renderedOffset: Int, selection: String) -> String {
        let index = position(forRendered: renderedOffset).chapter
        var chapter = chapters.indices.contains(index) ? chapters[index].title : ""
        chapter = chapter.replacingOccurrences(of: #"[（(]\d+/\d+[）)]$"#, with: "", options: .regularExpression)
        var text = selection.replacingOccurrences(of: "(?m)" + ChapterIndexer.chapterMarkPattern, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"[\s　]+"#, with: "", options: .regularExpression)
        func clean(_ s: String) -> String {
            s.replacingOccurrences(of: "::", with: "：")
                .replacingOccurrences(of: "|", with: "")
                .replacingOccurrences(of: "｜", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let source = [clean(book.title), clean(chapter)].filter { !$0.isEmpty }.joined(separator: "•")
        return source + "::" + clean(text)
    }

    // MARK: Bookmarks

    /// Bookmark at a rendered offset of the text view (a selection), in whichever chapter it falls.
    func addBookmark(renderedOffset: Int, excerpt: String?) {
        let position = position(forRendered: renderedOffset)
        addBookmark(chapter: position.chapter, sourceOffset: position.offset, excerpt: excerpt)
    }

    /// Bookmark at a source offset within the current chapter.
    func addBookmark(sourceOffset: Int, excerpt: String?) {
        addBookmark(chapter: chapterIndex, sourceOffset: sourceOffset, excerpt: excerpt)
    }

    private func addBookmark(chapter index: Int, sourceOffset: Int, excerpt: String?) {
        guard let loaded, chapters.indices.contains(index) else { return }
        let chapter = chapters[index]
        let offset = min(max(sourceOffset, 0), chapter.length)
        let text: String
        if let excerpt, !excerpt.isEmpty {
            text = Self.tidy(excerpt)
        } else {
            let full = loaded.fullText as NSString
            let start = chapter.startOffset + offset
            let length = min(80, full.length - start)
            text = Self.tidy(length > 0 ? full.substring(with: NSRange(location: start, length: length)) : chapter.title)
        }
        let mark = Bookmark(chapterIndex: index, characterOffset: offset, excerpt: String(text.prefix(40)))
        mark.book = book
        book.bookmarks.append(mark)
        try? context.save()
        toast = "已添加书签"
    }

    func jump(to bookmark: Bookmark) {
        go(toChapter: bookmark.chapterIndex, sourceOffset: bookmark.characterOffset)
    }

    func delete(_ bookmark: Bookmark) {
        context.delete(bookmark)
        try? context.save()
    }

    private static func tidy(_ s: String) -> String {
        var t = s.replacingOccurrences(of: ChapterIndexer.chapterMarkPattern, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[\s　]+"#, with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespaces)
    }
}
