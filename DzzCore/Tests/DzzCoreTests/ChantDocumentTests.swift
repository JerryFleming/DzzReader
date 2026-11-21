import Foundation
import Testing
@testable import DzzCore

@Suite struct ChantDocumentTests {
    private func parse(_ json: String) throws -> ChantDocument {
        try ChantDocument.parse(Data(json.utf8))
    }

    @Test func splitsRowsAndPassages() throws {
        let doc = try parse("""
        [{"type":"passage","style":"title"},
         {"char":"大","pinyin":"dà"},{"char":"悲","pinyin":"bēi"},
         {"type":"linebreak"},
         {"char":"（","pinyin":""},{"char":"三","pinyin":""},{"char":"）","pinyin":""},
         {"type":"linebreak"},
         {"type":"passage","style":"normal"},
         {"char":"南","pinyin":"ná"},{"char":"無","pinyin":"mó"},{"char":"，","pinyin":""},
         {"type":"linebreak"},
         {"char":"佛","pinyin":"fó"}]
        """)
        #expect(doc.rows.map(\.text) == ["大悲", "（三）", "南無，", "佛"])
        #expect(doc.rows.map(\.style) == [.title, .title, .normal, .normal])
        #expect(doc.rows.map(\.startsPassage) == [true, false, true, false])
        #expect(doc.rows.map(\.id) == [0, 1, 2, 3])
        #expect(doc.rows[0].cells[0] == ChantCell(char: "大", pinyin: "dà"))
        let annotations = doc.rows.map { $0.cells.map(\.isAnnotation) }
        #expect(annotations[1] == [true, true, true])
        #expect(annotations[2] == [false, false, false])
        #expect(doc.titleRows.map(\.id) == [0])
        #expect(doc.titleRow(atOrBefore: 3)?.text == "大悲")
    }

    @Test func annotationSpansRows() throws {
        let doc = try parse("""
        [{"char":"帝","pinyin":"dì"},{"char":"（","pinyin":""},{"char":"二","pinyin":""},
         {"type":"linebreak"},
         {"char":"十","pinyin":""},{"char":"）","pinyin":""},{"char":"那","pinyin":"nuó"}]
        """)
        #expect(doc.rows[0].cells.map(\.isAnnotation) == [false, true, true])
        #expect(doc.rows[1].cells.map(\.isAnnotation) == [true, true, false])
    }

    @Test func passageMidRowStartsNewRowAndEmptyRowsDrop() throws {
        let doc = try parse("""
        [{"char":"甲","pinyin":"jiǎ"},{"type":"passage","style":"subtitle"},{"char":"乙","pinyin":"yǐ"},
         {"type":"linebreak"},{"type":"linebreak"},{"char":"丙"}]
        """)
        #expect(doc.rows.map(\.text) == ["甲", "乙", "丙"])
        #expect(doc.rows.map(\.style) == [.normal, .subtitle, .subtitle])
        #expect(doc.rows[2].cells[0].pinyin == "")
    }

    @Test func versePassagesAreTheirOwnStyle() throws {
        let doc = try parse("""
        [{"char":"甲","pinyin":"jiǎ"},{"type":"passage","style":"verse"},{"char":"乙","pinyin":"yǐ"},
         {"type":"linebreak"},{"char":"丙","pinyin":"bǐng"},{"type":"passage","style":"normal"},{"char":"丁"}]
        """)
        #expect(doc.rows.map(\.text) == ["甲", "乙", "丙", "丁"])
        #expect(doc.rows.map(\.style) == [.normal, .verse, .verse, .normal])
        #expect(doc.rows.map(\.startsPassage) == [false, true, false, true])
        #expect(doc.titleRows.isEmpty)
    }

    @Test func rejectsBadInput() {
        #expect(throws: ChantDocumentError.notAnItemList) { try parse(#"{"char":"大"}"#) }
        #expect(throws: ChantDocumentError.badItem(1)) { try parse(#"[{"char":"大"},{"type":"page"}]"#) }
        #expect(throws: ChantDocumentError.badItem(0)) { try parse(#"[{"type":"passage","style":"red"}]"#) }
        #expect(throws: ChantDocumentError.empty) { try parse(#"[{"type":"linebreak"}]"#) }
    }
}
