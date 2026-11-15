import Foundation
import Testing
@testable import DzzCore

@Suite struct ChapterIndexerTests {
    let marked = try! Fixtures.text("marked-3juan")
    let unmarked = try! Fixtures.text("unmarked-2juan")
    let single = try! Fixtures.text("single")
    let pinOnly = try! Fixtures.text("pin-only")

    private func utf16Length(_ s: String) -> Int { (s as NSString).length }

    private func checkContiguous(_ chapters: [ChapterRange], text: String) {
        #expect(!chapters.isEmpty)
        #expect(chapters.first?.startOffset == 0)
        #expect(chapters.last?.endOffset == utf16Length(text))
        for (a, b) in zip(chapters, chapters.dropFirst()) {
            #expect(a.endOffset == b.startOffset)
        }
        for c in chapters {
            for s in c.sections {
                #expect(s.offset >= c.startOffset && s.offset < c.endOffset)
            }
        }
    }

    @Test func markedFileYieldsOneChapterPerJuanPlusFrontMatter() {
        let chapters = ChapterIndexer.index(text: marked, bookTitle: "长阿含经")
        #expect(chapters.map(\.title) == ["卷首", "佛说长阿含经卷第一", "佛说长阿含经卷第二", "佛说长阿含经卷第三"])
    }

    @Test func pinMarksBecomeSectionsOfTheirChapter() {
        let chapters = ChapterIndexer.index(text: marked, bookTitle: "长阿含经")
        #expect(chapters.count == 4)
        #expect(chapters[2].sections.map(\.title) == ["阎浮提州品第一", "佛说长阿含第四分世记经郁单曰品第二"])
        #expect(chapters[1].sections.isEmpty)
        #expect(chapters[3].sections.isEmpty)
        for s in chapters[2].sections {
            #expect(s.offset > chapters[2].startOffset && s.offset < chapters[2].endOffset)
        }
    }

    @Test func rangesAreContiguousAndCoverText() {
        for text in [marked, unmarked, single, pinOnly] {
            checkContiguous(ChapterIndexer.index(text: text, bookTitle: "书"), text: text)
        }
    }

    @Test func collapsesPairsIgnoringWhitespaceAndParentheticals() {
        let text = """
        大正藏 No. 0026 中阿含经
        　　东晋 瞿昙僧伽提婆译

        　　60卷

        第0章 　　中阿含经卷第一
        　　如是我闻。一时佛游舍卫国。在胜林给孤独园。
        　　尔时世尊告诸比丘。若有比丘正身正愿。
        第0章 　　中阿含经卷第一(八千一百九字)(初一日诵)

        """
        let chapters = ChapterIndexer.index(text: text, bookTitle: "中阿含经")
        #expect(chapters.map(\.title) == ["中阿含经卷第一"])
    }

    @Test func longMarkIsNotAHeading() {
        let body = String(repeating: "昔有一国王深识罪福信有果报。", count: 5)   // 70 chars
        let text = """
        No. 0207 杂譬喻经

        第0章 　　杂譬喻经卷第一
        \(String(repeating: "　　正文。", count: 40))
        第0章 　　\(body)
        \(String(repeating: "　　正文。", count: 40))
        第0章 　　杂譬喻经卷第一
        第0章 　　杂譬喻经卷第二
        \(String(repeating: "　　正文。", count: 40))
        第0章 　　杂譬喻经卷第二

        """
        let chapters = ChapterIndexer.index(text: text, bookTitle: "杂譬喻经")
        #expect(chapters.map(\.title) == ["杂譬喻经卷第一", "杂譬喻经卷第二"])
        #expect(chapters.allSatisfy { $0.sections.isEmpty })
    }

    @Test func unmarkedMultiJuanUsesJuanHeadings() {
        let chapters = ChapterIndexer.index(text: unmarked, bookTitle: "禅法要解")
        #expect(chapters.map(\.title) == ["禅法要解卷上", "禅法要解卷下"])
    }

    @Test func singleJuanIsOneChapterTitledByBook() {
        let chapters = ChapterIndexer.index(text: single, bookTitle: "帝释所问经")
        #expect(chapters == [ChapterRange(title: "帝释所问经", startOffset: 0, endOffset: utf16Length(single), sections: [])])
    }

