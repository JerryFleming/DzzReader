import Foundation
import SwiftData
import Testing
import DzzCore
@testable import DzzReader

@Suite @MainActor struct BookLoaderTests {
    @Test func indexesAndCachesChapters() async throws {
        let container = try ModelContainer.inMemory()
        let context = container.mainContext
        let fixture = TestFixtures.root.appending(path: "marked-3juan.txt")
        let size = try FileManager.default.attributesOfItem(atPath: fixture.path)[.size] as! Int
        let book = Book(id: "T0001", title: "长阿含经", source: .bundled, relativePath: "Books/00/0001长阿含经.txt",
                        section: "阿含部", juanCount: 22, author: nil, catalogOrder: 1000, byteSize: size, encodingName: "utf-8")
        context.insert(book)
        #expect(book.needsIndexing)

        let loaded = try await BookLoader.load(book: book, fileURL: fixture)
        #expect(loaded.chapters.count == 4)
        #expect(loaded.hasFrontMatter)
        #expect(book.chapters.count == 4)
        #expect(book.indexedByteSize == size)
        #expect(!book.needsIndexing)
        #expect(loaded.rendered(1).text.hasPrefix("　　　　佛说长阿含经卷第一"))

        // Second load must use the cache: plant a sentinel index and expect it back untouched.
        let sentinel = [ChapterRange(title: "哨兵", startOffset: 0, endOffset: (loaded.fullText as NSString).length, sections: [])]
        book.chapters = sentinel
        let again = try await BookLoader.load(book: book, fileURL: fixture)
        #expect(again.chapters == sentinel)
    }

    @Test func reindexesWhenSizeChanged() async throws {
        let container = try ModelContainer.inMemory()
        let fixture = TestFixtures.root.appending(path: "marked-3juan.txt")
        let book = Book(id: "T0001", title: "长阿含经", source: .bundled, relativePath: "x", section: nil, juanCount: nil,
                        author: nil, catalogOrder: 0, byteSize: 1, encodingName: "utf-8")
        container.mainContext.insert(book)
        book.chapters = [ChapterRange(title: "旧", startOffset: 0, endOffset: 1, sections: [])]
        book.indexedByteSize = 999
        let loaded = try await BookLoader.load(book: book, fileURL: fixture)
        #expect(loaded.chapters.count == 4)
    }
}
