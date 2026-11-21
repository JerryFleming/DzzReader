import Foundation
import SwiftData
import DzzCore

enum ImportError: Error, LocalizedError {
    case undecodable(String)
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .undecodable(let name): "无法识别「\(name)」的文字编码。"
        case .unreadable(let name): "无法读取「\(name)」。"
        }
    }
}

/// Copies txt files into Documents/Imported as UTF-8 and registers them as books.
@MainActor
enum Importer {
    static var importedDirectory: URL {
        let url = URL.documentsDirectory.appending(path: "Imported")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static let headerTitle = try! NSRegularExpression(pattern: #"^(?:大正藏\s*)?No\.\s*\S+\s+(.+)$"#)

    @discardableResult
    static func importFile(at url: URL, context: ModelContext) throws -> Book {
        let name = url.lastPathComponent
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ImportError.unreadable(name)
        }
        guard let decoded = TextDecoder.decode(data) else { throw ImportError.undecodable(name) }

        let id = UUID().uuidString
        let relativePath = "Imported/\(id).txt"
        let destination = importedDirectory.appending(path: "\(id).txt")
        let utf8 = Data(decoded.text.utf8)
        try utf8.write(to: destination, options: .atomic)

        let title = titleFor(text: decoded.text, filename: name)
        let book = Book(id: id, title: title, source: .imported, relativePath: relativePath,
                        section: nil, juanCount: nil, author: nil, catalogOrder: 0,
                        byteSize: utf8.count, encodingName: decoded.encodingName)
        book.chapters = ChapterIndexer.index(text: decoded.text, bookTitle: title)
        book.indexedByteSize = utf8.count
        context.insert(book)
        try context.save()

        // Files handed over by other apps land in Documents/Inbox; the copy is ours now, so tidy up.
        if url.path.contains("/Inbox/") {
            try? FileManager.default.removeItem(at: url)
        }
        return book
    }

    /// Removes books from the shelf along with their files (imported or downloaded), progress and bookmarks.
    /// A deleted downloaded book comes back only if an archive containing it is downloaded again.
    static func delete(_ books: [Book], context: ModelContext) throws {
        for book in books {
            try? FileManager.default.removeItem(at: book.fileURL)
            context.delete(book)
        }
        try context.save()
    }

    static func delete(_ book: Book, context: ModelContext) throws {
        try delete([book], context: context)
    }

    /// Title from the canon header line when present, else the filename without extension.
    static func titleFor(text: String, filename: String) -> String {
        let fallback = (filename as NSString).deletingPathExtension
        guard let firstLine = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map({ ChapterIndexer.normalise($0) }).first(where: { !$0.isEmpty }) else { return fallback }
        let ns = firstLine as NSString
        if let m = headerTitle.firstMatch(in: firstLine, range: NSRange(location: 0, length: ns.length)) {
            let title = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty { return title }
        }
        return fallback
    }
}
