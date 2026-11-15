import Foundation
import Testing
@testable import DzzCore

@Suite struct TextDecoderTests {
    static let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
        CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))

    @Test func decodesUTF8WithBOM() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append("佛".data(using: .utf8)!)
        #expect(TextDecoder.decode(data) == DecodedText(text: "佛", encodingName: "utf-8"))
    }

    @Test func decodesGB18030() {
        let text = "阿含经。如是我闻，一时佛在舍卫国。"
        let data = text.data(using: Self.gb18030)!
        #expect(TextDecoder.decode(data) == DecodedText(text: text, encodingName: "gb18030"))
    }

    @Test func decodesBig5() {
        let text = "佛說四十二章經。如是我聞，一時佛在舍衛國。"
        let data = text.data(using: TextDecoder.big5)!
        #expect(TextDecoder.decode(data) == DecodedText(text: text, encodingName: "big5"))
    }

    @Test func decodeNormalisesCRLF() {
        let data = "a\r\nb\rc".data(using: .utf8)!
        #expect(TextDecoder.decode(data)?.text == "a\nb\nc")
    }

    @Test func rejectsUndecodableBytes() {
        #expect(TextDecoder.decode(Data([0x80, 0x80, 0xFF, 0xFF])) == nil)
    }
}

@Suite struct ProgressMapperTests {
    let chapters = [
        ChapterRange(title: "一", startOffset: 0, endOffset: 100, sections: []),
        ChapterRange(title: "二", startOffset: 100, endOffset: 300, sections: []),
        ChapterRange(title: "三", startOffset: 300, endOffset: 400, sections: []),
    ]

    @Test func fractionRoundTrips() {
        #expect(ProgressMapper.fraction(chapterIndex: 1, offsetInChapter: 50, chapters: chapters) == 0.375)
        let located = ProgressMapper.locate(fraction: 0.375, chapters: chapters)
        #expect(located.chapterIndex == 1 && located.offsetInChapter == 50)
    }

    @Test func fractionOneLandsInLastChapter() {
        let located = ProgressMapper.locate(fraction: 1.0, chapters: chapters)
        #expect(located.chapterIndex == 2 && located.offsetInChapter == 100)
    }

    @Test func locateClampsOutOfRange() {
        let high = ProgressMapper.locate(fraction: 1.7, chapters: chapters)
        #expect(high.chapterIndex == 2 && high.offsetInChapter == 100)
        let low = ProgressMapper.locate(fraction: -1, chapters: chapters)
        #expect(low.chapterIndex == 0 && low.offsetInChapter == 0)
    }

    @Test func emptyBookIsComplete() {
        let empty = [ChapterRange(title: "空", startOffset: 0, endOffset: 0, sections: [])]
        #expect(ProgressMapper.fraction(chapterIndex: 0, offsetInChapter: 0, chapters: empty) == 1)
    }
}
