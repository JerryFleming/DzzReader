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
}
