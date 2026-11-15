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

/// A chapter's source text with every chapter-mark prefix removed, plus the map back to source offsets.
/// All offsets are UTF-16 units relative to the chapter start.
public struct RenderedChapter: Sendable {
    public let text: String
    public let spans: [StyledSpan]
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

    public static func render(fullText: String, chapter: ChapterRange, isFrontMatter: Bool) -> RenderedChapter {
        let full = fullText as NSString
        let sourceRange = NSRange(location: chapter.startOffset, length: chapter.endOffset - chapter.startOffset)
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

        var spans: [StyledSpan] = []
        let partial = RenderedChapter(text: rendered as String, spans: [], removals: removals,
                                      sourceLength: source.length, renderedLength: rendered.length)

        if !isFrontMatter, let heading = firstNonBlankLine(in: rendered) {
            spans.append(StyledSpan(kind: .chapterHeading, range: heading))
        }
        for section in chapter.sections {
            let start = partial.renderedOffset(forSource: section.offset - chapter.startOffset)
            let line = lineRange(in: rendered, at: start)
            if spans.contains(where: { $0.range == line }) { continue }
            spans.append(StyledSpan(kind: .sectionHeading, range: line))
        }

        return RenderedChapter(text: rendered as String, spans: spans, removals: removals,
                               sourceLength: source.length, renderedLength: rendered.length)
    }

    private static func firstNonBlankLine(in ns: NSString) -> NSRange? {
        var result: NSRange?
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines]) { sub, range, _, stop in
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
