import Foundation
import Testing
@testable import DzzCore

@Suite struct ChapterRendererTests {
    let source = "第0章 　　甲卷第一\n　　如是我闻。\n第0章 　　乙品第一\n　　正文。\n"

    private func chapter(for text: String, sections: [Section] = []) -> ChapterRange {
        ChapterRange(title: "甲卷第一", startOffset: 0, endOffset: (text as NSString).length, sections: sections)
    }

    private func sectionOffset(_ text: String) -> Int {
        (text as NSString).range(of: "第0章 　　乙品第一").location
    }

    @Test func stripsPrefixesAndKeepsBodyVerbatim() {
        let r = ChapterRenderer.render(fullText: source, chapter: chapter(for: source), isFrontMatter: false)
        #expect(r.text == "　　甲卷第一\n　　如是我闻。\n　　乙品第一\n　　正文。\n")
    }

    @Test func spansMarkHeadingAndSection() {
        let sections = [Section(title: "乙品第一", offset: sectionOffset(source))]
        let r = ChapterRenderer.render(fullText: source, chapter: chapter(for: source, sections: sections), isFrontMatter: false)
        let ns = r.text as NSString
        #expect(r.spans.count == 2)
        #expect(r.spans[0].kind == .chapterHeading)
        #expect(ns.substring(with: r.spans[0].range) == "　　甲卷第一")
        #expect(r.spans[1].kind == .sectionHeading)
        #expect(ns.substring(with: r.spans[1].range) == "　　乙品第一")
    }

    @Test func offsetMapRoundTripsAcrossRemovedPrefixes() {
        let r = ChapterRenderer.render(fullText: source, chapter: chapter(for: source), isFrontMatter: false)
        let sourceLength = (source as NSString).length
        let renderedLength = (r.text as NSString).length
        let prefix = (("第0章 " as NSString).length)
        let secondPrefixStart = sectionOffset(source)
        for s in 0...sourceLength {
            let back = r.sourceOffset(forRendered: r.renderedOffset(forSource: s))
            let insideFirst = s < prefix
            let insideSecond = s >= secondPrefixStart && s < secondPrefixStart + prefix
            if insideFirst {
                #expect(back == prefix, "s=\(s)")                       // maps to the heading text after the prefix
            } else if insideSecond {
                #expect(back == secondPrefixStart + prefix, "s=\(s)")
            } else {
                #expect(back == s, "s=\(s)")
            }
        }
        #expect(r.renderedOffset(forSource: sourceLength) == renderedLength)
        #expect(r.sourceOffset(forRendered: renderedLength) == sourceLength)
        #expect(r.renderedOffset(forSource: 99_999) == renderedLength)
        #expect(r.sourceOffset(forRendered: -5) == prefix)   // clamped to rendered 0, which is the heading text
    }

    @Test func frontMatterHasNoChapterHeadingSpan() {
        let r = ChapterRenderer.render(fullText: source, chapter: chapter(for: source), isFrontMatter: true)
        #expect(r.spans.isEmpty)
    }

    @Test func noMarksIsIdentity() {
        let plain = "　　甲卷第一\n　　如是我闻。\n"
        let r = ChapterRenderer.render(fullText: plain, chapter: chapter(for: plain), isFrontMatter: false)
        #expect(r.text == plain)
        for s in 0...(plain as NSString).length {
            #expect(r.renderedOffset(forSource: s) == s)
            #expect(r.sourceOffset(forRendered: s) == s)
        }
    }

    @Test func rendersOnlyTheChapterSubstring() {
        let full = "前言\n" + source
        let start = ("前言\n" as NSString).length
        let ch = ChapterRange(title: "甲卷第一", startOffset: start, endOffset: (full as NSString).length, sections: [])
        let r = ChapterRenderer.render(fullText: full, chapter: ch, isFrontMatter: false)
        #expect(r.text == "　　甲卷第一\n　　如是我闻。\n　　乙品第一\n　　正文。\n")
        #expect(r.sourceOffset(forRendered: 0) == ("第0章 " as NSString).length)   // chapter-relative, past the prefix
    }

