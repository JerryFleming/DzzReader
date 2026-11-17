import Foundation
import Testing
@testable import DzzReader

struct QuoteScriptTests {
    @Test func splitsSourceAndText() {
        let script = QuoteScript("僧伽吒经::佛告药上")
        #expect(script.source == "僧伽吒经")
        #expect(String(script.glyphs.map(\.character)) == "佛告药上")
    }

    @Test func defaultsSourceWithoutSeparator() {
        #expect(QuoteScript("如是我闻").source == "佛语典故")
        #expect(QuoteScript("  ::如是我闻").source == "佛语典故")
    }

    @Test func barsMarkUnderlinedText() {
        let script = QuoteScript("经::甲|乙丙|丁｜戊｜")
        #expect(script.glyphs.map(\.highlighted) == [false, true, true, false, true])
        #expect(script.highlightCount == 3)
    }

    @Test func punctuationRidesOnThePreviousCharacter() {
        let script = QuoteScript("经::善男子。|初发意，|何")
        #expect(String(script.glyphs.map(\.character)) == "善男子初发意何")
        #expect(script.glyphs[2].punctuation == "。")
        #expect(script.glyphs[5].punctuation == "，")
        #expect(script.glyphs[5].highlighted)
        #expect(!script.glyphs[6].highlighted)
    }

    @Test func leadingOrDoubledPunctuationGetsItsOwnCell() {
        let script = QuoteScript("。甲。。")
        #expect(script.glyphs.map(\.character) == ["。", "甲", "。"])
        #expect(script.glyphs[1].punctuation == "。")
        #expect(!script.glyphs[0].highlighted)
    }

    @Test func ignoresWhitespace() {
        #expect(String(QuoteScript("经::甲 乙\n丙").glyphs.map(\.character)) == "甲乙丙")
    }

    @Test func columnsFillTopToBottom() {
        let script = QuoteScript("一二三四五六七")
        #expect(script.columns(rows: 3) == [0..<3, 3..<6, 6..<7])
        #expect(QuoteScript("").columns(rows: 3).isEmpty)
    }

    @Test func sampleMatchesTheLecturePage() {
        let script = QuoteScript(QuoteScript.sample)
        #expect(script.source == "僧伽吒经•月婆首那")
        let underlined = String(script.glyphs.filter(\.highlighted).map(\.character))
        #expect(underlined == "于其梦中多见怖畏")
    }

    @Test func rowsShrinkAsTypeGrows() {
        #expect(QuoteCardView.rows(for: 24) == 15)
        #expect(QuoteCardView.rows(for: 40) < QuoteCardView.rows(for: 24))
    }
}

@MainActor struct QuoteAnimatorTests {
    let script = QuoteScript("经::甲|乙丙|丁")

    private func waitIdle(_ animator: QuoteAnimator) async {
        for _ in 0..<500 where animator.phase != .idle { try? await Task.sleep(for: .milliseconds(2)) }
    }

    @Test func startWritesThenSignsThenUnderlines() async {
        let animator = QuoteAnimator(tick: .milliseconds(1))
        animator.start(script)
        #expect(animator.phase == .writing)
        #expect(animator.revealed == 0)
        #expect(!animator.sourceShown)
        await waitIdle(animator)
        #expect(animator.revealed == 4)
        #expect(animator.sourceShown)
        #expect(animator.underlineCursor == 4)
    }

    @Test func underlineKeepsTextAndRedrawsLines() async {
        let animator = QuoteAnimator(tick: .milliseconds(1))
        animator.underline(script)
        #expect(animator.revealed == 4)
        #expect(animator.sourceShown)
        #expect(animator.phase == .underlining)
        await waitIdle(animator)
        #expect(animator.underlineCursor == 4)
    }

    @Test func showFinishedInterruptsPlayback() async {
        let animator = QuoteAnimator(tick: .seconds(10))
        animator.start(script)
        animator.showFinished(script)
        #expect(animator.phase == .idle)
        #expect(animator.revealed == 4)
        try? await Task.sleep(for: .milliseconds(20))
        #expect(animator.revealed == 4)
    }
}
