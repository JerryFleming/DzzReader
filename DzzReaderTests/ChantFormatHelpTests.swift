import Foundation
import Testing
import DzzCore
@testable import DzzReader

@MainActor struct ChantFormatHelpTests {
    /// The sample viewer reprints the bundled file one item per line; it must still be the same text.
    @Test func compactSampleParsesToSameDocument() throws {
        let url = try #require(ChantFormatHelp.sampleURL)
        let original = try ChantDocument.parse(Data(contentsOf: url))
        let compact = ChantSampleView.compact(url)
        #expect(try ChantDocument.parse(Data(compact.utf8)) == original)
        #expect(compact.hasPrefix("[\n  {\"type\": \"passage\", \"style\": \"title\"},\n  {\"char\": \"大\", \"pinyin\": \"dà\"},"))
    }
}
