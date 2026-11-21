import Foundation
import SwiftData
import DzzCore

/// Builds the shelf from downloaded archives: toc.txt joined with the files that actually exist.
@MainActor
enum CatalogLoader {
    /// 部 from the downloaded toc.txt keyed by name, for showing each 部's 经号 range.
    /// Parsed once it is there (it is missing until the first-run download finishes).
    static var bundledSections: [String: TocSection] {
        if let cachedSections { return cachedSections }
        let url = Corpus.booksDirectory.appending(path: "toc.txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        let sections = Dictionary(TocParser.parse(text).sections.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        cachedSections = sections
        return sections
    }
    private static var cachedSections: [String: TocSection]?

    /// Drops the parsed toc so the next read picks up a newly downloaded toc.txt.
    static func resetSections() { cachedSections = nil }

    /// Adds or updates books from `booksDirectory` (an unpacked archive; `relativePath` is "Books/" plus the
    /// path inside it). Books already on the shelf are never removed. With a toc.txt, `NN/<经号><title>.txt` files are grouped into
    /// its 部; without one, every .txt file is listed by name with no 部 (the shelf's unnamed group).
    static func load(booksDirectory: URL, context: ModelContext) throws -> Int {
        cachedSections = nil
        let tocURL = booksDirectory.appending(path: "toc.txt")
        let toc = FileManager.default.fileExists(atPath: tocURL.path)
            ? TocParser.parse(try String(contentsOf: tocURL, encoding: .utf8)) : nil

        var existing: [String: Book] = [:]
        let bundled = BookSource.bundled.rawValue
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.sourceRaw == bundled })
        for book in try context.fetch(descriptor) { existing[book.id] = book }

        var seen = Set<String>()
        func upsert(id: String, title: String, relativePath: String, section: String?, entry: TocEntry?,
                    order: Int, size: Int) {
            seen.insert(id)
            if let book = existing[id] {
                book.title = title
                book.section = section
                book.juanCount = entry?.juanCount
                book.author = entry?.author
                book.catalogOrder = order
                book.relativePath = relativePath
                book.byteSize = size
            } else {
                context.insert(Book(id: id, title: title, source: .bundled, relativePath: relativePath,
                                    section: section, juanCount: entry?.juanCount, author: entry?.author,
                                    catalogOrder: order, byteSize: size, encodingName: "utf-8"))
            }
        }

        let files = try bookFiles(in: booksDirectory, hasToc: toc != nil)
        if let toc {
            let entries = Dictionary(toc.entries.map { ($0.number, $0) }, uniquingKeysWith: { a, _ in a })
            for file in files {
                let name = file.name
                guard let number = CanonNumber.parse(filename: name) else { continue }
                let entry = entries[number]
                upsert(id: "T" + number,
                       title: entry?.title ?? String(name.dropFirst(number.count).dropLast(4)),
                       relativePath: "Books/\(file.path)", section: toc.section(forNumber: number)?.name,
                       entry: entry, order: CanonNumber.sortKey(number), size: file.size)
            }
        } else {
            for (order, file) in files.enumerated() {
                upsert(id: "F:" + file.path, title: String(file.name.dropLast(4)),
                       relativePath: "Books/\(file.path)", section: nil, entry: nil, order: order, size: file.size)
            }
        }
        try context.save()
        return seen.count
    }

    // MARK: - Files

    private struct BookFile {
        let path: String          // relative to the books folder: "00/0001长阿含经.txt"
        let size: Int
        var name: String { String(path.split(separator: "/").last ?? "") }
    }

    /// With a toc: the .txt files in the two-digit volume folders. Without: every .txt file, in name order.
    private static func bookFiles(in root: URL, hasToc: Bool) throws -> [BookFile] {
        let fm = FileManager.default
        var result: [BookFile] = []
        func size(_ url: URL) -> Int { (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        if hasToc {
            let dirs = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])
                .filter { $0.lastPathComponent.range(of: #"^\d\d$"#, options: .regularExpression) != nil }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for dir in dirs {
                let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])
                    .filter { $0.pathExtension == "txt" }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                for file in files {
                    result.append(BookFile(path: "\(dir.lastPathComponent)/\(file.lastPathComponent)", size: size(file)))
                }
            }
            return result
        }
        let rootPath = root.standardizedFileURL.path + "/"
        let walker = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                   options: [.skipsHiddenFiles])
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension.lowercased() == "txt",
                  (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let full = url.standardizedFileURL.path
            guard full.hasPrefix(rootPath) else { continue }
            result.append(BookFile(path: String(full.dropFirst(rootPath.count)), size: size(url)))
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
