import Foundation

/// Converts between (chapter, offset-in-chapter) and a 0…1 fraction over the whole book.
public enum ProgressMapper {
    public static func fraction(chapterIndex: Int, offsetInChapter: Int, chapters: [ChapterRange]) -> Double {
        guard let total = chapters.last?.endOffset, total > 0 else { return 1 }
        let index = min(max(chapterIndex, 0), chapters.count - 1)
        let chapter = chapters[index]
        let offset = min(max(offsetInChapter, 0), chapter.length)
        return Double(chapter.startOffset + offset) / Double(total)
    }

    public static func locate(fraction: Double, chapters: [ChapterRange]) -> (chapterIndex: Int, offsetInChapter: Int) {
        guard let last = chapters.last else { return (0, 0) }
        let f = min(max(fraction, 0), 1)
        if f >= 1 { return (chapters.count - 1, last.length) }
        let position = Int((Double(last.endOffset) * f).rounded())
        for (i, c) in chapters.enumerated() where position < c.endOffset || i == chapters.count - 1 {
            return (i, min(max(position - c.startOffset, 0), c.length))
        }
        return (0, 0)
    }
}
