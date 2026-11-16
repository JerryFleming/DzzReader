import CryptoKit
import Foundation
import SwiftData
import DzzCore

/// Builds the shelf from the bundled corpus: toc.txt joined with the files that actually exist.
@MainActor
enum CatalogLoader {
    static let hashKey = "catalogHash"

    /// Loads only when the bundled toc.txt or file count changed since the last load. Returns books upserted.
    static func loadIfNeeded(booksDirectory: URL, context: ModelContext, defaults: UserDefaults = .standard) throws -> Int {
        let hash = try catalogHash(booksDirectory: booksDirectory)
        if defaults.string(forKey: hashKey) == hash { return 0 }
        let count = try load(booksDirectory: booksDirectory, context: context)
        defaults.set(hash, forKey: hashKey)
        return count
    }

    static func load(booksDirectory: URL, context: ModelContext) throws -> Int {
        let tocText = try String(contentsOf: booksDirectory.appending(path: "toc.txt"), encoding: .utf8)
        let toc = TocParser.parse(tocText)
        let entries = Dictionary(toc.entries.map { ($0.number, $0) }, uniquingKeysWith: { a, _ in a })

        var existing: [String: Book] = [:]
        let bundled = BookSource.bundled.rawValue
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.sourceRaw == bundled })
        for book in try context.fetch(descriptor) { existing[book.id] = book }

        var count = 0
        for file in try bookFiles(in: booksDirectory) {
            guard let number = CanonNumber.parse(filename: file.name) else { continue }
            let entry = entries[number]
            let id = "T" + number
            let title = entry?.title ?? String(file.name.dropFirst(number.count).dropLast(4))
            let section = toc.section(forNumber: number)?.name
            let relativePath = "Books/\(file.directory)/\(file.name)"

            if let book = existing[id] {
                book.title = title
                book.section = section
                book.juanCount = entry?.juanCount
                book.author = entry?.author
                book.catalogOrder = CanonNumber.sortKey(number)
                book.relativePath = relativePath
                book.byteSize = file.size
            } else {
                let book = Book(id: id, title: title, source: .bundled, relativePath: relativePath,
                                section: section, juanCount: entry?.juanCount, author: entry?.author,
                                catalogOrder: CanonNumber.sortKey(number), byteSize: file.size, encodingName: "utf-8")
                context.insert(book)
            }
            count += 1
        }
        try context.save()
        return count
    }

    // MARK: - Files

    private struct BookFile {
        let directory: String
        let name: String
        let size: Int
    }

    private static func bookFiles(in root: URL) throws -> [BookFile] {
        let fm = FileManager.default
        var result: [BookFile] = []
        let dirs = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { $0.lastPathComponent.range(of: #"^\d\d$"#, options: .regularExpression) != nil }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for dir in dirs {
            let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])
                .filter { $0.pathExtension == "txt" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for file in files {
                let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                result.append(BookFile(directory: dir.lastPathComponent, name: file.lastPathComponent, size: size))
            }
        }
        return result
    }

    /// Changes when toc.txt, the file count, or any file size changes, so a replaced corpus invalidates cached indexes.
    private static func catalogHash(booksDirectory: URL) throws -> String {
        let toc = try Data(contentsOf: booksDirectory.appending(path: "toc.txt"))
        let files = try bookFiles(in: booksDirectory)
        let totalSize = files.reduce(0) { $0 + $1.size }
        var hasher = SHA256()
        hasher.update(data: toc)
        hasher.update(data: Data("\(files.count):\(totalSize)".utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
