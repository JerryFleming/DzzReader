import Foundation
import SwiftData
import Testing
@testable import DzzReader

final class TestBundleAnchor {}

enum TestFixtures {
    static var root: URL {
        Bundle(for: TestBundleAnchor.self).resourceURL!.appending(path: "Fixtures")
    }
    static var miniBooks: URL { root.appending(path: "MiniBooks") }
}

@Suite @MainActor struct CatalogLoaderTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer.inMemory()
    }

    @Test func loadsOnlyFilesThatExist() throws {
        let count = try CatalogLoader.load(booksDirectory: TestFixtures.miniBooks, context: context)
        #expect(count == 4)
        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.count == 4)
        let b = books.first { $0.id == "T0002" }
        #expect(b?.title == "佛说七佛经")   // toc title wins over the filename
        #expect(b?.section == "阿含部")
        #expect(b?.juanCount == 1)
        #expect(b?.author == "宋 法天译")
        #expect(b?.relativePath == "Books/00/0002七佛经.txt")
        #expect(b?.catalogOrder == 2000)
        #expect(b?.source == .bundled)
        #expect(b?.byteSize == 18283)
        #expect(b?.chapters.isEmpty == true)
    }

    @Test func suffixNumberIsKept() throws {
        _ = try CatalogLoader.load(booksDirectory: TestFixtures.miniBooks, context: context)
        let b = try context.fetch(FetchDescriptor<Book>()).first { $0.id == "T0894a" }
        #expect(b?.section == "密教部")
        #expect(b?.catalogOrder == 894001)
        #expect(b?.title == "苏悉地羯罗供养法")
    }

    @Test func fileWithoutTocEntryUsesFilename() throws {
        _ = try CatalogLoader.load(booksDirectory: TestFixtures.miniBooks, context: context)
        let b = try context.fetch(FetchDescriptor<Book>()).first { $0.id == "T9999" }
        #expect(b?.title == "无目录经")
        #expect(b?.section == nil)
        #expect(b?.juanCount == nil)
    }

    @Test func secondLoadIsNoOp() throws {
        let defaults = UserDefaults(suiteName: "CatalogLoaderTests-\(UUID().uuidString)")!
        let first = try CatalogLoader.loadIfNeeded(booksDirectory: TestFixtures.miniBooks, context: context, defaults: defaults)
        let second = try CatalogLoader.loadIfNeeded(booksDirectory: TestFixtures.miniBooks, context: context, defaults: defaults)
        #expect(first == 4)
        #expect(second == 0)
        #expect(try context.fetch(FetchDescriptor<Book>()).count == 4)
    }

    @Test func deletingBookCascades() throws {
        let book = Book(id: "X", title: "测试", source: .imported, relativePath: "Imported/x.txt",
                        section: nil, juanCount: nil, author: nil, catalogOrder: 0, byteSize: 1, encodingName: "utf-8")
        context.insert(book)
        let progress = ReadingProgress(chapterIndex: 0, characterOffset: 3, fraction: 0.1)
        progress.book = book
        book.progress = progress
        let mark = Bookmark(chapterIndex: 0, characterOffset: 5, excerpt: "摘")
        mark.book = book
        book.bookmarks.append(mark)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<ReadingProgress>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<Bookmark>()).count == 1)

        context.delete(book)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Book>()).count == 0)
        #expect(try context.fetch(FetchDescriptor<ReadingProgress>()).count == 0)
        #expect(try context.fetch(FetchDescriptor<Bookmark>()).count == 0)
    }
}
