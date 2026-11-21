import Foundation
import SwiftData
import DzzCore

@Model
final class Book {
    @Attribute(.unique) var id: String          // "T0026", "T0894a", "F:<path>" (downloaded, no toc), or a UUID for imports
    var title: String
    var sourceRaw: String                        // BookSource.rawValue; predicates cannot capture enums
    var relativePath: String                     // "Books/00/0026中阿含经.txt" | "Imported/<uuid>.txt"
    var section: String?
    var juanCount: Int?
    var author: String?
    var catalogOrder: Int
    var byteSize: Int
    var dateAdded: Date
    var lastOpened: Date?
    var chaptersData: Data?                      // JSON [ChapterRange], nil until indexed
    var indexedByteSize: Int?
    var encodingName: String

    @Relationship(deleteRule: .cascade, inverse: \ReadingProgress.book) var progress: ReadingProgress?
    @Relationship(deleteRule: .cascade, inverse: \Bookmark.book) var bookmarks: [Bookmark]

    init(id: String, title: String, source: BookSource, relativePath: String,
         section: String?, juanCount: Int?, author: String?, catalogOrder: Int,
         byteSize: Int, encodingName: String, dateAdded: Date = .now) {
        self.id = id
        self.title = title
        self.sourceRaw = source.rawValue
        self.relativePath = relativePath
        self.section = section
        self.juanCount = juanCount
        self.author = author
        self.catalogOrder = catalogOrder
        self.byteSize = byteSize
        self.encodingName = encodingName
        self.dateAdded = dateAdded
        self.bookmarks = []
    }

    var source: BookSource {
        get { BookSource(rawValue: sourceRaw) ?? .bundled }
        set { sourceRaw = newValue.rawValue }
    }

    var chapters: [ChapterRange] {
        get {
            guard let chaptersData else { return [] }
            return (try? JSONDecoder().decode([ChapterRange].self, from: chaptersData)) ?? []
        }
        set {
            chaptersData = try? JSONEncoder().encode(newValue)
        }
    }

    var needsIndexing: Bool { chaptersData == nil || indexedByteSize != byteSize }

    var fileURL: URL {
        switch source {
        case .bundled:
            return Corpus.root.appending(path: relativePath)   // downloaded from the 书架
        case .imported:
            return URL.documentsDirectory.appending(path: relativePath)
        }
    }

    /// "0026" for downloaded books catalogued by a toc.txt ("T0026"), nil otherwise.
    var canonNumber: String? {
        source == .bundled && id.hasPrefix("T") ? String(id.dropFirst()) : nil
    }
}