    // MARK: Several chapters in one document

    /// 卷首 front matter, two 卷, and a continuation part of the second 卷.
    private let book = "大正藏 No. 0001 某经\n\n第0章 　　某经卷第一\n　　甲。\n第0章 　　某经卷第二\n　　乙。\n　　丙。\n"

    private func bookChapters() -> [ChapterRange] {
        let ns = book as NSString
        let first = ns.range(of: "第0章 　　某经卷第一").location
        let second = ns.range(of: "第0章 　　某经卷第二").location
        let part = ns.range(of: "　　丙。").location
        return [
            ChapterRange(title: "卷首", startOffset: 0, endOffset: first, sections: []),
            ChapterRange(title: "某经卷第一", startOffset: first, endOffset: second, sections: []),
            ChapterRange(title: "某经卷第二（1/2）", startOffset: second, endOffset: part, sections: []),
            ChapterRange(title: "某经卷第二（2/2）", startOffset: part, endOffset: ns.length, sections: []),
        ]
    }

    @Test func wholeBookHasOneHeadingPerChapterButNoneForFrontMatterOrContinuations() {
        let r = ChapterRenderer.render(fullText: book, chapters: bookChapters(), span: 0..<4, hasFrontMatter: true)
        let ns = r.text as NSString
        #expect(r.text == "大正藏 No. 0001 某经\n\n　　某经卷第一\n　　甲。\n　　某经卷第二\n　　乙。\n　　丙。\n")
        #expect(r.spans.map(\.kind) == [.chapterHeading, .chapterHeading])
        #expect(r.spans.map { ns.substring(with: $0.range) } == ["　　某经卷第一", "　　某经卷第二"])
    }

    @Test func wholeBookChapterStartsAreRenderedOffsets() {
        let chapters = bookChapters()
        let r = ChapterRenderer.render(fullText: book, chapters: chapters, span: 0..<4, hasFrontMatter: true)
        let ns = r.text as NSString
        #expect(r.chapterStarts.count == 4)
        #expect(r.chapterStarts[0] == 0)
        #expect(ns.substring(from: r.chapterStarts[1]).hasPrefix("　　某经卷第一"))
        #expect(ns.substring(from: r.chapterStarts[2]).hasPrefix("　　某经卷第二"))
        #expect(ns.substring(from: r.chapterStarts[3]).hasPrefix("　　丙。"))
        // Source offsets are relative to the first chapter of the span, i.e. absolute here.
        for (i, c) in chapters.enumerated() {
            let back = r.sourceOffset(forRendered: r.chapterStarts[i])
            #expect(back >= c.startOffset && back < c.endOffset, "chapter \(i)")
        }
    }

    @Test func spanStartingMidBookIsRelativeToItsFirstChapter() {
        let r = ChapterRenderer.render(fullText: book, chapters: bookChapters(), span: 3..<4, hasFrontMatter: true)
        #expect(r.text == "　　丙。\n")
        #expect(r.chapterStarts == [0])
        // A lone chapter always gets its heading, even a continuation part (unchanged behaviour).
        #expect(r.spans.map(\.kind) == [.chapterHeading])
        #expect(r.sourceOffset(forRendered: 0) == 0)
    }

    @Test func chapterIndexLookupOverStarts() {
        let starts = [0, 10, 25, 40]
        #expect(ChapterRenderer.chapterIndex(forRendered: 0, starts: starts) == 0)
        #expect(ChapterRenderer.chapterIndex(forRendered: 9, starts: starts) == 0)
        #expect(ChapterRenderer.chapterIndex(forRendered: 10, starts: starts) == 1)
        #expect(ChapterRenderer.chapterIndex(forRendered: 39, starts: starts) == 2)
        #expect(ChapterRenderer.chapterIndex(forRendered: 9_999, starts: starts) == 3)
        #expect(ChapterRenderer.chapterIndex(forRendered: -1, starts: starts) == 0)
    }
}
