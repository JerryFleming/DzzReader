import Foundation

/// One 部 of the canon with its inclusive 经号 range.
public struct TocSection: Equatable, Sendable {
    public let name: String
    public let firstNumber: Int
    public let lastNumber: Int

    public init(name: String, firstNumber: Int, lastNumber: Int) {
        self.name = name
        self.firstNumber = firstNumber
        self.lastNumber = lastNumber
    }
}

/// One text entry of toc.txt.
public struct TocEntry: Equatable, Sendable {
    public let number: String      // "0026" or "0894a"
    public let title: String
    public let juanCount: Int?
    public let author: String?     // "东晋 瞿昙僧伽提婆译"
    public let note: String?

    public init(number: String, title: String, juanCount: Int?, author: String?, note: String?) {
        self.number = number
        self.title = title
        self.juanCount = juanCount
        self.author = author
        self.note = note
    }
}

public struct Toc: Sendable {
    public let sections: [TocSection]
    public let entries: [TocEntry]

    public init(sections: [TocSection], entries: [TocEntry]) {
        self.sections = sections
        self.entries = entries
    }

    public func section(forNumber number: String) -> TocSection? {
        let n = CanonNumber.numericPart(number)
        return sections.first { $0.firstNumber <= n && n <= $0.lastNumber }
    }
}

public enum TocParser {
    private static let sectionLine = try! NSRegularExpression(
        pattern: #"^(\S+部)\t\[[^\]]*\]\t（(\d{4})-(\d{4})）\s*$"#)
    private static let juanCount = try! NSRegularExpression(pattern: #"(?:第(\d+)-)?(\d+)卷"#)

    public static func parse(_ text: String) -> Toc {
        var sections: [TocSection] = []
        var entries: [TocEntry] = []

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if let section = parseSection(line) {
                sections.append(section)
            } else if let entry = parseEntry(line) {
                entries.append(entry)
            }
        }
        return Toc(sections: sections, entries: entries)
    }

    private static func parseSection(_ line: String) -> TocSection? {
        let ns = line as NSString
        guard let m = sectionLine.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return TocSection(
            name: ns.substring(with: m.range(at: 1)),
            firstNumber: Int(ns.substring(with: m.range(at: 2)))!,
            lastNumber: Int(ns.substring(with: m.range(at: 3)))!)
    }

    private static func parseEntry(_ line: String) -> TocEntry? {
        let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard fields.count >= 4, CanonNumber.isValid(fields[0]) else { return nil }

        let number = fields[0]
        let title = fields[3]
        guard !title.isEmpty else { return nil }

        var count: Int?
        if fields.count > 4 {
            let f = fields[4] as NSString
            if let m = juanCount.firstMatch(in: fields[4], range: NSRange(location: 0, length: f.length)) {
                let last = Int(f.substring(with: m.range(at: 2)))
                if m.range(at: 1).location != NSNotFound, let first = Int(f.substring(with: m.range(at: 1))), let last {
                    count = last - first + 1    // "(第401-600卷)" → 200
                } else {
                    count = last
                }
            }
        }

        var author: String?
        var note: String?
        let rest = fields.dropFirst(5)
        if let open = rest.firstIndex(where: { $0.hasPrefix("〖") }),
           let close = rest[open...].firstIndex(where: { $0.hasSuffix("〗") }) {
            let joined = rest[open...close].joined(separator: " ")
            author = joined
                .replacingOccurrences(of: "〖", with: "")
                .replacingOccurrences(of: "〗", with: "")
                .trimmingCharacters(in: .whitespaces)
            if author?.isEmpty == true { author = nil }
            let afterAuthor = rest[rest.index(after: close)...]
            note = afterAuthor.first(where: { !$0.isEmpty }).map(stripParens)
        } else {
            note = rest.first(where: { !$0.isEmpty && $0.hasPrefix("(") }).map(stripParens)
        }
        return TocEntry(number: number, title: title, juanCount: count, author: author, note: note)
    }

    private static func stripParens(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("(") || t.hasPrefix("（") { t.removeFirst() }
        if t.hasSuffix(")") || t.hasSuffix("）") { t.removeLast() }
        return t
    }
}
