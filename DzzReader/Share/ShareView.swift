import SwiftUI

/// 分享: compose a vertical quote card, play it as a writing animation, share it as a picture.
/// A port of the lecture page (lecture/index.html).
struct ShareView: View {
    @AppStorage("share.quote") private var markup = QuoteScript.sample
    @AppStorage("share.fontSize") private var fontSize = 24.0
    @State private var animator = QuoteAnimator(tick: ShareView.tick, sounds: .shared)
    @FocusState private var editing: Bool
    @State private var contentWidth: CGFloat = 0

    /// Milliseconds per character; UI tests shorten it with `-shareTickMs`.
    private static var tick: Duration {
        let ms = UserDefaults.standard.integer(forKey: "shareTickMs")
        return .milliseconds(ms > 0 ? ms : 200)
    }

    private var script: QuoteScript { QuoteScript(markup) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    controls
                    card
                    editor
                }
                .padding(16)
                .onGeometryChange(for: CGFloat.self) { $0.size.width - 32 } action: { contentWidth = $0 }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("分享")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { editing = false }
                }
            }
        }
        .onAppear { animator.showFinished(script) }
        .onDisappear { animator.showFinished(script) }   // also silences the sounds
        .onChange(of: markup) { animator.showFinished(script) }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            // Symbols as labels; VoiceOver (and the UI tests) still read the Chinese names.
            Button("▶\u{FE0E}") { editing = false; animator.start(script) }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("开始")
            Button("✎\u{FE0E}") { editing = false; animator.underline(script) }
                .buttonStyle(.bordered)
                .accessibilityLabel("标线")
                .disabled(script.highlightCount == 0)
            Spacer(minLength: 0)
            Button("A-") { fontSize = max(QuoteCardView.fontRange.lowerBound, fontSize - 1) }
                .buttonStyle(.bordered)
                .accessibilityLabel("缩小字号")
            Button("A+") { fontSize = min(QuoteCardView.fontRange.upperBound, fontSize + 1) }
                .buttonStyle(.bordered)
                .accessibilityLabel("放大字号")
            ShareLink(item: QuoteCardImage(markup: markup, fontSize: fontSize, minWidth: cardWidth),
                      preview: SharePreview(script.source, image: Image("QuotePaper"))) {
                Text("⇪\u{FE0E}")
            }
            .accessibilityLabel("图片")
            .buttonStyle(.bordered)
            .disabled(script.glyphs.isEmpty)
        }
        // Editing the text: centred on the row, in the gap between playback and the card's size and sharing.
        .overlay {
            HStack(spacing: 8) {
                Button("↺\u{FE0E}") { markup = QuoteScript.sample }
                    .accessibilityLabel("恢复示例")
                Button("⌫\u{FE0E}", role: .destructive) { markup = "" }
                    .disabled(markup.isEmpty)
                    .accessibilityLabel("清空")
            }
            .buttonStyle(.bordered)
        }
        .tint(.green)
        .controlSize(.small)
    }

    @ViewBuilder private var card: some View {
        let view = QuoteCardView(script: script, fontSize: fontSize, revealed: animator.revealed,
                                 underlineCursor: animator.underlineCursor, sourceShown: animator.sourceShown, minWidth: cardWidth)
            .padding(.trailing, 6).padding(.bottom, 6)   // keep the drop shadow on screen
        // A long quote is wider than the screen: scroll it, starting from the first (rightmost) column.
        ViewThatFits(in: .horizontal) {
            view
            ScrollView(.horizontal) { view }
                .defaultScrollAnchor(.trailing)
        }
    }

    /// The card fills the row, less room for its drop shadow.
    private var cardWidth: CGFloat { max(0, contentWidth - 6) }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: $markup)
                .focused($editing)
                .frame(minHeight: 120)
                .padding(6)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.separator))
                .accessibilityIdentifier("quoteEditor")
            Text("格式：出处::正文。用 | 把要标线的句子括起来；没有出处时显示“\(QuoteScript.defaultSource)”。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