    @Test func pinOnlyFileIsOneChapterWithSections() {
        let chapters = ChapterIndexer.index(text: pinOnly, bookTitle: "金刚三昧经")
        #expect(chapters.count == 1)
        #expect(chapters[0].title == "金刚三昧经")
        #expect(chapters[0].sections.count == 8)
        #expect(chapters[0].sections.first?.title == "金刚三昧经序品第一")
    }

    @Test func frontMatterOnlyWhenContentBeyondHeader() {
        let withJuanLine = """
        大正藏 No. 0002 七佛经
        　　宋 法天译

        　　2卷

        第0章 　　七佛经卷第一
        \(String(repeating: "　　正文。", count: 50))
        第0章 　　七佛经卷第一
        第0章 　　七佛经卷第二
        \(String(repeating: "　　正文。", count: 50))
        第0章 　　七佛经卷第二

        """
        #expect(ChapterIndexer.index(text: withJuanLine, bookTitle: "七佛经").first?.title == "七佛经卷第一")

        let noJuanLine = """
        No. 2185 法华义疏
        　　日本 圣德太子撰

        第0章 　　法华义疏卷第一
        \(String(repeating: "　　正文。", count: 50))
        第0章 　　法华义疏卷第一
        第0章 　　法华义疏卷第二
        \(String(repeating: "　　正文。", count: 50))
        第0章 　　法华义疏卷第二

        """
        #expect(ChapterIndexer.index(text: noJuanLine, bookTitle: "法华义疏").first?.title == "法华义疏卷第一")
    }

    @Test func shortFalsePositiveIsMerged() {
        let text = """
        No. 1 甲经

        第0章 　　甲经卷第一
        　　短。
        第0章 　　甲经卷第二
        \(String(repeating: "　　正文。", count: 100))
        第0章 　　甲经卷第二

        """
        let chapters = ChapterIndexer.index(text: text, bookTitle: "甲经")
        #expect(chapters.map(\.title) == ["甲经卷第二"])
        #expect(chapters.first?.startOffset == 0)
    }

    @Test func oversizedChapterIsSplitAtBlankLines() {
        var text = "No. 1 乙经\n\n第0章 　　乙经卷第一\n"
        let paragraph = String(repeating: "正", count: 998) + "\n\n"   // 1,000 units per paragraph incl. blank line
        var body = ""
        for _ in 0..<250 { body += paragraph }
        // place a 品 heading at roughly unit 150,000 of the body
        let ns = body as NSString
        let insertAt = ns.range(of: "\n\n", options: [], range: NSRange(location: 150_000, length: ns.length - 150_000)).location + 2
        body = ns.replacingCharacters(in: NSRange(location: insertAt, length: 0), with: "第0章 　　乙品第一\n")
        text += body
        let chapters = ChapterIndexer.index(text: text, bookTitle: "乙经")
        #expect(chapters.map(\.title) == ["乙经卷第一（1/3）", "乙经卷第一（2/3）", "乙经卷第一（3/3）"])
        checkContiguous(chapters, text: text)
        let full = text as NSString
        for c in chapters.dropFirst() {
            #expect(full.substring(with: NSRange(location: c.startOffset - 2, length: 2)) == "\n\n")
        }
        #expect(chapters.allSatisfy { $0.endOffset - $0.startOffset <= ChapterIndexer.oversizeLimit })
        #expect(chapters[1].sections.map(\.title) == ["乙品第一"])
        #expect(chapters[0].sections.isEmpty && chapters[2].sections.isEmpty)
    }

    @Test func emptyTextYieldsSingleEmptyChapter() {
        #expect(ChapterIndexer.index(text: "", bookTitle: "空") == [ChapterRange(title: "空", startOffset: 0, endOffset: 0, sections: [])])
    }

    @Test func normaliseAndKey() {
        #expect(ChapterIndexer.normalise("第0章 　　　　佛说长阿含经卷第一") == "佛说长阿含经卷第一")
        #expect(ChapterIndexer.comparisonKey("中阿含经卷第一(八千一百九字)(初一日诵)") == "中阿含经卷第一")
        #expect(ChapterIndexer.isJuanHeading(key: "阎浮提州品第一") == false)
        #expect(ChapterIndexer.isJuanHeading(key: "佛说长阿含经卷第一") == true)
        #expect(ChapterIndexer.isJuanHeading(key: "禅法要解卷上") == true)
    }
}
