import Foundation

/// Simplified or traditional Chinese characters.
public enum ChineseScript: String, Sendable, Equatable {
    case simplified, traditional

    public var other: ChineseScript { self == .simplified ? .traditional : .simplified }

    /// The ICU transform that converts text into this script.
    var transform: StringTransform {
        StringTransform(self == .simplified ? "Hant-Hans" : "Hans-Hant")
    }

    /// `text` in this script, or `text` itself when the conversion fails.
    public func convert(_ text: String) -> String {
        if self == .simplified, text.contains(where: Self.simplifiedKeeps.contains) {
            // Convert the runs between the kept characters.
            var result = "", run = ""
            for character in text {
                if Self.simplifiedKeeps.contains(character) {
                    result += convert(run) + String(character)
                    run = ""
                } else {
                    run.append(character)
                }
            }
            return result + convert(run)
        }
        guard var converted = text.applyingTransform(transform, reverse: false) else { return text }
        if self == .traditional {
            for (wrong, right) in Self.traditionalFixes where converted.contains(wrong) {
                converted = converted.replacingOccurrences(of: wrong, with: right)
            }
        }
        return converted
    }

    /// Words ICU's simplified → traditional conversion gets wrong in Buddhist texts, where a simplified character
    /// has more than one traditional form: 舍 is a house or a transliteration (舍卫国, 精舍, 耶舍), not 捨 "give up";
    /// 云何 is "how", not 雲 "cloud"; 布施 keeps 布. Each fix is the same length, so offsets are kept.
    static let traditionalFixes: [(String, String)] = [
        ("雲何", "云何"), ("雲爾", "云爾"), ("雲雲", "云云"), ("所雲", "所云"),
        ("捨衛", "舍衛"), ("王捨", "王舍"), ("精捨", "精舍"), ("耶捨", "耶舍"), ("房捨", "房舍"),
        ("屋捨", "屋舍"), ("田捨", "田舍"), ("宅捨", "宅舍"), ("客捨", "客舍"), ("館捨", "館舍"),
        ("僧捨", "僧舍"), ("寺捨", "寺舍"), ("捨脂", "舍脂"), ("迦捨", "迦舍"), ("捨那", "舍那"),
        ("佈施", "布施"),
    ]

    /// Characters ICU's traditional → simplified conversion changes although they are standard simplified
    /// characters too, used in Buddhist names and mantras: 俱胝, 俱舍 (not 具), 乾闼婆 (not 干), 突瑟吒 (not 咤).
    static let simplifiedKeeps: Set<Character> = ["俱", "乾", "吒"]

    /// `text` in this script with every character at the same UTF-16 offset, so offsets into the original
    /// (bookmarks, reading position, styled spans) still point at the same characters. A character whose
    /// conversion would change the length is left as it is.
    public func convertKeepingOffsets(_ text: String) -> String {
        let whole = convert(text)
        if whole.utf16.count == text.utf16.count, whole.count == text.count,
           zip(text, whole).allSatisfy({ $0.utf16.count == $1.utf16.count }) {
            return whole
        }
        return String(text.map { character -> String in
            let converted = convert(String(character))
            return converted.utf16.count == character.utf16.count ? converted : String(character)
        }.joined())
    }

    /// The script `text` is mostly written in: whichever conversion would change fewer characters.
    /// Texts can mix the two (a simplified text keeping 南無), so a single traditional character does not decide it.
    public static func detect(_ text: String) -> ChineseScript {
        func changes(_ script: ChineseScript) -> Int {
            let converted = script.convert(text)
            return zip(text, converted).reduce(0) { $0 + ($1.0 == $1.1 ? 0 : 1) }
        }
        return changes(.traditional) >= changes(.simplified) ? .simplified : .traditional
    }
}

extension ChantDocument {
    /// The script most of the text is in.
    public var script: ChineseScript {
        ChineseScript.detect(rows.map(\.text).joined())
    }

    /// The same rows and cells, with every character converted to `script`. Pinyin, styles and the number of
    /// cells stay as they are, so row ids and block indices still point at the same places.
    public func converted(to script: ChineseScript) -> ChantDocument {
        ChantDocument(rows: rows.map { row in
            // Convert the whole row so a conversion can use the neighbouring characters, and fall back to
            // one cell at a time if that changed the number of characters.
            let chars = row.cells.map(\.char)
            let whole = Array(script.convert(chars.joined()))
            let converted: [String] = whole.count == chars.count && chars.allSatisfy({ $0.count == 1 })
                ? whole.map(String.init)
                : chars.map(script.convert)
            let cells = zip(row.cells, converted).map {
                ChantCell(char: $1, pinyin: $0.pinyin, isAnnotation: $0.isAnnotation)
            }
            return ChantRow(id: row.id, style: row.style, startsPassage: row.startsPassage, cells: cells)
        })
    }
}
