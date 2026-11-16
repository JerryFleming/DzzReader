import SwiftUI
import UIKit
import DzzCore

/// Turns a RenderedChapter into the attributed string shown by the text view.
@MainActor
enum AttributedChapterBuilder {
    static let nextChapterURL = URL(string: "dzzreader://next")!

    static func footerText(for nextChapterTitle: String?) -> String {
        if let nextChapterTitle { return "\n\n→ 下一卷　\(nextChapterTitle)" }
        return "\n\n全书完"
    }

    static func footerLength(for nextChapterTitle: String?) -> Int {
        (footerText(for: nextChapterTitle) as NSString).length
    }

    static func font(named family: String, size: CGFloat, bold: Bool = false) -> UIFont {
        var base: UIFont
        if !family.isEmpty, let named = UIFont(name: family, size: size) {
            base = named
        } else {
            base = .systemFont(ofSize: size)
        }
        if bold, let descriptor = base.fontDescriptor.withSymbolicTraits(.traitBold) {
            base = UIFont(descriptor: descriptor, size: size)
        } else if bold {
            base = .boldSystemFont(ofSize: size)
        }
        return base
    }

    static func build(rendered: RenderedChapter, settings: ReaderSettings, theme: Theme, scheme: ColorScheme,
                      nextChapterTitle: String?) -> NSAttributedString {
        let size = CGFloat(settings.fontSize)
        let foreground = theme.foreground(for: scheme)

        let bodyStyle = NSMutableParagraphStyle()
        bodyStyle.lineSpacing = (settings.lineSpacing - 1) * size
        bodyStyle.paragraphSpacing = 0.6 * size
        bodyStyle.lineBreakMode = .byWordWrapping

        let body = NSMutableAttributedString(string: rendered.text, attributes: [
            .font: font(named: settings.fontName, size: size),
            .foregroundColor: foreground,
            .paragraphStyle: bodyStyle,
        ])

        for span in rendered.spans where NSMaxRange(span.range) <= body.length {
            switch span.kind {
            case .chapterHeading:
                let style = NSMutableParagraphStyle()
                style.setParagraphStyle(bodyStyle)
                style.alignment = .center
                style.paragraphSpacing = 1.4 * size
                style.paragraphSpacingBefore = 0.6 * size
                body.addAttributes([
                    .font: font(named: settings.fontName, size: (size * 1.2).rounded(), bold: true),
                    .paragraphStyle: style,
                ], range: span.range)
            case .sectionHeading:
                let style = NSMutableParagraphStyle()
                style.setParagraphStyle(bodyStyle)
                style.paragraphSpacingBefore = 0.8 * size
                body.addAttributes([
                    .font: font(named: settings.fontName, size: (size * 1.1).rounded(), bold: true),
                    .paragraphStyle: style,
                ], range: span.range)
            }
        }

        collapseEmptyLines(in: body)

        let footerStyle = NSMutableParagraphStyle()
        footerStyle.alignment = .center
        footerStyle.paragraphSpacingBefore = 1.5 * size
        var footerAttributes: [NSAttributedString.Key: Any] = [
            .font: font(named: settings.fontName, size: size),
            .foregroundColor: theme.secondary(for: scheme),
            .paragraphStyle: footerStyle,
        ]
        if nextChapterTitle != nil {
            footerAttributes[.link] = nextChapterURL
        }
        body.append(NSAttributedString(string: footerText(for: nextChapterTitle), attributes: footerAttributes))
        return body
    }

    /// Height of an empty (or whitespace-only) source line once collapsed.
    static let emptyLineHeight: CGFloat = 1

    /// Every paragraph already gets `paragraphSpacing` after it, so a blank source line would otherwise add a
    /// full line plus a second spacing. Shrink blank lines to a hairline instead of removing them, so rendered
    /// offsets (bookmarks, progress) still match the source.
    private static func collapseEmptyLines(in text: NSMutableAttributedString) {
        let ns = text.string as NSString
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = emptyLineHeight
        style.maximumLineHeight = emptyLineHeight
        let font = UIFont.systemFont(ofSize: emptyLineHeight)
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs]) { sub, _, enclosing, _ in
            guard let sub, sub.trimmingCharacters(in: .whitespaces).isEmpty, enclosing.length > 0 else { return }
            text.addAttributes([.font: font, .paragraphStyle: style], range: enclosing)
        }
    }
}
