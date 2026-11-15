import Foundation
import SwiftData

@Model
final class Bookmark {
    var chapterIndex: Int
    var characterOffset: Int        // SOURCE UTF-16 offset within the chapter
    var excerpt: String
    var createdAt: Date
    var book: Book?

    init(chapterIndex: Int, characterOffset: Int, excerpt: String, createdAt: Date = .now) {
        self.chapterIndex = chapterIndex
        self.characterOffset = characterOffset
        self.excerpt = excerpt
        self.createdAt = createdAt
    }
}
