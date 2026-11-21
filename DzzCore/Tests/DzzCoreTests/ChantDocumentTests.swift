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
    @Test func convertsBetweenSimplifiedAndTraditional() throws {
        let doc = try parse("""
        [{"type":"passage","style":"title"},
         {"char":"观","pinyin":"guān"},{"char":"世","pinyin":"shì"},{"char":"音","pinyin":"yīn"},
         {"char":"（","pinyin":""},{"char":"三","pinyin":""},{"char":"说","pinyin":""},{"char":"）","pinyin":""},
         {"type":"linebreak"},
         {"type":"passage","style":"normal"},
         {"char":"南","pinyin":"ná"},{"char":"無","pinyin":"mó"},{"char":"阿","pinyin":"ā"},
         {"char":"弥","pinyin":"mí"},{"char":"陀","pinyin":"tuó"},{"char":"佛","pinyin":"fó"},{"char":"。","pinyin":""}]
        """)
        // One traditional 無 in a simplified text does not make it traditional.
        #expect(doc.script == .simplified)

        let traditional = doc.converted(to: .traditional)
        #expect(traditional.rows.map(\.text) == ["觀世音（三說）", "南無阿彌陀佛。"])
        #expect(traditional.script == .traditional)
        // Everything but the characters is kept, cell for cell.
        #expect(traditional.rows.map(\.id) == doc.rows.map(\.id))
        #expect(traditional.rows.map(\.style) == doc.rows.map(\.style))
        #expect(traditional.rows.map(\.startsPassage) == doc.rows.map(\.startsPassage))
        #expect(traditional.rows.map { $0.cells.map(\.pinyin) } == doc.rows.map { $0.cells.map(\.pinyin) })
        #expect(traditional.rows.map { $0.cells.map(\.isAnnotation) } == doc.rows.map { $0.cells.map(\.isAnnotation) })

        #expect(traditional.converted(to: .simplified).rows.map(\.text) == ["观世音（三说）", "南无阿弥陀佛。"])
    }

    @Test func convertingBookTextKeepsOffsets() {
        let text = "大正藏 No. 0262 妙法莲华经\n\n　　如是我闻。一时佛住祇树给孤独园。\u{20000}"
        let traditional = ChineseScript.traditional.convertKeepingOffsets(text)
        #expect(traditional == "大正藏 No. 0262 妙法蓮華經\n\n　　如是我聞。一時佛住祇樹給孤獨園。\u{20000}")
        #expect(traditional.utf16.count == text.utf16.count)
        #expect(ChineseScript.detect(text) == .simplified)
        #expect(ChineseScript.detect(traditional) == .traditional)
        #expect(ChineseScript.simplified.convertKeepingOffsets(traditional) == text)
    }

    @Test func buddhistWordsKeepTheirTraditionalForms() {
        let text = "尔时佛住王舍城。舍利弗白佛言。云何布施。佛陀耶舍译。舍卫国祇树给孤独园精舍。舍身喜舍。"
        #expect(ChineseScript.traditional.convertKeepingOffsets(text)
                == "爾時佛住王舍城。舍利弗白佛言。云何布施。佛陀耶舍譯。舍衛國祇樹給孤獨園精舍。捨身喜捨。")
    }
}
