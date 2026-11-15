import Foundation
import Testing
@testable import DzzCore

enum Fixtures {
    static func text(_ name: String) throws -> String {
        let url = Bundle.module.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")!
        return try String(contentsOf: url, encoding: .utf8)
    }
}

@Suite struct TocParserTests {
    let toc = TocParser.parse(try! Fixtures.text("toc-sample"))

    @Test func parsesSectionTable() {
        #expect(toc.sections.count == 31)
        #expect(toc.sections.first == TocSection(name: "阿含部", firstNumber: 1, lastNumber: 151))
        #expect(toc.sections.last == TocSection(name: "疑似部", firstNumber: 2865, lastNumber: 2920))
    }

    @Test func parsesFullEntry() {
        let e = toc.entries.first { $0.number == "0026" }
        #expect(e == TocEntry(number: "0026", title: "中阿含经", juanCount: 60, author: "东晋 瞿昙僧伽提婆译", note: nil))
    }

    @Test func parsesEntryWithSuffixAndNote() {
        let e = toc.entries.first { $0.number == "0128b" }
        #expect(e?.number == "0128b")
        #expect(e?.title == "须摩提女经")
        #expect(e?.note == "与上文略有不同")
        #expect(e?.author == "吴 支谦译")
    }

    @Test func parsesEntryWithoutAuthor() {
        let e = toc.entries.first { $0.number == "9999" }
        #expect(e?.author == nil)
        #expect(e?.juanCount == 1)
        #expect(e?.title == "测试经")
    }

    @Test func skipsSubEntries() {
        #expect(toc.entries.allSatisfy { !$0.number.contains("#") })
    }

    @Test func parsesRangeJuanCount() {
        #expect(toc.entries.first { $0.number == "0220a" }?.juanCount == 200)
        #expect(toc.entries.first { $0.number == "0220b" }?.juanCount == 200)   // (第201-400卷)
        #expect(toc.entries.first { $0.number == "0216" }?.juanCount == 1)
    }

    @Test func skipsPreambleMissingAndSeparators() {
        #expect(toc.entries.allSatisfy { !$0.title.contains("卍") && !$0.title.contains("MISSING") })
        #expect(toc.entries.count == 10)
    }

    @Test func sectionLookup() {
        #expect(toc.section(forNumber: "0894a")?.name == "密教部")
        #expect(toc.section(forNumber: "0001")?.name == "阿含部")
        #expect(toc.section(forNumber: "9999") == nil)
    }
}

@Suite struct CanonNumberTests {
    @Test func parsesFilenames() {
        #expect(CanonNumber.parse(filename: "0894a苏悉地羯罗供养法.txt") == "0894a")
        #expect(CanonNumber.parse(filename: "0001长阿含经.txt") == "0001")
        #expect(CanonNumber.parse(filename: "toc.txt") == nil)
    }

    @Test func sortKeys() {
        #expect(CanonNumber.sortKey("0026") == 26000)
        #expect(CanonNumber.sortKey("0894a") == 894001)
        #expect(CanonNumber.sortKey("0894b") == 894002)
    }

    @Test func numericPart() {
        #expect(CanonNumber.numericPart("0894a") == 894)
    }
}
