import Foundation
import SwiftData
import Testing
import DzzCore
@testable import DzzReader

@Suite(.serialized) @MainActor struct ChantLibraryTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let scratch: URL

    init() throws {
        container = try ModelContainer.inMemory()
        scratch = FileManager.default.temporaryDirectory.appending(path: "ChantLibraryTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    private func write(_ text: String, name: String, in dir: URL? = nil) throws -> URL {
        let folder = dir ?? scratch
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try Data(text.utf8).write(to: url)
        return url
    }

    private let sample = #"[{"type":"passage","style":"title"},{"char":"心","pinyin":"xīn"},{"type":"linebreak"},{"char":"经","pinyin":"jīng"}]"#

    @Test func bundledTextParsesWithTitlesAndPinyin() async throws {
        try ChantLibrary.syncBundled(context: context)
        let books = try context.fetch(FetchDescriptor<ChantBook>())
        let book = try #require(books.first { $0.title == "佛教念诵集" })
        #expect(book.source == .bundled)
        #expect(book.relativePath == "ChantingTexts/佛教念诵集.json")
        let doc = try await ChantLibrary.load(book)
        #expect(doc.rows.first?.text == "大佛顶首楞严神咒")
        #expect(doc.rows.first?.cells.first?.pinyin == "dà")
        let titles = doc.titleRows.map(\.text)
        #expect(titles.contains("般若波罗蜜多心经"))
        #expect(titles.count == 28)
    }

    @Test func syncBundledKeepsRecentsAndDropsMissingFiles() throws {
        let root = scratch.appending(path: "Res")
        let folder = root.appending(path: ChantLibrary.bundledFolder)
        _ = try write(sample, name: "甲.json", in: folder)
        let second = try write(sample, name: "乙.json", in: folder)
        _ = try write("not json", name: "readme.txt", in: folder)

        try ChantLibrary.syncBundled(resourceRoot: root, context: context)
        var books = try context.fetch(FetchDescriptor<ChantBook>())
        #expect(Set(books.map(\.title)) == ["甲", "乙"])
        let opened = Date(timeIntervalSince1970: 1_000)
        try #require(books.first { $0.title == "甲" }).lastOpened = opened

        try FileManager.default.removeItem(at: second)
        try ChantLibrary.syncBundled(resourceRoot: root, context: context)
        books = try context.fetch(FetchDescriptor<ChantBook>())
        #expect(books.map(\.title) == ["甲"])
        #expect(books.first?.lastOpened == opened)   // re-syncing keeps it under 最近阅读
    }

    @Test func importsValidJSONUsingFileName() throws {
        let url = try write(sample, name: "心经.json")
        let book = try ChantLibrary.importFile(at: url, context: context)
        #expect(book.title == "心经")
        #expect(book.source == .imported)
        #expect(book.relativePath == "ImportedChanting/\(book.id).json")
        #expect(FileManager.default.fileExists(atPath: book.fileURL.path))
        try ChantLibrary.delete(book, context: context)
        #expect(!FileManager.default.fileExists(atPath: book.fileURL.path))
        #expect(try context.fetch(FetchDescriptor<ChantBook>()).isEmpty)
    }

    @Test func rejectsJSONThatIsNotAChantText() throws {
        let url = try write(#"{"title":"x"}"#, name: "other.json")
        #expect(throws: ChantImportError.self) { try ChantLibrary.importFile(at: url, context: context) }
        #expect(try context.fetch(FetchDescriptor<ChantBook>()).isEmpty)
    }

    @Test func deletedBundledTextStaysDeletedAfterSync() throws {
        let defaults = UserDefaults(suiteName: "ChantLibraryTests-\(UUID().uuidString)")!
        let root = scratch.appending(path: "Res")
        let folder = root.appending(path: ChantLibrary.bundledFolder)
        _ = try write(sample, name: "甲.json", in: folder)
        _ = try write(sample, name: "乙.json", in: folder)
        try ChantLibrary.syncBundled(resourceRoot: root, context: context, defaults: defaults)
        let jia = try #require(try context.fetch(FetchDescriptor<ChantBook>()).first { $0.title == "甲" })

        try ChantLibrary.delete(jia, context: context, defaults: defaults)
        try ChantLibrary.syncBundled(resourceRoot: root, context: context, defaults: defaults)
        #expect(try context.fetch(FetchDescriptor<ChantBook>()).map(\.title) == ["乙"])
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "甲.json").path))   // bundle untouched
    }
}
