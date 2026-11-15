import Foundation
import SwiftData
import SwiftUI
import DzzCore

@Observable @MainActor
final class ReaderViewModel {
    let book: Book
    private let context: ModelContext
    let settings: ReaderSettings

    private(set) var loaded: LoadedBook?
    private(set) var chapterIndex = 0
    private(set) var rendered: RenderedChapter?
    private(set) var attributed = NSAttributedString()
    private(set) var contentID = 0
    /// SOURCE offset within the current chapter of the first visible character. This is what gets persisted.
    private(set) var visibleSourceOffset = 0
    var scrollTarget: Int?                   // rendered offset handed to the text view
    var showChrome = false
    var error: String?
    var toast: String?

    private var scheme: ColorScheme = .light

    init(book: Book, context: ModelContext, settings: ReaderSettings) {
        self.book = book
        self.context = context
        self.settings = settings
    }

    // MARK: Derived

    var chapters: [ChapterRange] { loaded?.chapters ?? [] }

    var chapterTitle: String {
        chapters.indices.contains(chapterIndex) ? chapters[chapterIndex].title : book.title
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

    private var bodyLength: Int {
        attributed.length - AttributedChapterBuilder.footerLength(for: hasNext ? chapters[chapterIndex + 1].title : nil)
    }

    // MARK: Loading

    func load(fileURL: URL? = nil, scheme: ColorScheme) async {
        self.scheme = scheme
        do {
            let result = try await BookLoader.load(book: book, fileURL: fileURL)
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

    private func show(chapter index: Int, sourceOffset: Int) {
        guard let loaded else { return }
        let chapterChanged = index != chapterIndex || rendered == nil
        chapterIndex = index
        if chapterChanged {
            rendered = loaded.rendered(index)
            contentID += 1
            rebuildAttributed()
        }
        visibleSourceOffset = min(max(sourceOffset, 0), chapters[index].length)
        scrollTarget = rendered?.renderedOffset(forSource: visibleSourceOffset) ?? 0
        persistProgress()
    }

    // MARK: Appearance

    func restyle(scheme: ColorScheme) {
        self.scheme = scheme
        rebuildAttributed()
    }

    private func rebuildAttributed() {
        guard let rendered else { return }
        let nextTitle = hasNext ? chapters[chapterIndex + 1].title : nil
        attributed = AttributedChapterBuilder.build(rendered: rendered, settings: settings, theme: settings.theme,
                                                    scheme: scheme, nextChapterTitle: nextTitle)
    }

    // MARK: Progress

    func recordVisibleRenderedOffset(_ renderedOffset: Int) {
        guard let rendered else { return }
        let clamped = min(max(renderedOffset, 0), max(bodyLength, 0))
        let source = rendered.sourceOffset(forRendered: clamped)
        guard source != visibleSourceOffset else { return }
        visibleSourceOffset = source
        persistProgress()
    }

    private func persistProgress() {
        guard !chapters.isEmpty else { return }
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

    // MARK: Bookmarks

    func addBookmark(sourceOffset: Int, excerpt: String?) {
        guard let loaded, chapters.indices.contains(chapterIndex) else { return }
        let chapter = chapters[chapterIndex]
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
        let mark = Bookmark(chapterIndex: chapterIndex, characterOffset: offset, excerpt: String(text.prefix(40)))
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
