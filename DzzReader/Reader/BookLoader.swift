import Foundation
import SwiftData
import DzzCore

struct LoadedBook: Sendable {
    let fullText: String
    let chapters: [ChapterRange]
    let isWholeBook: Bool

    /// Books up to this many UTF-16 units are shown as one continuous document; larger ones a chapter at a time.
    static let wholeBookLimit = 300_000

    init(fullText: String, chapters: [ChapterRange], wholeBookLimit: Int = LoadedBook.wholeBookLimit) {
        self.fullText = fullText
        self.chapters = chapters
        self.isWholeBook = fullText.utf16.count <= wholeBookLimit
    }

    var hasFrontMatter: Bool { chapters.first?.title == "卷首" }

    /// The chapters shown together with chapter `index`: the whole book, or just that chapter.
    func documentSpan(containing index: Int) -> Range<Int> {
        let i = min(max(index, 0), chapters.count - 1)
        return isWholeBook ? 0..<chapters.count : i..<(i + 1)
    }

    func rendered(_ span: Range<Int>) -> RenderedChapter {
        ChapterRenderer.render(fullText: fullText, chapters: chapters, span: span, hasFrontMatter: hasFrontMatter)
    }
}

enum BookLoadError: LocalizedError {
    case undecodable

    var errorDescription: String? {
        switch self {
        case .undecodable: "无法读取这本书的文字编码。"
        }
    }
}

@MainActor
enum BookLoader {
    /// Reads and decodes the file, reusing the cached chapter index when the file size is unchanged.
    static func load(book: Book, fileURL: URL? = nil, wholeBookLimit: Int = LoadedBook.wholeBookLimit) async throws -> LoadedBook {
        let url = fileURL ?? book.fileURL
        let title = book.title
        let cached: [ChapterRange]? = book.needsIndexing ? nil : book.chapters

        let result = try await Task.detached(priority: .userInitiated) { () throws -> LoadedBook in
            let data = try Data(contentsOf: url)
            guard let decoded = TextDecoder.decode(data) else { throw BookLoadError.undecodable }
            let chapters = cached ?? ChapterIndexer.index(text: decoded.text, bookTitle: title)
            return LoadedBook(fullText: decoded.text, chapters: chapters, wholeBookLimit: wholeBookLimit)
        }.value

        if cached == nil {
            book.chapters = result.chapters
            book.indexedByteSize = book.byteSize
        }
        return result
    }
}
