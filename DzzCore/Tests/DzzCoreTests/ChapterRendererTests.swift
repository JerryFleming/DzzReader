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
}
