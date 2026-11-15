import Foundation
import SwiftData

@Model
final class ReadingProgress {
    var chapterIndex: Int
    var characterOffset: Int        // SOURCE UTF-16 offset within the chapter
    var fraction: Double
    var updatedAt: Date
    var book: Book?

    init(chapterIndex: Int, characterOffset: Int, fraction: Double, updatedAt: Date = .now) {
        self.chapterIndex = chapterIndex
        self.characterOffset = characterOffset
        self.fraction = fraction
        self.updatedAt = updatedAt
    }
}
