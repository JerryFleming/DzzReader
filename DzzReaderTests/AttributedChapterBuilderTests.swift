import Foundation
import SwiftUI
import Testing
import UIKit
import DzzCore
@testable import DzzReader

@Suite @MainActor struct AttributedChapterBuilderTests {
    let settings = ReaderSettings(defaults: UserDefaults(suiteName: "AttributedChapterBuilderTests-\(UUID().uuidString)")!)

    private func rendered() -> RenderedChapter {
        let source = "第0章 　　甲卷第一\n　　乙\n第0章 　　丙品第一\n　　丁\n"
        let ns = source as NSString
        let sectionOffset = ns.range(of: "第0章 　　丙品第一").location
        let chapter = ChapterRange(title: "甲卷第一", startOffset: 0, endOffset: ns.length,
                                   sections: [Section(title: "丙品第一", offset: sectionOffset)])
        return ChapterRenderer.render(fullText: source, chapter: chapter, isFrontMatter: false)
    }

    @Test func stylesSpansAndFooterLink() {
        let r = rendered()
        let text = AttributedChapterBuilder.build(rendered: r, settings: settings, theme: .light, scheme: .light, nextChapterTitle: "卷第二")
        let ns = text.string as NSString
        #expect(text.string.hasSuffix("→ 下一卷　卷第二"))

        let footerStart = ns.length - AttributedChapterBuilder.footerLength(for: "卷第二")
        #expect(ns.substring(from: footerStart) == "\n\n→ 下一卷　卷第二")
        let linkRange = ns.range(of: "→ 下一卷　卷第二")
        #expect(text.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL == AttributedChapterBuilder.nextChapterURL)

        let heading = ns.range(of: "　　甲卷第一")
        let headingFont = text.attribute(.font, at: heading.location, effectiveRange: nil) as! UIFont
        #expect(Double(headingFont.pointSize) >= settings.fontSize * 1.2)
        #expect(headingFont.fontDescriptor.symbolicTraits.contains(.traitBold))
        let headingStyle = text.attribute(.paragraphStyle, at: heading.location, effectiveRange: nil) as! NSParagraphStyle
        #expect(headingStyle.alignment == .center)

        let section = ns.range(of: "　　丙品第一")
        let sectionFont = text.attribute(.font, at: section.location, effectiveRange: nil) as! UIFont
        #expect(Double(sectionFont.pointSize) >= settings.fontSize * 1.1)
        #expect(sectionFont.fontDescriptor.symbolicTraits.contains(.traitBold))

        let body = ns.range(of: "　　乙")
        let bodyFont = text.attribute(.font, at: body.location, effectiveRange: nil) as! UIFont
        #expect(Double(bodyFont.pointSize) == settings.fontSize)
        #expect(ns.substring(with: body) == "　　乙")   // full-width spaces survive
        let bodyStyle = text.attribute(.paragraphStyle, at: body.location, effectiveRange: nil) as! NSParagraphStyle
        #expect(bodyStyle.firstLineHeadIndent == 0)
        #expect(abs(Double(bodyStyle.lineSpacing) - (settings.lineSpacing - 1) * settings.fontSize) < 0.001)
    }

    @Test func lastChapterShowsEnd() {
        let text = AttributedChapterBuilder.build(rendered: rendered(), settings: settings, theme: .sepia, scheme: .light, nextChapterTitle: nil)
        #expect(text.string.hasSuffix("全书完"))
        var hasLink = false
        text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if value != nil { hasLink = true }
        }
        #expect(!hasLink)
        #expect(AttributedChapterBuilder.footerLength(for: nil) == ("\n\n全书完" as NSString).length)
    }

    @Test func themeColoursApply() {
        let text = AttributedChapterBuilder.build(rendered: rendered(), settings: settings, theme: .black, scheme: .light, nextChapterTitle: nil)
        let colour = text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as! UIColor
        #expect(colour == Theme.black.foreground(for: .light))
    }
}
