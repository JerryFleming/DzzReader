import Foundation
import Testing
import DzzCore
@testable import DzzReader

@Suite struct ChantUnitsTests {
    // Row 0: 南 無 ， （ 1 ）   → blocks 南 無 ， （1）      stops 0 1
    // Row 1: 佛 。               → blocks 佛 。            stops 4
    // Row 2: （ 3 称 ）           → blocks （3称）          no stops
    // Row 3: 法                  → blocks 法              stops 7
    let units = ChantUnits(ChantDocument(rows: [
        ChantRow(id: 0, style: .normal, startsPassage: true, cells: [
            ChantCell(char: "南", pinyin: "ná"), ChantCell(char: "無", pinyin: "mó"), ChantCell(char: "，", pinyin: ""),
            ChantCell(char: "（", pinyin: "", isAnnotation: true), ChantCell(char: "1", pinyin: "", isAnnotation: true),
            ChantCell(char: "）", pinyin: "", isAnnotation: true),
        ]),
        ChantRow(id: 1, style: .normal, startsPassage: false, cells: [
            ChantCell(char: "佛", pinyin: "fó"), ChantCell(char: "。", pinyin: ""),
        ]),
        ChantRow(id: 2, style: .subtitle, startsPassage: true, cells: [
            ChantCell(char: "（", pinyin: "", isAnnotation: true), ChantCell(char: "3", pinyin: "", isAnnotation: true),
            ChantCell(char: "称", pinyin: "", isAnnotation: true), ChantCell(char: "）", pinyin: "", isAnnotation: true),
        ]),
        ChantRow(id: 3, style: .normal, startsPassage: true, cells: [ChantCell(char: "法", pinyin: "fǎ")]),
    ]))

    @Test func numbersBlocksAndKeepsNotesWhole() {
        let chars = units.rows.map { $0.map(\.char) }
        #expect(chars == [["南", "無", "，", "（1）"], ["佛", "。"], ["（3称）"], ["法"]])
        #expect(units.starts == [0, 4, 6, 7])
    }

    @Test func stopsOnlyOnBlocksWithPinyin() {
        #expect(units.stops == [0, 1, 4, 7])
        #expect(units.stop(after: 1) == 4)     // skips ， and （1）
        #expect(units.stop(after: 4) == 7)     // skips 。 and the note-only row
        #expect(units.stop(after: 7) == nil)
    }

    @Test func findsRowsAndRowStarts() {
        let rows = [0, 3, 4, 5, 6, 7].map { units.row(of: $0) }
        #expect(rows == [0, 0, 1, 1, 2, 3])
        #expect(units.firstStop(inOrAfterRow: 1) == 4)
        #expect(units.firstStop(inOrAfterRow: 2) == 7)   // a row without stops starts at the next one
        #expect(units.firstStop(inOrAfterRow: 9) == nil)
    }
}
