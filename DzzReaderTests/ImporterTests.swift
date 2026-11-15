import Foundation
import SwiftData
import Testing
import DzzCore
@testable import DzzReader

@Suite(.serialized) @MainActor struct ImporterTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let scratch: URL

    init() throws {
        container = try ModelContainer.inMemory()
        scratch = FileManager.default.temporaryDirectory.appending(path: "ImporterTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    private func write(_ data: Data, name: String) throws -> URL {
        let url = scratch.appending(path: name)
        try data.write(to: url)
        return url
    }

    @Test func importsUTF8File() throws {
        let text = "大正藏 No. 0026 中阿含经\n　　东晋 瞿昙僧伽提婆译\n\n　　60卷\n第0章 甲卷第一\n　　正文。\n"
        let url = try write(Data(text.utf8), name: "anything.txt")
        let book = try Importer.importFile(at: url, context: context)
        #expect(book.title == "中阿含经")
        #expect(book.source == .imported)
        #expect(book.encodingName == "utf-8")
        #expect(book.chapters.count >= 1)
        #expect(book.relativePath == "Imported/\(book.id).txt")
        #expect(FileManager.default.fileExists(atPath: Importer.importedDirectory.appending(path: "\(book.id).txt").path))
        #expect(book.byteSize == text.utf8.count)
        try Importer.delete(book, context: context)
    }

    @Test func importsGB18030UsingFilenameTitle() throws {
        let text = "佛说四十二章经\n如是我闻"
        let url = try write(text.data(using: TextDecoder.gb18030)!, name: "四十二章经.txt")
        let book = try Importer.importFile(at: url, context: context)
        #expect(book.title == "四十二章经")
        #expect(book.encodingName == "gb18030")
        let stored = try String(contentsOf: book.fileURL, encoding: .utf8)
        #expect(stored == text)
        try Importer.delete(book, context: context)
    }

    @Test func undecodableFileThrows() throws {
        let url = try write(Data([0x80, 0x80, 0xFF, 0xFF]), name: "garbage.txt")
        let before = (try? FileManager.default.contentsOfDirectory(atPath: Importer.importedDirectory.path).count) ?? 0
        #expect(throws: ImportError.self) { try Importer.importFile(at: url, context: context) }
        #expect(try context.fetch(FetchDescriptor<Book>()).isEmpty)
        let after = (try? FileManager.default.contentsOfDirectory(atPath: Importer.importedDirectory.path).count) ?? 0
        #expect(after == before)
    }

    @Test func deleteRemovesFileAndModel() throws {
        let url = try write(Data("只有一行。".utf8), name: "one.txt")
        let book = try Importer.importFile(at: url, context: context)
        let stored = book.fileURL
        #expect(FileManager.default.fileExists(atPath: stored.path))
        try Importer.delete(book, context: context)
        #expect(!FileManager.default.fileExists(atPath: stored.path))
        #expect(try context.fetch(FetchDescriptor<Book>()).isEmpty)
    }

    @Test func titleFallsBackToFilenameWithoutCanonHeader() throws {
        let url = try write(Data("第一行不是经名\n正文".utf8), name: "我的笔记.txt")
        let book = try Importer.importFile(at: url, context: context)
        #expect(book.title == "我的笔记")
        try Importer.delete(book, context: context)
    }
}
