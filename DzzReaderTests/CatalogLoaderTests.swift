import Foundation
import SwiftData
import Testing
import DzzCore
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

    /// A books folder without toc.txt: every .txt (any depth, hidden files skipped) in name order, no 部.
    private func makeTocless() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "Tocless-\(UUID().uuidString)")
        let files = ["心经.txt": "观自在菩萨", "卷/金刚经.txt": "如是我闻", ".hidden/x.txt": "skip", "notes.md": "skip"]
        for (path, text) in files {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        return root
    }

    @Test func withoutTocBooksGoInTheUnnamedGroup() throws {
        let root = try makeTocless()
        defer { try? FileManager.default.removeItem(at: root) }
        let count = try CatalogLoader.load(booksDirectory: root, context: context)
        #expect(count == 2)
        let books = try context.fetch(FetchDescriptor<Book>(sortBy: [SortDescriptor(\.catalogOrder)]))
        #expect(books.map(\.title) == ["金刚经", "心经"])   // "卷/金刚经.txt" sorts before "心经.txt"
        #expect(books.allSatisfy { $0.section == nil && $0.source == .bundled && $0.canonNumber == nil })
        #expect(books.first?.relativePath == "Books/卷/金刚经.txt")
        #expect(books.first?.id == "F:卷/金刚经.txt")
    }

    @Test func downloadingMoreBooksKeepsExistingOnes() throws {
        _ = try CatalogLoader.load(booksDirectory: TestFixtures.miniBooks, context: context)
        let imported = Book(id: UUID().uuidString, title: "导入", source: .imported, relativePath: "Imported/x.txt",
                            section: nil, juanCount: nil, author: nil, catalogOrder: 0, byteSize: 1, encodingName: "utf-8")
        context.insert(imported)
        try context.save()

        let root = try makeTocless()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try CatalogLoader.load(booksDirectory: root, context: context)
        let books = try context.fetch(FetchDescriptor<Book>())
        #expect(books.count == 7)                                   // 4 + 2 downloaded, plus the imported one
        #expect(books.contains { $0.id.hasPrefix("T") })
        #expect(books.contains { $0.source == .imported })
    }

    @Test func deletingDownloadedBooksRemovesTheirFiles() throws {
        let book = Book(id: "F:test-\(UUID().uuidString).txt", title: "删", source: .bundled,
                        relativePath: "Books/test-\(UUID().uuidString).txt", section: nil, juanCount: nil,
                        author: nil, catalogOrder: 0, byteSize: 1, encodingName: "utf-8")
        try FileManager.default.createDirectory(at: book.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: book.fileURL)
        context.insert(book)
        try context.save()

        try Importer.delete([book], context: context)
        #expect(!FileManager.default.fileExists(atPath: book.fileURL.path))
        #expect(try context.fetch(FetchDescriptor<Book>()).isEmpty)
    }
}
