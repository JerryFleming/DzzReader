import Foundation

/// One character cell of a quote card. A following 。or ， does not take a cell of its own:
/// it is drawn small beside this character, as on the original lecture page.
struct QuoteGlyph: Equatable, Sendable {
    var character: Character
    var punctuation: Character?
    var highlighted: Bool
}

/// The quote-card markup from the lecture page: `出处::正文`. Text between a pair of `|`
/// is underlined after the quote has been written out. Without `::` the source is 佛语典故.
struct QuoteScript: Equatable, Sendable {
    static let defaultSource = "佛语典故"
    static let sample = "僧伽吒经•月婆首那::佛告药上菩提萨埵言。善男子。初发意菩提萨埵。|于其梦中多见怖畏|。何以故。净一切业不可以身而受众苦。以是罪故梦见怖畏。"
    /// Marks that ride beside the previous character instead of taking a cell.
    static let attachedPunctuation: Set<Character> = ["。", "，", "、", "；", "：", "？", "！"]
    /// Both the ASCII and the full-width bar toggle underlining, so either keyboard works.
    static let underlineMarks: Set<Character> = ["|", "｜"]

    var source: String
    var glyphs: [QuoteGlyph]

    init(_ markup: String) {
        let parts = markup.components(separatedBy: "::")
        let named = parts.count > 1 ? parts[0].trimmingCharacters(in: .whitespacesAndNewlines) : ""
        source = named.isEmpty ? Self.defaultSource : named

        var glyphs: [QuoteGlyph] = []
        var underlining = false
        for ch in parts.last ?? "" {
            if Self.underlineMarks.contains(ch) {
                underlining.toggle()
            } else if ch.isWhitespace {
                continue
            } else if Self.attachedPunctuation.contains(ch), let last = glyphs.indices.last, glyphs[last].punctuation == nil {
                glyphs[last].punctuation = ch
            } else {
                let isMark = Self.attachedPunctuation.contains(ch)
                glyphs.append(QuoteGlyph(character: ch, punctuation: nil, highlighted: underlining && !isMark))
            }
        }
        self.glyphs = glyphs
    }

    var highlightCount: Int { glyphs.lazy.filter(\.highlighted).count }

    /// Glyph indices split into columns of `rows` cells; the first column is the rightmost.
    func columns(rows: Int) -> [Range<Int>] {
        let rows = max(1, rows)
        return stride(from: 0, to: glyphs.count, by: rows).map { $0..<min($0 + rows, glyphs.count) }
    }
}
