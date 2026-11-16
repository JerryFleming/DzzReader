import Foundation

public enum SpanKind: Equatable, Sendable {
    case chapterHeading
    case sectionHeading
}

/// A styled run in the RENDERED chapter text.
public struct StyledSpan: Equatable, Sendable {
    public let kind: SpanKind
    public let range: NSRange

    public init(kind: SpanKind, range: NSRange) {
        self.kind = kind
        self.range = range
    }
}

/// The source text of one chapter, or a run of consecutive chapters, with every chapter-mark prefix removed,
/// plus the map back to source offsets. All offsets are UTF-16 units relative to the start of the first chapter.
public struct RenderedChapter: Sendable {
    public let text: String
    public let spans: [StyledSpan]
    /// Rendered offset where each chapter of the run begins; the first is always 0.
    public let chapterStarts: [Int]
    /// (source offset of a removed prefix, its length), ascending.
    let removals: [(source: Int, length: Int)]
    let sourceLength: Int
    let renderedLength: Int

    public func renderedOffset(forSource sourceOffset: Int) -> Int {
        let s = min(max(sourceOffset, 0), sourceLength)
        var removed = 0
        for r in removals {
            if s >= r.source + r.length {
                removed += r.length
            } else if s > r.source {
                removed += s - r.source          // inside the prefix → the prefix's rendered position
            } else {
                break
            }
        }
        return s - removed
    }

    public func sourceOffset(forRendered renderedOffset: Int) -> Int {
        let r = min(max(renderedOffset, 0), renderedLength)
        var added = 0
        for removal in removals {
            let renderedPosition = removal.source - added
            if r >= renderedPosition {
                added += removal.length
            } else {
                break
            }
        }
        return r + added
    }
}

public enum ChapterRenderer {
    /// Only ASCII whitespace after the mark is removed; the full-width indent that follows belongs to the text.
    private static let markRegex = try! NSRegularExpression(pattern: #"^第\d+章[ \t]*"#, options: [.anchorsMatchLines])

    /// Part 2 onwards of an oversized 卷 split by the indexer: "…（2/3）".
    private static let continuationTitle = try! NSRegularExpression(pattern: #"（([2-9]|[1-9]\d+)/\d+）$"#)

    public static func render(fullText: String, chapter: ChapterRange, isFrontMatter: Bool) -> RenderedChapter {
        render(fullText: fullText, chapters: [chapter], span: 0..<1, hasFrontMatter: isFrontMatter)
    }

    /// Renders `chapters[span]` as one text. Every chapter gets a heading span on its first non-blank line,
    /// except front matter (index 0 when `hasFrontMatter`) and continuation parts that are not first in the run.
    public static func render(fullText: String, chapters: [ChapterRange], span: Range<Int>,
                              hasFrontMatter: Bool) -> RenderedChapter {
        let first = chapters[span.lowerBound]
        let base = first.startOffset
        let full = fullText as NSString
        let sourceRange = NSRange(location: base, length: chapters[span.upperBound - 1].endOffset - base)
        let source = full.substring(with: sourceRange) as NSString

        var removals: [(source: Int, length: Int)] = []
        let rendered = NSMutableString()
        var cursor = 0
        for m in markRegex.matches(in: source as String, range: NSRange(location: 0, length: source.length)) {
            rendered.append(source.substring(with: NSRange(location: cursor, length: m.range.location - cursor)))
            removals.append((source: m.range.location, length: m.range.length))
            cursor = m.range.location + m.range.length
        }
        rendered.append(source.substring(from: cursor))

        let partial = RenderedChapter(text: rendered as String, spans: [], chapterStarts: [], removals: removals,
                                      sourceLength: source.length, renderedLength: rendered.length)
        let starts = span.map { partial.renderedOffset(forSource: chapters[$0].startOffset - base) }

        var headings: [StyledSpan] = []
        var sectionSpans: [StyledSpan] = []
        for (k, index) in span.enumerated() {
            let chapter = chapters[index]
            if index == 0 && hasFrontMatter { continue }
            if k > 0, continuationTitle.firstMatch(in: chapter.title, range: NSRange(location: 0, length: (chapter.title as NSString).length)) != nil {
                continue
            }
            let end = k + 1 < starts.count ? starts[k + 1] : rendered.length
            if let heading = firstNonBlankLine(in: rendered, range: NSRange(location: starts[k], length: end - starts[k])) {
                headings.append(StyledSpan(kind: .chapterHeading, range: heading))
            }
        }
        for index in span {
            for section in chapters[index].sections {
                let start = partial.renderedOffset(forSource: section.offset - base)
                let line = lineRange(in: rendered, at: start)
                if headings.contains(where: { $0.range == line }) || sectionSpans.last?.range == line { continue }
                sectionSpans.append(StyledSpan(kind: .sectionHeading, range: line))
            }
        }

        return RenderedChapter(text: rendered as String, spans: headings + sectionSpans, chapterStarts: starts,
                               removals: removals, sourceLength: source.length, renderedLength: rendered.length)
    }

    /// Index of the chapter whose rendered start is the last one at or before `offset`.
    public static func chapterIndex(forRendered offset: Int, starts: [Int]) -> Int {
        var low = 0, high = starts.count - 1
        guard high > 0 else { return 0 }
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low
    }

    private static func firstNonBlankLine(in ns: NSString, range: NSRange) -> NSRange? {
        var result: NSRange?
        ns.enumerateSubstrings(in: range, options: [.byLines]) { sub, range, _, stop in
            if let sub, !sub.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result = range
                stop.pointee = true
            }
        }
        return result
    }

    /// The line containing `offset`, without its terminator.
    private static func lineRange(in ns: NSString, at offset: Int) -> NSRange {
        let clamped = min(max(offset, 0), max(ns.length - 1, 0))
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        let full = ns.lineRange(for: NSRange(location: clamped, length: 0))
        var end = full.location + full.length
        while end > full.location, ns.character(at: end - 1) == 0x0A || ns.character(at: end - 1) == 0x0D { end -= 1 }
        return NSRange(location: full.location, length: end - full.location)
    }
}
