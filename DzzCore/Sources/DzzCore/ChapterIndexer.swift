import Foundation

/// A 品 sub-heading inside a chapter. `offset` is the UTF-16 source offset of the heading line start.
public struct Section: Equatable, Sendable, Codable {
    public let title: String
    public let offset: Int

    public init(title: String, offset: Int) {
        self.title = title
        self.offset = offset
    }
}

/// One 卷 (or a synthetic part of an oversized 卷). Offsets are UTF-16 units into the source text; end is exclusive.
public struct ChapterRange: Equatable, Sendable, Codable {
    public let title: String
    public let startOffset: Int
    public let endOffset: Int
    public let sections: [Section]

    public init(title: String, startOffset: Int, endOffset: Int, sections: [Section]) {
        self.title = title
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.sections = sections
    }

    public var length: Int { endOffset - startOffset }
}

public enum ChapterIndexer {
    public static let chapterMarkPattern = #"^第\d+章\s*"#
    public static let oversizeLimit = 120_000
    static let partTarget = 100_000
    static let partSearchWindow = 20_000
    static let shortChapterLimit = 200
    static let maxHeadingLength = 30

    private static let markRegex = try! NSRegularExpression(pattern: chapterMarkPattern)
    private static let whitespaceRun = try! NSRegularExpression(pattern: #"[\s　]+"#)
    private static let parenthetical = try! NSRegularExpression(pattern: #"[（(][^（()）]*[)）]"#)
    private static let juanSuffix = try! NSRegularExpression(
        pattern: #"(卷第[一二三四五六七八九十百千〇零]+|卷[上中下]|卷)$"#)
    private static let unmarkedJuan = try! NSRegularExpression(
        pattern: #"^.{0,30}(卷第[一二三四五六七八九十百千〇零]+|卷[上中下])$"#)
    private static let headerTitleLine = try! NSRegularExpression(pattern: #"^(大正藏\s*)?No\.\s*\S+"#)
    private static let juanCountLine = try! NSRegularExpression(pattern: #"^\d+卷$"#)

    // MARK: - Public helpers

    /// Removes a chapter mark prefix, collapses whitespace runs (including U+3000) to one space, trims.
    public static func normalise<S: StringProtocol>(_ line: S) -> String {
        var s = String(line)
        s = replace(markRegex, in: s, with: "")
        s = replace(whitespaceRun, in: s, with: " ")
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// `normalise` output with every parenthetical removed.
    public static func comparisonKey(_ normalised: String) -> String {
        var s = normalised
        while true {
            let next = replace(parenthetical, in: s, with: "")
            if next == s { break }
            s = next
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    public static func isJuanHeading(key: String) -> Bool {
        matches(juanSuffix, key)
    }

    // MARK: - Indexing

    public static func index(text: String, bookTitle: String) -> [ChapterRange] {
        let ns = text as NSString
        let total = ns.length
        guard total > 0 else {
            return [ChapterRange(title: bookTitle, startOffset: 0, endOffset: 0, sections: [])]
        }

        let lines = enumerateLines(ns)
        let hasMarks = lines.contains { matches(markRegex, $0.text) }

        var juanHeadings: [(title: String, key: String, start: Int)] = []
        var sections: [Section] = []

        for line in lines {
            let isMarked = hasMarks && matches(markRegex, line.text)
            if hasMarks && !isMarked { continue }
            let title = normalise(line.text)
            let key = comparisonKey(title)
            if key.isEmpty || matches(headerTitleLine, key) { continue }

            if hasMarks {
                if key.count > maxHeadingLength { continue }
                if isJuanHeading(key: key) {
                    if juanHeadings.last?.key == key { continue }   // closing line of the same 卷
                    juanHeadings.append((title, key, line.start))
                } else {
                    sections.append(Section(title: title, offset: line.start))
                }
            } else if matches(unmarkedJuan, key) {
                if juanHeadings.last?.key == key { continue }
                juanHeadings.append((title, key, line.start))
            }
        }

        var chapters: [ChapterRange] = []
        if juanHeadings.isEmpty {
            chapters = [ChapterRange(title: bookTitle, startOffset: 0, endOffset: total, sections: [])]
        } else {
            let firstStart = juanHeadings[0].start
            let frontMatter = hasFrontMatterContent(lines.filter { $0.start < firstStart })
            for (i, h) in juanHeadings.enumerated() {
                let start = (i == 0 && !frontMatter) ? 0 : h.start
                let end = i + 1 < juanHeadings.count ? juanHeadings[i + 1].start : total
                chapters.append(ChapterRange(title: h.title, startOffset: start, endOffset: end, sections: []))
            }
            if frontMatter {
                chapters.insert(ChapterRange(title: "卷首", startOffset: 0, endOffset: firstStart, sections: []), at: 0)
            }
        }

        chapters = mergeShort(chapters)
        chapters = chapters.flatMap { splitOversized($0, in: ns) }
        return assign(sections: sections, to: chapters)
    }

    // MARK: - Steps

    private struct Line {
        let start: Int
        let text: String
    }

    private static func enumerateLines(_ ns: NSString) -> [Line] {
        var lines: [Line] = []
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines]) { sub, range, _, _ in
            lines.append(Line(start: range.location, text: sub ?? ""))
        }
        return lines
    }

    /// True when the lines before the first 卷 heading hold content beyond the header block.
    private static func hasFrontMatterContent(_ lines: [Line]) -> Bool {
        let nonBlank = lines.map { normalise($0.text) }.filter { !$0.isEmpty }
        let headerCount: Int
        if let i = nonBlank.firstIndex(where: { matches(juanCountLine, $0) }) {
            headerCount = i + 1
        } else {
            headerCount = 3
        }
        return nonBlank.count > headerCount
    }

    private static func mergeShort(_ chapters: [ChapterRange]) -> [ChapterRange] {
        var result: [ChapterRange] = []
        var pendingStart: Int?
        for (i, c) in chapters.enumerated() {
            let isLast = i == chapters.count - 1
            if c.length < shortChapterLimit && !isLast {
                if pendingStart == nil { pendingStart = c.startOffset }
                continue
            }
            let start = pendingStart ?? c.startOffset
            pendingStart = nil
            result.append(ChapterRange(title: c.title, startOffset: start, endOffset: c.endOffset, sections: []))
        }
        return result
    }

    private static func splitOversized(_ chapter: ChapterRange, in ns: NSString) -> [ChapterRange] {
        guard chapter.length > oversizeLimit else { return [chapter] }
        var bounds: [Int] = [chapter.startOffset]
        var cursor = chapter.startOffset
        while chapter.endOffset - cursor > oversizeLimit {
            let cut = findCut(near: cursor + partTarget, in: ns, lower: cursor + 1, upper: chapter.endOffset - 1)
            bounds.append(cut)
            cursor = cut
        }
        bounds.append(chapter.endOffset)
        let count = bounds.count - 1
        return (0..<count).map { i in
            ChapterRange(title: "\(chapter.title)（\(i + 1)/\(count)）",
                         startOffset: bounds[i], endOffset: bounds[i + 1], sections: [])
        }
    }

    /// Nearest paragraph boundary ("\n\n") to `target` within the search window, else nearest line break, else `target`.
    private static func findCut(near target: Int, in ns: NSString, lower: Int, upper: Int) -> Int {
        let lo = max(lower, target - partSearchWindow)
        let hi = min(upper, target + partSearchWindow)
        guard lo < hi else { return min(max(target, lower), upper) }
        for separator in ["\n\n", "\n"] {
            let before = ns.range(of: separator, options: [.backwards], range: NSRange(location: lo, length: target - lo))
            let after = ns.range(of: separator, options: [], range: NSRange(location: target, length: hi - target))
            var best: NSRange?
            if before.location != NSNotFound { best = before }
            if after.location != NSNotFound {
                if let b = best {
                    if (after.location - target) < (target - b.location) { best = after }
                } else {
                    best = after
                }
            }
            if let b = best { return b.location + b.length }
        }
        return target
    }

    private static func assign(sections: [Section], to chapters: [ChapterRange]) -> [ChapterRange] {
        chapters.map { c in
            let own = sections.filter { $0.offset >= c.startOffset && $0.offset < c.endOffset }
            return ChapterRange(title: c.title, startOffset: c.startOffset, endOffset: c.endOffset, sections: own)
        }
    }

    // MARK: - Regex helpers

    private static func matches(_ regex: NSRegularExpression, _ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    private static func replace(_ regex: NSRegularExpression, in s: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }
}
