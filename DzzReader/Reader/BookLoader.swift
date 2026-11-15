import Foundation
import SwiftData
import DzzCore

struct LoadedBook: Sendable {
    let fullText: String
    let chapters: [ChapterRange]

    var hasFrontMatter: Bool { chapters.first?.title == "卷首" }

    func rendered(_ index: Int) -> RenderedChapter {
        let i = min(max(index, 0), chapters.count - 1)
        return ChapterRenderer.render(fullText: fullText, chapter: chapters[i], isFrontMatter: i == 0 && hasFrontMatter)
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
    static func load(book: Book, fileURL: URL? = nil) async throws -> LoadedBook {
        let url = fileURL ?? book.fileURL
        let title = book.title
        let cached: [ChapterRange]? = book.needsIndexing ? nil : book.chapters

        let result = try await Task.detached(priority: .userInitiated) { () throws -> LoadedBook in
            let data = try Data(contentsOf: url)
            guard let decoded = TextDecoder.decode(data) else { throw BookLoadError.undecodable }
            let chapters = cached ?? ChapterIndexer.index(text: decoded.text, bookTitle: title)
            return LoadedBook(fullText: decoded.text, chapters: chapters)
        }.value

        if cached == nil {
            book.chapters = result.chapters
            book.indexedByteSize = book.byteSize
        }
        return result
    }
}
