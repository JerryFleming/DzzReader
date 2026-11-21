import Foundation
import DzzCore

/// The blocks the reader lays out, numbered through the whole text, and the ones auto-scroll highlights.
/// A block is one character with its pinyin, or a whole note in （…） (kept together so a line never
/// breaks inside it). Auto-scroll steps only through blocks with pinyin: punctuation and notes are passed over.
struct ChantUnits: Sendable {
    /// Blocks of each row.
    let rows: [[ChantCell]]
    /// Global index of each row's first block.
    let starts: [Int]
    /// Global indices of the blocks auto-scroll stops on, ascending.
    let stops: [Int]

    init(_ document: ChantDocument) {
        var rows: [[ChantCell]] = []
        var starts: [Int] = []
        var stops: [Int] = []
        var next = 0
        for row in document.rows {
            let units = Self.units(row.cells)
            starts.append(next)
            for (i, unit) in units.enumerated() where !unit.pinyin.isEmpty {
                stops.append(next + i)
            }
            rows.append(units)
            next += units.count
        }
        self.rows = rows
        self.starts = starts
        self.stops = stops
    }

    /// Row holding the block with this global index.
    func row(of index: Int) -> Int {
        var lo = 0, hi = starts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if starts[mid] <= index { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    /// The stop after `index`, or nil at the end of the text.
    func stop(after index: Int) -> Int? {
        firstStop(atOrAfter: index + 1)
    }

    /// First stop in `row` or later.
    func firstStop(inOrAfterRow row: Int) -> Int? {
        guard starts.indices.contains(row) else { return nil }
        return firstStop(atOrAfter: starts[row])
    }

    /// First stop at or after block `index`.
    func firstStop(atOrAfter index: Int) -> Int? {
        var lo = 0, hi = stops.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if stops[mid] < index { lo = mid + 1 } else { hi = mid }
        }
        return lo < stops.count ? stops[lo] : nil
    }

    /// Each note in （…） becomes one block, so a line never breaks inside it (「（9」 / 「7）」).
    static func units(_ cells: [ChantCell]) -> [ChantCell] {
        var out: [ChantCell] = []
        var note = ""
        for cell in cells {
            if cell.isAnnotation {
                note += cell.char
                if cell.char == "）" || cell.char == ")" {
                    out.append(ChantCell(char: note, pinyin: "", isAnnotation: true))
                    note = ""
                }
            } else {
                if !note.isEmpty { out.append(ChantCell(char: note, pinyin: "", isAnnotation: true)); note = "" }
                out.append(cell)
            }
        }
        if !note.isEmpty { out.append(ChantCell(char: note, pinyin: "", isAnnotation: true)) }
        return out
    }
}

/// Scroll id of a block; a distinct type so it never collides with the Int row ids used for the scroll position.
struct ChantBlockID: Hashable {
    let index: Int
}
