import Foundation

/// A chanting text with pinyin, parsed from the JSON item list produced from 佛教念诵集.pdf:
///
///     [{"type": "passage", "style": "title"},
///      {"char": "大", "pinyin": "dà"}, …,
///      {"type": "linebreak"}, …]
///
/// Character items carry one character and its pinyin (empty for punctuation and parenthesised notes);
/// `linebreak` items end a printed row; `passage` items start a passage styled `normal`, `title` or `subtitle`.
public struct ChantDocument: Sendable, Equatable {
    public let rows: [ChantRow]

    public init(rows: [ChantRow]) {
        self.rows = rows
    }

    /// Rows that open a title passage, for the table of contents.
    public var titleRows: [ChantRow] {
        rows.filter { $0.startsPassage && $0.style == .title }
    }

    /// The title row at or before `rowIndex`: the passage being read.
    public func titleRow(atOrBefore rowIndex: Int) -> ChantRow? {
        titleRows.last { $0.id <= rowIndex }
    }

    public static func parse(_ data: Data) throws -> ChantDocument {
        let items: [RawItem]
        do {
            items = try JSONDecoder().decode([RawItem].self, from: data)
        } catch {
            throw ChantDocumentError.notAnItemList
        }

        var rows: [ChantRow] = []
        var cells: [ChantCell] = []
        var style = ChantStyle.normal
        var rowStyle = ChantStyle.normal
        var startsPassage = false
        var parenDepth = 0

        func endRow() {
            if !cells.isEmpty {
                rows.append(ChantRow(id: rows.count, style: rowStyle, startsPassage: startsPassage, cells: cells))
            }
            cells = []
            startsPassage = false
            rowStyle = style
        }

        for (index, item) in items.enumerated() {
            if let char = item.char {
                guard !char.isEmpty else { throw ChantDocumentError.badItem(index) }
                let opens = char == "（" || char == "("
                let closes = char == "）" || char == ")"
                if opens { parenDepth += 1 }
                let annotation = parenDepth > 0
                if closes { parenDepth = max(0, parenDepth - 1) }
                if cells.isEmpty { rowStyle = style }
                cells.append(ChantCell(char: char, pinyin: item.pinyin ?? "", isAnnotation: annotation))
            } else if item.type == "linebreak" {
                endRow()
            } else if item.type == "passage" {
                guard let raw = item.style, let next = ChantStyle(rawValue: raw) else {
                    throw ChantDocumentError.badItem(index)
                }
                endRow()           // a passage always starts on a new row
                style = next
                rowStyle = next
                startsPassage = true
            } else {
                throw ChantDocumentError.badItem(index)
            }
        }
        endRow()
        guard !rows.isEmpty else { throw ChantDocumentError.empty }
        return ChantDocument(rows: rows)
    }

    private struct RawItem: Decodable {
        let char: String?
        let pinyin: String?
        let type: String?
        let style: String?
    }
}

public enum ChantStyle: String, Sendable, Equatable {
    case normal, title, subtitle
}

public struct ChantCell: Sendable, Equatable, Hashable {
    public let char: String
    public let pinyin: String
    /// Inside （…）: a note or verse number, printed small without pinyin.
    public let isAnnotation: Bool

    public init(char: String, pinyin: String, isAnnotation: Bool = false) {
        self.char = char
        self.pinyin = pinyin
        self.isAnnotation = isAnnotation
    }
}

public struct ChantRow: Sendable, Equatable, Identifiable {
    /// Position in `ChantDocument.rows`.
    public let id: Int
    public let style: ChantStyle
    /// First row of a passage.
    public let startsPassage: Bool
    public let cells: [ChantCell]

    public init(id: Int, style: ChantStyle, startsPassage: Bool, cells: [ChantCell]) {
        self.id = id
        self.style = style
        self.startsPassage = startsPassage
        self.cells = cells
    }

    public var text: String { cells.map(\.char).joined() }
}

public enum ChantDocumentError: Error, Equatable, LocalizedError {
    case notAnItemList
    case badItem(Int)
    case empty

    public var errorDescription: String? {
        switch self {
        case .notAnItemList: "不是诵经文本的 JSON 格式（应为字与拼音的列表）。"
        case .badItem(let i): "第 \(i + 1) 项无法识别。"
        case .empty: "文件中没有文字。"
        }
    }
}
