import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// A quote written top-to-bottom, right-to-left on aged paper inside a torn-edge frame,
/// with the source in small type at the bottom left — the card from the lecture page.
struct QuoteCardView: View {
    let script: QuoteScript
    let fontSize: CGFloat
    var revealed: Int
    var underlineCursor: Int
    var sourceShown: Bool
    /// The card stretches to at least this width, like the full-width block on the web page:
    /// the quote stays at the right, the source at the bottom left.
    var minWidth: CGFloat = 0

    /// The quote column is a fixed 435pt tall, as on the web page; bigger type means fewer rows.
    static let columnHeight: CGFloat = 435
    static let fontRange: ClosedRange<Double> = 14...40
    static let frameThickness: CGFloat = 22
    /// Keeps the text inside the double rule and clear of the corner ornaments.
    static let paperPadding: CGFloat = 36

    static func rows(for fontSize: CGFloat) -> Int { max(4, Int(columnHeight / (fontSize * 1.2))) }

    /// The finished card: everything written, underlined and signed.
    static func finished(_ script: QuoteScript, fontSize: CGFloat, minWidth: CGFloat = 0) -> QuoteCardView {
        QuoteCardView(script: script, fontSize: fontSize, revealed: script.glyphs.count,
                      underlineCursor: script.glyphs.count, sourceShown: true, minWidth: minWidth)
    }

    private var cell: CGFloat { fontSize * 1.2 }          // 1em glyph + .2em letter spacing
    private var columnWidth: CGFloat { fontSize * 1.5 }   // line-height 150%
    private var rows: Int { Self.rows(for: fontSize) }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            source
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.trailing, 24)
            Spacer(minLength: 0)
            // HStack runs left to right; the quote starts in the rightmost column.
            ForEach(script.columns(rows: rows).reversed(), id: \.lowerBound) { range in
                VStack(spacing: 0) {
                    ForEach(range, id: \.self) { glyphCell($0) }
                }
            }
        }
        .frame(height: CGFloat(rows) * cell, alignment: .top)
        .frame(minWidth: max(0, minWidth - 2 * (Self.paperPadding + Self.frameThickness)))
        .shadow(color: .black.opacity(0.35), radius: 1, x: 1, y: 1)
        .foregroundStyle(RetroPalette.ink)
        .padding(Self.paperPadding)
        .background { RetroPaper() }
        .padding(Self.frameThickness)
        .background { WoodFrame(thickness: Self.frameThickness) }
        .compositingGroup()
        .shadow(color: .black.opacity(0.9), radius: 3, x: 3, y: 3)
        .environment(\.colorScheme, .light)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("quoteCard")
        .accessibilityLabel(script.source + "：" + String(script.glyphs.map(\.character)))
        .accessibilityValue(stateDescription)
    }

    private func glyphCell(_ index: Int) -> some View {
        let glyph = script.glyphs[index]
        let underlined = glyph.highlighted && index < underlineCursor
        return Text(String(glyph.character))
            .font(.system(size: fontSize))
            .frame(width: columnWidth, height: cell)
            .overlay(alignment: .topLeading) {
                if let mark = glyph.punctuation {
                    // Small, in the gap just below and to the right of the character.
                    Text(String(Self.verticalForm(of: mark)))
                        .font(.system(size: fontSize * 0.6))
                        .frame(width: fontSize * 0.6, height: fontSize * 0.6)
                        .offset(x: fontSize * 0.8, y: fontSize * 1.0)
                }
            }
            .overlay(alignment: .leading) {
                if underlined {
                    Rectangle()
                        .fill(RetroPalette.cinnabar)
                        .frame(width: 2)
                        .shadow(color: .black.opacity(0.7), radius: 1, x: 1, y: 1)
                        .padding(.leading, fontSize * 0.25 - 4)
                }
            }
            .opacity(index < revealed ? 1 : 0)
    }

    private var source: some View {
        let size = (fontSize * 0.66).rounded(.down)
        let chars = Array("﹃" + script.source + "﹄")
        let perColumn = max(1, Int(CGFloat(rows) * cell / (size * 1.15)))
        let columns = stride(from: 0, to: chars.count, by: perColumn).map { chars[$0..<min($0 + perColumn, chars.count)] }
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(columns.indices.reversed(), id: \.self) { c in
                VStack(spacing: 0) {
                    ForEach(columns[c].indices, id: \.self) { i in
                        Text(String(columns[c][i]))
                            .font(.system(size: size))
                            .frame(width: size * 1.3, height: size * 1.15)
                    }
                }
            }
        }
        .opacity(sourceShown ? 1 : 0)
    }

    private var stateDescription: String {
        let underlined = script.glyphs.prefix(min(underlineCursor, script.glyphs.count)).filter(\.highlighted).count
        return "写出\(revealed)/\(script.glyphs.count) 标线\(underlined)/\(script.highlightCount) 出处\(sourceShown ? "显示" : "隐藏") 字号\(Int(fontSize))"
    }

    /// Presentation forms that sit in the upper right of the em box, as vertical text expects.
    static func verticalForm(of mark: Character) -> Character {
        switch mark {
        case "。": "︒"
        case "，": "︐"
        case "、": "︑"
        case "；": "︔"
        case "：": "︓"
        case "？": "︖"
        case "！": "︕"
        default: mark
        }
    }
}

/// The finished card as a PNG for the share sheet; rendered only when something asks for it.
struct QuoteCardImage: Transferable {
    let markup: String
    let fontSize: Double
    var minWidth: Double = 0

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { card in
            guard let data = await card.pngData() else { throw CocoaError(.fileWriteUnknown) }
            return data
        }
        .suggestedFileName { QuoteScript($0.markup).source + ".png" }
    }

    @MainActor func pngData() -> Data? {
        let card = QuoteCardView.finished(QuoteScript(markup), fontSize: fontSize, minWidth: minWidth)
            .padding(12)   // room for the drop shadow
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.isOpaque = false
        guard let image = renderer.uiImage else { return nil }
        // ImageRenderer draws in extended range, which makes a 16-bit PNG; many apps that receive it drop its
        // alpha and show the margin around the card as black. Redraw into a plain 8-bit sRGB canvas with alpha.
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: image.size, format: format).pngData { _ in
            image.draw(at: .zero)
        }
    }
}
